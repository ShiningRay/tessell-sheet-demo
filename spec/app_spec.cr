require "./spec_helper"

private def app : SheetDemo::SheetApp
  SheetDemo::SheetApp.new(File.join(Dir.tempdir, "tessell-sheet-app-spec.csv"))
end

describe "SheetDemo::SheetApp" do
  it "builds a root with toolbar, grid and a11y metadata" do
    sheet_app = app
    root = sheet_app.build_root(Tessell::Kit::StubTextMetrics.new,
      Tessell::Kit::MemoryClipboard.new)
    root.layout(1180.0_f32, 760.0_f32)
    root.build
    sink = [] of Tessell::A11y::Node
    root.a11y_emit(sink)
    sink.any? { |n| n.name == "Sheet grid" }.should be_true
    sink.any? { |n| n.name == "Formula bar" }.should be_true
    sink.count { |n| n.role == Tessell::A11y::Role::Button }.should be >= 10
  end

  it "places the grid below the toolbar and above the status bar" do
    sheet_app = app
    root = sheet_app.build_root(Tessell::Kit::StubTextMetrics.new,
      Tessell::Kit::MemoryClipboard.new)
    root.layout(1180.0_f32, 760.0_f32)
    root.build
    grid = sheet_app.grid.bounds
    toolbar = sheet_app.toolbar.bounds
    status = sheet_app.status.bounds
    grid.origin.y.should be > toolbar.max_y
    grid.max_y.should be < status.origin.y
    grid.origin.x.should eq(toolbar.origin.x)
  end

  it "updates the formula bar with the active cell" do
    sheet_app = app
    root = sheet_app.build_root(Tessell::Kit::StubTextMetrics.new,
      Tessell::Kit::MemoryClipboard.new)
    root.layout(1180.0_f32, 760.0_f32)
    root.build
    sheet_app.formula.address.should eq("A1")
    sheet_app.formula.content.should eq("Tessell Quarterly Budget")
    sheet_app.grid.handle(Tessell::Kit::Event.key_down(Tessell::Kit::Key::Right),
      root.context)
    sheet_app.refresh
    sheet_app.formula.address.should eq("B1")
  end

  it "reports selection aggregates in the status bar" do
    sheet_app = app
    root = sheet_app.build_root(Tessell::Kit::StubTextMetrics.new,
      Tessell::Kit::MemoryClipboard.new)
    root.layout(1180.0_f32, 760.0_f32)
    root.build
    ctrl_a = Tessell::Kit::Event.key_down(Tessell::Kit::Key::KeyA,
      Tessell::Kit::Modifiers.new(ctrl: true))
    sheet_app.grid.handle(ctrl_a, root.context)
    sheet_app.refresh
    sheet_app.status.text.should contain("Selected")
  end

  it "undoes and redoes a cell edit" do
    sheet_app = app
    sheet_app.grid.handle(Tessell::Kit::Event.text_input("999"),
      Tessell::Kit::Context.new)
    sheet_app.grid.commit_edit
    sheet_app.sheet.raw(0, 0).should eq("999")
    sheet_app.undo
    sheet_app.sheet.raw(0, 0).should eq("Tessell Quarterly Budget")
    sheet_app.redo
    sheet_app.sheet.raw(0, 0).should eq("999")
  end

  it "saves and reopens CSV, tracking modified state" do
    path = File.tempname("tessell-sheet-app", ".csv")
    sheet_app = SheetDemo::SheetApp.new(path)
    sheet_app.modified?.should be_false
    sheet_app.sheet.set_raw(0, 0, "edited")
    sheet_app.modified?.should be_true
    sheet_app.save
    sheet_app.modified?.should be_false
    File.exists?(path).should be_true

    other = SheetDemo::SheetApp.new(path)
    other.open
    other.sheet.raw(0, 0).should eq("edited")
    File.delete(path) if File.exists?(path)
  end

  it "inserts and deletes rows with undo" do
    sheet_app = app
    before = sheet_app.sheet.row_count
    sheet_app.insert_row
    sheet_app.sheet.row_count.should eq(before + 1)
    sheet_app.undo
    sheet_app.sheet.row_count.should eq(before)
    sheet_app.delete_row
    sheet_app.sheet.row_count.should eq(before - 1)
  end

  it "switches themes and keeps painting clip-balanced" do
    sheet_app = app
    root = sheet_app.build_root(Tessell::Kit::StubTextMetrics.new,
      Tessell::Kit::MemoryClipboard.new)
    root.layout(1180.0_f32, 760.0_f32)
    root.build
    sheet_app.set_theme(true)
    sheet_app.theme_dark.should be_true
    painter = Tessell::Kit::PaintListPainter.new
    root.paint(painter)
    painter.list.clip_depth.should eq(0)
    sheet_app.set_theme(false)
    sheet_app.theme_dark.should be_false
  end

  it "lets Escape move focus out of the grid to the first toolbar button" do
    sheet_app = app
    root = sheet_app.build_root(Tessell::Kit::StubTextMetrics.new,
      Tessell::Kit::MemoryClipboard.new)
    root.layout(1180.0_f32, 760.0_f32)
    root.build
    root.focus(sheet_app.grid)
    escape = Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Escape)
    sheet_app.handle_app_event(escape).should be_true
    root.focused_component.should eq(sheet_app.first_toolbar_button)
  end

  it "leaves Ctrl+Tab to Root so keyboard users can traverse focus" do
    sheet_app = app
    root = sheet_app.build_root(Tessell::Kit::StubTextMetrics.new,
      Tessell::Kit::MemoryClipboard.new)
    root.layout(1180.0_f32, 760.0_f32)
    root.build
    root.focus(sheet_app.grid)
    ctrl_tab = Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Tab,
      Tessell::Input::Modifiers.new(ctrl: true))
    sheet_app.handle_app_event(ctrl_tab).should be_false
  end

  it "intercepts Tab so the grid can move across cells" do
    sheet_app = app
    root = sheet_app.build_root(Tessell::Kit::StubTextMetrics.new,
      Tessell::Kit::MemoryClipboard.new)
    root.layout(1180.0_f32, 760.0_f32)
    root.build
    root.focus(sheet_app.grid)
    tab = Tessell::Input::Event.key_down(Tessell::Input::KeyCode::Tab)
    sheet_app.handle_app_event(tab).should be_true
    sheet_app.grid.address.should eq("B1")
  end
end
