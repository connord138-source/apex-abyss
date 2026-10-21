"""Reference images for the rolled parts' and the variants' model sheets (2026-10-21).

The approved boards (assets/concepts/PartsBoard.jpg: sheet B, the legendary parts;
assets/concepts/VariantsBoard.jpg) draw each part on a fish and each variant small, so
each is redrawn as its own clean model sheet (tools/tripo_jobs_parts_sheets.json,
tools/tripo_jobs_variant_sheets.json) from one reference image: its crop of the
concept sheet, large. A variant's crop sits over its own fish's model sheet (the
species it's a rare form of), so the redraw keeps that fish's look.

    python3 tools/props/parts_variants_refs.py      # -> assets/tripo/parts_refs/, variant_refs/
    python3 tools/props/parts_variants_refs.py --fix # touch up two finished sheets (FIXES)

`--fix` writes <Name>_fix.png beside a sheet, the image the 3D job converts: the
Sabrecuda's sheet copied the reference's two-band layout (the fish twice, one over the
other), so its top copy is cut out; the Veil Tail's stem stub came out terracotta (a
colour the moderation screen distrusts), so it's recoloured the tail's deep blue.
"""

from __future__ import annotations

import pathlib
import sys

from PIL import Image, ImageChops

ROOT = pathlib.Path(__file__).resolve().parents[2]
PARTS = ROOT / "assets/tripo/parts_concepts/PartsSheetB.png"
VARIANTS = ROOT / "assets/tripo/variant_concepts/VariantSheet.png"
SPECIES = ROOT / "assets/tripo/species_sheets"
SIZE = 1024
TOP = 640

# Each part's box on PartsSheetB (left, top, right, bottom), the fish it's worn by
# partly in view
PART_BOXES = {
    "AnglerLure": (180, 90, 480, 370),
    "NarwhalHorn": (690, 140, 1000, 300),
    "SawSnout": (440, 480, 845, 625),
    "SailFin": (110, 625, 420, 935),
    "VeilTail": (510, 665, 770, 965),  # the tail alone (with the fish, the redraw kept a body)
}

# Each variant's box on VariantSheet (variants_board.py's), and its species' sheet
VARIANT_BOXES = {
    "Puffball": ((40, 60, 305, 295), "Nibbler"),
    "Sabrecuda": ((360, 95, 672, 255), "Cuda"),
    "Porcupine": ((700, 25, 1008, 335), "Puffer"),
    "DragonMoray": ((28, 418, 502, 590), "MorayEel"),
    "Hammerhead": ((532, 385, 1008, 640), "ReefShark"),
    "Deepfang": ((612, 695, 955, 1002), "Angler"),
}


def fit(image: Image.Image, width: int, height: int) -> Image.Image:
    scale = min(width / image.width, height / image.height)
    return image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)


def content(image: Image.Image) -> tuple[int, int, int, int]:
    """The box round what differs from the corner's background"""
    back = Image.new("RGB", image.size, image.getpixel((4, 4)))
    diff = ImageChops.difference(image, back).convert("L").point(lambda v: 255 if v > 24 else 0)
    box = diff.getbbox() or (0, 0, image.width, image.height)
    pad = 16
    return (max(box[0] - pad, 0), max(box[1] - pad, 0), min(box[2] + pad, image.width), min(box[3] + pad, image.height))


def part(name: str) -> pathlib.Path:
    sheet = Image.open(PARTS).convert("RGB")
    crop = sheet.crop(PART_BOXES[name])
    canvas = Image.new("RGB", (SIZE, SIZE), sheet.getpixel((10, 10)))
    crop = fit(crop, SIZE - 80, SIZE - 80)
    canvas.paste(crop, ((SIZE - crop.width) // 2, (SIZE - crop.height) // 2))
    out = ROOT / "assets/tripo/parts_refs" / f"{name}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out)
    return out


def variant(name: str) -> pathlib.Path:
    box, species = VARIANT_BOXES[name]
    sheet = Image.open(VARIANTS).convert("RGB")
    crop = sheet.crop(box)
    canvas = Image.new("RGB", (SIZE, SIZE), crop.getpixel((2, 2)))
    crop = fit(crop, SIZE - 60, TOP - 40)
    canvas.paste(crop, ((SIZE - crop.width) // 2, (TOP - crop.height) // 2))
    canvas.paste((255, 255, 255), (0, TOP, SIZE, TOP + 8))
    base = Image.open(SPECIES / f"{species}.png").convert("RGB")
    base = base.crop(content(base))
    strip = Image.new("RGB", (SIZE, SIZE - TOP - 8), base.getpixel((4, 4)))
    small = fit(base, SIZE, SIZE - TOP - 8)
    strip.paste(small, ((SIZE - small.width) // 2, 0))
    canvas.paste(strip, (0, TOP + 8))
    out = ROOT / "assets/tripo/variant_refs" / f"{name}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out)
    return out


def fix_sabrecuda() -> pathlib.Path:
    path = ROOT / "assets/tripo/variant_sheets/Sabrecuda.png"
    image = Image.open(path).convert("RGB")
    top = image.crop((0, 0, image.width, image.height // 2 - 4))
    canvas = Image.new("RGB", (image.width, image.width), image.getpixel((4, 4)))
    canvas.paste(top, (0, (image.width - top.height) // 2))
    out = path.with_name("Sabrecuda_fix.png")
    canvas.save(out)
    return out


def fix_veil() -> pathlib.Path:
    path = ROOT / "assets/tripo/parts_sheets/VeilTail.png"
    image = Image.open(path).convert("RGB")
    hsv = image.convert("HSV")
    pixels, shades = image.load(), hsv.load()
    for y in range(image.height):
        for x in range(image.width):
            h, s, v = shades[x, y]
            # (orange to terracotta and the reddish band where it meets the fin: hue
            # 330-40 of 360, saturated, only on the stem, left of the lobes)
            if (h <= 40 or h >= 208) and s > 20 and v > 40 and x < 460:
                k = v / 255
                pixels[x, y] = (round(58 * k * 1.3), round(52 * k * 1.3), round(150 * k * 1.3))
    out = path.with_name("VeilTail_fix.png")
    image.save(out)
    return out


if __name__ == "__main__":
    if "--fix" in sys.argv:
        print("wrote", fix_sabrecuda())
        print("wrote", fix_veil())
        sys.exit(0)
    for key in PART_BOXES:
        print("wrote", part(key))
    for key in VARIANT_BOXES:
        print("wrote", variant(key))
