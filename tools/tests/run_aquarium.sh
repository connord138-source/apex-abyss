#!/usr/bin/env bash
# Checks Shared/Aquarium with the plain luau CLI (like
# run_tides.sh): copies Config and Aquarium to a temp folder, swaps Roblox
# requires for path requires, stubs Color3/Vector3/Enum, and runs aquarium_test.luau.
# Needs `luau` on PATH (or LUAU=/path/to/luau).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../../src/shared"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -r "$src/Config" "$tmp/"
cp "$src/Aquarium.luau" "$here/aquarium_test.luau" "$tmp/"
sed -i -E 's/require\(script\.Parent\.Config\.([A-Za-z]+)\)/require(".\/Config\/\1")/; s/require\(script\.Parent\.([A-Za-z]+)\)/require(".\/\1")/' "$tmp/Aquarium.luau"
sed -i -E 's/require\(script\.([A-Za-z]+)\)/require("@self\/\1")/' "$tmp/Config/init.luau"
for f in "$tmp"/Config/*.luau; do sed -i -E 's/require\(script\.Parent\.([A-Za-z]+)\)/require(".\/\1")/' "$f"; done
vec='local Vector3 = { new = function(x, y, z) return { X = x or 0, Y = y or 0, Z = z or 0 } end }; Vector3.one = Vector3.new(1, 1, 1); Vector3.zero = Vector3.new(0, 0, 0)'
stub="local __s = setmetatable({}, { __index = function() return 0 end }); local Color3 = { fromRGB = function() return __s end, new = function() return __s end }; $vec; local Enum = setmetatable({}, { __index = function() return __s end })"
for f in "$tmp"/Config/*.luau "$tmp/Aquarium.luau" "$tmp/aquarium_test.luau"; do sed -i "1a $stub" "$f"; done
cd "$tmp" && "${LUAU:-luau}" aquarium_test.luau
