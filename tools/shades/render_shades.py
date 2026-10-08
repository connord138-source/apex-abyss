"""Renders a fish wearing each of its shade skins, three-quarter view, for review.

    <blender python> tools/shades/render_shades.py -- <fish.glb> <skins_dir> <out_dir> [flip] [Shade ...]

Writes <out_dir>/<Fish>_<Shade>.png (the fish's own texture as <Fish>_Base.png).
contact_sheet.py lays them out. Each skin is shown the way it ships: its finish's
roughness map (or its own), its metal map and its glow map, from skins.json.
"""

import json
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
tree = body.material_slots[0].material.node_tree
for name in ("Metallic", "Roughness", "Emission Color"):
    for link in list(bsdf.inputs[name].links):
        tree.links.remove(link)
bsdf.inputs["Metallic"].default_value = 0.0
own = tex.image


def map_node(label):
    node = tree.nodes.new("ShaderNodeTexImage")
    node.label = label
    node.interpolation = tex.interpolation
    if tex.inputs["Vector"].links:
        tree.links.new(tex.inputs["Vector"].links[0].from_socket, node.inputs["Vector"])
    return node


rough_tex, metal_tex, emit_tex = map_node("rough"), map_node("metal"), map_node("emit")
own_rough = bsdf.inputs["Roughness"].default_value

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


def grey(path):
    image = bpy.data.images.load(str(path))
    image.colorspace_settings.name = "Non-Color"
    return image


def wear(spec, folder, shade):
    """Wires a skin's roughness, metal and glow maps (none for the fish's own look)."""
    for link in list(bsdf.inputs["Roughness"].links) + list(bsdf.inputs["Metallic"].links):
        tree.links.remove(link)
    for link in list(bsdf.inputs["Emission Color"].links):
        tree.links.remove(link)
    bsdf.inputs["Roughness"].default_value = own_rough
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Emission Strength"].default_value = 0.0
    if spec is None:
        return
    rough = folder / (f"{shade}_rough.png" if spec.get("rough") else f"finish_{spec['finish']}.png")
    if rough.exists():
        rough_tex.image = grey(rough)
        tree.links.new(rough_tex.outputs["Color"], bsdf.inputs["Roughness"])
    if spec.get("metal"):
        metal_tex.image = grey(folder / f"{shade}_metal.png")
        tree.links.new(metal_tex.outputs["Color"], bsdf.inputs["Metallic"])
    if spec.get("emit"):
        emit_tex.image = bpy.data.images.load(str(folder / f"{shade}_emit.png"))
        tree.links.new(emit_tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 3.0


def shoot(label, image):
    tex.image = image
    scene.render.filepath = str(OUT / f"{NAME}_{label}.png")
    bpy.ops.render.render(write_still=True)


FOLDER = SKINS / NAME
specs = json.loads((FOLDER / "skins.json").read_text()) if (FOLDER / "skins.json").exists() else {}
wear(None, FOLDER, "Base")
shoot("Base", own)
shades = rest or sorted(specs) or sorted(
    p.stem for p in FOLDER.glob("*.png") if p.stem != "eyes_debug" and "_" not in p.stem
)
for shade in shades:
    path = FOLDER / f"{shade}.png"
    if path.exists():
        wear(specs.get(shade, {"finish": "satin"}), FOLDER, shade)
        shoot(shade, bpy.data.images.load(str(path)))
print(f"[render] {NAME}: {len(shades)} shades")
