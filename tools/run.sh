#!/usr/bin/env bash
# Build and run Tessell Sheets with platform link flags.
# Usage:
#   tools/run.sh                    # run
#   tools/run.sh --frames=3 --screenshot=/tmp/sheet.ppm
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/bin"

LINK_FLAGS=()
if [[ "$(uname -s)" == "Darwin" ]]; then
  LINK_FLAGS=(--link-flags "-L/opt/homebrew/lib")
fi

crystal build "$ROOT/src/tessell_sheet_demo.cr" -o "$ROOT/bin/sheet_demo" "${LINK_FLAGS[@]}"
exec "$ROOT/bin/sheet_demo" "$@"
