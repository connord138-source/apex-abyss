#!/bin/bash
# Renders the hub as players see it: the cavern's Terrain (src/server/Cave.luau,
# voxelized) plus the parts the server builds on it: the den doorways and their
# nameplates (DenDoor.luau), the plaza's paving and dressing and the vendor stalls
# (Plaza.luau) and the Treasure Wheel (TreasureWheel.luau), signs' text included.
#   bash tools/preview/run_hub.sh <out_dir> [builder.luau]
# The builder is a luau script run after the modules load (default hub_build.luau:
# what WorldService builds, with a few dens owned). VIEWS=plaza,door,... picks the
# cameras (render_hub.py lists them). Needs `luau` (LUAU=...) and Blender's Python
# with numpy, scikit-image and Pillow (BPY=..., default python3.11). Cycles on the
# CPU: a view takes a minute or two.
set -e
cd "$(dirname "$0")"
OUT=${1:-/tmp/hub_preview}
BUILDER=${2:-hub_build.luau}
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
	module World $src/shared/Config/World.luau
	module Dens $src/shared/Config/Dens.luau
	module Shop $src/shared/Config/Shop.luau
	module Wheel $src/shared/Config/Wheel.luau
	module Materials $src/shared/Config/Materials.luau
	module Biomes $src/shared/Config/Biomes.luau
	echo 'local Config = { World = World, Dens = Dens, Shop = Shop, Wheel = Wheel, Materials = Materials, Biomes = Biomes }'
	module Layout $src/shared/Layout.luau
	echo 'SERVICES = { ReplicatedStorage = { Shared = { Config = Config, Layout = Layout, Props = PropsStub } } }'
	module Cave $src/server/Cave.luau
	for m in Decor DenDoor Plaza; do
		[ -f $src/server/$m.luau ] && module $m $src/server/$m.luau
	done
	module TreasureWheel $src/server/TreasureWheel.luau
	cat "$BUILDER"
} > "$chunk"
$LUAU "$chunk" > "$OUT/hub_parts.txt" || { cat "$OUT/hub_parts.txt" | tail -5; rm "$chunk"; exit 1; }
rm "$chunk"
grep '^C|' "$OUT/hub_parts.txt" | sed 's/^C|/parts|collide|query|shadow: /' || true

# The cavern's fill ops (as run_cave.sh)
chunk=$(mktemp --suffix=.luau)
{
	grep -v '^return true$' roblox_stub.luau
	grep -v '^return true$' cave_stub.luau
	module World $src/shared/Config/World.luau
	module Dens $src/shared/Config/Dens.luau
	echo 'local Config = { World = World, Dens = Dens }'
	module Layout $src/shared/Layout.luau
	echo 'SERVICES = { ReplicatedStorage = { Shared = { Config = Config, Layout = Layout } } }'
	module Cave $src/server/Cave.luau
	echo 'dumpOps(Cave.ops())'
} > "$chunk"
$LUAU "$chunk" > "$OUT/cave_ops.jsonl"
rm "$chunk"
[ -n "$DUMP_ONLY" ] && exit 0
EGL_PLATFORM=surfaceless ${BPY:-python3.11} render_hub.py -- "$OUT" 2>&1 | grep -E "wrote|Error|error|Traceback|^  " || true
