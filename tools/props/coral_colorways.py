"""Colourways of the reef's coral models, so the Blue Hole's rim and highway can stand in
colour districts like the approved scene (owner, 2026-10-21: "look how much different
your hole looks from the mockup"; assets/tripo/biome_concepts/ReefScene.png: fire red
and orange, blue and violet, yellow and green) without a Tripo model per colour.

    python3.11 tools/props/coral_colorways.py <stripped glb dir> <out dir>

Reads each source GLB (normal maps already stripped by strip_normals.py) and writes
one GLB per colourway: every coloured texel's hue turned by the recipe's step and its
saturation lifted to at least `floor`, grey and near-white texels (the sea fan's
rock) left alone. The colours are vivid and saturated, never pale or peach (the
moderation lessons: a soft orange or salmon reads as skin); run safe_colors.py and
the classifier screen on the outputs before they're bundled.
"""

import colorsys
import io
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from safe_colors import base_color_images, read_glb, write_glb  # noqa: E402

# name: (source model, hue the source's main colour goes to (degrees), saturation
# floor, value scale). The main colour is the source's median coloured hue; every
# coloured texel keeps its offset from it, so two-tone corals stay two-tone.
RECIPES = {
    "DomeCoralRed": ("DomeCoral", 352, 0.72, 0.92),
    "DomeCoralOrange": ("DomeCoral", 22, 0.78, 1.0),
    "DomeCoralYellow": ("DomeCoral", 44, 0.74, 1.0),
    "DomeCoralGreen": ("DomeCoral", 118, 0.62, 0.86),
    "BranchFanRed": ("BranchFan", 354, 0.74, 0.9),
    "BranchFanOrange": ("BranchFan", 20, 0.8, 1.0),
    "BranchFanYellow": ("BranchFan", 46, 0.75, 1.0),
    "BranchFanViolet": ("BranchFan", 272, 0.55, 0.85),
    "TableCoralBlue": ("TableCoral", 222, 0.62, 0.86),
    "TableCoralViolet": ("TableCoral", 266, 0.5, 0.82),
    "PillarCoralOrange": ("PillarCoral", 18, 0.74, 0.98),
    "PillarCoralBlue": ("PillarCoral", 226, 0.6, 0.85),
}


def views_of(doc: dict, blob: bytes) -> list[bytes]:
    out = []
    for view in doc["bufferViews"]:
        start = view.get("byteOffset", 0)
        out.append(blob[start : start + view["byteLength"]])
    return out


def recolour(rgb: np.ndarray, hue_to: float, sat_floor: float, value: float) -> np.ndarray:
    f = rgb.astype(np.float32) / 255.0
    mx, mn = f.max(axis=2), f.min(axis=2)
    v = mx
    s = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0)
    r, g, b = f[..., 0], f[..., 1], f[..., 2]
    d = np.maximum(mx - mn, 1e-6)
    h = np.where(
        mx == r,
        ((g - b) / d) % 6,
        np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4),
    ) / 6.0
    coloured = (s > 0.18) & (v > 0.12)
    if not coloured.any():
        return rgb
    # The source's main hue (circular median of its coloured texels)
    angles = h[coloured] * 2 * np.pi
    main = np.arctan2(np.median(np.sin(angles)), np.median(np.cos(angles))) / (2 * np.pi) % 1.0
    offset = ((h - main + 0.5) % 1.0) - 0.5
    new_h = (hue_to / 360.0 + offset * 0.6) % 1.0
    new_s = np.clip(np.maximum(s * 1.15, sat_floor), 0, 1)
    new_v = np.clip(v * value, 0, 1)
    hsv_to_rgb = np.vectorize(colorsys.hsv_to_rgb, otypes=[np.float32, np.float32, np.float32])
    nr, ng, nb = hsv_to_rgb(new_h, new_s, new_v)
    out = np.stack([nr, ng, nb], axis=2)
    out = np.where(coloured[..., None], out, f)
    return np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8)


def main() -> int:
    src_dir, out_dir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, (source, hue_to, sat_floor, value) in RECIPES.items():
        doc, blob = read_glb(src_dir / f"{source}.glb")
        views = views_of(doc, blob)
        for index in base_color_images(doc):
            image = doc["images"][index]
            raw = views[image["bufferView"]]
            picture = Image.open(io.BytesIO(raw))
            alpha = picture.getchannel("A") if picture.mode == "RGBA" else None
            small = picture.convert("RGB")
            out = Image.fromarray(recolour(np.asarray(small), hue_to, sat_floor, value))
            if alpha is not None:
                out.putalpha(alpha)
            buffer = io.BytesIO()
            if image.get("mimeType") == "image/jpeg":
                out.convert("RGB").save(buffer, "JPEG", quality=92)
            else:
                out.save(buffer, "PNG")
            views[image["bufferView"]] = buffer.getvalue()
        write_glb(out_dir / f"{name}.glb", doc, views)
        print("wrote", name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
