#!/usr/bin/env bash
# Renders the ambient sea life (the turtle, the manta, the stingray, the humpback and the
# crab) through their motion cycles: Shared/AmbientRigs runs in the luau CLI
# (ambient_dump.luau, with the test shims) and Blender poses the rigged FBXs
# (assets/fbx/ambient/<Name>.fbx, from tools/blender/rig_ambient.py) and builds the
# part-built stand-ins the same way. One contact sheet per creature: a row per moment,
# top, side and three-quarter views, the model on the left of each and its stand-in
# on the right.
#   LUAU=<luau> bash tools/preview/run_ambient.sh <out_dir> [Name ...]
# BPY=<python with bpy> (default python3.11); FBX=<dir> for the models.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$here/../.."
out="${1:-/tmp/ambient_preview}"
shift || true
mkdir -p "$out"
tmp="$(mktemp -d)"
[[ -n "${KEEP:-}" ]] || trap 'rm -rf "$tmp"' EXIT
cp "$root/src/shared/AmbientRigs.luau" "$root/src/shared/Config/Ambient.luau" "$here/../tests/sim_rbx.luau" "$here/ambient_dump.luau" "$tmp/"
header='local __rbx = require("./sim_rbx"); local Vector3, CFrame = __rbx.Vector3, __rbx.CFrame; local Color3 = { fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end }'
for f in "$tmp/AmbientRigs.luau" "$tmp/Ambient.luau" "$tmp/ambient_dump.luau"; do
	sed -i "1a $header" "$f"
done
(cd "$tmp" && "${LUAU:-luau}" ambient_dump.luau) > "$out/ambient_poses.json"
"${BPY:-python3.11}" "$here/ambient_render.py" "$out/ambient_poses.json" "$out" "${FBX:-$root/assets/fbx/ambient}" "$@"
