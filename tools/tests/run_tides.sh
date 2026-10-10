#!/usr/bin/env bash
# Checks Shared/Tides and Shared/Catch with the plain luau CLI (like run_odds.sh):
# copies Config, Tides and Catch to a temp folder, swaps Roblox requires for path
# requires, stubs Color3/Vector3/Enum, and runs tides_test.luau. Needs `luau` on
# PATH (or LUAU=/path/to/luau).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../../src/shared"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -r "$src/Config" "$tmp/"
cp "$src/Tides.luau" "$src/Catch.luau" "$here/tides_test.luau" "$tmp/"
sed -i -E 's/require\(script\.Parent\.Config\.([A-Za-z]+)\)/require(".\/Config\/\1")/; s/require\(script\.Parent\.([A-Za-z]+)\)/require(".\/\1")/' "$tmp/Tides.luau" "$tmp/Catch.luau"
sed -i -E 's/require\(script\.([A-Za-z]+)\)/require("@self\/\1")/' "$tmp/Config/init.luau"
for f in "$tmp"/Config/*.luau; do sed -i -E 's/require\(script\.Parent\.([A-Za-z]+)\)/require(".\/\1")/' "$f"; done
stub='local __s = setmetatable({}, { __index = function() return 0 end }); local Color3 = { fromRGB = function() return __s end, new = function() return __s end }; local Vector3 = { new = function() return __s end, one = __s, zero = __s }; local Enum = setmetatable({}, { __index = function() return __s end })'
for f in "$tmp"/Config/*.luau; do sed -i "1a $stub" "$f"; done
cd "$tmp" && "${LUAU:-luau}" tides_test.luau
