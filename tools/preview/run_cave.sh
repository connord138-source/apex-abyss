#!/bin/bash
# Dumps the hub cavern's Terrain fill ops (src/server/Cave.luau) with the luau CLI,
# then voxelizes and renders them in Blender:
#   bash tools/preview/run_cave.sh <out_dir>
# Needs `luau` on PATH (or LUAU=...), Blender's Python with numpy and scikit-image
# (BPY=..., default python3.11), and EGL for headless EEVEE.
set -e
cd "$(dirname "$0")"
OUT=${1:-/tmp/cave_preview}
mkdir -p "$OUT"
chunk=$(mktemp --suffix=.luau)
{
	grep -v '^return true$' roblox_stub.luau
	grep -v '^return true$' cave_stub.luau
	echo 'local World = (function()'
	grep -v '^--!strict' ../../src/shared/Config/World.luau
	echo 'end)()'
	echo 'local Layout = (function()'
	grep -v '^--!strict' ../../src/shared/Layout.luau | sed 's#require(script.Parent.Config)#{ World = World }#'
	echo 'end)()'
	echo 'SERVICES = { ReplicatedStorage = { Shared = { Config = { World = World }, Layout = Layout } } }'
	echo 'local Cave = (function()'
	grep -v '^--!strict' ../../src/server/Cave.luau \
		| sed 's#require(ReplicatedStorage.Shared.Config)#{ World = World }#' \
		| sed 's#require(ReplicatedStorage.Shared.Layout)#Layout#'
	echo 'end)()'
	echo 'if MODE == "layout" then dumpLayout(Layout, World.hub) else dumpOps(Cave.ops()) end'
} > "$chunk"
${LUAU:-luau} "$chunk" > "$OUT/cave_ops.jsonl"
sed -i '1i MODE = "layout"' "$chunk"
${LUAU:-luau} "$chunk" > "$OUT/cave_layout.json"
rm "$chunk"
echo "ops: $(wc -l < "$OUT/cave_ops.jsonl")"
EGL_PLATFORM=surfaceless ${BPY:-python3.11} cave_render.py -- "$OUT" 2>&1 | grep -E "wrote|Error|error|Traceback|^  " || true
