#!/usr/bin/env bash
# Simulates the AI predators' hunt and strike (src/server/Services/PredatorService)
# in the plain luau CLI against fake services (sim_services.luau) and prints how
# often a telegraphed bite lands on a still, a slow and a dashing fish.
#   LUAU=/path/to/luau bash tools/tests/run_predators.sh [PredatorService.luau]
# The optional argument runs another copy of the service (to compare before/after).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../../src"
service="${1:-$src/server/Services/PredatorService.luau}"
tmp="$(mktemp -d)"
[[ -n "${KEEP:-}" ]] || trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/Config"
for name in Tuning World Predators Chum Prey; do
	cp "$src/shared/Config/$name.luau" "$tmp/Config/"
done
cp "$src/shared/Size.luau" "$src/shared/Seafloor.luau" "$tmp/"
cp "$service" "$tmp/PredatorService.luau"
cp "$here/sim_rbx.luau" "$here/sim_services.luau" "$here/predator_sim.luau" "$tmp/"
header='local __rbx = require("./sim_rbx"); local Vector3, CFrame, Random, Color3, Enum, game = __rbx.Vector3, __rbx.CFrame, __rbx.Random, __rbx.Color3, __rbx.Enum, __rbx.game'
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
	-e 's/require\(ReplicatedStorage\.Shared\.(Size|Seafloor)\)/require(".\/\1")/' \
	-e 's/require\(ReplicatedStorage\.Shared\.([A-Za-z]+)\)/require(".\/sim_services").\1/' \
	-e 's/require\(script\.Parent\.Parent\.([A-Za-z]+)\)/require(".\/sim_services").\1/' \
	-e 's/require\(script\.Parent\.([A-Za-z]+)\)/require(".\/sim_services").\1/' \
	-e 's/^export type/type/' \
	"$tmp/PredatorService.luau"
cd "$tmp" && "${LUAU:-luau}" predator_sim.luau
