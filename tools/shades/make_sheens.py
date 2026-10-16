#!/usr/bin/env python3
"""Tiling sheen textures for the top skins (owner, 2026-10-12: "prismatic needs to
be moving across the fish not just static. same with the other highest rarity
skins"). Each is a 512x512 PNG that tiles in both directions; in game a Texture of
it sits on each face of the fish's mesh and slides (Shared/Cosmetics `sheen`), so
the pattern sweeps across the body while the skin underneath stays put. Upload
each as an Image (Decal) and paste its id into src/shared/Config/Textures.luau.

  python3.11 tools/shades/make_sheens.py                      # writes every assets/textures/sheen_*.png
  python3.11 tools/shades/make_sheens.py sheen_lava sheen_bolt  # only those (the others' bytes untouched)

v9 (2026-10-16) adds sheen_lava, sheen_caustic, sheen_facets, sheen_current and
sheen_bolt (they need scipy; the first four don't).

No skin tones anywhere: every colour is a saturated hue or near-white on black,
so the moderation screen has nothing to misread.
"""
from __future__ import annotations

import pathlib

import numpy as np
from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent.parent / "assets" / "textures"
SIZE = 512


def grid():
    v, u = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32) / SIZE
    return u, v


def hsv_to_rgb(h, s, v):
    i = np.floor(h * 6).astype(int) % 6
    f = h * 6 - np.floor(h * 6)
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    r = np.choose(i, [v, q, p, p, t, v])
    g = np.choose(i, [t, v, v, q, p, p])
    b = np.choose(i, [p, p, t, v, v, q])
    return np.stack([r, g, b], -1)


def save(name: str, rgb, alpha):
    rgba = np.concatenate([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)[..., None]], -1)
    Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(OUT / f"{name}.png")
    print(f"[sheens] {name}.png")


def prismatic():
    """Diagonal rainbow bands, soft-edged, with a brighter hot stripe in each: the
    holographic sweep. Hue runs along the diagonal so a slide along U rolls every
    colour across the body; alpha fades between bands so the skin shows through."""
    u, v = grid()
    d = (u + v) % 1.0  # the diagonal, tiling both ways (the slope must be a whole number)
    hue = d
    rgb = hsv_to_rgb(hue, np.full_like(hue, 0.95), np.ones_like(hue))
    # Alpha: two soft bands per tile, with a thin bright core
    band = 0.5 + 0.5 * np.cos(2 * np.pi * d * 2)
    core = np.exp(-((((d * 2) % 1.0) - 0.5) ** 2) / 0.004)
    alpha = 0.55 * band ** 1.6 + 0.45 * core
    rgb = rgb * (0.85 + 0.15 * core[..., None]) + core[..., None] * 0.25
    save("sheen_prismatic", rgb, alpha * 0.9)


def sparkle(seed: int, count: int, warm: bool):
    """Sparse soft sparkles (a four-point glint each) on nothing: the diamond's
    glitter, or warm gold motes for Divine."""
    rng = np.random.default_rng(seed)
    u, v = grid()
    alpha = np.zeros((SIZE, SIZE), np.float32)
    for _ in range(count):
        cx, cy = rng.random(), rng.random()
        r = rng.uniform(0.01, 0.028)
        for ox in (-1, 0, 1):  # wrap, so it tiles
            for oy in (-1, 0, 1):
                dx, dy = u - (cx + ox), v - (cy + oy)
                dist2 = dx * dx + dy * dy
                glow = np.exp(-dist2 / (r * r)) * 0.9
                # The four-point star: thin lines along the axes
                star = (np.exp(-(dx * dx) / (r * r * 0.02)) * np.exp(-(dy * dy) / (r * r * 3))
                        + np.exp(-(dy * dy) / (r * r * 0.02)) * np.exp(-(dx * dx) / (r * r * 3)))
                alpha = np.maximum(alpha, glow + 0.8 * star)
    alpha = np.clip(alpha, 0, 1)
    if warm:
        rgb = np.stack([np.ones_like(alpha), 0.84 * np.ones_like(alpha), 0.35 * np.ones_like(alpha)], -1)
    else:
        rgb = np.stack([0.85 + 0.15 * alpha, 0.95 + 0.05 * alpha, np.ones_like(alpha)], -1)
    return rgb, alpha


def veil():
    """Soft aurora curtains: vertical-ish ribbons of teal, green and violet that
    drift. Tiles both ways through sums of sines."""
    u, v = grid()
    tu, tv = 2 * np.pi * u, 2 * np.pi * v
    ribbon = (np.sin(tu * 3 + np.sin(tv * 2) * 1.3) + np.sin(tu * 5 + 1.7 + np.sin(tv * 3 + 0.8) * 0.9)) / 2
    a = np.clip(0.5 + 0.5 * ribbon, 0, 1) ** 2.2
    hue = (0.38 + 0.18 * np.sin(tu * 2 + tv) + 0.1 * np.sin(tv * 3)) % 1.0
    rgb = hsv_to_rgb(hue, np.full_like(hue, 0.85), np.ones_like(hue))
    save("sheen_veil", rgb, a * 0.85)


# ---------------------------------------------------------------------------
# v9 (owner, 2026-10-16: "A lot of the other ones should be moving textures or have
# elements that make them desirable. Still too many flat models"): five more moving
# layers. Every field below tiles: noise on a periodic lattice, Worley distances on a
# torus (cKDTree boxsize), lines drawn at every wrapped offset. The colour is set
# everywhere (alpha alone says where a layer shows), so a filtered edge never darkens
# and the moderation classifier, which sees the colour without its alpha, sees a
# coloured field, not bright lines on black (thin near-white lines on black scored
# high on it, docs/ASSETS.md). Saturated or cool colours only: no peach, beige, pink,
# cream or tan anywhere. Needs scipy (python3.11).
# ---------------------------------------------------------------------------


def pnoise(freq: int, seed: int, u=None, v=None):
    """Value noise on a freq x freq lattice that wraps, so it tiles (0..1)."""
    if u is None:
        u, v = grid()
    rng = np.random.default_rng(seed)
    lattice = rng.random((freq, freq)).astype(np.float32)
    x, y = (u % 1.0) * freq, (v % 1.0) * freq
    i0, j0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - i0, y - j0
    fx = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
    fy = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
    i0, j0 = i0 % freq, j0 % freq
    i1, j1 = (i0 + 1) % freq, (j0 + 1) % freq
    a = lattice[j0, i0] * (1 - fx) + lattice[j0, i1] * fx
    b = lattice[j1, i0] * (1 - fx) + lattice[j1, i1] * fx
    return a * (1 - fy) + b * fy


def pfbm(freq: int, seed: int, octaves=4, u=None, v=None):
    out, amp, total = 0.0, 1.0, 0.0
    for o in range(octaves):
        out = out + amp * pnoise(freq * 2**o, seed + o, u, v)
        total += amp
        amp *= 0.5
    return out / total


def pworley(count: int, seed: int, u=None, v=None):
    """F1 and F2 to `count` random points on the torus (distances in tiles)."""
    from scipy.spatial import cKDTree

    if u is None:
        u, v = grid()
    rng = np.random.default_rng(seed)
    pts = rng.random((count, 2))
    tree = cKDTree(pts, boxsize=1.0)
    q = np.stack([(u % 1.0).ravel(), (v % 1.0).ravel()], -1)
    q = np.clip(q, 0, np.nextafter(1.0, 0))
    d, _ = tree.query(q, k=2)
    return d[:, 0].reshape(u.shape).astype(np.float32), d[:, 1].reshape(u.shape).astype(np.float32)


def blur(field, sigma):
    from scipy import ndimage

    return ndimage.gaussian_filter(np.asarray(field, np.float32), sigma, mode="wrap")


def ramp(t, stops):
    """A colour ramp: t (0..1) through (position, (r, g, b)) stops."""
    t = np.clip(t, 0, 1)
    pos = np.array([p for p, _ in stops], np.float32)
    cols = np.array([c for _, c in stops], np.float32)
    return np.stack([np.interp(t, pos, cols[:, k]) for k in range(3)], -1).astype(np.float32)


class Canvas:
    """Lines and polygons drawn 4x over size and every primitive at its 9 wrapped
    offsets, then box-filtered down: anti-aliased coverage that tiles."""

    SS = 4

    def __init__(self):
        from PIL import ImageDraw

        self.n = SIZE * self.SS
        self.img = Image.new("L", (self.n, self.n), 0)
        self.draw = ImageDraw.Draw(self.img)

    def _wrapped(self, pts):
        for ox in (-1, 0, 1):
            for oy in (-1, 0, 1):
                yield [((x + ox) * self.n, (y + oy) * self.n) for x, y in pts]

    def line(self, pts, width_px, value=255):
        w = max(1, int(round(width_px * self.SS)))
        for q in self._wrapped(pts):
            self.draw.line(q, fill=value, width=w, joint="curve")
            for x, y in (q[0], q[-1]):
                r = w / 2
                self.draw.ellipse((x - r, y - r, x + r, y + r), fill=value)

    def polygon(self, pts, value=255):
        for q in self._wrapped(pts):
            self.draw.polygon(q, fill=value)

    def coverage(self):
        small = self.img.resize((SIZE, SIZE), Image.BOX)
        return np.asarray(small, np.float32) / 255.0


def contour_distance(field, level=0.5):
    """Distance in pixels to where `field` crosses `level` (first order: the gap over
    the slope), so a line drawn on it is as wide everywhere."""
    gy = (np.roll(field, -1, 0) - np.roll(field, 1, 0)) / 2
    gx = (np.roll(field, -1, 1) - np.roll(field, 1, 1)) / 2
    return np.abs(field - level) / (np.hypot(gx, gy) + 1e-5)


def lava():
    """Molten flow under a crust: glowing veins wandering along the slide (U), swelling
    and pinching, a few small pools of heat on them, each with a soft halo; mostly
    transparent between. The colour runs deep red at the halos' edges, orange, yellow,
    to a hot yellow-white in the veins' cores (blue kept near zero, so nothing pales
    toward peach), with dark crust rafts riding the flow."""
    u, v = grid()
    # Domain-warped, stretched along U so the veins read as flowing that way
    wu = pfbm(3, 501, 4) - 0.5
    wv = pfbm(3, 502, 4) - 0.5
    su, sv = u + 0.22 * wu, v + 0.3 * wv
    n = pfbm(2, 503, 5, su, sv)
    n2 = pfbm(4, 504, 4, su + 0.31, sv + 0.17)
    # The main veins (px wide) swell and pinch along their length
    swell = np.clip((pfbm(4, 507, 3) - 0.3) / 0.4, 0, 1)
    width = 2.0 + 7.0 * swell**1.5
    vein = np.exp(-((contour_distance(n) / width) ** 2))
    # Fine tributaries, only in places
    patchy = np.clip((pfbm(3, 508, 3) - 0.45) / 0.15, 0, 1)
    vein2 = np.exp(-((contour_distance(n2) / 1.8) ** 2)) * patchy * 0.8
    veins = np.maximum(vein, vein2)
    # Small pools of heat where the slow noise peaks, on a vein
    slow = pfbm(4, 505, 3)
    pools = np.clip((slow - 0.68) / 0.08, 0, 1) * np.exp(-((contour_distance(n) / 16.0) ** 2))
    pools = blur(pools, 2.5)
    # Dark crust rafts floating on the flow
    f1, _ = pworley(140, 506)
    rafts = np.clip((0.010 - f1) / 0.004, 0, 1)
    hot = np.maximum(veins, pools) * (1 - 0.55 * rafts)
    halo = np.clip(blur(hot, 4) * 2.2, 0, 1)
    wide = np.clip(blur(hot, 13) * 2.6, 0, 1)
    heat = np.clip(np.maximum(hot * (0.75 + 0.25 * swell), 0.5 * halo + 0.2 * wide), 0, 1)
    rgb = ramp(
        heat,
        [
            (0.0, (0.50, 0.02, 0.0)),
            (0.22, (0.78, 0.07, 0.0)),
            (0.45, (1.0, 0.28, 0.0)),
            (0.68, (1.0, 0.52, 0.0)),
            (0.86, (1.0, 0.76, 0.06)),
            (1.0, (1.0, 0.92, 0.28)),
        ],
    )
    alpha = 0.82 * hot + 0.42 * halo + 0.2 * wide
    alpha = np.clip(alpha, 0, 0.82)
    save("sheen_lava", rgb, alpha)


def caustic():
    """A caustic light net, the wobbly bright web on a sunlit pool's floor: two
    warped Worley edge nets at different scales, brightest where they cross. Aqua to
    cyan-white, transparent in the cells."""
    u, v = grid()

    def web(count, seed, warp, width):
        wu = pfbm(3, seed + 1, 3) - 0.5
        wv = pfbm(3, seed + 2, 3) - 0.5
        f1, f2 = pworley(count, seed, u + warp * wu, v + warp * wv)
        edge = f2 - f1
        return np.exp(-((edge / width) ** 1.3))

    a = web(26, 601, 0.09, 0.012)
    b = web(44, 611, 0.07, 0.008)
    net = np.clip(0.75 * a + 0.55 * b + 0.6 * a * b, 0, 1.4)
    # The light breathes along the net (some strands brighter)
    net = net * (0.65 + 0.5 * pfbm(4, 621, 3))
    glow = np.clip(blur(net, 3) * 1.3, 0, 1)
    core = np.clip((net - 0.55) / 0.5, 0, 1)
    rgb = ramp(
        np.clip(0.55 * glow + 0.6 * core, 0, 1),
        [(0.0, (0.05, 0.55, 0.70)), (0.45, (0.20, 0.82, 0.92)), (0.8, (0.55, 0.95, 1.0)), (1.0, (0.80, 0.98, 1.0))],
    )
    alpha = np.clip(0.62 * np.clip(net, 0, 1) + 0.25 * glow, 0, 0.85)
    save("sheen_caustic", rgb, alpha)


def facets():
    """Crystal facet glints: sparse sharp-edged triangles and rhombi of light, each
    brightest at one corner and fading across, edged with a thin line of prismatic
    fire (green, cyan, blue, violet, a touch of yellow: never pink), plus thin
    refraction streaks and a few four-point glints. Icy blue to cool white."""
    rng = np.random.default_rng(701)
    u, v = grid()
    fill = np.zeros((SIZE, SIZE), np.float32)
    tone = np.zeros((SIZE, SIZE), np.float32)  # 0 icy blue .. 1 cool white
    fire = np.zeros((SIZE, SIZE), np.float32)
    fire_hue = np.zeros((SIZE, SIZE), np.float32)
    count = 30
    for k in range(count):
        cx, cy = rng.random(), rng.random()
        size = rng.uniform(0.025, 0.07)
        rot = rng.uniform(0, 2 * np.pi)
        if rng.random() < 0.55:  # a triangle, a little irregular
            angles = rot + np.array([0, 2.1, 4.2]) + rng.uniform(-0.35, 0.35, 3)
            radii = size * rng.uniform(0.7, 1.15, 3)
        else:  # a rhombus, long and thin like a flash off a facet
            angles = rot + np.array([0, np.pi / 2, np.pi, 3 * np.pi / 2])
            radii = size * np.array([1.4, 0.45, 1.4, 0.45]) * rng.uniform(0.8, 1.1, 4)
        pts = [(cx + r * np.cos(a), cy + r * np.sin(a)) for a, r in zip(angles, radii)]
        shape = Canvas()
        shape.polygon(pts)
        cov = shape.coverage()
        outline = Canvas()
        outline.line(pts + [pts[0]], 1.4)
        edge = outline.coverage()
        # Brightest at its first corner, fading across the facet
        hx, hy = pts[0]
        dx = (u - hx + 0.5) % 1.0 - 0.5
        dy = (v - hy + 0.5) % 1.0 - 0.5
        grad = np.clip(1 - np.hypot(dx, dy) / (size * 2.2), 0, 1)
        strength = rng.uniform(0.7, 0.95)
        new = cov * strength * (0.5 + 0.5 * grad)
        fill = np.maximum(fill, new)
        tone = np.where(cov > 0.5, np.maximum(tone, grad), tone)
        hue = rng.uniform(0.14, 0.5)  # + 0.25 across it: yellow-green to violet, never pink
        fire = np.maximum(fire, edge * rng.uniform(0.6, 0.9))
        fire_hue = np.where(edge > 0.3, (hue + 0.25 * grad) % 1.0, fire_hue)
    # Thin refraction streaks: long, straight, tapered by a soft glow
    streak = Canvas()
    for k in range(9):
        cx, cy = rng.random(), rng.random()
        ang = rng.uniform(-0.6, 0.6) + (0 if rng.random() < 0.6 else np.pi / 2)
        length = rng.uniform(0.12, 0.3)
        p0 = (cx - np.cos(ang) * length / 2, cy - np.sin(ang) * length / 2)
        p1 = (cx + np.cos(ang) * length / 2, cy + np.sin(ang) * length / 2)
        streak.line([p0, p1], 1.2, value=int(rng.uniform(150, 230)))
    streaks = streak.coverage()
    # Four-point glints on some corners
    glint = Canvas()
    for k in range(10):
        cx, cy = rng.random(), rng.random()
        r = rng.uniform(0.012, 0.025)
        glint.line([(cx - r, cy), (cx + r, cy)], 1.0)
        glint.line([(cx, cy - r), (cx, cy + r)], 1.0)
    glints = glint.coverage()
    halo = np.clip(blur(np.maximum(fill, streaks), 5) * 1.6, 0, 1)
    icy, white = np.array((0.58, 0.84, 1.0), np.float32), np.array((0.88, 0.95, 1.0), np.float32)
    t = np.clip(tone * fill * 1.2 + 0.6 * streaks + glints, 0, 1)[..., None]
    rgb = icy * (1 - t) + white * t
    fire_rgb = hsv_to_rgb(fire_hue, np.full_like(fire_hue, 0.8), np.ones_like(fire_hue))
    rgb = rgb * (1 - fire[..., None] * 0.85) + fire_rgb * fire[..., None] * 0.85
    alpha = np.clip(np.maximum.reduce([fill, fire * 0.9, streaks * 0.75, glints * 0.9]) + 0.22 * halo, 0, 0.9)
    save("sheen_facets", rgb, alpha)


def current():
    """A streaming current: long thin wavy streaks running along U (the way the layer
    slides), each with a soft halo, teal and cyan with a few violet: water rushing
    past the fish."""
    rng = np.random.default_rng(801)
    u, v = grid()
    line = np.zeros((SIZE, SIZE), np.float32)
    halo = np.zeros((SIZE, SIZE), np.float32)
    col = np.zeros((SIZE, SIZE, 3), np.float32)
    weight = np.zeros((SIZE, SIZE), np.float32)
    palette = [(0.05, 0.80, 0.75), (0.15, 0.85, 0.95), (0.30, 0.70, 1.0), (0.50, 0.40, 1.0)]
    for k in range(16):
        base = rng.random()
        waves = int(rng.integers(1, 4))  # whole waves per tile, so it tiles
        amp = rng.uniform(0.008, 0.03)
        phase = rng.uniform(0, 2 * np.pi)
        y = base + amp * np.sin(2 * np.pi * waves * u + phase) + 0.4 * amp * np.sin(2 * np.pi * (waves + 2) * u + phase * 1.7)
        slope = 2 * np.pi * waves * amp * np.cos(2 * np.pi * waves * u + phase)
        dv = ((v - y + 0.5) % 1.0 - 0.5) / np.sqrt(1 + slope * slope)
        # Its length along U: a soft-ended stretch of the tile (wraps round)
        start, length = rng.random(), rng.uniform(0.25, 0.75)
        along = (u - start) % 1.0
        env = np.clip(np.minimum(along, length - along) / (0.3 * length), 0, 1) * (along < length)
        env = env * env * (3 - 2 * env)
        width = rng.uniform(0.0016, 0.0032)
        core = np.exp(-((dv / width) ** 2)) * env
        soft = np.exp(-((dv / (width * 7)) ** 2)) * env
        strength = rng.uniform(0.6, 1.0)
        line = np.maximum(line, core * strength)
        halo = np.maximum(halo, soft * strength)
        c = np.array(palette[3] if k % 5 == 4 else palette[int(rng.integers(0, 3))], np.float32)
        w = soft + 1e-4
        col += c * w[..., None]
        weight += w
    base_col = np.array(palette[1], np.float32)
    rgb = (col + base_col * 0.05) / (weight + 0.05)[..., None]
    rgb = rgb * (1 - 0.35 * line[..., None]) + np.array((0.70, 0.95, 1.0), np.float32) * (0.35 * line[..., None])
    alpha = np.clip(0.8 * line + 0.35 * halo, 0, 0.85)
    save("sheen_current", rgb, alpha)


def bolt():
    """Electric arcs: a few branching, crackling bolts of lightning, electric blue to
    violet, with a wide soft glow. Their cores stay a light blue-violet, never white
    (thin near-white lines on dark scored high on the classifier); the halo is wide."""
    rng = np.random.default_rng(901)

    def arc(p0, p1, rough, depth):
        """Midpoint displacement between two points: a jagged line."""
        pts = [np.array(p0, np.float64), np.array(p1, np.float64)]
        for _ in range(depth):
            out = [pts[0]]
            for a, b in zip(pts[:-1], pts[1:]):
                d = b - a
                normal = np.array([-d[1], d[0]])
                mid = (a + b) / 2 + normal * rng.normal(0, rough)
                out += [mid, b]
            pts = out
        return [tuple(p) for p in pts]

    main_cv, branch_cv = Canvas(), Canvas()
    for k in range(4):
        start = rng.random(2)
        ang = rng.uniform(0, 2 * np.pi)
        length = rng.uniform(0.3, 0.5)
        end = start + length * np.array([np.cos(ang), np.sin(ang)])
        pts = arc(start, end, 0.18, 6)
        main_cv.line(pts, 1.6)
        # Branches forking off the main arc
        for b in range(int(rng.integers(3, 6))):
            i = int(rng.integers(8, len(pts) - 8))
            root = np.array(pts[i])
            bang = ang + rng.choice([-1, 1]) * rng.uniform(0.4, 1.1)
            blen = length * rng.uniform(0.15, 0.4)
            bend = root + blen * np.array([np.cos(bang), np.sin(bang)])
            bpts = arc(root, bend, 0.22, 5)
            branch_cv.line(bpts, 1.1, value=int(rng.uniform(150, 220)))
            if rng.random() < 0.5:  # a twig
                j = int(rng.integers(4, len(bpts) - 4))
                troot = np.array(bpts[j])
                tang = bang + rng.choice([-1, 1]) * rng.uniform(0.5, 1.0)
                tend = troot + blen * 0.45 * np.array([np.cos(tang), np.sin(tang)])
                branch_cv.line(arc(troot, tend, 0.25, 4), 0.9, value=int(rng.uniform(110, 170)))
    core = np.maximum(main_cv.coverage(), branch_cv.coverage())
    near = np.clip(blur(core, 2.5) * 3.0, 0, 1)
    wide = np.clip(blur(core, 10) * 5.0, 0, 1)
    vast = np.clip(blur(core, 22) * 6.0, 0, 1)
    # Colour: violet in the far glow, electric blue nearer, a light blue-violet core
    u, v = grid()
    tint = pfbm(3, 911, 3)  # some bolts lean violet, some blue
    far_col = ramp(tint, [(0.0, (0.28, 0.22, 0.95)), (1.0, (0.50, 0.25, 1.0))])
    near_col = np.array((0.30, 0.50, 1.0), np.float32)
    core_col = np.array((0.66, 0.74, 1.0), np.float32)
    t1 = np.clip(near * 1.2, 0, 1)[..., None]
    rgb = far_col * (1 - t1) + near_col * t1
    t2 = np.clip(core * 1.3, 0, 1)[..., None]
    rgb = rgb * (1 - t2) + core_col * t2
    alpha = np.clip(0.85 * core + 0.45 * near + 0.3 * wide + 0.14 * vast, 0, 0.88)
    save("sheen_bolt", rgb, alpha)


MAKERS = {
    "sheen_prismatic": prismatic,
    "sheen_sparkle": lambda: save("sheen_sparkle", *sparkle(7, 90, False)),
    "sheen_gold": lambda: save("sheen_gold", *sparkle(11, 60, True)),
    "sheen_veil": veil,
    # v9 (2026-10-16)
    "sheen_lava": lava,
    "sheen_caustic": caustic,
    "sheen_facets": facets,
    "sheen_current": current,
    "sheen_bolt": bolt,
}


def main():
    """Every sheen, or only those named (python3.11 tools/shades/make_sheens.py
    sheen_lava sheen_bolt): naming them leaves the others' images untouched, so an
    uploaded image isn't rewritten."""
    import sys

    OUT.mkdir(parents=True, exist_ok=True)
    names = sys.argv[1:] or list(MAKERS)
    unknown = [n for n in names if n not in MAKERS]
    if unknown:
        raise SystemExit(f"[sheens] no sheen called {', '.join(unknown)} (have {', '.join(MAKERS)})")
    for name in names:
        MAKERS[name]()


if __name__ == "__main__":
    main()
