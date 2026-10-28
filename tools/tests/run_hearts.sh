#!/usr/bin/env bash
# Checks Shared/Hearts (den hearts: once a UTC day per den, the day turning over, the
# Best Dens frame's week, the signs' counts) with the plain luau CLI: copies it to a
# temp folder and runs hearts_test.luau. Needs `luau` on PATH (or LUAU=/path/to/luau).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../../src/shared"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp "$src/Hearts.luau" "$here/hearts_test.luau" "$tmp/"
cd "$tmp" && "${LUAU:-luau}" hearts_test.luau
