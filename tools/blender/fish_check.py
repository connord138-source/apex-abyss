"""Renders a rigged fish FBX (from rig_fish.py) in a swimming pose, to check the head
guess, the bone chain and the skin weights before importing into Studio.

    <bpy python> tools/blender/fish_check.py <in.fbx> <out.png>

Left: rest pose from the side (head should be on the LEFT). Right: the spine bent
with a travelling wave, from above, so stretched or torn skin shows up.
"""
import math
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
IN_PATH, OUT_PATH = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=IN_PATH)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
body = next(o for o in bpy.data.objects if o.type == "MESH")
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 16
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = 1200, 600
world = bpy.data.worlds.new("W")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.35, 0.42, 0.46, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
sun = bpy.data.lights.new("Sun", "SUN")
sun.energy = 3
so = bpy.data.objects.new("Sun", sun)
so.rotation_euler = (math.radians(50), math.radians(10), math.radians(30))
scene.collection.objects.link(so)

# The body axis from the rig itself (the Head bone points head -> tail), so the
# camera is side-on whatever shape the fish is (a round fish's fin span can beat
# its length, which fooled a bounding-box guess)
size = body.dimensions
length = max(size)
centre = body.matrix_world @ (0.125 * sum((Vector(c) for c in body.bound_box), Vector()))
# Bone positions survive the FBX round trip; bone directions don't (the importer
# re-orients them), so take the axis from the Head and Tail bones' positions
head_bone = arm.data.bones.get("Head")
tail_bone = arm.data.bones.get("Tail")
if head_bone and tail_bone:
    axis = arm.matrix_world.to_3x3() @ (tail_bone.head_local - head_bone.head_local)
else:
    axis = Vector((0, 1, 0))
axis.z = 0
axis.normalize()
side = Vector((-axis.y, axis.x, 0))  # perpendicular, horizontal
print("[fish_check] dims", tuple(round(v, 3) for v in size), "axis", tuple(round(v, 3) for v in axis), "side", tuple(round(v, 3) for v in side))
if head_bone and tail_bone:
    print("[fish_check] head bone at", tuple(round(v, 3) for v in (arm.matrix_world @ head_bone.head_local)), "tail bone at", tuple(round(v, 3) for v in (arm.matrix_world @ tail_bone.head_local)))

# A second copy, posed
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
body.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.duplicate()
arm2 = bpy.context.view_layer.objects.active
body2 = next(o for o in bpy.context.selected_objects if o.type == "MESH")
offset = axis * (length * 1.7)
arm2.location += offset
bpy.context.view_layer.objects.active = arm2
bpy.ops.object.mode_set(mode="POSE")
chain = ["Head", "Spine1", "Spine2", "Spine3", "Spine4", "Spine5", "Tail"]
for i, name in enumerate(chain):
    pb = arm2.pose.bones.get(name)
    if pb is None:
        continue
    phase = i * 0.9
    amplitude = 0.08 + 0.1 * i / len(chain)
    pb.rotation_mode = "XYZ"
    # Bend about the bone's own up axis (yaw), the swim wave
    pb.rotation_euler = (0, 0, math.sin(phase) * amplitude * 2.2)
bpy.ops.object.mode_set(mode="OBJECT")

cam = bpy.data.cameras.new("Cam")
cam.type = "ORTHO"
cam.ortho_scale = length * 3.6
co = bpy.data.objects.new("Cam", cam)
scene.collection.objects.link(co)
mid = centre + offset / 2
# Side-on and raised 35°, so the head end (should be on the LEFT) and the yaw bend
# of the posed copy both show
elevation = math.radians(35)
co.location = mid + side * (length * 4 * math.cos(elevation)) + Vector((0, 0, length * 4 * math.sin(elevation)))
direction = mid - co.location
co.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
scene.camera = co
scene.render.filepath = OUT_PATH
bpy.ops.render.render(write_still=True)
print("[fish_check] wrote", OUT_PATH)
