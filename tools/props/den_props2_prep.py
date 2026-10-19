"""Readies the den props of batch 2 (2026-10-19, tools/tripo_jobs_den_props2_models.json)
between strip_normals.py and the screen. Two steps:

    python3.11 tools/props/den_props2_prep.py prep  <stripped GLBs> --out <dir>   # before safe_colors.py
    python3.11 tools/props/den_props2_prep.py cloth <safe Banner.glb> --out <dir> # after it

`prep`:
- Names the scene, node and mesh after the piece.
- Sprinkles flecks over the pedestal's grey stone (FLECKS: the classifier read its
  smooth carved stone as skin, 0.62) and cools its pearl's pale pink.
- Squares a model up in plan (TURN, degrees about +Y, baked into the vertices, the
  normals and the tangents, so Roblox's importer sees an upright box): Tripo kept the
  concept's three-quarter turn on the framed chart (31 degrees off: a wall thing must
  lie flat on the rock) and a few degrees on the pedestal's plinth and the bed.
- Gives four pieces the concept's colors back (RECOLOR) where Tripo painted them in
  the screen's skin box and safe_colors.py would have made them odd: the jellyfish
  lamp's pale tan bells go deep amber gold and the coral lamp's salmon fans deep
  orange (saturated well past the box, Cb under 74), the bed's tan rope olive kelp
  rope, and the table's warm patches back to driftwood grey (they went orange),
  keeping each texel's brightness.
`cloth`:
- The banner's teal cloth lets the den's glow through: its base color gets an alpha
  channel, low (CLOTH_ALPHA) on the cloth and 1 everywhere else, saved as a 1024 PNG.
  Roblox's SurfaceAppearance in its Overlay mode (tools/studio/organize_imports.luau
  sets it) shows the MeshPart's own Color where the alpha is low, and DenItems colors
  the banner's MeshPart in the den's glow, so the cloth follows the glow while the
  gold trim, the emblem and the pole keep their texture. The color channels are left
  as they were (the teal), so a viewer that ignores the alpha shows the concept's
  banner, and the screen reads the same colors as before.
"""

from __future__ import annotations

import argparse
import io
import pathlib
import struct
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from safe_colors import base_color_images, read_glb, write_glb  # noqa: E402

# Degrees each model is turned about +Y (glTF), measured as the turn that gives the
# smallest box in plan (the chart's whole frame, the plinth, the bed)
TURN = {"TreasureChart": 31.0, "PearlPedestal": -9.0, "KelpBed": -5.0}

# Warm texels (hue in `hues`, degrees, saturation over `from`) recolored, keeping
# their brightness (times `value`): pushed to `hue` with at least `saturation`, or
# with `mute` their saturation capped there (grey-brown wood: |R - G| under the
# screen's 15). The lamp's grey rock and the brass's dark edges are under `from`.
RECOLOR = {
    # The bells' pale tan to the concept's deep amber gold
    "JellyLamp": {"hues": (12, 75), "from": 0.12, "hue": 40, "saturation": 0.84, "value": 1.0},
    # The fans' salmon to deep orange
    "CoralLamp": {"hues": (0, 48), "from": 0.3, "hue": 19, "saturation": 0.84, "value": 0.96},
    # Tan rope to olive kelp rope (safe_colors made it copper)
    "KelpBed": {"hues": (12, 42), "from": 0.22, "hue": 52, "saturation": 0.5, "value": 0.88},
    # Warm patches on the driftwood to its grey (safe_colors made them orange)
    "DriftwoodTable": {"hues": (5, 55), "from": 0.1, "mute": 0.09, "value": 1.0},
}

# Stone flecks (the toon materials' lesson, tools/textures/make_toon_materials.py):
# big smooth grey areas with soft curved lines read as skin to the classifier. The
# pedestal's carved stone scored 0.62 on one tile of the screen (by its pearl's pale
# pink-and-mint shimmer); a sprinkle of small darker and lighter flecks over its grey
# took every tile to 0.00. Count on a 2048 map; the pearl's pale pink goes cooler too.
FLECKS = {"PearlPedestal": 9000}
COOL_PINK = {"PearlPedestal"}

CLOTH_HUES = (160, 205)  # the banner's teal
CLOTH_ALPHA = 0.2
CLOTH_SIZE = 1024
JPEG_QUALITY = 93


def accessor_array(doc: dict, views: list[bytes], index: int) -> np.ndarray:
    accessor = doc["accessors"][index]
    assert accessor["componentType"] == 5126, "float accessors only"
    width = {"VEC3": 3, "VEC4": 4}[accessor["type"]]
    view = doc["bufferViews"][accessor["bufferView"]]
    stride = view.get("byteStride", 0)
    assert stride in (0, width * 4), "interleaved buffers aren't handled"
    data = views[accessor["bufferView"]]
    start = accessor.get("byteOffset", 0)
    return np.frombuffer(data, dtype=np.float32, count=accessor["count"] * width, offset=start).reshape(-1, width)


def put_accessor(doc: dict, views: list[bytes], index: int, values: np.ndarray):
    accessor = doc["accessors"][index]
    raw = bytearray(views[accessor["bufferView"]])
    start = accessor.get("byteOffset", 0)
    chunk = values.astype(np.float32).tobytes()
    raw[start : start + len(chunk)] = chunk
    views[accessor["bufferView"]] = bytes(raw)
    if "min" in accessor:
        accessor["min"] = values.min(axis=0).tolist()
        accessor["max"] = values.max(axis=0).tolist()


def turn(doc: dict, views: list[bytes], degrees: float):
    angle = np.radians(degrees)
    c, s = np.cos(angle), np.sin(angle)
    # About +Y, right-handed: +Z turns toward +X
    rotation = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=np.float64)
    done: set[int] = set()
    for mesh in doc["meshes"]:
        for primitive in mesh["primitives"]:
            for key in ("POSITION", "NORMAL", "TANGENT"):
                index = primitive["attributes"].get(key)
                if index is None or index in done:
                    continue
                done.add(index)
                values = accessor_array(doc, views, index).astype(np.float64)
                values[:, :3] = values[:, :3] @ rotation.T
                put_accessor(doc, views, index, values)
    for node in doc.get("nodes", []):
        assert not any(k in node for k in ("rotation", "matrix")), "a node already turned"


def hsv_to_rgb(h: np.ndarray, s: np.ndarray, v: np.ndarray) -> np.ndarray:
    h6 = (h % 360) / 60.0
    sector = np.floor(h6).astype(int) % 6
    f = h6 - np.floor(h6)
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    r = np.choose(sector, [v, q, p, p, t, v])
    g = np.choose(sector, [t, v, v, q, p, p])
    b = np.choose(sector, [p, p, t, v, v, q])
    return np.clip(np.stack([r, g, b], -1) * 255 + 0.5, 0, 255).astype(np.uint8)


def recolor(rgb: np.ndarray, spec: dict) -> np.ndarray:
    hsv = np.asarray(Image.fromarray(rgb).convert("HSV")).astype(np.float32) / 255.0
    hue, sat, val = hsv[..., 0] * 360, hsv[..., 1], hsv[..., 2]
    lo, hi = spec["hues"]
    warm = (hue >= lo) & (hue <= hi) & (sat > spec["from"])
    warm = ndimage.binary_dilation(warm, iterations=1) & (sat > spec["from"] * 0.7)
    v = np.minimum(1.0, val * spec["value"])
    if "mute" in spec:
        new = hsv_to_rgb(hue, np.minimum(sat, spec["mute"]), v)
    else:
        new = hsv_to_rgb(np.full_like(hue, spec["hue"]), np.maximum(sat, spec["saturation"]), v)
    return np.where(warm[..., None], new, rgb)


def flecks(rgb: np.ndarray, count: int, seed: int = 7) -> np.ndarray:
    """Small round flecks, mostly darker, on the grey (stone) texels only."""
    hsv = np.asarray(Image.fromarray(rgb).convert("HSV")).astype(np.float32) / 255.0
    grey = hsv[..., 1] < 0.18
    height, width = grey.shape
    scale = width / 2048
    rng = np.random.default_rng(seed)
    delta = np.zeros((height, width), np.float32)
    for y, x in zip(rng.integers(0, height, count), rng.integers(0, width, count)):
        r = rng.uniform(2.5, 5.5) * scale
        d = -34.0 if rng.random() < 0.6 else 16.0
        y0, y1, x0, x1 = max(0, int(y - r)), min(height, int(y + r) + 1), max(0, int(x - r)), min(width, int(x + r) + 1)
        yy, xx = np.mgrid[y0:y1, x0:x1]
        delta[y0:y1, x0:x1][np.hypot(yy - y, xx - x) < r] = d
    out = rgb.astype(np.float32) + (delta * grey)[..., None]
    return np.clip(out + 0.5, 0, 255).astype(np.uint8)


def cool_pink(rgb: np.ndarray) -> np.ndarray:
    """Pale pinks (a pearl's shimmer) a step toward lilac-blue."""
    hsv = np.asarray(Image.fromarray(rgb).convert("HSV")).astype(np.float32) / 255.0
    hue, sat, val = hsv[..., 0] * 360, hsv[..., 1], hsv[..., 2]
    pink = (sat < 0.35) & (val > 0.7) & ((hue > 270) | (hue < 30))
    out = rgb.astype(np.float32)
    out[pink] *= np.array([0.85, 0.95, 1.05], np.float32)
    return np.clip(out + 0.5, 0, 255).astype(np.uint8)


def encode(image: Image.Image, png: bool) -> bytes:
    buffer = io.BytesIO()
    if png:
        image.save(buffer, "PNG", optimize=True)
    else:
        image.convert("RGB").save(buffer, "JPEG", quality=JPEG_QUALITY, subsampling=0)
    return buffer.getvalue()


def load(path: pathlib.Path) -> tuple[dict, list[bytes]]:
    doc, blob = read_glb(path)
    views = [blob[v.get("byteOffset", 0) : v.get("byteOffset", 0) + v["byteLength"]] for v in doc["bufferViews"]]
    return doc, views


def prep(path: pathlib.Path, out: pathlib.Path):
    name = path.stem
    doc, views = load(path)
    notes = []
    if name in TURN:
        turn(doc, views, TURN[name])
        notes.append(f"turned {TURN[name]:+.1f} deg")
    if name in RECOLOR or name in FLECKS or name in COOL_PINK:
        for index in sorted(base_color_images(doc)):
            image = doc["images"][index]
            rgb = np.asarray(Image.open(io.BytesIO(views[image["bufferView"]])).convert("RGB"))
            new = rgb
            if name in RECOLOR:
                new = recolor(new, RECOLOR[name])
            if name in COOL_PINK:
                new = cool_pink(new)
            if name in FLECKS:
                new = flecks(new, FLECKS[name])
            changed = (new != rgb).any(axis=2).mean() * 100
            views[image["bufferView"]] = encode(Image.fromarray(new), image.get("mimeType") == "image/png")
            notes.append(f"recolored {changed:.1f}% of image {index}")
    # The scene, its node and its mesh named after the piece (Studio names an import
    # by these when it can; organize_imports.luau files it by name)
    for key in ("scenes", "nodes", "meshes"):
        for entry in doc.get(key, []):
            entry["name"] = name
    write_glb(out / path.name, doc, views)
    print(f"{name}: {', '.join(notes) or 'as is'}")


def cloth(path: pathlib.Path, out: pathlib.Path):
    doc, views = load(path)
    for index in sorted(base_color_images(doc)):
        image = doc["images"][index]
        rgb = Image.open(io.BytesIO(views[image["bufferView"]])).convert("RGB").resize(
            (CLOTH_SIZE, CLOTH_SIZE), Image.LANCZOS
        )
        hsv = np.asarray(rgb.convert("HSV")).astype(np.float32) / 255.0
        hue, sat = hsv[..., 0] * 360, hsv[..., 1]
        teal = (hue >= CLOTH_HUES[0]) & (hue <= CLOTH_HUES[1]) & (sat > 0.25)
        teal = ndimage.binary_opening(teal, iterations=1)
        soft = ndimage.gaussian_filter(teal.astype(np.float32), 1.2)
        alpha = 1.0 - soft * (1.0 - CLOTH_ALPHA)
        rgba = np.dstack([np.asarray(rgb), np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)])
        views[image["bufferView"]] = encode(Image.fromarray(rgba, "RGBA"), True)
        image["mimeType"] = "image/png"
        print(f"{path.stem} image {index}: cloth {teal.mean() * 100:.1f}% of the texels let the glow through")
    write_glb(out / path.name, doc, views)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("step", choices=("prep", "cloth"))
    ap.add_argument("glbs", nargs="+")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for name in args.glbs:
        (prep if args.step == "prep" else cloth)(pathlib.Path(name), out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
