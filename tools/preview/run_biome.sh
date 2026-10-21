#!/bin/bash
# Renders one biome's landmarks as players see them (owner, 2026-10-21: the biome
# detail boards): the Terrain (src/server/Shelf.luau, voxelized round the biome) plus
# every part its builder makes (src/server/Wrecks.luau, TrenchDress.luau,
# KelpDress.luau, ReefDress.luau, BlueDress.luau), seated on the fill ops
# (biome_build.luau).
#   bash tools/preview/run_biome.sh <Wreck|Trench|Kelp|Reef|Blue> <out_dir>
# PROPS=1 draws the imported models (assets/glb/props, assets/tripo/biome_*) in place
# of their part-built stand-ins, placed as Props.dress places them. VIEWS=a,b picks
# the cameras the module lists (biome_build.luau prints them as V| lines);
# DUMP_ONLY=1 stops after the build (hub_parts.txt: [<Biome>] the summary, C| counts).
# BOUNDS/CELL override the Terrain's box. Needs `luau` (LUAU=...) and Blender's Python
# with numpy, scikit-image and Pillow (BPY=..., default python3.11). Cycles on the
# CPU: a view takes a minute or two.
set -e
cd "$(dirname "$0")"
BIOME=${1:?Wreck, Trench, Kelp, Reef or Blue}
OUT=${2:-/tmp/biome_preview}
mkdir -p "$OUT"
LUAU=${LUAU:-luau}
src=../../src

case "$BIOME" in
	Wreck) MODULE=Wrecks; REGION="-900,-330,-430,430"; BOUNDS_DEFAULT="-880,-380,-70,140,-420,420" ;;
	Trench) MODULE=TrenchDress; REGION="-330,330,920,1480"; BOUNDS_DEFAULT="-260,260,-940,-380,1000,1460" ;;
	Kelp) MODULE=KelpDress; REGION="-500,500,-500,500"; BOUNDS_DEFAULT="-480,480,-40,440,-480,480" ;;
	Reef) MODULE=ReefDress; REGION="-880,880,-880,880"; BOUNDS_DEFAULT="250,530,-240,60,400,690" ;;
	Blue) MODULE=BlueDress; REGION="-700,700,-1500,-800"; BOUNDS_DEFAULT="-560,560,-460,440,-1480,-860" ;;
	*) echo "unknown biome $BIOME"; exit 1 ;;
esac

module() { # module <Name> <path>: wraps a ModuleScript as a local, with its requires resolved
	echo "local $1 = (function()"
	grep -v '^--!strict' "$2" \
		| sed -E 's#require\((ReplicatedStorage\.[A-Za-z.]+)\)#(\1)#g' \
		| sed -E 's#require\(script\.Parent\.Parent\.([A-Za-z]+)\)#\1#g' \
		| sed -E 's#require\(script\.Parent\.([A-Za-z]+)\)#\1#g' \
		| sed -E 's#^local Props = \(ReplicatedStorage\.Shared\.Props\)#local Props = PropsStub#'
	echo "end)()"
}

config() {
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
	echo 'SERVICES = { ReplicatedStorage = { Shared = { Config = Config, Layout = Layout, Seafloor = Seafloor, Props = PropsStub, Schools = Schools } } }'
	module VentsPlan $src/server/VentsPlan.luau
	module Cave $src/server/Cave.luau
	module Shelf $src/server/Shelf.luau
}

chunk=$(mktemp --suffix=.luau)
{
	grep -v '^return true$' roblox_stub.luau
	grep -v '^return true$' cave_stub.luau
	grep -v '^return true$' parts_stub.luau
	echo "USE_PROPS_ENV = $([ -n "$PROPS" ] && echo true || echo false)"
	echo "BIOME = \"$BIOME\""
	echo "REGION = { $REGION }"
	config
	module LandmarkKit $src/server/LandmarkKit.luau
	module PlaceMarks $src/server/PlaceMarks.luau
	module $MODULE $src/server/$MODULE.luau
	cat biome_build.luau
} > "$chunk"
$LUAU "$chunk" > "$OUT/hub_parts.txt" || { tail -5 "$OUT/hub_parts.txt"; rm "$chunk"; exit 1; }
rm "$chunk"
grep "^\[$BIOME\]" "$OUT/hub_parts.txt" || true
grep '^C|' "$OUT/hub_parts.txt" | sed 's/^C|/parts|collide|query|shadow: /' || true

chunk=$(mktemp --suffix=.luau)
{
	grep -v '^return true$' roblox_stub.luau
	grep -v '^return true$' cave_stub.luau
	config
	echo 'dumpOps(Shelf.ops())'
} > "$chunk"
$LUAU "$chunk" > "$OUT/cave_ops.jsonl"
rm "$chunk"
[ -n "$DUMP_ONLY" ] && exit 0
export BOUNDS=${BOUNDS:-$BOUNDS_DEFAULT}
export CELL=${CELL:-3}
export FOG=${FOG:-220}
EGL_PLATFORM=surfaceless ${BPY:-python3.11} render_hub.py -- "$OUT" 2>&1 | grep -E "wrote|Error|error|Traceback|^  " || true
