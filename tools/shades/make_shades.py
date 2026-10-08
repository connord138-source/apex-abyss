"""Makes the shade skins: one recolored color texture per fish and shade.

    python tools/shades/make_shades.py <maps_dir> <out_dir> [Fish ...] [--only Shade,Shade]

Needs numpy, scipy and pillow. The maps come from bake_maps.py (the fish's own color
texture plus, for every texel, where it sits on the body in 3D) and the eyes from
eyes.json (find_eyes.py). Owner, 2026-10-08: "All of the shades in general need much
much more variance and depth than just a slight reshape to the existing colors." A
tint can only darken a texture (SurfaceAppearance.Color multiplies), so every shade
is a real skin here: countershaded body, fins, then patterns laid on the body in 3D
(stripes, bands, spots, rosettes, nets, scales, facets, cracks, clouds) and a finish
(pearl, metal, glow halos), keeping the texture's painted strokes, the eyes, teeth
and mouth, and the Anglerfish's lure.

No skin may look like human skin (Hatch & Snatch, 2026-10-03: an account suspension
over a pale pinkish atlas). Every pale tone is cool (silver-blue whites), warm colors
are saturated (a saturated orange or gold is far outside the skin-tone rules; a
peach or beige is inside them), and screen_shades.py checks every skin before upload.

Writes <out_dir>/<Fish>/<Shade>.png (1024, what Roblox takes) plus eyes_debug.png.
"""

from __future__ import annotations

import json
import pathlib
import sys

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import cKDTree

HERE = pathlib.Path(__file__).parent
SIZE = 1024

# Per fish: keep its teeth and mouth (the predators), and the Anglerfish's glowing
# lure and iris
FISH = {
    "Nibbler": {"teeth": False, "keep_vivid": False},
    "Cuda": {"teeth": True, "keep_vivid": False},
    "Puffer": {"teeth": False, "keep_vivid": False},
    "MorayEel": {"teeth": True, "keep_vivid": False},
    "ReefShark": {"teeth": True, "keep_vivid": False},
    "Angler": {"teeth": True, "keep_vivid": True},
}


def C(*rgb):
    return np.array(rgb, np.float32)


def smoothstep(a, b, x):
    d = np.asarray(b, np.float32) - np.asarray(a, np.float32)
    d = np.where(np.abs(d) < 1e-9, 1e-9, d)
    t = np.clip((x - a) / d, 0, 1)
    return t * t * (3 - 2 * t)


def rgb_to_hsv(c):
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    mx, mn = c.max(-1), c.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rc = np.where(m, (mx - r) / np.where(m, d, 1), 0)
    gc = np.where(m, (mx - g) / np.where(m, d, 1), 0)
    bc = np.where(m, (mx - b) / np.where(m, d, 1), 0)
    h = np.where(r == mx, bc - gc, np.where(g == mx, 2 + rc - bc, 4 + gc - rc))
    h = (h / 6) % 1
    s = np.where(mx > 1e-6, d / np.where(mx > 1e-6, mx, 1), 0)
    return np.stack([np.where(m, h, 0), s, mx], -1)


def hsv_to_rgb(hsv):
    h, s, v = hsv[..., 0] % 1, hsv[..., 1], hsv[..., 2]
    i = np.floor(h * 6).astype(int) % 6
    f = h * 6 - np.floor(h * 6)
    p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    choices = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]
    out = np.zeros(h.shape + (3,), np.float32)
    for k, (a, b, c) in enumerate(choices):
        sel = i == k
        out[sel] = np.stack([a[sel], b[sel], c[sel]], -1)
    return out


class Fish:
    """A fish's texture and its texels' places on the body, at SIZE."""

    def __init__(self, name: str, npz: pathlib.Path, picks):
        d = np.load(npz)
        color = Image.fromarray(d["color"]).resize((SIZE, SIZE), Image.LANCZOS)
        self.name = name
        self.color = np.asarray(color, np.float32) / 255.0
        k = SIZE / d["position"].shape[0]
        zoom = (lambda a: ndimage.zoom(a, (k, k, 1), order=1)) if k != 1 else (lambda a: a)
        self.pos = zoom(d["position"].astype(np.float32))
        nrm = zoom(d["normal"].astype(np.float32))
        self.nrm = nrm / np.maximum(np.linalg.norm(nrm, axis=-1, keepdims=True), 1e-6)
        cov = d["covered"]
        if cov.shape[0] != SIZE:
            cov = ndimage.zoom(cov.astype(np.float32), k, order=0) > 0.5
        self.cov = cov
        self.mn, self.mx = d["bounds"]
        self.length = float(d["length"])
        self.faces = d["faces"]
        self.hsv = rgb_to_hsv(self.color)
        self.lum = self.color @ np.array([0.299, 0.587, 0.114], np.float32)
        # Body frame: y 0 at the snout .. 1 at the tail tip; x and z in body lengths
        self.y = (self.pos[..., 1] - self.mn[1]) / max(self.length, 1e-6)
        self.p = self.pos / max(self.length, 1e-6)  # body lengths
        self._cross_section()
        self.fine = self._fine_detail()
        self.keep = self._keep_mask(picks)

    # ---- the body's cross-section along its length: core ellipse, fins, countershade
    def _cross_section(self):
        bins = 48
        y, x, z = self.y, self.p[..., 0], self.p[..., 2]
        idx = np.clip((y * bins).astype(int), 0, bins - 1)
        xc = np.zeros(bins)
        zc = np.zeros(bins)
        wx = np.zeros(bins)
        wz = np.zeros(bins)
        for b in range(bins):
            sel = self.cov & (idx == b)
            if sel.sum() < 20:
                continue
            xs, zs = x[sel], z[sel]
            xc[b], zc[b] = np.median(xs), np.median(zs)
            wx[b] = np.percentile(np.abs(xs - xc[b]), 65)
            wz[b] = np.percentile(np.abs(zs - zc[b]), 65)
        # The core follows the torso, not the fins: fit the middle of the body and
        # taper it toward the tail, where the fin dominates the texels
        good = wx > 0
        for arr in (xc, zc, wx, wz):
            if good.any():
                arr[~good] = np.interp(np.flatnonzero(~good), np.flatnonzero(good), arr[good])
        ys = (np.arange(bins) + 0.5) / bins
        mid = (ys > 0.2) & (ys < 0.7)
        cap_x, cap_z = np.max(wx[mid]), np.max(wz[mid])
        taper = np.clip(1 - (ys - 0.7) / 0.3 * 0.75, 0.25, 1)
        wx = np.minimum(wx, cap_x * taper)
        wz = np.minimum(wz, cap_z * taper)
        smooth = lambda a: ndimage.gaussian_filter1d(a, 2, mode="nearest")  # noqa: E731
        xc, zc, wx, wz = smooth(xc), smooth(zc), smooth(wx), smooth(wz)
        self.xc, self.zc = xc[idx], zc[idx]
        ex = (x - self.xc) / np.maximum(wx[idx], 1e-4)
        ez = (z - self.zc) / np.maximum(wz[idx], 1e-4)
        self.r2 = ex * ex + ez * ez
        self.ez = ez
        self.ex = ex
        self.fin = smoothstep(2.2, 3.4, self.r2) * self.cov
        # How far up the body: 0 belly .. 1 back (with the normal, for countershading)
        zrel = np.clip(ez * 0.5 + 0.5, 0, 1)
        self.up = np.clip(0.6 * zrel + 0.4 * (self.nrm[..., 2] * 0.5 + 0.5), 0, 1)
        self.theta = np.arctan2(z - self.zc, x - self.xc)  # round the body

    def _fine_detail(self):
        t = np.clip(self.lum / max(float(np.percentile(self.lum[self.cov], 97)), 1e-3), 0, 1.2)
        low = ndimage.gaussian_filter(t, sigma=SIZE / 128)
        return np.clip(t - low, -0.5, 0.5)

    def _keep_mask(self, picks):
        rules = FISH.get(self.name, {})
        keep = np.zeros((SIZE, SIZE), np.float32)
        keep = np.maximum(keep, self._eyes(picks))
        head = self.cov & (self.y < 0.32)
        if rules.get("teeth"):
            sat, val = self.hsv[..., 1], self.hsv[..., 2]
            bright = head & (val > 0.72) & (sat < 0.3)
            dark = head & (val < 0.16)
            for cand, limit in ((bright, 2500), (dark, 6000)):
                labels, n = ndimage.label(cand)
                if n:
                    sizes = ndimage.sum(cand, labels, range(1, n + 1))
                    small = np.isin(labels, np.flatnonzero(sizes < limit) + 1)
                    keep = np.maximum(keep, small.astype(np.float32))
        if rules.get("keep_vivid"):
            hue, sat, val = self.hsv[..., 0], self.hsv[..., 1], self.hsv[..., 2]
            vivid = sat * val
            lure = (hue > 0.09) & (hue < 0.21) & (sat > 0.25) & (val > 0.55)  # the yellow bulb
            keep = np.maximum(keep, np.maximum(smoothstep(0.42, 0.6, vivid), lure.astype(np.float32)) * self.cov)
        return np.clip(ndimage.gaussian_filter(keep, 0.8), 0, 1)

    def _eyes(self, picks):
        """Eyes marked on the side renders (eyes.json): the texels under each pick,
        grown to a sphere on the body so the sides the camera missed are covered."""
        mask = np.zeros((SIZE, SIZE), bool)
        faces = self.faces
        yy, xx = np.mgrid[0 : faces.shape[1], 0 : faces.shape[2]]
        for view, px, py, radius in picks:
            face = faces[view]
            sel = ((xx - px) ** 2 + (yy - py) ** 2 <= radius * radius) & (face[..., 5] > 0.5)
            u, v = face[..., 3][sel], face[..., 4][sel]
            tx = np.clip((u % 1.0) * SIZE, 0, SIZE - 1).astype(int)
            ty = np.clip((1 - v % 1.0) * SIZE, 0, SIZE - 1).astype(int)
            hit = np.zeros((SIZE, SIZE), bool)
            hit[ty, tx] = True
            hit = ndimage.binary_closing(hit, iterations=3) & self.cov
            if not hit.any():
                continue
            pts = self.pos[hit]
            centre = np.median(pts, 0)
            r3 = float(np.percentile(np.linalg.norm(pts - centre, axis=-1), 90))
            sphere = (np.linalg.norm(self.pos - centre, axis=-1) < r3 * 1.08) & self.cov
            mask |= hit | sphere
        # Only the painted eye inside that sphere: the pale sclera and the dark pupil,
        # not the colored skin round it
        sat, val = self.hsv[..., 1], self.hsv[..., 2]
        eye = ((sat < 0.32) & (val > 0.5)) | (val < 0.3)
        if FISH.get(self.name, {}).get("keep_vivid"):
            eye |= sat * val > 0.42
        mask &= eye
        mask = ndimage.binary_opening(mask, iterations=1)
        return ndimage.binary_closing(mask, iterations=2).astype(np.float32)


# ---------------------------------------------------------------------------
# Noise and patterns (all in 3D on the body, in body lengths)
# ---------------------------------------------------------------------------


def value_noise(p, freq, seed):
    rng = np.random.default_rng(seed)
    lattice = rng.random((32, 32, 32)).astype(np.float32)
    q = p * freq + 7.3
    i0 = np.floor(q).astype(int)
    f = q - i0
    f = f * f * (3 - 2 * f)
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1]) * (f[..., 2] if dz else 1 - f[..., 2])
                out = out + w * lattice[(i0[..., 0] + dx) % 32, (i0[..., 1] + dy) % 32, (i0[..., 2] + dz) % 32]
    return out


def fbm(m: Fish, freq, seed, octaves=4):
    out, amp, total = 0, 1.0, 0.0
    for o in range(octaves):
        out = out + amp * value_noise(m.p, freq * 2**o, seed + o)
        total += amp
        amp *= 0.5
    return out / total


def worley(m: Fish, count, seed, jitter_box=1.0):
    """Distances to the nearest and second-nearest of `count` random points on the
    body, and the nearest one's index. Points are drawn from covered texels, so they
    sit on the skin."""
    rng = np.random.default_rng(seed)
    flat = m.p[m.cov]
    pts = flat[rng.choice(len(flat), size=min(count, len(flat)), replace=False)]
    tree = cKDTree(pts)
    d, i = tree.query(m.p.reshape(-1, 3), k=2)
    shape = m.cov.shape
    return d[:, 0].reshape(shape), d[:, 1].reshape(shape), i[:, 0].reshape(shape), len(pts)


def stripes(m: Fish, freq, width=0.5, wobble=0.0, slant=0.0, seed=1, edge=0.05):
    t = m.y * freq + slant * m.ez + wobble * (fbm(m, 6, seed) - 0.5) * 2
    s = 0.5 + 0.5 * np.cos(2 * np.pi * t)
    return smoothstep(1 - width - edge, 1 - width + edge, s)


def bands(m: Fish, centers, half, wobble=0.0, seed=2):
    w = wobble * (fbm(m, 5, seed) - 0.5) * 2
    out = np.zeros_like(m.y)
    for c in centers:
        d = np.abs(m.y - c + w)
        out = np.maximum(out, smoothstep(half + 0.012, half - 0.004, d))
    return out


def band_edges(m: Fish, centers, half, width=0.012, wobble=0.0, seed=2):
    w = wobble * (fbm(m, 5, seed) - 0.5) * 2
    out = np.zeros_like(m.y)
    for c in centers:
        d = np.abs(np.abs(m.y - c + w) - half)
        out = np.maximum(out, smoothstep(width, width * 0.3, d))
    return out


def spots(m: Fish, count, radius, seed=3, vary=0.35):
    d1, _, i, n = worley(m, count, seed)
    rng = np.random.default_rng(seed + 100)
    r = radius * (1 + vary * (rng.random(n) - 0.5) * 2)
    rr = r[i]
    return smoothstep(rr * 1.12, rr * 0.88, d1)


def rosettes(m: Fish, count, radius, seed=4):
    d1, _, i, n = worley(m, count, seed)
    rng = np.random.default_rng(seed + 100)
    rr = (radius * (0.8 + 0.4 * rng.random(n)))[i]
    ring = smoothstep(rr * 0.28, rr * 0.12, np.abs(d1 - rr * 0.75))
    gap = 0.5 + 0.5 * np.cos(np.arctan2(m.p[..., 2], m.p[..., 1]) * 3 + i * 1.7)
    return ring * smoothstep(0.15, 0.35, gap)


def net(m: Fish, count, width, seed=5):
    d1, d2, _, _ = worley(m, count, seed)
    return smoothstep(width, width * 0.35, d2 - d1)


def cells(m: Fish, count, seed=6):
    d1, d2, i, n = worley(m, count, seed)
    rng = np.random.default_rng(seed + 200)
    return rng.random(n)[i].astype(np.float32), d2 - d1


def scales(m: Fish, size):
    """Overlapping scales: rows along the body, each scale darker toward its rim."""
    u = m.y / size
    radius = 0.12
    v = m.theta * radius / size
    row = np.floor(u)
    v = v + 0.5 * (row % 2)
    fu, fv = u - row, v - np.floor(v)
    d = np.sqrt(((fu - 0.15) / 1.1) ** 2 + (fv - 0.5) ** 2)
    return smoothstep(0.25, 0.62, d)


def scale_edges(m: Fish, size, width=0.07):
    """The outlines of overlapping scales, as thin lines (for filigree)."""
    u = m.y / size
    v = m.theta * 0.12 / size
    row = np.floor(u)
    v = v + 0.5 * (row % 2)
    fu, fv = u - row, v - np.floor(v)
    d = np.sqrt(((fu - 0.15) / 1.1) ** 2 + (fv - 0.5) ** 2)
    return smoothstep(width, width * 0.25, np.abs(d - 0.5))


def speckle(m: Fish, freq, cut, seed=7):
    return smoothstep(cut, cut + 0.04, value_noise(m.p, freq, seed))


def glow_halo(mask, sigma):
    return np.clip(ndimage.gaussian_filter(mask.astype(np.float32), sigma) * 1.8, 0, 1)


def mix(rgb, color, amount):
    a = np.asarray(amount, np.float32)[..., None]
    return rgb * (1 - a) + np.asarray(color, np.float32) * a


# ---------------------------------------------------------------------------
# Building a coat
# ---------------------------------------------------------------------------


def coat(m: Fish, back, belly, fin, soft=0.25, hard_fins=False):
    w = smoothstep(0.5 - soft, 0.5 + soft, m.up)
    rgb = mix(np.broadcast_to(C(*belly), m.color.shape).copy(), back, w)
    fins = smoothstep(0.45, 0.55, m.fin) if hard_fins else m.fin
    return mix(rgb, fin, fins)


def body_only(m: Fish, mask):
    return mask * (1 - m.fin)


def sheen(m: Fish, rgb, strength=0.35, tint=(1, 1, 1)):
    """A metallic look baked in: bright and dark bands from the normal, like an
    environment reflection, plus a highlight on top."""
    n = m.nrm
    env = 0.5 + 0.5 * np.sin(5.5 * n[..., 2] + 2.4 * n[..., 0] + 1.3)
    hi = smoothstep(0.8, 1.0, env) * smoothstep(-0.2, 0.6, n[..., 2])
    rgb = rgb * (1 - strength * 0.5 + strength * env[..., None])
    return mix(rgb, C(*tint), hi * strength * 0.9)


def pearl(m: Fish, rgb, amount=0.35, hue_spread=0.14, base_hue=0.58):
    """A pearly film: a cool hue that drifts with the surface's facing."""
    n = m.nrm
    h = base_hue + hue_spread * (n[..., 0] * 0.6 + n[..., 2] * 0.4)
    film = hsv_to_rgb(np.stack([h % 1, np.full_like(h, 0.32), np.full_like(h, 1.0)], -1))
    return mix(rgb, film, amount * (0.6 + 0.4 * np.abs(n[..., 0])))


def finish(m: Fish, rgb, detail=1.3):
    """The painted strokes back on, then the eyes, teeth, mouth and lure as they were."""
    rgb = rgb * (1 + detail * m.fine)[..., None]
    rgb = np.clip(rgb, 0, 1)
    rgb = mix(rgb, m.color, m.keep)
    rgb[~m.cov] = m.color[~m.cov]
    return rgb


# ---------------------------------------------------------------------------
# The shades
# ---------------------------------------------------------------------------

# Cool whites and pale tones (never warm: a warm pale on loose atlas pieces reads as skin)
SNOW = (0.92, 0.95, 1.0)
INKY = (0.06, 0.06, 0.09)


def mint(m):
    rgb = coat(m, (0.36, 0.78, 0.62), (0.80, 0.96, 0.92), (0.16, 0.58, 0.54))
    saddle = body_only(m, spots(m, 28, 0.075, seed=11)) * smoothstep(0.55, 0.8, m.up)
    rgb = mix(rgb, (0.17, 0.50, 0.42), saddle * 0.85)
    rgb = mix(rgb, (0.10, 0.36, 0.32), speckle(m, 90, 0.72, seed=12) * 0.6 * (1 - m.fin))
    return finish(m, rgb)


def sunset(m):
    along = smoothstep(0.05, 0.95, m.y)
    rgb = mix(np.broadcast_to(C(1.0, 0.80, 0.12), m.color.shape).copy(), (0.95, 0.28, 0.08), along)
    rgb = mix(rgb, (1.0, 0.90, 0.30), smoothstep(0.45, 0.15, m.up) * 0.7)
    waves = stripes(m, 0, 1) * 0  # (no vertical stripes)
    horizon = 0.5 + 0.5 * np.sin(m.ez * 7 + (fbm(m, 4, 13) - 0.5) * 6)
    rgb = mix(rgb, (0.78, 0.12, 0.22), smoothstep(0.75, 0.95, horizon) * 0.55 * (1 - m.fin))
    rgb = mix(rgb, (0.82, 0.10, 0.26), m.fin)
    return finish(m, rgb + waves[..., None])


def ink(m):
    rgb = coat(m, (0.09, 0.12, 0.26), (0.40, 0.48, 0.68), (0.18, 0.22, 0.50))
    rgb = mix(rgb, (0.04, 0.05, 0.12), net(m, 220, 0.010, seed=14) * 0.7)
    lateral = smoothstep(0.09, 0.02, np.abs(m.ez - 0.05)) * smoothstep(0.08, 0.2, m.y) * smoothstep(0.95, 0.8, m.y)
    rgb = mix(rgb, (0.55, 0.80, 1.0), body_only(m, lateral))
    return finish(m, rgb)


def sand(m):
    rgb = coat(m, (0.58, 0.60, 0.50), (0.80, 0.83, 0.82), (0.50, 0.52, 0.44))
    blot = smoothstep(0.55, 0.62, fbm(m, 7, 15)) * smoothstep(0.3, 0.6, m.up)
    rgb = mix(rgb, (0.32, 0.35, 0.28), blot * 0.85)
    rgb = mix(rgb, (0.24, 0.26, 0.22), speckle(m, 110, 0.74, seed=16) * 0.7)
    rgb = mix(rgb, (0.78, 0.82, 0.86), speckle(m, 140, 0.8, seed=17) * 0.5)
    return finish(m, rgb)


def ember(m):
    rgb = coat(m, (0.80, 0.09, 0.07), (1.0, 0.58, 0.10), (0.95, 0.30, 0.06))
    tiger = stripes(m, 9, 0.28, wobble=0.25, slant=0.18, seed=18) * smoothstep(0.25, 0.6, m.up)
    rgb = mix(rgb, INKY, body_only(m, tiger))
    rgb = mix(rgb, (1.0, 0.72, 0.10), m.fin * smoothstep(0.6, 0.9, m.r2 / 6))
    return finish(m, rgb)


def lilac(m):
    rgb = coat(m, (0.52, 0.36, 0.86), (0.66, 0.56, 0.94), (0.40, 0.24, 0.78))
    dots = spots(m, 160, 0.02, seed=19, vary=0.25)
    rgb = mix(rgb, (0.84, 0.86, 1.0), dots * 0.9)
    rgb = mix(rgb, (0.28, 0.16, 0.60), m.fin * stripes(m, 40, 0.5, seed=20) * 0.5)
    return finish(m, rgb)


def moss(m):
    rgb = coat(m, (0.22, 0.40, 0.16), (0.62, 0.74, 0.44), (0.30, 0.46, 0.18))
    rgb = mix(rgb, (0.66, 0.80, 0.20), net(m, 130, 0.016, seed=21) * 0.9)
    rgb = mix(rgb, (0.10, 0.22, 0.08), speckle(m, 80, 0.75, seed=22) * 0.5)
    return finish(m, rgb)


def ocean(m):
    rgb = coat(m, (0.08, 0.32, 0.82), (0.34, 0.56, 0.92), (1.0, 0.82, 0.08))
    swoosh = smoothstep(0.18, 0.05, np.abs(m.ez - 0.35 - 0.25 * np.sin(m.y * 5.5))) * smoothstep(0.15, 0.3, m.y)
    rgb = mix(rgb, (0.03, 0.05, 0.14), body_only(m, swoosh))
    tail = smoothstep(0.78, 0.9, m.y)
    rgb = mix(rgb, (1.0, 0.82, 0.08), tail)
    return finish(m, rgb)


def tiger(m):
    # A hard edge between the orange and the cool white belly: a soft blend of the
    # two is peach, which the skin screen (rightly) flags
    rgb = coat(m, (1.0, 0.42, 0.0), SNOW, (0.95, 0.34, 0.0), soft=0.025, hard_fins=True)
    t = stripes(m, 11, 0.24, wobble=0.35, slant=0.25, seed=23) * smoothstep(0.15, 0.55, m.up)
    rgb = mix(rgb, INKY, t)
    edge = smoothstep(0.03, 0.0, np.abs(m.up - 0.5)) * (1 - m.fin)
    rgb = mix(rgb, INKY, edge * 0.85)
    return finish(m, rgb)


def bumblebee(m):
    rgb = coat(m, (1.0, 0.80, 0.05), (1.0, 0.88, 0.25), INKY)
    b = bands(m, (0.32, 0.52, 0.72), 0.06, wobble=0.03, seed=24)
    rgb = mix(rgb, INKY, body_only(m, b))
    return finish(m, rgb)


def tetra(m):
    rgb = coat(m, (0.05, 0.10, 0.28), (0.70, 0.78, 0.92), (0.42, 0.55, 0.85))
    rear = smoothstep(0.42, 0.55, m.y) * smoothstep(0.62, 0.35, m.up)
    rgb = mix(rgb, (0.95, 0.12, 0.10), body_only(m, rear))
    stripe = smoothstep(0.16, 0.06, np.abs(m.ez - 0.18)) * smoothstep(0.1, 0.22, m.y) * smoothstep(0.92, 0.75, m.y)
    rgb = mix(rgb, (0.12, 0.98, 1.0), body_only(m, stripe))
    return finish(m, rgb)


def leopard(m):
    rgb = coat(m, (0.98, 0.72, 0.10), (1.0, 0.88, 0.44), (0.90, 0.60, 0.08))
    rgb = mix(rgb, (0.88, 0.48, 0.05), rosettes(m, 70, 0.045, seed=25) * 0 + spots(m, 70, 0.03, seed=25) * 0.6)
    rgb = mix(rgb, INKY, rosettes(m, 70, 0.045, seed=25))
    rgb = mix(rgb, INKY, spots(m, 220, 0.009, seed=26) * smoothstep(0.3, 0.6, m.up))
    return finish(m, rgb)


def lunar(m):
    rgb = coat(m, (0.42, 0.50, 0.76), (0.84, 0.88, 0.98), (0.56, 0.62, 0.88))
    rgb = sheen(m, rgb, 0.3, (0.9, 0.94, 1.0))
    d1, _, i, n = worley(m, 14, 27)
    rng = np.random.default_rng(127)
    radius = (0.035 + 0.02 * rng.random(n))[i]
    shift = (0.4 * radius)
    full = smoothstep(radius * 1.05, radius * 0.92, d1)
    # A crescent: the moon disc minus a disc nudged toward the tail
    offset = np.zeros_like(m.p)
    offset[..., 1] = shift
    d2, _, _, _ = worley_shifted(m, 14, 27, offset)
    bite = smoothstep(radius * 1.0, radius * 0.88, d2)
    moon = np.clip(full - bite, 0, 1)
    rgb = mix(rgb, (0.93, 0.95, 1.0), body_only(m, moon))
    rgb = mix(rgb, (1.0, 1.0, 1.0), speckle(m, 170, 0.85, seed=28) * 0.9)
    rgb = mix(rgb, (0.75, 0.82, 1.0), glow_halo(speckle(m, 50, 0.92, seed=128), 2.5) * 0.4)
    return finish(m, rgb, detail=0.8)


def worley_shifted(m: Fish, count, seed, offset):
    rng = np.random.default_rng(seed)
    flat = m.p[m.cov]
    pts = flat[rng.choice(len(flat), size=min(count, len(flat)), replace=False)]
    tree = cKDTree(pts)
    d, i = tree.query((m.p - offset).reshape(-1, 3), k=2)
    shape = m.cov.shape
    return d[:, 0].reshape(shape), d[:, 1].reshape(shape), i[:, 0].reshape(shape), len(pts)


def glowspot(m):
    rgb = coat(m, (0.03, 0.06, 0.18), (0.06, 0.20, 0.30), (0.04, 0.10, 0.26))
    s = spots(m, 120, 0.016, seed=29, vary=0.5)
    rgb = mix(rgb, (0.10, 0.80, 0.95), glow_halo(s, 6) * 0.55)
    rgb = mix(rgb, (0.75, 1.0, 1.0), s)
    edge = m.fin * smoothstep(3.6, 5.5, m.r2)
    rgb = mix(rgb, (0.20, 0.95, 1.0), edge * 0.8)
    return finish(m, rgb, detail=0.8)


def tidepool(m):
    w = smoothstep(0.2, 0.85, m.up)
    rgb = mix(np.broadcast_to(C(0.42, 0.28, 0.80), m.color.shape).copy(), (0.04, 0.56, 0.62), w)
    rgb = mix(rgb, (0.10, 0.36, 0.70), m.fin)
    caustic = net(m, 260, 0.012, seed=30) * (0.5 + 0.5 * smoothstep(0.3, 0.8, m.up))
    rgb = mix(rgb, (0.55, 1.0, 0.95), caustic * 0.75)
    return finish(m, rgb)


def diamond(m):
    value, edge = cells(m, 340, seed=31)
    base = mix(np.broadcast_to(C(0.66, 0.80, 0.96), m.color.shape).copy(), SNOW, value)
    rgb = mix(base, (1.0, 1.0, 1.0), smoothstep(0.012, 0.004, edge))
    fire = speckle(m, 150, 0.83, seed=32)
    hue = (m.y * 3 + m.ez) % 1
    rgb = mix(rgb, hsv_to_rgb(np.stack([hue, np.full_like(hue, 0.6), np.ones_like(hue)], -1)), fire * 0.7)
    rgb = sheen(m, rgb, 0.25, (1, 1, 1))
    return finish(m, rgb, detail=0.6)


def magma(m):
    rgb = coat(m, (0.10, 0.08, 0.08), (0.18, 0.12, 0.10), (0.12, 0.08, 0.07))
    cracks = net(m, 150, 0.010, seed=33)
    rgb = mix(rgb, (0.85, 0.18, 0.02), glow_halo(cracks, 5) * 0.75)
    rgb = mix(rgb, (1.0, 0.55, 0.05), cracks)
    rgb = mix(rgb, (1.0, 0.88, 0.35), cracks * smoothstep(0.6, 1, fbm(m, 9, 34)))
    return finish(m, rgb, detail=0.7)


def glacier(m):
    rgb = coat(m, (0.24, 0.52, 0.80), (0.70, 0.86, 0.98), (0.40, 0.70, 0.94))
    frost = smoothstep(0.55, 0.7, fbm(m, 8, 35))
    rgb = mix(rgb, SNOW, frost * 0.85)
    rgb = mix(rgb, (0.85, 0.95, 1.0), net(m, 120, 0.007, seed=36) * 0.9)
    rgb = sheen(m, rgb, 0.2, (0.9, 0.97, 1.0))
    return finish(m, rgb)


def divine(m):
    gold = (1.0, 0.66, 0.0)  # no blue: a gold that can't drift into skin tone
    # Ice-blue pearl, not white: a near-white skin packed to JPEG tripped the classifier
    rgb = coat(m, (0.66, 0.76, 0.98), (0.78, 0.85, 1.0), (0.62, 0.72, 0.98), hard_fins=True)
    rgb = pearl(m, rgb, 0.3, 0.1, 0.6)
    lines = smoothstep(0.5, 0.6, scale_edges(m, 0.05, 0.06))
    rgb = mix(rgb, gold, body_only(m, lines))
    crown = smoothstep(0.76, 0.775, m.up) * (1 - m.fin)
    rgb = mix(rgb, gold, crown)
    rim = smoothstep(0.5, 0.6, m.fin * smoothstep(3.6, 4.2, m.r2))
    rgb = mix(rgb, gold, rim)
    rgb = sheen(m, rgb, 0.25, (0.94, 0.97, 1.0))
    return finish(m, rgb, detail=0.8)


def aurora(m):
    rgb = coat(m, (0.03, 0.10, 0.16), (0.06, 0.16, 0.26), (0.04, 0.12, 0.22))
    flow = m.ez * 2.2 + (fbm(m, 3, 37) - 0.5) * 4 + m.y * 1.5
    curtain = 0.5 + 0.5 * np.sin(flow * 3.2)
    hue = 0.36 + 0.42 * (0.5 + 0.5 * np.sin(m.y * 6 + fbm(m, 2, 38) * 5))
    color = hsv_to_rgb(np.stack([hue, np.full_like(hue, 0.8), np.ones_like(hue)], -1))
    veil = smoothstep(0.55, 0.95, curtain) * smoothstep(0.25, 0.7, m.up)
    rgb = mix(rgb, color, veil * 0.9)
    rgb = mix(rgb, (0.85, 1.0, 0.95), speckle(m, 170, 0.86, seed=39) * 0.7)
    return finish(m, rgb, detail=0.8)


def thunder(m):
    rgb = coat(m, (0.18, 0.21, 0.30), (0.46, 0.52, 0.64), (0.14, 0.17, 0.26))
    ridge = 1 - np.abs(fbm(m, 6, 40) * 2 - 1)
    bolt = smoothstep(0.93, 0.975, ridge)
    rgb = mix(rgb, (0.30, 0.55, 1.0), glow_halo(bolt, 5) * 0.7)
    rgb = mix(rgb, (0.85, 0.95, 1.0), bolt)
    return finish(m, rgb, detail=0.9)


def exotic(m):
    rgb = coat(m, (0.08, 0.36, 1.0), (0.10, 0.62, 1.0), (1.0, 0.42, 0.06))
    rgb = mix(rgb, (1.0, 0.86, 0.05), body_only(m, spots(m, 80, 0.026, seed=41)))
    head = smoothstep(0.35, 0.2, m.y) * stripes(m, 26, 0.3, wobble=0.1, seed=42)
    rgb = mix(rgb, (0.35, 1.0, 0.25), body_only(m, head))
    return finish(m, rgb)


def prismatic(m):
    hue = (m.y * 1.6 + m.ez * 0.25 + m.nrm[..., 0] * 0.08) % 1
    rgb = hsv_to_rgb(np.stack([hue, np.full_like(hue, 0.72), np.full_like(hue, 1.0)], -1))
    rgb = pearl(m, rgb, 0.22, 0.2, 0.55)
    rgb = mix(rgb, (1.0, 1.0, 1.0), speckle(m, 150, 0.84, seed=43) * 0.8)
    return finish(m, rgb, detail=0.7)


def nebula(m):
    rgb = coat(m, (0.04, 0.03, 0.10), (0.06, 0.05, 0.14), (0.05, 0.04, 0.12))
    a, b = fbm(m, 3, 44), fbm(m, 5, 45)
    cloud = smoothstep(0.48, 0.75, a)
    hue = 0.62 + 0.2 * (b - 0.5) * 2  # blue to violet
    color = hsv_to_rgb(np.stack([hue % 1, np.full_like(hue, 0.75), np.full_like(hue, 0.95)], -1))
    rgb = mix(rgb, color, cloud * 0.8)
    rgb = mix(rgb, (0.10, 0.85, 0.85), smoothstep(0.62, 0.8, b) * cloud * 0.6)
    stars = speckle(m, 220, 0.86, seed=46)
    rgb = mix(rgb, (1.0, 1.0, 1.0), stars)
    rgb = mix(rgb, (0.75, 0.85, 1.0), glow_halo(speckle(m, 60, 0.9, seed=47), 3) * 0.6)
    return finish(m, rgb, detail=0.6)


def void(m):
    rgb = coat(m, (0.03, 0.02, 0.06), (0.06, 0.03, 0.10), (0.05, 0.02, 0.09))
    cracks = net(m, 90, 0.008, seed=48)
    rgb = mix(rgb, (0.38, 0.10, 0.80), glow_halo(cracks, 6) * 0.8)
    rgb = mix(rgb, (0.82, 0.55, 1.0), cracks)
    rim = smoothstep(0.55, 0.15, np.abs(m.nrm[..., 0])) * (1 - m.fin)
    rgb = mix(rgb, (0.50, 0.20, 0.95), rim * 0.35)
    rgb = mix(rgb, (0.62, 0.30, 1.0), m.fin * smoothstep(3.6, 6, m.r2))
    return finish(m, rgb, detail=0.6)


def abyss_ink(m):
    rgb = coat(m, (0.06, 0.04, 0.10), (0.16, 0.10, 0.24), (0.32, 0.16, 0.56))
    s = spots(m, 70, 0.02, seed=49, vary=0.5)
    s2 = spots(m, 60, 0.012, seed=50, vary=0.5)
    rgb = mix(rgb, (0.50, 0.30, 1.0), glow_halo(s, 6) * 0.6)
    rgb = mix(rgb, (0.75, 0.55, 1.0), s)
    rgb = mix(rgb, (0.40, 0.90, 1.0), s2)
    return finish(m, rgb, detail=0.7)


def sunken_gold(m):
    rgb = coat(m, (0.86, 0.62, 0.12), (1.0, 0.82, 0.30), (0.74, 0.50, 0.08))
    rgb = mix(rgb, (0.55, 0.36, 0.05), (1 - scales(m, 0.04)) * 0 + smoothstep(0.9, 0.98, scales(m, 0.04)) * 0.8)
    patina = smoothstep(0.55, 0.7, fbm(m, 6, 51)) * (smoothstep(0.6, 0.9, m.y) + m.fin * 0.6)
    rgb = mix(rgb, (0.20, 0.62, 0.52), np.clip(patina, 0, 1) * 0.85)
    rgb = sheen(m, rgb, 0.45, (1.0, 0.95, 0.70))
    return finish(m, rgb, detail=0.7)


def drowned_pearl(m):
    rgb = coat(m, (0.90, 0.92, 1.0), SNOW, (0.80, 0.86, 1.0))
    n = m.nrm
    hue = 0.45 + 0.28 * (0.5 + 0.5 * np.sin(n[..., 0] * 3.0 + n[..., 2] * 2.0 + m.y * 4))  # teal to violet, never pink
    film = hsv_to_rgb(np.stack([hue % 1, np.full_like(hue, 0.42), np.ones_like(hue)], -1))
    rgb = mix(rgb, film, 0.55)
    growth = stripes(m, 34, 0.1, wobble=0.6, slant=0.6, seed=52)
    rgb = mix(rgb, (0.70, 0.78, 0.95), growth * 0.4)
    rgb = sheen(m, rgb, 0.22, (1, 1, 1))
    return finish(m, rgb, detail=0.6)


RECIPES = {
    "Mint": mint,
    "Sunset": sunset,
    "Ink": ink,
    "Sand": sand,
    "Ember": ember,
    "Lilac": lilac,
    "Moss": moss,
    "Ocean": ocean,
    "Tiger": tiger,
    "Bumblebee": bumblebee,
    "Tetra": tetra,
    "Leopard": leopard,
    "Lunar": lunar,
    "Glowspot": glowspot,
    "Tidepool": tidepool,
    "Diamond": diamond,
    "Magma": magma,
    "Glacier": glacier,
    "Divine": divine,
    "Aurora": aurora,
    "Thunder": thunder,
    "Exotic": exotic,
    "Prismatic": prismatic,
    "Nebula": nebula,
    "Void": void,
    "AbyssInk": abyss_ink,
    "SunkenGold": sunken_gold,
    "DrownedPearl": drowned_pearl,
}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    only = None
    for a in sys.argv[1:]:
        if a.startswith("--only="):
            only = set(a.split("=", 1)[1].split(","))
    maps, out = pathlib.Path(args[0]), pathlib.Path(args[1])
    names = args[2:] or [p.stem for p in sorted(maps.glob("*.npz"))]
    eyes = json.loads((HERE / "eyes.json").read_text())
    for name in names:
        fish = Fish(name, maps / f"{name}.npz", eyes.get(name, {}).get("picks", []))
        folder = out / name
        folder.mkdir(parents=True, exist_ok=True)
        dbg = fish.color.copy()
        dbg = mix(dbg, (1, 0, 1), fish.keep * 0.8)
        dbg = mix(dbg, (0, 1, 0), fish.fin * 0.5)
        Image.fromarray((np.clip(dbg, 0, 1) * 255).astype(np.uint8)).save(folder / "eyes_debug.png")
        for shade, recipe in RECIPES.items():
            if only and shade not in only:
                continue
            rgb = recipe(fish)
            Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).save(folder / f"{shade}.png")
        print(f"[shades] {name}: {len(RECIPES) if not only else len(only)} skins")


if __name__ == "__main__":
    main()
