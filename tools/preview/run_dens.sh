#!/bin/bash
# Dumps one den's Terrain fill ops carved to one level (src/server/DenCarve.luau;
# since 2026-10-16 every den is its own block far outside the play area, and all
# twelve are carved alike) with the luau CLI, then checks and draws them:
#   LEVEL=5 LUAU=<luau> bash tools/preview/run_dens.sh <out_dir>
# check_dens.py voxelizes the ops in the den's own frame and fails if the rooms
# open out of their block, aren't one cave joined by the shafts, or leave a room's
# floor or a storey's rock wrong; it writes a slice of each storey and one along it.
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
		| sed 's#require(ReplicatedStorage.Shared.Config)#Config#; s#require(ReplicatedStorage.Shared.DenSpace)#DenSpace#; s#require(script.Parent.Cave)#Cave#; s#require(ReplicatedStorage.Shared.Layout)#Layout#'
	echo 'end)()'
	echo "local ops = DenCarve.ops(1, $LEVEL)"
	echo 'dumpOps(ops)'
	# den 1's frame, its block and its rooms, for the checker (den-local numbers; the
	# lines that aren't ops start with a word)
	echo 'local o = Layout.denOrigin(1).Position'
	echo 'local e = Layout.DEN_EXTENT'
	echo 'print(string.format("FRAME %f %f %f %f %f %f %f %f", o.X, o.Y, o.Z, e.half, e.front, e.back, e.top, e.bottom))'
	echo 'for n, st in Dens.storeys do print(string.format("STOREY %d %f %f %f %f", n, st.deck, st.floor, st.ceiling, st.wall)) end'
	echo "for _, r in Dens.rooms do if r.level <= $LEVEL then print(string.format(\"ROOM %s %d %d %f %f %f\", r.id, r.level, r.storey, r.x, r.z0, r.z1)) end end"
	echo "for _, sh in Dens.shafts do if sh.level <= $LEVEL then print(string.format(\"SHAFT %s %d %d %f %f\", sh.id, sh.from, sh.to, sh.z, sh.radius)) end end"
} > "$chunk"
${LUAU:-luau} "$chunk" > "$OUT/dens_ops.jsonl" || { rm "$chunk"; exit 1; }
rm "$chunk"
echo "ops: $(wc -l < "$OUT/dens_ops.jsonl")"
${PY:-python3.11} check_dens.py "$OUT/dens_ops.jsonl" "$OUT" "$LEVEL"
