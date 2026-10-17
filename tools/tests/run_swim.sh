#!/usr/bin/env bash
# Measures the swim's handling with the plain luau CLI (like run_odds.sh): copies
# Config/Tuning and Shared/Size to a temp folder, swaps the Roblox requires for
# path requires, stubs Color3/Vector3, and runs swim_sim.luau, which prints the old
# and current handling side by side and fails on a broken rule. Needs `luau` on
# PATH (or LUAU=/path/to/luau).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../../src/shared"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp "$src/Config/Tuning.luau" "$src/Size.luau" "$here/swim_sim.luau" "$tmp/"
sed -i 's/require(script\.Parent\.Config)/{ Tuning = require(".\/Tuning") }/' "$tmp/Size.luau"
stub='local __s = setmetatable({}, { __index = function() return 0 end }); local Color3 = { fromRGB = function() return __s end, new = function() return __s end }; local Vector3 = { new = function() return __s end, one = __s, zero = __s }'
sed -i "1a $stub" "$tmp/Tuning.luau" "$tmp/Size.luau"
cd "$tmp" && "${LUAU:-luau}" swim_sim.luau
