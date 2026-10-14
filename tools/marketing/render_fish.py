"""Renders one fish wearing one of its real skins on a transparent background, for
shop art built from the game itself (the Deep Pass icon: compose.py `pass`).

    python3.11 tools/marketing/render_fish.py -- <fish.glb> <skins_dir> <Shade> <out.png> [size] [view]

The fish is squared up the way tools/shades/render_shades.py does it (longest axis
along Y, head toward -Y), then shot in perspective three-quarter from the front and a
little below with a key, a fill and a cyan rim light. The skin's colour, roughness
(its finish) and glow maps are wired the way they ship; its relief map is not used.
`view` is x,y,z (the camera's direction from the fish, before normalising).
"""

import json
import math
import pathlib
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :]
SRC, SKINS, SHADE, OUT = argv[0], pathlib.Path(argv[1]).resolve(), argv[2], pathlib.Path(argv[3]).resolve()
SIZE = int(argv[4]) if len(argv) > 4 else 1400
VIEW = Vector(tuple(float(v) for v in argv[5].split(","))) if len(argv) > 5 else Vector((1.0, -1.1, 0.12))
NAME = pathlib.Path(SRC).stem

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


if not girth(0.08, 0.3) > girth(0.7, 0.92):
    body.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
co = np.array([v.co[:] for v in body.data.vertices])
mn, mx = co.min(0), co.max(0)
mid = Vector(((mn + mx) / 2).tolist())

# The skin: colour, its finish's roughness, its glow
tree = body.material_slots[0].material.node_tree
bsdf = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")
tex = bsdf.inputs["Base Color"].links[0].from_node
for name in ("Metallic", "Roughness", "Emission Color", "Normal"):
    for link in list(bsdf.inputs[name].links):
        tree.links.remove(link)
bsdf.inputs["Metallic"].default_value = 0.0
folder = SKINS / NAME
spec = json.loads((folder / "skins.json").read_text()).get(SHADE, {})
tex.image = bpy.data.images.load(str(folder / f"{SHADE}.png"))


def side_map(path, colour=False):
    node = tree.nodes.new("ShaderNodeTexImage")
    node.image = bpy.data.images.load(str(path))
    if not colour:
        node.image.colorspace_settings.name = "Non-Color"
    if tex.inputs["Vector"].links:
        tree.links.new(tex.inputs["Vector"].links[0].from_socket, node.inputs["Vector"])
    return node


rough = folder / f"finish_{spec.get('finish', 'satin')}.png"
if rough.exists():
    tree.links.new(side_map(rough).outputs["Color"], bsdf.inputs["Roughness"])
if spec.get("emit"):
    tree.links.new(side_map(folder / f"{SHADE}_emit.png", True).outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 2.6

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 96
scene.cycles.use_denoising = True
scene.render.film_transparent = True
scene.render.resolution_x = scene.render.resolution_y = SIZE
scene.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("W")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.04, 0.13, 0.22, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7


def light(kind, energy, rot, colour=(1, 1, 1)):
    data = bpy.data.lights.new(kind, "SUN")
    data.energy = energy
    data.color = colour
    obj = bpy.data.objects.new(kind, data)
    obj.rotation_euler = tuple(math.radians(a) for a in rot)
    scene.collection.objects.link(obj)


light("Key", 3.4, (40, 0, 40))  # from above, front-right
light("Fill", 0.9, (100, 0, -60), (0.7, 0.85, 1.0))
light("Rim", 4.0, (-60, 0, 200), (0.45, 0.95, 1.0))  # cyan from behind

cam_data = bpy.data.cameras.new("Cam")
cam_data.lens = 70
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
direction = VIEW.normalized()
cam.location = mid + direction * length * 2.6
cam.rotation_euler = (mid - cam.location).to_track_quat("-Z", "Y").to_euler()
OUT.parent.mkdir(parents=True, exist_ok=True)
scene.render.filepath = str(OUT)
bpy.ops.render.render(write_still=True)
print(f"[render_fish] {NAME} in {SHADE} -> {OUT}")
