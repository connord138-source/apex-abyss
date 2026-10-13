"""Finds the six pieces on each furniture board (assets/concepts/Furn*.jpg): pixels
far from the board's flat background, closed and filled, as connected components.
Writes their boxes to tools/props/furniture_boxes.json for furniture_crops.py.

    python tools/props/furniture_segment.py assets/concepts/Furn{KelpCottage,ReefPalace,Shipwreck,SunkenTemple,VentForge,AbyssGlow,Trophies}.jpg
"""
import json
import os
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

boards = sys.argv[1:]
out = {}
for path in boards:
    im = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    h, w, _ = im.shape
    # Background: the median of the border
    border = np.concatenate([im[:8].reshape(-1, 3), im[-8:].reshape(-1, 3), im[:, :8].reshape(-1, 3), im[:, -8:].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    d = np.sqrt(((im - bg) ** 2).sum(axis=2))
    mask = d > 38
    mask = ndimage.binary_closing(mask, iterations=6)
    mask = ndimage.binary_fill_holes(mask)
    mask = ndimage.binary_opening(mask, iterations=2)
    lab, n = ndimage.label(mask)
    boxes = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        area = (lab[sl] == i + 1).sum()
        if area < 3000:
            continue
        ys, xs = sl
        boxes.append({"x0": xs.start, "y0": ys.start, "x1": xs.stop, "y1": ys.stop, "area": int(area), "label": i + 1})
    boxes.sort(key=lambda b: (round((b["y0"] + b["y1"]) / 2 / 340), (b["x0"] + b["x1"]) / 2))
    out[path] = {"bg": bg.tolist(), "boxes": boxes}
    print(path, [ (b["x0"], b["y0"], b["x1"], b["y1"], b["area"]) for b in boxes])
json.dump(out, open(os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "furniture_boxes.json"), "w"), indent=1)
