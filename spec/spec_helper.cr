require "spec"
require "../src/sheet_demo"

module SheetSpecHelpers
  def self.context(theme : Tessell::Kit::Theme = Tessell::Kit::Theme.light) : Tessell::Kit::Context
    Tessell::Kit::Context.new(theme, Tessell::Kit::StubTextMetrics.new)
  end

  def self.grid(sheet : SheetDemo::Sheet? = nil,
                clipboard : Tessell::Kit::Clipboard = Tessell::Kit::MemoryClipboard.new) : SheetDemo::SheetGrid
    grid = SheetDemo::SheetGrid.new(Tessell::UI::UiKey.root.child(1_u64), sheet || SheetDemo::Sheet.demo, clipboard)
    grid.arrange(context, Tessell::Rect.new(0.0_f32, 0.0_f32, 900.0_f32, 560.0_f32))
    grid
  end
end
