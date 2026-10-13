#!/bin/bash
# Dumps the hub cavern's Terrain fill ops plus every den carved to one level
# (src/server/DenCarve.luau) with the luau CLI, then checks and draws them:
#   LEVEL=5 LUAU=<luau> bash tools/preview/run_dens.sh <out_dir>
# check_dens.py voxelizes the ops and fails if a den's rooms reach another den, a
# tunnel or the sand outside, and writes a top-down slice of each storey.
set -e
cd "$(dirname "$0")"
OUT=${1:-/tmp/dens_preview}
LEVEL=${LEVEL:-5}
mkdir -p "$OUT"
chunk=$(mktemp --suffix=.luau)
{
	grep -v '^return true$' roblox_stub.luau
	grep -v '^return true$' cave_stub.luau
	echo 'local World = (function()'
	grep -v '^--!strict' ../../src/shared/Config/World.luau
	echo 'end)()'
	echo 'local Dens = (function()'
	grep -v '^--!strict' ../../src/shared/Config/Dens.luau
	echo 'end)()'
	echo 'local Config = { World = World, Dens = Dens }'
	echo 'local Layout = (function()'
	grep -v '^--!strict' ../../src/shared/Layout.luau | sed 's#require(script.Parent.Config)#Config#'
	echo 'end)()'
	echo 'local DenSpace = (function()'
	grep -v '^--!strict' ../../src/shared/DenSpace.luau \
		| sed 's#require(script.Parent.Config.Dens)#Dens#; s#require(script.Parent.Config)#Config#; s#require(script.Parent.Layout)#Layout#'
	echo 'end)()'
	echo 'SERVICES = { ReplicatedStorage = { Shared = { Config = Config, Layout = Layout, DenSpace = DenSpace } } }'
	echo 'local Cave = (function()'
	grep -v '^--!strict' ../../src/server/Cave.luau \
		| sed 's#require(ReplicatedStorage.Shared.Config)#Config#' \
		| sed 's#require(ReplicatedStorage.Shared.Layout)#Layout#'
	echo 'end)()'
	echo 'local DenCarve = (function()'
	grep -v '^--!strict' ../../src/server/DenCarve.luau \
		| sed 's#require(ReplicatedStorage.Shared.Config)#Config#; s#require(ReplicatedStorage.Shared.DenSpace)#DenSpace#; s#require(script.Parent.Cave)#Cave#'
	echo 'end)()'
	echo "local ops = Cave.ops()"
	echo "for den = 1, Layout.DEN_COUNT do for _, op in DenCarve.ops(den, $LEVEL) do table.insert(ops, op) end end"
	echo 'dumpOps(ops)'
} > "$chunk"
${LUAU:-luau} "$chunk" > "$OUT/dens_ops.jsonl" || { rm "$chunk"; exit 1; }
rm "$chunk"
echo "ops: $(wc -l < "$OUT/dens_ops.jsonl")"
${PY:-python3.11} check_dens.py "$OUT/dens_ops.jsonl" "$OUT" "$LEVEL"
