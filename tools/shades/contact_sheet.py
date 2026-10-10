"""Lays shade renders out in a labelled grid.

    python tools/shades/contact_sheet.py <renders_dir> <out.jpg> [Fish] [columns] [tile_height]

With a Fish, its renders come in its list's order (shade_lines.py: the fish's own
line, Common to Mythic, then the universal skins), the fish's own look first, each
labelled with its id and tier. Tiles keep the renders' shape (render_shades.py `pair`
renders are two views wide).
"""

import pathlib
import sys

from PIL import Image, ImageDraw

import shade_lines

renders = pathlib.Path(sys.argv[1])
out = sys.argv[2]
fish = sys.argv[3] if len(sys.argv) > 3 else ""
cols = int(sys.argv[4]) if len(sys.argv) > 4 else 6
th = int(sys.argv[5]) if len(sys.argv) > 5 else 180
files = sorted(renders.glob(f"{fish}*.png"), key=lambda p: (p.stem.split("_")[0], p.stem.split("_", 1)[1] != "Base", p.stem))
labels = {p: p.stem.replace("_", " · ") for p in files}
if fish and fish in shade_lines.fishes():
    order = ["Base"] + shade_lines.shades(fish)
    by_shade = {p.stem.split("_", 1)[1]: p for p in files if p.stem.split("_", 1)[0] == fish}
    files = [by_shade[s] for s in order if s in by_shade]
    labels = {by_shade[s]: f"{s} · {shade_lines.tier(fish, s) or 'own look'}" for s in order if s in by_shade}
if not files:
    raise SystemExit(f"no renders for {fish or 'any fish'} in {renders}")
first = Image.open(files[0])
tw = round(th * first.width / first.height)
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * tw, rows * th), (10, 20, 28))
draw = ImageDraw.Draw(sheet)
for i, path in enumerate(files):
    im = Image.open(path).convert("RGB").resize((tw, th), Image.LANCZOS)
    x, y = (i % cols) * tw, (i // cols) * th
    sheet.paste(im, (x, y))
    draw.rectangle((x, y, x + 7 * len(labels[path]) + 10, y + 16), fill=(10, 20, 28))
    draw.text((x + 6, y + 3), labels[path], fill=(255, 230, 120))
sheet.save(out, quality=88)
print("sheet", out, len(files))
