# SheetApp — workbook state, toolbar actions, undo/redo, file IO and theme.
require "tessell/kit"
require "./sheet"
require "./grid"
require "./widgets"

module SheetDemo
  class SheetApp
    getter sheet : Sheet
    getter grid : SheetGrid
    getter toolbar : Tessell::Kit::Row
    getter formula : FormulaBar
    getter status : StatusBar
    getter shell : SheetShell
    getter root : Tessell::Kit::Root?
    property file_path : String
    getter theme_dark : Bool
    getter message : String

    @undo : Array(SheetSnapshot)
    @redo : Array(SheetSnapshot)
    @saved_revision : Int32
    @theme_button : Tessell::Kit::Button?
    @clipboard : Tessell::Kit::Clipboard

    def initialize(@file_path : String = "sheet.csv", @theme_dark : Bool = false,
                   clipboard : Tessell::Kit::Clipboard = Tessell::Kit::MemoryClipboard.new)
      @clipboard = clipboard
      @undo = [] of SheetSnapshot
      @redo = [] of SheetSnapshot
      @root = nil
      @theme_button = nil
      @saved_revision = 0
      @message = ""
      @sheet = Sheet.demo
      @grid = SheetGrid.new(key(0x10_u64), @sheet, clipboard)
      @formula = FormulaBar.new(key(0x11_u64), "A1", "")
      @status = StatusBar.new(key(0x12_u64), "", "Tessell Kit")
      @toolbar = build_toolbar(key(0x13_u64))
      @shell = SheetShell.new(key(0x01_u64), @toolbar, @formula, @grid, @status)
      @saved_revision = @sheet.revision
      @message = "Ready"
      wire_grid
      update_theme_button
      refresh
    end

    def build_root(metrics : Tessell::Kit::TextMetrics,
                   clipboard : Tessell::Kit::Clipboard,
                   scale : Float32 = 1.0_f32) : Tessell::Kit::Root
      @clipboard = clipboard
      @grid.clipboard = clipboard
      @root = Tessell::Kit::Root.new(@shell, current_theme, metrics,
        Tessell::Rect.new(0.0_f32, 0.0_f32, 1180.0_f32, 760.0_f32), scale)
      @root.not_nil!
    end

    def on_root_ready(root : Tessell::Kit::Root) : Nil
      @root = root
      root.focus(@grid)
      refresh
    end

    def current_theme : Tessell::Kit::Theme
      @theme_dark ? Tessell::Kit::Theme.dark : Tessell::Kit::Theme.light
    end

    def modified? : Bool
      @sheet.revision != @saved_revision
    end

    # Tab must be intercepted before Root: Root always consumes Tab for focus
    # traversal, so a grid cannot implement cell-over-cell Tab navigation.
    def handle_app_event(event : Tessell::Input::Event) : Bool
      return false unless event.kind == Tessell::Input::Event::Kind::KeyDown
      root = @root
      return false unless root
      return false unless @grid.focused

      # Tab is always consumed by Root for focus traversal; Ctrl/Meta+Tab is
      # left to Root so the keyboard user can leave the grid.
      if event.key == Tessell::Input::KeyCode::Tab
        return false if event.ctrl? || event.meta?
        return @grid.handle(
          Tessell::Kit::Event.key_down(Tessell::Kit::Key::Tab, event.modifiers),
          root.context)
      end

      # Escape leaves the grid (when not editing) so focus can reach the
      # toolbar; there is no other way out of the cell navigation loop.
      if event.key == Tessell::Input::KeyCode::Escape && !@grid.editing?
        if button = first_toolbar_button
          root.focus(button)
        end
        return true
      end
      false
    end

    def first_toolbar_button : Tessell::Kit::Button?
      @toolbar.children.first?.as?(Tessell::Kit::Button)
    end

    # Cmd/Ctrl+S/O/N/Y cannot travel through KeyCode (Y/S/O/N are absent), so
    # the SDL host calls this after reading the raw platform key symbol.
    def handle_shortcut(char : Char) : Bool
      case char.downcase
      when 's'
        save
        true
      when 'o'
        open
        true
      when 'n'
        new_sheet
        true
      when 'y'
        redo
        true
      else
        false
      end
    end

    def new_sheet : Nil
      push_undo
      @sheet = Sheet.empty
      @grid.sheet = @sheet
      @grid.reset_selection
      @saved_revision = -1
      @message = "New sheet"
      refresh
    end

    def open : Nil
      unless File.exists?(@file_path)
        @message = "No #{@file_path}"
        refresh
        return
      end
      push_undo
      @sheet = Sheet.from_csv(File.read(@file_path))
      @grid.sheet = @sheet
      @grid.reset_selection
      @saved_revision = @sheet.revision
      @message = "Opened #{@file_path}"
      refresh
    rescue ex
      @message = "Open failed: #{ex.message}"
      refresh
    end

    def save : Nil
      File.write(@file_path, @sheet.to_csv)
      @saved_revision = @sheet.revision
      @message = "Saved #{@file_path}"
      refresh
    rescue ex
      @message = "Save failed: #{ex.message}"
      refresh
    end

    def undo : Nil
      return if @undo.empty?
      @redo << @sheet.snapshot
      @sheet.restore(@undo.pop)
      @grid.cancel_edit
      @grid.refresh_after_change
      @message = "Undo"
      refresh
    end

    def redo : Nil
      return if @redo.empty?
      @undo << @sheet.snapshot
      @sheet.restore(@redo.pop)
      @grid.cancel_edit
      @grid.refresh_after_change
      @message = "Redo"
      refresh
    end

    def insert_row : Nil
      push_undo
      @sheet.insert_row(@grid.active_row)
      @grid.refresh_after_change
      @message = "Inserted row #{@grid.active_row + 1}"
      refresh
    end

    def delete_row : Nil
      return if @sheet.row_count <= 1
      push_undo
      @sheet.delete_row(@grid.active_row)
      @grid.refresh_after_change
      @message = "Deleted row"
      refresh
    end

    def insert_col : Nil
      push_undo
      @sheet.insert_col(@grid.active_col)
      @grid.refresh_after_change
      @message = "Inserted column #{Formula.col_label(@grid.active_col)}"
      refresh
    end

    def delete_col : Nil
      return if @sheet.col_count <= 1
      push_undo
      @sheet.delete_col(@grid.active_col)
      @grid.refresh_after_change
      @message = "Deleted column"
      refresh
    end

    def toggle_theme : Nil
      set_theme(!@theme_dark)
      @message = @theme_dark ? "Dark theme" : "Light theme"
      refresh
    end

    def set_theme(dark : Bool) : Nil
      @theme_dark = dark
      @root.try { |root| root.theme = current_theme }
      update_theme_button
      refresh
    end

    def load_demo : Nil
      push_undo
      @sheet = Sheet.demo
      @grid.sheet = @sheet
      @grid.reset_selection
      @saved_revision = -1
      @message = "Demo data"
      refresh
    end

    def push_undo : Nil
      @undo << @sheet.snapshot
      @undo.shift if @undo.size > 100
      @redo.clear
    end

    def refresh : Nil
      @formula.address = @grid.address
      @formula.content = @grid.editing? ? @grid.editing_text : @grid.active_raw
      @status.text = status_text
      if button = @theme_button
        button.label = @theme_dark ? "Light" : "Dark"
      end
    end

    private def status_text : String
      active = @grid.address
      display = @grid.active_display
      r0, r1, c0, c1 = @grid.selection_bounds
      rows = r1 - r0 + 1
      cols = c1 - c0 + 1
      sum = 0.0
      numeric = 0
      nonempty = 0
      row = r0
      while row <= r1
        col = c0
        while col <= c1
          value = @sheet.value(row, col)
          unless value.empty?
            nonempty += 1
            if value.number?
              sum += value.number
              numeric += 1
            end
          end
          col += 1
        end
        row += 1
      end

      parts = [] of String
      parts << "#{active}  #{display.empty? ? "empty" : display}"
      if rows > 1 || cols > 1
        parts << "Selected #{rows}x#{cols}"
        parts << "Non-empty #{nonempty}"
        if numeric > 0
          parts << "Sum #{CellValue.format_number(sum)}"
          parts << "Avg #{CellValue.format_number(sum / numeric)}"
          parts << "Count #{numeric}"
        end
      end
      parts << (modified? ? "Modified" : "Saved")
      parts << @message unless @message.empty?
      parts.join("  |  ")
    end

    private def wire_grid : Nil
      @grid.on_before_change = -> { push_undo; nil }
      @grid.on_change = -> { refresh; nil }
      @grid.on_selection_change = -> { refresh; nil }
      @grid.on_edit_change = -> { refresh; nil }
      @grid.on_undo = -> { undo; nil }
      @grid.on_redo = -> { redo; nil }
    end

    private def build_toolbar(key : Tessell::UI::UiKey) : Tessell::Kit::Row
      row = Tessell::Kit::Row.new(key, Tessell::Insets.new, 6.0_f32,
        Tessell::Kit::Alignment::Start)
      add_button(row, key.child(1_u64), "New", -> { new_sheet; nil })
      add_button(row, key.child(2_u64), "Open", -> { open; nil })
      add_button(row, key.child(3_u64), "Save", -> { save; nil })
      add_button(row, key.child(4_u64), "Undo", -> { undo; nil })
      add_button(row, key.child(5_u64), "Redo", -> { redo; nil })
      add_button(row, key.child(6_u64), "+ Row", -> { insert_row; nil })
      add_button(row, key.child(7_u64), "+ Col", -> { insert_col; nil })
      add_button(row, key.child(8_u64), "- Row", -> { delete_row; nil })
      add_button(row, key.child(9_u64), "- Col", -> { delete_col; nil })
      theme = add_button(row, key.child(10_u64), "Dark", -> { toggle_theme; nil })
      @theme_button = theme
      add_button(row, key.child(11_u64), "Demo", -> { load_demo; nil })
      row
    end

    private def add_button(row : Tessell::Kit::Row, key : Tessell::UI::UiKey,
                           label : String, action : Proc(Nil)) : Tessell::Kit::Button
      button = Tessell::Kit::Button.new(key, label,
        Tessell::Kit::Variant::Secondary, Tessell::Kit::ControlSize::Small)
      button.on_click = action
      row.add(button)
      button
    end

    private def update_theme_button : Nil
      if button = @theme_button
        button.label = @theme_dark ? "Light" : "Dark"
      end
    end

    private def key(local : UInt64) : Tessell::UI::UiKey
      Tessell::UI::UiKey.root.child(local)
    end
  end
end
