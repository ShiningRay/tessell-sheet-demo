# Pure library entry: models, formula engine, grid, shell and app.
# The SDL/OpenGL host lives in ./sheet_demo/sdl_host.cr and is only loaded by
# the executable target, so specs do not link against SDL2.
require "tessell/kit"
require "./sheet_demo/formula"
require "./sheet_demo/sheet"
require "./sheet_demo/grid"
require "./sheet_demo/widgets"
require "./sheet_demo/app"

module SheetDemo
  VERSION = "0.1.0"
end
