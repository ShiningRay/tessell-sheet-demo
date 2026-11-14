require "./spec_helper"
require "tessell/render/software_backend"

# Pixel-level checks with the CPU backend (tessell 0.2.0, issue #10).
# The grid paints through Kit::DrawListPainter into a DrawList; SoftwareBackend
# executes it without a window or GPU. Text commands are skipped by the
# software draw_draw_list, which is fine here: these assertions are about
# fills, grid lines, selection and clip boundaries.
private def render_grid(grid : SheetDemo::SheetGrid,
                        ctx : Tessell::Kit::Context,
                        width : Int32, height : Int32) : Tessell::Render::SoftwareBackend
  backend = Tessell::Render::SoftwareBackend.new
  backend.init(width, height)
  backend.begin_frame(nil, ctx.theme.to_render)
  painter = Tessell::Kit::DrawListPainter.new
  grid.paint(painter, ctx)
  backend.draw_draw_list(painter.list)
  backend.end_frame
  backend
end

describe "SheetDemo::SheetGrid software rendering" do
  it "fills the selection with the theme selection colour" do
    grid = SheetSpecHelpers.grid
    ctx = SheetSpecHelpers.context
    rgb = ctx.theme.palette.selection
    # A1 is the active cell (painted with surface); B1 is inside the
    # one-cell-wide selection only after extending right.
    shift_right = Tessell::Kit::Event.key_down(Tessell::Kit::Key::Right,
      Tessell::Kit::Modifiers.new(shift: true))
    grid.handle(shift_right, ctx)
    backend = render_grid(grid, ctx, 900, 560)
    cell = grid.cell_rect(0, 0)
    backend.pixel((cell.origin.x + 4).to_i, (cell.origin.y + 4).to_i).should eq(rgb)
  end

  it "keeps the body clip from painting over the row header" do
    grid = SheetSpecHelpers.grid
    ctx = SheetSpecHelpers.context
    gradient = grid.cell_rect(0, 0)
    backend = render_grid(grid, ctx, 900, 560)
    # left of the body is the frozen row header: surface_raised, never cell white
    header_x = (gradient.origin.x - 8.0_f32).to_i
    header_y = (gradient.origin.y + 4.0_f32).to_i
    backend.pixel(header_x, header_y).should_not eq(ctx.theme.palette.surface)
  end

  it "renders dark theme surface and header" do
    grid = SheetSpecHelpers.grid
    ctx = SheetSpecHelpers.context(Tessell::Kit::Theme.dark)
    backend = render_grid(grid, ctx, 900, 560)
    backend.pixel(2, 2).should eq(ctx.theme.palette.surface_raised)
    cell = grid.cell_rect(1, 1)
    backend.pixel((cell.origin.x + 6).to_i, (cell.origin.y + 6).to_i)
      .should eq(ctx.theme.palette.surface)
  end

  it "shows the active cell border in the focus colour" do
    grid = SheetSpecHelpers.grid
    ctx = SheetSpecHelpers.context
    backend = render_grid(grid, ctx, 900, 560)
    cell = grid.cell_rect(0, 0)
    # border is 2px wide, drawn inside the cell edge
    backend.pixel(cell.origin.x.to_i + 1, (cell.origin.y + cell.size.height / 2.0_f32).to_i)
      .should eq(ctx.theme.palette.focus)
  end
end
