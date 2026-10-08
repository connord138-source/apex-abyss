"""Finds each fish's eyes on its side face renders (bake_maps.py) and writes the picks
to tools/shades/eyes.json, plus a debug sheet to check them by eye.

    python tools/shades/find_eyes.py assets/shades/maps [debug.jpg]

A fish's eye is a dark pupil inside a light ring (a white or pale iris), on the side
of the head. On each side view the best such blob in the front of the fish is picked
(view, x, y, radius in face pixels); make_shades.py grows each pick onto the body in
3D and keeps those texels as they are (or recolors only the iris). Edit eyes.json by
hand if a pick is wrong; this script only fills in fish it doesn't list yet unless
--force is given.
"""

import json
import pathlib
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

HERE = pathlib.Path(__file__).parent
SIDES = (3, 4)  # bake_maps.py's views: 0 front, 1/2 three-quarter, 3/4 sides


def disk(r):
    y, x = np.mgrid[-r : r + 1, -r : r + 1]
    return (x * x + y * y <= r * r).astype(np.float32)


def best_eye(face):
    rgb = np.clip(face[..., :3], 0, 1) ** (1 / 2.2)
    alpha = face[..., 5] > 0.5
    v = rgb.max(-1) * alpha
    h, w = v.shape
    ys, xs = np.nonzero(alpha)
    if len(xs) == 0:
        return None
    # The head is the end of the silhouette nearer the camera's view centre column;
    # in a side view the fish runs left-right, so take the outer 45% at each end and
    # keep the end whose blob scores best
    best = (0.0, None)
    for r_in in (3, 4, 6, 8, 11, 14):
        r_out = int(r_in * 2.1) + 2
        inner = disk(r_in)
        ring = disk(r_out)
        pad = r_out - r_in
        ring[pad : pad + 2 * r_in + 1, pad : pad + 2 * r_in + 1] -= inner
        ring = np.clip(ring, 0, 1)
        centre = ndimage.convolve(v, inner / inner.sum(), mode="constant")
        around = ndimage.convolve(v, ring / ring.sum(), mode="constant")
        inside = ndimage.minimum_filter(alpha.astype(np.float32), size=2 * r_out + 1) > 0.5
        score = np.clip(around - centre, 0, 1) * around * inside
        score *= centre < 0.35  # a dark pupil
        idx = np.unravel_index(np.argmax(score), score.shape)
        if score[idx] > best[0]:
            best = (float(score[idx]), (int(idx[1]), int(idx[0]), int(r_out)))
    return best[1] if best[0] > 0.05 else None


def main():
    maps = pathlib.Path(sys.argv[1])
    debug = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else None
    force = "--force" in sys.argv
    path = HERE / "eyes.json"
    picks = json.loads(path.read_text()) if path.exists() else {}
    rows = []
    for npz in sorted(maps.glob("*.npz")):
        name = npz.stem
        faces = np.load(npz)["faces"]
        if force or name not in picks:
            found = []
            for view in SIDES:
                eye = best_eye(faces[view])
                if eye:
                    found.append([view, *eye])
            picks[name] = {"picks": found}
            print(name, found)
        tiles = []
        for view in SIDES:
            rgb = np.clip(faces[view][..., :3], 0, 1) ** (1 / 2.2) * 255
            im = Image.fromarray(rgb.astype(np.uint8))
            dr = ImageDraw.Draw(im)
            for v, x, y, r in picks[name]["picks"]:
                if v == view:
                    dr.ellipse([x - r, y - r, x + r, y + r], outline=(255, 0, 255), width=3)
            dr.text((6, 6), f"{name} view {view}", fill=(255, 255, 0))
            tiles.append(im.resize((384, 384)))
        row = Image.new("RGB", (768, 384))
        for i, t in enumerate(tiles):
            row.paste(t, (i * 384, 0))
        rows.append(row)
    path.write_text(json.dumps(picks, indent=1) + "\n")
    if debug and rows:
        sheet = Image.new("RGB", (768, 384 * len(rows)))
        for i, r in enumerate(rows):
            sheet.paste(r, (0, i * 384))
        sheet.save(debug, quality=85)
        print("debug", debug)


if __name__ == "__main__":
    main()
