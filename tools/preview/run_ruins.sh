#!/bin/bash
# Renders the Sunken Ruins as players see them: the Terrain (src/server/Shelf.luau,
# voxelized round the city) plus every part src/server/Ruins.luau builds on it, and
# checks that a LV 100 fish gets through every swim line it registers.
#   bash tools/preview/run_ruins.sh <out_dir>
# PROPS=1 draws the hero props (ruins_glb: assets/glb/props once fetch_assets.py has
# run, else assets/tripo/ruins) and the corals in place of their part-built stand-ins,
# placed as Props.dress places them (the importer's half turn, the box's own axes).
# VIEWS=headway,headtop,headgaze,hand,capital are close-ups found by the placements
# (the H| line gives the head's middle and the way its face looks; BOUNDS=960,1280,
# -474,-330,-140,220 keeps the Terrain to them). SCHOOLS=1 also lifts prey schools laid
# through the city over its stones (Shared/Schools.settle) and checks no fish swims
# inside one (ruins_schools.luau: K| lines). VIEWS=approach,avenue,... picks the cameras
# (ruins_build.luau lists them); DUMP_ONLY=1 stops after the build and the checks
# (read hub_parts.txt: C| counts, S| swim lines, [Ruins] the summary). Needs `luau`
# (LUAU=...) and Blender's Python with numpy, scikit-image and Pillow (BPY=...,
# default python3.11). Cycles on the CPU: a view takes a minute or two.
set -e
cd "$(dirname "$0")"
OUT=${1:-/tmp/ruins_preview}
mkdir -p "$OUT"
LUAU=${LUAU:-luau}
src=../../src

module() { # module <Name> <path>: wraps a ModuleScript as a local, with its requires resolved
	echo "local $1 = (function()"
	grep -v '^--!strict' "$2" \
		| sed -E 's#require\((ReplicatedStorage\.[A-Za-z.]+)\)#(\1)#g' \
		| sed -E 's#require\(script\.Parent\.Parent\.([A-Za-z]+)\)#\1#g' \
		| sed -E 's#require\(script\.Parent\.([A-Za-z]+)\)#\1#g' \
		| sed -E 's#^local Props = \(ReplicatedStorage\.Shared\.Props\)#local Props = PropsStub#'
	echo "end)()"
}

chunk=$(mktemp --suffix=.luau)
{
	grep -v '^return true$' roblox_stub.luau
	grep -v '^return true$' cave_stub.luau
	grep -v '^return true$' parts_stub.luau
	echo "USE_PROPS_ENV = $([ -n "$PROPS" ] && echo true || echo false)"
	module World $src/shared/Config/World.luau
	module Dens $src/shared/Config/Dens.luau
	module RuinsConfig $src/shared/Config/Ruins.luau
	module Prey $src/shared/Config/Prey.luau
	module Tuning $src/shared/Config/Tuning.luau
	echo 'local Config = { World = World, Dens = Dens, Ruins = RuinsConfig, Prey = Prey, Tuning = Tuning }'
	module Layout $src/shared/Layout.luau
	module Seafloor $src/shared/Seafloor.luau
	echo 'SERVICES = { ReplicatedStorage = { Shared = { Config = Config, Layout = Layout, Seafloor = Seafloor, Props = PropsStub } } }'
	# (Shelf lays the Vents' field out round the prey schools: VentsPlan reads Schools)
	module Size $src/shared/Size.luau
	module Schools $src/shared/Schools.luau
	echo 'SERVICES.ReplicatedStorage.Shared.Schools = Schools'
	module VentsPlan $src/server/VentsPlan.luau
	module Cave $src/server/Cave.luau
	module Shelf $src/server/Shelf.luau
	module Decor $src/server/Decor.luau
	module Ruins $src/server/Ruins.luau
	cat ruins_build.luau
	if [ -n "$SCHOOLS" ]; then cat ruins_schools.luau; fi
} > "$chunk"
$LUAU "$chunk" > "$OUT/hub_parts.txt" || { tail -5 "$OUT/hub_parts.txt"; rm "$chunk"; exit 1; }
rm "$chunk"
grep '^\[Ruins\]' "$OUT/hub_parts.txt" || true
grep '^C|' "$OUT/hub_parts.txt" | sed 's/^C|/parts|collide|query|shadow: /' || true
grep '^S|' "$OUT/hub_parts.txt" | sed 's/^S|/swim: /' || true
grep '^K|' "$OUT/hub_parts.txt" | sed 's/^K|/schools: /' || true

# The Terrain round the city (cave_render.py rasterizes it at BOUNDS, CELL)
chunk=$(mktemp --suffix=.luau)
{
	grep -v '^return true$' roblox_stub.luau
	grep -v '^return true$' cave_stub.luau
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
	echo 'dumpOps(Shelf.ops())'
} > "$chunk"
$LUAU "$chunk" > "$OUT/cave_ops.jsonl"
rm "$chunk"
[ -n "$DUMP_ONLY" ] && exit 0
export BOUNDS=${BOUNDS:-900,1500,-474,-310,-260,330}
export CELL=${CELL:-2}
export FOG=${FOG:-170}
EGL_PLATFORM=surfaceless ${BPY:-python3.11} render_hub.py -- "$OUT" 2>&1 | grep -E "wrote|Error|error|Traceback|^  " || true
