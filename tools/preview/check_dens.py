"""Checks a den's rock (owner, 2026-10-16: every den is a private interior, its own
block of rock far outside the play area; Layout.denOrigin, DenCarve). run_dens.sh
dumps den 1's Terrain fill ops carved to one level, plus its frame, block, storeys,
rooms and shafts; this voxelizes them on a 2-stud grid (open water all round, as
in game) and fails when:

  * the rooms open out of their block (the cave's air reaches the open water), or
    have less than 6 studs of rock to it anywhere;
  * the rooms aren't one cave (every open storey joined by its shaft);
  * a room isn't open over its deck (just above it, and up to its walls' top);
  * there isn't rock between one storey's floor and the next one's ceiling, away
    from the shafts.

Writes storey_<n>.png (top-down just over each deck), along.png (a slice down the
den's middle) and across.png (a slice across the biggest room, its arch) for a
look. Exit code 1 on a breach.

    LEVEL=5 LUAU=<luau> bash tools/preview/run_dens.sh <dir>
"""

import json
import math
import sys

import numpy as np
from scipy import ndimage

CELL = 2.0
MARGIN = 10.0


def read(path):
    ops, frame, storeys, rooms, shafts = [], None, {}, [], []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("{"):
                ops.append(json.loads(line))
                continue
            word, *rest = line.split()
            if word == "FRAME":
                frame = [float(v) for v in rest]
            elif word == "STOREY":
                n, deck, floor, ceiling, wall = rest
                storeys[int(n)] = dict(deck=float(deck), floor=float(floor), ceiling=float(ceiling), wall=float(wall))
            elif word == "ROOM":
                rid, level, storey, x, z0, z1 = rest
                rooms.append(dict(id=rid, level=int(level), storey=int(storey), x=float(x), z0=float(z0), z1=float(z1)))
            elif word == "SHAFT":
                sid, a, b, z, r = rest
                shafts.append(dict(id=sid, **{"from": int(a)}, to=int(b), z=float(z), radius=float(r)))
    return ops, frame, storeys, rooms, shafts


class Grid:
    """World-space voxels over the den's block (+ a margin of open water)."""

    def __init__(self, frame):
        ox, oy, oz, half, front, back, top, bottom = frame
        self.o = (ox, oy, oz)
        self.block = (half, front, back, top, bottom)
        # den-local z runs opposite world z (Layout: world z = origin z - local z)
        self.x0, self.x1 = ox - half - MARGIN, ox + half + MARGIN
        self.y0, self.y1 = oy + bottom - MARGIN, oy + top + MARGIN
        self.z0, self.z1 = oz - front - MARGIN, oz - back + MARGIN
        self.xs = np.arange(self.x0 + CELL / 2, self.x1, CELL)
        self.ys = np.arange(self.y0 + CELL / 2, self.y1, CELL)
        self.zs = np.arange(self.z0 + CELL / 2, self.z1, CELL)
        self.solid = np.zeros((len(self.xs), len(self.ys), len(self.zs)), bool)

    def index(self, x, y, z):
        """Den-local point to a cell index."""
        ox, oy, oz = self.o
        wx, wy, wz = ox + x, oy + y, oz - z
        return (
            int((wx - self.x0) // CELL),
            int((wy - self.y0) // CELL),
            int((wz - self.z0) // CELL),
        )

    def apply(self, op):
        solid = op["material"] != "Air"
        cx, cy, cz = op["center"]
        if op["kind"] == "ball":
            ext = op["radius"]
        elif op["kind"] == "block":
            ext = math.sqrt(sum(s * s for s in op["size"])) / 2
        else:
            ext = math.sqrt(op["radius"] ** 2 + (op["height"] / 2) ** 2)
        xs, ys, zs = self.xs, self.ys, self.zs
        i0, i1 = np.searchsorted(xs, cx - ext), np.searchsorted(xs, cx + ext, side="right")
        j0, j1 = np.searchsorted(ys, cy - ext), np.searchsorted(ys, cy + ext, side="right")
        k0, k1 = np.searchsorted(zs, cz - ext), np.searchsorted(zs, cz + ext, side="right")
        if i0 >= i1 or j0 >= j1 or k0 >= k1:
            return
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
        self.solid[i0:i1, j0:j1, k0:k1][mask] = solid


def main():
    path, out, level = sys.argv[1], sys.argv[2], int(sys.argv[3])
    ops, frame, storeys, rooms, shafts = read(path)
    grid = Grid(frame)
    for op in ops:
        grid.apply(op)
    problems = []
    air = ~grid.solid
    labels, count = ndimage.label(air)
    # The open water: every label on the grid's edge
    edge = set(np.unique(labels[0])) | set(np.unique(labels[-1])) | set(np.unique(labels[:, 0])) | set(
        np.unique(labels[:, -1])
    ) | set(np.unique(labels[:, :, 0])) | set(np.unique(labels[:, :, -1]))
    edge.discard(0)

    def label_at(x, y, z):
        i, j, k = grid.index(x, y, z)
        return int(labels[i, j, k])

    open_storeys = sorted({r["storey"] for r in rooms})
    nook = label_at(0, storeys[1]["deck"] + 4, -10)
    if nook == 0:
        problems.append("the Nook is solid rock just over its deck")
    elif nook in edge:
        problems.append("the den's rooms open out of its block into the open water")
    else:
        # 6 studs of rock to the open water everywhere
        cave = labels == nook
        water = np.isin(labels, list(edge))
        grown = ndimage.binary_dilation(cave, iterations=3)
        if (grown & water).any():
            problems.append(f"{int((grown & water).sum())} cells of the cave are within 6 studs of the open water")
    # One cave: a point over every open storey's deck in the same air
    for n in open_storeys:
        s = storeys[n]
        room = max((r for r in rooms if r["storey"] == n), key=lambda r: r["x"])
        lab = label_at(0, s["deck"] + 4, (room["z0"] + room["z1"]) / 2)
        if lab != nook:
            problems.append(f"storey {n} isn't joined to the Nook (label {lab} vs {nook})")
    interior = [lab for lab in range(1, count + 1) if lab not in edge]
    big = [lab for lab in interior if (labels == lab).sum() > 30]
    if len(big) > 1:
        problems.append(f"{len(big)} separate pockets of air in the block (should be one cave)")
    # Every room open over its deck and up to its walls' top
    for room in rooms:
        s = storeys[room["storey"]]
        closed = 0
        total = 0
        for x in np.arange(-room["x"] + 3, room["x"] - 2, 4):
            for z in np.arange(room["z1"] + 3, room["z0"] - 2, 4):
                for y in (s["deck"] + 3, s["deck"] + s["wall"] - 3):
                    total += 1
                    i, j, k = grid.index(x, y, z)
                    if grid.solid[i, j, k]:
                        closed += 1
        if closed > total * 0.02:
            problems.append(f"{room['id']}: {closed} of {total} samples over its deck are rock")
    # Rock between storeys, away from the shafts
    for n in open_storeys[1:]:
        above, below = storeys[n - 1], storeys[n]
        y = (above["floor"] + below["ceiling"]) / 2
        holes = 0
        for room in (r for r in rooms if r["storey"] == n):
            for x in np.arange(-room["x"] + 4, room["x"] - 3, 6):
                for z in np.arange(room["z1"] + 4, room["z0"] - 3, 6):
                    if any(abs(z - sh["z"]) < sh["radius"] + 6 and abs(x) < sh["radius"] + 6 for sh in shafts):
                        continue
                    i, j, k = grid.index(x, y, z)
                    if not grid.solid[i, j, k]:
                        holes += 1
        if holes:
            problems.append(f"{holes} holes in the rock between storeys {n - 1} and {n}")

    print(f"level {level}: {len(open_storeys)} storeys, {len(rooms)} rooms, {len(shafts)} shafts, {len(ops)} ops")

    try:
        from PIL import Image

        def save(name, plane):
            img = np.where(plane, 70, 235).astype(np.uint8)
            Image.fromarray(img).convert("RGB").resize((img.shape[1] * 3, img.shape[0] * 3), Image.NEAREST).save(
                f"{out}/{name}.png"
            )

        for n in open_storeys:
            _, j, _ = grid.index(0, storeys[n]["deck"] + 4, 0)
            save(f"storey_{n}", grid.solid[:, j, :].T)
        i, _, _ = grid.index(0, 0, 0)
        save("along", grid.solid[i, ::-1, :].T[:, ::-1].T)
        widest = max(rooms, key=lambda r: r["x"])
        _, _, k = grid.index(0, 0, (widest["z0"] + widest["z1"]) / 2)
        save("across", grid.solid[:, ::-1, k].T)
    except ImportError:
        pass

    if problems:
        for p in problems:
            print("BREACH:", p)
        sys.exit(1)
    print("dens: OK")


if __name__ == "__main__":
    main()
