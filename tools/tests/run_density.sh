#!/usr/bin/env bash
# How full of prey the sea is and what drawing it costs a client (density_test.luau):
# schools and fish per biome, how often prey is within 100 / 150 studs of a swimming
# fish, and how many prey fish a client moves, waves and keeps built at once.
#   LUAU=/path/to/luau bash tools/tests/run_density.sh
# TEST=jump_test plays SchoolController's move rule frame by frame from busy spots
# and prints how far held fish jump on screen (1080p px) under each variant.
# SRC=<an older src/> measures an older checkout (e.g. `git archive HEAD src | tar -x -C /tmp/old`).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="${SRC:-$here/../../src}"
tmp="$(mktemp -d)"
[[ -n "${KEEP:-}" ]] || trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/Config"
for name in Tuning World Prey Biomes; do
	cp "$src/shared/Config/$name.luau" "$tmp/Config/"
done
cp "$src/shared/Size.luau" "$src/shared/Seafloor.luau" "$src/shared/Schools.luau" "$tmp/"
cp "$here/sim_rbx.luau" "$here/density_test.luau" "$here/jump_test.luau" "$tmp/"
header='local __rbx = require("./sim_rbx"); local Vector3, CFrame, Random, Color3, Enum = __rbx.Vector3, __rbx.CFrame, __rbx.Random, __rbx.Color3, __rbx.Enum'
for f in "$tmp"/Config/*.luau; do
	sed -i "1a ${header//.\/sim_rbx/..\/sim_rbx}" "$f"
done
cat > "$tmp/Config/init.luau" <<'LUA'
return {
	Tuning = require("@self/Tuning"),
	World = require("@self/World"),
	Prey = require("@self/Prey"),
	Biomes = require("@self/Biomes"),
}
LUA
for f in "$tmp/Size.luau" "$tmp/Seafloor.luau" "$tmp/Schools.luau" "$tmp/density_test.luau" "$tmp/jump_test.luau"; do
	sed -i "1a $header" "$f"
	sed -i -E 's/require\(script\.Parent\.([A-Za-z]+)\)/require(".\/\1")/' "$f"
done
cd "$tmp" && "${LUAU:-luau}" "${TEST:-density_test}.luau"
