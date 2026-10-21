"""Squares up the rolled parts' Tripo models for the game and measures where each
attaches to a fish (2026-10-21, the parts of the approved PartsBoard sheet B).

    python3.11 tools/props/parts_prep.py <in dir of safe GLBs> <out dir> [--no-glow]

Each part is turned so the end that points toward the fish's nose is Blender +Y and
its up is +Z (the frame `rig_fish.py --static` gives prey: glTF -Z, which Roblox's
importer turns to face +Z, so `organize_imports` stamps it `Facing = "+Z"` and
Cosmetics turns it round), centred on its box, and written as a GLB. The sheets drew
each part's front on the picture's left, which Tripo puts on -Y (the lure's bulb on
the right): long, thin parts are squared up along their own axes first (PCA: the horn,
the saw, the sail kept the concept's three-quarter turn).

`parts.json` beside the GLBs holds each part's box and its attach point (where it
meets the fish: the horn's and the saw's base, the lure's stalk foot, the middle of
the sail's foot, the tail's stem), in units of its longest side, in the game's frame
(x right, y up, z back: Blender (x, z, -y)). Config/Exotics `model` copies them.

Glow: the parts' cyan (the lure's crystal, the saw's line, the sail's spines, the
veil's edge) becomes an emissive map, the colour itself over black, opened up a few
texels so no thin bright line sits alone on black (the screen distrusts those), so
the parts light up like the concept in dark water. `--no-glow` leaves it out.
"""

import json
import pathlib
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
IN_DIR, OUT_DIR = pathlib.Path(argv[0]), pathlib.Path(argv[1])
GLOW = "--no-glow" not in argv

# How each part is squared up: "pca" turns its own longest axis onto Y (`flat` names
# which of the other two becomes up: "mid" for a sail standing on its foot, "least"
# for the saw's blade lying flat); "plane" stands a flat part (the lure's arch, the
# tail's fan) upright in the body's plane: its thinnest axis, levelled, becomes X.
# `front` is which end of the picture faced the fish's nose, `attach` where it meets
# the fish
PARTS = {
    "AnglerLure": {"pca": False, "plane": True, "front": "right", "attach": "back"},
    "NarwhalHorn": {"pca": True, "flat": "mid", "front": "left", "attach": "back"},
    "SawSnout": {"pca": True, "flat": "least", "front": "left", "attach": "back"},
    "SailFin": {"pca": True, "flat": "mid", "front": "left", "attach": "foot"},
    "VeilTail": {"pca": False, "plane": True, "front": "left", "attach": "front"},
}


def mesh_points(objects) -> np.ndarray:
    points = []
    for o in objects:
        m = o.matrix_world
        points.extend((m @ v.co)[:] for v in o.data.vertices)
    return np.array(points, dtype=np.float64)


def turn(objects, matrix: Matrix):
    for o in objects:
        o.matrix_world = matrix @ o.matrix_world
    bpy.context.view_layer.update()


def glow_map(material, name: str):
    """Adds an emissive map from the base colour's bright cyan texels."""
    nodes = material.node_tree.nodes
    bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None or not bsdf.inputs["Base Color"].is_linked:
        return 0.0
    source = bsdf.inputs["Base Color"].links[0].from_node
    if source.type != "TEX_IMAGE" or source.image is None:
        return 0.0
    image = source.image
    w, h = image.size
    px = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)[..., :3]
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    hi, lo = px.max(-1), px.min(-1)
    sat = (hi - lo) / np.maximum(hi, 1e-4)
    # cyan to sky blue: green and blue both well over red, bright
    cyan = (g > r + 0.18) & (b > r + 0.18) & (hi > 0.55) & (sat > 0.3)
    try:
        from scipy import ndimage

        mask = ndimage.binary_dilation(cyan, iterations=2)
        soft = ndimage.gaussian_filter(mask.astype(np.float32), 1.5)
    except ImportError:
        soft = cyan.astype(np.float32)
    share = float(cyan.mean())
    if share < 0.002:
        return share
    tint = np.array([0.35, 0.95, 1.0], dtype=np.float32)
    rgb = np.where(cyan[..., None], px, tint) * soft[..., None]
    out = np.concatenate([rgb, np.ones((h, w, 1), np.float32)], -1)
    glow = bpy.data.images.new(f"{name}_Glow", w, h)
    glow.pixels[:] = out.ravel()
    glow.file_format = "PNG"
    glow.pack()
    node = nodes.new("ShaderNodeTexImage")
    node.image = glow
    material.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.0
    return share


def prep(name: str, how: dict) -> dict:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(IN_DIR / f"{name}.glb"))
    objects = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    points = mesh_points(objects)
    centre = points.mean(0)
    if how["pca"]:
        values, vectors = np.linalg.eigh(np.cov((points - centre).T))
        order = np.argsort(values)[::-1]
        long_axis = vectors[:, order[0]]
        up_axis = vectors[:, order[1] if how["flat"] == "mid" else order[2]]
    elif how.get("plane"):
        values, vectors = np.linalg.eigh(np.cov((points - centre).T))
        normal = vectors[:, int(np.argmin(values))].copy()
        normal[2] = 0.0
        normal /= max(np.linalg.norm(normal), 1e-9)
        up_axis = np.array([0.0, 0.0, 1.0])
        long_axis = np.cross(up_axis, normal)
    else:
        long_axis = np.array([0.0, 1.0, 0.0])
        up_axis = np.array([0.0, 0.0, 1.0])
    # Front: the picture's left is -Y in the Tripo model, its right +Y
    toward = np.array([0.0, -1.0, 0.0]) if how["front"] == "left" else np.array([0.0, 1.0, 0.0])
    if np.dot(long_axis, toward) < 0:
        long_axis = -long_axis
    if up_axis[2] < 0:
        up_axis = -up_axis
    y = Vector(long_axis).normalized()
    z = (Vector(up_axis) - y * Vector(up_axis).dot(y)).normalized()
    x = y.cross(z)
    rows = Matrix((x, y, z))  # world -> part frame (front +Y, up +Z)
    turn(objects, rows.to_4x4() @ Matrix.Translation(-Vector(centre)))
    points = mesh_points(objects)
    lo, hi = points.min(0), points.max(0)
    mid = (lo + hi) / 2
    turn(objects, Matrix.Translation(-Vector(mid)))
    points = points - mid
    lo, hi = points.min(0), points.max(0)
    size = hi - lo
    unit = float(size.max())
    band = 0.04 * unit
    if how["attach"] == "back":
        at = points[points[:, 1] < lo[1] + band].mean(0)
        at[1] = lo[1]
    elif how["attach"] == "front":
        at = points[points[:, 1] > hi[1] - band].mean(0)
        at[1] = hi[1]
    else:  # the foot: the middle of its lowest band
        foot = points[points[:, 2] < lo[2] + band]
        at = np.array([0.0, (foot[:, 1].min() + foot[:, 1].max()) / 2, lo[2]])
    glow = 0.0
    if GLOW:
        for material in {s.material for o in objects for s in o.material_slots if s.material}:
            glow = max(glow, glow_map(material, name))
    for o in objects:
        o.name = name
        o.data.name = name
    bpy.ops.object.select_all(action="SELECT")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_DIR / f"{name}.glb"), export_format="GLB", use_selection=True, export_yup=True
    )

    def game(v):  # Blender (x, y, z) -> the game's part frame (x, z, -y), in units
        return [round(float(v[0]) / unit, 4), round(float(v[2]) / unit, 4), round(-float(v[1]) / unit, 4)]

    box = game(size)
    record = {"box": [abs(c) for c in box], "attach": game(at), "glow": round(glow * 100, 2)}
    print(f"[parts_prep] {name}: box {record['box']} attach {record['attach']} glow {record['glow']}%")
    return record


records = {name: prep(name, how) for name, how in PARTS.items() if (IN_DIR / f"{name}.glb").exists()}
(OUT_DIR / "parts.json").write_text(json.dumps(records, indent=1) + "\n")
