"""Reference images for the second prey batch's model sheets (2026-10-18).

The approved concept sheet (assets/tripo/prey_concepts/PreySheetA.png, eight prey in
a 4 x 2 grid) draws each fish too small to convert to 3D, so each one is redrawn as
its own clean model sheet (tools/tripo_jobs_prey2_sheets.json). Nano Banana takes one
reference image, so this puts both references in one: the fish's own crop of the
concept sheet, large, over a strip of the style reference (StyleRef.png's top row).

    python3 tools/props/prey_refs.py [Name ...]      # -> assets/tripo/prey2_refs/<Name>.png
    python3 tools/props/prey_refs.py --tops Name ...  # -> assets/tripo/prey2_sheets/<Name>_top.png

A sheet that copied the style strip under its fish (the Wreck Cod and the Yellowfin
Tuna did) is cut above the strip's white rule with `--tops` instead of being redrawn.

The third batch (2026-10-19) comes from the approved PreySheetB_grid.png the same way:
put `--batch B` first (-> assets/tripo/prey3_refs/, assets/tripo/prey3_sheets/;
tools/tripo_jobs_prey3_*.json). Its fish face right, so each crop is mirrored to face
left like the model-sheet prompts ask.
"""

from __future__ import annotations

import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
SHEET = ROOT / "assets/tripo/prey_concepts/PreySheetA.png"
STYLE = ROOT / "assets/tripo/prey_concepts/StyleRef.png"
OUT = ROOT / "assets/tripo/prey2_refs"

# Each fish's box on the 1024 px concept sheet (left, top, right, bottom), above its label
BOXES = {
    "Garibaldi": (30, 250, 225, 425),
    "WreckCod": (245, 250, 515, 425),
    "Parrotfish": (520, 250, 750, 425),
    "YellowfinTuna": (755, 245, 1000, 420),
    "MahiMahi": (25, 565, 285, 735),
    "Lionfish": (295, 525, 525, 740),
    "GhostShrimp": (540, 565, 750, 740),
    "Lanternfish": (770, 585, 995, 715),
}
STYLE_BAND = (0, 150, 1024, 430)  # StyleRef's top row of fish

# The batches: concept sheet, each fish's box on it, where the references and the model
# sheets go, and whether the sheet's fish face right (mirrored to face left)
BATCHES = {
    "A": {"sheet": SHEET, "boxes": BOXES, "out": OUT, "sheets": "prey2_sheets", "mirror": False},
    "B": {
        "sheet": ROOT / "assets/tripo/prey_concepts/PreySheetB_grid.png",
        # (2500 x 946 px)
        "boxes": {
            "Butterflyfish": (225, 150, 490, 385),
            "Triggerfish": (780, 175, 1130, 385),
            "Swordfish": (1255, 145, 1835, 410),
            "OceanSunfish": (1985, 110, 2290, 455),
            "Coelacanth": (120, 540, 590, 790),
            "VentEelpout": (740, 580, 1165, 750),
            "GulperEel": (1320, 570, 1765, 765),
            "Oarfish": (1900, 550, 2385, 785),
        },
        "out": ROOT / "assets/tripo/prey3_refs",
        "sheets": "prey3_sheets",
        "mirror": True,
        # The Oarfish's and the Gulper Eel's tails curl on the concept, and Nano Banana
        # copied the curl however the prompt asked for a straight body (a rig wants one).
        # Their references are straightened: everything past `cut` (x on the 1024 px
        # reference) goes, then the body's last `period` columns repeat on `extend` px
        # further, tapering to `taper` of their height (`clear` boxes: the curl's other
        # bits left of the cut)
        "straighten": {
            "Oarfish": {"cut": 705, "period": 220, "extend": 560, "taper": 0.1, "clear": []},
            "GulperEel": {"cut": 795, "period": 70, "extend": 560, "taper": 0.12, "clear": [(660, 420, 800, 560)]},
        },
    },
}
batch = BATCHES["A"]
SIZE = 1024
TOP = 700  # the fish's part of the image; the style strip fills the rest


def straighten(canvas: Image.Image, how: dict) -> Image.Image:
    """Cut the curled tail off the reference's fish and run the body on straight."""
    import numpy as np

    top_area = np.asarray(canvas.crop((0, 0, SIZE, TOP))).astype(np.float32)
    bg = top_area[300, 35].copy()  # the panel's teal, left of every fish's head
    fish = np.sqrt(((top_area - bg) ** 2).sum(-1)) > 30
    cut, period, extend, taper = how["cut"], how["period"], how["extend"], how["taper"]
    for x0, y0, x1, y1 in how["clear"]:
        fish[y0:y1, x0:x1] = False
    wide = np.empty((TOP, cut + extend, 3), np.float32)
    wide[:] = bg
    keep = fish[:, :cut]
    wide[:, :cut][keep] = top_area[:, :cut][keep]
    # The band's middle at the cut, which every extended column keeps level with
    rows = np.nonzero(fish[:, cut - 1])[0]
    middle = (rows.min() + rows.max()) / 2
    for k in range(extend):
        phase = k % (2 * period)  # ping-pong through the last `period` columns: no seam
        src = cut - 1 - (phase if phase < period else 2 * period - 1 - phase)
        t = k / extend
        scale = 1 - (1 - taper) * t**1.2
        # Only the run of the column through the band's middle (not the fin streamers)
        column = fish[:, src]
        lo = hi = int(middle)
        while lo > 0 and column[lo - 1]:
            lo -= 1
        while hi < TOP - 1 and column[hi + 1]:
            hi += 1
        ys = np.arange(TOP)
        from_y = np.round(middle + (ys - middle) / scale).astype(int)
        ok = (from_y >= lo) & (from_y <= hi) & column[int(middle)]
        wide[ys[ok], cut + k] = top_area[from_y[ok], src]
    # Fit the longer fish back into the reference's top part
    cols = np.nonzero((np.sqrt(((wide - bg) ** 2).sum(-1)) > 30).any(0))[0]
    rows = np.nonzero((np.sqrt(((wide - bg) ** 2).sum(-1)) > 30).any(1))[0]
    body = Image.fromarray(wide[rows.min() : rows.max() + 1, cols.min() : cols.max() + 1].astype(np.uint8))
    scale = min((SIZE - 60) / body.width, (TOP - 40) / body.height)
    body = body.resize((round(body.width * scale), round(body.height * scale)), Image.LANCZOS)
    fill = tuple(int(c) for c in bg)
    canvas.paste(fill, (0, 0, SIZE, TOP))
    canvas.paste(body, ((SIZE - body.width) // 2, (TOP - body.height) // 2))
    return canvas


def make(name: str) -> pathlib.Path:
    sheet = Image.open(batch["sheet"]).convert("RGB")
    style = Image.open(STYLE).convert("RGB").crop(STYLE_BAND)
    box = batch["boxes"][name]
    crop = sheet.crop(box)
    if batch["mirror"]:
        crop = crop.transpose(Image.FLIP_LEFT_RIGHT)
    # The concept's own teal fills the canvas, so the crop's edges don't show
    canvas = Image.new("RGB", (SIZE, SIZE), sheet.getpixel((box[0] + 2, box[1] + 2)))
    scale = min((SIZE - 60) / crop.width, (TOP - 40) / crop.height)
    crop = crop.resize((round(crop.width * scale), round(crop.height * scale)), Image.LANCZOS)
    canvas.paste(crop, ((SIZE - crop.width) // 2, (TOP - crop.height) // 2))
    if name in batch.get("straighten", {}):
        canvas = straighten(canvas, batch["straighten"][name])
    strip = style.resize((SIZE, SIZE - TOP - 8), Image.LANCZOS)
    canvas.paste((255, 255, 255), (0, TOP, SIZE, TOP + 8))
    canvas.paste(strip, (0, TOP + 8))
    batch["out"].mkdir(parents=True, exist_ok=True)
    path = batch["out"] / f"{name}.png"
    canvas.save(path)
    return path


def top(name: str) -> pathlib.Path:
    image = Image.open(ROOT / f"assets/tripo/{batch['sheets']}/{name}.png").convert("RGB")
    cut = image.crop((0, 0, image.width, TOP - 6))
    # Back to a square on the sheet's own grey, the fish in the middle
    canvas = Image.new("RGB", (image.width, image.width), cut.getpixel((4, 4)))
    canvas.paste(cut, (0, (image.width - cut.height) // 2))
    path = ROOT / f"assets/tripo/{batch['sheets']}/{name}_top.png"
    canvas.save(path)
    return path


def main() -> int:
    global batch
    args = sys.argv[1:]
    if args[:1] == ["--batch"]:
        batch = BATCHES[args[1]]
        args = args[2:]
    if args[:1] == ["--tops"]:
        for name in args[1:]:
            print(top(name).relative_to(ROOT))
        return 0
    names = args or list(batch["boxes"])
    for name in names:
        print(make(name).relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
