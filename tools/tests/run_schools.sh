#!/usr/bin/env bash
# Checks Shared/Schools' lift over the ground (Schools.settle / load) in the plain
# luau CLI: lays rocks and ridges over the nominal floor, lifts the schools over them
# and samples every fish along its loop to see none swims into the ground.
#   LUAU=/path/to/luau bash tools/tests/run_schools.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../../src"
tmp="$(mktemp -d)"
[[ -n "${KEEP:-}" ]] || trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/Config"
for name in Tuning World Prey; do
	cp "$src/shared/Config/$name.luau" "$tmp/Config/"
done
cp "$src/shared/Size.luau" "$src/shared/Seafloor.luau" "$src/shared/Schools.luau" "$tmp/"
cp "$here/sim_rbx.luau" "$here/schools_test.luau" "$tmp/"
header='local __rbx = require("./sim_rbx"); local Vector3, CFrame, Random, Color3, Enum = __rbx.Vector3, __rbx.CFrame, __rbx.Random, __rbx.Color3, __rbx.Enum'
for f in "$tmp"/Config/*.luau; do
	sed -i "1a ${header//.\/sim_rbx/..\/sim_rbx}" "$f"
done
cat > "$tmp/Config/init.luau" <<'LUA'
return {
	Tuning = require("@self/Tuning"),
	World = require("@self/World"),
	Prey = require("@self/Prey"),
}
LUA
for f in "$tmp/Size.luau" "$tmp/Seafloor.luau" "$tmp/Schools.luau"; do
	sed -i "1a $header" "$f"
	sed -i -E 's/require\(script\.Parent\.([A-Za-z]+)\)/require(".\/\1")/' "$f"
done
cd "$tmp" && "${LUAU:-luau}" schools_test.luau
