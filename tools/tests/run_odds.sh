#!/usr/bin/env bash
# Checks Shared/RollOdds with the plain luau CLI: copies Config + RollOdds to a temp
# folder, swaps Roblox requires for path requires, stubs Color3/Vector3/Enum, and
# runs odds_test.luau. Needs `luau` on PATH (or LUAU=/path/to/luau).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../../src/shared"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -r "$src/Config" "$tmp/"
cp "$src/RollOdds.luau" "$here/odds_test.luau" "$tmp/"
sed -i 's/require(script\.Parent\.Config)/require(".\/Config")/' "$tmp/RollOdds.luau"
sed -i -E 's/require\(script\.([A-Za-z]+)\)/require("@self\/\1")/' "$tmp/Config/init.luau"
stub='local __s = setmetatable({}, { __index = function() return 0 end }); local Color3 = { fromRGB = function() return __s end, new = function() return __s end }; local Vector3 = { new = function() return __s end, one = __s, zero = __s }; local Enum = setmetatable({}, { __index = function() return __s end })'
for f in "$tmp"/Config/*.luau; do sed -i "1a $stub" "$f"; done
cd "$tmp" && "${LUAU:-luau}" odds_test.luau
