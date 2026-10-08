"""Renders a fish wearing each of its shade skins, three-quarter view, for review.

    <blender python> tools/shades/render_shades.py -- <fish.glb> <skins_dir> <out_dir> [flip] [Shade ...]

Writes <out_dir>/<Fish>_<Shade>.png (the fish's own texture as <Fish>_Base.png).
contact_sheet.py lays them out.
"""

import math
import pathlib
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :]
SRC, SKINS, OUT = argv[0], pathlib.Path(argv[1]).resolve(), pathlib.Path(argv[2]).resolve()
rest = argv[3:]
FLIP = bool(rest) and rest[0] == "flip"
if FLIP:
    rest = rest[1:]
NAME = pathlib.Path(SRC).stem
OUT.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
if len(meshes) > 1:
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.data.transform(body.matrix_world)
body.matrix_world = Matrix.Identity(4)
co = np.array([v.co[:] for v in body.data.vertices])
centre = (co.max(0) + co.min(0)) / 2
body.data.transform(Matrix.Translation(-Vector(centre)))
co -= centre
evals, evecs = np.linalg.eigh(np.cov(co[:, :2].T))
axis = evecs[:, np.argmax(evals)]
body.data.transform(Matrix.Rotation(math.atan2(axis[0], axis[1]), 4, "Z"))
co = np.array([v.co[:] for v in body.data.vertices])
y0, length = co[:, 1].min(), np.ptp(co[:, 1])


def girth(lo, hi):
    band = co[(co[:, 1] >= y0 + lo * length) & (co[:, 1] < y0 + hi * length)]
    return np.ptp(band[:, 0]) * np.ptp(band[:, 2]) if len(band) >= 8 else 0.0


head_low = girth(0.08, 0.3) > girth(0.7, 0.92)
if FLIP:
    head_low = not head_low
if not head_low:
    body.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
co = np.array([v.co[:] for v in body.data.vertices])
mn, mx = co.min(0), co.max(0)
mid = Vector(((mn + mx) / 2).tolist())

# The color texture node, to swap skins into
bsdf = next(n for n in body.material_slots[0].material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
tex = bsdf.inputs["Base Color"].links[0].from_node
bsdf.inputs["Metallic"].default_value = 0.0
if bsdf.inputs["Metallic"].links:
    body.material_slots[0].material.node_tree.links.remove(bsdf.inputs["Metallic"].links[0])
own = tex.image

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 24
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = 520, 360
scene.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("W")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.05, 0.16, 0.24, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
for energy, rot in ((3.2, (50, 0, 30)), (1.2, (110, 0, 200))):
    light = bpy.data.lights.new("Key", "SUN")
    light.energy = energy
    obj = bpy.data.objects.new("Key", light)
    obj.rotation_euler = tuple(math.radians(a) for a in rot)
    scene.collection.objects.link(obj)
cam_data = bpy.data.cameras.new("Cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = length * 1.25
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
direction = Vector((1.0, -0.55, 0.35)).normalized()  # three-quarter from the fish's right, head forward
cam.location = mid + direction * length * 3
cam.rotation_euler = (mid - cam.location).to_track_quat("-Z", "Y").to_euler()


def shoot(label, image):
    tex.image = image
    scene.render.filepath = str(OUT / f"{NAME}_{label}.png")
    bpy.ops.render.render(write_still=True)


shoot("Base", own)
shades = rest or sorted(p.stem for p in (SKINS / NAME).glob("*.png") if p.stem != "eyes_debug")
for shade in shades:
    path = SKINS / NAME / f"{shade}.png"
    if path.exists():
        shoot(shade, bpy.data.images.load(str(path)))
print(f"[render] {NAME}: {len(shades)} shades")
