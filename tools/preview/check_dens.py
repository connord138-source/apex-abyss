"""Checks the dens' rock (owner, 2026-10-13: dens "larger and much more depth"):
every den carved to one level (run_dens.sh dumps the cavern's and the dens' Terrain
fill ops), voxelized on a 2-stud grid over the shelf's rock, then:

  * below the main floor each den's storeys are one cave, inside its own wedge, at
    least 4 studs of rock from any other den's and from the drum's hollow (y < -80);
  * nothing below the main floor comes up to the sand outside the seamount;
  * the Burrow keeps rock between it and the tunnels and the next dens.

Writes slice_<storey>.png (top-down, air light) for a look. Exit code 1 on a breach.

    LEVEL=5 LUAU=<luau> bash tools/preview/run_dens.sh <dir>
"""

import json
import math
import sys

import numpy as np
from scipy import ndimage

CELL = 2.0
SPAN = 240
X0, Y0, Z0 = -SPAN, -118.0, -SPAN
NX, NY, NZ = int(2 * SPAN / CELL), int(160 / CELL), int(2 * SPAN / CELL)
DEN_FLOOR = 4
HUB_RADIUS = 95
SEGMENTS = 24


def axes():
    return (
        X0 + CELL * (np.arange(NX) + 0.5),
        Y0 + CELL * (np.arange(NY) + 0.5),
        Z0 + CELL * (np.arange(NZ) + 0.5),
    )


def fill(ops):
    xs, ys, zs = axes()
    grid = np.zeros((NX, NY, NZ), np.uint8)
    # The shelf: rock and sand from the sand's top (0) down to the drum's hollow (-80)
    grid[:, (ys < 0) & (ys > -80), :] = 1
    for op in ops:
        solid = 0 if op["material"] == "Air" else 1
        cx, cy, cz = op["center"]
        if op["kind"] == "ball":
            ext = op["radius"]
        elif op["kind"] == "block":
            ext = math.sqrt(sum(s * s for s in op["size"])) / 2
        else:
            ext = math.sqrt(op["radius"] ** 2 + (op["height"] / 2) ** 2)
        i0, i1 = np.searchsorted(xs, cx - ext), np.searchsorted(xs, cx + ext, side="right")
        j0, j1 = np.searchsorted(ys, cy - ext), np.searchsorted(ys, cy + ext, side="right")
        k0, k1 = np.searchsorted(zs, cz - ext), np.searchsorted(zs, cz + ext, side="right")
        if i0 >= i1 or j0 >= j1 or k0 >= k1:
            continue
        X, Y, Z = np.meshgrid(xs[i0:i1], ys[j0:j1], zs[k0:k1], indexing="ij")
        dx, dy, dz = X - cx, Y - cy, Z - cz
        if op["kind"] == "ball":
            mask = dx * dx + dy * dy + dz * dz <= op["radius"] ** 2
        else:
            right, up, look = (np.array(a, dtype=float) for a in op["axes"])
            lr = dx * right[0] + dy * right[1] + dz * right[2]
            lu = dx * up[0] + dy * up[1] + dz * up[2]
            ll = dx * look[0] + dy * look[1] + dz * look[2]
            if op["kind"] == "block":
                sx, sy, sz = op["size"]
                mask = (np.abs(lr) <= sx / 2) & (np.abs(lu) <= sy / 2) & (np.abs(ll) <= sz / 2)
            else:
                mask = (np.abs(lu) <= op["height"] / 2) & (lr * lr + ll * ll <= op["radius"] ** 2)
        grid[i0:i1, j0:j1, k0:k1][mask] = solid
    return grid


def den_angles():
    out = []
    for segment in range(1, SEGMENTS + 1):
        k = (segment - 1) % 6
        if k % 2 == 1:
            out.append((segment - 1) * 2 * math.pi / SEGMENTS)
    return out


def tunnel_angles():
    return [(s - 1) * 2 * math.pi / SEGMENTS for s in range(1, SEGMENTS + 1) if (s - 1) % 6 == 0]


def which_den(angle, dens):
    # The rock between two dens is split at the line halfway between their axes,
    # 15 degrees from each (dens are 30 apart; a tunnel's segment sits on the line)
    for index, a in enumerate(dens):
        delta = (angle - a + math.pi) % (2 * math.pi) - math.pi
        if abs(delta) <= math.pi / 12:
            return index
    return -1


def main():
    path, out, level = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(path) as f:
        ops = [json.loads(line) for line in f if line.strip()]
    grid = fill(ops)
    xs, ys, zs = axes()
    X, Z = np.meshgrid(xs, zs, indexing="ij")
    R = np.hypot(X, Z)
    A = np.arctan2(Z, X)
    dens = den_angles()
    tunnels = tunnel_angles()
    problems = []

    # Below the main floor: one cave per den, apart from each other and the hollow
    low = ys < DEN_FLOOR - 10
    hollow = ys < -80
    air = grid == 0
    sub = air[:, low, :].copy()
    labels, count = ndimage.label(sub)
    sizes = ndimage.sum(sub, labels, range(1, count + 1))
    owner = {}
    lowys = ys[low]
    for lab in range(1, count + 1):
        cells = np.argwhere(labels == lab)
        if (lowys[cells[:, 1]] < -80).any():
            if (lowys[cells[:, 1]] >= -80).any():
                problems.append(f"a cave reaches down into the drum's hollow ({int(sizes[lab - 1])} cells)")
            continue
        angles = A[cells[:, 0], cells[:, 2]]
        hit = {which_den(a, dens) for a in angles[:: max(1, len(angles) // 400)]}
        if len(hit) > 1 or -1 in hit:
            problems.append(f"a cave below the main floor spans dens {sorted(hit)} ({int(sizes[lab - 1])} cells)")
        owner[lab] = next(iter(hit))
    caves = [lab for lab in owner]
    print(f"below the main floor: {len(caves)} caves (dens {sorted(owner.values())})")
    # 4 studs apart: grow each den's cave by 1 cell and see whether it meets another
    for lab in caves:
        grown = ndimage.binary_dilation(labels == lab, iterations=1)
        others = (labels > 0) & (labels != lab)
        if (grown & others).any():
            met = set(np.unique(labels[grown & others])) - {0}
            problems.append(f"den {owner[lab] + 1}'s cave is within 4 studs of {sorted(int(m) for m in met)}")

    # Nothing below the main floor up at the sand outside the seamount
    band = (ys > -7) & (ys < 0)
    outside = R > 168
    near = air[:, band, :] & outside[:, None, :]
    if near.any():
        problems.append(f"{int(near.sum())} air cells just under the sand outside the seamount")

    # The main storey: with the cavern and the Nooks taken away, each den's Burrow
    # is its own pocket of air and each tunnel runs out to the sea; none may join, or
    # come within 2 studs of another
    main = (ys > DEN_FLOOR + 1) & (ys < 36)
    # (behind the Nook's back, r 133: the Nooks of the dens beside a tunnel already
    # stand a stud or two from its tube, as the cavern has always been carved)
    ring = (R > 134) & (R < 200)
    pocket = air[:, main, :] & ring[:, None, :]
    mlabels, mcount = ndimage.label(pocket)
    kinds = {}
    for lab in range(1, mcount + 1):
        cells = np.argwhere(mlabels == lab)
        angles = A[cells[:, 0], cells[:, 2]]
        radii = R[cells[:, 0], cells[:, 2]]
        if len(cells) < 40:
            continue
        mid = float(np.arctan2(np.sin(angles).mean(), np.cos(angles).mean()))
        if radii.max() > 185:
            kinds[lab] = "the tunnels and the sea"
        else:
            kinds[lab] = f"den {which_den(mid, dens) + 1}"
    for lab, kind in kinds.items():
        if not kind.startswith("den"):
            continue
        grown = ndimage.binary_dilation(mlabels == lab, iterations=1)
        met = set(np.unique(mlabels[grown & (mlabels > 0) & (mlabels != lab)])) - {0}
        met = {kinds.get(int(m), "a pocket") for m in met}
        if met:
            problems.append(f"{kind}'s main storey is within 2 studs of {sorted(met)}")
    pockets = sum(1 for k in kinds.values() if k.startswith("den"))
    print(f"main storey: {pockets} Burrows on their own")
    if int(level) >= 2 and pockets != len(dens):
        problems.append(f"only {pockets} of {len(dens)} Burrows are sealed off (one opens to a tunnel or the sea)")

    # Slices for a look
    try:
        from PIL import Image, ImageDraw

        for name, y in (("main", DEN_FLOOR + 3), ("hall", -27), ("sanctum", -59)):
            j = int((y - Y0) / CELL)
            img = np.where(grid[:, j, :] == 0, 235, 70).astype(np.uint8).T
            im = Image.fromarray(img).convert("RGB").resize((NX * 3, NZ * 3), Image.NEAREST)
            draw = ImageDraw.Draw(im)
            for a in dens + tunnels:
                c = (NX * 1.5, NZ * 1.5)
                draw.line([c, (c[0] + math.cos(a) * 700, c[1] + math.sin(a) * 700)], fill=(255, 120, 60) if a in tunnels else (90, 170, 230), width=1)
            im.save(f"{out}/slice_{name}.png")
    except ImportError:
        pass

    if problems:
        for p in problems:
            print("BREACH:", p)
        sys.exit(1)
    print(f"dens at level {level}: OK")


if __name__ == "__main__":
    main()
