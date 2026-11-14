# Executable entry: SDL2/OpenGL window host for the spreadsheet demo.
#
# macOS:
#   crystal run src/tessell_sheet_demo.cr --link-flags "-L/opt/homebrew/lib"
#
# Headless screenshot smoke:
#   crystal run src/tessell_sheet_demo.cr --link-flags "-L/opt/homebrew/lib" -- \
#     --frames=3 --screenshot=assets/screenshot.ppm
require "./sheet_demo"
require "./sheet_demo/sdl_host"

module SheetDemo
  class SheetWindow < SdlDemoHost
    def initialize
      super(SheetApp.new)
    end

    def title : String
      "Tessell Sheets"
    end
  end
end

SheetDemo::SheetWindow.new.run(ARGV)
