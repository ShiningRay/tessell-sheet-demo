# SheetGrid — a self-drawn spreadsheet viewport.
#
# The grid is one Kit component (one retained node). It owns:
#   - active cell + rectangular selection
#   - row/column headers, frozen while the body scrolls
#   - in-cell editing through Kit::TextEditing
#   - pointer selection, wheel scrolling and scrollbar dragging
#   - clipboard TSV copy/cut/paste
#
# The framework has no 2D data-grid primitive, so all coordinate mapping,
# clipping and scrollbar logic lives here on top of Kit::Painter.
require "tessell/kit"
require "./sheet"

module SheetDemo
  class SheetGrid < Tessell::Kit::Component
    enum DragMode
      None
      Select
      VScroll
      HScroll
    end

    getter sheet : Sheet
    getter active_row : Int32
    getter active_col : Int32
    getter anchor_row : Int32
    getter anchor_col : Int32
    getter sel_row0 : Int32
    getter sel_row1 : Int32
    getter sel_col0 : Int32
    getter sel_col1 : Int32
    # 滚动数学委托给 Kit::ScrollModel（tessell 0.2.0, issue #17）。
    # 行等高，行区间与坐标↔索引直接用 model_y；列宽不等，x 轴只取
    # offset/clamp，可见列单独扫描。
    getter model_x : Tessell::Kit::ScrollModel
    getter model_y : Tessell::Kit::ScrollModel
    getter row_height : Float32
    getter header_width : Float32
    getter header_height : Float32
    getter default_col_width : Float32
    getter scrollbar_width : Float32
    getter editing : Tessell::Kit::TextEditing?
    getter hover_row : Int32?
    getter hover_col : Int32?

    property clipboard : Tessell::Kit::Clipboard
    property on_before_change : Proc(Nil)?
    property on_change : Proc(Nil)?
    property on_selection_change : Proc(Nil)?
    property on_edit_change : Proc(Nil)?
    property on_undo : Proc(Nil)?
    property on_redo : Proc(Nil)?

    @col_widths : Array(Float32)
    @drag_mode : DragMode
    @drag_thumb_offset : Float32
    @last_click_ms : Int64
    @last_click_row : Int32
    @last_click_col : Int32

    def initialize(@key : Tessell::UI::UiKey, @sheet : Sheet,
                   @clipboard : Tessell::Kit::Clipboard = Tessell::Kit::MemoryClipboard.new,
                   enabled : Bool = true)
      super(@key, enabled)
      @active_row = 0
      @active_col = 0
      @anchor_row = 0
      @anchor_col = 0
      @sel_row0 = 0
      @sel_row1 = 0
      @sel_col0 = 0
      @sel_col1 = 0
      @model_x = Tessell::Kit::ScrollModel.new
      @model_y = Tessell::Kit::ScrollModel.new
      @row_height = 28.0_f32
      @header_width = 56.0_f32
      @header_height = 32.0_f32
      @default_col_width = 100.0_f32
      @scrollbar_width = 12.0_f32
      @col_widths = Array.new(@sheet.col_count) { |index| index == 0 ? 150.0_f32 : 100.0_f32 }
      @editing = nil
      @hover_row = nil
      @hover_col = nil
      @drag_mode = DragMode::None
      @drag_thumb_offset = 0.0_f32
      @last_click_ms = -10_000_i64
      @last_click_row = -1
      @last_click_col = -1
      @on_before_change = nil
      @on_change = nil
      @on_selection_change = nil
      @on_edit_change = nil
      @on_undo = nil
      @on_redo = nil
    end

    def sheet=(value : Sheet) : Nil
      return if value.same?(@sheet)
      @sheet = value
      @col_widths = Array.new(@sheet.col_count) { |index| index == 0 ? 150.0_f32 : 100.0_f32 }
      @editing = nil
      reset_selection
      @model_x.offset = 0.0_f32
      @model_y.offset = 0.0_f32
      notify_selection
    end

    def scroll_x : Float32
      @model_x.offset
    end

    def scroll_x=(value : Float32) : Nil
      @model_x.offset = value
    end

    def scroll_y : Float32
      @model_y.offset
    end

    def scroll_y=(value : Float32) : Nil
      @model_y.offset = value
    end

    # 表格内部导航（tessell 0.2.0, issue #16）：Root 先把 Tab/Shift+Tab
    # 投递给焦点组件；Ctrl/Meta+Tab 仍恒定走焦点环。
    def wants_tab? : Bool
      @visible && @enabled
    end

    def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
      width = constraints.max_width.infinite? ? 960.0_f32 : constraints.max_width
      height = constraints.max_height.infinite? ? 560.0_f32 : constraints.max_height
      constraints.constrain(Tessell::Size.new(width, height))
    end

    def arrange(ctx : Tessell::Kit::Context, bounds : Tessell::Rect) : Nil
      @bounds = bounds
      sync_scroll_models
      ensure_visible
    end

    def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
      b.node(@key, @bounds, paint: paint_token,
        a11y_role: Tessell::A11y::Role::Group,
        a11y_name: "Sheet grid",
        a11y_value: a11y_value,
        a11y_focusable: focusable?,
        a11y_enabled: @enabled)
    end

    def focusable? : Bool
      @visible && @enabled
    end

    def a11y_name : String
      "Sheet grid"
    end

    def a11y_value : String
      "#{address} #{sheet.value(@active_row, @active_col).display}"
    end

    def address(row : Int32 = @active_row, col : Int32 = @active_col) : String
      "#{Formula.col_label(col)}#{row + 1}"
    end

    def active_raw : String
      @sheet.raw(@active_row, @active_col)
    end

    def active_display : String
      @sheet.value(@active_row, @active_col).display
    end

    def editing? : Bool
      !@editing.nil?
    end

    def editing_text : String
      @editing.try(&.text) || ""
    end

    # Logical center of a cell in window coordinates. Useful for tests and
    # scripted screenshots; pointer events still go through Root#handle.
    def cell_center(row : Int32, col : Int32) : Tessell::Point
      rect = cell_rect(row, col)
      Tessell::Point.new(rect.origin.x + rect.size.width / 2.0_f32,
        rect.origin.y + rect.size.height / 2.0_f32)
    end

    def selection_bounds : {Int32, Int32, Int32, Int32}
      {@sel_row0, @sel_row1, @sel_col0, @sel_col1}
    end

    def reset_selection : Nil
      @active_row = 0
      @active_col = 0
      @anchor_row = 0
      @anchor_col = 0
      update_selection
    end

    def select_all : Nil
      @active_row = 0
      @active_col = 0
      @anchor_row = 0
      @anchor_col = 0
      @sel_row0 = 0
      @sel_row1 = @sheet.row_count - 1
      @sel_col0 = 0
      @sel_col1 = @sheet.col_count - 1
      notify_selection
    end

    # Call after row/column insert/delete or undo/redo.
    def refresh_after_change : Nil
      sync_col_widths
      @active_row = @active_row.clamp(0, @sheet.row_count - 1)
      @active_col = @active_col.clamp(0, @sheet.col_count - 1)
      @anchor_row = @anchor_row.clamp(0, @sheet.row_count - 1)
      @anchor_col = @anchor_col.clamp(0, @sheet.col_count - 1)
      update_selection
      sync_scroll_models
      ensure_visible
      notify_selection
    end

    def begin_edit(clear : Bool = false, initial : String? = nil) : Nil
      text = clear ? "" : @sheet.raw(@active_row, @active_col)
      @editing = Tessell::Kit::TextEditing.new(text)
      @editing.not_nil!.insert(initial) if initial
      ensure_visible
      notify_edit
    end

    def cancel_edit : Nil
      return unless @editing
      @editing = nil
      notify_edit
    end

    def commit_edit : Bool
      editing = @editing
      return false unless editing
      @editing = nil
      value = editing.text
      changed = value != @sheet.raw(@active_row, @active_col)
      if changed
        @on_before_change.try(&.call)
        @sheet.set_raw(@active_row, @active_col, value)
      end
      notify_edit
      notify_selection
      changed
    end

    def handle(event : Tessell::Kit::Event, ctx : Tessell::Kit::Context) : Bool
      case event.kind
      when Tessell::Kit::Event::Kind::PointerDown
        pointer_down(event, ctx)
      when Tessell::Kit::Event::Kind::PointerMove
        pointer_move(event, ctx)
      when Tessell::Kit::Event::Kind::PointerUp
        if @drag_mode != DragMode::None
          @drag_mode = DragMode::None
          true
        else
          false
        end
      when Tessell::Kit::Event::Kind::PointerCancel
        @drag_mode = DragMode::None
        false
      when Tessell::Kit::Event::Kind::Wheel
        wheel(event)
      when Tessell::Kit::Event::Kind::KeyDown
        key_down(event, ctx)
      when Tessell::Kit::Event::Kind::TextInput
        text_input(event)
      when Tessell::Kit::Event::Kind::Blur
        commit_edit
        false
      when Tessell::Kit::Event::Kind::PointerEnter, Tessell::Kit::Event::Kind::PointerLeave
        false
      else
        false
      end
    end

    def on_focus_changed(focused : Bool) : Nil
      super
      commit_edit unless focused
    end

    def paint(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context) : Nil
      return unless @visible
      palette = ctx.theme.palette
      body = body_rect

      p.fill_rect(@bounds, palette.canvas)
      p.fill_rect(body, palette.surface)

      first_row, last_row, first_col, last_col = visible_ranges

      p.push_clip(body)
      paint_selection(p, ctx, first_row, last_row, first_col, last_col)
      paint_grid_lines(p, ctx, first_row, last_row, first_col, last_col, body)
      paint_cells(p, ctx, first_row, last_row, first_col, last_col)
      paint_selection_border(p, ctx)
      paint_editor(p, ctx)
      p.pop_clip

      paint_headers(p, ctx, first_row, last_row, first_col, last_col)
      paint_scrollbars(p, ctx)
    end

    def paint_token : UInt32
      token = @sheet.revision.to_u32
      token = token &* 16777619_u32 &+ @active_row.to_u32
      token = token &* 16777619_u32 &+ @active_col.to_u32
      token = token &* 16777619_u32 &+ @sel_row0.to_u32
      token = token &* 16777619_u32 &+ @sel_row1.to_u32
      token = token &* 16777619_u32 &+ @sel_col0.to_u32
      token = token &* 16777619_u32 &+ @sel_col1.to_u32
      token = token &* 16777619_u32 &+ @model_x.offset.to_i32.to_u32
      token = token &* 16777619_u32 &+ @model_y.offset.to_i32.to_u32
      if editing = @editing
        token = token &* 16777619_u32 &+ editing.cursor.to_u32
        token = token &* 16777619_u32 &+ (editing.text.hash & 0xffffffff_u64).to_u32
      end
      token
    end

    private def pointer_down(event : Tessell::Kit::Event, ctx : Tessell::Kit::Context) : Bool
      commit_edit if @editing
      point = Tessell::Point.new(event.x, event.y)
      body = body_rect
      return false unless @bounds.contains?(point)

      if scrollbar_rect_v.contains?(point) && can_vscroll?
        @drag_mode = DragMode::VScroll
        thumb = vthumb_rect
        @drag_thumb_offset = thumb.contains?(point) ? event.y - thumb.origin.y : thumb.size.height / 2.0_f32
        scroll_to_pointer_y(event.y)
        return true
      end
      if scrollbar_rect_h.contains?(point) && can_hscroll?
        @drag_mode = DragMode::HScroll
        thumb = hthumb_rect
        @drag_thumb_offset = thumb.contains?(point) ? event.x - thumb.origin.x : thumb.size.width / 2.0_f32
        scroll_to_pointer_x(event.x)
        return true
      end

      if event.x < body.origin.x && event.y < body.origin.y
        select_all
        return true
      elsif event.x < body.origin.x
        if row = row_at_y(event.y)
          select_row(row)
          return true
        end
      elsif event.y < body.origin.y
        if col = col_at_x(event.x)
          select_column(col)
          return true
        end
      elsif body.contains?(point)
        if row = row_at_y(event.y)
          if col = col_at_x(event.x)
            double_click = @last_click_row == row && @last_click_col == col &&
                           ctx.now_ms - @last_click_ms <= 400_i64
            @last_click_ms = ctx.now_ms
            @last_click_row = row
            @last_click_col = col
            if double_click
              select_cell(row, col, extending: false)
              begin_edit
            else
              select_cell(row, col, extending: event.shift?)
              @drag_mode = DragMode::Select unless event.shift?
            end
            return true
          end
        end
      end
      false
    end

    private def pointer_move(event : Tessell::Kit::Event, ctx : Tessell::Kit::Context) : Bool
      point = Tessell::Point.new(event.x, event.y)
      body = body_rect
      case @drag_mode
      when DragMode::Select
        if body.contains?(point)
          if row = row_at_y(event.y)
            if col = col_at_x(event.x)
              select_cell(row, col, extending: true)
            end
          end
        end
        true
      when DragMode::VScroll
        scroll_to_pointer_y(event.y)
        true
      when DragMode::HScroll
        scroll_to_pointer_x(event.x)
        true
      else
        if body.contains?(point)
          @hover_row = row_at_y(event.y)
          @hover_col = col_at_x(event.x)
        else
          @hover_row = nil
          @hover_col = nil
        end
        false
      end
    end

    private def wheel(event : Tessell::Kit::Event) : Bool
      if event.shift? || event.wheel_dx.abs > event.wheel_dy.abs
        delta = event.wheel_dx != 0.0_f32 ? event.wheel_dx : event.wheel_dy
        @model_x.scroll_by(delta)
      else
        @model_y.scroll_by(-event.wheel_dy)
      end
      true
    end

    private def key_down(event : Tessell::Kit::Event, ctx : Tessell::Kit::Context) : Bool
      if @editing
        return edit_key(event, ctx)
      end

      if event.ctrl? || event.meta?
        case event.key
        when Tessell::Kit::Key::KeyC
          copy_selection
          true
        when Tessell::Kit::Key::KeyX
          cut_selection
          true
        when Tessell::Kit::Key::KeyV
          paste_clipboard
          true
        when Tessell::Kit::Key::KeyA
          select_all
          true
        when Tessell::Kit::Key::KeyZ
          if event.shift?
            @on_redo.try(&.call)
          else
            @on_undo.try(&.call)
          end
          true
        else
          false
        end
      else
        navigate_key(event)
      end
    end

    private def navigate_key(event : Tessell::Kit::Event) : Bool
      page_rows = (body_rect.size.height / @row_height).floor.to_i.clamp(1, @sheet.row_count)
      case event.key
      when Tessell::Kit::Key::Left
        move_active(0, -1, event.shift?)
      when Tessell::Kit::Key::Right
        move_active(0, 1, event.shift?)
      when Tessell::Kit::Key::Up
        move_active(-1, 0, event.shift?)
      when Tessell::Kit::Key::Down
        move_active(1, 0, event.shift?)
      when Tessell::Kit::Key::Tab
        move_tab(event.shift?)
      when Tessell::Kit::Key::Enter
        move_active(event.shift? ? -1 : 1, 0, false)
      when Tessell::Kit::Key::Home
        select_cell(@active_row, 0, extending: event.shift?)
        true
      when Tessell::Kit::Key::End
        select_cell(@active_row, @sheet.col_count - 1, extending: event.shift?)
        true
      when Tessell::Kit::Key::PageUp
        move_active(-page_rows, 0, event.shift?)
      when Tessell::Kit::Key::PageDown
        move_active(page_rows, 0, event.shift?)
      when Tessell::Kit::Key::Delete
        clear_selection
        true
      when Tessell::Kit::Key::Backspace
        begin_edit(clear: true)
        true
      else
        false
      end
    end

    private def edit_key(event : Tessell::Kit::Event, ctx : Tessell::Kit::Context) : Bool
      editing = @editing.not_nil!
      if event.ctrl? || event.meta?
        case event.key
        when Tessell::Kit::Key::KeyA
          editing.select_all
          notify_edit
          true
        when Tessell::Kit::Key::KeyC
          if editing.selection?
            editing.copy(@clipboard)
          else
            @clipboard.set(editing.text)
          end
          true
        when Tessell::Kit::Key::KeyX
          if editing.selection?
            editing.cut(@clipboard)
          else
            @clipboard.set(editing.text)
            editing.select_all
            editing.cut(@clipboard)
          end
          notify_edit
          true
        when Tessell::Kit::Key::KeyV
          if value = @clipboard.get
            editing.insert(value.gsub("\r\n", " ").gsub('\n', ' ').gsub('\r', ' '))
            notify_edit
          end
          true
        else
          false
        end
      else
        extending = event.shift?
        case event.key
        when Tessell::Kit::Key::Left
          editing.move_left(extending)
          notify_edit
          true
        when Tessell::Kit::Key::Right
          editing.move_right(extending)
          notify_edit
          true
        when Tessell::Kit::Key::Home
          editing.move_home(extending)
          notify_edit
          true
        when Tessell::Kit::Key::End
          editing.move_end(extending)
          notify_edit
          true
        when Tessell::Kit::Key::Backspace
          editing.backspace
          notify_edit
          true
        when Tessell::Kit::Key::Delete
          editing.delete
          notify_edit
          true
        when Tessell::Kit::Key::Escape
          cancel_edit
          true
        when Tessell::Kit::Key::Enter
          commit_and_move(event.shift? ? -1 : 1, 0)
          true
        when Tessell::Kit::Key::Tab
          commit_and_move_tab(event.shift?)
          true
        when Tessell::Kit::Key::Up
          commit_and_move(-1, 0)
          true
        when Tessell::Kit::Key::Down
          commit_and_move(1, 0)
          true
        else
          false
        end
      end
    end

    private def text_input(event : Tessell::Kit::Event) : Bool
      text = event.text
      return false unless text
      unless @editing
        begin_edit(clear: true)
      end
      editing = @editing
      return false unless editing
      editing.insert(text)
      notify_edit
      true
    end

    private def notify_edit : Nil
      @on_edit_change.try(&.call)
    end

    private def notify_selection : Nil
      @on_selection_change.try(&.call)
    end

    private def select_cell(row : Int32, col : Int32, extending : Bool) : Nil
      row = row.clamp(0, @sheet.row_count - 1)
      col = col.clamp(0, @sheet.col_count - 1)
      @active_row = row
      @active_col = col
      unless extending
        @anchor_row = row
        @anchor_col = col
      end
      update_selection
      ensure_visible
      notify_selection
    end

    private def select_column(col : Int32) : Nil
      col = col.clamp(0, @sheet.col_count - 1)
      @active_row = 0
      @active_col = col
      @anchor_row = 0
      @anchor_col = col
      @sel_row0 = 0
      @sel_row1 = @sheet.row_count - 1
      @sel_col0 = col
      @sel_col1 = col
      ensure_visible
      notify_selection
    end

    private def select_row(row : Int32) : Nil
      row = row.clamp(0, @sheet.row_count - 1)
      @active_row = row
      @active_col = 0
      @anchor_row = row
      @anchor_col = 0
      @sel_row0 = row
      @sel_row1 = row
      @sel_col0 = 0
      @sel_col1 = @sheet.col_count - 1
      ensure_visible
      notify_selection
    end

    private def update_selection : Nil
      @sel_row0 = Math.min(@anchor_row, @active_row)
      @sel_row1 = Math.max(@anchor_row, @active_row)
      @sel_col0 = Math.min(@anchor_col, @active_col)
      @sel_col1 = Math.max(@anchor_col, @active_col)
    end

    private def move_active(row_delta : Int32, col_delta : Int32, extending : Bool) : Bool
      row = (@active_row + row_delta).clamp(0, @sheet.row_count - 1)
      col = (@active_col + col_delta).clamp(0, @sheet.col_count - 1)
      select_cell(row, col, extending)
      true
    end

    private def move_tab(backward : Bool) : Bool
      if backward
        if @active_col > 0
          select_cell(@active_row, @active_col - 1, false)
        elsif @active_row > 0
          select_cell(@active_row - 1, @sheet.col_count - 1, false)
        end
      else
        if @active_col < @sheet.col_count - 1
          select_cell(@active_row, @active_col + 1, false)
        elsif @active_row < @sheet.row_count - 1
          select_cell(@active_row + 1, 0, false)
        end
      end
      true
    end

    private def commit_and_move(row_delta : Int32, col_delta : Int32) : Nil
      commit_edit
      select_cell(@active_row + row_delta, @active_col + col_delta, false)
    end

    private def commit_and_move_tab(backward : Bool) : Nil
      commit_edit
      move_tab(backward)
    end

    private def clear_selection : Bool
      return false unless selection_has_content?
      @on_before_change.try(&.call)
      changed = @sheet.clear_range(@sel_row0, @sel_row1, @sel_col0, @sel_col1)
      if changed
        @on_change.try(&.call)
        notify_selection
      end
      changed
    end

    private def selection_has_content? : Bool
      row = @sel_row0
      while row <= @sel_row1
        col = @sel_col0
        while col <= @sel_col1
          return true unless @sheet.raw(row, col).empty?
          col += 1
        end
        row += 1
      end
      false
    end

    private def copy_selection : Nil
      builder = String::Builder.new
      row = @sel_row0
      while row <= @sel_row1
        col = @sel_col0
        while col <= @sel_col1
          builder << @sheet.raw(row, col)
          builder << '\t' if col < @sel_col1
          col += 1
        end
        builder << '\n' if row < @sel_row1
        row += 1
      end
      @clipboard.set(builder.to_s)
    end

    private def cut_selection : Nil
      copy_selection
      clear_selection
    end

    private def paste_clipboard : Nil
      text = @clipboard.get
      return if text.nil? || text.empty?
      records = parse_tsv(text)
      return if records.empty?
      @on_before_change.try(&.call)
      changed = false
      records.each_with_index do |record, r|
        record.each_with_index do |raw, c|
          row = @sel_row0 + r
          col = @sel_col0 + c
          changed = @sheet.set_raw(row, col, raw) || changed
        end
      end
      @active_row = @sel_row0
      @active_col = @sel_col0
      @anchor_row = @sel_row0
      @anchor_col = @sel_col0
      rows = Math.min(records.size, @sheet.row_count - @sel_row0)
      widest = 0
      records.each { |record| widest = Math.max(widest, record.size) }
      cols = Math.min(widest, @sheet.col_count - @sel_col0)
      @sel_row0 = @active_row
      @sel_row1 = (@active_row + rows - 1).clamp(@active_row, @sheet.row_count - 1)
      @sel_col0 = @active_col
      @sel_col1 = (@active_col + cols - 1).clamp(@active_col, @sheet.col_count - 1)
      if changed
        @on_change.try(&.call)
      end
      ensure_visible
      notify_selection
    end

    private def parse_tsv(text : String) : Array(Array(String))
      lines = text.split('\n').map(&.chomp('\r'))
      while !lines.empty? && lines.last.empty?
        lines.pop
      end
      lines.map { |line| line.split('\t') }
    end

    # 内容尺寸/viewport 变化后同步到 ScrollModel；写入 offset 即 clamp。
    private def sync_scroll_models : Nil
      body = body_rect
      @model_x.content_size = total_width
      @model_x.viewport_size = body.size.width
      @model_y.content_size = @sheet.row_count * @row_height
      @model_y.viewport_size = body.size.height
      @model_x.offset = @model_x.offset
      @model_y.offset = @model_y.offset
    end

    private def ensure_visible : Nil
      body = body_rect
      return if body.size.width <= 0.0_f32 || body.size.height <= 0.0_f32
      sync_scroll_models
      x0 = col_x(@active_col)
      x1 = x0 + col_width(@active_col)
      view_x = @model_x.offset
      view_w = body.size.width
      if x0 < view_x
        @model_x.offset = x0
      elsif x1 > view_x + view_w
        @model_x.offset = x1 - view_w
      end
      # 行等高：ScrollModel 的 index_at/offset_at 直接可用，
      # 可见性仍按“整行进入视口”的表格语义处理。
      row_top = @model_y.offset_at(@active_row, @row_height)
      row_bottom = row_top + @row_height
      view_y = @model_y.offset
      view_h = body.size.height
      if row_top < view_y
        @model_y.offset = row_top
      elsif row_bottom > view_y + view_h
        @model_y.offset = row_bottom - view_h
      end
    end

    private def body_rect : Tessell::Rect
      Tessell::Rect.new(
        @bounds.origin.x + @header_width,
        @bounds.origin.y + @header_height,
        Math.max(0.0_f32, @bounds.size.width - @header_width),
        Math.max(0.0_f32, @bounds.size.height - @header_height)
      )
    end

    private def max_scroll_x : Float32
      @model_x.max_offset
    end

    private def max_scroll_y : Float32
      @model_y.max_offset
    end

    private def can_hscroll? : Bool
      @model_x.scrollable?
    end

    private def can_vscroll? : Bool
      @model_y.scrollable?
    end

    private def total_width : Float32
      total = 0.0_f32
      @col_widths.each { |width| total += width }
      total
    end

    private def col_width(col : Int32) : Float32
      @col_widths[col]? || @default_col_width
    end

    private def col_x(col : Int32) : Float32
      total = 0.0_f32
      index = 0
      while index < col && index < @col_widths.size
        total += @col_widths[index]
        index += 1
      end
      total
    end

    private def col_at_x(x : Float32) : Int32?
      local = x - body_rect.origin.x + @model_x.offset
      return nil if local < 0.0_f32 || local > total_width
      total = 0.0_f32
      @col_widths.each_with_index do |width, index|
        if local < total + width
          return index
        end
        total += width
      end
      nil
    end

    private def row_at_y(y : Float32) : Int32?
      row = @model_y.index_at(y - body_rect.origin.y, @row_height)
      row >= 0 && row < @sheet.row_count ? row : nil
    end

    def cell_rect(row : Int32, col : Int32) : Tessell::Rect
      body = body_rect
      Tessell::Rect.new(
        body.origin.x + col_x(col) - @model_x.offset,
        body.origin.y + @model_y.offset_at(row, @row_height) - @model_y.offset,
        col_width(col),
        @row_height
      )
    end

    private def visible_ranges : {Int32, Int32, Int32, Int32}
      body = body_rect
      first_row, last_row = @model_y.visible_range(@row_height, @sheet.row_count)
      first_row = first_row.clamp(0, @sheet.row_count - 1)
      last_row = last_row.clamp(0, @sheet.row_count - 1)
      view_right = @model_x.offset + body.size.width
      first_col = 0
      while first_col < @sheet.col_count - 1 && col_x(first_col) + col_width(first_col) <= @model_x.offset
        first_col += 1
      end
      last_col = first_col
      while last_col < @sheet.col_count - 1 && col_x(last_col + 1) < view_right
        last_col += 1
      end
      {first_row, last_row, first_col, last_col}
    end

    private def sync_col_widths : Nil
      return if @col_widths.size == @sheet.col_count
      old = @col_widths
      @col_widths = Array.new(@sheet.col_count) { |index| index == 0 ? 150.0_f32 : 100.0_f32 }
      count = Math.min(old.size, @col_widths.size)
      index = 0
      while index < count
        @col_widths[index] = old[index]
        index += 1
      end
    end

    private def scrollbar_rect_v : Tessell::Rect
      body = body_rect
      Tessell::Rect.new(@bounds.max_x - @scrollbar_width, body.origin.y,
        @scrollbar_width, body.size.height)
    end

    private def scrollbar_rect_h : Tessell::Rect
      body = body_rect
      Tessell::Rect.new(body.origin.x, @bounds.max_y - @scrollbar_width,
        body.size.width, @scrollbar_width)
    end

    private def vthumb_rect : Tessell::Rect
      body = body_rect
      track = scrollbar_rect_v
      thumb = @model_y.thumb(body.size.height)
      Tessell::Rect.new(track.origin.x + 2.0_f32, body.origin.y + thumb.pos,
        @scrollbar_width - 4.0_f32, thumb.size)
    end

    private def hthumb_rect : Tessell::Rect
      body = body_rect
      track = scrollbar_rect_h
      thumb = @model_x.thumb(body.size.width)
      Tessell::Rect.new(body.origin.x + thumb.pos, track.origin.y + 2.0_f32,
        thumb.size, @scrollbar_width - 4.0_f32)
    end

    private def scroll_to_pointer_y(y : Float32) : Nil
      body = body_rect
      thumb = @model_y.thumb(body.size.height)
      travel = body.size.height - thumb.size
      return if travel <= 0.0_f32
      local = y - body.origin.y - @drag_thumb_offset
      @model_y.offset = (local / travel).clamp(0.0_f32, 1.0_f32) * @model_y.max_offset
    end

    private def scroll_to_pointer_x(x : Float32) : Nil
      body = body_rect
      thumb = @model_x.thumb(body.size.width)
      travel = body.size.width - thumb.size
      return if travel <= 0.0_f32
      local = x - body.origin.x - @drag_thumb_offset
      @model_x.offset = (local / travel).clamp(0.0_f32, 1.0_f32) * @model_x.max_offset
    end

    private def paint_selection(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context,
                                first_row : Int32, last_row : Int32,
                                first_col : Int32, last_col : Int32) : Nil
      row = Math.max(first_row, @sel_row0)
      while row <= Math.min(last_row, @sel_row1)
        col = Math.max(first_col, @sel_col0)
        while col <= Math.min(last_col, @sel_col1)
          p.fill_rect(cell_rect(row, col), ctx.theme.palette.selection)
          col += 1
        end
        row += 1
      end
      if @active_row >= first_row && @active_row <= last_row &&
         @active_col >= first_col && @active_col <= last_col
        p.fill_rect(cell_rect(@active_row, @active_col), ctx.theme.palette.surface)
      end
    end

    private def paint_grid_lines(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context,
                                 first_row : Int32, last_row : Int32,
                                 first_col : Int32, last_col : Int32,
                                 body : Tessell::Rect) : Nil
      # semantic grid token (tessell 0.2.0, issue #8) instead of generic border
      color = ctx.render_theme.grid
      body_top = body.origin.y
      body_bottom = body.max_y
      body_left = body.origin.x
      body_right = body.max_x
      col = first_col
      while col <= last_col + 1 && col <= @sheet.col_count
        x = body_left + col_x(col) - @model_x.offset
        if x >= body_left && x <= body_right
          p.line(x, body_top, x, body_bottom, color, 1.0_f32)
        end
        col += 1
      end
      row = first_row
      while row <= last_row + 1 && row <= @sheet.row_count
        y = body_top + row * @row_height - @model_y.offset
        if y >= body_top && y <= body_bottom
          p.line(body_left, y, body_right, y, color, 1.0_f32)
        end
        row += 1
      end
    end

    private def paint_cells(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context,
                            first_row : Int32, last_row : Int32,
                            first_col : Int32, last_col : Int32) : Nil
      fs = ctx.theme.font_size(Tessell::Kit::ControlSize::Medium)
      row = first_row
      while row <= last_row
        col = first_col
        while col <= last_col
          # Painter 契约保证调用顺序即绘制顺序、clip 同时裁切文本
          # （tessell 0.2.0, issue #15）。半可见单元格直接发命令，由后端
          # scissor 裁切；编辑器的填充会在之后按命令序覆盖原值文本。
          cell = cell_rect(row, col)
          value = @sheet.value(row, col)
          unless value.empty?
            content = fit_text(ctx, value.display, fs, cell.size.width - 12.0_f32)
            color = value.error? ? ctx.theme.palette.danger : ctx.theme.palette.foreground
            align_right = value.number? || value.bool?
            x = align_right ? cell.max_x - 6.0_f32 - ctx.measure_text(content, fs).width : cell.origin.x + 6.0_f32
            baseline = TextBaseline.centered(ctx, cell, fs)
            p.text(x, baseline, content, color, fs)
          end
          col += 1
        end
        row += 1
      end
    end

    private def paint_selection_border(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context) : Nil
      body = body_rect
      return unless @sel_col0 <= @sel_col1 && @sel_row0 <= @sel_row1
      x0 = body.origin.x + col_x(@sel_col0) - @model_x.offset
      x1 = body.origin.x + col_x(@sel_col1) + col_width(@sel_col1) - @model_x.offset
      y0 = body.origin.y + @sel_row0 * @row_height - @model_y.offset
      y1 = body.origin.y + (@sel_row1 + 1) * @row_height - @model_y.offset
      p.stroke_rect(Tessell::Rect.new(x0, y0, x1 - x0, y1 - y0),
        ctx.theme.palette.accent, 1.5_f32)
      active = cell_rect(@active_row, @active_col)
      p.stroke_rect(active, ctx.theme.palette.focus, 2.0_f32)
    end

    private def paint_editor(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context) : Nil
      editing = @editing
      return unless editing
      cell = cell_rect(@active_row, @active_col)
      body = body_rect
      return unless Tessell::Kit::Geometry.intersect(cell, body).size.width > 0.0_f32
      fs = ctx.theme.font_size(Tessell::Kit::ControlSize::Medium)
      p.fill_rect(cell, ctx.theme.palette.surface)
      p.stroke_rect(cell, ctx.theme.palette.focus, 2.0_f32)
      p.push_clip(cell)
      pad = 5.0_f32
      text_x = cell.origin.x + pad
      baseline = TextBaseline.centered(ctx, cell, fs)
      if editing.selection?
        start_x = text_x + ctx.measure_text(editing.text.byte_slice(0, editing.selection_start), fs).width
        end_x = text_x + ctx.measure_text(editing.text.byte_slice(0, editing.selection_end), fs).width
        p.fill_rect(Tessell::Rect.new(start_x, cell.origin.y + 3.0_f32,
          end_x - start_x, cell.size.height - 6.0_f32), ctx.theme.palette.selection)
      end
      p.text(text_x, baseline, editing.text, ctx.theme.palette.foreground, fs)
      if editing.preedit?
        preedit_x = text_x + ctx.measure_text(editing.text.byte_slice(0, editing.cursor), fs).width
        p.text(preedit_x, baseline, editing.preedit, ctx.theme.palette.accent, fs)
      end
      caret_x = text_x + ctx.measure_text(editing.text.byte_slice(0, editing.cursor), fs).width
      if (ctx.now_ms / 500_i64) % 2_i64 == 0_i64
        p.line(caret_x, cell.origin.y + 4.0_f32, caret_x, cell.max_y - 4.0_f32,
          ctx.theme.palette.foreground, 1.0_f32)
      end
      p.pop_clip
    end

    private def paint_headers(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context,
                              first_row : Int32, last_row : Int32,
                              first_col : Int32, last_col : Int32) : Nil
      body = body_rect
      palette = ctx.theme.palette
      metrics = ctx.theme.metrics
      header_fs = ctx.theme.font_size(Tessell::Kit::ControlSize::Small)

      column_header = Tessell::Rect.new(body.origin.x, @bounds.origin.y,
        body.size.width, @header_height)
      p.fill_rect(column_header, palette.surface_raised)
      p.push_clip(column_header)
      col = first_col
      while col <= last_col
        x = body.origin.x + col_x(col) - @model_x.offset
        width = col_width(col)
        if col >= @sel_col0 && col <= @sel_col1
          p.fill_rect(Tessell::Rect.new(x, @bounds.origin.y, width, @header_height),
            palette.selection)
        end
        label = Formula.col_label(col)
        text_w = ctx.measure_text(label, header_fs).width
        color = col == @active_col ? palette.accent : palette.muted
        p.text(x + (width - text_w) / 2.0_f32,
          TextBaseline.centered(ctx,
            Tessell::Rect.new(x, @bounds.origin.y, width, @header_height), header_fs),
          label, color, header_fs)
        p.line(x + width, @bounds.origin.y, x + width, @bounds.origin.y + @header_height,
          palette.border, 1.0_f32)
        col += 1
      end
      p.pop_clip

      row_header = Tessell::Rect.new(@bounds.origin.x, body.origin.y,
        @header_width, body.size.height)
      p.fill_rect(row_header, palette.surface_raised)
      p.push_clip(row_header)
      row = first_row
      while row <= last_row
        y = body.origin.y + row * @row_height - @model_y.offset
        if row >= @sel_row0 && row <= @sel_row1
          p.fill_rect(Tessell::Rect.new(@bounds.origin.x, y, @header_width, @row_height),
            palette.selection)
        end
        label = (row + 1).to_s
        text_w = ctx.measure_text(label, header_fs).width
        color = row == @active_row ? palette.accent : palette.muted
        p.text(@bounds.origin.x + @header_width - 8.0_f32 - text_w,
          TextBaseline.centered(ctx,
            Tessell::Rect.new(@bounds.origin.x, y, @header_width, @row_height), header_fs),
          label, color, header_fs)
        p.line(@bounds.origin.x, y + @row_height, @bounds.origin.x + @header_width,
          y + @row_height, palette.border, 1.0_f32)
        row += 1
      end
      p.pop_clip

      corner = Tessell::Rect.new(@bounds.origin.x, @bounds.origin.y,
        @header_width, @header_height)
      p.fill_rect(corner, palette.surface_raised)
      p.stroke_rect(corner, palette.border, metrics.border_width)
      p.line(corner.max_x, corner.origin.y, corner.max_x, corner.max_y,
        palette.border, 1.0_f32)
      p.line(corner.origin.x, corner.max_y, corner.max_x, corner.max_y,
        palette.border, 1.0_f32)
    end

    private def paint_scrollbars(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context) : Nil
      palette = ctx.theme.palette
      if can_vscroll?
        track = scrollbar_rect_v
        p.fill_rect(track, palette.surface_raised)
        p.fill_round_rect(vthumb_rect, 3.0_f32, palette.muted)
      end
      if can_hscroll?
        track = scrollbar_rect_h
        p.fill_rect(track, palette.surface_raised)
        p.fill_round_rect(hthumb_rect, 3.0_f32, palette.muted)
      end
    end

    private def fit_text(ctx : Tessell::Kit::Context, text : String, fs : Float32,
                         max_width : Float32) : String
      return text if text.empty? || max_width <= 0.0_f32
      return text if ctx.measure_text(text, fs).width <= max_width
      ellipsis = "…"
      ellipsis_width = ctx.measure_text(ellipsis, fs).width
      builder = String::Builder.new
      width = 0.0_f32
      text.each_char do |char|
        char_width = ctx.measure_text(char.to_s, fs).width
        break if width + char_width + ellipsis_width > max_width
        builder << char
        width += char_width
      end
      builder << ellipsis
      builder.to_s
    end
  end
end
