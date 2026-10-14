"""The Deep Pass product icon, built from the game itself (owner, 2026-10-14: generated
key art "has nothing to do with deep pass and [is] clearly AI").

    python3.11 tools/marketing/render_fish.py -- assets/tripo/species/ReefShark.glb assets/shades/skins PassRiptide <dir>/shark_riptide.png 1200
    python3.11 tools/marketing/render_fish.py -- assets/tripo/species/Cuda.glb assets/shades/skins PassUndertow <dir>/cuda_undertow.png 900
    python3.11 tools/marketing/render_fish.py -- assets/tripo/species/Angler.glb assets/shades/skins PassAbyssalCurrent <dir>/angler_current.png 900
    python3.11 tools/marketing/pass_icon.py <dir>

The three fish are real renders of the game's models wearing Season 1's Deep Pass skins
(Riptide, Undertow, Abyssal Current: the real textures from assets/shades/skins). The
card is drawn here in the game's UI palette (Ui.luau: navy glass, gold, teal) with its
fonts: a riptide swirl of thin current lines, bubbles, a gold frame, DEEP PASS on top.
Writes marketing/deep_pass_512.png (the three skins) and deep_pass_512_alt.png (the
Riptide shark alone), both 512x512, for Creator Hub (the Deep Pass developer product).
Screen them with tools/shades/screen_shades.py before uploading.
"""

import math
import pathlib
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
FONTS = pathlib.Path(__file__).resolve().parent / "fonts"
OUT = ROOT / "marketing"
S = 1024  # drawn at twice the size, then halved

NAVY = (4, 22, 40)
PANEL = (12, 34, 54)
FOOT = (3, 10, 20)
TEAL = (86, 222, 255)
GOLD = (255, 204, 92)
GOLD_TOP = (255, 238, 170)
GOLD_LOW = (240, 168, 52)
AQUA = (150, 236, 255)


def rounded_mask(size: int, inset: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((inset, inset, size - inset, size - inset), radius, fill=255)
    return mask


def background() -> Image.Image:
    """Navy glass, lighter at the top, with a riptide: thin current lines spiralling in."""
    card = Image.new("RGBA", (S, S))
    draw = ImageDraw.Draw(card)
    for y in range(S):
        t = y / (S - 1)
        colour = tuple(round(a + (b - a) * t**1.2) for a, b in zip(PANEL, FOOT))
        draw.line([(0, y), (S, y)], fill=colour + (255,))
    # A soft teal glow behind where the fish swim
    glow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(glow).ellipse((S * 0.14, S * 0.30, S * 0.86, S * 0.86), fill=150)
    glow = glow.filter(ImageFilter.GaussianBlur(110))
    card.paste((24, 120, 150), (0, 0), glow)
    # The riptide: arcs of a logarithmic spiral round a point below the middle
    swirl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(swirl)
    cx, cy = S * 0.5, S * 0.6
    for arm in range(7):
        start = arm * 2 * math.pi / 7
        points = []
        for i in range(140):
            a = start + i * 0.045
            r = 40 * math.exp(0.16 * (a - start)) + 30
            if r > S * 0.75:
                break
            points.append((cx + math.cos(a) * r, cy + math.sin(a) * r * 0.62))
        for i in range(1, len(points)):
            fade = min(1.0, i / 25) * max(0.0, 1 - i / len(points))
            sd.line([points[i - 1], points[i]], fill=TEAL + (round(95 * fade),), width=6)
    card.alpha_composite(swirl.filter(ImageFilter.GaussianBlur(1.2)))
    # Bubbles: thin rings, a few
    bd = ImageDraw.Draw(card)
    for x, y, r in ((150, 330, 16), (118, 400, 9), (880, 310, 13), (905, 370, 8), (860, 640, 11), (170, 700, 12)):
        bd.ellipse((x - r, y - r, x + r, y + r), outline=AQUA + (130,), width=3)
        bd.ellipse((x - r * 0.45, y - r * 0.6, x - r * 0.05, y - r * 0.2), fill=(255, 255, 255, 110))
    return card


def frame(card: Image.Image) -> Image.Image:
    """Cut to a rounded square with a gold rim and a teal hairline inside it."""
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(card, (0, 0), rounded_mask(S, 0, 150))
    d = ImageDraw.Draw(out)
    d.rounded_rectangle((10, 10, S - 10, S - 10), 140, outline=GOLD + (255,), width=18)
    d.rounded_rectangle((36, 36, S - 36, S - 36), 116, outline=TEAL + (120,), width=4)
    # A hairline of light along the top edge, like the game's panels
    d.arc((40, 30, S - 40, 260), 200, 340, fill=(255, 255, 255, 60), width=3)
    return out


def fish(path: pathlib.Path, width: int, flip: bool = False, dim: float = 1.0) -> Image.Image:
    im = Image.open(path).convert("RGBA")
    im = im.crop(im.getbbox())
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    if dim < 1:
        r, g, b, a = im.split()
        im = Image.merge("RGBA", tuple(c.point(lambda v: round(v * dim)) for c in (r, g, b)) + (a,))
    return im


def with_shadow(layer: Image.Image, blur: int = 24, alpha: int = 150) -> Image.Image:
    pad = blur * 3
    out = Image.new("RGBA", (layer.width + pad * 2, layer.height + pad * 2), (0, 0, 0, 0))
    shadow = Image.new("RGBA", out.size, (0, 0, 0, 0))
    mask = Image.new("L", out.size, 0)
    mask.paste(layer.getchannel("A"), (pad, pad + blur // 2))
    shadow.paste((0, 6, 16, alpha), (0, 0), mask.filter(ImageFilter.GaussianBlur(blur)))
    out.alpha_composite(shadow)
    out.alpha_composite(layer, (pad, pad))
    return out


def text(text: str, font: str, size: int, top, low, stroke: int) -> Image.Image:
    """Game-style lettering: a gradient fill, a thick navy outline, a drop shadow."""
    f = ImageFont.truetype(str(FONTS / font), size)
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    box = probe.textbbox((0, 0), text, font=f, stroke_width=stroke)
    pad = stroke * 3
    w, h = box[2] - box[0] + pad * 2, box[3] - box[1] + pad * 2
    fill_mask, all_mask = Image.new("L", (w, h), 0), Image.new("L", (w, h), 0)
    at = (pad - box[0], pad - box[1])
    ImageDraw.Draw(all_mask).text(at, text, font=f, fill=255, stroke_width=stroke, stroke_fill=255)
    ImageDraw.Draw(fill_mask).text(at, text, font=f, fill=255)
    gradient = Image.new("RGB", (w, h))
    gd = ImageDraw.Draw(gradient)
    for y in range(h):
        t = min(1.0, max(0.0, (y - pad) / max(1, h - 2 * pad)))
        gd.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, low)))
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 180), (0, 0), all_mask)
    layer.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(stroke * 0.7)), (0, 0))
    layer.alpha_composite(Image.new("RGBA", (w, h), (0, 0, 0, 0)))
    layer.paste(NAVY + (255,), (0, stroke // 2), all_mask)
    layer.paste(NAVY + (255,), (0, 0), all_mask)
    layer.paste(gradient, (0, 0), fill_mask)
    return layer


def pill(label: str, size: int) -> Image.Image:
    """A small rounded tag, like the game's chips: navy glass, teal rim, aqua text."""
    f = ImageFont.truetype(str(FONTS / "LilitaOne-Regular.ttf"), size)
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    box = probe.textbbox((0, 0), label, font=f)
    w, h = box[2] - box[0] + size * 1.4, box[3] - box[1] + size * 0.8
    w, h = round(w), round(h)
    tag = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(tag)
    d.rounded_rectangle((0, 0, w - 1, h - 1), h // 2, fill=(6, 26, 44, 235), outline=TEAL + (200,), width=4)
    d.text(((w - (box[2] - box[0])) / 2 - box[0], (h - (box[3] - box[1])) / 2 - box[1]), label, font=f, fill=AQUA)
    return tag


def place(canvas: Image.Image, layer: Image.Image, cx: float, cy: float):
    canvas.alpha_composite(layer, (round(cx - layer.width / 2), round(cy - layer.height / 2)))


def build(renders: pathlib.Path, trio: bool) -> Image.Image:
    card = background()
    if trio:
        # The Undertow 'Cuda and the Abyssal Current Angler behind, the Riptide shark in front
        place(card, with_shadow(fish(renders / "cuda_undertow.png", 330, flip=True, dim=0.92), 18, 110), S * 0.31, S * 0.48)
        place(card, with_shadow(fish(renders / "angler_current.png", 280, dim=0.92), 18, 110), S * 0.72, S * 0.47)
        place(card, with_shadow(fish(renders / "shark_riptide.png", 640)), S * 0.50, S * 0.665)
    else:
        place(card, with_shadow(fish(renders / "shark_riptide.png", 820)), S * 0.50, S * 0.60)
    card = frame(card)
    place(card, text("DEEP PASS", "LuckiestGuy-Regular.ttf", 150, GOLD_TOP, GOLD_LOW, 14), S * 0.5, S * 0.19)
    place(card, pill("SEASON 1 · RIPTIDE", 44), S * 0.5, S * 0.33)
    if trio:
        place(card, pill("3 EXCLUSIVE SKINS", 46), S * 0.5, S * 0.885)
    return card.resize((512, 512), Image.LANCZOS)


def main():
    renders = pathlib.Path(sys.argv[1])
    OUT.mkdir(exist_ok=True)
    build(renders, True).save(OUT / "deep_pass_512.png")
    build(renders, False).save(OUT / "deep_pass_512_alt.png")
    print(f"wrote {OUT / 'deep_pass_512.png'} and {OUT / 'deep_pass_512_alt.png'}")


if __name__ == "__main__":
    main()
