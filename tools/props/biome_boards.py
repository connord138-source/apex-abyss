"""The biome detail concept boards for the owner (2026-10-21: "lets brainstorm some
ideas to expand on design of the biomes"): for each biome, its landmark scene and its
prop kit side by side, with what each is and how it plays.

    python3 tools/props/biome_boards.py <out dir>

Reads assets/tripo/biome_concepts/<Key>{Scene,Kit}.png (tools/tripo_jobs_biome_concepts.json)
and writes Board<Key>.jpg for each.
"""

import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
SHEETS = ROOT / "assets/tripo/biome_concepts"
FONTS = ROOT / "tools/marketing/fonts"

BIOMES = [
    (
        "Wreck",
        "SHIPWRECK GRAVEYARD",
        "The Broken Galleon",
        "A galleon broken in two you swim through, its captain's cabin lit (a treasure dig site inside); a "
        "toppled lighthouse across the sand; a steamer and a trawler in the haze; chains, cannons, nets.",
        ["Cannon", "Anchor and chain", "Sea-serpent figurehead", "Wheel and bell", "Barrels in a net", "Ship's lantern"],
        "Bite the bell to ring it  ·  a cannon fires you across the bay  ·  lanterns light the wrecks",
    ),
    (
        "Trench",
        "ABYSSAL TRENCH",
        "The Leviathan's Spine",
        "A colossal sea-serpent skeleton arching across the canyon, its ribs an archway to swim through, the "
        "horned skull on a ledge; the Giant Squid's lair with its eggs; glowing crystals on the walls.",
        ["Cyan crystals", "Violet glow tubes", "Glass sponge", "Leviathan skull", "Glowing egg clutch", "Bones with glow worms"],
        "Crystals replace the glowing balls  ·  lines of glowing growth lead you down  ·  the Squid rises from its lair",
    ),
    (
        "Kelp",
        "KELP SHALLOWS",
        "The Kelp Cathedral",
        "A giant kelp grove reaching the surface, its canopy a roof with sun shafts through the gaps; sea-grass "
        "meadows, rippled sand, an urchin patch, sea otters floating on the surface above.",
        ["Lobster trap", "Sunken rowboat", "Sea otter (at the surface)", "Urchins on a rock", "Buoy and chain", "Sea grass"],
        "A trail of old traps and boats leads toward the Wreck bay  ·  the meadows hide small fish",
    ),
    (
        "Reef",
        "CORAL REEF",
        "The Blue Hole",
        "A ring of reef round a deep sinkhole that drops to the deep floor (a shortcut down); table corals on "
        "pillars, sandy highways, colour districts: fire corals, blue and violet, yellow and green.",
        ["Table coral", "Giant clam and pearl", "Garden eels", "Brain coral", "Pillar coral", "Sea fan"],
        "Bite a clam's pearl for a reward (it regrows)  ·  garden eels duck as you pass  ·  dive the Blue Hole",
    ),
    (
        "Blue",
        "OPEN BLUE",
        "The Whale's Rest",
        "Kept open water. A giant whale skeleton on the floor far below; sargassum rafts at the surface with "
        "small fish under them; long glowing jellyfish chains; one far pinnacle ringed by hammerheads (your call).",
        ["Whale skeleton", "Sargassum raft", "Glowing jelly chain", "Coral pinnacle", "Jellyfish", "Rusty buoy"],
        "Small fish shelter under the rafts  ·  steer by the pinnacle  ·  the rest stays open ocean",
    ),
]

INK = (16, 32, 44)
WHITE = (255, 255, 255)
GOLD = (255, 205, 92)
TEAL = (120, 236, 220)
GREY = (190, 210, 220)


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / name), size)


def wrap(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.FreeTypeFont, width: int) -> list[str]:
    lines, line = [], ""
    for word in text.split(" "):
        test = f"{line} {word}".strip()
        if draw.textlength(test, font=f) > width and line:
            lines.append(line)
            line = word
        else:
            line = test
    return lines + [line]


def board(key, title, landmark, about, kit, plays) -> Image.Image:
    gap, head, band = 24, 110, 330
    width = 1024 * 2 + gap * 3
    image = Image.new("RGB", (width, head + 1024 + band), INK)
    draw = ImageDraw.Draw(image)
    draw.text((gap, 22), title, font=font("LuckiestGuy-Regular.ttf", 64), fill=GOLD)
    left = gap + draw.textlength(title, font=font("LuckiestGuy-Regular.ttf", 64)) + 30
    draw.text((left, 38), f"landmark: {landmark}", font=font("LilitaOne-Regular.ttf", 42), fill=WHITE)
    for i, part in enumerate(("Scene", "Kit")):
        sheet = Image.open(SHEETS / f"{key}{part}.png").convert("RGB").resize((1024, 1024))
        image.paste(sheet, (gap + i * (1024 + gap), head))
    text_f = font("LilitaOne-Regular.ttf", 32)
    small = font("LilitaOne-Regular.ttf", 30)
    y = head + 1024 + 22
    for line in wrap(draw, about, text_f, 1024 - 10):
        draw.text((gap, y), line, font=text_f, fill=WHITE)
        y += 42
    draw.text((gap, y + 14), "PLAY", font=small, fill=GOLD)
    for line in wrap(draw, plays, small, 1024 - 90):
        draw.text((gap + 80, y + 14), line, font=small, fill=TEAL)
        y += 40
    x, y = gap * 2 + 1024, head + 1024 + 22
    draw.text((x, y), "KIT (top row, then bottom, left to right)", font=small, fill=GOLD)
    for i, name in enumerate(kit):
        column, row = i // 3, i % 3
        draw.text((x + column * 500, y + 50 + row * 46), f"{i + 1} · {name}", font=text_f, fill=WHITE)
    draw.text(
        (x, head + 1024 + band - 60),
        "Each landmark is a named place: on the map, and a first-visit reward in the LOG.",
        font=small,
        fill=GREY,
    )
    return image


def main(out_dir: str):
    out = pathlib.Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    for spec in BIOMES:
        path = out / f"Board{spec[0]}.jpg"
        board(*spec).save(path, quality=90)
        print("wrote", path)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
