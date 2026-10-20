"""The variants' concept board for the owner: each fish's variant cut from the
generated sheet (assets/tripo/variant_concepts/VariantSheet.png, from
tools/tripo_jobs_variant_concepts.json) into a clean 3 by 2 grid, named, with the bonus
each variant's signature ability would get.

    python3 tools/props/variants_board.py <out.jpg>
"""

import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
SHEET = ROOT / "assets/tripo/variant_concepts/VariantSheet.png"
FONTS = ROOT / "tools/marketing/fonts"

# Each variant's box on the sheet (the model added a seventh fish, left out here),
# its name, its fish and the bonus to its fish's signature ability
VARIANTS = [
    ((40, 60, 305, 295), "PUFFBALL NIBBLER", "Nibbler", "Dash recharges 20% faster"),
    ((360, 95, 672, 255), "SABRECUDA", "'Cuda", "Torpedo lasts 25% longer"),
    ((700, 25, 1008, 335), "PORCUPINE PUFFER", "Pufferfish", "Puff Up lasts 25% longer"),
    ((28, 418, 502, 590), "DRAGON MORAY", "Moray Eel", "Burrow recharges 25% faster"),
    ((532, 385, 1008, 640), "HAMMERHEAD", "Reef Shark", "Blood Sense reaches 25% further"),
    ((612, 695, 955, 1002), "DEEPFANG ANGLER", "Anglerfish", "Lantern Flash reaches 25% further"),
]

INK = (16, 32, 44)
WHITE = (255, 255, 255)
GOLD = (255, 205, 92)
TEAL = (120, 236, 220)
GREY = (190, 210, 220)


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / name), size)


def centred(draw: ImageDraw.ImageDraw, x: int, y: int, text: str, f: ImageFont.FreeTypeFont, fill):
    left, top, right, _ = draw.textbbox((0, 0), text, font=f)
    draw.text((x - (right - left) // 2 - left, y - top), text, font=f, fill=fill)


def main(out: str):
    sheet = Image.open(SHEET).convert("RGB").resize((1024, 1024))
    cell_w, cell_h, text_h, gap, head = 600, 420, 120, 24, 110
    width = cell_w * 3 + gap * 4
    height = head + (cell_h + text_h + gap) * 2 + 70
    board = Image.new("RGB", (width, height), INK)
    draw = ImageDraw.Draw(board)
    draw.text((gap, 22), "VARIANTS", font=font("LuckiestGuy-Regular.ttf", 64), fill=GOLD)
    draw.text(
        (gap + 330, 38),
        "each fish's rare form, a whole new model (not pieces stuck on)",
        font=font("LilitaOne-Regular.ttf", 40),
        fill=WHITE,
    )
    name_f = font("LilitaOne-Regular.ttf", 40)
    fish_f = font("LilitaOne-Regular.ttf", 28)
    does_f = font("LilitaOne-Regular.ttf", 32)
    for i, (box, name, fish, does) in enumerate(VARIANTS):
        x = gap + (i % 3) * (cell_w + gap)
        y = head + (i // 3) * (cell_h + text_h + gap)
        # (the sheet's own teal, sampled by the crop's corners, so no seam shows)
        corner = sheet.getpixel((box[0] + 2, box[1] + 2))
        draw.rounded_rectangle((x, y, x + cell_w, y + cell_h), radius=22, fill=corner)
        crop = sheet.crop(box)
        scale = min((cell_w - 50) / crop.width, (cell_h - 40) / crop.height)
        crop = crop.resize((int(crop.width * scale), int(crop.height * scale)), Image.LANCZOS)
        board.paste(crop, (x + (cell_w - crop.width) // 2, y + (cell_h - crop.height) // 2))
        tag_w = draw.textlength(fish, font=fish_f)
        draw.rounded_rectangle((x + 14, y + 14, x + 42 + tag_w, y + 58), radius=12, fill=INK)
        draw.text((x + 28, y + 20), fish, font=fish_f, fill=GREY)
        centred(draw, x + cell_w // 2, y + cell_h + 12, name, name_f, TEAL)
        centred(draw, x + cell_w // 2, y + cell_h + 60, does, does_f, WHITE)
    draw.text(
        (gap, height - 56),
        "Bonuses boost each fish's own ability a little; looks and the bonus only, never bite damage.",
        font=fish_f,
        fill=GREY,
    )
    board.save(out, quality=92)
    print("wrote", out, board.size)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "variants_board.jpg")
