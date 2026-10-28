"""Concept boards for the rolled parts redrawn as mutations of each fish's own body
(owner, 2026-10-28, of the Veil Tail on the Reef Shark: "dont like how any of these
look. theyre not a part of the fish like we need. think mutation or variant").

One generated sheet per fish (tools/tripo_jobs_parts_v2_concepts.json, Nano Banana Pro):
2 columns by 3 rows, the plain fish top left, then the fish grown each of the five
parts (Angler Lure, Narwhal Horn, Sawblade Snout, Sail Fin, Veil Tail) out of its own
skin. Each sheet's reference is that fish's own model sheet six times on soft teal, so
the redraw keeps its body, colours, eyes and view and only grows the part.

    python3 tools/props/parts_v2_board.py refs  # -> assets/tripo/parts_v2_refs/<Fish>.png, <Fish>_big.png
    python3 tools/props/parts_v2_board.py       # -> assets/concepts/parts_v2/<Fish>.jpg, AllFish.jpg

A sheet that needed another go is <Fish>_try2.png (or _try3) beside the first, made on
the `_big` reference (the jobs file names them); PICK says which sheet each board cell
comes from.
"""

from __future__ import annotations

import pathlib
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPECIES = ROOT / "assets/tripo/species_sheets"
REFS = ROOT / "assets/tripo/parts_v2_refs"
SHEETS = ROOT / "assets/tripo/parts_v2_concepts"
OUT = ROOT / "assets/concepts/parts_v2"
FONTS = ROOT / "tools/marketing/fonts"

TEAL = (122, 197, 190)  # the variant sheet's background
SIZE = 1024
COLS, ROWS = 2, 3
# Each copy's size in its cell on the reference, leaving room to grow; the "_big" refs
# (for the second goes) draw the fish larger, so the redraw gives it more pixels
REF_BOXES = {"": (300, 196), "_big": (370, 236)}

# (sheet name, the name players see)
FISH = [
    ("Nibbler", "NIBBLER"),
    ("Cuda", "'CUDA"),
    ("Puffer", "PUFFERFISH"),
    ("MorayEel", "MORAY EEL"),
    ("ReefShark", "REEF SHARK"),
    ("Angler", "ANGLERFISH"),
]

# The cells in reading order, as the prompts name them
PARTS = ["", "ANGLER LURE", "NARWHAL HORN", "SAWBLADE SNOUT", "SAIL FIN", "VEIL TAIL"]

# Which generated sheet each of a board's six cells comes from ("" = the first go,
# "_try2" / "_try3" = a later one, on the larger reference); a fish not listed takes
# every cell from its first sheet. Picked by eye, 2026-10-28: the second goes drew the
# fish bigger and fixed the weak sails and veils; the first go kept the better one where
# the redo was worse (the shark's saw was short and beige, the Angler's veil smaller,
# the Puffer's sail a crest of spines).
PICK: dict[str, list[str]] = {
    "Cuda": ["_try2"] * 6,
    "Puffer": ["_try2", "_try2", "_try2", "_try2", "", "_try2"],
    "MorayEel": ["_try3", "_try3", "_try3", "_try3", "_try2", "_try3"],
    "ReefShark": ["_try2", "_try2", "_try2", "", "_try2", "_try2"],
    "Angler": ["_try2", "_try2", "_try2", "_try2", "_try2", ""],
}

INK = (16, 32, 44)
WHITE = (255, 255, 255)
GOLD = (255, 205, 92)
MINT = (120, 236, 220)
GREY = (190, 210, 220)


# -- references -----------------------------------------------------------------------


def matte(image: Image.Image) -> Image.Image:
    """The fish's mask: everything not joined to the border by background colour"""
    work = image.copy()
    sentinel = (255, 0, 255)
    w, h = work.size
    seeds = [(x, y) for x in range(0, w, 16) for y in (0, h - 1)] + [(x, y) for y in range(0, h, 16) for x in (0, w - 1)]
    for seed in seeds:
        if work.getpixel(seed) != sentinel:
            ImageDraw.floodfill(work, seed, sentinel, thresh=34)
    pixels = np.asarray(work)
    background = (pixels[..., 0] == 255) & (pixels[..., 1] == 0) & (pixels[..., 2] == 255)
    mask = Image.fromarray(np.where(background, 0, 255).astype(np.uint8))
    return mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))


def fit(image: Image.Image, width: int, height: int) -> Image.Image:
    scale = min(width / image.width, height / image.height)
    return image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)


def reference(name: str, suffix: str = "") -> pathlib.Path:
    sheet = Image.open(SPECIES / f"{name}.png").convert("RGB")
    mask = matte(sheet)
    box = mask.point(lambda v: 255 if v > 40 else 0).getbbox()
    fish = Image.new("RGB", sheet.size, TEAL)
    fish.paste(sheet, (0, 0), mask)
    fish, mask = fish.crop(box), mask.crop(box)
    box_w, box_h = REF_BOXES[suffix]
    fish, mask = fit(fish, box_w, box_h), fit(mask, box_w, box_h)
    canvas = Image.new("RGB", (SIZE, SIZE), TEAL)
    cell_w, cell_h = SIZE // COLS, SIZE // ROWS
    for i in range(COLS * ROWS):
        x = (i % COLS) * cell_w + (cell_w - fish.width) // 2
        y = (i // COLS) * cell_h + (cell_h - fish.height) // 2
        canvas.paste(fish, (x, y), mask)
    out = REFS / f"{name}{suffix}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out)
    return out


# -- boards ---------------------------------------------------------------------------


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / name), size)


def centred(draw: ImageDraw.ImageDraw, x: int, y: int, text: str, f: ImageFont.FreeTypeFont, fill):
    left, top, right, _ = draw.textbbox((0, 0), text, font=f)
    draw.text((x - (right - left) // 2 - left, y - top), text, font=f, fill=fill)


def background_of(sheet: np.ndarray) -> np.ndarray:
    """The sheet's own teal: the median of its border"""
    border = np.concatenate([sheet[:6].reshape(-1, 3), sheet[-6:].reshape(-1, 3), sheet[:, :6].reshape(-1, 3), sheet[:, -6:].reshape(-1, 3)])
    return np.median(border, axis=0)


def islands(mask: np.ndarray) -> list[tuple[int, int, int, int, int]]:
    """Connected blobs of a coarse mask: (left, top, right, bottom, area) in mask cells"""
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    found = []
    for y0 in range(h):
        for x0 in range(w):
            if not mask[y0, x0] or seen[y0, x0]:
                continue
            stack = [(y0, x0)]
            seen[y0, x0] = True
            left, top, right, bottom, area = x0, y0, x0, y0, 0
            while stack:
                y, x = stack.pop()
                area += 1
                left, right, top, bottom = min(left, x), max(right, x), min(top, y), max(bottom, y)
                for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            found.append((left, top, right + 1, bottom + 1, area))
    return found


def cells(sheet: Image.Image) -> list[Image.Image]:
    """The six fish, each cropped by its content: what differs from the sheet's teal,
    found as blobs over the whole sheet (a horn or a tail may cross a cell's line), each
    blob going to the cell its middle is in; a cell keeps its biggest blob plus anything
    near it (a lure's bulb, a trailing lobe)"""
    rgb = np.asarray(sheet.convert("RGB")).astype(np.int32)
    back = background_of(rgb)
    differs = np.abs(rgb - back).sum(axis=2) > 46
    h, w = differs.shape
    cell_w, cell_h = w // COLS, h // ROWS
    # (4 px blocks: the blob search stays quick and specks drop out)
    coarse = differs[: h // 4 * 4, : w // 4 * 4].reshape(h // 4, 4, w // 4, 4).mean(axis=(1, 3)) > 0.3
    by_cell: dict[int, list] = {}
    for blob in islands(coarse):
        mid_x, mid_y = (blob[0] + blob[2]) * 2, (blob[1] + blob[3]) * 2
        i = min(int(mid_y // cell_h), ROWS - 1) * COLS + min(int(mid_x // cell_w), COLS - 1)
        by_cell.setdefault(i, []).append(blob)
    out = []
    for i in range(COLS * ROWS):
        blobs = sorted(by_cell.get(i, []), key=lambda b: -b[4])
        if not blobs:
            x0, y0 = (i % COLS) * cell_w, (i // COLS) * cell_h
            out.append(sheet.crop((x0, y0, x0 + cell_w, y0 + cell_h)))
            continue
        main = blobs[0]
        keep = [main] + [b for b in blobs[1:] if b[4] >= 6 and touches(b, main, 30)]
        pad = 20
        out.append(
            sheet.crop(
                (
                    max(min(b[0] for b in keep) * 4 - pad, 0),
                    max(min(b[1] for b in keep) * 4 - pad, 0),
                    min(max(b[2] for b in keep) * 4 + pad, w),
                    min(max(b[3] for b in keep) * 4 + pad, h),
                )
            )
        )
    return out


def fade(size: tuple[int, int], ramp: int = 18) -> Image.Image:
    """A paste mask that fades a crop's edges out, so the sheet's own teal round a glow
    or in a corner never shows as a box against the cell's"""
    w, h = size
    xs = np.minimum(np.arange(w), np.arange(w)[::-1])
    ys = np.minimum(np.arange(h), np.arange(h)[::-1])
    edge = np.minimum.outer(ys, xs).astype(np.float32)
    return Image.fromarray((np.clip(edge / ramp, 0, 1) * 255).astype(np.uint8))


def touches(a, b, gap: int) -> bool:
    return a[0] <= b[2] + gap and b[0] <= a[2] + gap and a[1] <= b[3] + gap and b[1] <= a[3] + gap


def picks(name: str) -> list[str]:
    return PICK.get(name, [""] * len(PARTS))


def board(name: str, label: str) -> Image.Image:
    # Every cell from the sheet PICK names for it, on that sheet's own teal
    crops, backs = [], []
    loaded: dict[str, tuple[list[Image.Image], tuple[int, ...]]] = {}
    for i, suffix in enumerate(picks(name)):
        if suffix not in loaded:
            sheet = Image.open(SHEETS / f"{name}{suffix}.png").convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
            back = tuple(int(v) for v in background_of(np.asarray(sheet).astype(np.int32)))
            loaded[suffix] = (cells(sheet), back)
        crops.append(loaded[suffix][0][i])
        backs.append(loaded[suffix][1])
    cell_w, cell_h, text_h, gap, head = 600, 400, 70, 24, 110
    width = cell_w * 3 + gap * 4
    height = head + (cell_h + text_h + gap) * 2 + 60
    out = Image.new("RGB", (width, height), INK)
    draw = ImageDraw.Draw(out)
    title_f = font("LuckiestGuy-Regular.ttf", 64)
    draw.text((gap, 22), label, font=title_f, fill=GOLD)
    title_w = draw.textlength(label, font=title_f)
    draw.text(
        (gap + title_w + 30, 38),
        "the rolled parts as mutations of its own body",
        font=font("LilitaOne-Regular.ttf", 40),
        fill=WHITE,
    )
    name_f = font("LilitaOne-Regular.ttf", 38)
    for i, crop in enumerate(crops):
        x = gap + (i % 3) * (cell_w + gap)
        y = head + (i // 3) * (cell_h + text_h + gap)
        draw.rounded_rectangle((x, y, x + cell_w, y + cell_h), radius=22, fill=backs[i])
        scale = min((cell_w - 40) / crop.width, (cell_h - 30) / crop.height)
        crop = crop.resize((int(crop.width * scale), int(crop.height * scale)), Image.LANCZOS)
        out.paste(crop, (x + (cell_w - crop.width) // 2, y + (cell_h - crop.height) // 2), fade(crop.size))
        part = PARTS[i]
        caption = f"{label} · {part}" if part else f"{label} · AS IT IS"
        centred(draw, x + cell_w // 2, y + cell_h + 14, caption, name_f, MINT if part else GREY)
    draw.text(
        (gap, height - 50),
        "Concept only: each part grows out of the fish's own skin, colours and facets, as if it were born that way.",
        font=font("LilitaOne-Regular.ttf", 28),
        fill=GREY,
    )
    return out


def overview(boards: list[tuple[str, Image.Image]]) -> Image.Image:
    """All six boards, small: 2 across, 3 down, under one title"""
    small_w = 1100
    smalls = [b.resize((small_w, round(b.height * small_w / b.width)), Image.LANCZOS) for _, b in boards]
    gap, head = 30, 120
    width = small_w * 2 + gap * 3
    height = head + (smalls[0].height + gap) * 3 + 20
    out = Image.new("RGB", (width, height), (10, 22, 32))
    draw = ImageDraw.Draw(out)
    title_f = font("LuckiestGuy-Regular.ttf", 72)
    draw.text((gap, 26), "PARTS AS MUTATIONS", font=title_f, fill=GOLD)
    draw.text(
        (gap + draw.textlength("PARTS AS MUTATIONS", font=title_f) + 40, 46),
        "every fish, every part, grown from its own body",
        font=font("LilitaOne-Regular.ttf", 44),
        fill=WHITE,
    )
    for i, small in enumerate(smalls):
        x = gap + (i % 2) * (small_w + gap)
        y = head + (i // 2) * (small.height + gap)
        out.paste(small, (x, y))
    return out


def main():
    args = sys.argv[1:]
    if args and args[0] == "refs":
        for name, _ in FISH:
            for suffix in REF_BOXES:
                print("wrote", reference(name, suffix))
        return
    OUT.mkdir(parents=True, exist_ok=True)
    made = []
    for name, label in FISH:
        missing = [s for s in set(picks(name)) if not (SHEETS / f"{name}{s}.png").exists()]
        if missing:
            print("missing sheet", name, missing)
            continue
        image = board(name, label)
        path = OUT / f"{name}.jpg"
        image.save(path, quality=90)
        print("wrote", path, image.size)
        made.append((name, image))
    if len(made) == len(FISH):
        image = overview(made)
        path = OUT / "AllFish.jpg"
        image.save(path, quality=88)
        print("wrote", path, image.size)


if __name__ == "__main__":
    main()
