# SDL2 + OpenGL host for Tessell Sheet.
#
# This file is a copy of tessell/examples/lib/kit_sdl_host.cr adapted for this
# demo. The framework still has no published optional platform host, so every
# app has to own this boilerplate. See docs/friction-log.md and the GitHub
# issues linked from the README.
require "tessell/kit"
require "tessell/render/gl/gl_backend"
require "tessell/render/text_renderer"
require "tessell/text/ft_measurer"
require "tessell/text/measurer"
require "tessell/text/glyph_atlas"
require "tessell/text/rasterizer"
require "../sheet_demo"
require "tessell/tools/lib/png"

module SheetDemo
  @[Link("SDL2")]
  lib LibSDL
    struct Keysym
      scancode : Int32
      sym : Int32
      mod : UInt16
      unused : UInt32
    end

    struct KeyboardEvent
      type : UInt32
      timestamp : UInt32
      window_id : UInt32
      state : UInt8
      repeat : UInt8
      padding2 : UInt8
      padding3 : UInt8
      keysym : Keysym
    end

    struct TextInputEvent
      type : UInt32
      timestamp : UInt32
      window_id : UInt32
      text : StaticArray(UInt8, 32)
    end

    struct MouseMotionEvent
      type : UInt32
      timestamp : UInt32
      window_id : UInt32
      which : UInt32
      state : UInt32
      x : Int32
      y : Int32
      xrel : Int32
      yrel : Int32
    end

    struct MouseButtonEvent
      type : UInt32
      timestamp : UInt32
      window_id : UInt32
      which : UInt32
      button : UInt8
      state : UInt8
      clicks : UInt8
      padding1 : UInt8
      x : Int32
      y : Int32
    end

    struct MouseWheelEvent
      type : UInt32
      timestamp : UInt32
      window_id : UInt32
      which : UInt32
      x : Int32
      y : Int32
      direction : UInt32
      precise_x : Float32
      precise_y : Float32
      mouse_x : Int32
      mouse_y : Int32
    end

    struct WindowEvent
      type : UInt32
      timestamp : UInt32
      window_id : UInt32
      event : UInt8
      padding1 : UInt8
      padding2 : UInt8
      padding3 : UInt8
      data1 : Int32
      data2 : Int32
    end

    struct Event
      type : UInt32
      padding : StaticArray(UInt8, 52)
    end

    fun SDL_Init(flags : UInt32) : Int32
    fun SDL_Quit : Void
    fun SDL_GetError : UInt8*
    fun SDL_CreateWindow(title : UInt8*, x : Int32, y : Int32,
                         w : Int32, h : Int32, flags : UInt32) : Void*
    fun SDL_DestroyWindow(window : Void*) : Void
    fun SDL_GetWindowSize(window : Void*, w : Int32*, h : Int32*) : Void
    fun SDL_GL_SetAttribute(attr : Int32, value : Int32) : Int32
    fun SDL_GL_CreateContext(window : Void*) : Void*
    fun SDL_GL_DeleteContext(context : Void*) : Void
    fun SDL_GL_MakeCurrent(window : Void*, context : Void*) : Int32
    fun SDL_GL_SetSwapInterval(interval : Int32) : Int32
    fun SDL_GL_SwapWindow(window : Void*) : Void
    fun SDL_GL_GetDrawableSize(window : Void*, w : Int32*, h : Int32*) : Void
    fun SDL_PollEvent(event : Event*) : Int32
    fun SDL_StartTextInput : Void
    fun SDL_StopTextInput : Void
    fun SDL_Delay(ms : UInt32) : Void
    fun SDL_GetTicks : UInt32
    fun SDL_GetClipboardText : UInt8*
    fun SDL_SetClipboardText(text : UInt8*) : Int32
    fun SDL_free(ptr : Void*) : Void
  end

  SDL_INIT_VIDEO           = 0x00000020_u32
  SDL_INIT_EVENTS          = 0x00004000_u32
  SDL_WINDOW_OPENGL        = 0x00000002_u32
  SDL_WINDOW_SHOWN         = 0x00000004_u32
  SDL_WINDOW_RESIZABLE     = 0x00000020_u32
  SDL_WINDOW_ALLOW_HIGHDPI = 0x00002000_u32
  SDL_WINDOWPOS_CENTERED   = 0x2FFF0000_u32

  SDL_QUIT                     = 0x100_u32
  SDL_WINDOWEVENT              = 0x200_u32
  SDL_KEYDOWN                  = 0x300_u32
  SDL_KEYUP                    = 0x301_u32
  SDL_TEXTINPUT                = 0x303_u32
  SDL_MOUSEMOTION              = 0x400_u32
  SDL_MOUSEBUTTONDOWN          = 0x401_u32
  SDL_MOUSEBUTTONUP            = 0x402_u32
  SDL_MOUSEWHEEL               = 0x403_u32
  SDL_WINDOWEVENT_CLOSE        =  0x0E_u32
  SDL_WINDOWEVENT_RESIZED      = 0x201_u32
  SDL_WINDOWEVENT_SIZE_CHANGED = 0x202_u32

  SDL_GL_DOUBLEBUFFER                  =      5_i32
  SDL_GL_DEPTH_SIZE                    =      6_i32
  SDL_GL_STENCIL_SIZE                  =      7_i32
  SDL_GL_CONTEXT_MAJOR_VERSION         =     17_i32
  SDL_GL_CONTEXT_MINOR_VERSION         =     18_i32
  SDL_GL_CONTEXT_PROFILE_MASK          =     21_i32
  SDL_GL_CONTEXT_PROFILE_COMPATIBILITY = 0x0002_i32

  KMOD_SHIFT = 0x0003_u16
  KMOD_CTRL  = 0x00C0_u16
  KMOD_ALT   = 0x0100_u16
  KMOD_GUI   = 0x0400_u16

  SDLK_BACKSPACE =          8
  SDLK_TAB       =          9
  SDLK_RETURN    =         13
  SDLK_ESCAPE    =         27
  SDLK_SPACE     =         32
  SDLK_DELETE    =        127
  SDLK_LEFT      = 0x40000050
  SDLK_RIGHT     = 0x4000004F
  SDLK_UP        = 0x40000052
  SDLK_DOWN      = 0x40000051
  SDLK_HOME      = 0x4000004A
  SDLK_END       = 0x4000004D
  SDLK_PAGEUP    = 0x4000004B
  SDLK_PAGEDOWN  = 0x4000004E
  SDLK_F1        = 0x4000003A
  SDLK_a         =         97
  SDLK_b         =         98
  SDLK_c         =         99
  SDLK_n         =        110
  SDLK_o         =        111
  SDLK_s         =        115
  SDLK_v         =        118
  SDLK_x         =        120
  SDLK_y         =        121
  SDLK_z         =        122

  class SdlClipboard < Tessell::Kit::Clipboard
    def get : String?
      ptr = LibSDL.SDL_GetClipboardText
      return nil if ptr.null?
      text = String.new(ptr)
      LibSDL.SDL_free(ptr.as(Void*))
      text
    end

    def set(text : String) : Nil
      LibSDL.SDL_SetClipboardText(text.to_unsafe)
    end
  end

  class GLPainter < Tessell::Kit::Painter
    getter scale : Float32

    @draw : Tessell::Kit::DrawListPainter
    @renderer : Tessell::Render::TextRenderer
    @renderers : Hash(Int32, Tessell::Render::TextRenderer)
    @atlas : Tessell::Text::GlyphAtlas
    @width : Int32
    @height : Int32
    @sink : Array(Tessell::Text::GlyphPlacement)

    def initialize(@renderer : Tessell::Render::TextRenderer,
                   @atlas : Tessell::Text::GlyphAtlas,
                   @width : Int32, @height : Int32, @scale : Float32,
                   renderers : Hash(Int32, Tessell::Render::TextRenderer)? = nil)
      @draw = Tessell::Kit::DrawListPainter.new
      @sink = [] of Tessell::Text::GlyphPlacement
      @renderers = renderers || {0 => @renderer}
      @renderers[0] ||= @renderer
    end

    def resize(width : Int32, height : Int32, scale : Float32) : Nil
      @width = width
      @height = height
      @scale = scale
    end

    def fill_rect(rect : Tessell::Rect, color : UInt32) : Nil
      @draw.fill_rect(scale_rect(rect), color)
    end

    def stroke_rect(rect : Tessell::Rect, color : UInt32, width : Float32 = 1.0_f32) : Nil
      @draw.stroke_rect(scale_rect(rect), color, width * @scale)
    end

    def fill_round_rect(rect : Tessell::Rect, radius : Float32, color : UInt32) : Nil
      @draw.fill_round_rect(scale_rect(rect), radius * @scale, color)
    end

    def stroke_round_rect(rect : Tessell::Rect, radius : Float32, color : UInt32,
                          width : Float32 = 1.0_f32) : Nil
      @draw.stroke_round_rect(scale_rect(rect), radius * @scale, color, width * @scale)
    end

    def line(x1 : Float32, y1 : Float32, x2 : Float32, y2 : Float32,
             color : UInt32, width : Float32 = 1.0_f32) : Nil
      @draw.line(x1 * @scale, y1 * @scale, x2 * @scale, y2 * @scale,
        color, width * @scale)
    end

    # font_id 来自 Kit 的 FontWeight→face 解析（issue #29）。宿主为每个 face
    # 建一个 TextRenderer；单 face 时只有 id 0。
    # 命令里的坐标/字号保持逻辑单位（Painter 契约）——与 fill_rect 等原语
    # 一致；设备像素换算统一在 flush 里做一次，避免双重缩放。
    def text(x : Float32, baseline_y : Float32, text : String,
             color : UInt32, size : Float32, font_id : Int32 = 0) : Nil
      @draw.text(x, baseline_y, text, color, size, font_id)
    end

    def push_clip(rect : Tessell::Rect) : Nil
      @draw.push_clip(scale_rect(rect))
    end

    def pop_clip : Nil
      @draw.pop_clip
    end

    # Painter 契约要求实现 image（issue #28）。GLBackend 尚未实现外部纹理
    # 通道（create_texture 走基类返回 0），所以这里显式失败而不是静默跳过：
    # 静默 no-op 会让"图没显示"变成难查的空现象。
    def image(texture_id : Int32, bounds : Tessell::Rect,
              tint : UInt32 = 0xffffffff_u32, src : Tessell::Rect? = nil) : Nil
      raise "GLPainter#image: GLBackend has no external texture channel yet " \
            "(texture_id=#{texture_id}); see tessell issue about create_texture"
    end

    # 单遍遍历命令列表即可（issue #21）：Text 命令自带文本/字号/font_id/clip。
    # 形状段连续提交；遇到 Text 就地 shape、增量同步 atlas（未变化即 no-op，
    # issue #22），再提交该命令自己的批次并按 clip scissor。
    def flush(backend : Tessell::Render::Backend) : Nil
      list = @draw.list
      seg = 0
      i = 0
      while i < list.size
        cmd = list[i]
        if cmd.kind == Tessell::Render::CmdKind::Text
          backend.draw_draw_list(list, seg, i - seg) if i > seg
          renderer = @renderers[cmd.atlas_id]? || @renderer
          before = renderer.batch_count
          # DrawCmd 存的是逻辑单位（Painter 契约），shape 需要设备像素。
          px_size = (cmd.font_size * @scale).round.to_i
          if px_size > 0
            renderer.append_text_cached(@sink, cmd.text,
              cmd.bounds.origin.x * @scale, cmd.bounds.origin.y * @scale,
              px_size, @width, @height, cmd.color)
          end
          after = renderer.batch_count
          if after > before
            backend.sync_atlas_dirty(@atlas)
            # draw_text 的 batch_count 是开区间上界（[from, batch_count)），
            # 不是增量条数——传 delta 会重复绘制已有批次。
            # cmd.clip 已在 push_clip 里换算成设备像素（与形状命令同源），
            # scissor_params 不再缩放——这里原样传。
            backend.draw_text(renderer.vertices, renderer.batch_runs, after, before, cmd.clip)
          end
          seg = i + 1
        end
        i += 1
      end
      backend.draw_draw_list(list, seg, list.size - seg) if list.size > seg
      @draw.reset
      @renderer.reset
      @renderers.each_value(&.reset)
    end

    def clip_depth : Int32
      @draw.clip_depth
    end

    private def scale_rect(rect : Tessell::Rect) : Tessell::Rect
      Tessell::Rect.new(rect.origin.x * @scale, rect.origin.y * @scale,
        rect.size.width * @scale, rect.size.height * @scale)
    end
  end

  abstract class SdlDemoHost
    getter app : SheetApp

    def initialize(@app : SheetApp)
    end

    abstract def title : String

    def width : Int32
      1180
    end

    def height : Int32
      760
    end

    def run(args : Array(String)) : Nil
      frames_limit = 0
      screenshot_path : String? = nil
      scenario = ""
      args.each do |arg|
        if arg.starts_with?("--frames=")
          frames_limit = arg.split("=", 2)[1].to_i
        elsif arg.starts_with?("--screenshot=")
          screenshot_path = arg.split("=", 2)[1]
        elsif arg.starts_with?("--open=")
          @app.file_path = arg.split("=", 2)[1]
          @app.open
        elsif arg == "--theme=dark"
          @app.set_theme(true)
        elsif arg == "--theme=light"
          @app.set_theme(false)
        elsif arg.starts_with?("--scenario=")
          scenario = arg.split("=", 2)[1]
        end
      end

      unless LibSDL.SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) == 0
        STDERR.puts "SDL_Init failed: #{String.new(LibSDL.SDL_GetError)}"
        exit 1
      end

      LibSDL.SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1)
      LibSDL.SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 0)
      LibSDL.SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8)
      LibSDL.SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2)
      LibSDL.SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1)
      LibSDL.SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK,
        SDL_GL_CONTEXT_PROFILE_COMPATIBILITY)

      window = LibSDL.SDL_CreateWindow(title.to_unsafe,
        SDL_WINDOWPOS_CENTERED.to_i32, SDL_WINDOWPOS_CENTERED.to_i32,
        width, height, SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN |
                       SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI)
      if window.null?
        STDERR.puts "SDL_CreateWindow failed: #{String.new(LibSDL.SDL_GetError)}"
        LibSDL.SDL_Quit
        exit 1
      end

      context = LibSDL.SDL_GL_CreateContext(window)
      if context.null?
        STDERR.puts "SDL_GL_CreateContext failed: #{String.new(LibSDL.SDL_GetError)}"
        LibSDL.SDL_DestroyWindow(window)
        LibSDL.SDL_Quit
        exit 1
      end
      LibSDL.SDL_GL_MakeCurrent(window, context)
      LibSDL.SDL_GL_SetSwapInterval(1)
      LibSDL.SDL_StartTextInput

      logical_w = 0
      logical_h = 0
      drawable_w = 0
      drawable_h = 0
      update_sizes(window, pointerof(logical_w), pointerof(logical_h),
        pointerof(drawable_w), pointerof(drawable_h))
      scale = device_scale(logical_w, drawable_w)

      ft_measurer = load_measurer
      measurer = Tessell::Text::CachingMeasurer.new(ft_measurer)
      atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
      rasterizer = Tessell::Text::Rasterizer.new(ft_measurer, atlas, 0, 4096)
      renderer = Tessell::Render::TextRenderer.new(atlas, rasterizer)
      renderer.reserve_quads(16384)
      renderer.reserve_batches(256)

      backend = Tessell::Render::GL::GLBackend.new
      backend.init(drawable_w, drawable_h)
      backend.resize(drawable_w, drawable_h)

      clipboard = SdlClipboard.new
      # Context#measure_text returns logical units since tessell 0.2.0
      # (issue #14); no host-side divide-by-scale adapter is needed.
      metrics = Tessell::Kit::CoreTextMetrics.new(measurer, 0)
      root = @app.build_root(metrics, clipboard, scale)
      root.layout(logical_w.to_f32, logical_h.to_f32)
      root.build
      @app.on_root_ready(root)

      painter = GLPainter.new(renderer, atlas, drawable_w, drawable_h, scale)
      @root = root
      @window = window
      @mouse_x = 0
      @mouse_y = 0

      # Platform-neutral frame loop (tessell 0.2.0, issue #3).
      runner = Tessell::App::Runner.new
      runner.frames_limit = frames_limit
      frames = 0
      last_ticks = LibSDL.SDL_GetTicks.to_i64
      quit = false
      until quit
        quit = pump_events(root)
        break if quit

        # F1 debug overlay (issue #11): Root handles the toggle, the host
        # just supplies stats once per frame.
        now = LibSDL.SDL_GetTicks.to_i64
        root.debug_info = Tessell::Kit::DebugInfo.collect(backend.stats, atlas, root,
          (now - last_ticks).to_f32)
        last_ticks = now

        if @resize_pending
          update_sizes(window, pointerof(logical_w), pointerof(logical_h),
            pointerof(drawable_w), pointerof(drawable_h))
          new_scale = device_scale(logical_w, drawable_w)
          if new_scale == scale
            root.layout(logical_w.to_f32, logical_h.to_f32)
          else
            # 跨 DPI 拖动/缩放（issue #30）：Root#scale= 清文本测量缓存并重排，
            # 焦点、编辑态、滚动位置全部保留——不再重建 Root。
            scale = new_scale
            root.scale = new_scale
            root.layout(logical_w.to_f32, logical_h.to_f32)
          end
          root.build
          backend.resize(drawable_w, drawable_h)
          painter.resize(drawable_w, drawable_h, scale)
          @resize_pending = false
        end

        if frames == 1 && !scenario.empty?
          run_scenario(root, scenario)
        end

        root.advance_time(LibSDL.SDL_GetTicks.to_i64)
        root.build

        backend.begin_frame(nil, @app.current_theme.to_render)
        root.paint(painter)
        painter.flush(backend)
        backend.end_frame

        if path = screenshot_path
          if frames_limit == 0 || runner.frame_count + 1 >= frames_limit
            if path.ends_with?(".png")
              capture_png(path, drawable_w, drawable_h)
            else
              capture_ppm(path, drawable_w, drawable_h)
            end
            screenshot_path = nil
          end
        end

        LibSDL.SDL_GL_SwapWindow(window)

        frames += 1
        # Runner owns frames_limit / stop() (issue #3).
        break if runner.advance(LibSDL.SDL_GetTicks.to_i64)
        LibSDL.SDL_Delay(8)
      end

      LibSDL.SDL_StopTextInput
      LibSDL.SDL_GL_DeleteContext(context)
      LibSDL.SDL_DestroyWindow(window)
      LibSDL.SDL_Quit
      puts "SHEET_DEMO_RUN frames=#{frames} size=#{logical_w}x#{logical_h} scale=#{scale}"
    end

    @root : Tessell::Kit::Root?
    @window : Void* = Pointer(Void).null
    @mouse_x : Int32 = 0
    @mouse_y : Int32 = 0
    @resize_pending : Bool = false

    # Deterministic driver used for README screenshots and routing smoke tests.
    # Events go through Root#handle, i.e. the real hit-test/focus path, not a
    # direct call into the grid.
    private def run_scenario(root : Tessell::Kit::Root, scenario : String) : Nil
      grid = @app.grid
      case scenario
      when "selection"
        point = grid.cell_center(3, 1)
        click_point(root, point.x, point.y)
        edge = grid.cell_center(7, 4)
        root.handle(Tessell::Input::Event.pointer_move(edge.x, edge.y))
        shift_key(root, Tessell::Input::KeyCode::Down)
        shift_key(root, Tessell::Input::KeyCode::Right)
      when "editing"
        point = grid.cell_center(5, 1)
        click_point(root, point.x, point.y)
        root.handle(Tessell::Input::Event.text_input("=(C4+C5)/2"))
      when "debug"
        root.handle(Tessell::Input::Event.key_down(Tessell::Input::KeyCode::F1))
        point = grid.cell_center(3, 1)
        root.handle(Tessell::Input::Event.pointer_move(point.x, point.y))
      when "scrolled"
        6.times do
          root.handle(Tessell::Input::Event.wheel(
            grid.bounds.origin.x + 300.0_f32, grid.bounds.origin.y + 300.0_f32,
            0.0_f32, -120.0_f32))
        end
        root.handle(Tessell::Input::Event.wheel(
          grid.bounds.origin.x + 300.0_f32, grid.bounds.origin.y + 300.0_f32,
          600.0_f32, 0.0_f32))
      end
      @app.refresh
    end

    private def click_point(root : Tessell::Kit::Root, x : Float32, y : Float32) : Nil
      root.handle(Tessell::Input::Event.pointer_move(x, y))
      root.handle(Tessell::Input::Event.pointer_down(x, y))
      root.handle(Tessell::Input::Event.pointer_up(x, y))
    end

    private def shift_key(root : Tessell::Kit::Root, key : Tessell::Input::KeyCode) : Nil
      root.handle(Tessell::Input::Event.key_down(key,
        Tessell::Input::Modifiers.new(shift: true)))
    end

    # PNG screenshot (issue #9): uses the upstream writer shipped at
    # tessell/tools/lib/png.cr (reachable through the shard require path).
    private def capture_png(path : String, width : Int32, height : Int32) : Nil
      return if width <= 0 || height <= 0
      rgba = Bytes.new(width * height * 4)
      TessellGL.glFinish
      TessellGL.glPixelStorei(TessellGL::GL_PACK_ALIGNMENT, 1)
      TessellGL.glReadPixels(0, 0, width, height, TessellGL::GL_RGBA,
        TessellGL::GL_UNSIGNED_BYTE, rgba.to_unsafe.as(Void*))
      top_down = Bytes.new(width * height * 4)
      row = width * 4
      y = 0
      while y < height
        src = (height - 1 - y) * row
        dst = y * row
        (top_down.to_unsafe + dst).copy_from(rgba.to_unsafe + src, row)
        y += 1
      end
      TessellPNG.write(path, width, height, top_down)
    end

    private def capture_ppm(path : String, width : Int32, height : Int32) : Nil
      return if width <= 0 || height <= 0
      dir = File.dirname(path)
      Dir.mkdir_p(dir) unless dir.empty? || Dir.exists?(dir)
      rgba = Bytes.new(width * height * 4)
      TessellGL.glFinish
      TessellGL.glPixelStorei(TessellGL::GL_PACK_ALIGNMENT, 1)
      TessellGL.glReadPixels(0, 0, width, height, TessellGL::GL_RGBA,
        TessellGL::GL_UNSIGNED_BYTE, rgba.to_unsafe.as(Void*))
      rgb = Bytes.new(width * height * 3)
      y = 0
      while y < height
        src_row = (height - 1 - y) * width * 4
        dst_row = y * width * 3
        x = 0
        while x < width
          si = src_row + x * 4
          di = dst_row + x * 3
          rgb[di] = rgba[si]
          rgb[di + 1] = rgba[si + 1]
          rgb[di + 2] = rgba[si + 2]
          x += 1
        end
        y += 1
      end
      File.open(path, "wb") do |io|
        io << "P6\n#{width} #{height}\n255\n"
        io.write(rgb)
      end
      puts "SHEET_DEMO_SCREENSHOT path=#{path} size=#{width}x#{height}"
    end

    private def update_sizes(window : Void*, lw : Int32*, lh : Int32*,
                             dw : Int32*, dh : Int32*) : Nil
      LibSDL.SDL_GetWindowSize(window, lw, lh)
      LibSDL.SDL_GL_GetDrawableSize(window, dw, dh)
      lw.value = 1 if lw.value <= 0
      lh.value = 1 if lh.value <= 0
      dw.value = lw.value if dw.value <= 0
      dh.value = lh.value if dh.value <= 0
    end

    private def device_scale(logical_w : Int32, drawable_w : Int32) : Float32
      return 1.0_f32 if logical_w <= 0
      (drawable_w.to_f32 / logical_w.to_f32).clamp(1.0_f32, 4.0_f32)
    end

    private def load_measurer : Tessell::Text::FtMeasurer
      candidates = [] of String
      if path = ENV["TESSELL_FONT"]?
        candidates << path
      end
      {% if flag?(:darwin) %}
        candidates << "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"
        candidates << "/System/Library/Fonts/Supplemental/Arial.ttf"
      {% elsif flag?(:windows) %}
        candidates << "C:/Windows/Fonts/msyh.ttc"
        candidates << "C:/Windows/Fonts/arial.ttf"
      {% else %}
        candidates << "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
      {% end %}
      candidates.each do |path|
        return Tessell::Text::FtMeasurer.open(path, 0) if File.exists?(path)
      end
      raise "no usable font found; set TESSELL_FONT to a TTF/TTC path"
    end

    private def pump_events(root : Tessell::Kit::Root) : Bool
      event = uninitialized LibSDL::Event
      while LibSDL.SDL_PollEvent(pointerof(event)) != 0
        case event.type
        when SDL_QUIT
          return true
        when SDL_WINDOWEVENT
          window_event = pointerof(event).as(LibSDL::WindowEvent*).value
          if window_event.event == SDL_WINDOWEVENT_CLOSE
            return true
          elsif window_event.event == SDL_WINDOWEVENT_RESIZED ||
                window_event.event == SDL_WINDOWEVENT_SIZE_CHANGED
            @resize_pending = true
          end
        when SDL_KEYDOWN
          key = pointerof(event).as(LibSDL::KeyboardEvent*).value
          mods = modifiers(key.keysym.mod)
          if (mods.meta || mods.ctrl) && (char = shortcut_char(key.keysym.sym))
            @app.handle_shortcut(char)
            next
          end
          if code = map_key(key.keysym.sym)
            dispatch(root, Tessell::Input::Event.key_down(code, mods,
              key.timestamp.to_i64, key.repeat != 0))
          end
        when SDL_KEYUP
          key = pointerof(event).as(LibSDL::KeyboardEvent*).value
          if code = map_key(key.keysym.sym)
            dispatch(root, Tessell::Input::Event.new(Tessell::Input::Event::Kind::KeyUp,
              0.0_f32, 0.0_f32, 0, code, nil, modifiers(key.keysym.mod),
              timestamp_ms: key.timestamp.to_i64))
          end
        when SDL_TEXTINPUT
          text_event = pointerof(event).as(LibSDL::TextInputEvent*).value
          dispatch(root, Tessell::Input::Event.text_input(
            String.new(text_event.text.to_unsafe), timestamp_ms: text_event.timestamp.to_i64))
        when SDL_MOUSEMOTION
          motion = pointerof(event).as(LibSDL::MouseMotionEvent*).value
          @mouse_x = motion.x
          @mouse_y = motion.y
          dispatch(root, Tessell::Input::Event.new(Tessell::Input::Event::Kind::PointerMove,
            motion.x.to_f32, motion.y.to_f32, 0, nil, nil, Tessell::Input::Modifiers.none,
            timestamp_ms: motion.timestamp.to_i64))
        when SDL_MOUSEBUTTONDOWN
          button = pointerof(event).as(LibSDL::MouseButtonEvent*).value
          @mouse_x = button.x
          @mouse_y = button.y
          # SDL 的时间戳必须透传：Router 的双击/拖拽判定只认事件时间戳，
          # 传 0 会让双击永不成立（issue #20 的 click_count 恒为 1）。
          dispatch(root, Tessell::Input::Event.pointer_down(
            button.x.to_f32, button.y.to_f32, button.button.to_i32 - 1,
            timestamp_ms: button.timestamp.to_i64))
        when SDL_MOUSEBUTTONUP
          button = pointerof(event).as(LibSDL::MouseButtonEvent*).value
          @mouse_x = button.x
          @mouse_y = button.y
          dispatch(root, Tessell::Input::Event.pointer_up(
            button.x.to_f32, button.y.to_f32, button.button.to_i32 - 1,
            timestamp_ms: button.timestamp.to_i64))
        when SDL_MOUSEWHEEL
          wheel = pointerof(event).as(LibSDL::MouseWheelEvent*).value
          dispatch(root, Tessell::Input::Event.wheel(@mouse_x.to_f32,
            @mouse_y.to_f32, wheel.x.to_f32 * 40.0_f32,
            wheel.y.to_f32 * 40.0_f32))
        end
      end
      false
    end

    private def dispatch(root : Tessell::Kit::Root, event : Tessell::Input::Event) : Nil
      return if @app.handle_app_event(event)
      root.handle(event)
    end

    private def shortcut_char(sym : Int32) : Char?
      case sym
      when SDLK_s then 's'
      when SDLK_o then 'o'
      when SDLK_n then 'n'
      when SDLK_y then 'y'
      else             nil
      end
    end

    private def modifiers(mod : UInt16) : Tessell::Input::Modifiers
      Tessell::Input::Modifiers.new(
        shift: (mod & KMOD_SHIFT) != 0,
        ctrl: (mod & KMOD_CTRL) != 0,
        alt: (mod & KMOD_ALT) != 0,
        meta: (mod & KMOD_GUI) != 0)
    end

    private def map_key(sym : Int32) : Tessell::Input::KeyCode?
      case sym
      when SDLK_ESCAPE    then Tessell::Input::KeyCode::Escape
      when SDLK_RETURN    then Tessell::Input::KeyCode::Enter
      when SDLK_BACKSPACE then Tessell::Input::KeyCode::Backspace
      when SDLK_TAB       then Tessell::Input::KeyCode::Tab
      when SDLK_DELETE    then Tessell::Input::KeyCode::Delete
      when SDLK_SPACE     then Tessell::Input::KeyCode::Space
      when SDLK_LEFT      then Tessell::Input::KeyCode::Left
      when SDLK_RIGHT     then Tessell::Input::KeyCode::Right
      when SDLK_UP        then Tessell::Input::KeyCode::Up
      when SDLK_DOWN      then Tessell::Input::KeyCode::Down
      when SDLK_HOME      then Tessell::Input::KeyCode::Home
      when SDLK_END       then Tessell::Input::KeyCode::End
      when SDLK_PAGEUP    then Tessell::Input::KeyCode::PageUp
      when SDLK_PAGEDOWN  then Tessell::Input::KeyCode::PageDown
      when SDLK_a         then Tessell::Input::KeyCode::KeyA
      when SDLK_b         then Tessell::Input::KeyCode::KeyB
      when SDLK_c         then Tessell::Input::KeyCode::KeyC
      when SDLK_v         then Tessell::Input::KeyCode::KeyV
      when SDLK_x         then Tessell::Input::KeyCode::KeyX
      when SDLK_z         then Tessell::Input::KeyCode::KeyZ
      when SDLK_F1        then Tessell::Input::KeyCode::F1
      else
        nil
      end
    end
  end
end
