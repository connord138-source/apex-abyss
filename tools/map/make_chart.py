"""The sea chart behind the minimap and the full map (owner, 2026-10-14: "needs to be
an actual accurate mini map not dots"): the real seafloor seen from straight above.

The Terrain fill ops the server applies (run_world.sh dumps Shelf.luau and Cave.luau
as world_ops.jsonl) are rasterized at 4-stud cells, later ops over earlier ones as
Roblox does, and each column's top solid surface and its material give the chart:
depth shading from the shallow shelf to the Trench's floor, light from the
north-west so reef heads, ridges, arches, wreck bays, vent basins and the canyon
stand out, contour lines every 40 studs (stronger every 200), lava caps in orange.
North is up (-Z at the top), x and z from -SPAN to +SPAN.

The palette is cool on purpose: blues, teals and slate, no beige or sand tones (an
uploaded image is screened by tools/shades/screen_shades.py first; large tan areas
read as skin).

    DUMP_ONLY=1 LUAU=<luau> bash tools/preview/run_world.sh <dir>
    python tools/map/make_chart.py <dir>/world_ops.jsonl     # writes assets/textures/map_chart.png
"""

from __future__ import annotations

import json
import math
import pathlib
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "textures" / "map_chart.png"
SPAN = 1600  # studs from the middle to the chart's edge (the map's wall is at 1,500)
CELL = 4.0
Y_RANGE = (-960.0, 220.0)
PIXELS = 1024  # Roblox shows images at most 1024 across
MATERIALS = {"Air": 0, "Rock": 1, "Slate": 2, "Sandstone": 3, "Sand": 4, "Basalt": 5, "Mud": 6, "CrackedLava": 7, "Glacier": 8}

# Height (studs) → colour: a nautical chart, shallow pale teal down to deep navy
RAMP = [
    (180.0, (196, 236, 238)),  # the seamount's cap
    (40.0, (150, 214, 218)),
    (0.0, (104, 184, 196)),  # the shelf
    (-60.0, (72, 150, 184)),
    (-200.0, (44, 108, 160)),
    (-430.0, (24, 66, 124)),  # the deep floor
    (-560.0, (16, 46, 96)),  # the vent basins
    (-920.0, (6, 16, 44)),  # the Trench's floor
]
LAVA = np.array((235, 92, 32), dtype=np.float32)


def rasterize_heights(ops: list[dict]) -> tuple[np.ndarray, np.ndarray]:
    xs = np.arange(-SPAN + CELL / 2, SPAN, CELL)
    ys = np.arange(Y_RANGE[0] + CELL / 2, Y_RANGE[1], CELL)
    zs = xs.copy()
    grid = np.zeros((len(xs), len(ys), len(zs)), dtype=np.uint8)
    for op in ops:
        material = MATERIALS[op["material"]]
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
        X, Y, Z = np.meshgrid(xs[i0:i1], ys[j0:j1], zs[k0:k1], indexing="ij", sparse=True)
        if op["kind"] == "ball":
            r = op["radius"]
            mask = (X - cx) ** 2 + (Y - cy) ** 2 + (Z - cz) ** 2 <= r * r
        else:
            right, up, look = (np.array(a, dtype=float) for a in op["axes"])
            dx, dy, dz = X - cx, Y - cy, Z - cz
            lr = dx * right[0] + dy * right[1] + dz * right[2]
            lu = dx * up[0] + dy * up[1] + dz * up[2]
            ll = dx * look[0] + dy * look[1] + dz * look[2]
            if op["kind"] == "block":
                sx, sy, sz = op["size"]
                mask = (np.abs(lr) <= sx / 2) & (np.abs(lu) <= sy / 2) & (np.abs(ll) <= sz / 2)
            else:
                r, h = op["radius"], op["height"]
                mask = (np.abs(lu) <= h / 2) & (lr * lr + ll * ll <= r * r)
        mask = np.broadcast_to(mask, (i1 - i0, j1 - j0, k1 - k0))
        sub = grid[i0:i1, j0:j1, k0:k1]
        sub[mask] = material
    solid = grid > 0
    # The top solid cell of each column (the deepest cell where there's none)
    top = solid.shape[1] - 1 - np.argmax(solid[:, ::-1, :], axis=1)
    has = solid.any(axis=1)
    top = np.where(has, top, 0)
    heights = ys[top]
    material = np.take_along_axis(grid, top[:, None, :], axis=1)[:, 0, :]
    # (x, z) → rows z, columns x
    return heights.T, material.T


def ramp(h: np.ndarray) -> np.ndarray:
    keys = np.array([k for k, _ in RAMP])[::-1]
    cols = np.array([c for _, c in RAMP], dtype=np.float32)[::-1]
    out = np.zeros(h.shape + (3,), dtype=np.float32)
    for c in range(3):
        out[..., c] = np.interp(h, keys, cols[:, c])
    return out


def main() -> None:
    ops = [json.loads(line) for line in open(sys.argv[1])]
    heights, material = rasterize_heights(ops)
    heights = ndimage.gaussian_filter(heights, 0.6)
    # (by height alone: the rock filled under the Trench sits level with the mud
    # round it, and shading it by material drew a box)
    rgb = ramp(heights)
    # Light from the north-west, 40° up
    gz, gx = np.gradient(heights, CELL)
    nx, nz, ny = -gx, -gz, np.ones_like(heights)
    norm = np.sqrt(nx * nx + nz * nz + ny * ny)
    light = np.array([-1.0, 1.1, -1.0])  # x, y, z: from -x (west) and -z (north)
    light /= np.linalg.norm(light)
    shade = (nx * light[0] + ny * light[1] + nz * light[2]) / norm
    shade = np.clip(0.55 + 0.6 * shade, 0.45, 1.15)
    rgb *= shade[..., None]
    # Contours: thin lines every 40 studs, stronger every 200
    for step, strength in ((40.0, 0.12), (200.0, 0.22)):
        band = np.floor(heights / step)
        edge = (band != np.roll(band, 1, 0)) | (band != np.roll(band, 1, 1))
        rgb[edge] *= 1 - strength
    lava = material == MATERIALS["CrackedLava"]
    rgb[lava] = LAVA
    image = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")
    image = image.resize((PIXELS, PIXELS), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUT)
    print(f"wrote {OUT} ({PIXELS}x{PIXELS}, {2 * SPAN} studs across); heights {heights.min():.0f}..{heights.max():.0f}")


if __name__ == "__main__":
    main()
