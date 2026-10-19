#!/bin/bash
# Checks the start screen's documentary shots (Config/Start, Shared/StartShots)
# against the Terrain and renders each one's key frames:
#   LUAU=<luau> bash tools/preview/run_start.sh <out_dir>
# The luau CLI builds the Terrain's fill ops (Shelf.luau, Cave.luau) in-process, lifts
# the schools over them like the server (Schools.settle), and plans every shot on up
# to MOST candidate schools (default 14) at three moments, with the client's own
# checks (StartShots.plan: the subject sees the camera, its travel is clear, open
# water under and round it); every plan tried is an R| line in <out_dir>/start.txt,
# each shot's tally a SUMMARY| line. It exits 1 if a shot has no clear plan at all.
# Then Blender (BPY=..., default python3.11, with numpy, scikit-image and Pillow)
# voxelizes the Terrain round each shot's chosen plan and renders its key frames as
# the player sees them (letterbox, lower third, the title and cards' places), with
# the school's fish as stand-ins and the water's haze: <out_dir>/start_<shot>_<k>.png
# and a contact sheet, start_sheet.png. DUMP_ONLY=1 stops after the checks;
# SHOTS=reef,ruins renders only those; SAMPLES / RES / CELL tune the renders.
# The preview's Random isn't Roblox's: its schools, reef heads and vent basins sit
# elsewhere than the game's, so this checks the shots' logic on a world built the
# same way; the client runs the same checks on the real world before every shot.
set -e
cd "$(dirname "$0")"
OUT=${1:-/tmp/start_preview}
mkdir -p "$OUT"
LUAU=${LUAU:-luau}
src=../../src

chunk=$(mktemp --suffix=.luau)
{
	grep -v '^return true$' roblox_stub.luau
	grep -v '^return true$' cave_stub.luau
	echo "START_MOST = ${MOST:-14}"
	# Shelf.luau and everything it requires (Cave, VentsPlan, ...), the shots' modules,
	# and every Config module they read
	python3 -S luau_bundle.py $src server/Shelf server/Cave shared/StartShots
	echo 'local Shelf, Cave, Schools, StartShots, Seafloor = M_Shelf, M_Cave, M_Schools, M_StartShots, M_Seafloor'
	echo 'local World = Config.World'
	cat start_shots.luau
} > "$chunk"
$LUAU "$chunk" > "$OUT/start.txt" || { tail -5 "$OUT/start.txt"; rm "$chunk"; exit 1; }
rm "$chunk"
grep '^INFO|' "$OUT/start.txt" | sed 's/^INFO|/start: /'
grep '^SUMMARY|' "$OUT/start.txt" | awk -F'|' '{ printf "  %-9s %2d of %2d plans clear  (%d candidate schools: %s)\n", $2, $3, $4, $5, $6 }'
grep '^SHOT|' "$OUT/start.txt" | awk -F'|' '{ printf "  %-9s render: school %s, variant %s, open water round the camera >= %s studs  (%s · %s)\n", $2, $11, $9, $10, $7, $8 }'
failed=$(grep '^SUMMARY|' "$OUT/start.txt" | awk -F'|' '$3 == 0 { print $2 }')
if [ -n "$failed" ]; then
	echo "start: no clear plan for: $failed"
	status=1
fi
[ -n "$DUMP_ONLY" ] && exit ${status:-0}
EGL_PLATFORM=surfaceless ${BPY:-python3.11} start_render.py -- "$OUT" 2>&1 | grep -E "wrote|Error|error|Traceback|^  " || true
exit ${status:-0}
