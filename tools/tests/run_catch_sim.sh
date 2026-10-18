#!/usr/bin/env bash
# How often players meet rare fish (catch_sim.luau): a hunter and a casual player
# swimming each biome on the real school layout (Shared/Schools from Config/Prey),
# the real tide clock (Shared/Tides) and the real spawner (Shared/RareSpawn), with
# the old per-fish rolls as a sanity check, the Catch of the Week, twelve players in
# one biome, and the hours each skin goal takes. Rerun after changing Config/Catch,
# Config/Tides or Config/Prey.
#   LUAU=/path/to/luau bash tools/tests/run_catch_sim.sh
#   HOURS=40 ... (simulated hours per biome and player; default 30)
#   QUICK=1 ... (the Kelp, the Reef and the Ruins only)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="${SRC:-$here/../../src}"
tmp="$(mktemp -d)"
[[ -n "${KEEP:-}" ]] || trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/Config"
for name in Tuning World Prey Biomes Catch Tides; do
	cp "$src/shared/Config/$name.luau" "$tmp/Config/"
done
cp "$src/shared/Size.luau" "$src/shared/Seafloor.luau" "$src/shared/Schools.luau" "$tmp/"
cp "$src/shared/Tides.luau" "$src/shared/Catch.luau" "$src/shared/RareSpawn.luau" "$tmp/"
cp "$here/sim_rbx.luau" "$here/catch_sim.luau" "$tmp/"
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
	Catch = require("@self/Catch"),
	Tides = require("@self/Tides"),
}
LUA
for f in "$tmp"/{Size,Seafloor,Schools,Tides,Catch,RareSpawn,catch_sim}.luau; do
	sed -i "1a $header" "$f"
	sed -i -E 's/require\(script\.Parent\.Config\.([A-Za-z]+)\)/require(".\/Config\/\1")/; s/require\(script\.Parent\.([A-Za-z]+)\)/require(".\/\1")/' "$f"
done
cat > "$tmp/simargs.luau" <<LUA
return { hours = ${HOURS:-30}, quick = ${QUICK:-0} == 1 }
LUA
cd "$tmp" && "${LUAU:-luau}" catch_sim.luau
