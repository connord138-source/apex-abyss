"""Badge icons (Config/Social badges), made the way the product icons are
(tools/marketing/product_icons.py: real renders of the game's models on a card drawn in
code, every word set here; owner, 2026-10-14: generated art is "clearly AI").

    python tools/marketing/badge_icons.py renders <dir>   # Blender: the new renders into <dir> (~3 min)
    python tools/marketing/badge_icons.py cards <dir>     # marketing/badge_<icon>_512.png from <dir>
    python tools/marketing/badge_icons.py all <dir>       # both
    python tools/shades/screen_shades.py marketing/badge_*_512.png   # screen before uploading

<dir> also needs product_icons.py's renders (side_<Fish>, shark, chest): run its
`renders <dir>` first, or point both at the same folder.

Roblox crops a badge to a circle, so each card is a round medallion: the cards' navy
glass and bubbles inside a gold ring with a teal hairline, the title kept inside the
circle's chord, the subject in the middle and a tag under it. Outside the ring is
transparent. A Golden or Crystal fish is the Garibaldi's own render with its shading
mapped onto gold or ice (the game draws rare prey as foil and glass, SchoolController).
"""

import math
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = pathlib.Path(os.environ.get("ICONS_OUT", ROOT / "marketing"))

sys.path.insert(0, str(HERE))
import product_icons  # noqa: E402  (Blender, the Cards kit)

# New renders through render_fish.py, own textures: (name, model, view)
RENDERS = [
    ("side_Garibaldi", ROOT / "assets/fbx/prey/Garibaldi.fbx", "1.0,-0.3,0.1"),
    ("side_Megalodon", ROOT / "assets/fbx/bosses/Megalodon.fbx", "1.0,-0.45,0.12"),
]

GOLD_RAMP = ((70, 38, 6), (196, 128, 30), (255, 206, 88), (255, 246, 196))
ICE_RAMP = ((16, 60, 96), (70, 168, 220), (176, 236, 255), (246, 254, 255))


def renders(folder: pathlib.Path):
    folder.mkdir(parents=True, exist_ok=True)
    threads = str(max(1, (os.cpu_count() or 2) // 2))
    base = [product_icons.blender_exe(), "-b", "-t", threads, "--python-exit-code", "1", "-P"]
    for name, model, view in RENDERS:
        print(f"[badge_icons] rendering {name}", flush=True)
        job = base + [str(HERE / "render_fish.py"), "--", str(model), "-", "-", str(folder / f"{name}.png"), "1100", view]
        result = subprocess.run(job, cwd=ROOT, capture_output=True, text=True)
        if result.returncode != 0:
            print(result.stdout[-3000:], result.stderr[-3000:])
            sys.exit(f"[badge_icons] Blender failed on {name}")


class Badges(product_icons.Cards):
    # The medallion: the card's glass cut to a circle, a gold ring, a teal hairline
    def medal(self, card):
        Image, ImageDraw = self.Image, self.ImageDraw
        S, k = self.S, self.k
        out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).ellipse((14, 14, S - 14, S - 14), fill=255)
        out.paste(card, (0, 0), mask)
        d = ImageDraw.Draw(out)
        d.ellipse((14, 14, S - 14, S - 14), outline=k.GOLD + (255,), width=26)
        d.ellipse((52, 52, S - 52, S - 52), outline=k.TEAL + (130,), width=5)
        d.arc((80, 60, S - 80, S * 0.5), 205, 335, fill=(255, 255, 255, 70), width=4)
        return out

    def ramp(self, name, width, colours, dim=1.0):
        """A render's shading mapped onto a colour ramp (gold foil, ice), alpha kept."""
        im = self.fish(name, width, dim=dim, shadow=None)
        r, g, b, a = im.split()
        lum = self.Image.merge("RGB", (r, g, b)).convert("L")
        lum = self.ImageOps.autocontrast(lum, cutoff=1)
        stops = len(colours) - 1
        lut = []
        for channel in range(3):
            for v in range(256):
                t = v / 255 * stops
                i = min(stops - 1, int(t))
                f = t - i
                lut.append(round(colours[i][channel] + (colours[i + 1][channel] - colours[i][channel]) * f))
        rgb = self.Image.merge("RGB", (lum, lum, lum)).point(lut)
        out = rgb.convert("RGBA")
        out.putalpha(a)
        return self.k.with_shadow(out, 22, 150)

    def tag(self, card, label, y=0.80):
        self.k.place(card, self.k.pill(label, 46), self.S * 0.5, self.S * y)

    def welcome(self):
        S, k = self.S, self.k
        card = self.background()
        self.rings(card, S * 0.5, S * 0.62, k.TEAL, [150, 230, 310, 390], alpha=80)
        self.bubbles(card, ((210, 380, 16), (180, 450, 9), (820, 370, 13), (845, 430, 8), (790, 640, 11), (230, 650, 12)))
        k.place(card, self.fish("side_Nibbler", 560), S * 0.5, S * 0.56)
        self.title(card, "WELCOME!", y=0.26, size=130, max_w=0.6)
        self.tag(card, "APEX TIDE")
        return self.finish(self.medal(card))

    def graduate(self):
        S, k = self.S, self.k
        card = self.background(glow=(40, 110, 130))
        self.rays(card, S * 0.5, S * 0.56, k.GOLD, n=14, alpha=34, outer=520)
        self.bubbles(card, ((220, 400, 14), (800, 390, 12), (790, 650, 10), (240, 660, 11)))
        k.place(card, self.fish("side_Nibbler", 520, flip=True), S * 0.5, S * 0.57)
        self.glint(card, S * 0.30, S * 0.41, 50, colour=(255, 226, 140))
        self.glint(card, S * 0.71, S * 0.68, 30, colour=(255, 226, 140))
        self.title(card, "GRADUATE", y=0.26, size=124, max_w=0.6)
        self.tag(card, "TUTORIAL DONE")
        return self.finish(self.medal(card))

    def golden(self):
        S, k = self.S, self.k
        card = self.background(glow=(110, 84, 30))
        self.rays(card, S * 0.5, S * 0.56, k.GOLD, n=18, alpha=48, outer=560)
        k.place(card, self.ramp("side_Garibaldi", 540, GOLD_RAMP), S * 0.5, S * 0.56)
        for x, y, r in ((0.30, 0.43, 44), (0.70, 0.66, 36), (0.66, 0.40, 26)):
            self.glint(card, S * x, S * y, r, colour=(255, 244, 200))
        self.title(card, "GOLDEN", y=0.26, size=136, max_w=0.6)
        self.tag(card, "GOLDEN CATCH")
        return self.finish(self.medal(card))

    def crystal(self):
        S, k = self.S, self.k
        card = self.background(glow=(30, 120, 170))
        self.rays(card, S * 0.5, S * 0.56, k.AQUA, n=12, alpha=36, outer=540, width=0.05)
        k.place(card, self.ramp("side_Garibaldi", 540, ICE_RAMP), S * 0.5, S * 0.56)
        for x, y, r in ((0.31, 0.44, 40), (0.69, 0.64, 34), (0.62, 0.41, 24), (0.42, 0.68, 20)):
            self.glint(card, S * x, S * y, r, colour=(230, 252, 255))
        self.title(card, "CRYSTAL", y=0.26, size=136, max_w=0.6)
        self.tag(card, "CRYSTAL CATCH")
        return self.finish(self.medal(card))

    def boss(self):
        S, k = self.S, self.k
        card = self.background(glow=(20, 70, 100), glow_box=(0.1, 0.3, 0.9, 0.85))
        self.bubbles(card, ((230, 410, 12), (800, 400, 10), (780, 660, 12), (250, 650, 9)))
        k.place(card, self.fish("side_Megalodon", 700), S * 0.5, S * 0.56)
        self.title(card, "BOSS HUNTER", y=0.26, size=112, max_w=0.6)
        self.tag(card, "WORLD BOSS")
        return self.finish(self.medal(card))

    def level(self, label, fish, width, gold=False):
        S, k = self.S, self.k
        card = self.background(glow=(60, 96, 120) if gold else (24, 120, 150))
        if gold:
            self.rays(card, S * 0.5, S * 0.56, k.GOLD, n=18, alpha=44, outer=560)
        else:
            self.rings(card, S * 0.5, S * 0.64, k.TEAL, [160, 240, 320], alpha=70)
        self.bubbles(card, ((220, 410, 13), (810, 400, 11), (790, 650, 10), (240, 655, 12)))
        k.place(card, self.fish(fish, width), S * 0.5, S * 0.56)
        self.title(card, label, y=0.26, size=150, max_w=0.56)
        self.tag(card, "ANY FISH")
        return self.finish(self.medal(card))

    def friend(self):
        S, k = self.S, self.k
        card = self.background()
        self.bubbles(card, ((210, 400, 13), (820, 390, 11), (800, 655, 10), (230, 650, 12)))
        for name, width, x, y in (("side_Puffer", 250, 0.34, 0.50), ("side_Cuda", 300, 0.64, 0.47), ("side_Nibbler", 330, 0.5, 0.63)):
            k.place(card, self.fish(name, width, shadow=(14, 110)), S * x, S * y)
        self.title(card, "SCHOOL'S IN", y=0.26, size=112, max_w=0.6)
        self.tag(card, "A FRIEND JOINED")
        return self.finish(self.medal(card))

    def treasure(self):
        S, k = self.S, self.k
        card = self.background(glow=(90, 80, 40))
        self.rays(card, S * 0.5, S * 0.58, k.GOLD, n=14, alpha=36, outer=520)
        k.place(card, self.fish("chest", 520), S * 0.5, S * 0.58)
        self.title(card, "TREASURE", y=0.26, size=124, max_w=0.6)
        self.tag(card, "X MARKS THE SPOT")
        return self.finish(self.medal(card))

    def apex(self):
        S, k = self.S, self.k
        card = self.background(glow=(60, 96, 120))
        self.rays(card, S * 0.5, S * 0.56, k.GOLD, n=18, alpha=46, outer=560)
        k.place(card, self.fish("shark", 560), S * 0.5, S * 0.58)
        self.glint(card, S * 0.5, S * 0.38, 52, colour=(255, 226, 140))
        self.title(card, "APEX HUNTER", y=0.26, size=112, max_w=0.6)
        self.tag(card, "ATE THE APEX")
        return self.finish(self.medal(card))


def cards(folder: pathlib.Path):
    from PIL import ImageOps

    b = Badges(folder)
    b.ImageOps = ImageOps
    OUT.mkdir(parents=True, exist_ok=True)
    made = {
        "welcome": b.welcome(),
        "graduate": b.graduate(),
        "golden": b.golden(),
        "boss": b.boss(),
        "level25": b.level("LV 25", "side_Cuda", 600),
        "friend": b.friend(),
        "treasure": b.treasure(),
        "apex": b.apex(),
        "crystal": b.crystal(),
        "level100": b.level("LV 100", "side_ReefShark", 640, gold=True),
    }
    for name, image in made.items():
        path = OUT / f"badge_{name}_512.png"
        image.save(path)
        print(f"[badge_icons] {path.relative_to(ROOT) if path.is_relative_to(ROOT) else path}")


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("renders", "cards", "all"):
        sys.exit(__doc__)
    folder = pathlib.Path(sys.argv[2]).resolve()
    if sys.argv[1] in ("renders", "all"):
        renders(folder)
    if sys.argv[1] in ("cards", "all"):
        cards(folder)


if __name__ == "__main__":
    main()
