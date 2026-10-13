"""Packs a fish's shade skins into one GLB for Studio's 3D importer.

    <blender python> tools/shades/pack_shades.py -- <fish.glb> <skins_dir>/<Fish> <out.glb> [size]

The GLB holds one tiny quad per skin, named for its shade, for the shades in the
fish's own list only (shade_lines.py: its line plus the universal skins; anything else
in the folder is left out, and a listed shade with no skin is reported). Each quad's
material is the skin as it ships (skins.json from make_shades.py): its color map, a
roughness/metal map (its finish's, shared by every shade with
that finish, or its own for a metal shade) and, for a glowing shade, its glow map as
the emissive texture. Importing it uploads the textures and makes a SurfaceAppearance on each quad
(the importer turns the emissive texture into the glow mask);
tools/studio/organize_shades.luau then files them under
ReplicatedStorage.ShadeSkins.<Fish>.<Shade>, where Cosmetics wears them in place of
the fish's own texture and sets how bright they glow. Textures are scaled to `size`
(default 1024, Roblox's largest).

The roughness/metal maps are written to <skins_dir>/<Fish>/_packed as glTF wants
them: green roughness, blue metal, red left at 0 (an orange-looking red+green map is
the kind of image the skin screen exists for).
"""

import json
import pathlib
import sys

import bpy
import numpy as np
import shade_lines
from PIL import Image

argv = sys.argv[sys.argv.index("--") + 1 :]
SRC = str(pathlib.Path(argv[0]).resolve())
SKINS, OUT = pathlib.Path(argv[1]).resolve(), pathlib.Path(argv[2]).resolve()
SIZE = int(argv[3]) if len(argv) > 3 else 1024
PACKED = SKINS / "_packed"
PACKED.mkdir(exist_ok=True)
# NEVER pack a normal map (2026-10-13): Roblox terminated the owner's account over
# one, the Nibbler Living Reef relief map (asset 133593810809027), a flat lilac
# image our own screen scored 0.000. Every image in these GLBs is uploaded on
# import, so skins carry no NormalMap at all, not even the fish's own. Depth comes
# from the colour map's painted creases (make_shades DETAIL_FLOOR) instead.
NORMALS = False

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)


def find_image(prefix: str):
    for image in bpy.data.images:
        if image.name.lower().startswith(prefix) and image.size[0] > 0:
            return image
    return None


def fit(image):
    if image is not None and max(image.size) > SIZE:
        image.scale(SIZE, SIZE)
    return image


def grey(path: pathlib.Path) -> np.ndarray:
    with Image.open(path) as img:
        return np.asarray(img.convert("L").resize((SIZE, SIZE), Image.LANCZOS))


normal = fit(find_image("normal"))
own_normal: np.ndarray | None = None
if normal is not None:
    w, h = normal.size
    px = np.array(normal.pixels[:], np.float32).reshape(h, w, 4)[::-1, :, :3]  # bpy rows run bottom-up
    if (h, w) != (SIZE, SIZE):
        px = np.asarray(Image.fromarray((px * 255).astype(np.uint8)).resize((SIZE, SIZE), Image.LANCZOS), np.float32) / 255
    own_normal = px
for obj in list(bpy.data.objects):
    bpy.data.objects.remove(obj, do_unlink=True)


def blended_normal(shade: str) -> bpy.types.Image | None:
    """The fish's own normal map with the skin's relief on top (the pattern's own
    bumps, make_shades relief_normal), as one image for the material."""
    path = SKINS / f"{shade}_normal.png"
    if not path.exists():
        return None
    with Image.open(path) as img:
        skin = np.asarray(img.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS), np.float32) / 255
    a = skin * 2 - 1
    if own_normal is not None:
        b = own_normal * 2 - 1
        # Whiteout blend: the slopes add, the "up" parts multiply
        n = np.stack([a[..., 0] + b[..., 0], a[..., 1] + b[..., 1], a[..., 2] * b[..., 2]], -1)
    else:
        n = a
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
    out = PACKED / f"{shade}_nrm.png"
    Image.fromarray((np.clip(n * 0.5 + 0.5, 0, 1) * 255).astype(np.uint8)).save(out)
    image = bpy.data.images.load(str(out))
    image.name = f"{OUT.stem}_{shade}_nrm"
    image.colorspace_settings.name = "Non-Color"
    return image

specs = json.loads((SKINS / "skins.json").read_text())
FISH = SKINS.name
if FISH in shade_lines.fishes():
    wanted = shade_lines.shades(FISH)
    missing = [s for s in wanted if s not in specs or not (SKINS / f"{s}.png").exists()]
    if missing:
        print(f"[pack] {FISH}: no skin for {', '.join(missing)} (screened out or not made); packing the rest")
    specs = {s: specs[s] for s in wanted if s in specs}
rm_images: dict[str, bpy.types.Image] = {}


def rm_image(shade: str, spec: dict):
    """The roughness/metal image for a shade: its finish's, or its own."""
    own = spec.get("rough") or spec.get("metal")
    key = shade if own else f"finish_{spec['finish']}"
    if key in rm_images:
        return rm_images[key]
    rough_path = SKINS / (f"{shade}_rough.png" if spec.get("rough") else f"finish_{spec['finish']}.png")
    rough = grey(rough_path)
    metal = grey(SKINS / f"{shade}_metal.png") if spec.get("metal") else np.zeros_like(rough)
    rgb = np.stack([np.zeros_like(rough), rough, metal], -1)
    path = PACKED / f"{key}_rm.png"
    Image.fromarray(rgb).save(path)
    image = bpy.data.images.load(str(path))
    image.name = f"{OUT.stem}_{key}_rm"
    image.colorspace_settings.name = "Non-Color"
    rm_images[key] = image
    return image


made = 0
for index, shade in enumerate(sorted(specs)):
    spec = specs[shade]
    path = SKINS / f"{shade}.png"
    if not path.exists():
        continue
    skin = fit(bpy.data.images.load(str(path)))
    skin.name = f"{OUT.stem}_{shade}"
    mat = bpy.data.materials.new(shade)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    color = nodes.new("ShaderNodeTexImage")
    color.image = skin
    links.new(color.outputs["Color"], bsdf.inputs["Base Color"])
    bump = blended_normal(shade) if NORMALS and spec.get("normal") else None
    if NORMALS and (bump is not None or normal is not None):
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = bump if bump is not None else normal
        tex.image.colorspace_settings.name = "Non-Color"
        node = nodes.new("ShaderNodeNormalMap")
        links.new(tex.outputs["Color"], node.inputs["Color"])
        links.new(node.outputs["Normal"], bsdf.inputs["Normal"])
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = rm_image(shade, spec)
    split = nodes.new("ShaderNodeSeparateColor")
    links.new(tex.outputs["Color"], split.inputs["Color"])
    links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
    links.new(split.outputs["Blue"], bsdf.inputs["Metallic"])
    if spec.get("emit"):
        glow = fit(bpy.data.images.load(str(SKINS / f"{shade}_emit.png")))
        glow.name = f"{OUT.stem}_{shade}_emit"
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = glow
        links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
    bpy.ops.mesh.primitive_plane_add(size=0.2, location=(index * 0.3, 0, 0))
    quad = bpy.context.active_object
    quad.name = shade
    quad.data.name = shade
    quad.data.materials.append(mat)
    made += 1

if made == 0:
    raise SystemExit(f"no skins in {SKINS}")
OUT.parent.mkdir(parents=True, exist_ok=True)
# Studio names the imported model after the glTF scene; organize_shades.luau matches
# models by "<Fish>_Shades"
bpy.context.scene.name = OUT.stem
bpy.ops.export_scene.gltf(
    filepath=str(OUT), export_format="GLB", export_image_format="JPEG", export_jpeg_quality=92
)
print(f"[pack] {OUT.name}: {made} skins, {len(rm_images)} roughness/metal maps")
