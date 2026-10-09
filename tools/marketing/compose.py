"""Builds the Roblox store art (icon, logo, thumbnails) for Apex Abyss.

    python3 tools/marketing/compose.py refs     # the style-reference sheets for the image jobs
    SR_MODEL=<EDSR_x2.pb> python3 tools/marketing/compose.py sr   # upscale the key art (slow, cached)
    python3 tools/marketing/compose.py          # icon, logo and every thumbnail
    python3 tools/marketing/compose.py shots    # only the thumbnails from in-game captures

Pipeline (owner, 2026-10-09: "generate our page photo and some thumbnails"):

1. `refs` lays 2-3 approved concepts (assets/concepts/) side by side into one sheet
   per image job, in assets/tripo/marketing_refs/ (gitignored): the Tripo image API
   takes a single reference image, and one concept alone copies its composition.
2. `python3 tools/tripo.py run tools/tripo_jobs_marketing.json` paints the key art
   with Nano Banana Pro (10 credits each) into assets/tripo/marketing/ (gitignored).
   The API only returns 1024x1024 (an aspect setting is ignored), so each scene is
   painted inside a 16:9 strip of the square (`BANDS`) and cropped out here.
3. `sr` upscales each strip 2x with OpenCV's EDSR model (opencv-contrib-python-headless
   and EDSR_x2.pb from github.com/Saafke/EDSR_Tensorflow, ~7 min an image on a CPU)
   into assets/tripo/marketing_sr/; without it the strips are resized with Lanczos.
4. The default command sets the text (never the image model: crisp and spelled
   right), keys the logo off its magenta screen, and writes marketing/ (committed),
   the files to upload in Creator Hub:

       icon_512.png, icon_512_alt.png   the experience icon (512x512) and the runner-up
       logo.png                         APEX ABYSS on a transparent background
       thumb_N_<name>.jpg               thumbnails (1920x1080)
       thumb_N_<name>.jpg from marketing/raw/shot_*.png, in-game captures (committed)

Fonts: tools/marketing/fonts (Lilita One / Titan One, OFL; Luckiest Guy, Apache 2.0).
"""
import os
import pathlib
import sys

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONCEPTS = ROOT / "assets" / "concepts"
REFS = ROOT / "assets" / "tripo" / "marketing_refs"
SRC = ROOT / "assets" / "tripo" / "marketing"
SR = ROOT / "assets" / "tripo" / "marketing_sr"
RAW = ROOT / "marketing" / "raw"
OUT = ROOT / "marketing"
FONTS = pathlib.Path(__file__).resolve().parent / "fonts"

W, H = 1920, 1080
NAVY = (4, 22, 40)
BIG = "LuckiestGuy-Regular.ttf"
SUB = "LilitaOne-Regular.ttf"
WHITE, AQUA = (255, 255, 255), (150, 236, 255)

# The reference sheet behind each image job: approved concepts for its look
REF_SHEETS = {
    "RefHero": ["StyleSheet", "BiomeKelpShallows", "Megalodon"],
    "RefBoss": ["Megalodon", "SpeciesRoster", "BiomeOpenBlue"],
    "RefSquid": ["GiantSquid", "BiomeAbyssalTrench", "StyleSheet"],
    "RefGrow": ["NibblerGrowth", "BiomeCoralReef", "BiomeKelpShallows"],
    "RefShades": ["ShadeSheet", "StyleSheet"],
    "RefTreasure": ["BiomeShipwreck", "StyleSheet", "BiomeCoralReef"],
    "RefWorld": ["BiomeCoralReef", "BiomeShipwreck", "BiomeKelpShallows"],
    "RefIcon": ["StyleSheet", "Megalodon", "NibblerGrowth"],
}

# The 16:9 strip of each 1024x1024 image the scene was painted in (left, top, right,
# bottom); the hero has no strip, so a band round its two subjects is taken
BANDS = {
    "HeroWide": (0, 232, 1024, 808),
    "Boss": (0, 224, 1024, 800),
    "Squid2": (0, 225, 1024, 800),
    "Grow2": (0, 224, 1024, 800),
    "Shades": (0, 224, 1024, 800),
    "Treasure": (0, 224, 1024, 798),
    "World": (0, 224, 1024, 800),
}


def build_refs():
    REFS.mkdir(parents=True, exist_ok=True)
    for name, panels in REF_SHEETS.items():
        size = 768
        sheet = Image.new("RGB", (size * len(panels) + 16 * (len(panels) - 1), size), (255, 255, 255))
        for i, panel in enumerate(panels):
            im = Image.open(CONCEPTS / f"{panel}.jpg").convert("RGB").resize((size, size), Image.LANCZOS)
            sheet.paste(im, (i * (size + 16), 0))
        sheet.save(REFS / f"{name}.jpg", quality=92)
        print("ref", name, sheet.size)


def src(name: str) -> Image.Image:
    path = SRC / f"{name}.png"
    if not path.exists():
        raise SystemExit(f"missing source image {path}")
    return Image.open(path).convert("RGB")


def upscale_bands():
    """EDSR 2x of every strip, cached in assets/tripo/marketing_sr/."""
    import cv2  # opencv-contrib-python-headless

    model = os.environ.get("SR_MODEL")
    if not model:
        raise SystemExit("set SR_MODEL to the path of EDSR_x2.pb")
    SR.mkdir(parents=True, exist_ok=True)
    engine = cv2.dnn_superres.DnnSuperResImpl_create()
    engine.readModel(model)
    engine.setModel("edsr", 2)
    for name, box in BANDS.items():
        out = SR / f"{name}.png"
        if out.exists():
            continue
        band = src(name).crop(box)
        band.save(SR / f"{name}_band.png")
        up = engine.upsample(cv2.imread(str(SR / f"{name}_band.png")))
        cv2.imwrite(str(out), up)
        (SR / f"{name}_band.png").unlink()
        print("upscaled", name, up.shape[1], "x", up.shape[0], flush=True)


def band(name: str) -> Image.Image:
    """The scene's strip at 1920x1080: the EDSR upscale when there is one."""
    cached = SR / f"{name}.png"
    if cached.exists():
        return cover(Image.open(cached).convert("RGB"), W, H)
    # Without the upscale: Lanczos and a light sharpen
    return cover(src(name).crop(BANDS[name]), W, H).filter(ImageFilter.UnsharpMask(2, 70, 2))


def cover(im: Image.Image, w: int, h: int, focus: tuple[float, float] = (0.5, 0.5)) -> Image.Image:
    """Scales to fill w x h and crops around `focus` (0..1 of the source)."""
    scale = max(w / im.width, h / im.height)
    im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
    left = min(max(round(im.width * focus[0] - w / 2), 0), im.width - w)
    top = min(max(round(im.height * focus[1] - h / 2), 0), im.height - h)
    return im.crop((left, top, left + w, top + h))


def key_magenta(im: Image.Image) -> Image.Image:
    """Magenta-screen logo -> RGBA with soft edges and no pink fringe."""
    r, g, b = im.convert("RGB").split()
    magenta = ImageChops.subtract(ImageChops.darker(r, b), g)
    alpha = magenta.point(lambda v: 255 if v < 50 else 0 if v > 130 else round(255 * (130 - v) / 80))
    # Despill: the logo is white, aqua, blue and navy, so red never rises above green
    # or blue there; at the edges the screen's pink did
    r = ImageChops.darker(r, ImageChops.lighter(g, b))
    out = Image.merge("RGBA", (r, g, b, alpha))
    return out.crop(out.getbbox())


def vibrance(im: Image.Image, amount: float = 1.1, contrast: float = 1.04) -> Image.Image:
    return ImageEnhance.Contrast(ImageEnhance.Color(im).enhance(amount)).enhance(contrast)


def text_layer(
    text: str,
    font_name: str,
    size: int,
    top=WHITE,
    bottom=AQUA,
    stroke: int | None = None,
    angle: float = 0,
) -> Image.Image:
    """Chunky game-style text: gradient fill, thick navy outline, drop shadow."""
    font = ImageFont.truetype(str(FONTS / font_name), size)
    stroke = stroke if stroke is not None else max(4, size // 9)
    lines = text.split("\n")
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    boxes = [probe.textbbox((0, 0), line, font=font, stroke_width=stroke) for line in lines]
    line_h = max(b[3] - b[1] for b in boxes)
    width = max(b[2] - b[0] for b in boxes)
    pad = stroke * 3
    height = line_h * len(lines) + pad * 2
    mask_fill = Image.new("L", (width + pad * 2, height), 0)
    mask_all = Image.new("L", mask_fill.size, 0)
    d_fill, d_all = ImageDraw.Draw(mask_fill), ImageDraw.Draw(mask_all)
    for i, (line, box) in enumerate(zip(lines, boxes)):
        x = pad + (width - (box[2] - box[0])) // 2 - box[0]
        y = pad + i * line_h - box[1]
        d_all.text((x, y), line, font=font, fill=255, stroke_width=stroke, stroke_fill=255)
        d_fill.text((x, y), line, font=font, fill=255)
    gradient = Image.new("RGB", mask_fill.size)
    gd = ImageDraw.Draw(gradient)
    for y in range(gradient.height):
        t = y / max(1, gradient.height - 1)
        gd.line([(0, y), (gradient.width, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    layer = Image.new("RGBA", mask_fill.size, (0, 0, 0, 0))
    shadow = Image.new("RGBA", mask_fill.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 170), (0, 0), mask_all)
    shadow = shadow.filter(ImageFilter.GaussianBlur(stroke * 0.8))
    layer.alpha_composite(shadow, (stroke // 2, stroke))
    layer.paste(NAVY + (255,), (0, 0), mask_all)
    layer.paste(gradient, (0, 0), mask_fill)
    if angle:
        layer = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    return layer


def place(canvas: Image.Image, layer: Image.Image, x: int, y: int, anchor: str = "lt"):
    if anchor[0] == "m":
        x -= layer.width // 2
    elif anchor[0] == "r":
        x -= layer.width
    if anchor[1] == "m":
        y -= layer.height // 2
    elif anchor[1] == "b":
        y -= layer.height
    canvas.alpha_composite(layer, (x, y))


def logo_at(width: int, logo: Image.Image) -> Image.Image:
    """The logo at `width`, with a soft dark halo so it reads on any water."""
    scaled = logo.resize((width, round(logo.height * width / logo.width)), Image.LANCZOS)
    halo = Image.new("RGBA", (scaled.width + 80, scaled.height + 80), (0, 0, 0, 0))
    alpha = Image.new("L", halo.size, 0)
    alpha.paste(scaled.getchannel("A"), (40, 40))
    halo.paste((0, 8, 20, 150), (0, 0), alpha.filter(ImageFilter.GaussianBlur(18)))
    halo.alpha_composite(scaled, (40, 40))
    return halo


def scrim(canvas: Image.Image, corner: str, strength: int = 150, reach: float = 0.55):
    """Darkens toward one corner or edge ('tl', 'tr', 'bl', 'br', 't', 'b') so text reads."""
    mask = Image.new("L", (W // 4, H // 4), 0)
    pixels = mask.load()
    for y in range(mask.height):
        for x in range(mask.width):
            u, v = x / (mask.width - 1), y / (mask.height - 1)
            dx = u if "l" in corner else 1 - u if "r" in corner else 0
            dy = v if "t" in corner else 1 - v if "b" in corner else 0
            d = (dx * dx + dy * dy) ** 0.5 if len(corner) == 2 else dy
            pixels[x, y] = round(strength * max(0.0, 1 - d / reach) ** 1.6)
    mask = mask.resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(8))
    dark = Image.new("RGBA", (W, H), NAVY + (0,))
    dark.putalpha(mask)
    canvas.alpha_composite(dark)


def vignette(canvas: Image.Image, strength: int = 90):
    mask = Image.new("L", canvas.size, 0)
    d = ImageDraw.Draw(mask)
    d.ellipse((-canvas.width * 0.15, -canvas.height * 0.25, canvas.width * 1.15, canvas.height * 1.25), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(160))
    dark = Image.new("RGBA", canvas.size, (0, 0, 0, strength))
    dark.putalpha(ImageChops.invert(mask).point(lambda v: v * strength // 255))
    canvas.alpha_composite(dark)


def thumb(name: str, strength: int = 80) -> Image.Image:
    c = vibrance(band(name)).convert("RGBA")
    vignette(c, strength)
    return c


def save(c: Image.Image, name: str):
    c.convert("RGB").save(OUT / name, quality=92)


def main():
    OUT.mkdir(exist_ok=True)
    logo = key_magenta(src("Logo"))
    logo.save(OUT / "logo.png")

    # The icon: eat or be eaten, readable at the size of a thumbnail tile. B (the
    # Nibbler chomping at you) is the runner-up
    vibrance(src("IconA")).resize((512, 512), Image.LANCZOS).save(OUT / "icon_512.png")
    vibrance(src("IconB")).resize((512, 512), Image.LANCZOS).save(OUT / "icon_512_alt.png")

    # 1. The hook (lead thumbnail): the Nibbler gulping, the Megalodon behind
    c = thumb("HeroWide")
    scrim(c, "tl", 150)
    scrim(c, "bl", 120, 0.45)
    place(c, logo_at(640, logo), 10, 0)
    place(c, text_layer("EAT. GROW.\nBECOME THE APEX!", BIG, 92, angle=-3), 60, H - 36, "lb")
    save(c, "thumb_1_eat.jpg")

    # 2. World bosses: the whole server on the Megalodon
    c = thumb("Boss")
    scrim(c, "bl", 170, 0.6)
    place(c, logo_at(420, logo), 10, 0)
    place(c, text_layer("WORLD\nBOSSES!", BIG, 128, (255, 240, 140), (255, 120, 40), angle=-4), 60, H - 110, "lb")
    place(c, text_layer("TEAM UP · TAKE DOWN THE MEGALODON", SUB, 52), 70, H - 36, "lb")
    save(c, "thumb_2_boss.jpg")

    # 3. The pitch-dark Trench and the Giant Squid
    c = thumb("Squid2", 60)
    scrim(c, "tl", 120)
    place(c, logo_at(420, logo), 10, 0)
    place(c, text_layer("HUNT IN\nTHE DARK!", BIG, 120, (220, 255, 250), (80, 230, 200), angle=-3), W - 50, H - 40, "rb")
    save(c, "thumb_3_dark.jpg")

    # 4. Grow: fry to apex
    c = thumb("Grow2", 60)
    scrim(c, "tl", 140)
    place(c, logo_at(420, logo), 10, 0)
    place(c, text_layer("START SMALL.\nEAT BIG!", BIG, 112, (255, 240, 140), (255, 140, 40), angle=-3), W - 50, 40, "rt")
    place(c, text_layer("FRY  ›  JUVENILE  ›  ADULT  ›  APEX", SUB, 52), W // 2, H - 30, "mb")
    save(c, "thumb_4_grow.jpg")

    # 5. Rare shades
    c = thumb("Shades", 40)
    place(c, text_layer("RARE SHADES!", BIG, 128, (255, 240, 190), (255, 196, 70)), W // 2, 30, "mt")
    place(c, text_layer("PRISMATIC · GHOST · MAGMA · NEBULA · DIVINE", SUB, 50), W // 2, H - 40, "mb")
    place(c, logo_at(300, logo), 10, H - 10, "lb")
    save(c, "thumb_5_shades.jpg")

    # 6. Treasure maps
    # (the map itself lies at the left, so the headline sits top right)
    c = thumb("Treasure")
    scrim(c, "tl", 150)
    scrim(c, "tr", 130, 0.5)
    scrim(c, "b", 110, 0.28)
    place(c, logo_at(420, logo), 10, 0)
    place(c, text_layer("TREASURE\nMAPS!", BIG, 120, (255, 240, 140), (255, 170, 40), angle=3), W - 50, 30, "rt")
    place(c, text_layer("DIG UP CORAL, SHELLS AND RARE SHADES", SUB, 50), W // 2, H - 34, "mb")
    save(c, "thumb_6_treasure.jpg")

    # 7. Seven biomes
    c = thumb("World")
    scrim(c, "t", 150, 0.42)
    place(c, text_layer("EXPLORE 7 BIOMES!", BIG, 116), W // 2, 26, "mt")
    place(c, text_layer("KELP · REEF · WRECKS · OPEN BLUE · RUINS · VENTS · TRENCH", SUB, 44), W // 2, H - 34, "mb")
    place(c, logo_at(300, logo), W - 10, H - 70, "rb")
    save(c, "thumb_7_biomes.jpg")

    shots()
    print("wrote", ", ".join(sorted(p.name for p in OUT.iterdir() if p.is_file())))


def shots():
    """Thumbnails from in-game captures (marketing/raw/shot_*.png, 1920x1080, HUD
    hidden), each made when its capture is there. docs/STORE_PAGE.md lists the shots."""
    logo_path = OUT / "logo.png"
    if not logo_path.exists():
        return
    logo = Image.open(logo_path).convert("RGBA")

    def shot(name: str) -> Image.Image | None:
        path = RAW / f"{name}.png"
        if not path.exists():
            return None
        c = vibrance(cover(Image.open(path).convert("RGB"), W, H)).convert("RGBA")
        vignette(c, 70)
        return c

    lines = {
        "shot_8_den": ("BUILD YOUR\nDEN!", "TROPHIES · FURNITURE · CORAL GARDEN"),
        "shot_9_megalodon": ("FIGHT THE\nMEGALODON!", "A WORLD BOSS EVERY 30 MINUTES"),
        "shot_10_reveal": ("ROLL RARE\nSHADES!", "COLLECT SHELLS · 30+ SHADES TO FIND"),
    }
    for name, (headline, sub) in lines.items():
        c = shot(name)
        if c is None:
            continue
        scrim(c, "tl", 140)
        scrim(c, "b", 120, 0.3)
        place(c, logo_at(420, logo), 10, 0)
        place(c, text_layer(headline, BIG, 116, angle=-3), W - 50, 40, "rt")
        place(c, text_layer(sub, SUB, 50), W // 2, H - 34, "mb")
        number, label = name.split("_")[1], name.split("_", 2)[2]
        save(c, f"thumb_{number}_{label}.jpg")


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "refs":
        build_refs()
    elif command == "sr":
        upscale_bands()
    elif command == "shots":
        shots()
    else:
        main()
