"""The studio community's cover photo (1440x456, the size Roblox takes for a banner).

    python3 tools/marketing/community_cover.py [path to the hatch-and-snatch clone] [name]

Apex Tide on the left, Hatch & Snatch on the right, the community badge and the
studio's name on a navy panel between them, edged with foam. The Apex Tide scene is
the store hero (assets/tripo/marketing_sr/HeroWide.png, gitignored); the Hatch &
Snatch one is a text-free crop of that game's lead thumbnail. Writes
marketing/community_cover_1440x456.png.
"""
import math
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from compose import BIG, OUT, SR, SUB, WHITE, AQUA, cover, place, text_layer, vibrance  # noqa: E402

W, H = 1440, 456
PANEL = (0, 34, 68)
GOLD_TOP, GOLD_BOTTOM = (255, 232, 130), (246, 158, 28)
# The navy panel's edges: a gentle swell either side of the middle
LEFT_EDGE, RIGHT_EDGE, SWELL, WAVE = 548, 892, 16, 152


def edge(base: float, y: float, phase: float) -> float:
    return base + SWELL * math.sin(2 * math.pi * y / WAVE + phase)


def panel_mask() -> Image.Image:
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    left = [(edge(LEFT_EDGE, y, 0), y) for y in range(0, H + 1, 2)]
    right = [(edge(RIGHT_EDGE, y, math.pi), y) for y in range(H, -1, -2)]
    d.polygon(left + right, fill=255)
    return mask


def foam(canvas: Image.Image):
    """White crests along both edges with a teal glow."""
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    line = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dg, dl = ImageDraw.Draw(glow), ImageDraw.Draw(line)
    for base, phase in ((LEFT_EDGE, 0), (RIGHT_EDGE, math.pi)):
        points = [(edge(base, y, phase), y) for y in range(-4, H + 5, 2)]
        dg.line(points, fill=(40, 230, 230, 200), width=22)
        dl.line(points, fill=(255, 255, 255, 255), width=6)
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(9)))
    canvas.alpha_composite(line)


def badge(size: int) -> Image.Image:
    im = Image.open(OUT / "community_a_512.png").convert("RGBA")
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).ellipse((40, 40, 472, 472), fill=255)
    im.putalpha(mask.filter(ImageFilter.GaussianBlur(2)))
    im = im.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size + 60, size + 60), (0, 0, 0, 0))
    shadow = Image.new("L", out.size, 0)
    shadow.paste(im.getchannel("A"), (30, 38))
    out.paste((0, 6, 16, 190), (0, 0), shadow.filter(ImageFilter.GaussianBlur(12)))
    out.alpha_composite(im, (30, 30))
    return out


def main():
    hs_root = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else OUT.parents[1] / "hatch-and-snatch"
    name = sys.argv[2] if len(sys.argv) > 2 else "TIDEBITE"

    canvas = Image.new("RGBA", (W, H), PANEL + (255,))

    # Apex Tide: the Nibbler gulping with the Megalodon behind
    apex = Image.open(SR / "HeroWide.png").convert("RGB").crop((400, 0, 1900, 1152))
    canvas.paste(vibrance(cover(apex, LEFT_EDGE + 40, H, (0.5, 0.55))), (0, 0))

    # Hatch & Snatch: the moon egg, the hatchery dome and the egg belt (no text there)
    hs = Image.open(hs_root / "marketing" / "thumb_1_steal.jpg").convert("RGB").crop((860, 90, 1920, 980))
    width = W - RIGHT_EDGE + 40
    canvas.paste(vibrance(cover(hs, width, H, (0.5, 0.45)), 1.0, 1.0), (W - width, 0))

    # The panel between them: navy, lighter at the top like the badge's own water
    panel = Image.new("RGBA", (W, H))
    pd = ImageDraw.Draw(panel)
    for y in range(H):
        t = y / (H - 1)
        pd.line([(0, y), (W, y)], fill=(0, round(92 - 62 * t), round(132 - 70 * t), 255))
    canvas.paste(panel, (0, 0), panel_mask())
    foam(canvas)

    mid = (LEFT_EDGE + RIGHT_EDGE) // 2
    place(canvas, badge(214), mid, 6, "mt")
    place(canvas, text_layer(name, BIG, 70, WHITE, AQUA), mid, 290, "mt")
    place(canvas, text_layer("STUDIOS", SUB, 40, GOLD_TOP, GOLD_BOTTOM), mid, 368, "mt")

    target = OUT / "community_cover_1440x456.png"
    canvas.convert("RGB").save(target)
    print("wrote", target)


if __name__ == "__main__":
    main()
