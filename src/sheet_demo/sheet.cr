# Sheet storage, CSV import/export, demo workbook and undo snapshots.
require "./formula"

module SheetDemo
  struct SheetSnapshot
    getter rows : Int32
    getter cols : Int32
    getter data : Array(Array(String))

    def initialize(@rows : Int32, @cols : Int32, data : Array(Array(String)))
      @data = data.map(&.dup)
    end
  end

  class Sheet
    include Formula::SheetLike

    MIN_ROWS = 200
    MIN_COLS =  26

    getter row_count : Int32
    getter col_count : Int32
    getter revision : Int32

    @raw : Array(Array(String))
    @evaluator : Formula::Evaluator

    def initialize(@row_count : Int32 = MIN_ROWS, @col_count : Int32 = MIN_COLS)
      @raw = Array.new(@row_count) { Array.new(@col_count, "") }
      @revision = 0
      # Crystal does not treat an assignment whose argument is `self` as
      # initializing the ivar in `initialize`; uninitialized is a workaround.
      @evaluator = uninitialized Formula::Evaluator
      @evaluator = Formula::Evaluator.new(self)
      raise ArgumentError.new("row_count must be positive") if @row_count <= 0
      raise ArgumentError.new("col_count must be positive") if @col_count <= 0
    end

    def self.empty : Sheet
      new
    end

    def raw(row : Int32, col : Int32) : String
      return "" unless in_bounds?(row, col)
      @raw[row][col]
    end

    def value(row : Int32, col : Int32) : CellValue
      return CellValue.error(CellError::Ref) unless in_bounds?(row, col)
      @evaluator.cell_value(row, col)
    end

    def set_raw(row : Int32, col : Int32, raw : String) : Bool
      return false unless in_bounds?(row, col)
      return false if @raw[row][col] == raw
      @raw[row][col] = raw
      changed!
      true
    end

    def clear_cell(row : Int32, col : Int32) : Bool
      set_raw(row, col, "")
    end

    def clear_range(row0 : Int32, row1 : Int32, col0 : Int32, col1 : Int32) : Bool
      r0, r1, c0, c1 = normalize_range(row0, row1, col0, col1)
      changed = false
      row = r0
      while row <= r1
        col = c0
        while col <= c1
          if !@raw[row][col].empty?
            @raw[row][col] = ""
            changed = true
          end
          col += 1
        end
        row += 1
      end
      changed!
      changed
    end

    def insert_row(at : Int32) : Bool
      return false unless at >= 0 && at <= @row_count
      @raw.insert(at, Array.new(@col_count, ""))
      @row_count += 1
      changed!
      true
    end

    def delete_row(at : Int32) : Bool
      return false unless in_row_bounds?(at)
      if @row_count <= 1
        @raw[0].fill("")
      else
        @raw.delete_at(at)
        @row_count -= 1
      end
      changed!
      true
    end

    def insert_col(at : Int32) : Bool
      return false unless at >= 0 && at <= @col_count
      @raw.each { |row| row.insert(at, "") }
      @col_count += 1
      changed!
      true
    end

    def delete_col(at : Int32) : Bool
      return false unless in_col_bounds?(at)
      if @col_count <= 1
        @raw.each { |row| row[0] = "" }
      else
        @raw.each { |row| row.delete_at(at) }
        @col_count -= 1
      end
      changed!
      true
    end

    def replace_with(other : Sheet) : Nil
      @row_count = other.row_count
      @col_count = other.col_count
      @raw = other.snapshot.data
      changed!
    end

    def snapshot : SheetSnapshot
      SheetSnapshot.new(@row_count, @col_count, @raw)
    end

    def restore(snapshot : SheetSnapshot) : Nil
      @row_count = snapshot.rows
      @col_count = snapshot.cols
      @raw = snapshot.data.map(&.dup)
      changed!
    end

    def load_records(records : Array(Array(String))) : Nil
      rows = Math.max(records.size, 1)
      cols = 1
      records.each { |record| cols = Math.max(cols, record.size) }
      if rows > @row_count || cols > @col_count
        @row_count = Math.max(rows, @row_count)
        @col_count = Math.max(cols, @col_count)
        @raw = Array.new(@row_count) { Array.new(@col_count, "") }
      else
        @raw.each { |row| row.fill("") }
      end
      records.each_with_index do |record, r|
        record.each_with_index do |text, c|
          @raw[r][c] = text if in_bounds?(r, c)
        end
      end
      changed!
    end

    def self.from_csv(text : String) : Sheet
      records = parse_csv(text)
      rows = Math.max(MIN_ROWS, records.size)
      cols = MIN_COLS
      records.each { |record| cols = Math.max(cols, record.size) }
      sheet = new(rows, cols)
      sheet.load_records(records)
      sheet
    end

    def to_csv : String
      last_row, last_col = used_bounds
      return "" if last_row < 0 || last_col < 0
      builder = String::Builder.new
      row = 0
      while row <= last_row
        col = 0
        while col <= last_col
          builder << csv_escape(@raw[row][col])
          builder << ',' if col < last_col
          col += 1
        end
        builder << '\n'
        row += 1
      end
      builder.to_s
    end

    def used_bounds : {Int32, Int32}
      last_row = -1
      last_col = -1
      @raw.each_with_index do |row, r|
        row.each_with_index do |raw, c|
          next if raw.empty?
          last_row = r if r > last_row
          last_col = c if c > last_col
        end
      end
      {last_row, last_col}
    end

    def self.parse_csv(text : String) : Array(Array(String))
      return [] of Array(String) if text.empty?
      rows = [] of Array(String)
      row = [] of String
      field = String::Builder.new
      in_quotes = false
      chars = text.chars
      i = 0
      while i < chars.size
        char = chars[i]
        if in_quotes
          if char == '"'
            if i + 1 < chars.size && chars[i + 1] == '"'
              field << '"'
              i += 2
            else
              in_quotes = false
              i += 1
            end
          else
            field << char
            i += 1
          end
        else
          case char
          when '"'
            in_quotes = true
            i += 1
          when ','
            row << field.to_s
            field = String::Builder.new
            i += 1
          when '\n'
            row << field.to_s
            rows << row
            row = [] of String
            field = String::Builder.new
            i += 1
          when '\r'
            i += 1
          else
            field << char
            i += 1
          end
        end
      end
      row << field.to_s
      rows << row unless row.size == 1 && row[0].empty?
      rows
    end

    def self.demo : Sheet
      sheet = new(200, 26)
      rows = [
        ["Tessell Quarterly Budget", "", "", "", "", "", ""],
        ["", "", "", "", "", "", ""],
        ["Category", "Q1", "Q2", "Q3", "Q4", "Total", "Share"],
        ["Revenue", "120000", "135000", "128000", "150000", "=SUM(B4:E4)", "=ROUND(F4/$F$4*100, 1) & \"%\""],
        ["COGS", "62000", "68000", "65000", "72000", "=SUM(B5:E5)", "=ROUND(F5/$F$4*100, 1) & \"%\""],
        ["Gross Profit", "=B4-B5", "=C4-C5", "=D4-D5", "=E4-E5", "=SUM(B6:E6)", "=ROUND(F6/$F$4*100, 1) & \"%\""],
        ["Operating", "28000", "30000", "31000", "33000", "=SUM(B7:E7)", "=ROUND(F7/$F$4*100, 1) & \"%\""],
        ["Net Income", "=B6-B7", "=C6-C7", "=D6-D7", "=E6-E7", "=SUM(B8:E8)", "=ROUND(F8/$F$4*100, 1) & \"%\""],
        ["", "", "", "", "", "", ""],
        ["Assumptions", "", "", "", "", "", ""],
        ["Tax rate", "0.21", "", "", "", "", ""],
        ["Headcount", "42", "", "", "", "", ""],
        ["Revenue / head", "=ROUND(B4/B12, 2)", "", "", "", "", ""],
        ["", "", "", "", "", "", ""],
        ["Checks", "", "", "", "", "", ""],
        ["Gross margin", "=F6/F4", "", "", "", "", ""],
        ["Net margin", "=F8/F4", "", "", "", "", ""],
        ["Average Q revenue", "=AVERAGE(B4:E4)", "", "", "", "", ""],
        ["Max quarter", "=MAX(B4:E4)", "", "", "", "", ""],
        ["Forecast next", "=ROUND(F4*1.08,0)", "", "", "", "", ""],
        ["", "", "", "", "", "", ""],
        ["Top products", "Units", "Price", "Revenue", "", "", ""],
        ["Atlas", "1200", "49.5", "=B23*C23", "", "", ""],
        ["Canvas", "860", "79", "=B24*C24", "", "", ""],
        ["Runner", "540", "129", "=B25*C25", "", "", ""],
        ["Total", "", "", "=SUM(D23:D25)", "", "", ""],
      ]
      sheet.load_records(rows)
      sheet
    end

    private def changed! : Nil
      @revision &+= 1
      @evaluator.reset_cache
    end

    private def normalize_range(row0 : Int32, row1 : Int32, col0 : Int32, col1 : Int32) : {Int32, Int32, Int32, Int32}
      r0 = Math.min(row0, row1).clamp(0, @row_count - 1)
      r1 = Math.max(row0, row1).clamp(0, @row_count - 1)
      c0 = Math.min(col0, col1).clamp(0, @col_count - 1)
      c1 = Math.max(col0, col1).clamp(0, @col_count - 1)
      {r0, r1, c0, c1}
    end

    private def in_row_bounds?(row : Int32) : Bool
      row >= 0 && row < @row_count
    end

    private def in_col_bounds?(col : Int32) : Bool
      col >= 0 && col < @col_count
    end

    private def csv_escape(value : String) : String
      if value.includes?(',') || value.includes?('"') ||
         value.includes?('\n') || value.includes?('\r')
        "\"#{value.gsub("\"", "\"\"")}\""
      else
        value
      end
    end
  end
end
