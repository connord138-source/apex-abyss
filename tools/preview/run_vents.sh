#!/bin/bash
# Renders the Hydrothermal Vents' field as players see it: the Terrain
# (src/server/Shelf.luau, voxelized round each view) plus every part
# src/server/Vents.luau builds on it, in the Vents' warm murk, and checks that the
# field lifts no prey school (VentsPlan keeps every top under the schools' loops).
#   bash tools/preview/run_vents.sh <out_dir>
# Views (vents_build.luau finds them on the plan): map and aerial (the whole field), forge
# (the Forge from ~250 studs down its causeway's side), crater, causeway, basin (the
# brine pool's basin), terraces1/2, smoker1..3, basalt1/2, chimney and chimney2 (a
# tall basin chimney's flanges from beside it, a short one's from over it) and worms
# (a tube-worm forest); VIEWS=a,b,... picks some. Each view voxelizes its own box (B| lines) at
# its own cell size (CELL=... overrides), so Terrain past it isn't drawn (a far
# chimney's flanges can seem to float). NO_SCHOOLS=1 skips the school check (K|
# lines); T| is the boulder tidy's test; DUMP_ONLY=1 stops after the build and the
# checks (read hub_parts.txt: C| counts, O| Terrain ops, [Vents] the summary).
# Particles are drawn as see-through balls (fainter the more transparent the
# emitter starts), far heavier than the game's. The previews' Random isn't
# Roblox's: the basins, chimneys, schools and so every landmark's spot differ from
# the game's (the layout rules are the game's). Needs `luau` (LUAU=...) and
# Blender's Python with numpy, scikit-image and Pillow (BPY=..., default
# python3.11). Cycles on the CPU: a view takes a few minutes.
set -e
cd "$(dirname "$0")"
OUT=${1:-/tmp/vents_preview}
mkdir -p "$OUT"
LUAU=${LUAU:-luau}
src=../../src

module() { # module <Name> <path>: wraps a ModuleScript as a local, with its requires resolved
	echo "local $1 = (function()"
	grep -v '^--!strict' "$2" \
		| sed -E 's#require\((ReplicatedStorage\.[A-Za-z.]+)\)#(\1)#g' \
		| sed -E 's#require\(script\.Parent\.Parent\.([A-Za-z]+)\)#\1#g' \
		| sed -E 's#require\(script\.Parent\.([A-Za-z]+)\)#\1#g'
	echo "end)()"
}

modules() {
	module World $src/shared/Config/World.luau
	module Dens $src/shared/Config/Dens.luau
	module RuinsConfig $src/shared/Config/Ruins.luau
	module Prey $src/shared/Config/Prey.luau
	module Tuning $src/shared/Config/Tuning.luau
	echo 'local Config = { World = World, Dens = Dens, Ruins = RuinsConfig, Prey = Prey, Tuning = Tuning }'
	module Layout $src/shared/Layout.luau
	module Seafloor $src/shared/Seafloor.luau
	module Size $src/shared/Size.luau
	module Schools $src/shared/Schools.luau
	echo 'SERVICES = { ReplicatedStorage = { Shared = { Config = Config, Layout = Layout, Seafloor = Seafloor, Schools = Schools } } }'
	module VentsPlan $src/server/VentsPlan.luau
	module Cave $src/server/Cave.luau
	module Shelf $src/server/Shelf.luau
}

chunk=$(mktemp --suffix=.luau)
{
	grep -v '^return true$' roblox_stub.luau
	grep -v '^return true$' cave_stub.luau
	grep -v '^return true$' parts_stub.luau
	echo "SCHOOL_CHECK = $([ -n "$NO_SCHOOLS" ] && echo false || echo true)"
	modules
	module Vents $src/server/Vents.luau
	cat vents_build.luau
} > "$chunk"
$LUAU "$chunk" > "$OUT/hub_parts.txt" || { tail -5 "$OUT/hub_parts.txt"; rm "$chunk"; exit 1; }
rm "$chunk"
grep '^\[Vents\]' "$OUT/hub_parts.txt" || true
grep '^C|' "$OUT/hub_parts.txt" | sed 's/^C|/parts|collide|query|shadow: /' || true
grep '^O|' "$OUT/hub_parts.txt" | sed 's/^O|/terrain: /' || true
grep '^K|' "$OUT/hub_parts.txt" | sed 's/^K|/schools: /' || true
grep '^T|' "$OUT/hub_parts.txt" | sed 's/^T|/tidy: /' || true

# The Terrain (cave_render.py rasterizes it at each view's BOUNDS, CELL)
chunk=$(mktemp --suffix=.luau)
{
	grep -v '^return true$' roblox_stub.luau
	grep -v '^return true$' cave_stub.luau
	modules
	echo 'dumpOps(Shelf.ops())'
} > "$chunk"
$LUAU "$chunk" > "$OUT/cave_ops.jsonl"
rm "$chunk"
[ -n "$DUMP_ONLY" ] && exit 0

# The Vents' warm murk (OceanController VENTS_GRADE: haze (112, 62, 44), density 0.6);
# each view has its own haze distance (the B| line's last field; FOG=... overrides)
export FOG_COLOR=${FOG_COLOR:-112,62,44}
export SUN=${SUN:-2.2}
export AMBIENT=${AMBIENT:-0.11,0.08,0.07}
views=${VIEWS:-$(grep '^B|' "$OUT/hub_parts.txt" | cut -d'|' -f2 | paste -sd, -)}
for name in ${views//,/ }; do
	line=$(grep "^B|$name|" "$OUT/hub_parts.txt" || true)
	[ -z "$line" ] && { echo "no view $name"; continue; }
	BOUNDS=$(echo "$line" | cut -d'|' -f3) CELL=${CELL:-$(echo "$line" | cut -d'|' -f4)} \
		FOG=${FOG:-$(echo "$line" | cut -d'|' -f5)} VIEWS=$name \
		EGL_PLATFORM=surfaceless ${BPY:-python3.11} render_hub.py -- "$OUT" 2>&1 \
		| grep -E "wrote|Error|error|Traceback|^  " || true
done
