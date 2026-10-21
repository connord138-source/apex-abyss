"""Warmer, lighter kelp and sea grass for the Kelp Shallows (2026-10-21: the rebuilt
Kelp Cathedral and Otter Meadow matched their scene's layout, but the kelp read dark
teal and the grass a dark green lawn, where assets/tripo/biome_concepts/KelpScene.png
has bright golden yellow-olive kelp and pale yellow-green blades).

    python3 tools/props/shallows_recolor.py <in.glb> <out.glb> <kelp|clump|grass>

Two things made the kelp read dark in the water. Its colour map was a deep, very
saturated olive, and its metal map was ~0.67 with roughness ~0.34 (Tripo's guess), so in
game it mirrored the blue water round it. Every recipe here lifts the colour map toward
the scene's colours (hue held in a narrow band, saturation and value lifted, the map's
own light and dark kept) and makes the finish matte: metal 0 (the map's blue channel and
`metallicFactor`), roughness at least 0.72. A SurfaceAppearance colour only darkens, so
the map itself has to carry the lighter colour.

Grey texels (little saturation: the clump's rock and holdfast) are left as they are.
Yellow stays clear of the moderation screen's skin rules by keeping blue low (Cb well
under the skin range); screen the result anyway (tools/shades/screen_shades.py). Run
on GLBs already through strip_normals.py: a normal map is never written back.
"""

import io
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from safe_colors import base_color_images, read_glb, write_glb  # noqa: E402

# Hue (degrees) the colour is pulled to, how much of its own hue spread it keeps,
# saturation (scale, floor, ceiling) and value (lift + scale) for each recipe
RECIPES = {
    # GiantKelp: the scene's golden yellow-olive, lit a step lighter than it shows
    # there, since the game's water light is bluer than the concept's
    "kelp": {"hue": 52, "keep": 0.35, "sat": (0.78, 0.55, 0.80), "val": (0.34, 0.66), "edge": 0.10},
    # KelpClump: the same family as the kelp, a touch greener so the two read apart
    "clump": {"hue": 58, "keep": 0.35, "sat": (0.80, 0.50, 0.78), "val": (0.30, 0.70), "edge": 0.08},
    # SeaGrass: pale yellow-green blades (it was a dark teal-green, hue ~150)
    "grass": {"hue": 74, "keep": 0.25, "sat": (0.75, 0.42, 0.62), "val": (0.40, 0.85), "edge": 0.06},
}
ROUGH_FLOOR = 0.72


def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rm = m & (mx == r)
    gm = m & (mx == g) & ~rm
    bm = m & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = (b - r)[gm] / d[gm] + 2
    h[bm] = (r - g)[bm] / d[bm] + 4
    h = h * 60.0
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    return h, s, mx


def hsv_to_rgb(h, s, v):
    c = v * s
    hp = (h % 360) / 60.0
    x = c * (1 - np.abs(hp % 2 - 1))
    z = np.zeros_like(h)
    conds = [hp < 1, hp < 2, hp < 3, hp < 4, hp < 5, hp >= 5]
    rs = [c, x, z, z, x, c]
    gs = [x, c, c, x, z, z]
    bs = [z, z, x, c, c, x]
    r = np.select(conds, rs)
    g = np.select(conds, gs)
    b = np.select(conds, bs)
    m = v - c
    return np.stack([r + m, g + m, b + m], -1)


def recolor(rgb: np.ndarray, recipe: dict) -> np.ndarray:
    h, s, v = rgb_to_hsv(rgb)
    # Texels with real colour move; greys (rock, holdfast) stay
    weight = np.clip((s - 0.15) / 0.15, 0, 1)
    spread = ((h - np.median(h[weight > 0.5]) + 180) % 360) - 180 if (weight > 0.5).any() else h * 0
    nh = recipe["hue"] + spread * recipe["keep"]
    scale, lo, hi = recipe["sat"]
    ns = np.clip(s * scale, lo, hi)
    lift, gain = recipe["val"]
    nv = np.clip(lift + v * gain, 0, 0.94)
    # The lightest texels (the map's own highlights, often leaf edges) a little lighter
    # and less saturated: the scene's pale leaf rims
    edge = np.clip((v - np.percentile(v, 75)) / 0.15, 0, 1) * recipe["edge"]
    nv = np.clip(nv + edge, 0, 0.95)
    ns = np.clip(ns - edge * 0.8, 0, 1)
    out = hsv_to_rgb(nh, ns, nv)
    # Keep blue low against red: a pale yellow with blue in it reads beige to the screen
    out[..., 2] = np.minimum(out[..., 2], out[..., 0] * 0.55)
    out = rgb * (1 - weight[..., None]) + out * weight[..., None]
    return np.clip(out, 0, 1)


def views_of(doc: dict, blob: bytes) -> list[bytes]:
    out = []
    for view in doc["bufferViews"]:
        start = view.get("byteOffset", 0)
        out.append(bytes(blob[start : start + view["byteLength"]]))
    return out


def png(rgb: np.ndarray) -> bytes:
    buf = io.BytesIO()
    Image.fromarray(np.round(np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB").save(buf, "PNG", optimize=True)
    return buf.getvalue()


def main() -> int:
    src, dst, name = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
    recipe = RECIPES[name]
    doc, blob = read_glb(src)
    views = views_of(doc, blob)
    colour_images = base_color_images(doc)
    orm_images = set()
    for material in doc.get("materials", []):
        assert "normalTexture" not in material, f"{src}: strip its normal map first"
        pbr = material.setdefault("pbrMetallicRoughness", {})
        pbr["metallicFactor"] = 0.0
        pbr["roughnessFactor"] = 1.0
        info = pbr.get("metallicRoughnessTexture")
        if info is not None:
            orm_images.add(doc["textures"][info["index"]]["source"])
    for index, image in enumerate(doc.get("images", [])):
        view = image["bufferView"]
        pixels = np.asarray(Image.open(io.BytesIO(views[view])).convert("RGB")).astype(np.float32) / 255
        if index in colour_images:
            before = pixels.reshape(-1, 3).mean(0)
            pixels = recolor(pixels, recipe)
            after = pixels.reshape(-1, 3).mean(0)
            print(f"[recolor] {src.name} colour {np.round(before * 255)} -> {np.round(after * 255)}")
        elif index in orm_images:
            pixels[..., 1] = np.maximum(pixels[..., 1], ROUGH_FLOOR)
            pixels[..., 2] = 0.0
            print(f"[recolor] {src.name} finish: roughness >= {ROUGH_FLOOR}, metal 0")
        else:
            continue
        views[view] = png(pixels)
        image["mimeType"] = "image/png"
    dst.parent.mkdir(parents=True, exist_ok=True)
    write_glb(dst, doc, views)
    print(f"[recolor] wrote {dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
