"""Reference images for the new predators' model sheets (2026-10-21, the owner: "I like
those new predators", of assets/concepts/PredatorsBoard.jpg).

The two approved concept sheets (assets/tripo/predator_concepts/PredatorSheet{A,B}.png,
four predators each in a 2 x 2 grid) draw each creature too small to convert to 3D, so
each one is redrawn as its own clean model sheet (tools/tripo_jobs_predator_sheets.json),
the way the prey were (tools/props/prey_refs.py): the creature's crop of its concept
sheet, mirrored to face left and large, over a strip of the prey style reference.

    python3.11 tools/props/predator_refs.py [Name ...]   # -> assets/tripo/predator_refs/<Name>.png
    python3.11 tools/props/predator_refs.py --fix Name ...  # -> assets/tripo/predator_sheets/<Name>_fix.png

`--fix` touches a finished model sheet up before 3D (`FIXES`): a mouth's or an ear's
pink, plum or maroon recoloured a cool navy-grey of the same brightness (the moderation
screen distrusts those colours).
"""

from __future__ import annotations

import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONCEPTS = ROOT / "assets/tripo/predator_concepts"
STYLE = ROOT / "assets/tripo/prey_concepts/StyleRef.png"
STYLE_BAND = (0, 150, 1024, 430)  # StyleRef's top row of fish
OUT = ROOT / "assets/tripo/predator_refs"
SHEETS = ROOT / "assets/tripo/predator_sheets"

# Each creature's sheet and its box there (1024 px; found from the sheet's teal)
BOXES = {
    "SeaLion": ("A", (31, 80, 475, 445)),
    "GoliathGrouper": ("A", (548, 116, 987, 405)),
    "GiantTrevally": ("A", (45, 624, 467, 906)),
    "MakoShark": ("A", (541, 645, 995, 886)),
    "SixgillShark": ("B", (24, 132, 487, 344)),
    "WolfEel": ("B", (537, 157, 998, 350)),
    "GoblinShark": ("B", (24, 659, 486, 855)),
    "BlackDragonfish": ("B", (538, 669, 1010, 876)),
}
SIZE = 1024
TOP = 700  # the creature's part of the image; the style strip fills the rest
PAD = 14

# Model-sheet touch-ups: in each box (1024 px, the head's end) the mauve, plum and
# maroon texels of an open mouth (red well over green, blue not under green) become
# navy-grey at the same brightness; Nano Banana painted every open mouth's inside
# mauve, (70, 48, 53) to (117, 81, 89), however the prompt asked for slate grey
HEAD = (0, 0, 520, 1024)
FIXES: dict[str, dict] = {
    # (the sea lion swimming, SeaLionSwim.png: its open mouth and its pink ear)
    # (only its mouth and ear: its brown fur has mauve shadows that would turn blue)
    "SeaLionSwim": {"mauve": [(60, 520, 180, 595), (195, 465, 250, 510)]},
    "GoliathGrouper": {"mauve": [HEAD]},
    "GiantTrevally": {"mauve": [HEAD]},
    "MakoShark": {"mauve": [HEAD]},
    "SixgillShark": {"mauve": [HEAD]},
    # (its thrust-out jaws are pale mauve-grey, (130, 122, 130): a looser cut)
    "GoblinShark": {"mauve": [HEAD], "over": 3},
}


def make(name: str) -> pathlib.Path:
    key, (x0, y0, x1, y1) = BOXES[name]
    sheet = Image.open(CONCEPTS / f"PredatorSheet{key}.png").convert("RGB")
    style = Image.open(STYLE).convert("RGB").crop(STYLE_BAND)
    box = (max(x0 - PAD, 0), max(y0 - PAD, 0), min(x1 + PAD, sheet.width), min(y1 + PAD, sheet.height))
    crop = sheet.crop(box).transpose(Image.FLIP_LEFT_RIGHT)
    canvas = Image.new("RGB", (SIZE, SIZE), sheet.getpixel((5, 5)))
    scale = min((SIZE - 60) / crop.width, (TOP - 40) / crop.height)
    crop = crop.resize((round(crop.width * scale), round(crop.height * scale)), Image.LANCZOS)
    canvas.paste(crop, ((SIZE - crop.width) // 2, (TOP - crop.height) // 2))
    strip = style.resize((SIZE, SIZE - TOP - 8), Image.LANCZOS)
    canvas.paste((255, 255, 255), (0, TOP, SIZE, TOP + 8))
    canvas.paste(strip, (0, TOP + 8))
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}.png"
    canvas.save(path)
    return path


def fix(name: str) -> pathlib.Path:
    import numpy as np

    source = SHEETS / f"{name}.png"
    image = np.asarray(Image.open(source).convert("RGB")).astype(np.float64) / 255
    for x0, y0, x1, y1 in FIXES[name].get("mauve", []):
        box = image[y0:y1, x0:x1]
        r, g, b = box[..., 0], box[..., 1], box[..., 2]
        warm = (r > g + FIXES[name].get("over", 12) / 255) & (b > g - 2 / 255)
        luma = 0.299 * r + 0.587 * g + 0.114 * b
        cool = np.stack([luma * 0.86, luma * 0.98, luma * 1.18], -1).clip(0, 1)
        box[warm] = cool[warm]
    path = SHEETS / f"{name}_fix.png"
    Image.fromarray((image.clip(0, 1) * 255).round().astype(np.uint8)).save(path)
    return path


def main() -> int:
    args = sys.argv[1:]
    if args[:1] == ["--fix"]:
        for name in args[1:]:
            print(fix(name).relative_to(ROOT))
        return 0
    for name in args or list(BOXES):
        print(make(name).relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
