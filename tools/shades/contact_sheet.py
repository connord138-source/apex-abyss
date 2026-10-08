"""Lays shade renders out in a labelled grid.

    python tools/shades/contact_sheet.py <renders_dir> <out.jpg> [Fish] [columns]
"""

import pathlib
import sys

from PIL import Image, ImageDraw

renders = pathlib.Path(sys.argv[1])
out = sys.argv[2]
fish = sys.argv[3] if len(sys.argv) > 3 else ""
cols = int(sys.argv[4]) if len(sys.argv) > 4 else 6
files = sorted(renders.glob(f"{fish}*.png"), key=lambda p: (p.stem.split("_")[0], p.stem.split("_", 1)[1] != "Base", p.stem))
tw, th = 260, 180
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * tw, rows * th), (10, 20, 28))
draw = ImageDraw.Draw(sheet)
for i, path in enumerate(files):
    im = Image.open(path).convert("RGB").resize((tw, th))
    x, y = (i % cols) * tw, (i // cols) * th
    sheet.paste(im, (x, y))
    draw.text((x + 6, y + 4), path.stem.replace("_", " · "), fill=(255, 230, 120))
sheet.save(out, quality=88)
print("sheet", out, len(files))
