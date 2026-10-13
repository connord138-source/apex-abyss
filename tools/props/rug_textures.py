"""Top-down rug textures for the den's rugs, cut off the approved furniture boards
(assets/concepts/Furn*.jpg, seen from three-quarters above): a round rug's ellipse is
stretched back into a circle, an oval's by the same squash, and the square mosaic's
four corners are pulled square. The background goes transparent, so a rug draws as
a Decal on a flat part (Shared/DenItems). Skin-tone texels (the mosaic's pale gold)
are moved out as tools/props/safe_colors.py does for props. Screen them before
they're uploaded.

    python tools/props/rug_textures.py            # writes assets/textures/rug_<Id>.png
"""

from __future__ import annotations

import pathlib

import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "props"))
from safe_colors import recolor  # noqa: E402  (skin-tone texels moved out, as for the props)
SIZE = 512
# board, box (x0, y0, x1, y1), shape; the camera squashes depth to ~0.57 of width
RUGS = {
    "BraidedKelpRug": ("FurnKelpCottage", (653, 775, 980, 962), "round"),
    "CoralRug": ("FurnReefPalace", (685, 727, 999, 891), "oval"),
    "WaveMosaicRug": ("FurnSunkenTemple", (602, 662, 994, 873), "square"),
    "PlanktonRug": ("FurnAbyssGlow", (366, 699, 716, 887), "round"),
}
SQUASH = 0.57


def piece_mask(im: np.ndarray, box: tuple[int, int, int, int]) -> np.ndarray:
    h, w, _ = im.shape
    border = np.concatenate([im[:8].reshape(-1, 3), im[-8:].reshape(-1, 3), im[:, :8].reshape(-1, 3), im[:, -8:].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    mask = np.sqrt(((im - bg) ** 2).sum(axis=2)) > 38
    mask = ndimage.binary_closing(mask, iterations=4)
    mask = ndimage.binary_fill_holes(mask)
    x0, y0, x1, y1 = box
    keep = np.zeros_like(mask)
    keep[y0:y1, x0:x1] = mask[y0:y1, x0:x1]
    lab, _ = ndimage.label(keep)
    sizes = ndimage.sum(keep, lab, range(1, lab.max() + 1))
    return lab == (int(np.argmax(sizes)) + 1)


def homography(src: np.ndarray, dst: np.ndarray) -> np.ndarray:
    rows = []
    for (x, y), (u, v) in zip(src, dst):
        rows.append([x, y, 1, 0, 0, 0, -u * x, -u * y, -u])
        rows.append([0, 0, 0, x, y, 1, -v * x, -v * y, -v])
    _, _, vt = np.linalg.svd(np.array(rows, dtype=np.float64))
    return vt[-1].reshape(3, 3) / vt[-1][-1]


def main() -> None:
    out = ROOT / "assets" / "textures"
    out.mkdir(parents=True, exist_ok=True)
    for rug, (board, box, shape) in RUGS.items():
        image = Image.open(ROOT / "assets" / "concepts" / f"{board}.jpg").convert("RGB")
        im = np.asarray(image).astype(np.float32)
        mask = piece_mask(im, box)
        ys, xs = np.nonzero(mask)
        if shape == "square":
            # The four corners: extremes along the diagonals
            pts = np.stack([xs, ys], 1).astype(np.float64)
            corners = [pts[np.argmin(pts[:, 1])], pts[np.argmax(pts[:, 0])], pts[np.argmax(pts[:, 1])], pts[np.argmin(pts[:, 0])]]
            dst = np.array([[0, 0], [SIZE, 0], [SIZE, SIZE], [0, SIZE]], dtype=np.float64)
            H = np.linalg.inv(homography(np.array(corners), dst))
            gy, gx = np.mgrid[0:SIZE, 0:SIZE] + 0.5
            p = H @ np.stack([gx.ravel(), gy.ravel(), np.ones(gx.size)])
            sx, sy = p[0] / p[2], p[1] / p[2]
            alpha = np.ones(SIZE * SIZE)
            width, height = SIZE, SIZE
        else:
            cx, cy = xs.mean(), ys.mean()
            rx = (xs.max() - xs.min()) / 2
            ry = (ys.max() - ys.min()) / 2
            true_ry = ry / SQUASH  # the rug's depth before the camera's squash
            aspect = true_ry / rx
            width, height = SIZE, int(round(SIZE * min(aspect, 1.0)))
            if aspect > 1:
                width = int(round(SIZE / aspect))
            gy, gx = np.mgrid[0:height, 0:width] + 0.5
            u = (gx.ravel() / width) * 2 - 1
            v = (gy.ravel() / height) * 2 - 1
            sx = cx + u * rx
            sy = cy + v * ry
            r = np.sqrt(u * u + v * v)
            alpha = np.clip((1.0 - r) * 40, 0, 1)
        sxi = np.clip(sx, 0, im.shape[1] - 1)
        syi = np.clip(sy, 0, im.shape[0] - 1)
        rgb = np.stack([ndimage.map_coordinates(im[..., c], [syi, sxi], order=1) for c in range(3)], 1)
        safe, _ = recolor(rgb.reshape(height, width, 3).clip(0, 255).astype(np.uint8))
        rgba = np.concatenate([np.asarray(safe, dtype=np.float32).reshape(-1, 3), alpha[:, None] * 255], 1).reshape(height, width, 4)
        Image.fromarray(rgba.clip(0, 255).astype(np.uint8), "RGBA").save(out / f"rug_{rug}.png")
        print(rug, shape, f"{width}x{height}")


if __name__ == "__main__":
    main()
