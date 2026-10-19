#!/bin/bash
# Renders the drop-off as players see it: the Terrain (src/server/Shelf.luau,
# voxelized round one stretch of the wall) plus every part src/server/Cliff.luau
# dresses it with, seated by rays against the fill ops (cliff_build.luau).
#   bash tools/preview/run_cliff.sh <out_dir>
# ANGLES=300,180 picks the stretches (degrees round the hub; default 300, the reef
# over the Open Blue, and 180, the Shipwreck Graveyard's bay over the Vents); each
# renders WANT (default wide,face,lip,over,ledge: from the deep floor up the wall,
# straight at the mid face, the lip close up, over the lip from the shelf, the
# ledge nearest the middle; cave is also offered) as <angle>_<view>.png.
# PROPS=1 draws the imported models (assets/glb/props, assets/tripo/props,
# assets/tripo/cliff) in place of their part-built stand-ins, placed as Props.dress
# places them. CLIFF=0 leaves the dressing off (the Terrain alone, e.g. against an
# older Shelf.luau: SHELF=<file>). DUMP_ONLY=1 stops after the build (hub_parts.txt:
# [Cliff] the summary, C| counts). Needs `luau` (LUAU=...) and Blender's Python with
# numpy, scikit-image and Pillow (BPY=..., default python3.11). Cycles on the CPU:
# a view takes a minute or two.
set -e
cd "$(dirname "$0")"
OUT=${1:-/tmp/cliff_preview}
mkdir -p "$OUT"
LUAU=${LUAU:-luau}
src=../../src
SHELF=${SHELF:-$src/server/Shelf.luau}

module() { # module <Name> <path>: wraps a ModuleScript as a local, with its requires resolved
	echo "local $1 = (function()"
	grep -v '^--!strict' "$2" \
		| sed -E 's#require\((ReplicatedStorage\.[A-Za-z.]+)\)#(\1)#g' \
		| sed -E 's#require\(script\.Parent\.Parent\.([A-Za-z]+)\)#\1#g' \
		| sed -E 's#require\(script\.Parent\.([A-Za-z]+)\)#\1#g' \
		| sed -E 's#^local Props = \(ReplicatedStorage\.Shared\.Props\)#local Props = PropsStub#'
	echo "end)()"
}

shared_modules() { # Config (Prey and Tuning: VentsPlan reads the prey schools), Layout, Seafloor, Size, Schools
	module Prey $src/shared/Config/Prey.luau
	module Tuning $src/shared/Config/Tuning.luau
	echo 'local Config = { World = World, Dens = Dens, Ruins = RuinsConfig, Biomes = Biomes, Prey = Prey, Tuning = Tuning }'
	module Layout $src/shared/Layout.luau
	module Seafloor $src/shared/Seafloor.luau
	module Size $src/shared/Size.luau
	module Schools $src/shared/Schools.luau
}
vents_plan() { # Shelf.luau lays the Vents' field from VentsPlan once it's there
	if [ -f $src/server/VentsPlan.luau ]; then module VentsPlan $src/server/VentsPlan.luau; fi
}

for ANGLE in $(echo "${ANGLES:-300,180}" | tr ',' ' '); do
	DIR="$OUT/a$ANGLE"
	mkdir -p "$DIR"
	chunk=$(mktemp --suffix=.luau)
	{
		grep -v '^return true$' roblox_stub.luau
		grep -v '^return true$' cave_stub.luau
		grep -v '^return true$' parts_stub.luau
		echo "USE_PROPS_ENV = $([ -n "$PROPS" ] && echo true || echo false)"
		echo "REGION = $ANGLE"
		module World $src/shared/Config/World.luau
		module Dens $src/shared/Config/Dens.luau
		module RuinsConfig $src/shared/Config/Ruins.luau
		module Biomes $src/shared/Config/Biomes.luau
		shared_modules
		echo 'SERVICES = { ReplicatedStorage = { Shared = { Config = Config, Layout = Layout, Seafloor = Seafloor, Schools = Schools, Props = PropsStub } } }'
		module Cave $src/server/Cave.luau
		vents_plan
		module Shelf "$SHELF"
		module Decor $src/server/Decor.luau
		if [ "${CLIFF:-1}" != 0 ] && [ -f $src/server/Cliff.luau ]; then
			module Cliff $src/server/Cliff.luau
		else
			echo 'local Cliff = nil'
		fi
		cat cliff_build.luau
	} > "$chunk"
	$LUAU "$chunk" > "$DIR/hub_parts.txt" || { tail -5 "$DIR/hub_parts.txt"; rm "$chunk"; exit 1; }
	rm "$chunk"
	echo "== $ANGLE"
	grep '^\[Cliff\]' "$DIR/hub_parts.txt" || true
	grep '^C|' "$DIR/hub_parts.txt" | sed 's/^C|/parts|collide|query|shadow (whole ring): /' || true

	# The Terrain (cave_render.py rasterizes it inside the region's box)
	chunk=$(mktemp --suffix=.luau)
	{
		grep -v '^return true$' roblox_stub.luau
		grep -v '^return true$' cave_stub.luau
		module World $src/shared/Config/World.luau
		module Dens $src/shared/Config/Dens.luau
		module RuinsConfig $src/shared/Config/Ruins.luau
		echo 'local Biomes = nil'
		shared_modules
		echo 'SERVICES = { ReplicatedStorage = { Shared = { Config = Config, Layout = Layout, Seafloor = Seafloor, Schools = Schools } } }'
		module Cave $src/server/Cave.luau
		vents_plan
		module Shelf "$SHELF"
		echo 'dumpOps(Shelf.ops())'
	} > "$chunk"
	$LUAU "$chunk" > "$DIR/cave_ops.jsonl"
	rm "$chunk"
	[ -n "$DUMP_ONLY" ] && continue
	export BOUNDS=$(grep '^B|' "$DIR/hub_parts.txt" | head -1 | cut -d'|' -f2)
	SUN_DIR=$(grep '^D|' "$DIR/hub_parts.txt" | head -1 | cut -d'|' -f2)
	export SUN_DIR
	export CELL=${CELL:-3}
	export FOG=${FOG:-420}
	# (only the views this stretch offers: a ledge or a cave may not be in it)
	offered=$(grep '^V|' "$DIR/hub_parts.txt" | cut -d'|' -f2 | tr '\n' ' ')
	VIEWS=$(for v in $(echo "${WANT:-wide,face,lip,over,ledge}" | tr ',' ' '); do
		case " $offered " in *" $v "*) printf '%s,' "$v" ;; esac
	done | sed 's/,$//')
	export VIEWS
	EGL_PLATFORM=surfaceless ${BPY:-python3.11} render_hub.py -- "$DIR" 2>&1 | grep -E "wrote|Error|error|Traceback|^  " || true
	for f in "$DIR"/hub_*.png; do
		[ -f "$f" ] && mv "$f" "$OUT/${ANGLE}_$(basename "$f" .png | sed 's/^hub_//').png"
	done
done
ls "$OUT"/*.png 2>/dev/null || true
