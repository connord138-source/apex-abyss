"""The new predators' concept board for the owner (2026-10-21: "we need more predator
fish too that felt pretty scattered"): sheets A (the shelf and the Open Blue) and B
(the deep biomes) side by side, each predator named with its biome and how it hunts.

    python3 tools/props/predator_board.py <out.jpg>

Reads assets/tripo/predator_concepts/PredatorSheet{A,B}.png
(tools/tripo_jobs_predator_concepts.json).
"""

import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
SHEETS = ROOT / "assets/tripo/predator_concepts"
FONTS = ROOT / "tools/marketing/fonts"

# Per sheet, its four quadrants: name, biome and levels, how it hunts
PREDATORS = {
    "A": [
        ("SEA LION", "Kelp Shallows · LV 1-10", "Harrier: darts in, nips, loops back. A light bite: learn to juke"),
        ("GOLIATH GROUPER", "Shipwreck Graveyard · LV 10-25", "Lurker: waits in a hull; its gulp sucks you in. Dash out"),
        ("GIANT TREVALLY", "Coral Reef · LV 25-40", "Pack of three: one drives you, two flank. Hide in the arches"),
        ("MAKO SHARK", "Open Blue · LV 35-55", "Missile: the fastest thing in the sea, strikes from below. Juke late"),
    ],
    "B": [
        ("SIXGILL SHARK", "Sunken Ruins · LV 50-70", "Patroller: huge and slow, glowing eyes in the gloom; a heavy bite"),
        ("WOLF EEL", "Hydrothermal Vents · LV 65-85", "Crevice striker: lunges from a basalt hole with a long reach"),
        ("GOBLIN SHARK", "Abyssal Trench · LV 80-100", "Jaw launch: its jaws shoot out for a long bite. Dodge sideways"),
        ("BLACK DRAGONFISH", "Abyssal Trench · LV 80-100", "Lure: a glowing bulb in the dark; get close and it strikes"),
    ],
}

INK = (16, 32, 44)
PANEL = (14, 30, 42, 225)
WHITE = (255, 255, 255)
GOLD = (255, 205, 92)
TEAL = (120, 236, 220)
GREY = (190, 210, 220)


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / name), size)


def main(out: str):
    gap, head, band = 24, 110, 260
    width = 1024 * 2 + gap * 3
    board = Image.new("RGBA", (width, head + 1024 + band), INK + (255,))
    draw = ImageDraw.Draw(board)
    draw.text((gap, 22), "NEW PREDATORS", font=font("LuckiestGuy-Regular.ttf", 64), fill=GOLD)
    draw.text(
        (gap + 500, 38),
        "one or two for every biome, each hunting its own way",
        font=font("LilitaOne-Regular.ttf", 40),
        fill=WHITE,
    )
    name_f = font("LilitaOne-Regular.ttf", 34)
    where_f = font("LilitaOne-Regular.ttf", 26)
    how_f = font("LilitaOne-Regular.ttf", 27)
    for i, key in enumerate(("A", "B")):
        x0 = gap + i * (1024 + gap)
        sheet = Image.open(SHEETS / f"PredatorSheet{key}.png").convert("RGBA").resize((1024, 1024))
        board.alpha_composite(sheet, (x0, head))
        layer = Image.new("RGBA", board.size, (0, 0, 0, 0))
        tags = ImageDraw.Draw(layer)
        for q, (name, where, _) in enumerate(PREDATORS[key]):
            x = x0 + (q % 2) * 512 + 18
            y = head + (q // 2) * 512 + 420
            w = max(tags.textlength(name, font=name_f), tags.textlength(where, font=where_f)) + 28
            tags.rounded_rectangle((x, y - 8, x + w, y + 66), radius=12, fill=PANEL)
            tags.text((x + 14, y - 2), name, font=name_f, fill=TEAL)
            tags.text((x + 14, y + 36), where, font=where_f, fill=GREY)
        board.alpha_composite(layer)
    y = head + 1024 + 20
    for i, key in enumerate(("A", "B")):
        x0 = gap + i * (1024 + gap)
        for q, (name, _, how) in enumerate(PREDATORS[key]):
            yy = y + q * 48
            draw.text((x0, yy), name.title(), font=how_f, fill=GOLD)
            draw.text((x0 + 222, yy), how, font=how_f, fill=WHITE)
    board.convert("RGB").save(out, quality=90)
    print("wrote", out, board.size)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "predators_board.jpg")
