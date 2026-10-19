"""Reference images for the ambient sea life's model sheets (2026-10-19).

The owner asked for the sea turtles, mantas and stingrays to be "dialed up" (they were
part-built: "essentially just circles put together"). None of them has an approved
concept, so each model sheet (tools/tripo_jobs_ambient_sheets.json) is drawn from its
prompt over a style board of approved art: Nano Banana takes one reference image, and a
single creature as the reference copies its body and pose (Hatch & Snatch's lesson), so
the board shows several at once and the prompts say to copy the style only.

    python3 tools/props/ambient_refs.py      # -> assets/tripo/ambient_refs/{Style,Humpback}.png
    python3.11 tools/props/ambient_refs.py --fix Humpback   # -> assets/tripo/ambient_sheets/Humpback_fix.png

- Style.png: three rows of approved creatures (the species row of StyleRef.png without
  the googly-eyed Nibbler, the two rows of the approved PreySheetC) on the concepts' teal,
  for the Turtle, Manta, Stingray and Crab.
- Humpback.png: the approved Whale Fall sheet (a humpback in the game's style, dead on
  the floor) large at the top, the style strip under it, for the live humpback the
  Open Blue's far giants are (the sheet's prompt says to redraw it alive and whole).

`--fix Humpback` touches the humpback's model sheet up before 3D: Nano Banana copied the
style strip under the whale and the dead design's shut eye (a closed line), so the sheet
is cut above the strip and the eye painted open (the line painted over from round it, a
dark pupil with a glint drawn in), like prey_refs.py's `--tops` and `--fix`.
"""

from __future__ import annotations

import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/tripo/ambient_refs"
STYLE = ROOT / "assets/tripo/prey_concepts/StyleRef.png"
PREY_C = ROOT / "assets/tripo/prey_concepts/PreySheetC_grid.png"
WHALE = ROOT / "assets/tripo/whalefall_sheets/WhaleFallA.png"
SIZE = 1024
TEAL = (118, 190, 178)


def fit(image: Image.Image, width: int, height: int) -> Image.Image:
    scale = min(width / image.width, height / image.height)
    return image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)


def style_board() -> pathlib.Path:
    style = Image.open(STYLE).convert("RGB")
    prey = Image.open(PREY_C).convert("RGB")
    rows = [
        style.crop((150, 160, 1000, 420)),  # the 'Cuda's wrasse, 'Cuda, Reef Shark, Angler
        prey.crop((90, 110, 2090, 420)),  # Opaleye, Kelp Bass, Blue Tang, Lingcod
        prey.crop((60, 440, 2090, 760)),  # Rattail, Viperfish, Hatchetfish, Humphead Wrasse
    ]
    canvas = Image.new("RGB", (SIZE, SIZE), TEAL)
    band = SIZE // len(rows)
    for i, row in enumerate(rows):
        piece = fit(row, SIZE - 40, band - 24)
        canvas.paste(piece, ((SIZE - piece.width) // 2, i * band + (band - piece.height) // 2))
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / "Style.png"
    canvas.save(path)
    return path


def humpback() -> pathlib.Path:
    whale = Image.open(WHALE).convert("RGB").crop((20, 290, 1010, 730))
    style = Image.open(STYLE).convert("RGB").crop((150, 160, 1000, 420))
    canvas = Image.new("RGB", (SIZE, SIZE), whale.getpixel((4, 4)))
    top = 700
    piece = fit(whale, SIZE - 40, top - 40)
    canvas.paste(piece, ((SIZE - piece.width) // 2, (top - piece.height) // 2))
    canvas.paste((255, 255, 255), (0, top, SIZE, top + 8))
    strip = style.resize((SIZE, SIZE - top - 8), Image.LANCZOS)
    canvas.paste(strip, (0, top + 8))
    path = OUT / "Humpback.png"
    canvas.save(path)
    return path


# `--fix`: (the sheet's top part, kept above the copied strip; the closed eye line's box;
# the open eye's centre, radii and tilt in degrees)
FIXES = {"Humpback": {"top": 700, "line": (394, 470, 434, 492), "eye": (414, 480, 9.5, 7.0, -12)}}


def fix(name: str) -> pathlib.Path:
    import numpy as np
    from PIL import ImageDraw
    from skimage.restoration import inpaint_biharmonic

    folder = ROOT / "assets/tripo/ambient_sheets"
    how = FIXES[name]
    image = Image.open(folder / f"{name}.png").convert("RGB")
    rgb = np.asarray(image).astype(np.float64) / 255
    x0, y0, x1, y1 = how["line"]
    box = rgb[y0:y1, x0:x1]
    holes = np.zeros(rgb.shape[:2], bool)
    holes[y0:y1, x0:x1] = box.sum(-1) < 1.0  # the dark line
    from scipy import ndimage

    holes = ndimage.binary_dilation(holes, iterations=2)
    rgb = inpaint_biharmonic(rgb, holes, channel_axis=-1, split_into_regions=True)
    canvas = Image.fromarray((rgb.clip(0, 1) * 255).round().astype(np.uint8))
    up = 4
    layer = Image.new("RGBA", (canvas.width * up, canvas.height * up), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    cx, cy, rx, ry, tilt = how["eye"]
    eye = Image.new("RGBA", (int(rx * 2 * up + 8), int(ry * 2 * up + 8)), (0, 0, 0, 0))
    ImageDraw.Draw(eye).ellipse([4, 4, eye.width - 4, eye.height - 4], fill=(24, 30, 40, 255))
    eye = eye.rotate(tilt, expand=True, resample=Image.BICUBIC)
    layer.alpha_composite(eye, (int(cx * up - eye.width / 2), int(cy * up - eye.height / 2)))
    g = 2.0 * up
    gx, gy = (cx - rx * 0.35) * up, (cy - ry * 0.35) * up
    draw.ellipse([gx - g, gy - g, gx + g, gy + g], fill=(245, 248, 252, 255))
    layer = layer.resize(canvas.size, Image.LANCZOS)
    canvas = Image.alpha_composite(canvas.convert("RGBA"), layer).convert("RGB")
    # Above the copied strip only, back to a square on the sheet's own grey
    top = canvas.crop((0, 0, canvas.width, how["top"] - 6))
    square = Image.new("RGB", (canvas.width, canvas.width), top.getpixel((4, 4)))
    square.paste(top, (0, (canvas.width - top.height) // 2))
    path = folder / f"{name}_fix.png"
    square.save(path)
    return path


if __name__ == "__main__":
    import sys

    if sys.argv[1:2] == ["--fix"]:
        for name in sys.argv[2:]:
            print(fix(name).relative_to(ROOT))
    else:
        for made in (style_board(), humpback()):
            print(made.relative_to(ROOT))
