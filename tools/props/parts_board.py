"""The rolled parts' concept board for the owner: sheet A (natural) and sheet B
(legendary) side by side, each part named under its fish, and a band below with the
bonus each part would give.

    python3 tools/props/parts_board.py <out.jpg>

Reads assets/tripo/parts_concepts/PartsSheet{A,B}.png (tools/tripo_jobs_parts_concepts.json).
"""

import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
SHEETS = ROOT / "assets/tripo/parts_concepts"
FONTS = ROOT / "tools/marketing/fonts"

# Where each part's name sits on its sheet (the middle of the label, under its fish)
LABELS = {
    "A": [
        ("1 · ANGLER LURE", (235, 340)),
        ("2 · NARWHAL HORN", (760, 340)),
        ("3 · SAWBLADE SNOUT", (335, 640)),
        ("4 · SAIL FIN", (262, 985)),
        ("5 · VEIL TAIL", (750, 995)),
    ],
    "B": [
        ("1 · ANGLER LURE", (280, 372)),
        ("2 · NARWHAL HORN", (765, 378)),
        ("3 · SAWBLADE SNOUT", (555, 640)),
        ("4 · SAIL FIN", (270, 950)),
        ("5 · VEIL TAIL", (745, 985)),
    ],
}

BONUSES = [
    ("1 · ANGLER LURE", "Its own light in dark water, and small prey drift into your mouth (+25% swallow reach)"),
    ("2 · NARWHAL HORN", "Your Dash (or Torpedo) carries 20% further"),
    ("3 · SAWBLADE SNOUT", "Rakes the sand: shells and treasure sites found from 50% further"),
    ("4 · SAIL FIN", "+5% top speed"),
    ("5 · VEIL TAIL", "Turns 15% tighter"),
]

INK = (16, 32, 44)
PANEL = (14, 30, 42, 210)
WHITE = (255, 255, 255)
GOLD = (255, 205, 92)
TEAL = (120, 236, 220)


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / name), size)


def pill(draw: ImageDraw.ImageDraw, centre: tuple[int, int], text: str, f: ImageFont.FreeTypeFont):
    left, top, right, bottom = draw.textbbox((0, 0), text, font=f)
    w, h = right - left, bottom - top
    x, y = centre[0] - w // 2, centre[1] - h // 2
    draw.rounded_rectangle((x - 14, y - 9, x + w + 14, y + h + 11), radius=14, fill=PANEL)
    draw.text((x - left, y - top), text, font=f, fill=WHITE)


def sheet(key: str) -> Image.Image:
    image = Image.open(SHEETS / f"PartsSheet{key}.png").convert("RGBA").resize((1024, 1024))
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    f = font("LilitaOne-Regular.ttf", 30)
    for text, at in LABELS[key]:
        pill(draw, at, text, f)
    return Image.alpha_composite(image, layer)


def main(out: str):
    gap, band, head = 24, 380, 110
    width = 1024 * 2 + gap * 3
    board = Image.new("RGBA", (width, head + 1024 + band + gap), INK + (255,))
    draw = ImageDraw.Draw(board)
    title = font("LuckiestGuy-Regular.ttf", 64)
    sub = font("LilitaOne-Regular.ttf", 40)
    draw.text((gap, 22), "ROLLED PARTS", font=title, fill=GOLD)
    draw.text((gap + 470, 38), "pick A or B (or mix: e.g. B's lure with A's horn)", font=sub, fill=WHITE)
    for i, key in enumerate(("A", "B")):
        x = gap + i * (1024 + gap)
        board.alpha_composite(sheet(key), (x, head))
        tag = "A · NATURAL" if key == "A" else "B · LEGENDARY"
        f = font("LuckiestGuy-Regular.ttf", 44)
        draw.rounded_rectangle((x + 16, head + 16, x + 16 + 330, head + 80), radius=16, fill=(14, 30, 42, 230))
        draw.text((x + 34, head + 24), tag, font=f, fill=GOLD if key == "B" else TEAL)
    y = head + 1024 + 28
    draw.text((gap, y), "WHAT EACH PART DOES (a modest bonus, never bite damage)", font=sub, fill=GOLD)
    y += 64
    name_f = font("LilitaOne-Regular.ttf", 36)
    text_f = font("LilitaOne-Regular.ttf", 34)
    for name, does in BONUSES:
        draw.text((gap + 10, y), name, font=name_f, fill=TEAL)
        draw.text((gap + 430, y + 2), does, font=text_f, fill=WHITE)
        y += 54
    board.convert("RGB").save(out, quality=92)
    print("wrote", out, board.size)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "parts_board.jpg")
