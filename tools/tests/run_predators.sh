#!/usr/bin/env bash
# Simulates the AI predators' hunt and strike (src/server/Services/PredatorService)
# in the plain luau CLI against fake services (sim_services.luau): each hunting
# style (Config/Predators `style`) against still, cruising, fleeing, juking,
# looping, dashing, hidden, burrowed and puffed fish of several levels and
# species, plus PredatorService.stun. Prints the table and fails on a broken rule.
#   LUAU=/path/to/luau bash tools/tests/run_predators.sh [PredatorService.luau]
# The optional argument runs another copy of the service; SRC=<an older src/> runs
# an older checkout's Config and shared code too, and BEFORE=1 only prints the table
# (an older service has no stun, burrow or puff to check).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="${SRC:-$here/../../src}"
service="${1:-$src/server/Services/PredatorService.luau}"
tmp="$(mktemp -d)"
[[ -n "${KEEP:-}" ]] || trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/Config"
for name in Tuning World Predators Chum Prey; do
	cp "$src/shared/Config/$name.luau" "$tmp/Config/"
done
cp "$src/shared/Size.luau" "$src/shared/Seafloor.luau" "$src/shared/Format.luau" "$tmp/"
cp "$service" "$tmp/PredatorService.luau"
cp "$here/sim_rbx.luau" "$here/sim_services.luau" "$here/predator_sim.luau" "$tmp/"
if [[ -n "${BEFORE:-}" ]]; then echo 'return { before = true }' > "$tmp/sim_mode.luau"; else echo 'return { before = false }' > "$tmp/sim_mode.luau"; fi
header='local __rbx = require("./sim_rbx"); local Vector3, CFrame, Random, Color3, Enum, game, workspace = __rbx.Vector3, __rbx.CFrame, __rbx.Random, __rbx.Color3, __rbx.Enum, __rbx.game, __rbx.workspace'
for f in "$tmp"/Config/*.luau; do
	sed -i "1a ${header//.\/sim_rbx/..\/sim_rbx}" "$f"
done
cat > "$tmp/Config/init.luau" <<'LUA'
return {
	Tuning = require("@self/Tuning"),
	World = require("@self/World"),
	Predators = require("@self/Predators"),
	Chum = require("@self/Chum"),
	Prey = require("@self/Prey"),
}
LUA
for f in "$tmp/Size.luau" "$tmp/Seafloor.luau" "$tmp/PredatorService.luau"; do
	sed -i "1a $header" "$f"
	sed -i -E 's/require\(script\.Parent\.Config\)/require(".\/Config")/' "$f"
done
sed -i -E \
	-e 's/require\(ReplicatedStorage\.Shared\.Config\.Predators\)/require(".\/Config\/Predators")/' \
	-e 's/require\(ReplicatedStorage\.Shared\.Config\)/require(".\/Config")/' \
	-e 's/require\(ReplicatedStorage\.Shared\.(Size|Seafloor|Format)\)/require(".\/\1")/' \
	-e 's/require\(ReplicatedStorage\.Shared\.([A-Za-z]+)\)/require(".\/sim_services").\1/' \
	-e 's/require\(script\.Parent\.Parent\.([A-Za-z]+)\)/require(".\/sim_services").\1/' \
	-e 's/require\(script\.Parent\.([A-Za-z]+)\)/require(".\/sim_services").\1/' \
	-e 's/^export type/type/' \
	"$tmp/PredatorService.luau"
cd "$tmp" && "${LUAU:-luau}" predator_sim.luau
