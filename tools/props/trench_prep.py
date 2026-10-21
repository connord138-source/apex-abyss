"""Readies the Abyssal Trench's and the Open Blue's models for the landmark rebuild
(owner, 2026-10-21: "look how much different your hole looks from the mockup", "really
everything other than the whale, ship and lighthouse needs more detail and more
intricacy"): the new Leviathan bones, a violet and a cyan variant of the crystals and
glow tubes, and glow maps so the bioluminescent pieces light up in the dark like the
approved scene (assets/tripo/biome_concepts/TrenchScene.png).

    python3.11 tools/props/trench_prep.py <safe GLB dir> <out dir>

Inputs are GLBs already through strip_normals.py and safe_colors.py (the shipped
biome_trench_glb and biome_blue_glb pieces, and the new LeviathanVertebra,
LeviathanRib and SquidBeak). Run strip_normals.py and the screen on the output.

- LeviathanRib: Tripo drew a gently bent bone; it's bent into a quarter ellipse in
  Blender's XZ plane (its knob at the top on -X, its tip at the bottom on +X, thin
  along Y), 0.82 as wide as it is tall, so TrenchDress hangs it from the spine down
  to the canyon floor (in Roblox the importer's half turn puts the knob on +X).
- LeviathanVertebra, SquidBeak: centred on their boxes.
- Glow: the bright cyan, teal or violet texels become an emissive map (the colour
  itself over black, opened up a little so no thin bright line sits alone on black,
  the screen's rule), as tools/props/parts_prep.py does for the rolled parts.
- Variants: TrenchCrystalsViolet (the cyan crystals turned violet, rock unchanged)
  and TrenchGlowTubesCyan (the violet tubes turned cyan), so the walls carry both
  colours like the concept without new models.
"""

import colorsys
import math
import os
import pathlib
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
IN_DIR, OUT_DIR = pathlib.Path(argv[0]), pathlib.Path(argv[1])
OUT_DIR.mkdir(parents=True, exist_ok=True)

# name -> (source, glow rule, hue turn)
JOBS = {
    "LeviathanVertebra": ("LeviathanVertebra", "cyan", None),
    "LeviathanRib": ("LeviathanRib", "pale", None),
    "SquidBeak": ("SquidBeak", None, None),
    "LeviathanSkull": ("LeviathanSkull", "teal", None),
    "BoneHeap": ("BoneHeap", "teal", None),
    "TrenchCrystals": ("TrenchCrystals", "cyan", None),
    "TrenchCrystalsViolet": ("TrenchCrystals", "violet", ("cyan", 0.77)),
    "TrenchGlowTubes": ("TrenchGlowTubes", "violet", None),
    "TrenchGlowTubesCyan": ("TrenchGlowTubes", "cyan", ("violet", 0.5)),
    "GlowEggs": ("GlowEggs", "teal", None),
    "JellyChain": ("JellyChain", "violet", None),
}
RIB_ASPECT = 0.82  # width / height of the bent rib's box
RIB_THIN = 0.55  # its cross-section, thinned: Tripo's bone was a femur's girth for a rib
ONLY = [n for n in os.environ.get("ONLY", "").split(",") if n]


def load(source: str):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(IN_DIR / f"{source}.glb"))
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def points(objects) -> np.ndarray:
    out = []
    for o in objects:
        m = o.matrix_world
        out.extend((m @ v.co)[:] for v in o.data.vertices)
    return np.array(out, dtype=np.float64)


def apply_transforms(objects):
    for o in objects:
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
        o.parent = None


def centre(objects):
    p = points(objects)
    mid = (p.min(0) + p.max(0)) / 2
    for o in objects:
        o.data.transform(Matrix.Translation(-Vector(mid)))
    return p.max(0) - p.min(0)


def bend_rib(objects):
    """A gently bent bone, knob at one end, into a quarter ellipse in XZ."""
    apply_transforms(objects)
    p = points(objects)
    mid = p.mean(0)
    values, vectors = np.linalg.eigh(np.cov((p - mid).T))
    order = np.argsort(values)[::-1]
    long_axis, curve_axis, thin_axis = (vectors[:, order[k]] for k in range(3))
    s_all = (p - mid) @ long_axis
    lo, hi = s_all.min(), s_all.max()
    # The knob end is the wider one (spread across the curve plane at each end)
    u_all = (p - mid) @ curve_axis
    v_all = (p - mid) @ thin_axis
    end = (hi - lo) * 0.12

    def spread(mask):
        return float(np.ptp(u_all[mask]) + np.ptp(v_all[mask])) if mask.any() else 0.0

    if spread(s_all > hi - end) < spread(s_all < lo + end):
        long_axis = -long_axis
        s_all = -s_all
        lo, hi = -hi, -lo
    length = hi - lo
    phi = math.pi / 2
    radius = length / phi
    for o in objects:
        for vert in o.data.vertices:
            q = np.array(vert.co[:]) - mid
            s = (hi - float(q @ long_axis)) / length  # 0 at the knob, 1 at the tip
            u = float(q @ curve_axis) * RIB_THIN
            v = float(q @ thin_axis) * RIB_THIN
            theta = math.pi / 2 - s * phi
            r = radius - u
            vert.co = Vector((r * math.cos(theta) * RIB_ASPECT, v, r * math.sin(theta)))
    # The arc runs from the knob at (0, R) to the tip at (R, 0) in XZ: centred, the knob
    # is at the top on -X and the tip at the bottom on +X
    return centre(objects)


def texture_of(material):
    nodes = material.node_tree.nodes
    bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None or not bsdf.inputs["Base Color"].is_linked:
        return None, None
    source = bsdf.inputs["Base Color"].links[0].from_node
    if source.type != "TEX_IMAGE" or source.image is None:
        return None, None
    return bsdf, source.image


def pixels(image) -> np.ndarray:
    w, h = image.size
    return np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)


def masks(px: np.ndarray) -> dict:
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    hi, lo = px[..., :3].max(-1), px[..., :3].min(-1)
    sat = (hi - lo) / np.maximum(hi, 1e-4)
    return {
        "cyan": (g > r + 0.18) & (b > r + 0.18) & (hi > 0.55) & (sat > 0.3),
        "teal": (g > r + 0.12) & (b > r + 0.08) & (hi > 0.42) & (sat > 0.25),
        "violet": (b > g + 0.12) & (r > g + 0.04) & (hi > 0.45) & (sat > 0.2),
        # the rib's pale blue worm bands (the bone itself is a cool neutral white)
        "pale": (b > r + 0.1) & (g > r + 0.05) & (hi > 0.5) & (sat > 0.14),
    }


def turn_hue(image, rule: str, hue: float):
    """Turns the texels `rule` picks (cyan or violet) to `hue` (0-1), same S and V."""
    px = pixels(image)
    pick = masks(px)[rule]
    try:
        from scipy import ndimage

        pick = ndimage.binary_dilation(pick, iterations=1)
    except ImportError:
        pass
    rgb = px[..., :3]
    out = rgb.copy()
    ys, xs = np.nonzero(pick)
    for y, x in zip(ys, xs):
        h, s, v = colorsys.rgb_to_hsv(*rgb[y, x])
        if s > 0.12:
            out[y, x] = colorsys.hsv_to_rgb(hue, s, v)
    px[..., :3] = out
    image.pixels[:] = px.ravel()
    image.update()
    image.pack()
    return float(pick.mean())


def glow_map(material, rule: str, name: str) -> float:
    bsdf, image = texture_of(material)
    if image is None:
        return 0.0
    px = pixels(image)
    pick = masks(px)[rule]
    share = float(pick.mean())
    if share < 0.002:
        return share
    try:
        from scipy import ndimage

        mask = ndimage.binary_dilation(pick, iterations=2)
        soft = ndimage.gaussian_filter(mask.astype(np.float32), 1.5)
    except ImportError:
        soft = pick.astype(np.float32)
    rgb = px[..., :3]
    tint = rgb[pick].mean(0)
    out = np.where(pick[..., None], rgb, tint) * soft[..., None]
    h, w = out.shape[:2]
    glow = bpy.data.images.new(f"{name}_Glow", w, h)
    glow.pixels[:] = np.concatenate([out, np.ones((h, w, 1), np.float32)], -1).ravel()
    glow.file_format = "PNG"
    glow.pack()
    node = material.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = glow
    material.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.0
    return share


def main():
    for name, (source, rule, hue) in JOBS.items():
        if ONLY and name not in ONLY:
            continue
        if not (IN_DIR / f"{source}.glb").exists():
            print(f"{name}: no {source}.glb, skipped")
            continue
        objects = load(source)
        apply_transforms(objects)
        if name == "LeviathanRib":
            ext = bend_rib(objects)
        else:
            ext = centre(objects)
        turned = 0.0
        glowing = 0.0
        seen = set()
        for o in objects:
            for slot in o.material_slots:
                material = slot.material
                if material is None or material.name in seen or not material.use_nodes:
                    continue
                seen.add(material.name)
                if hue:
                    _, image = texture_of(material)
                    if image is not None:
                        image = image.copy()
                        image.name = f"{name}_Color"
                        bsdf, old = texture_of(material)
                        for node in material.node_tree.nodes:
                            if node.type == "TEX_IMAGE" and node.image == old:
                                node.image = image
                        turned = turn_hue(image, hue[0], hue[1])
                if rule:
                    glowing = glow_map(material, rule, name)
        for o in objects:
            o.select_set(True)
        bpy.ops.export_scene.gltf(
            filepath=str(OUT_DIR / f"{name}.glb"),
            export_format="GLB",
            use_selection=True,
            export_apply=True,
        )
        print(
            f"{name}: box {ext[0]:.2f} x {ext[1]:.2f} x {ext[2]:.2f} (Blender x, y, z), glow {glowing * 100:.1f}%"
            + (f", hue turned {turned * 100:.1f}%" if hue else "")
        )


main()
