# Small chrome components around the grid: formula bar, status bar and shell.
require "tessell/kit"
require "./grid"

module SheetDemo
  class FormulaBar < Tessell::Kit::Component
    property address : String
    property content : String

    def initialize(@key : Tessell::UI::UiKey, @address : String = "A1", @content : String = "")
      super(@key)
    end

    def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
      constraints.constrain(Tessell::Size.new(
        constraints.max_width.infinite? ? 600.0_f32 : constraints.max_width,
        30.0_f32
      ))
    end

    def arrange(ctx : Tessell::Kit::Context, bounds : Tessell::Rect) : Nil
      @bounds = bounds
    end

    def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
      b.node(@key, @bounds, paint: paint_token,
        a11y_role: Tessell::A11y::Role::TextField,
        a11y_name: "Formula bar",
        a11y_value: "#{@address} #{@content}",
        a11y_focusable: false,
        a11y_enabled: true)
    end

    def paint(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context) : Nil
      return unless @visible
      palette = ctx.theme.palette
      radius = ctx.theme.metrics.radius_sm
      fs = ctx.theme.font_size(Tessell::Kit::ControlSize::Small)
      p.fill_round_rect(@bounds, radius, palette.surface)
      p.stroke_round_rect(@bounds, radius, palette.border, 1.0_f32)

      address_rect = Tessell::Rect.new(@bounds.origin.x, @bounds.origin.y,
        86.0_f32, @bounds.size.height)
      p.fill_round_rect(address_rect, radius, palette.surface_raised)
      p.line(address_rect.max_x, address_rect.origin.y + 4.0_f32,
        address_rect.max_x, address_rect.max_y - 4.0_f32, palette.border, 1.0_f32)
      address_w = ctx.measure_text(@address, fs).width
      p.text(address_rect.origin.x + (address_rect.size.width - address_w) / 2.0_f32,
        baseline(@bounds, fs), @address, palette.foreground, fs)

      fx_x = address_rect.max_x + 10.0_f32
      p.text(fx_x, baseline(@bounds, fs), "fx", palette.accent, fs)
      content_x = fx_x + 22.0_f32
      max_width = Math.max(0.0_f32, @bounds.max_x - content_x - 8.0_f32)
      p.push_clip(Tessell::Rect.new(content_x, @bounds.origin.y,
        max_width, @bounds.size.height))
      p.text(content_x, baseline(@bounds, fs),
        fit_text(ctx, @content, fs, max_width), palette.foreground, fs)
      p.pop_clip
    end

    def paint_token : UInt32
      hash = @address.hash
      hash = hash &* 1099511628211_u64 ^ @content.hash
      (hash & 0xffffffff_u64).to_u32
    end

    def a11y_name : String
      "Formula bar"
    end

    def a11y_value : String
      "#{@address} #{@content}"
    end

    private def baseline(rect : Tessell::Rect, fs : Float32) : Float32
      rect.origin.y + (rect.size.height + fs) / 2.0_f32 - fs * 0.1_f32
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

  class StatusBar < Tessell::Kit::Component
    property text : String
    property right_text : String

    def initialize(@key : Tessell::UI::UiKey, @text : String = "", @right_text : String = "Tessell Kit")
      super(@key)
    end

    def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
      constraints.constrain(Tessell::Size.new(
        constraints.max_width.infinite? ? 600.0_f32 : constraints.max_width,
        20.0_f32
      ))
    end

    def arrange(ctx : Tessell::Kit::Context, bounds : Tessell::Rect) : Nil
      @bounds = bounds
    end

    def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
      b.node(@key, @bounds, paint: paint_token,
        a11y_role: Tessell::A11y::Role::Text,
        a11y_name: "Status bar",
        a11y_value: "#{@text} #{@right_text}",
        a11y_focusable: false,
        a11y_enabled: true)
    end

    def paint(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context) : Nil
      return unless @visible
      palette = ctx.theme.palette
      fs = ctx.theme.font_size(Tessell::Kit::ControlSize::Small)
      p.line(@bounds.origin.x, @bounds.origin.y,
        @bounds.max_x, @bounds.origin.y, palette.border, 1.0_f32)
      baseline = @bounds.origin.y + (@bounds.size.height + fs) / 2.0_f32 - fs * 0.1_f32
      p.text(@bounds.origin.x, baseline, @text, palette.muted, fs)
      right_w = ctx.measure_text(@right_text, fs).width
      p.text(@bounds.max_x - right_w, baseline, @right_text, palette.muted, fs)
    end

    def paint_token : UInt32
      hash = @text.hash ^ (@right_text.hash &* 31_u64)
      (hash & 0xffffffff_u64).to_u32
    end

    def a11y_name : String
      "Status bar"
    end

    def a11y_value : String
      "#{@text} #{@right_text}"
    end
  end

  class SheetShell < Tessell::Kit::Component
    PADDING        = 12.0_f32
    GAP            =  8.0_f32
    TOOLBAR_HEIGHT = 32.0_f32
    FORMULA_HEIGHT = 30.0_f32
    STATUS_HEIGHT  = 20.0_f32

    getter toolbar : Tessell::Kit::Row
    getter formula : FormulaBar
    getter grid : SheetGrid
    getter status : StatusBar

    def initialize(@key : Tessell::UI::UiKey, @toolbar : Tessell::Kit::Row,
                   @formula : FormulaBar, @grid : SheetGrid, @status : StatusBar)
      super(@key)
      attach(@toolbar)
      attach(@formula)
      attach(@grid)
      attach(@status)
    end

    def measure(ctx : Tessell::Kit::Context, constraints : Tessell::Constraints) : Tessell::Size
      width = constraints.max_width.infinite? ? 1180.0_f32 : constraints.max_width
      height = constraints.max_height.infinite? ? 760.0_f32 : constraints.max_height
      constraints.constrain(Tessell::Size.new(width, height))
    end

    def arrange(ctx : Tessell::Kit::Context, bounds : Tessell::Rect) : Nil
      @bounds = bounds
      inner = Tessell::Kit::Geometry.inset(bounds, PADDING)
      top = inner.origin.y
      @toolbar.arrange(ctx, Tessell::Rect.new(inner.origin.x, top,
        inner.size.width, TOOLBAR_HEIGHT))
      top += TOOLBAR_HEIGHT + GAP
      @formula.arrange(ctx, Tessell::Rect.new(inner.origin.x, top,
        inner.size.width, FORMULA_HEIGHT))
      top += FORMULA_HEIGHT + GAP
      grid_height = Math.max(0.0_f32, inner.max_y - top - STATUS_HEIGHT - GAP)
      @grid.arrange(ctx, Tessell::Rect.new(inner.origin.x, top,
        inner.size.width, grid_height))
      @status.arrange(ctx, Tessell::Rect.new(inner.origin.x, inner.max_y - STATUS_HEIGHT,
        inner.size.width, STATUS_HEIGHT))
    end

    def emit(b : Tessell::UI::Builder, ctx : Tessell::Kit::Context) : Nil
      b.group(@key, @bounds, paint: paint_token,
        a11y_role: Tessell::A11y::Role::Window,
        a11y_name: "Tessell Sheet",
        a11y_focusable: false,
        a11y_enabled: true) do
        @toolbar.emit(b, ctx)
        @formula.emit(b, ctx)
        @grid.emit(b, ctx)
        @status.emit(b, ctx)
      end
    end

    def paint(p : Tessell::Kit::Painter, ctx : Tessell::Kit::Context) : Nil
      return unless @visible
      p.fill_rect(@bounds, ctx.theme.palette.canvas)
      @toolbar.paint(p, ctx)
      @formula.paint(p, ctx)
      @grid.paint(p, ctx)
      @status.paint(p, ctx)
    end

    def collect_components(sink : Array(Tessell::Kit::Component)) : Nil
      sink << self
      @toolbar.collect_components(sink)
      @formula.collect_components(sink)
      @grid.collect_components(sink)
      @status.collect_components(sink)
    end

    def paint_token : UInt32
      0_u32
    end
  end
end
