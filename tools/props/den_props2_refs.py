"""Reference images for the den props, batch 2 (2026-10-19): the twelve pieces on
the two approved boards (assets/concepts/DenPropsA.jpg and DenPropsB.jpg, six each in
a loose 3 x 2 layout), each cut off its board on a clean background and drawn large,
for Nano Banana to redraw as one clean model sheet a piece
(tools/tripo_jobs_den_props2_sheets.json), which Tripo then turns into a model
(tools/tripo_jobs_den_props2_models.json).

    python3.11 tools/props/den_props2_refs.py [Name ...]   # -> assets/tripo/den_props2_refs/<Name>.png

Each piece is the board's connected regions inside its box (pixels far from the flat
background, closed and filled, as in furniture_segment.py), dilated and feathered,
over the board's own teal, so a neighbour's corner never comes along. Plus a contact
sheet, _contact.jpg.
"""

from __future__ import annotations

import pathlib
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/tripo/den_props2_refs"
SIZE = 1024
FILL = 0.86  # the piece's longer side, as a share of the canvas

# Each piece's box on its 1024 px board (left, top, right, bottom); every region
# whose middle falls inside it is the piece's (the jellyfish chains, the porthole)
PIECES = {
    "DenPropsA": {
        "DriftwoodTable": (20, 30, 530, 385),
        "KelpBed": (312, 248, 772, 618),
        "PearlPedestal": (795, 26, 982, 497),
        "BubbleColumn": (18, 466, 330, 718),
        "SpongeSofa": (242, 640, 708, 1000),
        "ShipwreckBookshelf": (718, 558, 1006, 1000),
    },
    "DenPropsB": {
        "JellyLamp": (60, 34, 310, 472),
        "SeaGlassLantern": (400, 76, 618, 432),
        "CoralLamp": (682, 46, 990, 538),
        "Banner": (40, 512, 324, 998),
        "ConchGramophone": (366, 545, 644, 962),
        "TreasureChart": (682, 642, 995, 942),
    },
}


def regions(board: np.ndarray, bg: np.ndarray) -> np.ndarray:
    distance = np.sqrt(((board - bg) ** 2).sum(axis=2))
    mask = distance > 38
    mask = ndimage.binary_closing(mask, iterations=6)
    mask = ndimage.binary_fill_holes(mask)
    mask = ndimage.binary_opening(mask, iterations=2)
    labels, _ = ndimage.label(mask)
    return labels


def make(board_name: str, name: str, box: tuple[int, int, int, int]) -> Image.Image:
    board = np.asarray(Image.open(ROOT / f"assets/concepts/{board_name}.jpg").convert("RGB")).astype(np.float32)
    border = np.concatenate(
        [board[:8].reshape(-1, 3), board[-8:].reshape(-1, 3), board[:, :8].reshape(-1, 3), board[:, -8:].reshape(-1, 3)]
    )
    bg = np.median(border, axis=0)
    labels = regions(board, bg)
    x0, y0, x1, y1 = box
    own = np.zeros(labels.shape, bool)
    for index, found in enumerate(ndimage.find_objects(labels)):
        if found is None:
            continue
        ys, xs = found
        cx, cy = (xs.start + xs.stop) / 2, (ys.start + ys.stop) / 2
        if x0 <= cx <= x1 and y0 <= cy <= y1:
            own |= labels == index + 1
    own = ndimage.binary_dilation(own, iterations=10)
    soft = ndimage.gaussian_filter(own.astype(np.float32), 3)[..., None]
    clean = board * soft + bg * (1 - soft)
    ys, xs = np.nonzero(own)
    crop = Image.fromarray(clean.clip(0, 255).astype(np.uint8)).crop(
        (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    )
    scale = SIZE * FILL / max(crop.width, crop.height)
    crop = crop.resize((round(crop.width * scale), round(crop.height * scale)), Image.LANCZOS)
    canvas = Image.new("RGB", (SIZE, SIZE), tuple(int(v) for v in bg))
    canvas.paste(crop, ((SIZE - crop.width) // 2, (SIZE - crop.height) // 2))
    return canvas


def main() -> int:
    wanted = set(sys.argv[1:])
    OUT.mkdir(parents=True, exist_ok=True)
    tiles = []
    for board_name, pieces in PIECES.items():
        for name, box in pieces.items():
            if wanted and name not in wanted:
                continue
            image = make(board_name, name, box)
            path = OUT / f"{name}.png"
            image.save(path)
            tiles.append((name, image))
            print(path.relative_to(ROOT))
    cols = 6
    sheet = Image.new("RGB", (cols * 256, (len(tiles) + cols - 1) // cols * 276), (30, 30, 30))
    draw = ImageDraw.Draw(sheet)
    for i, (name, image) in enumerate(tiles):
        x, y = i % cols * 256, i // cols * 276
        sheet.paste(image.resize((256, 256)), (x, y))
        draw.text((x + 4, y + 258), name, fill=(255, 255, 255))
    sheet.save(OUT / "_contact.jpg", quality=85)
    return 0


if __name__ == "__main__":
    sys.exit(main())
