require "./spec_helper"

private def click(grid : SheetDemo::SheetGrid, x : Float32, y : Float32,
                  ctx : Tessell::Kit::Context,
                  shift : Bool = false) : Nil
  mods = Tessell::Kit::Modifiers.new(shift: shift)
  grid.handle(Tessell::Kit::Event.new(Tessell::Kit::Event::Kind::PointerDown,
    x, y, 0, nil, nil, mods), ctx)
  grid.handle(Tessell::Kit::Event.new(Tessell::Kit::Event::Kind::PointerUp,
    x, y, 0, nil, nil, mods), ctx)
end

describe "SheetDemo::SheetGrid geometry" do
  it "maps cell clicks to the expected address" do
    grid = SheetSpecHelpers.grid
    ctx = SheetSpecHelpers.context
    # body starts at (56, 32); A lane is 150 wide, rows are 28 high
    click(grid, 56.0_f32 + 160.0_f32, 32.0_f32 + 28.0_f32 * 2 + 4.0_f32, ctx)
    grid.address.should eq("B3")
    grid.selection_bounds.should eq({2, 2, 1, 1})
  end

  it "extends selection with shift and drag" do
    grid = SheetSpecHelpers.grid
    ctx = SheetSpecHelpers.context
    click(grid, 60.0_f32, 40.0_f32, ctx)
    grid.handle(Tessell::Kit::Event.new(Tessell::Kit::Event::Kind::PointerDown,
      56.0_f32 + 90.0_f32, 32.0_f32 + 28.0_f32 * 3 + 4.0_f32, 0, nil, nil,
      Tessell::Kit::Modifiers.new(shift: true)), ctx)
    grid.selection_bounds.should eq({0, 3, 0, 0})
  end

  it "selects whole rows from the row header" do
    grid = SheetSpecHelpers.grid
    ctx = SheetSpecHelpers.context
    click(grid, 20.0_f32, 32.0_f32 + 28.0_f32 * 3 + 4.0_f32, ctx)
    r0, r1, c0, c1 = grid.selection_bounds
    r0.should eq(3)
    r1.should eq(3)
    c0.should eq(0)
    c1.should eq(grid.sheet.col_count - 1)
  end

  it "selects whole columns from the column header" do
    grid = SheetSpecHelpers.grid
    ctx = SheetSpecHelpers.context
    click(grid, 56.0_f32 + 160.0_f32, 10.0_f32, ctx)
    r0, r1, c0, c1 = grid.selection_bounds
    c0.should eq(1)
    c1.should eq(1)
    r0.should eq(0)
    r1.should eq(grid.sheet.row_count - 1)
  end

  it "selects all cells from the corner" do
    grid = SheetSpecHelpers.grid
    ctx = SheetSpecHelpers.context
    click(grid, 10.0_f32, 10.0_f32, ctx)
    grid.selection_bounds.should eq({0, grid.sheet.row_count - 1,
                                     0, grid.sheet.col_count - 1})
  end

  it "scrolls with the wheel and clamps to content bounds" do
    grid = SheetSpecHelpers.grid
    ctx = SheetSpecHelpers.context
    grid.handle(Tessell::Kit::Event.wheel(400.0_f32, 300.0_f32, 0.0_f32, -120.0_f32), ctx)
    grid.scroll_y.should eq(120.0_f32)
    grid.handle(Tessell::Kit::Event.wheel(400.0_f32, 300.0_f32, 0.0_f32, 100_000.0_f32), ctx)
    grid.scroll_y.should eq(0.0_f32)
  end
end

describe "SheetDemo::SheetGrid navigation" do
  it "moves the active cell with arrow keys and Enter" do
    grid = SheetSpecHelpers.grid
    ctx = SheetSpecHelpers.context
    grid.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Right), ctx).should be_true
    grid.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Down), ctx).should be_true
    grid.address.should eq("B2")
    grid.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Enter), ctx).should be_true
    grid.address.should eq("B3")
  end

  it "extends selection with Shift+Arrow" do
    grid = SheetSpecHelpers.grid
    ctx = SheetSpecHelpers.context
    shift_down = Tessell::Kit::Event.key_down(Tessell::Kit::Key::Down,
      Tessell::Kit::Modifiers.new(shift: true))
    grid.handle(shift_down, ctx)
    grid.handle(shift_down, ctx)
    grid.address.should eq("A3")
    grid.selection_bounds.should eq({0, 2, 0, 0})
  end

  it "clamps movement at the sheet edges" do
    grid = SheetSpecHelpers.grid
    ctx = SheetSpecHelpers.context
    grid.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Left), ctx)
    grid.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Up), ctx)
    grid.address.should eq("A1")
    grid.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::End), ctx)
    grid.address.should eq("Z1")
    grid.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Down), ctx)
    grid.address.should eq("Z2")
  end

  it "keeps the active cell visible while moving" do
    grid = SheetSpecHelpers.grid
    ctx = SheetSpecHelpers.context
    grid.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::End), ctx)
    grid.scroll_x.should be > 0.0_f32
    grid.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Home), ctx)
    grid.scroll_x.should eq(0.0_f32)
  end
end

describe "SheetDemo::SheetGrid editing" do
  it "starts editing on text input and commits on Enter, then moves down" do
    grid = SheetSpecHelpers.grid(SheetDemo::Sheet.new(20, 8))
    ctx = SheetSpecHelpers.context
    grid.handle(Tessell::Kit::Event.text_input("42"), ctx).should be_true
    grid.editing?.should be_true
    grid.editing_text.should eq("42")
    grid.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Enter), ctx)
    grid.editing?.should be_false
    grid.sheet.raw(0, 0).should eq("42")
    grid.address.should eq("A2")
  end

  it "opens the editor with an existing value and can cancel" do
    grid = SheetSpecHelpers.grid
    ctx = SheetSpecHelpers.context
    # demo sheet row 4 (index 3) holds Revenue; navigate there first
    3.times { grid.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Down), ctx) }
    grid.address.should eq("A4")
    grid.begin_edit
    grid.editing_text.should eq(grid.sheet.raw(3, 0))
    grid.editing_text.should eq("Revenue")
    grid.cancel_edit
    grid.editing?.should be_false
    grid.sheet.raw(3, 0).should eq("Revenue")
  end

  it "moves caret and deletes inside the cell editor" do
    grid = SheetSpecHelpers.grid(SheetDemo::Sheet.new(20, 8))
    ctx = SheetSpecHelpers.context
    grid.handle(Tessell::Kit::Event.text_input("abc"), ctx)
    grid.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Left), ctx)
    grid.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Backspace), ctx)
    grid.editing_text.should eq("ac")
  end
end

describe "SheetDemo::SheetGrid clipboard" do
  it "copies a rectangular selection as TSV" do
    clipboard = Tessell::Kit::MemoryClipboard.new
    grid = SheetSpecHelpers.grid(nil, clipboard)
    ctx = SheetSpecHelpers.context
    grid.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::KeyA,
      Tessell::Kit::Modifiers.new(ctrl: true)), ctx).should be_true
    grid.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::KeyC,
      Tessell::Kit::Modifiers.new(ctrl: true)), ctx).should be_true
    text = clipboard.get
    text.should_not be_nil
    text.not_nil!.lines.first.split('\t')[0].should eq("Tessell Quarterly Budget")
    text.not_nil!.lines.first.split('\t')[1].should eq("")
  end

  it "pastes TSV into the active cell and expands the selection" do
    clipboard = Tessell::Kit::MemoryClipboard.new("x\ty\n1\t2")
    grid = SheetSpecHelpers.grid(SheetDemo::Sheet.new(20, 8), clipboard)
    ctx = SheetSpecHelpers.context
    grid.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::KeyV,
      Tessell::Kit::Modifiers.new(ctrl: true)), ctx).should be_true
    grid.sheet.raw(0, 0).should eq("x")
    grid.sheet.raw(0, 1).should eq("y")
    grid.sheet.raw(1, 0).should eq("1")
    grid.sheet.raw(1, 1).should eq("2")
    grid.selection_bounds.should eq({0, 1, 0, 1})
  end

  it "clears a selection with Delete" do
    grid = SheetSpecHelpers.grid
    ctx = SheetSpecHelpers.context
    grid.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Delete), ctx)
    grid.sheet.raw(0, 0).should eq("")
  end
end

describe "SheetDemo::SheetGrid painting" do
  it "paints headers, cells and scrollbars without leaking clips" do
    grid = SheetSpecHelpers.grid
    painter = Tessell::Kit::PaintListPainter.new
    grid.paint(painter, SheetSpecHelpers.context)
    painter.list.clip_depth.should eq(0)
    painter.list.size.should be > 20
  end

  it "paints in dark theme and stays clip balanced" do
    grid = SheetSpecHelpers.grid
    painter = Tessell::Kit::PaintListPainter.new
    grid.paint(painter, SheetSpecHelpers.context(Tessell::Kit::Theme.dark))
    painter.list.clip_depth.should eq(0)
  end

  it "changes its paint token when the active cell changes" do
    grid = SheetSpecHelpers.grid
    before = grid.paint_token
    ctx = SheetSpecHelpers.context
    grid.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Right), ctx)
    grid.paint_token.should_not eq(before)
  end
end
