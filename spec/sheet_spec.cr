require "./spec_helper"

private def sheet_with(rows : Array(Array(String))) : SheetDemo::Sheet
  sheet = SheetDemo::Sheet.new(50, 10)
  sheet.load_records(rows)
  sheet
end

private def number_at(sheet : SheetDemo::Sheet, row : Int32, col : Int32) : Float64
  value = sheet.value(row, col)
  value.number?.should be_true
  value.number
end

describe "SheetDemo::Sheet values" do
  it "evaluates arithmetic with precedence and parentheses" do
    sheet = sheet_with([
      ["1", "2", "=A1+B1*3", "=(A1+B1)*3", "=2^3^2", "=-A1"],
    ])
    number_at(sheet, 0, 2).should eq(7.0)
    number_at(sheet, 0, 3).should eq(9.0)
    number_at(sheet, 0, 4).should eq(512.0)
    number_at(sheet, 0, 5).should eq(-1.0)
  end

  it "evaluates percentages and concat" do
    sheet = sheet_with([["50", "=A1%", %(=A1 & "px")]])
    number_at(sheet, 0, 1).should eq(0.5)
    sheet.value(0, 2).display.should eq("50px")
  end

  it "evaluates aggregate functions over ranges" do
    sheet = sheet_with([
      ["1", "2", "3"],
      ["=SUM(A1:C1)", "=AVERAGE(A1:C1)", "=MIN(A1:C1)"],
      ["=MAX(A1:C1)", "=COUNT(A1:C1)", "=COUNTA(A1:C1)"],
      ["=SUM(A1:C1)*2", "=ROUND(3.14159, 2)", "=ABS(-7)"],
    ])
    number_at(sheet, 1, 0).should eq(6.0)
    number_at(sheet, 1, 1).should eq(2.0)
    number_at(sheet, 1, 2).should eq(1.0)
    number_at(sheet, 2, 0).should eq(3.0)
    number_at(sheet, 2, 1).should eq(3.0)
    number_at(sheet, 2, 2).should eq(3.0)
    number_at(sheet, 3, 0).should eq(12.0)
    number_at(sheet, 3, 1).should eq(3.14)
    number_at(sheet, 3, 2).should eq(7.0)
  end

  it "ignores text in numeric aggregates and counts empties" do
    sheet = sheet_with([
      ["1", "text", ""],
      ["=SUM(A1:C1)", "=COUNT(A1:C1)", "=COUNTA(A1:C1)"],
    ])
    number_at(sheet, 1, 0).should eq(1.0)
    number_at(sheet, 1, 1).should eq(1.0)
    number_at(sheet, 1, 2).should eq(2.0)
  end

  it "evaluates IF, IFERROR and boolean logic" do
    sheet = sheet_with([
      ["5", "=IF(A1>3, \"big\", \"small\")", "=IFERROR(1/0, 42)"],
      ["=AND(A1>1, A1<10)", "=OR(A1<1, A1>4)", "=NOT(A1>3)"],
    ])
    sheet.value(0, 1).display.should eq("big")
    number_at(sheet, 0, 2).should eq(42.0)
    sheet.value(1, 0).display.should eq("TRUE")
    sheet.value(1, 1).display.should eq("TRUE")
    sheet.value(1, 2).display.should eq("FALSE")
  end

  it "returns error values for bad expressions, names and refs" do
    sheet = sheet_with([
      ["=1/0", "=NOPE(1)", "=1+", "=SUM(A1:B99)", "=SQRT(-1)"],
    ])
    sheet.value(0, 0).error.should eq(SheetDemo::CellError::DivZero)
    sheet.value(0, 1).error.should eq(SheetDemo::CellError::Name)
    sheet.value(0, 2).error.should eq(SheetDemo::CellError::Parse)
    sheet.value(0, 3).error.should eq(SheetDemo::CellError::Ref)
    sheet.value(0, 4).error.should eq(SheetDemo::CellError::Num)
  end

  it "detects circular references instead of looping" do
    sheet = sheet_with([
      ["=B1", "=C1", "=A1"],
    ])
    sheet.value(0, 0).error.should eq(SheetDemo::CellError::Cycle)
  end

  it "treats quoted text as literal and plain text as text" do
    sheet = sheet_with([
      [%('=1+1), "abc", "12"],
    ])
    sheet.value(0, 0).display.should eq("=1+1")
    sheet.value(0, 1).display.should eq("abc")
    number_at(sheet, 0, 2).should eq(12.0)
  end

  it "recomputed values follow edits" do
    sheet = sheet_with([["1", "=A1*10"]])
    number_at(sheet, 0, 1).should eq(10.0)
    sheet.set_raw(0, 0, "7")
    number_at(sheet, 0, 1).should eq(70.0)
  end

  it "formats numbers without trailing zeros" do
    sheet = sheet_with([["=1/4", "=2/1", "=0.0000001"]])
    sheet.value(0, 0).display.should eq("0.25")
    sheet.value(0, 1).display.should eq("2")
  end
end

describe "SheetDemo::Sheet structure" do
  it "inserts and deletes rows and columns" do
    sheet = sheet_with([["1", "2"], ["3", "4"]])
    sheet.insert_row(1)
    sheet.raw(1, 0).should eq("")
    sheet.raw(2, 0).should eq("3")
    sheet.delete_row(1)
    sheet.raw(1, 0).should eq("3")

    sheet.insert_col(1)
    sheet.raw(0, 1).should eq("")
    sheet.raw(0, 2).should eq("2")
    sheet.delete_col(1)
    sheet.raw(0, 1).should eq("2")
  end

  it "refuses out-of-bounds edits and deletions" do
    sheet = SheetDemo::Sheet.new(5, 3)
    sheet.set_raw(-1, 0, "x").should be_false
    sheet.set_raw(5, 0, "x").should be_false
    sheet.delete_row(99).should be_false
    sheet.delete_col(99).should be_false
  end

  it "clears ranges and reports changes" do
    sheet = sheet_with([["1", "2"], ["3", "4"]])
    revision = sheet.revision
    sheet.clear_range(0, 1, 0, 1).should be_true
    sheet.raw(0, 0).should eq("")
    sheet.revision.should be > revision
    sheet.clear_range(0, 1, 0, 1).should be_false
  end

  it "snapshots and restores full state including dimensions" do
    sheet = sheet_with([["1", "=A1+1"]])
    snapshot = sheet.snapshot
    sheet.set_raw(0, 0, "5")
    sheet.insert_row(0)
    sheet.restore(snapshot)
    sheet.raw(0, 0).should eq("1")
    number_at(sheet, 0, 1).should eq(2.0)
    sheet.row_count.should eq(snapshot.rows)
  end
end

describe "SheetDemo::Sheet CSV" do
  it "round-trips quoted fields, commas and newlines" do
    text = %(a,b\n"x,y","line\nbreak"\n)
    sheet = SheetDemo::Sheet.from_csv(text)
    sheet.raw(0, 0).should eq("a")
    sheet.raw(0, 1).should eq("b")
    sheet.raw(1, 0).should eq("x,y")
    sheet.raw(1, 1).should eq("line\nbreak")
    sheet.to_csv.lines.first.chomp.should eq("a,b")
  end

  it "keeps formulas intact through export and import" do
    source = SheetDemo::Sheet.new(10, 5)
    source.load_records([["2", "3", "=A1*B1"]])
    csv = source.to_csv
    reloaded = SheetDemo::Sheet.from_csv(csv)
    reloaded.raw(0, 2).should eq("=A1*B1")
    number_at(reloaded, 0, 2).should eq(6.0)
  end

  it "escapes quotes on export" do
    sheet = SheetDemo::Sheet.new(5, 5)
    sheet.set_raw(0, 0, %(say "hi"))
    sheet.to_csv.lines.first.chomp.should eq(%("say ""hi"""))
  end

  it "parses CRLF input" do
    records = SheetDemo::Sheet.parse_csv("a,b\r\n1,2\r\n")
    records.should eq([["a", "b"], ["1", "2"]])
  end
end

describe "SheetDemo::Sheet.demo" do
  it "ships a workbook whose formulas evaluate" do
    sheet = SheetDemo::Sheet.demo
    sheet.raw(3, 5).should eq("=SUM(B4:E4)")
    number_at(sheet, 3, 5).should eq(533000.0)
    number_at(sheet, 5, 1).should eq(58000.0)
    number_at(sheet, 10, 1).should eq(0.21)
  end
end
