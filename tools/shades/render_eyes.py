"""Close-ups of a fish's eyes in each of its skins, to check that no skin bleeds into
an eye (owner, 2026-10-17: "Every single skin on nibbler glitches into the eye").

    python3.11 tools/shades/render_eyes.py -- <fish.glb> <skins_dir> <out_dir> [res=300] [water=0.35] [maps=<dir>] [Shade ...]

Writes <out_dir>/<Fish>_<Shade>.png (the fish's own texture as <Fish>_Base.png): three
views side by side, the eye on the fish's right side-on, the eye on its left side-on,
and the face from the front three-quarter. The eyes' places come from the bake
(assets/shades/maps/<Fish>.npz, beside the skins dir's parent) and eyes.json, the
same spheres make_shades.py keeps the eyes in. Lay them out with contact_sheet.py
(`python3.11 tools/shades/contact_sheet.py <out_dir> sheet.jpg <Fish> 3 200`).
Each skin is worn the way render_shades.py wears it (finish, metal and glow maps).
"""

import json
import math
import pathlib
import sys

import bpy
import numpy as np
import shade_lines
from mathutils import Matrix, Vector
from PIL import Image
from scipy import ndimage

HERE = pathlib.Path(__file__).parent
argv = sys.argv[sys.argv.index("--") + 1 :]
SRC, SKINS, OUT = argv[0], pathlib.Path(argv[1]).resolve(), pathlib.Path(argv[2]).resolve()
rest = argv[3:]
OPTS = dict(a.split("=", 1) for a in rest if "=" in a)
RES = int(OPTS.get("res", 300))
WATER = float(OPTS.get("water", 0.0))
STRENGTH = float(OPTS.get("strength", 0.65))
WATER_TINT = np.array((222, 238, 246), np.float32) / 255
WATER_HAZE = np.array((44, 126, 156), np.float32) / 255
rest = [a for a in rest if "=" not in a]
NAME = pathlib.Path(SRC).stem
OUT.mkdir(parents=True, exist_ok=True)
MAPS = pathlib.Path(OPTS["maps"]).resolve() if "maps" in OPTS else SKINS.parent / "maps"
if not (MAPS / f"{NAME}.npz").exists():
    MAPS = HERE.parent.parent / "assets" / "shades" / "maps"


def eye_centres():
    """The eyes' centres and radii in the bake's body frame (make_shades Fish._eyes)."""
    d = np.load(MAPS / f"{NAME}.npz")
    pos = d["position"].astype(np.float32)
    size = pos.shape[0]
    cov = d["covered"]
    faces = d["faces"]
    picks = json.loads((HERE / "eyes.json").read_text())[NAME]["picks"]
    yy, xx = np.mgrid[0 : faces.shape[1], 0 : faces.shape[2]]
    out = []
    for view, px, py, radius in picks:
        face = faces[view]
        sel = ((xx - px) ** 2 + (yy - py) ** 2 <= radius * radius) & (face[..., 5] > 0.5)
        u, v = face[..., 3][sel], face[..., 4][sel]
        tx = np.clip((u % 1.0) * size, 0, size - 1).astype(int)
        ty = np.clip((1 - v % 1.0) * size, 0, size - 1).astype(int)
        hit = np.zeros((size, size), bool)
        hit[ty, tx] = True
        hit = ndimage.binary_closing(hit, iterations=3) & cov
        pts = pos[hit]
        centre = np.median(pts, 0)
        r3 = float(np.percentile(np.linalg.norm(pts - centre, axis=-1), 90))
        out.append((Vector(centre.tolist()), r3))
    return out


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
# Squared up exactly as bake_maps.py does, so the bake's eye places land on the eyes
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

bsdf = next(n for n in body.material_slots[0].material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
tex = bsdf.inputs["Base Color"].links[0].from_node
tree = body.material_slots[0].material.node_tree
for name in ("Metallic", "Roughness", "Emission Color", "Normal"):
    for link in list(bsdf.inputs[name].links):
        tree.links.remove(link)
bsdf.inputs["Metallic"].default_value = 0.0
own = tex.image
own_rough = bsdf.inputs["Roughness"].default_value


def map_node():
    node = tree.nodes.new("ShaderNodeTexImage")
    node.interpolation = tex.interpolation
    if tex.inputs["Vector"].links:
        tree.links.new(tex.inputs["Vector"].links[0].from_socket, node.inputs["Vector"])
    return node


rough_tex, metal_tex, emit_tex = map_node(), map_node(), map_node()

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 16
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = RES, RES
scene.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("W")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.05, 0.16, 0.24, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
for energy, rot in ((3.2, (50, 0, 30)), (1.2, (110, 0, 200)), (1.0, (60, 0, -150))):
    light = bpy.data.lights.new("Key", "SUN")
    light.energy = energy
    obj = bpy.data.objects.new("Key", light)
    obj.rotation_euler = tuple(math.radians(a) for a in rot)
    scene.collection.objects.link(obj)
cam_data = bpy.data.cameras.new("Cam")
cam_data.type = "ORTHO"
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

eyes = eye_centres()
right = max(eyes, key=lambda e: e[0].x)  # +X is the fish's right (render_shades' main view)
left = min(eyes, key=lambda e: e[0].x)
both = (right[0] + left[0]) / 2
span = max((right[0] - left[0]).length, 4 * max(right[1], left[1]))
# (target, direction from it to the camera, frame width)
SHOTS = [
    (right[0], Vector((1.0, -0.25, 0.12)).normalized(), right[1] * 3.2),
    (left[0], Vector((-1.0, -0.25, 0.12)).normalized(), left[1] * 3.2),
    (both, Vector((0.55, -1.0, 0.25)).normalized(), span * 1.9),
]


def grey(path):
    image = bpy.data.images.load(str(path))
    image.colorspace_settings.name = "Non-Color"
    return image


def wear(spec, folder, shade):
    for name in ("Roughness", "Metallic", "Emission Color"):
        for link in list(bsdf.inputs[name].links):
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
        bsdf.inputs["Emission Strength"].default_value = STRENGTH


def shoot(label, image):
    tex.image = image
    tiles = []
    for i, (target, direction, width) in enumerate(SHOTS):
        cam_data.ortho_scale = width
        cam.location = target + direction * length * 3
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        path = OUT / f"{NAME}_{label}.v{i}.png"
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        tiles.append(Image.open(path).convert("RGB"))
        path.unlink()
    strip = Image.new("RGB", (RES * len(tiles), RES))
    for i, t in enumerate(tiles):
        strip.paste(t, (RES * i, 0))
    if WATER > 0:
        rgb = np.asarray(strip, np.float32) / 255 * WATER_TINT
        rgb = rgb * (1 - WATER) + WATER_HAZE * WATER
        strip = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8))
    strip.save(OUT / f"{NAME}_{label}.png")


FOLDER = SKINS / NAME
specs = json.loads((FOLDER / "skins.json").read_text()) if (FOLDER / "skins.json").exists() else {}
wear(None, FOLDER, "Base")
shoot("Base", own)
shades = rest or [s for s in shade_lines.shades(NAME) if s in specs]
for shade in shades:
    path = FOLDER / f"{shade}.png"
    if path.exists():
        wear(specs.get(shade, {"finish": "satin"}), FOLDER, shade)
        shoot(shade, bpy.data.images.load(str(path)))
print(f"[eyes] {NAME}: {len(shades)} shades")
