#!/bin/bash
# Dumps the whole seafloor's Terrain fill ops (src/server/Shelf.luau plus the hub
# seamount from Cave.luau) with the luau CLI, then voxelizes and renders them in
# Blender from above and from the sides:
#   bash tools/preview/run_world.sh <out_dir>
# Needs `luau` on PATH (or LUAU=...) and Blender's Python with numpy and
# scikit-image (BPY=..., default python3.11).
set -e
cd "$(dirname "$0")"
OUT=${1:-/tmp/world_preview}
mkdir -p "$OUT"
chunk=$(mktemp --suffix=.luau)
{
	grep -v '^return true$' roblox_stub.luau
	grep -v '^return true$' cave_stub.luau
	echo 'local World = (function()'
	grep -v '^--!strict' ../../src/shared/Config/World.luau
	echo 'end)()'
	echo 'local Config = { World = World }'
	echo 'local Layout = (function()'
	grep -v '^--!strict' ../../src/shared/Layout.luau | sed 's#require(script.Parent.Config)#Config#'
	echo 'end)()'
	echo 'local Seafloor = (function()'
	grep -v '^--!strict' ../../src/shared/Seafloor.luau | sed 's#require(script.Parent.Config)#Config#'
	echo 'end)()'
	echo 'SERVICES = { ReplicatedStorage = { Shared = { Config = Config, Layout = Layout, Seafloor = Seafloor } } }'
	echo 'local Cave = (function()'
	grep -v '^--!strict' ../../src/server/Cave.luau \
		| sed 's#require(ReplicatedStorage.Shared.Config)#Config#' \
		| sed 's#require(ReplicatedStorage.Shared.Layout)#Layout#'
	echo 'end)()'
	echo 'local Shelf = (function()'
	grep -v '^--!strict' ../../src/server/Shelf.luau \
		| sed 's#require(ReplicatedStorage.Shared.Config)#Config#' \
		| sed 's#require(ReplicatedStorage.Shared.Seafloor)#Seafloor#' \
		| sed 's#require(script.Parent.Cave)#Cave#'
	echo 'end)()'
	echo 'local ops = Shelf.ops()'
	echo 'for _, op in Cave.ops() do table.insert(ops, op) end'
	echo 'dumpOps(ops)'
} > "$chunk"
${LUAU:-luau} "$chunk" > "$OUT/world_ops.jsonl"
rm "$chunk"
echo "ops: $(wc -l < "$OUT/world_ops.jsonl")"
EGL_PLATFORM=surfaceless ${BPY:-python3.11} cave_render.py -- "$OUT" --world 2>&1 | grep -E "wrote|Error|error|Traceback|^  " || true
