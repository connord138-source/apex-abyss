"""Cuts the rusty buoy off the approved Open Blue kit sheet
(assets/tripo/biome_concepts/BlueKit.png) into its own square reference on the sheet's
flat teal, for Tripo image_to_model (tools/tripo_jobs_blue2.json), the same way
tools/props/biome_kit_crops.py cut the other Blue pieces (owner, 2026-10-21: the
landmark rebuild, "everything other than the whale, ship and lighthouse needs more
detail and more intricacy").

    python3.11 tools/props/blue_kit_crops.py

Writes assets/tripo/biome_models/refs/RustyBuoy.png. The box was found by segmenting the
sheet (pixels far from the border's median colour, closed and filled, as components).
"""

import pathlib

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
SHEET = ROOT / "assets/tripo/biome_concepts/BlueKit.png"
OUT = ROOT / "assets/tripo/biome_models/refs"

# (box (x0, y0, x1, y1) on the 1024 sheet, name)
CROPS = [
    ((715, 606, 962, 962), "RustyBuoy"),
]

SIZE = 768
MARGIN = 0.14


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    image = Image.open(SHEET).convert("RGB").resize((1024, 1024))
    pixels = np.asarray(image).astype(np.float32)
    border = np.concatenate(
        [pixels[:8].reshape(-1, 3), pixels[-8:].reshape(-1, 3), pixels[:, :8].reshape(-1, 3), pixels[:, -8:].reshape(-1, 3)]
    )
    background = tuple(int(v) for v in np.median(border, axis=0))
    for box, name in CROPS:
        x0, y0, x1, y1 = box
        pad = 6
        crop = image.crop((max(x0 - pad, 0), max(y0 - pad, 0), min(x1 + pad, 1024), min(y1 + pad, 1024)))
        side = int(max(crop.width, crop.height) * (1 + MARGIN * 2))
        square = Image.new("RGB", (side, side), background)
        square.paste(crop, ((side - crop.width) // 2, (side - crop.height) // 2))
        square.resize((SIZE, SIZE), Image.LANCZOS).save(OUT / f"{name}.png")
        print("wrote", name)


if __name__ == "__main__":
    main()
