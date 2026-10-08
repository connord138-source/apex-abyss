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

Writes, per fish, <out_dir>/<Fish>/: <Shade>.png (color, 1024, what Roblox takes),
<Shade>_emit.png (what glows, RGB; the importer turns it into the emissive mask),
<Shade>_metal.png and <Shade>_rough.png where a shade has its own, finish_<name>.png
(the roughness every other shade with that finish shares: matte, satin, gloss,
mirror), skins.json (which maps each shade has) and eyes_debug.png.
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
        self.eyes = self._eyes(picks)
        self.lure = None
        keep = np.maximum(keep, self.eyes)
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
            self.lure = np.clip(ndimage.gaussian_filter((lure & self.cov).astype(np.float32), 0.8), 0, 1)
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


def fbm_at(p, freq, seed, octaves=4):
    out, amp, total = 0, 1.0, 0.0
    for o in range(octaves):
        out = out + amp * value_noise(p, freq * 2**o, seed + o)
        total += amp
        amp *= 0.5
    return out / total


def fbm(m: Fish, freq, seed, octaves=4):
    return fbm_at(m.p, freq, seed, octaves)


def body_coords(m: Fish, girth=0.12):
    """The body as if every fish were equally round: along it in body lengths, round
    it in a fixed girth. Noise drawn here keeps its scale on a thin eel."""
    return np.stack([m.ex * girth, m.y, m.ez * girth], -1).astype(np.float32)


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


# ---------------------------------------------------------------------------
# Finishing a skin: color, glow, metal and roughness
# ---------------------------------------------------------------------------

# Roughness for each finish (per fish, shared by every shade with that finish)
FINISHES = {"matte": 0.86, "satin": 0.56, "gloss": 0.3, "mirror": 0.14}


def done(m: Fish, rgb, finish="satin", emit=None, metal=None, rough=None, detail=1.3):
    """A finished skin: the painted strokes back on, the eyes, teeth, mouth and lure
    as they were, plus its glow (RGB), metal (0..1) and own roughness, if any. The
    Angler's lure always glows."""
    rgb = rgb * (1 + detail * m.fine)[..., None]
    rgb = np.clip(rgb, 0, 1)
    rgb = mix(rgb, m.color, m.keep)
    rgb[~m.cov] = m.color[~m.cov]
    if emit is not None:
        emit = np.clip(np.asarray(emit, np.float32), 0, 1) * (1 - m.keep)[..., None]
    if m.lure is not None:
        lure = m.color * m.lure[..., None]
        emit = lure if emit is None else np.maximum(emit, lure)
    if emit is not None:
        emit = emit * m.cov[..., None]
    if metal is not None:
        metal = np.clip(metal, 0, 1) * (1 - m.keep) * m.cov
    if rough is not None:
        rough = np.clip(rough + 0.12 * m.fine, 0.05, 1)
        rough = rough * (1 - m.eyes) + 0.12 * m.eyes
    return {"rgb": rgb, "emit": emit, "metal": metal, "rough": rough, "finish": finish}


def finish_map(m: Fish, finish):
    """A finish's roughness map: its level, the painted detail as a little variation,
    wet eyes."""
    rough = np.clip(FINISHES[finish] + 0.12 * m.fine, 0.05, 1)
    rough = rough * (1 - m.eyes) + 0.12 * m.eyes
    rough[~m.cov] = 1.0
    return rough


# ---------------------------------------------------------------------------
# More patterns (all in 3D on the body)
# ---------------------------------------------------------------------------


def rings(m: Fish, count, rmin, rmax, width, seed):
    """Bubble rings: circles of many sizes scattered over the body."""
    d1, _, i, n = worley(m, count, seed)
    rng = np.random.default_rng(seed + 300)
    r = (rmin + (rmax - rmin) * rng.random(n))[i]
    return smoothstep(width, width * 0.3, np.abs(d1 - r))


def contours(m: Fish, freq, lines, seed, warp=0.0):
    """Topographic lines of a noise field: distance (0..0.5) to the nearest line."""
    f = fbm(m, freq, seed)
    if warp:
        f = f + warp * (fbm(m, freq * 2.3, seed + 1) - 0.5)
    t = (f * lines) % 1.0
    return np.abs(t - 0.5)


def photophores(m: Fish, rows, spacing, radius):
    """Rows of glowing dots along the flanks, like a lanternfish's light organs."""
    yy = m.y / spacing
    fy = (yy - np.floor(yy) - 0.5) * spacing
    out = np.zeros_like(m.y)
    for row in rows:
        dz = (m.ez - row) * 0.11
        d = np.sqrt(fy * fy + dz * dz)
        out = np.maximum(out, smoothstep(radius, radius * 0.55, d))
    span = smoothstep(0.12, 0.2, m.y) * smoothstep(0.9, 0.8, m.y)
    return out * span * (1 - m.fin)


def skeleton(m: Fish):
    """An x-ray skeleton drawn on the flanks: skull, spine, ribs, spines and fin rays."""
    body = 1 - m.fin
    spine = smoothstep(0.05, 0.02, np.abs(m.ez - 0.02)) * smoothstep(0.17, 0.22, m.y) * smoothstep(0.93, 0.87, m.y)
    spine *= smoothstep(0.15, 0.35, 0.5 + 0.5 * np.cos(m.y * 2 * np.pi / 0.032))
    ribs = np.zeros_like(m.y)
    for yi in np.arange(0.25, 0.64, 0.042):
        yr = yi + 0.05 * m.ez * m.ez
        ribs = np.maximum(ribs, smoothstep(0.009, 0.0035, np.abs(m.y - yr)) * smoothstep(0.08, -0.05, m.ez) * smoothstep(-0.85, -0.65, m.ez))
    for yi in np.arange(0.24, 0.86, 0.036):
        yr = yi - 0.04 * m.ez
        ribs = np.maximum(ribs, 0.8 * smoothstep(0.006, 0.0025, np.abs(m.y - yr)) * smoothstep(0.08, 0.2, m.ez) * smoothstep(0.75, 0.55, m.ez))
    d = np.sqrt(((m.y - 0.12) / 0.095) ** 2 + (m.ez / 0.72) ** 2)
    skull = smoothstep(0.07, 0.02, np.abs(d - 1)) * smoothstep(0.25, 0.2, m.y)
    orbit = smoothstep(0.05, 0.015, np.abs(np.sqrt(((m.y - 0.09) / 0.03) ** 2 + ((m.ez - 0.2) / 0.2) ** 2) - 1))
    rays = m.fin * smoothstep(0.86, 0.96, 0.5 + 0.5 * np.cos(m.theta * 18 + m.y * 20))
    return np.clip((spine + ribs) * body + (skull + orbit) * body + rays, 0, 1)


def flame_field(m: Fish, seed):
    warp = (fbm(m, 6, seed) - 0.5) * 0.5
    return m.up + 0.2 * np.sin(m.y * 46 + warp * 9) + warp * 0.6


# ---------------------------------------------------------------------------
# The shades
# ---------------------------------------------------------------------------

# Cool whites and pale tones (never warm: a warm pale on loose atlas pieces reads as
# skin), and golds and oranges with no blue in them (a blue-tinged gold blended toward
# white is beige, inside the skin-tone rules)
SNOW = (0.92, 0.95, 1.0)
INKY = (0.05, 0.05, 0.08)


def board(m: Fish, color):
    return np.broadcast_to(C(*color), m.color.shape).copy()


def mint(m):  # Seafoam: foam rings over sea-green
    rgb = coat(m, (0.06, 0.50, 0.48), (0.30, 0.78, 0.70), (0.04, 0.38, 0.42))
    foam = rings(m, 420, 0.008, 0.026, 0.0045, seed=11)
    froth = foam * (0.35 + 0.65 * smoothstep(0.35, 0.85, m.up))
    rgb = mix(rgb, (0.74, 1.0, 0.92), froth)
    rgb = mix(rgb, (0.02, 0.28, 0.32), speckle(m, 120, 0.8, seed=12) * 0.45 * (1 - m.fin))
    return done(m, rgb, "gloss")


def sunset(m):
    along = smoothstep(0.05, 0.95, m.y)
    rgb = mix(board(m, (1.0, 0.80, 0.0)), (0.95, 0.26, 0.0), along)
    rgb = mix(rgb, (1.0, 0.90, 0.20), smoothstep(0.45, 0.15, m.up) * 0.7)
    horizon = 0.5 + 0.5 * np.sin(m.ez * 7 + (fbm(m, 4, 13) - 0.5) * 6)
    rgb = mix(rgb, (0.74, 0.06, 0.22), smoothstep(0.75, 0.95, horizon) * 0.6 * (1 - m.fin))
    rgb = mix(rgb, (0.78, 0.04, 0.24), m.fin)
    return done(m, rgb, "gloss")


def ink(m):  # Ink wash: pigment pooling at the edges, a glowing lateral line
    rgb = coat(m, (0.34, 0.42, 0.60), (0.48, 0.56, 0.70), (0.28, 0.34, 0.54))
    for k, (col, cut) in enumerate((((0.16, 0.18, 0.44), 0.5), ((0.05, 0.06, 0.22), 0.58))):
        f = fbm(m, 4 + 2 * k, 60 + k)
        rgb = mix(rgb, col, smoothstep(cut, cut + 0.04, f) * 0.88)
        rgb = mix(rgb, (0.02, 0.02, 0.10), smoothstep(0.03, 0.0, np.abs(f - cut - 0.01)) * 0.75)
    lateral = (
        smoothstep(0.07, 0.02, np.abs(m.ez - 0.05))
        * smoothstep(0.08, 0.2, m.y)
        * smoothstep(0.95, 0.8, m.y)
        * (1 - m.fin)
    )
    glow = C(0.45, 0.85, 1.0)
    rgb = mix(rgb, glow, lateral)
    return done(m, rgb, "matte", emit=lateral[..., None] * glow)


def sand(m):  # A sandbar: ripple marks, shell grit and grey-green weed shadows
    rgb = coat(m, (0.58, 0.60, 0.50), (0.74, 0.78, 0.78), (0.50, 0.52, 0.44))
    ripple = stripes(m, 26, 0.22, wobble=0.55, slant=0.35, seed=18, edge=0.12)
    rgb = mix(rgb, (0.40, 0.42, 0.34), body_only(m, ripple) * 0.75)
    crest = stripes(m, 26, 0.08, wobble=0.55, slant=0.35, seed=18, edge=0.06)
    rgb = mix(rgb, (0.82, 0.86, 0.88), body_only(m, crest * (1 - ripple)) * 0.4)
    blot = smoothstep(0.55, 0.62, fbm(m, 7, 15)) * smoothstep(0.3, 0.6, m.up)
    rgb = mix(rgb, (0.30, 0.33, 0.26), blot * 0.7)
    rgb = mix(rgb, (0.22, 0.24, 0.20), speckle(m, 110, 0.74, seed=16) * 0.7)
    rgb = mix(rgb, (0.80, 0.84, 0.90), speckle(m, 140, 0.8, seed=17) * 0.6)
    return done(m, rgb, "matte")


def ember(m):  # Flames licking up from the belly over a charcoal back
    f = flame_field(m, 18)
    flame = smoothstep(0.64, 0.56, f)
    heat = np.clip((0.62 - f) / 0.5, 0, 1)
    fire = mix(board(m, (1.0, 0.86, 0.0)), (1.0, 0.38, 0.0), smoothstep(0.08, 0.45, heat))
    fire = mix(fire, (0.78, 0.04, 0.0), smoothstep(0.5, 0.95, heat))
    rgb = mix(board(m, (0.08, 0.06, 0.09)), fire, flame)
    tips = smoothstep(0.06, 0.0, np.abs(f - 0.6)) * flame
    return done(m, rgb, "satin", emit=tips[..., None] * C(1.0, 0.55, 0.05))


def lilac(m):
    rgb = coat(m, (0.52, 0.36, 0.86), (0.66, 0.56, 0.94), (0.40, 0.24, 0.78))
    dots = spots(m, 160, 0.02, seed=19, vary=0.25)
    rgb = mix(rgb, (0.84, 0.86, 1.0), dots * 0.9)
    rgb = mix(rgb, (0.28, 0.16, 0.60), m.fin * stripes(m, 40, 0.5, seed=20) * 0.5)
    return done(m, rgb, "gloss")


def moss(m):  # Lichen patches with bright rims, algae hanging from the back
    rgb = coat(m, (0.10, 0.24, 0.10), (0.30, 0.42, 0.18), (0.12, 0.26, 0.10))
    f = fbm(m, 7, 21)
    patch = smoothstep(0.55, 0.6, f)
    rgb = mix(rgb, (0.50, 0.66, 0.10), patch * 0.85)
    rgb = mix(rgb, (0.78, 0.92, 0.24), smoothstep(0.02, 0.0, np.abs(f - 0.57)))
    rgb = mix(rgb, (0.30, 0.42, 0.04), speckle(m, 150, 0.8, seed=22) * patch)
    hang = smoothstep(0.62, 0.7, value_noise(m.p * np.array([1.0, 1.0, 0.1], np.float32), 50, 23)) * smoothstep(0.3, 0.9, m.up)
    rgb = mix(rgb, (0.04, 0.12, 0.04), hang * 0.8)
    return done(m, rgb, "matte")


def ocean(m):
    rgb = coat(m, (0.08, 0.32, 0.82), (0.34, 0.56, 0.92), (1.0, 0.82, 0.0))
    swoosh = smoothstep(0.18, 0.05, np.abs(m.ez - 0.35 - 0.25 * np.sin(m.y * 5.5))) * smoothstep(0.15, 0.3, m.y)
    rgb = mix(rgb, (0.03, 0.05, 0.14), body_only(m, swoosh))
    rgb = mix(rgb, (1.0, 0.82, 0.0), smoothstep(0.78, 0.9, m.y))
    return done(m, rgb, "gloss")


def tiger(m):
    rgb = coat(m, (1.0, 0.42, 0.0), SNOW, (0.95, 0.34, 0.0), soft=0.025, hard_fins=True)
    t = stripes(m, 11, 0.24, wobble=0.35, slant=0.25, seed=23) * smoothstep(0.15, 0.55, m.up)
    rgb = mix(rgb, INKY, t)
    edge = smoothstep(0.03, 0.0, np.abs(m.up - 0.5)) * (1 - m.fin)
    rgb = mix(rgb, INKY, edge * 0.85)
    return done(m, rgb, "satin")


def bumblebee(m):
    rgb = coat(m, (1.0, 0.80, 0.0), (1.0, 0.86, 0.12), INKY)
    b = bands(m, (0.32, 0.52, 0.72), 0.06, wobble=0.03, seed=24)
    rgb = mix(rgb, INKY, body_only(m, b))
    rgb = rgb * (0.9 + 0.2 * speckle(m, 260, 0.6, seed=124))[..., None]  # fuzz
    return done(m, rgb, "matte")


def tetra(m):
    rgb = coat(m, (0.05, 0.10, 0.28), (0.52, 0.60, 0.80), (0.42, 0.55, 0.85))
    rear = smoothstep(0.42, 0.55, m.y) * smoothstep(0.62, 0.35, m.up)
    rgb = mix(rgb, (0.95, 0.06, 0.04), body_only(m, rear))
    stripe = smoothstep(0.16, 0.06, np.abs(m.ez - 0.18)) * smoothstep(0.1, 0.22, m.y) * smoothstep(0.92, 0.75, m.y)
    stripe = body_only(m, stripe)
    rgb = mix(rgb, (0.12, 0.98, 1.0), stripe)
    return done(m, rgb, "gloss", emit=stripe[..., None] * C(0.1, 0.9, 1.0))


def leopard(m):
    rgb = coat(m, (0.98, 0.70, 0.0), (1.0, 0.86, 0.30), (0.90, 0.58, 0.0))
    rgb = mix(rgb, (0.86, 0.44, 0.0), spots(m, 70, 0.03, seed=25) * 0.6)
    rgb = mix(rgb, INKY, rosettes(m, 70, 0.045, seed=25))
    rgb = mix(rgb, INKY, spots(m, 220, 0.009, seed=26) * smoothstep(0.3, 0.6, m.up))
    return done(m, rgb, "satin")


def rust(m):  # A shipwreck's iron: bare gunmetal (metal) under rough rust
    rgb = coat(m, (0.30, 0.33, 0.37), (0.40, 0.43, 0.47), (0.24, 0.26, 0.30), hard_fins=True)
    f = fbm(m, 6, 70)
    rusty = smoothstep(0.515, 0.525, f)
    rgb = mix(rgb, (0.12, 0.04, 0.0), smoothstep(0.012, 0.0, np.abs(f - 0.52)))  # the corroded edge
    rgb = mix(rgb, (0.56, 0.20, 0.0), rusty)
    rgb = mix(rgb, (0.36, 0.10, 0.0), smoothstep(0.6, 0.62, f))
    rgb = mix(rgb, (0.14, 0.05, 0.0), speckle(m, 160, 0.78, seed=71) * rusty * 0.8)
    rivets = spots(m, 90, 0.008, seed=72) * (1 - rusty) * (1 - m.fin)
    rgb = mix(rgb, (0.62, 0.66, 0.72), rivets)
    metal = (1 - rusty) * 0.95
    rough = 0.42 * (1 - rusty) + 0.92 * rusty
    return done(m, rgb, "satin", metal=metal, rough=rough)


def toxic(m):  # Poison dart frog: acid lime and gloss black blotches
    rgb = coat(m, (0.40, 0.95, 0.0), (0.70, 1.0, 0.22), (0.20, 0.70, 0.0))
    blot = smoothstep(0.56, 0.575, fbm(m, 5, 73))
    rgb = mix(rgb, INKY, blot)
    rgb = mix(rgb, (0.10, 0.55, 1.0), spots(m, 140, 0.007, seed=74) * blot)
    return done(m, rgb, "gloss")


def lunar(m):  # The moon's face: silver-blue regolith, dark maria, craters, moonlit glow
    rgb = coat(m, (0.50, 0.56, 0.68), (0.62, 0.68, 0.80), (0.40, 0.46, 0.62))
    maria = body_only(m, smoothstep(0.54, 0.6, fbm(m, 4, 27)))
    rgb = mix(rgb, (0.22, 0.26, 0.40), maria * 0.85)
    d1, _, i, n = worley(m, 70, 127)
    rng = np.random.default_rng(128)
    radius = (0.009 + 0.032 * rng.random(n) ** 2)[i]
    bowl = body_only(m, smoothstep(radius, radius * 0.55, d1))
    rim = body_only(m, smoothstep(radius * 0.3 + 0.002, 0.0, np.abs(d1 - radius)))
    rgb = mix(rgb, (0.28, 0.32, 0.46), bowl * 0.55)
    rgb = mix(rgb, (0.86, 0.90, 0.98), rim * 0.85)
    rgb = mix(rgb, (0.80, 0.84, 0.94), speckle(m, 160, 0.8, seed=28) * 0.35)
    crown = smoothstep(0.72, 0.95, m.up)
    emit = crown[..., None] * C(0.30, 0.42, 0.75) * 0.45 + rim[..., None] * C(0.45, 0.55, 0.85) * 0.3
    return done(m, rgb, "matte", emit=emit, detail=0.9)


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
    halo = glow_halo(s, 6)
    rgb = mix(rgb, (0.10, 0.80, 0.95), halo * 0.55)
    rgb = mix(rgb, (0.75, 1.0, 1.0), s)
    edge = m.fin * smoothstep(3.6, 5.5, m.r2)
    rgb = mix(rgb, (0.20, 0.95, 1.0), edge * 0.8)
    emit = (s[..., None] * C(0.6, 1.0, 1.0)) + (halo * 0.35)[..., None] * C(0.1, 0.8, 0.95) + (edge * 0.6)[..., None] * C(0.2, 0.9, 1.0)
    return done(m, rgb, "gloss", emit=emit, detail=0.8)


def tidepool(m):  # Ripples spreading from a few drops, teal into violet
    w = smoothstep(0.2, 0.85, m.up)
    rgb = mix(board(m, (0.36, 0.22, 0.76)), (0.02, 0.50, 0.58), w)
    rgb = mix(rgb, (0.08, 0.32, 0.66), m.fin)
    d1, _, _, _ = worley(m, 6, 30)
    ripple = 0.5 + 0.5 * np.cos(d1 * 2 * np.pi / 0.032)
    rings_ = smoothstep(0.82, 0.95, ripple) * smoothstep(0.22, 0.02, d1)
    rgb = mix(rgb, (0.55, 1.0, 0.95), rings_ * 0.85)
    rgb = mix(rgb, (0.75, 1.0, 1.0), speckle(m, 150, 0.84, seed=31) * 0.5)
    return done(m, rgb, "gloss")


def mandarin(m):  # The mandarinfish's maze: orange contour lines edged green on blue
    rgb = coat(m, (0.04, 0.22, 0.82), (0.08, 0.40, 0.92), (1.0, 0.45, 0.0), hard_fins=True)
    d = contours(m, 3.5, 12, seed=75, warp=0.4)
    line = body_only(m, smoothstep(0.15, 0.11, d))
    edge = body_only(m, smoothstep(0.21, 0.17, d)) * (1 - line)
    rgb = mix(rgb, (0.10, 0.80, 0.30), edge)
    rgb = mix(rgb, (1.0, 0.48, 0.0), line)
    rgb = mix(rgb, (0.04, 0.22, 0.82), m.fin * stripes(m, 40, 0.3, seed=76))
    return done(m, rgb, "gloss")


def lanternfish(m):  # Navy back, mirror-silver flanks, rows of glowing light organs
    rgb = coat(m, (0.06, 0.09, 0.18), (0.62, 0.68, 0.80), (0.08, 0.11, 0.20), soft=0.12)
    rgb = sheen(m, rgb, 0.5, (0.85, 0.92, 1.0))
    pho = photophores(m, (-0.66, -0.44, -0.18), 0.04, 0.011)
    halo = glow_halo(pho, 3)
    rgb = mix(rgb, (0.20, 0.42, 0.85), halo * 0.5)
    rgb = mix(rgb, (0.6, 0.88, 1.0), pho)
    silver = smoothstep(0.55, 0.3, m.up) * (1 - m.fin)
    emit = pho[..., None] * C(0.5, 0.85, 1.0) + (halo * 0.3)[..., None] * C(0.2, 0.45, 0.9)
    return done(m, rgb, "gloss", emit=emit, metal=silver * 0.5)


def diamond(m):
    value, edge = cells(m, 340, seed=31)
    base = mix(board(m, (0.62, 0.78, 0.96)), SNOW, value)
    rgb = mix(base, (1.0, 1.0, 1.0), smoothstep(0.012, 0.004, edge))
    fire = speckle(m, 150, 0.83, seed=32)
    hue = (m.y * 3 + m.ez) % 1
    rgb = mix(rgb, hsv_to_rgb(np.stack([hue, np.full_like(hue, 0.6), np.ones_like(hue)], -1)), fire * 0.7)
    rgb = sheen(m, rgb, 0.25, (1, 1, 1))
    return done(m, rgb, "mirror", detail=0.6)


def magma(m):
    rgb = coat(m, (0.10, 0.08, 0.08), (0.18, 0.12, 0.10), (0.12, 0.08, 0.07))
    cracks = net(m, 150, 0.010, seed=33)
    halo = glow_halo(cracks, 5)
    rgb = mix(rgb, (0.85, 0.18, 0.0), halo * 0.75)
    rgb = mix(rgb, (1.0, 0.55, 0.0), cracks)
    hot = cracks * smoothstep(0.6, 1, fbm(m, 9, 34))
    rgb = mix(rgb, (1.0, 0.88, 0.25), hot)
    emit = cracks[..., None] * C(1.0, 0.45, 0.0) + (halo * 0.5)[..., None] * C(0.9, 0.15, 0.0) + hot[..., None] * C(1.0, 0.8, 0.2)
    return done(m, rgb, "satin", emit=emit, detail=0.7)


def glacier(m):  # Ice in strata: layers of teal and cyan, a frosted cap, rime
    w = (fbm(m, 5, 35) - 0.5) * 0.18
    layer = (m.up + w) * 7
    idx = np.floor(layer).astype(int) % 4
    palette = np.array([(0.03, 0.28, 0.42), (0.08, 0.50, 0.64), (0.24, 0.70, 0.84), (0.50, 0.84, 0.95)], np.float32)
    rgb = palette[idx]
    seam = smoothstep(0.06, 0.0, layer - np.floor(layer))
    rgb = mix(rgb, (0.80, 0.95, 1.0), seam * 0.7)
    cap = smoothstep(0.82, 0.86, m.up + w * 0.5) * (1 - m.fin)
    rgb = mix(rgb, (0.80, 0.92, 1.0), cap)
    rgb = mix(rgb, (0.46, 0.82, 0.94), m.fin)
    rgb = mix(rgb, (0.9, 0.97, 1.0), speckle(m, 180, 0.84, seed=36) * 0.7)
    rgb = sheen(m, rgb, 0.2, (0.9, 0.97, 1.0))
    return done(m, rgb, "gloss")


def xray(m):  # A glowing skeleton seen through a dark body
    rgb = coat(m, (0.03, 0.07, 0.16), (0.05, 0.12, 0.24), (0.04, 0.10, 0.22))
    scan = 0.15 * (0.5 + 0.5 * np.sin(m.ez * 80))  # faint scanlines
    rgb = mix(rgb, (0.05, 0.18, 0.30), scan)
    bones = skeleton(m)
    halo = glow_halo(bones, 6)
    # Electric blue bones in a wide inner glow, not thin near-white lines on black:
    # those scored high on the moderation classifier (screen, 2026-10-08)
    rgb = mix(rgb, (0.15, 0.45, 1.0), halo * 0.65)
    rgb = mix(rgb, (0.45, 0.72, 1.0), bones)
    emit = bones[..., None] * C(0.35, 0.6, 1.0) + (halo * 0.3)[..., None] * C(0.15, 0.3, 1.0)
    emit = emit + ndimage.gaussian_filter(emit, (4, 4, 0)) * 1.6
    return done(m, rgb, "satin", emit=emit, detail=0.6)


def divine(m):
    gold = (1.0, 0.66, 0.0)
    rgb = coat(m, (0.66, 0.76, 0.98), (0.78, 0.85, 1.0), (0.62, 0.72, 0.98), hard_fins=True)
    rgb = pearl(m, rgb, 0.3, 0.1, 0.6)
    lines = smoothstep(0.5, 0.6, scale_edges(m, 0.05, 0.06))
    gilt = body_only(m, lines)
    crown = smoothstep(0.76, 0.775, m.up) * (1 - m.fin)
    rim = smoothstep(0.5, 0.6, m.fin * smoothstep(3.6, 4.2, m.r2))
    gilded = np.clip(gilt + crown + rim, 0, 1)
    rgb = mix(rgb, gold, gilded)
    rgb = sheen(m, rgb, 0.25, (0.94, 0.97, 1.0))
    return done(m, rgb, "gloss", metal=gilded * 0.7, detail=0.8)


def aurora(m):
    rgb = coat(m, (0.03, 0.10, 0.16), (0.06, 0.16, 0.26), (0.04, 0.12, 0.22))
    flow = m.ez * 2.2 + (fbm(m, 3, 37) - 0.5) * 4 + m.y * 1.5
    curtain = 0.5 + 0.5 * np.sin(flow * 3.2)
    hue = 0.36 + 0.42 * (0.5 + 0.5 * np.sin(m.y * 6 + fbm(m, 2, 38) * 5))
    color = hsv_to_rgb(np.stack([hue, np.full_like(hue, 0.8), np.ones_like(hue)], -1))
    veil = smoothstep(0.55, 0.95, curtain) * smoothstep(0.25, 0.7, m.up)
    rgb = mix(rgb, color, veil * 0.9)
    stars = speckle(m, 170, 0.86, seed=39)
    rgb = mix(rgb, (0.85, 1.0, 0.95), stars * 0.7)
    emit = color * (veil * 0.8)[..., None] + stars[..., None] * 0.5
    return done(m, rgb, "satin", emit=emit, detail=0.8)


def thunder(m):
    rgb = coat(m, (0.16, 0.19, 0.30), (0.26, 0.31, 0.46), (0.12, 0.15, 0.26))
    ridge = 1 - np.abs(fbm_at(body_coords(m), 6, 40) * 2 - 1)
    lo, hi = np.percentile(ridge[m.cov], [93.5, 97.5])  # forked lines, never blotches
    bolt = smoothstep(lo, hi, ridge)
    halo = glow_halo(bolt, 5)
    # Violet-blue bolts: near-white lines on black trip the moderation classifier
    rgb = mix(rgb, (0.38, 0.32, 1.0), halo * 0.7)
    rgb = mix(rgb, (0.72, 0.68, 1.0), bolt)
    emit = bolt[..., None] * C(0.55, 0.48, 1.0) + (halo * 0.45)[..., None] * C(0.35, 0.25, 1.0)
    return done(m, rgb, "satin", emit=emit, detail=0.9)


def exotic(m):  # A parrotfish mosaic: every scale its own reef color, edged in cobalt
    d1, d2, i, n = worley(m, 240, 41)
    rng = np.random.default_rng(141)
    palette = np.array(
        [(0.0, 0.85, 0.72), (0.42, 1.0, 0.08), (0.62, 0.16, 1.0), (1.0, 0.76, 0.0), (0.08, 0.50, 1.0)],
        np.float32,
    )
    rgb = palette[rng.integers(0, len(palette), n)][i]
    rgb = mix(rgb, (0.03, 0.10, 0.48), body_only(m, smoothstep(0.012, 0.004, d2 - d1)))
    face = smoothstep(0.22, 0.14, m.y) * (1 - m.fin)
    rgb = mix(rgb, (1.0, 0.70, 0.0), face)
    rgb = mix(rgb, (0.0, 0.80, 0.72), face * stripes(m, 32, 0.3, wobble=0.2, seed=42))
    fins = mix(board(m, (0.62, 0.16, 1.0)), (0.0, 0.85, 0.72), stripes(m, 40, 0.35, seed=43))
    rgb = mix(rgb, fins, smoothstep(0.45, 0.55, m.fin))
    return done(m, rgb, "gloss", detail=0.6)


def prismatic(m):
    hue = (m.y * 1.6 + m.ez * 0.25 + m.nrm[..., 0] * 0.08) % 1
    rgb = hsv_to_rgb(np.stack([hue, np.full_like(hue, 0.72), np.full_like(hue, 1.0)], -1))
    rgb = pearl(m, rgb, 0.22, 0.2, 0.55)
    sparkle = speckle(m, 150, 0.84, seed=43)
    rgb = mix(rgb, (1.0, 1.0, 1.0), sparkle * 0.8)
    emit = rgb * 0.18 + sparkle[..., None] * 0.6
    return done(m, rgb, "gloss", emit=emit, detail=0.7)


def nebula(m):  # Gas clouds in magenta, violet and cyan, dark dust lanes, newborn stars
    rgb = coat(m, (0.06, 0.03, 0.14), (0.08, 0.05, 0.18), (0.07, 0.04, 0.16))
    a, b = fbm(m, 3, 44), fbm(m, 5, 45)
    a = a + 0.3 * (fbm(m, 2.2, 48) - 0.5)
    # Thresholds from this fish's own spread of the field, so a thin body (the 'Cuda)
    # gets as much cloud as a round one
    lo, hi, top = np.percentile(a[m.cov], [30, 70, 92])
    cloud = smoothstep(lo, hi, a)
    blo, bhi = np.percentile(b[m.cov], [15, 85])
    t = np.clip((b - blo) / max(bhi - blo, 1e-4), 0, 1)[..., None]
    magenta, violet, cyan = C(0.92, 0.18, 0.92), C(0.45, 0.22, 1.0), C(0.12, 0.85, 1.0)
    color = np.where(t < 0.5, magenta + (violet - magenta) * (t * 2), violet + (cyan - violet) * (t * 2 - 1))
    core = smoothstep(hi, top, a)
    dust = smoothstep(0.04, 0.0, np.abs(fbm(m, 7, 49) - 0.5)) * cloud
    rgb = mix(rgb, color, cloud * 0.92)
    rgb = mix(rgb, (0.90, 0.90, 1.0), core * 0.45)
    rgb = mix(rgb, (0.04, 0.02, 0.08), dust * 0.8)
    stars = speckle(m, 220, 0.9, seed=46)
    big = glow_halo(speckle(m, 50, 0.93, seed=47), 3)
    rgb = mix(rgb, (1.0, 1.0, 1.0), stars * 0.9)
    rgb = mix(rgb, (0.9, 0.92, 1.0), big * 0.7)
    lit = (cloud * (1 - dust * 0.8) * 0.45)[..., None]
    emit = color * lit + core[..., None] * C(0.9, 0.85, 1.0) * 0.3 + stars[..., None] * 0.8 + big[..., None] * 0.5
    return done(m, rgb, "gloss", emit=emit, detail=0.5)


def void(m):  # An event horizon: a black core, a glowing accretion spiral, a violet rim
    rgb = coat(m, (0.02, 0.01, 0.04), (0.04, 0.02, 0.07), (0.03, 0.01, 0.06))
    dy = m.y - 0.45
    dz = (m.ez - 0.05) * 0.11
    r = np.sqrt(dy * dy + dz * dz) + 1e-4
    th = np.arctan2(dz, dy)
    arms = 0.5 + 0.5 * np.cos(th * 2 - np.log(r) * 7)
    disk = smoothstep(0.42, 0.1, r) * smoothstep(0.03, 0.06, r)
    band = body_only(m, smoothstep(0.62, 0.95, arms) * disk)
    hot = smoothstep(0.25, 0.05, r)
    col = mix(board(m, (0.36, 0.08, 0.85)), (0.86, 0.66, 1.0), hot)
    rgb = mix(rgb, col, band)
    rim = smoothstep(0.45, 0.12, np.abs(m.nrm[..., 0])) * (1 - band)
    rgb = mix(rgb, (0.45, 0.16, 0.90), rim * 0.4)
    rgb = mix(rgb, (0.62, 0.30, 1.0), m.fin * smoothstep(3.6, 6, m.r2))
    emit = col * band[..., None] + (rim * 0.35)[..., None] * C(0.45, 0.16, 0.9)
    return done(m, rgb, "gloss", emit=emit, detail=0.6)


def abyss_ink(m):  # The Kraken's skin: ink pigment cells, glowing violet veins, sucker rings
    rgb = coat(m, (0.10, 0.04, 0.16), (0.22, 0.10, 0.30), (0.30, 0.10, 0.50))
    rgb = mix(rgb, (0.03, 0.01, 0.05), spots(m, 900, 0.006, seed=49, vary=0.6) * 0.8)
    vein = net(m, 70, 0.006, seed=50)
    halo = glow_halo(vein, 4)
    rgb = mix(rgb, (0.55, 0.25, 1.0), halo * 0.5)
    rgb = mix(rgb, (0.80, 0.55, 1.0), vein)
    suckers = body_only(m, rings(m, 40, 0.01, 0.022, 0.004, seed=51) * smoothstep(0.45, 0.2, m.up))
    rgb = mix(rgb, (0.66, 0.60, 0.95), suckers)
    emit = (
        vein[..., None] * C(0.7, 0.4, 1.0)
        + (halo * 0.35)[..., None] * C(0.5, 0.2, 1.0)
        + suckers[..., None] * C(0.3, 0.25, 0.6) * 0.4
    )
    return done(m, rgb, "gloss", emit=emit, detail=0.7)


def sunken_gold(m):
    rgb = coat(m, (0.95, 0.68, 0.0), (1.0, 0.84, 0.16), (0.84, 0.56, 0.0))
    rgb = mix(rgb, (0.62, 0.38, 0.0), smoothstep(0.9, 0.98, scales(m, 0.04)) * 0.7)
    patina = np.clip(smoothstep(0.55, 0.7, fbm(m, 6, 51)) * (smoothstep(0.6, 0.9, m.y) + m.fin * 0.6), 0, 1)
    rgb = mix(rgb, (0.12, 0.56, 0.48), patina * 0.85)
    rgb = sheen(m, rgb, 0.45, (1.0, 0.92, 0.55))
    rough = 0.16 * (1 - patina) + 0.8 * patina
    return done(m, rgb, "gloss", metal=(1 - patina) * 0.55, rough=rough, detail=0.7)


def drowned_pearl(m):
    rgb = coat(m, (0.90, 0.92, 1.0), SNOW, (0.80, 0.86, 1.0))
    n = m.nrm
    hue = 0.45 + 0.28 * (0.5 + 0.5 * np.sin(n[..., 0] * 3.0 + n[..., 2] * 2.0 + m.y * 4))
    film = hsv_to_rgb(np.stack([hue % 1, np.full_like(hue, 0.42), np.ones_like(hue)], -1))
    rgb = mix(rgb, film, 0.55)
    growth = stripes(m, 34, 0.1, wobble=0.6, slant=0.6, seed=52)
    rgb = mix(rgb, (0.70, 0.78, 0.95), growth * 0.4)
    rgb = sheen(m, rgb, 0.22, (1, 1, 1))
    return done(m, rgb, "gloss", detail=0.6)


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
    "Rust": rust,
    "Toxic": toxic,
    "Lunar": lunar,
    "Glowspot": glowspot,
    "Tidepool": tidepool,
    "Mandarin": mandarin,
    "Lanternfish": lanternfish,
    "Diamond": diamond,
    "Magma": magma,
    "Glacier": glacier,
    "Xray": xray,
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


def save_rgb(path, arr):
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).save(path)


def save_gray(path, arr):
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "L").save(path)


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
        manifest_path = folder / "skins.json"
        manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
        made = 0
        for shade, recipe in RECIPES.items():
            if only and shade not in only:
                continue
            skin = recipe(fish)
            save_rgb(folder / f"{shade}.png", skin["rgb"])
            for suffix in ("_emit", "_metal", "_rough"):
                (folder / f"{shade}{suffix}.png").unlink(missing_ok=True)
            if skin["emit"] is not None:
                save_rgb(folder / f"{shade}_emit.png", skin["emit"])
            if skin["metal"] is not None:
                save_gray(folder / f"{shade}_metal.png", skin["metal"])
            if skin["rough"] is not None:
                save_gray(folder / f"{shade}_rough.png", skin["rough"])
            manifest[shade] = {
                "finish": skin["finish"],
                "emit": skin["emit"] is not None,
                "metal": skin["metal"] is not None,
                "rough": skin["rough"] is not None,
            }
            made += 1
        # The finish maps every shade without its own roughness shares
        for finish in sorted({v["finish"] for v in manifest.values()}):
            save_gray(folder / f"finish_{finish}.png", finish_map(fish, finish))
        manifest_path.write_text(json.dumps(manifest, indent=1, sort_keys=True) + "\n")
        print(f"[shades] {name}: {made} skins")


if __name__ == "__main__":
    main()
