"""Renders a rigged fish FBX in the poses PredatorController drives (the swim wave,
a C-bend and bank in a burst-turn, a bite's tell with the jaw open and the fins
hunched, the snap with a head shake, a charge, a breach), to check a rig moves as one
body before it goes to Studio: no tearing at the jaw, the fins or the neck.

    <bpy python> tools/blender/pose_check.py <in.fbx> <out.png> [--poses cruise,turn,tell,snap,charge,breach] [--top] [--jaw C,W,S]

`--jaw cruise,wide,shut` (radians) sets the jaw to that rig's own range from
PredatorController's JAW table (the Megalodon's -0.05,0.5,-0.2 by default; the Reef
Shark 0.07,0.36,-0.08, the Barracuda 0.03,0.42,-0.12).

The pose maths mirrors src/shared/SwimWave.luau (yaw per spine bone, the head turned
about its neck, the arch) and PredatorController's jaw, fin and roll values, in
Blender's axes (the fish along Y with its head at -Y, Z up: a turn about Z is a
yaw, a jaw opens about +X, the +X fin (FinL) droops about +Y). Frames are tiled
three to a row, each from the front three-quarters a little above.
"""
import math
import os
import sys
import tempfile

import bpy
from mathutils import Matrix, Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
IN_PATH, OUT_PATH = argv[0], argv[1]
POSES = argv[argv.index("--poses") + 1].split(",") if "--poses" in argv else ["cruise", "turn", "tell", "snap", "charge", "breach"]

# name: (phase, amplitude, bend, arch, look, gape, fin droop, fin sweep, roll, body pitch degrees)
SPECS = {
    "cruise": (1.0, 0.08, 0.0, 0.0, 0.0, -0.05, 0.0, 0.05, 0.0, 0),
    # (a right turn: + bend swings the tail to the fish's right, concave into the turn,
    # the head eyeing right and the body banked right side down, belly out)
    "turn": (2.2, 0.12, 0.2, 0.0, -0.15, -0.05, 0.1, 0.05, -0.9, 0),
    "tell": (0.6, 0.06, 0.1, 0.0, 0.2, 0.5, 0.32, 0.05, 0.1, 0),
    "snap": (0.6, 0.06, 0.05, 0.0, -0.22, -0.2, 0.2, 0.05, 0.12, 0),
    "charge": (3.0, 0.22, 0.0, 0.0, 0.0, 0.45, -0.12, 0.35, 0.0, 0),
    "breach": (2.0, 0.2, 0.0, 0.08, 0.0, 0.45, -0.12, 0.35, 0.0, 70),
    # The Giant Squid's arms: writhing, curled up to reach in a grab's tell, streamed in a jet
    "writhe": (1.5, 0.1, 0.05, 0.15, 0.0, 0.0, 0.0, 0.0, 0.0, 0),
    "reach": (1.5, 0.08, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0),
    "jet": (1.5, 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0),
}


if "--jaw" in argv:
    cruise, wide, shut = (float(v) for v in argv[argv.index("--jaw") + 1].split(","))
    gapes = {"cruise": cruise, "turn": cruise, "tell": wide, "snap": shut, "charge": wide * 0.9, "breach": wide * 0.9}
    for name, gape in gapes.items():
        spec = list(SPECS[name])
        spec[5] = gape
        SPECS[name] = tuple(spec)


def envelope(t):
    return 0.06 + 0.94 * t ** 1.9


def spread(n):
    return 2.0 + 0.3 * max(n - 3, 0)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=IN_PATH)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
body = next(o for o in bpy.data.objects if o.type == "MESH")
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 16
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = 640, 480
world = bpy.data.worlds.new("W")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.3, 0.42, 0.52, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
sun = bpy.data.lights.new("Sun", "SUN")
sun.energy = 3
so = bpy.data.objects.new("Sun", sun)
so.rotation_euler = (math.radians(35), math.radians(15), math.radians(30))
scene.collection.objects.link(so)

length = max(body.dimensions)
bones = arm.pose.bones
spine = []
i = 1
while bones.get(f"Spine{i}"):
    spine.append(f"Spine{i}")
    i += 1
if bones.get("Tail"):
    spine.append("Tail")
n = len(spine)
soften = (3 / n) ** 0.6 if n else 1
to_arm = arm.matrix_world.inverted().to_3x3()


def fish_axis(v):
    return (to_arm @ Vector(v)).normalized()


UP, LATERAL, ALONG = fish_axis((0, 0, 1)), fish_axis((1, 0, 0)), fish_axis((0, 1, 0))


def local_rotation(pb, axis, angle):
    """A rotation about a fish axis (armature space), in the bone's own space."""
    rest = pb.bone.matrix_local.to_quaternion()
    q = Quaternion(axis, angle)
    return rest.inverted() @ q @ rest


def pose(spec):
    phase, amplitude, bend, arch, look, gape, droop, sweep, roll, pitch = spec
    for pb in bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    amp, bnd, arc = amplitude * 1.6 * soften, bend * soften, arch * soften
    head = bones.get("Head")
    if head:
        yaw = bnd * 0.25
        q = Quaternion(UP, yaw)
        if look and n:
            # About the neck (the first spine joint), the body behind held
            neck = bones[spine[0]].bone.head_local - head.bone.head_local
            ql = Quaternion(UP, look)
            offset = neck - ql @ neck
            q = q @ ql
            rest = head.bone.matrix_local.to_quaternion()
            head.location = rest.inverted() @ (Quaternion(UP, yaw) @ offset)
        rest = head.bone.matrix_local.to_quaternion()
        head.rotation_quaternion = rest.inverted() @ q @ rest
    for k, name in enumerate(spine, start=1):
        t = k / n
        yaw = math.sin(phase - spread(n) * t) * amp * envelope(t) + bnd * (0.3 + 0.7 * t)
        if k == 1 and look:
            yaw -= look
        q = Quaternion(UP, yaw) @ Quaternion(LATERAL, -arc * (0.3 + 0.7 * t))
        rest = bones[name].bone.matrix_local.to_quaternion()
        bones[name].rotation_quaternion = rest.inverted() @ q @ rest
    if bones.get("Jaw"):
        bones["Jaw"].rotation_quaternion = local_rotation(bones["Jaw"], LATERAL, gape)
    for name, side in (("FinL", 1), ("FinR", -1)):
        pb = bones.get(name)
        if pb:
            q = Quaternion(ALONG, side * droop) @ Quaternion(UP, side * sweep)
            rest = pb.bone.matrix_local.to_quaternion()
            pb.rotation_quaternion = rest.inverted() @ q @ rest
    # The whole body: banked (belly out) and pitched (a breach)
    arm.rotation_euler = (math.radians(-pitch), roll, 0)


centre = body.matrix_world @ (0.125 * sum((Vector(c) for c in body.bound_box), Vector()))
cam = bpy.data.cameras.new("Cam")
cam.type = "ORTHO"
cam.ortho_scale = length * 1.25
co = bpy.data.objects.new("Cam", cam)
scene.collection.objects.link(co)
# (`--top`: from straight above, for the C-bend and the head's turn)
direction = Vector((0.05, -0.05, 1)).normalized() if "--top" in argv else Vector((0.8, -0.75, 0.45)).normalized()
co.location = centre + direction * length * 4
co.rotation_euler = (centre - co.location).to_track_quat("-Z", "Y").to_euler()
scene.camera = co

bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")
tmp = tempfile.mkdtemp()
frames = []
for k, name in enumerate(POSES):
    pose(SPECS[name])
    bpy.context.view_layer.update()
    path = os.path.join(tmp, f"{k}.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    frames.append(path)
bpy.ops.object.mode_set(mode="OBJECT")

images = [bpy.data.images.load(p) for p in frames]
w, h = images[0].size
cols = min(3, len(images))
rows = (len(images) + cols - 1) // cols
out = bpy.data.images.new("Sheet", w * cols, h * rows, alpha=False)
pixels = [0.0] * (w * cols * h * rows * 4)
for k, img in enumerate(images):
    src = list(img.pixels)
    col, row = k % cols, rows - 1 - k // cols
    for y in range(h):
        start = ((row * h + y) * w * cols + col * w) * 4
        pixels[start : start + w * 4] = src[y * w * 4 : (y + 1) * w * 4]
out.pixels = pixels
out.filepath_raw = OUT_PATH
out.file_format = "PNG"
out.save()
print("[pose_check] wrote", OUT_PATH, "poses", ",".join(POSES))
