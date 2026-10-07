"""Rigs a Tripo fish GLB with a spine for the procedural swim, and exports an FBX.

    <bpy python> tools/blender/rig_fish.py <in.glb> <out.fbx> [--flip] [--segments N]

The fish is squared up (its long axis becomes the body axis), the head end is found
(the deep, wide end; a tail fin is thin), and a chain of bones runs head to tail:

    Root -> Head -> Spine1 .. SpineN -> Tail

Every vertex is weighted to the two bones nearest along the body with a smooth
hand-over, so the client (FishAnimator) can wave the spine with a travelling sine
and swing the head and tail. Fins and the lure follow whatever bone they sit on.

Blender imports glTF as Z-up; the export bakes the conversion back to Y-up (Roblox),
with the fish facing -Z, the way FishBuilder's part bodies face. `--flip` swaps the
head guess when it's wrong (check tools/blender/fish_check.py's renders).
"""
import math
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
IN_PATH, OUT_PATH = argv[0], argv[1]
FLIP = "--flip" in argv
SEGMENTS = int(argv[argv.index("--segments") + 1]) if "--segments" in argv else 5


def log(*args):
    print("[rig_fish]", *args)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=IN_PATH)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
if not meshes:
    sys.exit("no mesh in " + IN_PATH)
# One body: join if Tripo split it
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = "Body"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.data.objects):
    if o.type == "EMPTY":
        bpy.data.objects.remove(o)

# ---------- square up: the body axis becomes +Y (Blender), length along it ----------
co = np.array([v.co[:] for v in body.data.vertices])
centre = (co.max(0) + co.min(0)) / 2
co -= centre
# Principal axis in the horizontal plane (fish swim level; the lure or a tall dorsal
# fin would otherwise tilt the guess)
flat = co[:, :2]
cov = np.cov(flat.T)
evals, evecs = np.linalg.eigh(cov)
axis = evecs[:, np.argmax(evals)]
angle = math.atan2(axis[0], axis[1])  # rotate so the axis lands on +Y
rot = Matrix.Rotation(angle, 4, "Z")
body.matrix_world = rot @ Matrix.Translation(-Vector(centre)) @ body.matrix_world
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
co = np.array([v.co[:] for v in body.data.vertices])

# ---------- head end: the deep, wide quarter (a tail fin is a thin blade) ----------
length = co[:, 1].max() - co[:, 1].min()
y0 = co[:, 1].min()


def girth(lo, hi):
    band = co[(co[:, 1] >= y0 + lo * length) & (co[:, 1] < y0 + hi * length)]
    if len(band) < 8:
        return 0.0
    return (band[:, 0].max() - band[:, 0].min()) * (band[:, 2].max() - band[:, 2].min())


# Compare the two ends' bulk a little in from the tips (snouts and tail tips are both thin)
head_at_low = girth(0.08, 0.3) > girth(0.7, 0.92)
if FLIP:
    head_at_low = not head_at_low
if head_at_low:
    # Turn the fish round so the head is at +Y... then the export (Y -> -Z) faces -Z
    body.matrix_world = Matrix.Rotation(math.pi, 4, "Z") @ body.matrix_world
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    co = np.array([v.co[:] for v in body.data.vertices])
log("head at +Y, length", round(length, 3), "flip" if FLIP else "")

# Stand the body on the ground plane's centre (the root sits at the body's middle)
co = np.array([v.co[:] for v in body.data.vertices])
y_min, y_max = co[:, 1].min(), co[:, 1].max()
z_mid = (co[:, 2].max() + co[:, 2].min()) / 2
x_mid = (co[:, 0].max() + co[:, 0].min()) / 2
body.matrix_world = Matrix.Translation(Vector((-x_mid, -(y_min + y_max) / 2, -z_mid))) @ body.matrix_world
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
co = np.array([v.co[:] for v in body.data.vertices])
y_min, y_max = co[:, 1].min(), co[:, 1].max()
length = y_max - y_min

# ---------- bones ----------
# Spine stations head -> tail along Y (head at y_max). The head bone covers the front
# 28%, the tail bone the last 14% (the fin), spine segments share the middle.
stations = [y_max, y_max - 0.28 * length]
mid_len = (0.86 - 0.28) * length
for i in range(1, SEGMENTS + 1):
    stations.append(y_max - 0.28 * length - mid_len * i / SEGMENTS)
stations.append(y_min)
names = ["Head"] + [f"Spine{i}" for i in range(1, SEGMENTS + 1)] + ["Tail"]

# The spine's height: follow the body's vertical middle in each stretch
def mid_z(lo, hi):
    band = co[(co[:, 1] >= min(lo, hi)) & (co[:, 1] <= max(lo, hi))]
    return float((band[:, 2].max() + band[:, 2].min()) / 2) if len(band) else 0.0


bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
arm = bpy.context.active_object
arm.name = "Armature"
eb = arm.data.edit_bones
for b in list(eb):
    eb.remove(b)


def bone(name, head, tail, parent=None, connect=False):
    b = eb.new(name)
    b.head = Vector(head)
    b.tail = Vector(tail)
    if parent:
        b.parent = eb[parent]
        b.use_connect = connect
    return b


bone("Root", (0, 0, 0), (0, 0, 0.1 * length))
segments = {}
parent = "Root"
for i, name in enumerate(names):
    a, b = stations[i], stations[i + 1]
    z = mid_z(a, b)
    # Bones point tailward: head at the front station, tail at the back one
    bone(name, (0, a, z), (0, b, z), parent, connect=(i > 0))
    segments[name] = (a, b)
    parent = name
bpy.ops.object.mode_set(mode="OBJECT")

# ---------- skinning: two nearest stations along the body, smooth hand-over ----------
centres = {name: (a + b) / 2 for name, (a, b) in segments.items()}
order = names
groups = {name: body.vertex_groups.new(name=name) for name in order}
ys = co[:, 1]
cs = np.array([centres[n] for n in order])
for i in range(len(co)):
    y = ys[i]
    # Which two bone centres bracket this vertex (head end has the highest y)
    j = int(np.argmin(np.abs(cs - y)))
    k = j + 1 if (j + 1 < len(cs) and y < cs[j]) else j - 1
    if k < 0 or k >= len(cs):
        groups[order[j]].add([i], 1.0, "REPLACE")
        continue
    span = abs(cs[j] - cs[k])
    t = abs(y - cs[j]) / span if span > 1e-6 else 0.0
    t = min(max(t, 0.0), 0.5)  # halfway at the boundary between the two
    # Smoothstep for a soft bend
    w = t * t * (3 - 2 * t)
    groups[order[j]].add([i], float(1 - w), "REPLACE")
    if w > 0.001:
        groups[order[k]].add([i], float(w), "REPLACE")

mod = body.modifiers.new("Armature", "ARMATURE")
mod.object = arm
body.parent = arm

# ---------- export ----------
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.fbx(
    filepath=OUT_PATH,
    use_selection=True,
    object_types={"ARMATURE", "MESH"},
    add_leaf_bones=False,
    bake_anim=False,
    axis_forward="-Z",
    axis_up="Y",
    # Bake the Z-up -> Y-up conversion into the mesh and bones (Studio drops a root
    # transform on skinned meshes; Hatch & Snatch's creatures once came in on their heads)
    bake_space_transform=True,
    apply_scale_options="FBX_SCALE_ALL",
    path_mode="COPY",
    embed_textures=True,
)
log("wrote", OUT_PATH, "bones", ", ".join(["Root"] + names))
