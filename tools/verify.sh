#!/usr/bin/env bash
# Type-checks and format-checks src/ without Studio (cloud sessions).
# Needs rojo, luau-lsp and stylua 2.0.2 on PATH (or in $TOOLS), and
# globalTypes.d.luau (from the luau-lsp repo's scripts/ folder) in $TOOLS or here.
set -euo pipefail
cd "$(dirname "$0")/.."
TOOLS="${TOOLS:-}"
bin() { if [[ -n "$TOOLS" && -x "$TOOLS/$1" ]]; then echo "$TOOLS/$1"; else command -v "$1"; fi; }
DEFS="${TOOLS:+$TOOLS/}globalTypes.d.luau"
MAP="$(mktemp -t sourcemap.XXXX.json)"
"$(bin rojo)" sourcemap default.project.json -o "$MAP"
"$(bin luau-lsp)" analyze --definitions="$DEFS" --sourcemap="$MAP" --ignore="**/Packages/**" src
"$(bin stylua)" --check src --glob '!**/Packages/**'
echo "verify: OK"
