#!/usr/bin/env bash
# How fast a fish levels (progress_sim.luau): a hunter swims out of the hub to the
# biome that suits its level, eats every prey it can swallow on the real school
# layout (Shared/Schools from Config/Prey) and the shelf's filler food
# (Config/Forage), swims home when its Haul is full and banks it, dive after dive.
# It runs the rules before the 2026-10-19 retune (a Haul rate of 0.35 and a size cap
# only) as a check against the PC's PG1 numbers, then the rules in Config/Tuning
# `growth` (Shared/Size haulRate / haulCap), and prints, per level band, minutes per
# dive, levels per dive, coral and Tide Pass XP a minute, and the hours to each level.
# Rerun after changing Config/Tuning `growth`, Config/Prey, Config/Forage, the biomes'
# levels or the size and speed curves.
#   LUAU=/path/to/luau bash tools/tests/run_progress_sim.sh
#   SPECIES=Cuda ... (the fish; default Nibbler)
#   MODE=probe ... (kg eaten a second at each level, for designing the curves)
#   QUICK=1 ... (the new rules only, no old-rules check)
#   STAY=OpenBlue ... (a player who keeps to one biome once its level opens it)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="${SRC:-$here/../../src}"
tmp="$(mktemp -d)"
[[ -n "${KEEP:-}" ]] || trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/Config"
for name in Tuning World Prey Biomes Forage Species Pass Rewards; do
	cp "$src/shared/Config/$name.luau" "$tmp/Config/"
done
cp "$src/shared/Size.luau" "$src/shared/Seafloor.luau" "$src/shared/Schools.luau" "$tmp/"
cp "$here/sim_rbx.luau" "$here/progress_sim.luau" "$tmp/"
header='local __rbx = require("./sim_rbx"); local Vector3, CFrame, Random, Color3, Enum = __rbx.Vector3, __rbx.CFrame, __rbx.Random, __rbx.Color3, __rbx.Enum'
for f in "$tmp"/Config/*.luau; do
	sed -i "1a ${header//.\/sim_rbx/..\/sim_rbx}" "$f"
	sed -i -E 's/require\(script\.Parent\.([A-Za-z]+)\)/require(".\/\1")/' "$f"
done
cat > "$tmp/Config/init.luau" <<'LUA'
return {
	Tuning = require("@self/Tuning"),
	World = require("@self/World"),
	Prey = require("@self/Prey"),
	Biomes = require("@self/Biomes"),
	Forage = require("@self/Forage"),
	Species = require("@self/Species"),
	Pass = require("@self/Pass"),
}
LUA
for f in "$tmp"/{Size,Seafloor,Schools,progress_sim}.luau; do
	sed -i "1a $header" "$f"
	sed -i -E 's/require\(script\.Parent\.Config\.([A-Za-z]+)\)/require(".\/Config\/\1")/; s/require\(script\.Parent\.([A-Za-z]+)\)/require(".\/\1")/' "$f"
done
cat > "$tmp/simargs.luau" <<LUA
return {
	species = "${SPECIES:-Nibbler}",
	mode = "${MODE:-progress}",
	quick = ${QUICK:-0} == 1,
	stay = "${STAY:-}",
}
LUA
cd "$tmp" && "${LUAU:-luau}" progress_sim.luau
