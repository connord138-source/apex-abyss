"""Renders a rigged fish FBX (rig_fish.py --jaw [--fins]) with its jaw shut, at rest and
open, so a bad hand-over (a torn lip, a cheek dragged down, a tooth left behind)
shows before the model goes to Studio.

    <bpy python> tools/blender/jaw_check.py <in.fbx> <out.png> [--angles -12,0,28] [--view side|three]

Each angle (degrees; positive opens) is one picture of the head, side-on from +X with
the head on the LEFT (`--view three`: from the front three-quarters, below the eye
line, looking into the mouth). The frames are tiled left to right into one PNG.
With `--fins` in the rig, a last frame tilts the pectoral fins down 25°.
"""
import math
import os
import sys
import tempfile

import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
IN_PATH, OUT_PATH = argv[0], argv[1]
ANGLES = [float(a) for a in argv[argv.index("--angles") + 1].split(",")] if "--angles" in argv else [-12.0, 0.0, 28.0]
VIEW = argv[argv.index("--view") + 1] if "--view" in argv else "side"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=IN_PATH)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
body = next(o for o in bpy.data.objects if o.type == "MESH")
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 16
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = 720, 540
world = bpy.data.worlds.new("W")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.42, 0.5, 0.56, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.1
sun = bpy.data.lights.new("Sun", "SUN")
sun.energy = 3
so = bpy.data.objects.new("Sun", sun)
so.rotation_euler = (math.radians(40), math.radians(15), math.radians(35))
scene.collection.objects.link(so)

length = max(body.dimensions)
jaw = arm.pose.bones.get("Jaw")
fins = [arm.pose.bones.get(n) for n in ("FinL", "FinR")]
fins = [f for f in fins if f is not None]
if jaw is None:
    print("[jaw_check] no Jaw bone in", IN_PATH)
# The fish runs along Y with its head at -Y (rig_fish.py), Z up
to_arm = arm.matrix_world.inverted().to_3x3()
lateral = (to_arm @ Vector((1, 0, 0))).normalized()
along = (to_arm @ Vector((0, 1, 0))).normalized()


def pose_about(pb, axis, degrees):
    rest = pb.bone.matrix_local
    pivot = rest.translation
    pb.matrix = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(degrees), 4, axis) @ Matrix.Translation(-pivot) @ rest


hinge = arm.matrix_world @ jaw.bone.head_local if jaw else Vector((0, -0.3 * length, -0.08 * length))
focus = Vector((0, hinge.y - 0.06 * length, hinge.z))
cam = bpy.data.cameras.new("Cam")
cam.type = "ORTHO"
cam.ortho_scale = length * 0.42
co = bpy.data.objects.new("Cam", cam)
scene.collection.objects.link(co)
if VIEW == "three":
    direction = Vector((0.75, -1.0, -0.12)).normalized()
else:
    direction = Vector((1, 0, 0))
co.location = focus + direction * length * 3
co.rotation_euler = (focus - co.location).to_track_quat("-Z", "Y").to_euler()
scene.camera = co

frames = []
tmp = tempfile.mkdtemp()
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")
shots = [("jaw", a) for a in ANGLES] + ([("fins", 25.0)] if fins else [])
for i, (kind, angle) in enumerate(shots):
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    if kind == "jaw" and jaw is not None:
        pose_about(jaw, lateral, angle)
    elif kind == "fins":
        for pb in fins:
            # Each fin's trailing edge tips down (about the body's long axis, the left
            # fin one way and the right the other)
            side = 1 if (arm.matrix_world @ pb.bone.head_local).x > 0 else -1
            pose_about(pb, along, -side * angle)
    bpy.context.view_layer.update()
    path = os.path.join(tmp, f"{i}.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    frames.append(path)
bpy.ops.object.mode_set(mode="OBJECT")

# Tile them
images = [bpy.data.images.load(p) for p in frames]
w, h = images[0].size
out = bpy.data.images.new("Sheet", w * len(images), h, alpha=False)
pixels = [0.0] * (w * len(images) * h * 4)
for k, img in enumerate(images):
    src = list(img.pixels)
    for row in range(h):
        start = (row * w * len(images) + k * w) * 4
        pixels[start : start + w * 4] = src[row * w * 4 : (row + 1) * w * 4]
out.pixels = pixels
out.filepath_raw = OUT_PATH
out.file_format = "PNG"
out.save()
print("[jaw_check] wrote", OUT_PATH, "angles", ANGLES, "fins" if fins else "")
