#!/usr/bin/env python3
"""Toon colour maps for the base-material overrides (owner, 2026-10-16: "Walls need to
look more like schedule 1 or how to fish graphics. Looks too much like garrymod textures
or semi realistic for our purposes"). Each is a 1024x1024 PNG that tiles both ways, used
as the ColorMap of a MaterialVariant that overrides a stock material game-wide
(MaterialService base-material overrides reach Terrain and parts alike).

  python3.11 tools/textures/make_toon_materials.py               # writes every assets/textures/toon_*.png
  python3.11 tools/textures/make_toon_materials.py Rock Sand     # only those

The look is cel-shaded: big flat value regions, two or three posterized steps of
slightly lighter and darker blobs with soft edges, bold simple dark seams or cracks
with a thin light rim on their lit side (light from the top-left of the tile), and
almost no fine grain. Features are big: one tile covers roughly 8-16 studs
(StudsPerTile), so a rock plate is about a quarter of the tile.

Every map but CrackedLava is neutral grey (R = G = B), mean ~175-200, because Roblox
multiplies it by the Terrain MaterialColors / part Color, which give the hue; grey
also leaves the moderation screen nothing to read as skin. CrackedLava carries its
own colour (saturated yellow-to-red cracks on a near-black crust, no tan, peach or
beige; its blues are kept low wherever red is high, so no blend reads as skin), so
its MaterialColor should be white. Colour maps only: no normal or roughness maps
(never upload a normal map, CLAUDE.md). Screen before upload:
python3.11 tools/shades/screen_shades.py assets/textures/toon_*.png

Every field tiles: value noise on a lattice that wraps, Worley cells on a torus
(cKDTree boxsize), blurs and offsets in wrap mode, lines at wrapped distances.
"""

from __future__ import annotations

import argparse
import pathlib
import sys

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import cKDTree

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent.parent / "assets" / "textures"
SIZE = 1024
F = np.float32

# Each map's mean value (0-255) after composing, and the ceiling (no pure white areas).
# Roblox multiplies the map by the part's or terrain's colour, so a map with mean 0.8
# darkens what wears it by a fifth; the terrain's colours are lifted to match when the
# toon materials are on (WorldService), and parts keep a little extra depth.
TARGET = {
    "Rock": 190,  # (204 scored 0.144 on the classifier, 182 scored 0.085)
    "Slate": 202,
    "Basalt": 198,
    "Sandstone": 208,
    "Sand": 210,
    "Mud": 200,
    "Pebble": 200,
    "Marble": 212,
    "WoodPlanks": 202,
    "Wood": 204,
}
CEILING = 246
FLOOR = 72


# --- Tiling building blocks ------------------------------------------------------------


def grid():
    v, u = np.mgrid[0:SIZE, 0:SIZE].astype(F) / SIZE
    return u, v


U, V = grid()


def wrap01(x):
    x = np.mod(x, 1.0)
    return np.where(x >= 1.0, 0.0, x)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def blur(x, sigma):
    return ndimage.gaussian_filter(np.asarray(x, F), sigma, mode="wrap")


def shift(x, dy, dx):
    """Moves an image down by dy and right by dx pixels, wrapping."""
    return np.roll(np.roll(x, dy, 0), dx, 1)


def pnoise(fx: int, fy: int, seed: int, u=None, v=None):
    """Value noise on an fx x fy lattice that wraps, so it tiles (0..1)."""
    u = U if u is None else u
    v = V if v is None else v
    rng = np.random.default_rng(seed)
    lattice = rng.random((fy, fx)).astype(F)
    x, y = wrap01(u) * fx, wrap01(v) * fy
    i0, j0 = np.floor(x).astype(int), np.floor(y).astype(int)
    tx, ty = x - i0, y - j0
    tx = tx * tx * tx * (tx * (tx * 6 - 15) + 10)
    ty = ty * ty * ty * (ty * (ty * 6 - 15) + 10)
    i0, j0 = i0 % fx, j0 % fy
    i1, j1 = (i0 + 1) % fx, (j0 + 1) % fy
    a = lattice[j0, i0] * (1 - tx) + lattice[j0, i1] * tx
    b = lattice[j1, i0] * (1 - tx) + lattice[j1, i1] * tx
    return (a * (1 - ty) + b * ty).astype(F)


def fbm(fx: int, fy: int, seed: int, octaves=3, u=None, v=None):
    out, amp, total = 0.0, 1.0, 0.0
    for o in range(octaves):
        out = out + amp * pnoise(fx * 2**o, fy * 2**o, seed + 7 * o, u, v)
        total += amp
        amp *= 0.5
    return (out / total).astype(F)


def perlin(fx: int, fy: int, seed: int, u=None, v=None):
    """Gradient noise on an fx x fy lattice that wraps (about -0.7..0.7). Rounder than
    value noise: posterized value noise shows its square lattice as boxy blotches."""
    u = U if u is None else u
    v = V if v is None else v
    rng = np.random.default_rng(seed)
    ang = rng.random((fy, fx)) * 2 * np.pi
    gx, gy = np.cos(ang).astype(F), np.sin(ang).astype(F)
    x, y = wrap01(u) * fx, wrap01(v) * fy
    i0, j0 = np.floor(x).astype(int), np.floor(y).astype(int)
    tx, ty = (x - i0).astype(F), (y - j0).astype(F)
    i0, j0 = i0 % fx, j0 % fy
    i1, j1 = (i0 + 1) % fx, (j0 + 1) % fy

    def corner(i, j, ox, oy):
        return gx[j, i] * (tx - ox) + gy[j, i] * (ty - oy)

    sx = tx * tx * tx * (tx * (tx * 6 - 15) + 10)
    sy = ty * ty * ty * (ty * (ty * 6 - 15) + 10)
    a = lerp(corner(i0, j0, 0, 0), corner(i1, j0, 1, 0), sx)
    b = lerp(corner(i0, j1, 0, 1), corner(i1, j1, 1, 1), sx)
    return lerp(a, b, sy).astype(F)


def pfbm(fx: int, fy: int, seed: int, octaves=3, u=None, v=None, gain=0.5):
    out, amp = 0.0, 1.0
    for o in range(octaves):
        out = out + amp * perlin(fx * 2**o, fy * 2**o, seed + 7 * o, u, v)
        amp *= gain
    return np.asarray(out, F)


def rank(field):
    """Rank-normalizes a field to 0..1, so a threshold of t leaves the fraction t below it."""
    flat = field.ravel()
    out = np.empty(flat.size, F)
    out[np.argsort(flat, kind="stable")] = np.linspace(0, 1, flat.size, dtype=F)
    return out.reshape(field.shape)


def blobs(freq: int, seed: int, octaves=2, amp=0.04, fy: int | None = None):
    """Big organic blobs: warped gradient noise, rank-normalized (thresholds = areas)."""
    wu, wv = warp(amp, max(2, freq), seed + 900)
    return rank(pfbm(freq, fy or freq, seed, octaves, wu, wv))


def contour_dist(f):
    """Pixel distance to a smooth field's zero level (|f| over its gradient)."""
    gx = (np.roll(f, -1, 1) - np.roll(f, 1, 1)) * 0.5
    gy = (np.roll(f, -1, 0) - np.roll(f, 1, 0)) * 0.5
    return (np.abs(f) / np.maximum(np.hypot(gx, gy), 1e-6)).astype(F)


def warp(amp: float, freq: int, seed: int, u=None, v=None):
    """The tile's coordinates pushed about by tiling noise (amp in tile units)."""
    u = U if u is None else u
    v = V if v is None else v
    du = (fbm(freq, freq, seed, 2) - 0.5) * 2 * amp
    dv = (fbm(freq, freq, seed + 50, 2) - 0.5) * 2 * amp
    return u + du, v + dv


def jgrid(nx: int, ny: int, jitter: float, rng, hex_rows=False):
    """Jittered grid sites in the unit torus (hex_rows offsets every other row)."""
    pts = []
    for j in range(ny):
        for i in range(nx):
            x = (i + 0.5 + (0.5 if hex_rows and j % 2 else 0.0)) / nx
            y = (j + 0.5) / ny
            pts.append((x + rng.uniform(-jitter, jitter) * 0.5 / nx, y + rng.uniform(-jitter, jitter) * 0.5 / ny))
    return np.mod(np.array(pts, np.float64), 1.0)


def worley(sites, u, v):
    """(distance to own site, distance to the cell's border, cell index), on the torus.
    Distances are in pixels."""
    tree = cKDTree(sites, boxsize=1.0)
    pts = np.stack([wrap01(u).ravel(), wrap01(v).ravel()], -1).astype(np.float64)
    pts = np.minimum(pts, np.nextafter(1.0, 0.0))
    d, i = tree.query(pts, k=2, workers=-1)
    delta = sites[i[:, 1]] - sites[i[:, 0]]
    delta -= np.round(delta)
    sep = np.maximum(np.hypot(delta[:, 0], delta[:, 1]), 1e-6)
    edge = (d[:, 1] ** 2 - d[:, 0] ** 2) / (2 * sep)
    shape = u.shape
    return (d[:, 0] * SIZE).reshape(shape).astype(F), (edge * SIZE).reshape(shape).astype(F), i[:, 0].reshape(shape)


def nearest(centers, u=None, v=None):
    """(wrapped dx, dy in pixels to the nearest centre, its index)."""
    u = U if u is None else u
    v = V if v is None else v
    tree = cKDTree(np.mod(centers, 1.0), boxsize=1.0)
    pts = np.minimum(np.stack([wrap01(u).ravel(), wrap01(v).ravel()], -1).astype(np.float64), np.nextafter(1.0, 0.0))
    _, idx = tree.query(pts, k=1, workers=-1)
    c = centers[idx]
    dx = pts[:, 0] - c[:, 0]
    dy = pts[:, 1] - c[:, 1]
    dx -= np.round(dx)
    dy -= np.round(dy)
    shape = u.shape
    return (dx * SIZE).reshape(shape).astype(F), (dy * SIZE).reshape(shape).astype(F), idx.reshape(shape)


def line(dist_px, half_width):
    """An antialiased stroke: 1 within half_width pixels of a distance field's zero."""
    return (1.0 - smoothstep(half_width - 0.75, half_width + 0.75, dist_px)).astype(F)


def steps(field, thresholds, values, sigma):
    """Posterizes a field into flat steps (values has one more entry than thresholds),
    then softens the steps' edges by sigma pixels."""
    out = np.full(field.shape, values[0], F)
    for t, a, b in zip(thresholds, values[:-1], values[1:]):
        out += (b - a) * (field > t)
    return blur(out, sigma) if sigma > 0 else out


def bevel(raised, sigma: float, hi: float, lo: float, cut=0.3):
    """Toon edge light on raised regions (1 = raised): a flat light rim on edges facing
    the top-left light, a flat dark one on edges facing away. Returns a value delta."""
    h = blur(raised, sigma)
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    lit = (gx + gy) / np.sqrt(2) * np.sqrt(2 * np.pi) * sigma  # ~ -1..1 across an edge
    up = smoothstep(cut - 0.08, cut + 0.08, lit)
    down = smoothstep(cut - 0.08, cut + 0.08, -lit)
    return (hi * up - lo * down).astype(F)


def groove_light(stroke, d=3, amount=14.0):
    """A thin light line on the lit (bottom-right) wall of a dark groove."""
    return (shift(stroke, d, d) * (1.0 - stroke) * amount).astype(F)


def flecks(n: int, seed: int, dark=-30.0, light=14.0, rmin=2.2, rmax=4.5, dark_share=0.6):
    """A sprinkle of small round flecks, mostly darker, some lighter (a value delta).
    Besides the look, they keep big smooth grey areas from reading as skin to the
    moderation classifier (Rock and Slate scored 0.42 without them, under 0.1 with)."""
    rng = np.random.default_rng(seed)
    centers = rng.random((n, 2))
    radii = rng.uniform(rmin, rmax, n)
    dx, dy, idx = nearest(centers)
    dot = 1.0 - smoothstep(radii[idx] - 0.8, radii[idx] + 0.8, np.hypot(dx, dy))
    is_dark = rng.random(n) < dark_share
    return (np.where(is_dark[idx], dark, light).astype(F) * dot).astype(F)


def ellipse_field(centers, radii, angle=None):
    """Normalized ellipse radius (1 on the rim) round the nearest centre, and its index."""
    dx, dy, idx = nearest(centers)
    rx, ry = radii[idx, 0], radii[idx, 1]
    if angle is not None:
        a = angle[idx]
        dx, dy = dx * np.cos(a) + dy * np.sin(a), -dx * np.sin(a) + dy * np.cos(a)
    return np.sqrt((dx / rx) ** 2 + (dy / ry) ** 2).astype(F), idx, dx, dy


# --- Materials -------------------------------------------------------------------------


def tapered_cracks(nx: int, seed: int, rng, share: float, width: float, clear_of=None, clear_px=30.0):
    """Occasional bold crack strokes: the borders of a coarse warped Worley pattern, kept
    only inside a share of blob area and tapering to nothing at their ends."""
    wu, wv = warp(0.025, 4, seed)
    _, e, _ = worley(jgrid(nx, nx, 0.9, rng), wu, wv)
    k = smoothstep(1 - share, 1 - share + 0.1, blobs(2, seed + 1))
    if clear_of is not None:
        k = k * smoothstep(clear_px * 0.6, clear_px, clear_of)
    return (line(e, width * k) * smoothstep(0.0, 0.35, k)).astype(F)


def rock():
    """Chunky plates: ~16 boulder faces with bold dark joints, a light rim on their lit
    edges, a few big soft lighter/darker blobs and the odd tapering crack."""
    rng = np.random.default_rng(11)
    wu, wv = warp(0.035, 3, 101)
    sites = jgrid(4, 4, 0.85, rng)
    _, e, cell = worley(sites, wu, wv)
    w = 3.0 + 3.8 * pnoise(6, 6, 102)
    joint = line(e, w)
    tones = rng.choice(np.array([-15, -5, 5, 13], F), len(sites))
    val = 184 + tones[cell]
    val += steps(blobs(3, 103), [0.22, 0.78], [-9, 0, 7], 4)
    val += bevel((e > w).astype(F), 5, 22, 14)
    val += flecks(120, 106)
    crack = tapered_cracks(5, 104, rng, 0.28, 3.0, e)
    val += groove_light(crack, 3, 16)
    val = lerp(val, 104, crack)
    return lerp(val, 100, joint)


def slate():
    """Broad layered bands of three tones, each split by a dark seam with a light lip
    under it, the odd vertical joint, and faint long streaks."""
    rng = np.random.default_rng(21)
    n = 5
    gaps = 0.12 + (1 - 0.12 * n) * rng.dirichlet(np.full(n, 3.0))
    bounds = np.sort(np.mod(np.cumsum(gaps) + rng.random(), 1.0))
    y = wrap01(V + perlin(2, 1, 201) * 0.06 + perlin(5, 2, 202) * 0.012)
    band = np.searchsorted(bounds, y) % n
    dist = np.full(y.shape, 1e9, F)
    for b in bounds:
        dd = y - b
        dist = np.minimum(dist, np.abs(dd - np.round(dd)) * SIZE)
    w = 2.6 + 1.8 * pnoise(7, 3, 203)
    seam = line(dist, w)
    tones = np.array([-13, 9, -3, 12, -8], F)[:n]
    val = 182 + tones[band]
    val += steps(blobs(2, 204, 2, 0.03, fy=12), [0.25, 0.8], [-6, 0, 5], 2.5)
    val += steps(blobs(3, 205), [0.8], [0, -7], 4)
    val += bevel((dist > w).astype(F), 4, 18, 12)
    val += flecks(120, 206)
    joint = np.zeros_like(val)
    for k in range(n):
        lo = bounds[k]
        for _ in range(rng.integers(1, 3)):
            x0, lean = rng.random(), rng.uniform(-0.12, 0.12)
            dx = U - x0 - lean * (y - lo)
            dpx = np.abs(dx - np.round(dx)) * SIZE
            joint = np.maximum(joint, line(dpx, 1.9) * (band == ((k + 1) % n)))
    val += groove_light(joint, 3, 13)
    val = lerp(val, 108, joint)
    return lerp(val, 98, seam)


def basalt():
    """Big hexagonal column tops (5 x 6 per tile), each one flat tone with a bevelled
    rim, dark joints between them and the occasional crack across a top."""
    rng = np.random.default_rng(31)
    sites = jgrid(5, 6, 0.22, rng, hex_rows=True)
    wu, wv = warp(0.01, 4, 301)
    _, e, cell = worley(sites, wu, wv)
    w = 3.6 + 1.8 * pnoise(8, 8, 302)
    joint = line(e, w)
    tones = rng.choice(np.array([-13, -5, 4, 11], F), len(sites))
    val = 180 + tones[cell]
    val += steps(blobs(3, 303), [0.8], [0, -8], 4)
    val += bevel((e > w).astype(F), 6, 22, 15)
    val += flecks(110, 306)
    crack = tapered_cracks(6, 304, rng, 0.14, 2.4, e, 24)
    val += groove_light(crack, 3, 14)
    val = lerp(val, 106, crack)
    return lerp(val, 94, joint)


def sandstone():
    """Soft horizontal strata in three tones, a few seams with a light lip, and rounded
    erosion pits lit on their lower rim."""
    rng = np.random.default_rng(41)
    n = 8
    gaps = 0.06 + (1 - 0.06 * n) * rng.dirichlet(np.full(n, 3.0))
    bounds = np.sort(np.mod(np.cumsum(gaps) + rng.random(), 1.0))
    y = wrap01(V + perlin(2, 1, 401) * 0.05 + perlin(4, 2, 402) * 0.02 + perlin(9, 3, 406) * 0.004)
    band = np.searchsorted(bounds, y) % n
    tones = np.array([0, -12, 7, -4, 10, -9, 3, -6], F)[:n]
    val = 188 + blur(tones[band], 2.5)
    val += steps(blobs(2, 403, fy=5), [0.2, 0.8], [-6, 0, 5], 4)
    seam = np.zeros_like(val)
    for i, b in enumerate(bounds):
        dd = y - b
        dpx = np.abs(dd - np.round(dd)) * SIZE
        k = smoothstep(0.3, 0.5, blobs(2, 404 + i, fy=3))
        seam = np.maximum(seam, line(dpx, 2.6 * k) * smoothstep(0, 0.3, k))
    val += (shift(seam, 3, 0) * (1 - seam) * 15).astype(F)
    val = lerp(val, 122, seam)
    centers = rng.random((7, 2))
    radii = np.stack([rng.uniform(30, 56, 7), rng.uniform(15, 26, 7)], -1)
    r, _, _, _ = ellipse_field(centers, radii)
    pit = 1.0 - smoothstep(0.92, 1.08, r)
    val += -14 * pit
    val += bevel(1.0 - pit, 4, 16, 10)
    return val + flecks(90, 405, -24, 12)


def sand():
    """Gentle ripple bands (a lit crest and a dark lee line that comes and goes), broad
    soft blotches and a sprinkle of speckles."""
    rng = np.random.default_rng(51)
    phase = 6 * V + U + pfbm(2, 2, 501, 2) * 0.9
    s = np.mod(phase, 1.0)
    crest = smoothstep(0.03, 0.07, s) * (1 - smoothstep(0.36, 0.40, s))
    lee = smoothstep(0.84, 0.86, s) * (1 - smoothstep(0.915, 0.935, s))
    fade = smoothstep(0.25, 0.45, blobs(3, 502, 2))
    val = 192 + 9 * crest - 19 * lee * fade
    val += steps(blobs(2, 503), [0.25, 0.75], [-7, 0, 6], 6)
    n = 110
    centers = rng.random((n, 2))
    radii = rng.uniform(2.4, 4.8, n)
    dx, dy, idx = nearest(centers)
    dot = 1.0 - smoothstep(radii[idx] - 0.8, radii[idx] + 0.8, np.hypot(dx, dy))
    dark = rng.random(n) < 0.55
    val += np.where(dark[idx], -34, 18).astype(F) * dot
    return val


def mud():
    """Soft blotches in three flat tones, a few shallow puddle dips lit on the lower rim
    and a handful of small round stones."""
    rng = np.random.default_rng(61)
    val = 178 + steps(blobs(2, 601, 2, 0.05), [0.3, 0.72], [-15, 0, 9], 8)
    val += steps(blobs(5, 602), [0.84], [0, -8], 4)
    centers = rng.random((5, 2))
    radii = np.stack([rng.uniform(40, 64, 5), rng.uniform(26, 40, 5)], -1)
    r, _, _, _ = ellipse_field(centers, radii, rng.uniform(0, np.pi, 5))
    dip = 1.0 - smoothstep(0.88, 1.12, r)
    val += -14 * dip + bevel(1.0 - dip, 6, 13, 9)
    stones = rng.random((20, 2))
    sr = np.stack([rng.uniform(4.5, 9, 20), rng.uniform(4, 7, 20)], -1)
    r2, _, _, _ = ellipse_field(stones, sr, rng.uniform(0, np.pi, 20))
    stone = 1.0 - smoothstep(0.85, 1.15, r2)
    val += 12 * stone + bevel(stone, 2.5, 12, 14)
    return val


def pebble():
    """Rounded stones (6 x 6 per tile) in four tones, each outlined dark in a darker grout
    and lit on its upper-left rim."""
    rng = np.random.default_rng(71)
    sites = jgrid(6, 6, 0.8, rng)
    wu, wv = warp(0.02, 4, 701)
    _, e, cell = worley(sites, wu, wv)
    stone = (blur((e > 8.0).astype(F), 13) > 0.62).astype(F)
    stone = blur(stone, 0.9)
    tones = rng.choice(np.array([-16, -6, 4, 12], F), len(sites))
    val = 186 + tones[cell]
    val += steps(blobs(4, 702, 2), [0.8], [0, -7], 3)
    val += bevel(stone, 6, 22, 15)
    val = lerp(np.full_like(val, 122), val, stone)
    hard = stone > 0.5
    rim = hard & ~(ndimage.minimum_filter(hard.astype(np.uint8), size=5, mode="wrap") > 0)
    outline = blur(rim.astype(F), 0.8)
    return lerp(val, 92, np.clip(outline * 1.6, 0, 1))


def marble():
    """Pale soft clouds crossed by long meandering diagonal veins that swell, thin and
    fade out, and a fainter family of branch veins at another angle."""
    val = 202 + steps(blobs(2, 801, 3, 0.08), [0.3, 0.62], [-10, -4, 0], 10)
    au, av = warp(0.04, 3, 802)
    f = np.sin(2 * np.pi * (U + V + pfbm(2, 2, 803, 3, au, av, gain=0.45) * 0.3))
    d = contour_dist(f)
    k = smoothstep(0.2, 0.45, blobs(2, 804))
    w = (1.3 + 3.0 * pnoise(5, 5, 805)) * k
    main = blur(line(d, w) * smoothstep(0, 0.3, k), 1.2)
    halo = blur(line(d, 11 * k), 5)
    bu, bv = warp(0.05, 3, 806)
    f2 = np.sin(2 * np.pi * (2 * U - V + pfbm(3, 3, 807, 2, bu, bv) * 0.3))
    k2 = smoothstep(0.6, 0.78, blobs(3, 808))
    branch = blur(line(contour_dist(f2), 1.1 * k2) * smoothstep(0, 0.3, k2), 0.9)
    val -= 6 * halo
    val += flecks(90, 809, -20, 6, 1.8, 3.6, 0.75)
    val = lerp(val, 174, branch)
    return lerp(val, 146, main)


def wood_planks():
    """Eight rows of planks, two per row with staggered ends, dark seams, a light lip
    on each plank's top-left edge, a few grain lines, the odd knot and two nails at
    every end."""
    rng = np.random.default_rng(91)
    rows = 8
    row = np.minimum((V * rows).astype(int), rows - 1)
    vl = V * rows - row
    rowpx = SIZE / rows
    j1 = rng.random(rows)
    j2 = np.mod(j1 + 0.5 + rng.uniform(-0.14, 0.14, rows), 1.0)
    x = np.mod(U - j1[row], 1.0)
    seg = (x >= np.mod(j2 - j1, 1.0)[row]).astype(int)
    plank = row * 2 + seg
    dh = np.minimum(vl, 1 - vl) * rowpx
    dv = np.full(U.shape, 1e9, F)
    for j in (j1, j2):
        dd = U - j[row]
        dv = np.minimum(dv, np.abs(dd - np.round(dd)) * SIZE)
    seam = np.maximum(line(dh, 2.8), line(dv, 2.4))
    tones = rng.choice(np.array([-14, -6, 2, 10], F), rows * 2)
    val = 182 + tones[plank]
    val += steps(blobs(3, 901, 2, 0.03, fy=12), [0.25, 0.8], [-6, 0, 4], 2.5)
    # Grain: three wavy lines a plank, swirling round a knot where there is one
    phase = rng.random(rows * 2)
    has_knot = rng.random(rows * 2) < 0.35
    ku = np.array(
        [np.mod((j1 if s == 0 else j2)[r] + rng.uniform(0.12, 0.38), 1.0) for r in range(rows) for s in (0, 1)]
    )
    kv = (np.arange(rows * 2) // 2 + 0.5 + rng.uniform(-0.1, 0.1, rows * 2)) / rows
    dxk = U - ku[plank]
    dxk = (dxk - np.round(dxk)) * SIZE
    dyk = (V - kv[plank]) * SIZE
    rk = np.sqrt((dxk / 13) ** 2 + (dyk / 6.5) ** 2)
    knot_on = has_knot[plank]
    bump = np.where(knot_on, 1.6 * np.exp(-((rk / 3.0) ** 2)), 0.0)
    g = 2.5 * vl + phase[plank] + perlin(4, 6, 902) * 0.4 + bump
    gd = contour_dist(np.sin(np.pi * g)) * 1.0
    grain = line(gd, 1.4) * (0.6 + 0.4 * smoothstep(0.3, 0.6, pnoise(6, 12, 903)))
    val -= 24 * grain
    core = np.where(knot_on, 1.0 - smoothstep(0.85, 1.15, rk), 0.0)
    val = lerp(val, 128, core)
    val += bevel(1.0 - seam, 4, 16, 13)
    nails = []
    for r in range(rows):
        for j in (j1[r], j2[r]):
            for side in (-1, 1):
                for t in (0.28, 0.72):
                    nails.append((j + side * 15 / SIZE, (r + t) / rows))
    dx, dy, _ = nearest(np.array(nails))
    head = 1.0 - smoothstep(3.4, 4.8, np.hypot(dx, dy))
    glint = 1.0 - smoothstep(1.0, 2.0, np.hypot(dx + 1.5, dy + 1.5))
    val = lerp(val, 96, head)
    val = lerp(val, 168, glint * head)
    return lerp(val, 92, seam)


def wood():
    """Long grain: broad bands of three tones along the tile with a dark line at each
    band's edge, fainter lines between, and two knots the grain rings round."""
    rng = np.random.default_rng(101)
    knots = rng.random((2, 2))
    dx, dy, _ = nearest(knots)
    rk = np.sqrt((dx / 30) ** 2 + (dy / 15) ** 2)
    f = 6 * V + pfbm(2, 3, 1001, 2) * 0.7 + 1.6 * np.exp(-((rk / 2.6) ** 2))
    s = np.mod(f, 1.0)
    val = 184 + steps(s, [0.42, 0.74], [3, -8, 7], 1.5)
    edge = contour_dist(np.sin(np.pi * f))
    strength = 0.55 + 0.45 * smoothstep(0.3, 0.6, pnoise(5, 9, 1002))
    val -= 26 * line(edge, 1.4) * strength
    thin = line(contour_dist(np.sin(np.pi * (2 * f + 0.25))), 0.9) * smoothstep(0.55, 0.65, pnoise(4, 8, 1003))
    val -= 12 * thin
    val += steps(blobs(2, 1004, fy=6), [0.8], [0, -6], 4)
    core = 1.0 - smoothstep(0.85, 1.15, rk)
    val = lerp(val, 128, core)
    return lerp(val, 104, 1.0 - smoothstep(0.35, 0.55, rk))


def cracked_lava():
    """Near-black crust plates (two tones, a cool grey rim on their lit edges) split by
    glowing cracks of varying width: a yellow core, orange, then a deep red glow into
    the crust. Every colour is saturated; blues stay low wherever red is high."""
    rng = np.random.default_rng(111)
    wu, wv = warp(0.035, 3, 1101)
    sites = jgrid(4, 4, 0.8, rng)
    _, e, cell = worley(sites, wu, wv)
    w = 2.2 + 6.0 * blobs(4, 1102) ** 1.3
    tone = rng.choice(np.array([0.0, 1.0], F), len(sites))[cell]
    crust_a, crust_b = np.array([30, 30, 34], F), np.array([40, 40, 46], F)
    rgb = lerp(crust_a, crust_b, tone[..., None])
    light = steps(blobs(3, 1103), [0.78], [0, 1], 4)
    rgb = lerp(rgb, np.array([52, 52, 58], F), (light * 0.8)[..., None])
    rim = np.clip(bevel((e > w).astype(F), 5, 1, 0.6), -1, 1)
    rgb = rgb + np.where(rim > 0, rim * 26, rim * 10)[..., None]
    glow = np.exp(-np.maximum(e - w, 0) / (5.0 + 1.5 * w)) * 0.85
    rgb = lerp(rgb, np.array([168, 20, 0], F), glow[..., None])
    rgb = lerp(rgb, np.array([255, 116, 6], F), line(e, w)[..., None])
    rgb = lerp(rgb, np.array([255, 218, 52], F), line(e, w * 0.45)[..., None])
    return np.clip(rgb, 0, 255)


MATERIALS = {
    "Rock": rock,
    "Slate": slate,
    "Basalt": basalt,
    "Sandstone": sandstone,
    "Sand": sand,
    "Mud": mud,
    "CrackedLava": cracked_lava,
    "Pebble": pebble,
    "Marble": marble,
    "WoodPlanks": wood_planks,
    "Wood": wood,
}


# --- Output ------------------------------------------------------------------------------


def skin_guard(rgb):
    """Pulls the blue out of any texel the moderation screen's skin rules would read as
    skin (an orange-brown blend at a crack's edge); invisible at that brightness."""
    sys.path.insert(0, str(HERE.parent / "shades"))
    from screen_shades import skin_masks

    out = np.round(np.clip(rgb, 0, 255)).astype(np.uint8)
    for _ in range(4):
        skin, pale = skin_masks(out)
        bad = skin | pale
        if not bad.any():
            break
        out[..., 2] = np.where(bad, np.minimum(out[..., 2], 12), out[..., 2])
        out[..., 1] = np.where(bad & (out[..., 1] > 40), (out[..., 1] * 0.8).astype(np.uint8), out[..., 1])
    return out


def seam_score(img):
    """How much the wrap seams differ, against neighbouring rows/columns inside."""
    a = img.astype(F)
    inner = (np.abs(np.diff(a, axis=0)).mean() + np.abs(np.diff(a, axis=1)).mean()) / 2
    wrap = (np.abs(a[0] - a[-1]).mean() + np.abs(a[:, 0] - a[:, -1]).mean()) / 2
    return wrap, inner


def write(name: str):
    val = MATERIALS[name]()
    if val.ndim == 2:
        val = val + (TARGET[name] - float(val.mean()))
        val = np.clip(val, FLOOR, CEILING)
        grey = np.round(val).astype(np.uint8)
        rgb = np.stack([grey] * 3, -1)
    else:
        rgb = skin_guard(val)
    path = OUT / f"toon_{name}.png"
    Image.fromarray(rgb, "RGB").save(path, optimize=True)
    wrap, inner = seam_score(rgb)
    y = rgb.astype(F).mean(-1)
    print(
        f"[toon] {path.name}: mean {y.mean():.0f}, min {y.min():.0f}, max {y.max():.0f}, "
        f">=230 {100 * (y >= 230).mean():.1f}%, wrap seam {wrap:.2f} vs inside {inner:.2f}"
    )


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("only", nargs="*", help=f"materials to write (default all): {', '.join(MATERIALS)}")
    args = ap.parse_args(argv)
    names = args.only or list(MATERIALS)
    unknown = [n for n in names if n not in MATERIALS]
    if unknown:
        print(f"[toon] unknown: {', '.join(unknown)}")
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    for name in names:
        write(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
