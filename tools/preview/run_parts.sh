#!/usr/bin/env bash
# Draws the rolled parts' models (Angler Lure, Narwhal Horn, Sawblade Snout, Sail Fin,
# Veil Tail) on every playable fish the way the game hangs and tints them
# (Shared/PartFit; owner, 2026-10-28: the parts must "shape to the fish and change
# their appearance to fit"): one contact sheet, a row per fish, a side and a
# three-quarter view per part.
#   bash tools/preview/run_parts.sh <out.png> [Plan | Plan:PartId | :PartId]
# A second argument draws only that fish (or that part on it, or that part on every
# fish), bigger. PARTS_VIEWS, PARTS_FOCUS and PARTS_CELL pick the views, frame the
# shots on the parts and size them (parts_preview.py). Needs `luau`
# (LUAU=...), Blender's Python (BPY=..., default python3.11), the species FBX
# (FBX=..., default assets/fbx/species) and the parts' GLBs with parts.json beside
# them (PARTS=..., default assets/glb/parts), both from tools/fetch_assets.py. Cycles
# on the CPU: the whole sheet takes about a minute.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$here/../.."
OUT=${1:?out.png}
ONLY=${2:-}
LUAU=${LUAU:-luau}
BPY=${BPY:-python3.11}
FBX=${FBX:-$root/assets/fbx/species}
PARTS=${PARTS:-$root/assets/glb/parts}
tmp="$(mktemp -d)"
[[ -n "${KEEP:-}" ]] || trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/Config"
cp "$root/tools/tests/sim_rbx.luau" "$here/parts_rbx.luau" "$here/parts_dump.luau" "$tmp/"
cp "$root/src/shared/PartFit.luau" "$tmp/"
cp "$root/src/shared/Config/Species.luau" "$tmp/Config/"
header='local __p = require("./parts_rbx"); local Vector3, CFrame, Color3, Enum = __p.Vector3, __p.CFrame, __p.Color3, __p.Enum'
sed -i "1a $header" "$tmp/PartFit.luau"
sed -i "1a ${header//.\/parts_rbx/..\/parts_rbx}" "$tmp/Config/Species.luau"
"$BPY" "$here/parts_preview.py" -- dims "$FBX" "$tmp/dims.luau" > /dev/null
"$LUAU" "$tmp/parts_dump.luau" > "$tmp/fits.json"
"$BPY" "$here/parts_preview.py" -- sheet "$tmp/fits.json" "$FBX" "$PARTS" "$OUT" $ONLY 2>&1 | grep '\[parts_preview\]'
