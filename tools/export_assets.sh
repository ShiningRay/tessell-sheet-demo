#!/usr/bin/env bash
# Regenerate README screenshots with the real SDL2/OpenGL window.
# Usage: tools/export_assets.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LINK=()
if [[ "$(uname -s)" == "Darwin" ]]; then
  LINK=(--link-flags "-L/opt/homebrew/lib")
fi

mkdir -p bin
crystal build src/tessell_sheet_demo.cr -o bin/sheet_demo "${LINK[@]}"

render() {
  local name="$1"; shift
  ./bin/sheet_demo --frames=3 --screenshot="bin/$name.png" "$@" >/dev/null
  sips -Z 1180 "bin/$name.png" --out "assets/$name.png" >/dev/null
}

render sheet-light
render sheet-dark --theme=dark
render sheet-selection --scenario=selection
render sheet-editing --scenario=editing
render sheet-scrolled --scenario=scrolled
render sheet-debug --scenario=debug
echo "assets updated"
