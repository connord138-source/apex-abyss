"""Makes the shade skins: one recolored color texture per fish and shade.

    python tools/shades/make_shades.py <maps_dir> <out_dir> [Fish ...] [--only=Shade,Shade]

Needs numpy, scipy and pillow. The maps come from bake_maps.py (the fish's own color
texture plus, for every texel, where it sits on the body in 3D) and the eyes from
eyes.json (find_eyes.py). Owner, 2026-10-08: "All of the shades in general need much
much more variance and depth than just a slight reshape to the existing colors." A
tint can only darken a texture (SurfaceAppearance.Color multiplies), so every shade
is a real skin here: countershaded body, fins, then patterns laid on the body in 3D
(stripes, bands, spots, rosettes, nets, scales, facets, cracks, clouds, rays, prints)
and a finish (pearl, metal, glow halos), keeping the texture's painted strokes, the
eyes, teeth and mouth, and the Anglerfish's lure.

Each fish has its own skin line (owner, 2026-10-10: "skins to be different for each
playable fish. Common skins should be similar to original just with realistic fish
reshades and the rarer they get the wilder they get"): lines.json lists, per fish,
its 12 line skins (4 Common realistic colour morphs of the real species, then
Uncommon to Mythic, each wilder) and the universal skins every fish gets (the catch
track, the weekly limited skins, the trophy and treasure shades). A fish is made with
ONLY its own line plus the universal skins (shade_lines.py reads the lists for every
tool here); a recipe for every id in lines.json lives in RECIPES.

No skin may look like human skin (Hatch & Snatch, 2026-10-03: an account suspension
over a pale pinkish atlas). Every pale tone is cool (silver-blue whites), warm colors
are saturated (a saturated orange or gold is far outside the skin-tone rules; a
peach or beige is inside them) with hard edges against anything pale, dark tones are
cool (olive, charcoal, slate, never a warm brown), and screen_shades.py checks every
skin before upload.

Writes, per fish, <out_dir>/<Fish>/: <Shade>.png (color, 1024, what Roblox takes),
<Shade>_emit.png (what glows, RGB; the importer turns it into the emissive mask),
<Shade>_metal.png and <Shade>_rough.png where a shade has its own, finish_<name>.png
(the roughness every other shade with that finish shares: matte, satin, gloss,
mirror), skins.json (which maps each shade has; only the fish's own list, anything
else in the folder is removed) and eyes_debug.png.
"""

from __future__ import annotations

import json
import pathlib
import sys

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import cKDTree

import shade_lines
from screen_shades import skin_masks

HERE = pathlib.Path(__file__).parent
SIZE = 1024

# Per fish: keep its teeth and mouth (the predators), and the Anglerfish's glowing
# lure and iris; `blade` is how thin its fins are (body lengths: the Nibbler's and
# the Puffer's are chunky) and `blade_top` how far a fin stands out at least (the
# Puffer's spines are not fins), `tail_from` where its tail fin starts if the blade
# test misses it, `mirror` copies its right side's fins to its left; `fins` finds
# them another way (the 'Cuda's are
# painted yellow, the eel's is the ridge along its back)
# Teeth are this, shaded like their own paint (Fish._tooth_colour): a neutral bone
# white. Any warmer and screen_shades.py counts it as pale cream (Cr - Cb >= 3): the
# first try, (0.93, 0.92, 0.88), added 1% cream to two Reef Shark skins and was flagged
BONE = (0.92, 0.92, 0.91)
# No glow within this of the teeth (body lengths, in 3D: inner, outer), on any skin:
# the gums and the inside of the mouth between the teeth (Fish.mouth_zone). The
# 'Cuda's mouth slot lies 0.003-0.015 from its teeth, its lips beyond
MOUTH_DARK = (0.006, 0.016)

FISH = {
    "Nibbler": {"teeth": False, "keep_vivid": False, "blade": 0.045, "blade_top": 0.035},
    "Cuda": {"teeth": True, "keep_vivid": False, "fins": "yellow", "blade_top": 0.012},
    "Puffer": {"teeth": False, "keep_vivid": False, "blade": 0.045, "blade_top": 0.04, "tail_from": 0.85, "mirror": True},
    "MorayEel": {"teeth": True, "keep_vivid": False, "fins": "ridge", "blade_top": 0.006},
    "ReefShark": {"teeth": True, "keep_vivid": False, "blade": 0.02},
    "Angler": {"teeth": True, "keep_vivid": True, "blade": 0.024, "blade_top": 0.03},
}


# Each fish's eye palette (eyes.json `eye`, `skin`; Fish._eyes)
EYE_SPECS = {k: v for k, v in json.loads((HERE / "eyes.json").read_text()).items() if isinstance(v, dict)}


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

    def __init__(self, name: str, npz: pathlib.Path, picks, teeth=None):
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
        # Texels the bake never reached keep the bounds' corner as their place (a
        # quarter of the atlas): left out of the point sets the lines' patterns use
        corner = np.all(np.abs(self.pos - self.mn.astype(np.float32)) < 1e-3, axis=-1)
        self.real = cov & ~corner
        # (every skin's maps are filled there from the baked texels round them: see
        # padded())
        self.length = float(d["length"])
        self.faces = d["faces"]
        self.maps = pathlib.Path(npz).parent
        self.hsv = rgb_to_hsv(self.color)
        self.lum = self.color @ np.array([0.299, 0.587, 0.114], np.float32)
        # Body frame: y 0 at the snout .. 1 at the tail tip; x and z in body lengths
        self.y = (self.pos[..., 1] - self.mn[1]) / max(self.length, 1e-6)
        self.p = self.pos / max(self.length, 1e-6)  # body lengths
        self._cross_section()
        self.fine = self._fine_detail()
        self.keep = self._keep_mask(picks)
        self.teeth = self._teeth(teeth)
        self.tooth = self._tooth_colour()

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
        # The fits per slice, for the smooth frame (Smooth: interpolated between the
        # slices' middles instead of looked up per slice)
        self.slices = (ys, xc, zc, wx, wz)
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
        # The eyes keep their own unmixed edge (no blur: a blurred edge kept a ring
        # of the old skin colour round them)
        return np.maximum(np.clip(ndimage.gaussian_filter(keep, 0.8), 0, 1), self.eyes)

    def _teeth(self, spec):
        """The teeth (owner, 2026-10-14: "All fish should always have bone white
        teeth"): mouths marked on the bake's head views (teeth.json boxes); inside
        them, texels of the fish's own tooth colour (`rule`), grown to the whole of
        each tooth's piece of the atlas. Soft-edged, 0..1."""
        mask = np.zeros((SIZE, SIZE), np.float32)
        if not spec:
            return mask
        if spec["rule"] == "slot":
            return self._slot_teeth(spec)
        r, g, b = self.color[..., 0], self.color[..., 1], self.color[..., 2]
        hue, sat, val = self.hsv[..., 0], self.hsv[..., 1], self.hsv[..., 2]
        rule = spec["rule"]
        if rule == "pale_warm":  # the Angler's beige fangs
            cand = (val > 0.45) & (sat < 0.5) & (r >= b - 0.02)
        elif rule == "warm":  # the 'Cuda's peach teeth on a white-blue jaw
            cand = (r > b + 0.06) & (val > 0.45) & ((hue < 0.11) | (hue > 0.9))
        else:  # "pale": off-white teeth on a coloured body (the Moray)
            cand = (val > 0.55) & (sat < 0.35)
        cand &= self.cov
        hits = np.zeros((SIZE, SIZE), bool)
        for view, x0, y0, x1, y1 in spec["boxes"]:
            face = self.faces[view][y0:y1, x0:x1]
            sel = face[..., 5] > 0.5
            u, v = face[..., 3][sel], face[..., 4][sel]
            tx = np.clip((u % 1.0) * SIZE, 0, SIZE - 1).astype(int)
            ty = np.clip((1 - v % 1.0) * SIZE, 0, SIZE - 1).astype(int)
            hits[ty, tx] = True
        seed = ndimage.binary_dilation(hits, iterations=2) & cand
        labels, n = ndimage.label(cand)
        if n == 0:
            return mask
        counts = ndimage.sum(seed, labels, range(1, n + 1))
        sizes = ndimage.sum(cand, labels, range(1, n + 1))
        # A piece is a tooth when enough of it was seen inside a mouth box (and it's
        # not a whole pale belly that happens to touch one)
        good = np.flatnonzero((counts >= 3) & (counts >= sizes * 0.02) & (sizes < 60000)) + 1
        teeth = np.isin(labels, good)
        teeth = ndimage.binary_closing(teeth, iterations=1) & self.cov
        return np.clip(ndimage.gaussian_filter(teeth.astype(np.float32), 0.6) * 1.8, 0, 1)

    def _slot_teeth(self, spec):
        """Teeth too small for the head views (the Reef Shark's, a pixel or two
        each): bake_mouth.py's close-ups of the mouth (<Fish>.mouth.npz beside the
        maps, rendered at teeth.json `mouth`), where the teeth are the light bits
        inside the dark slot of the mouth. Texels many of them land on are teeth;
        lone hits along UV seams are dropped."""
        path = self.maps / f"{self.name}.mouth.npz"
        assert path.exists(), f"{path} missing: run bake_mouth.py with teeth.json's mouth for {self.name}"
        views = np.load(path)["faces"].astype(np.float32)
        hits = np.zeros((SIZE, SIZE), np.float32)
        for face in views:
            rgb, seen = face[..., :3], face[..., 5] > 0.5
            r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
            val = rgb.max(-1)
            # The slot: dark and purple (the back's dark grey has more green)
            dark = seen & (val < 0.3) & (r > g + 0.015) & (b > g + 0.03)
            slot = ndimage.binary_fill_holes(ndimage.binary_closing(dark, iterations=6)) & seen
            slot = ndimage.binary_opening(slot, iterations=3)
            tooth = slot & ~dark & (val > 0.3)
            u, v = face[..., 3][tooth], face[..., 4][tooth]
            tx = np.clip((u % 1.0) * SIZE, 0, SIZE - 1).astype(int)
            ty = np.clip((1 - v % 1.0) * SIZE, 0, SIZE - 1).astype(int)
            np.add.at(hits, (ty, tx), 1.0)
        dense = ndimage.gaussian_filter(np.minimum(hits, 1.0), 2.0) > 0.12
        # The teeth are painted lavender grey: bluer than the belly's pale grey and
        # the flank's mid grey, which seams and the lips' edges also land on
        r, g, b = self.color[..., 0], self.color[..., 1], self.color[..., 2]
        lavender = (b > g + 0.05) & (r > g - 0.025) & (self.hsv[..., 2] > 0.3)
        teeth = ndimage.binary_closing(dense, iterations=2) & self.cov & lavender
        labels, n = ndimage.label(teeth)
        if n:
            sizes = ndimage.sum(teeth, labels, range(1, n + 1))
            teeth = np.isin(labels, np.flatnonzero(sizes >= 150) + 1)
        teeth = ndimage.binary_closing(teeth, iterations=1) & self.cov
        return np.clip(ndimage.gaussian_filter(teeth.astype(np.float32), 0.6) * 1.8, 0, 1)

    def mouth_zone(self, inner, outer):
        """How near each texel is to the teeth, in 3D on the body (1 within `inner`
        body lengths of a tooth, 0 past `outer`; all 0 on a fish with no teeth). Only
        the head's teeth count: a few tooth texels land on UV seams far down the body.
        The gums and the inside of the mouth sit between the teeth there, which the
        teeth mask leaves to the skin: Thunder's arcs glowed across them, and read as
        lightning over the teeth ('Cuda, playtest 2026-10-16)."""
        key = ("mouth_zone", inner, outer)
        store = self.__dict__.setdefault("_cache", {})
        if key not in store:
            heads = (self.teeth > 0.5) & self.real & (self.y < 0.35)
            if not heads.any():
                store[key] = np.zeros(self.y.shape, np.float32)
            else:
                if "teeth_distance" not in store:
                    d, _ = cKDTree(self.p[heads]).query(self.p.reshape(-1, 3), k=1)
                    store["teeth_distance"] = d.reshape(self.y.shape).astype(np.float32)
                store[key] = (smoothstep(outer, inner, store["teeth_distance"]) * self.cov).astype(np.float32)
        return store[key]

    def _tooth_colour(self):
        """Bone white, shaded like the teeth's own paint (darker at the roots)."""
        bone = np.array(BONE, np.float32)
        sel = self.teeth > 0.5
        if not sel.any():
            return np.broadcast_to(bone, self.color.shape).copy()
        mean = float(np.mean(self.lum[sel]))
        shade = np.clip(0.97 + 0.2 * (self.lum - mean) / max(mean, 1e-3), 0.88, 1.05)
        return np.clip(bone * shade[..., None], 0, 1)

    def _eyes(self, picks):
        """The whole painted eye (sclera with its shaded side, iris, pupil and
        highlight), soft-edged 0..1, with its own colour for done() in self.kept.

        Owner, 2026-10-17: "Every single skin on nibbler glitches into the eye". Up
        to v11 the eye was the pale or dark texels inside a sphere round each pick,
        and only the pieces holding a pupil were kept (v8, to drop the cream band
        behind the Nibbler's eye). But an eye's sclera spans several UV islands, and
        the islands with no pupil on them were dropped: the skin bit a stair-stepped
        chunk out of the sclera on every skin. The Puffer's iris and the Moray's
        ring fell out of the colour test as well.

        Now each fish has its own eye and skin palette in eyes.json (the eye's
        painted colours, and the skin colours round it, the Nibbler's cream band
        among them). A texel is eye when its colour is nearer an eye colour than a
        skin colour; every piece of eye that lies mostly inside the eye's sphere
        (`core`) is kept whole, wherever the atlas cut it; small holes are filled;
        and the edge is unmixed from the texture's own anti-aliasing (each edge
        texel's colour as a blend of the eye's colour and the skin's beside it), so
        it is as round and clean as the painted eye, and none of the old skin
        colour is kept as a fringe."""
        spec = EYE_SPECS.get(self.name, {})
        size = SIZE
        faces = self.faces
        yy, xx = np.mgrid[0 : faces.shape[1], 0 : faces.shape[2]]
        dist = np.full((size, size), np.inf, np.float32)  # in each eye's own radius
        clear = np.full((size, size), np.inf, np.float32)  # body lengths out from an eye
        for view, px, py, radius in picks:
            face = faces[view]
            sel = ((xx - px) ** 2 + (yy - py) ** 2 <= radius * radius) & (face[..., 5] > 0.5)
            u, v = face[..., 3][sel], face[..., 4][sel]
            tx = np.clip((u % 1.0) * size, 0, size - 1).astype(int)
            ty = np.clip((1 - v % 1.0) * size, 0, size - 1).astype(int)
            hit = np.zeros((size, size), bool)
            hit[ty, tx] = True
            hit = ndimage.binary_closing(hit, iterations=3) & self.cov
            if not hit.any():
                continue
            pts = self.pos[hit]
            centre = np.median(pts, 0)
            r3 = float(np.percentile(np.linalg.norm(pts - centre, axis=-1), 90))
            far = np.linalg.norm(self.pos - centre, axis=-1)
            dist = np.minimum(dist, far / max(r3, 1e-6))
            clear = np.minimum(clear, (far - r3) / max(self.length, 1e-6))
        self.eye_dist = dist
        self.eye_clear = clear
        self.kept = self.color.copy()
        if not np.isfinite(dist).any():
            return np.zeros((size, size), np.float32)
        eye_pal = np.array(spec.get("eye", [[0.1, 0.1, 0.1], [0.85, 0.87, 0.9]]), np.float32)
        skin_pal = np.array(spec.get("skin", []), np.float32).reshape(-1, 3)
        core = float(spec.get("core", 1.0))
        reach = float(spec.get("reach", 2.0))
        near = self.real & (dist < reach * 1.2)
        c = self.color

        def nearest(pal):
            d = np.full((size, size), np.inf, np.float32)
            idx = np.zeros((size, size), np.int32)
            for k, col in enumerate(pal):
                dk = np.linalg.norm(c - col, axis=-1)
                better = dk < d
                d = np.where(better, dk, d)
                idx = np.where(better, k, idx)
            return d, idx

        d_eye, _ = nearest(eye_pal)
        d_skin, _ = nearest(skin_pal) if len(skin_pal) else (np.full((size, size), np.inf, np.float32), None)
        tol = float(spec.get("tol", 0.22))  # an eye texel is at least this near an eye colour
        cand = near & (d_eye < d_skin) & (d_eye < tol)
        # The pieces of eye, whole: kept when most of a piece lies inside the sphere
        # (pieces of the same colour elsewhere, a pale belly or a white band, reach
        # far out of it)
        labels, n = ndimage.label(cand, structure=np.ones((3, 3)))
        eye = np.zeros((size, size), bool)
        if n:
            idx = np.arange(1, n + 1)
            sizes = ndimage.sum(cand, labels, idx)
            inside = ndimage.sum(cand & (dist < core), labels, idx)
            good = idx[(inside >= np.maximum(sizes * float(spec.get("share", 0.5)), 3))]
            eye = np.isin(labels, good) & (dist < reach)
        # Holes in the eye (a highlight, a pupil's rim the palette missed), if small
        holes = ndimage.binary_fill_holes(eye) & ~eye
        hl, hn = ndimage.label(holes)
        if hn:
            hs = ndimage.sum(holes, hl, np.arange(1, hn + 1))
            eye |= np.isin(hl, np.flatnonzero(hs < float(spec.get("hole", 400))) + 1)
        eye = ndimage.binary_opening(eye, iterations=1) | (eye & (dist < core * 0.5))
        if not eye.any():
            return np.zeros((size, size), np.float32)
        # The edge: unmix each texel near the outline between the eye's colour inside
        # it and the skin's colour outside it
        inner = ndimage.binary_erosion(eye, iterations=1)
        inner |= eye & ~ndimage.binary_dilation(inner, iterations=3)  # thin pieces
        outer = ~ndimage.binary_dilation(eye, iterations=2) & self.real
        band = ~inner & ndimage.binary_dilation(eye, iterations=2) & self.cov
        _, (iy, ix) = ndimage.distance_transform_edt(~inner, return_indices=True)
        _, (oy, ox) = ndimage.distance_transform_edt(~outer, return_indices=True)
        e_col = c[iy, ix]
        s_col = c[oy, ox]
        es = e_col - s_col
        den = (es * es).sum(-1)
        a = ((c - s_col) * es).sum(-1) / np.maximum(den, 1e-6)
        a = np.where(den > 0.006, np.clip(a, 0, 1), eye.astype(np.float32))
        # Only out to the eye's reach (a skin colour beside it is never eye)
        a = a * (dist < reach * 1.15)
        alpha = np.where(inner, 1.0, np.where(band, a, 0.0)).astype(np.float32)
        alpha *= self.cov
        self.kept = np.where(band[..., None], e_col, c)
        return alpha


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


NORMAL_Y_SIGN = 1.0  # glTF/OpenGL: green is up the image; flip to -1 if rivets look sunken in Studio
# No relief normal maps are written (v10): none ships since v8.1 (pack_shades.py
# NORMALS = False; the account was terminated over one, 2026-10-13), and
# screen_shades.py flags every one it finds. `relief` and `height` are kept so they
# could come back as colour shading; the colour maps never depended on them
NORMALS = False
DETAIL_FLOOR = 0.8  # the fish's painted creases (gill, fin rays, mouth) always show at least this much


def relief_normal(m: Fish, rgb, height=None, relief=1.0, fine=None):
    """A tangent-space normal map from a skin's own pattern (rivets, scales, coral,
    spirals, grout stand out or sink in) and the fish's painted creases, so a skin is
    lit as a surface, not a decal (owner, 2026-10-12: "They just look pasted on the
    fish ... The designs need much more depth")."""
    if height is None:
        lum = np.asarray(rgb, np.float32) @ np.array([0.299, 0.587, 0.114], np.float32)
        # Band-pass: the pattern's edges a few texels wide, not its broad fills
        height = ndimage.gaussian_filter(lum, 1.0) - ndimage.gaussian_filter(lum, 7.0)
        height = np.clip(height * 3.0, -1, 1)
    f = m.fine if fine is None else fine
    height = height + 0.6 * f
    height = height * m.cov
    k = 0.9 * relief
    dx = ndimage.sobel(height, axis=1) / 8.0
    dy = ndimage.sobel(height, axis=0) / 8.0
    nx = -dx * k
    ny = dy * k * NORMAL_Y_SIGN
    nz = np.ones_like(height)
    n = np.stack([nx, ny, nz], -1)
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
    return n * 0.5 + 0.5


def done(m: Fish, rgb, finish="satin", emit=None, metal=None, rough=None, detail=1.3, hush=None, relief=1.0, height=None, floor=None):
    """A finished skin: the painted strokes back on, the eyes, teeth, mouth and lure
    as they were, plus its glow (RGB), metal (0..1) and own roughness, if any, and a
    normal map of its own relief (`relief` 0 for a smooth skin; `height` to give the
    bumps yourself, 0..1 up). The Angler's lure always glows. `hush` (0..1) quiets
    the painted strokes where a skin paints over the fish's own markings (old band
    edges showing through as ghosts), but never below DETAIL_FLOOR of them: a skin
    with no creases read as pasted on."""
    fine = m.fine if hush is None else m.fine * (1 - np.clip(hush, 0, 1))
    # `floor` lowers the creases' floor for one skin (thin pale lines on a dark body
    # read as skin to the classifier once the creases brightened them: Undertow)
    strength = max(detail, DETAIL_FLOOR if floor is None else floor)
    normal = relief_normal(m, rgb, height, relief, fine) if NORMALS and relief > 0 else None
    rgb = rgb * (1 + strength * fine)[..., None]
    rgb = np.clip(rgb, 0, 1)
    rgb = mix(rgb, m.kept, m.keep)
    # Teeth are always bone white, whatever the skin (owner, 2026-10-14)
    rgb = mix(rgb, m.tooth, m.teeth)
    rgb[~m.cov] = m.color[~m.cov]
    if emit is not None:
        # Nothing glows on the teeth or right round them (the gums and the inside of
        # the mouth between them), so no glow runs across the teeth (v10)
        dim = np.maximum(np.maximum(m.keep, m.teeth), m.mouth_zone(*MOUTH_DARK))
        emit = np.clip(np.asarray(emit, np.float32), 0, 1) * (1 - dim)[..., None]
    if m.lure is not None:
        lure = m.color * m.lure[..., None]
        emit = lure if emit is None else np.maximum(emit, lure)
    if emit is not None:
        emit = emit * m.cov[..., None]
    if metal is not None:
        metal = np.clip(metal, 0, 1) * (1 - np.maximum(m.keep, m.teeth)) * m.cov
    if rough is not None:
        rough = np.clip(rough + 0.12 * m.fine, 0.05, 1)
        rough = rough * (1 - m.eyes) + 0.12 * m.eyes
        rough = rough * (1 - m.teeth) + 0.35 * m.teeth
    rgb, emit, metal, rough = (None if a is None else padded(m, a) for a in (rgb, emit, metal, rough))
    if normal is not None:
        # Flat where the eyes and kept paint are, flat in the atlas gaps
        normal = mix(normal, (0.5, 0.5, 1.0), m.keep)
        normal = padded_plain(m, normal)
    return {"rgb": rgb, "emit": emit, "metal": metal, "rough": rough, "normal": normal, "finish": finish}


def natural(m: Fish):
    """The fish's own look with bone-white teeth: worn when no shade is (Cosmetics),
    so the teeth are white on every fish, skin or not. Its lure glows as in every skin."""
    rgb = mix(m.color, m.tooth, m.teeth)
    emit = m.color * m.lure[..., None] if m.lure is not None else None
    if emit is not None:
        emit = padded(m, emit * m.cov[..., None])
    return {"rgb": padded(m, rgb), "emit": emit, "metal": None, "rough": None, "normal": None, "finish": "satin"}


def padded_plain(m: Fish, arr):
    """padded() without the skin-tone guard (a normal map is never a colour)."""
    arr = np.asarray(arr, np.float32)
    known = m.real.astype(np.float32)
    out = arr * known[..., None]
    filled = m.real.copy()
    for sigma in (2, 4, 8, 16, 32, 64, 128):
        den = ndimage.gaussian_filter(known, sigma)
        num = np.stack([ndimage.gaussian_filter(arr[..., k] * known, sigma) for k in range(arr.shape[-1])], -1)
        fill = num / np.maximum(den, 1e-6)[..., None]
        new = ~filled & (den > 0.05)
        out[new] = fill[new]
        filled |= new
        if filled.all():
            break
    out[~filled] = (0.5, 0.5, 1.0)
    return out


def padded(m: Fish, arr):
    """A map with the atlas gaps (texels the bake never reached) filled with a soft
    blur of the baked texels round them (pull-push, widening until every gap is
    filled): nearest-texel padding drew streaks the moderation classifier scored
    higher. A blend of two colours can be a skin tone (orange into white is peach),
    so wherever the fill lands on one, the nearest baked texel's own colour is used
    instead (the same rule screen_shades.py checks)."""
    arr = np.asarray(arr, np.float32)
    if arr.ndim == 0:
        return arr
    known = m.real.astype(np.float32)
    out = arr * (known if arr.ndim == 2 else known[..., None])
    filled = m.real.copy()
    for sigma in (2, 4, 8, 16, 32, 64, 128):
        den = ndimage.gaussian_filter(known, sigma)
        if arr.ndim == 2:
            num = ndimage.gaussian_filter(arr * known, sigma)
            fill = num / np.maximum(den, 1e-6)
        else:
            num = np.stack([ndimage.gaussian_filter(arr[..., k] * known, sigma) for k in range(arr.shape[-1])], -1)
            fill = num / np.maximum(den, 1e-6)[..., None]
        new = ~filled & (den > 0.05)
        out[new] = fill[new]
        filled |= new
        if filled.all():
            break
    out[~filled] = arr[~filled]
    # Round the eyes the gaps take the nearest baked texel (the eye's own colour), not
    # a blur that reaches the skin beside them: a texture sampled across an eye's UV
    # seam (mip levels at a distance) would draw a thin line of skin through the eye
    eye_gap = cache(m, "eye_gap", lambda: ndimage.binary_dilation(m.eyes > 0.5, iterations=8) & ~m.real)
    if eye_gap.any():
        idx = cache(m, "nearest_real", lambda: ndimage.distance_transform_edt(~m.real, return_distances=False, return_indices=True))
        out[eye_gap] = arr[idx[0], idx[1]][eye_gap]
    if arr.ndim == 3:
        skin, pale = skin_masks((np.clip(out, 0, 1) * 255).astype(np.uint8))
        risky = ndimage.binary_dilation((skin | pale) & ~m.real, iterations=2) & ~m.real
        if risky.any():
            idx = cache(m, "nearest_real", lambda: ndimage.distance_transform_edt(~m.real, return_distances=False, return_indices=True))
            out[risky] = arr[idx[0], idx[1]][risky]
    return out


def finish_map(m: Fish, finish):
    """A finish's roughness map: its level, the painted detail as a little variation,
    wet eyes."""
    rough = np.clip(FINISHES[finish] + 0.12 * m.fine, 0.05, 1)
    rough = rough * (1 - m.eyes) + 0.12 * m.eyes
    rough[~m.cov] = 1.0
    return padded(m, rough)


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
    m = smooth(m)  # edges along the body, not stepped per slice (playtest 2026-10-10)
    along = smoothstep(0.05, 0.95, m.y)
    rgb = mix(board(m, (1.0, 0.80, 0.0)), (0.95, 0.26, 0.0), along)
    rgb = mix(rgb, (1.0, 0.90, 0.20), smoothstep(0.45, 0.15, m.up) * 0.7)
    horizon = 0.5 + 0.5 * np.sin(m.ez * 7 + (fbm(m, 4, 13) - 0.5) * 6)
    rgb = mix(rgb, (0.74, 0.06, 0.22), smoothstep(0.75, 0.95, horizon) * 0.6 * (1 - m.fin))
    rgb = mix(rgb, (0.78, 0.04, 0.24), m.fin)
    return done(m, rgb, "gloss")


def ink(m):  # Ink wash: pigment pooling at the edges, a glowing lateral line
    m = smooth(m)  # edges along the body, not stepped per slice (playtest 2026-10-10)
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


def lilac(m):  # Lilac (v12): lilac darkening to violet on the back, fine iridescent scales, violet-edged fins
    """A designed lavender morph (owner, 2026-10-17: the old Lilac "reads as purple with
    random white spots"): a pale lilac belly through a lilac flank to deep violet
    along the back, every scale drawn round the body with a fine violet rim and a
    soft iridescent film that shifts from blue to violet with the surface, a smooth
    unscaled face, and lilac fins with crisp violet margins. Mid-toned: the palest
    lilac is still well blue of any pink."""
    base = m.base if isinstance(m, Smooth) else m
    sm = smooth(base)
    fins, tip = fin_parts(base)
    u, v, vn = height(sm)
    t = sm.up
    rgb = mix(board(base, (0.78, 0.68, 0.95)), (0.68, 0.50, 0.90), smoothstep(0.15, 0.5, t))
    rgb = mix(rgb, (0.40, 0.18, 0.66), smoothstep(0.55, 0.95, t))
    # Scales: laid round the body in its own girth, a thin darker rim on each, the
    # exposed middle a touch lighter (a little volume), none on the face or fins
    d = round_scales(sm, 0.042)
    on = smoothstep(0.17, 0.26, u) * (1 - hard(fins))
    rim = smoothstep(0.075, 0.035, np.abs(d - 0.5)) * on
    rgb = rgb * (1 + 0.09 * smoothstep(0.5, 0.1, d) * on)[..., None]
    rgb = mix(rgb, (0.44, 0.26, 0.74), rim * 0.45)
    # The iridescent film: blue-violet to violet with the surface's facing, stronger
    # on the scales than the face
    rgb = pearl(sm, rgb, 0.16 + 0.1 * on, 0.08, 0.71)
    # Fins: lilac with the fish's own rays drawn in violet, deepening outward to a
    # crisp violet margin along each fin's free edge (fin_reach)
    reach = fin_reach(base)
    on = hard(fins)
    fin_rgb = mix(board(base, (0.74, 0.58, 0.93)), (0.56, 0.36, 0.86), smoothstep(0.25, 0.8, reach))
    fin_rgb = mix(fin_rgb, (0.44, 0.24, 0.76), smoothstep(0.25, 0.8, own_lines(base)) * 0.6)
    rgb = mix(rgb, fin_rgb, on)
    rgb = mix(rgb, (0.30, 0.10, 0.58), crisp(base, reach - 0.8, texels=1.5) * on)
    return done(m, rgb, "gloss", detail=0.7)


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
    m = smooth(m)  # edges along the body, not stepped per slice (playtest 2026-10-10)
    rgb = coat(m, (0.08, 0.32, 0.82), (0.34, 0.56, 0.92), (1.0, 0.82, 0.0))
    swoosh = smoothstep(0.18, 0.05, np.abs(m.ez - 0.35 - 0.25 * np.sin(m.y * 5.5))) * smoothstep(0.15, 0.3, m.y)
    rgb = mix(rgb, (0.03, 0.05, 0.14), body_only(m, swoosh))
    rgb = mix(rgb, (1.0, 0.82, 0.0), smoothstep(0.78, 0.9, m.y))
    return done(m, rgb, "gloss")


def tiger(m):
    m = smooth(m)  # edges along the body, not stepped per slice (playtest 2026-10-10)
    rgb = coat(m, (1.0, 0.42, 0.0), SNOW, (0.95, 0.34, 0.0), soft=0.025, hard_fins=True)
    t = stripes(m, 11, 0.24, wobble=0.35, slant=0.25, seed=23) * smoothstep(0.15, 0.55, m.up)
    rgb = mix(rgb, INKY, t)
    edge = smoothstep(0.03, 0.0, np.abs(m.up - 0.5)) * (1 - m.fin)
    rgb = mix(rgb, INKY, edge * 0.85)
    return done(m, rgb, "satin")


def bumblebee(m):  # Bumblebee goby (v12): bold black and warm-yellow bands wrapping the body, velvet in the black
    """A real bumblebee goby on the Nibbler (owner, 2026-10-17: the old Bumblebee "reads
    as blotchy yellow/black"): its own three painted bands, widened along the body so
    they wrap it exactly as its bands do, turned to broad velvet-black bands with a
    faint fuzz, crisp-edged against a warm yellow (no orange, no cream) that's a
    little deeper on the back; yellow fins edged in black, the black running onto
    each fin's root."""
    base = m.base if isinstance(m, Smooth) else m
    _, which, outside, _, _ = nib_bands(base)
    sm = smooth(base)
    fins, tip = fin_parts(base)
    u, v, vn = height(sm)
    yellow = body_coat(sm, (0.95, 0.70, 0.0), (1.0, 0.84, 0.10), soft=0.35)
    grain = value_noise(base.p, 260, 2401)  # a fine grain: no big smooth warm field
    yellow = yellow * (0.96 + 0.07 * grain)[..., None]
    widen = np.choose(which - 1, [0.016, 0.026, 0.02]).astype(np.float32)
    black = crisp(base, widen - outside, texels=1.6)
    # Velvet: a dark charcoal with fine fibres a little lighter, densest at the
    # band's edges where the light rakes across it
    fibre = smoothstep(0.58, 0.82, value_noise(base.p * np.array([1.0, 0.35, 1.0], np.float32), 520, 2402))
    rim = smoothstep(widen * 0.55, widen, outside) * black
    velvet = mix(board(base, (0.055, 0.055, 0.065)), (0.17, 0.17, 0.19), np.clip(fibre * 0.45 + rim * 0.3, 0, 1))
    body = mix(yellow, velvet, black)
    # Fins: amber-yellow with the fish's own rays drawn darker, deepening toward a
    # crisp black margin along each fin's free edge (fin_reach)
    reach = fin_reach(base)
    on = hard(fins)
    fin_yellow = mix(board(base, (0.98, 0.74, 0.04)), (0.92, 0.60, 0.0), smoothstep(0.3, 0.8, reach))
    fin_yellow = mix(fin_yellow, (0.62, 0.40, 0.0), smoothstep(0.25, 0.8, own_lines(base)) * on * 0.7)
    rgb = mix(body, fin_yellow, on)
    rgb = mix(rgb, (0.06, 0.06, 0.07), crisp(base, reach - 0.82, texels=1.5) * on)
    return done(m, rgb, "matte", detail=0.8)


def tetra(m):
    # Edges along the body, not stepped per slice (playtest 2026-10-10), and a stripe
    # ruled straight down it: on the smooth frame it still followed the Puffer's lumpy
    # middle and kinked behind the pectoral fin (playtest 2026-10-11), so its height is
    # measured from one straight line fitted through the body's middles, in one body
    # height for the whole length
    m = smooth(m, flatten=6)
    rgb = coat(m, (0.05, 0.10, 0.28), (0.52, 0.60, 0.80), (0.42, 0.55, 0.85))
    rear = smoothstep(0.42, 0.55, m.y) * smoothstep(0.62, 0.35, m.up)
    rgb = mix(rgb, (0.95, 0.06, 0.04), body_only(m, rear))
    ys, _, zc, _, wz = m.slices
    mid = (ys > 0.15) & (ys < 0.85)
    slope, at0 = np.polyfit(ys[mid], zc[mid], 1)
    level = (m.p[..., 2] - (slope * m.y + at0)) / float(np.median(wz[mid]))
    stripe = smoothstep(0.16, 0.06, np.abs(level - 0.18)) * smoothstep(0.1, 0.22, m.y) * smoothstep(0.92, 0.75, m.y)
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


def diamond(m):  # Cut diamond: ice-blue facets, dispersion fire along the bevels, gloss
    """v15 (PC 2026-10-20 round 2, DM: "nearly white in the den, dark navy in the
    Reef"): v8's mirror finish (roughness 0.14, metal 0.35) showed whatever was round
    it, the warm den or the dark water, and never its own colour. Now a gloss with no
    metal, so it reads as the colour painted here: a deeper ice blue (facets from
    pale ice to a cold sapphire, the bevels' highlights blue-white well under white),
    and a faint, even ice-blue glow so it holds pale blue in dark water. The glow map
    is a blue field over the whole body, never thin lines on black."""
    m = smooth(m)
    value, edge = cells(m, 150, seed=31)
    d1, d2, _, _ = worley(m, 150, 31)
    bevel = smoothstep(0.0, 0.06, edge)  # 0 at a facet's edge .. 1 at its heart
    base = mix(board(m, (0.50, 0.70, 0.94)), (0.68, 0.84, 0.99), value)
    # Each facet tilts a little, so it catches the light differently from its neighbours
    facet = mix(base, (0.27, 0.46, 0.84), (1 - value) * 0.55)
    rgb = mix(facet, (0.80, 0.91, 1.0), smoothstep(0.35, 0.0, bevel) * 0.6)
    hue = (value * 2.3 + m.y * 1.5) % 1
    fire_col = hsv_to_rgb(np.stack([hue, np.full_like(hue, 0.6), np.ones_like(hue)], -1))
    fire = smoothstep(0.45, 0.12, bevel) * smoothstep(0.08, 0.0, edge * 0 + (d2 - d1)) * 0.55
    rgb = mix(rgb, fire_col, np.clip(fire, 0, 1))
    glints = speckle(m, 160, 0.86, seed=32)
    rgb = mix(rgb, (0.86, 0.94, 1.0), glints * 0.6)
    rgb = sheen(m, rgb, 0.22, (0.85, 0.93, 1.0))
    # A faint ice-blue glow, a little more in each facet's heart
    emit = (0.13 + 0.09 * bevel)[..., None] * C(0.36, 0.62, 1.0)
    height = bevel * 0.8  # facets stand proud of their bevels
    return done(m, rgb, "gloss", emit=emit, detail=0.6, relief=1.6, height=height)


def plate_field(m: Fish, count, seed, weight=None, round_k=0.0025):
    """Plates on the body (Voronoi round scattered points, in 3D): per texel its
    distance to the nearest plate edge (to the bisector with the nearer of its two
    nearest neighbours, corners rounded by a smooth minimum `round_k` wide, so gaps
    open into small pools where three plates meet), the plate's index, its centre,
    and the direction across the nearest edge (toward the neighbouring plate) laid on
    the skin. Body lengths."""
    pts = scatter(m, count, seed, weight)
    tree = cKDTree(pts)
    d, i = tree.query(m.p.reshape(-1, 3), k=3)
    shape = m.y.shape
    p = m.p.reshape(-1, 3)
    c1, c2, c3 = pts[i[:, 0]], pts[i[:, 1]], pts[i[:, 2]]
    e2 = (d[:, 1] ** 2 - d[:, 0] ** 2) / (2 * np.maximum(np.linalg.norm(c2 - c1, axis=1), 1e-6))
    e3 = (d[:, 2] ** 2 - d[:, 0] ** 2) / (2 * np.maximum(np.linalg.norm(c3 - c1, axis=1), 1e-6))
    k = round_k
    edge = np.maximum(-k * np.logaddexp(-e2 / k, -e3 / k), 0)
    cn = np.where((e2 <= e3)[:, None], c2, c3)
    across = (p - c1) / np.maximum(d[:, :1], 1e-6) - (p - cn) / np.maximum(np.linalg.norm(p - cn, axis=1, keepdims=True), 1e-6)
    n = m.nrm.reshape(-1, 3)
    across = across - n * (across * n).sum(-1, keepdims=True)
    across /= np.maximum(np.linalg.norm(across, axis=1, keepdims=True), 1e-6)
    out = (p - c1) - n * ((p - c1) * n).sum(-1, keepdims=True)  # from the plate's middle, on the skin
    return (
        edge.reshape(shape).astype(np.float32),
        i[:, 0].reshape(shape),
        d[:, 0].reshape(shape).astype(np.float32),
        across.reshape(shape + (3,)).astype(np.float32),
        out.reshape(shape + (3,)).astype(np.float32),
        len(pts),
    )


def painted_light(m: Fish, tilt, strength=1.0):
    """How much a surface tilted by `tilt` (a vector on the skin) catches a light from
    above and a little ahead, against the skin as it is: + lit, - in shade. Painted
    into the colour map (no normal maps, ever: 2026-10-13)."""
    light = np.array([0.0, -0.35, 0.94], np.float32)
    light /= np.linalg.norm(light)
    n2 = m.nrm + tilt * strength
    n2 /= np.maximum(np.linalg.norm(n2, axis=-1, keepdims=True), 1e-6)
    return (n2 @ light) - (m.nrm @ light)


def magma(m):  # Lava gaps: raised basalt crust plates over recessed rivers of glowing lava
    """Owner, 2026-10-16: "The one where its lava should have texture that looks like
    lava gaps". Dark cool basalt plates stand proud (rims lit from above on one side,
    shaded on the other, a slight dome, rough grain, a few cooling cracks); between
    them rivers of lava, wide in places and pinched thin in others, white-yellow at
    the core of the wide ones, orange, then deep red at the plate edges, the glow
    bleeding onto the rims, embers flecked about. Depth is painted in the colour map.
    Orange is never blended into anything pale (the lava's edge is deep red against
    near-black crust), and the yellow-white core keeps its blue low."""
    m = smooth(m)
    # Smaller plates on the head
    weight = 1 + 1.4 * smoothstep(0.3, 0.06, m.y)
    edge, idx, f1, across, out, count = plate_field(m, 115, 330, weight)
    rng = np.random.default_rng(331)
    # The rivers' half-width wanders along each gap: wide, then pinched thin
    wander = fbm_at(m.p, 14, 332, 3)
    half = 0.0011 + 0.0105 * smoothstep(0.3, 0.84, wander) ** 1.5
    half = half * (1.0 - 0.3 * smoothstep(0.3, 0.05, m.y))  # finer round the head's small plates
    widest = 0.0011 + 0.0105
    plate = crisp(m, edge - half, 0.0, texels=1.6)  # 0 lava .. 1 crust
    lava = 1 - plate
    q = np.maximum(edge - half, 0)  # into the plate from its edge
    # --- The crust: a plate's own tone, grain, pits, its domed and bevelled top
    tone = (0.75 + 0.5 * rng.random(count))[idx]
    grain = value_noise(m.p, 260, 333) * 0.55 + value_noise(m.p, 610, 334) * 0.45
    crust = C(0.105, 0.11, 0.128) * (tone * (0.8 + 0.4 * grain))[..., None]
    crust = mix(crust, (0.05, 0.055, 0.068), smoothstep(0.62, 0.8, fbm(m, 40, 335)) * 0.6)  # darker scoria patches
    bevel = 0.0085
    slope = smoothstep(bevel, 0.0, q) ** 1.2  # steep at the rim, flat on top
    # The rim falls away toward the gap (tilting across the edge); the top is domed
    radius = np.maximum(np.percentile(f1[m.real], 70), 1e-4)
    tilt = across * (1.3 * slope)[..., None] + out / radius * 0.55
    shade = painted_light(m, tilt)
    lit = np.clip(shade * 2.6, -1, 1)
    crust = crust * (1 + 0.7 * lit)[..., None]
    # A cool, hard highlight along the rims facing the light; a dark lip on the far side
    rim = smoothstep(0.0, 0.0012, q) * smoothstep(0.0055, 0.0018, q)
    crust = mix(crust, (0.42, 0.44, 0.5), np.clip(lit * 1.3, 0, 1) * rim * 0.85)
    crust = mix(crust, (0.01, 0.01, 0.014), np.clip(-lit * 1.3, 0, 1) * rim * 0.75)
    # Vesicles: small gas pits, dark with a lit lower lip
    d1, _, _, _ = worley(m, 5000, 336)
    pit = smoothstep(0.0016, 0.0009, d1) * smoothstep(0.003, 0.006, q)
    crust = mix(crust, (0.025, 0.025, 0.03), pit * 0.85)
    # Cooling cracks inside the plates: thin dark lines, a few with a red heart
    cf = fbm(m, 22, 337)
    crack_line = smoothstep(0.0085, 0.003, np.abs(cf - 0.5)) * smoothstep(0.004, 0.008, q)
    crack_line *= smoothstep(0.45, 0.6, fbm(m, 9, 338))  # only in places
    crust = mix(crust, (0.02, 0.018, 0.02), crack_line * 0.85)
    ember_crack = crack_line * smoothstep(0.62, 0.72, fbm(m, 7, 339))
    crust = mix(crust, (0.62, 0.06, 0.0), ember_crack * 0.6)
    # The lava's glow bleeding up onto the rims (more beside a wide river)
    width_here = np.clip(half / widest, 0, 1)
    bleed = np.exp(-q / 0.0035) * (0.45 + 0.55 * width_here) * plate
    crust = mix(crust, (0.70, 0.10, 0.0), bleed * 0.7)
    crust = mix(crust, (0.95, 0.30, 0.0), np.exp(-q / 0.0012) * width_here * plate * 0.5)
    # --- The lava: hottest in the middle of a wide river, deep red at the plate edges
    t = np.clip(edge / np.maximum(half, 1e-6), 0, 1)  # 0 the river's middle .. 1 its bank
    flow = fbm_at(m.p * np.array([1.0, 0.35, 1.0], np.float32), 70, 340, 3)  # streaks in the flow
    heat = (1 - t) ** 1.2 * (0.35 + 0.65 * width_here ** 0.8) * (0.85 + 0.3 * flow)
    heat = np.clip(heat + 0.12 * (1 - t), 0, 1)
    stops = np.array([0.0, 0.22, 0.45, 0.68, 0.86, 1.0], np.float32)
    cols = np.array(
        [(0.42, 0.02, 0.0), (0.78, 0.07, 0.0), (1.0, 0.30, 0.0), (1.0, 0.52, 0.0), (1.0, 0.76, 0.05), (1.0, 0.92, 0.42)],
        np.float32,
    )
    melt = np.stack([np.interp(heat, stops, cols[:, k]) for k in range(3)], -1).astype(np.float32)
    # Dark crust rafts drifting in the wide rivers
    r1, _, _, _ = worley(m, 2600, 341)
    raft = smoothstep(0.0022, 0.0014, r1) * smoothstep(0.55, 0.85, width_here) * (t < 0.75)
    melt = mix(melt, (0.30, 0.03, 0.0), raft * 0.8)
    rgb = mix(crust, melt, lava)
    # Embers: bright flecks on the crust near the rivers
    sparks = scatter(m, 260, 342, weight=np.exp(-q / 0.005) * plate)
    s1, _, si = nearest(m, sparks)
    size = (0.0006 + 0.0009 * np.random.default_rng(343).random(len(sparks)) ** 2)[si]
    ember = smoothstep(size * 1.4, size * 0.6, s1) * plate
    rgb = mix(rgb, (1.0, 0.62, 0.02), ember)
    glow = melt * (0.55 + 0.45 * heat)[..., None] * (lava * (1 - 0.7 * raft))[..., None]
    halo = glow_halo(lava * (0.4 + 0.6 * width_here), 4)
    emit = (
        glow
        + C(0.75, 0.12, 0.0) * (bleed * 0.55 + halo * 0.25 * plate)[..., None]
        + C(1.0, 0.55, 0.0) * ember[..., None]
        + C(0.7, 0.08, 0.0) * (ember_crack * 0.5)[..., None]
    )
    # The fish's own painted creases stay on the crust, not in the molten rivers
    return done(m, rgb, "satin", emit=emit, detail=0.5, hush=lava * 0.95, relief=0)


def glacier(m):  # Ice in strata: layers of teal and cyan, a frosted cap, rime
    m = smooth(m)  # edges along the body, not stepped per slice (playtest 2026-10-10)
    w = (fbm(m, 5, 35) - 0.5) * 0.18
    layer = (m.up + w) * 7
    palette = np.array([(0.03, 0.28, 0.42), (0.08, 0.50, 0.64), (0.24, 0.70, 0.84), (0.50, 0.84, 0.95)], np.float32)
    # Each texel between the layers either side of its nearest boundary, on a ramp a
    # texel and a half wide (a hard switch of layer stair-stepped along the texels)
    frac = layer - np.floor(layer)
    above = np.floor(layer).astype(int) + (frac >= 0.5)
    sd = np.where(frac < 0.5, frac, frac - 1)  # layers above the boundary (+) or below (-)
    a = np.clip(sd / (texel_step(m, layer) * 1.4 + 1e-6) + 0.5, 0, 1)[..., None]
    rgb = palette[above % 4] * a + palette[(above - 1) % 4] * (1 - a)
    seam = smoothstep(0.06, 0.0, np.maximum(sd, 0)) * a[..., 0]
    rgb = mix(rgb, (0.80, 0.95, 1.0), seam * 0.7)
    cap = smoothstep(0.82, 0.86, m.up + w * 0.5) * (1 - m.fin)
    rgb = mix(rgb, (0.80, 0.92, 1.0), cap)
    rgb = mix(rgb, (0.46, 0.82, 0.94), m.fin)
    rgb = mix(rgb, (0.9, 0.97, 1.0), speckle(m, 180, 0.84, seed=36) * 0.7)
    rgb = sheen(m, rgb, 0.2, (0.9, 0.97, 1.0))
    return done(m, rgb, "gloss")


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
    m = smooth(m)  # edges along the body, not stepped per slice (playtest 2026-10-10)
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
    # The arcs stop short of the mouth (playtest 2026-10-16: on the 'Cuda they ran
    # along the gums between the teeth and read as lightning over them), like
    # Riptide's stripes
    calm = m.mouth_zone(0.02, 0.045)
    bolt = smoothstep(lo, hi, ridge) * (1 - calm)
    halo = glow_halo(bolt, 5) * (1 - calm)
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


def prismatic(m):  # Holographic foil: diffraction micro-lines, hue-shifted facet cells, chrome under it
    m = smooth(m)
    value, edge = cells(m, 90, seed=43)
    u, v = flank(m)
    # Diffraction lines: fine stripes whose hue runs through the spectrum along them
    line_phase = (u * 70 + v * 24) % 1.0
    lines = 0.5 + 0.5 * np.cos(2 * np.pi * line_phase)
    # The spectrum skips the orange-peach band (hue 0.02-0.13): mixed with silver
    # and pearl it read as skin to the colour screen (6.4% on the Nibbler, v8)
    hue = (0.13 + 0.87 * ((m.y * 1.2 + value * 0.9 + m.nrm[..., 0] * 0.12 + lines * 0.08) % 1)) % 1
    foil = hsv_to_rgb(np.stack([hue, np.full_like(hue, 0.88), np.full_like(hue, 1.0)], -1))
    silver = board(m, (0.86, 0.88, 0.92))
    rgb = mix(silver, foil, 0.72 + 0.26 * lines)
    rgb = mix(rgb, (1.0, 1.0, 1.0), smoothstep(0.03, 0.0, edge) * 0.5)  # the facets' seams
    rgb = pearl(m, rgb, 0.15, 0.2, 0.55)
    sparkle = speckle(m, 160, 0.85, seed=44)
    rgb = mix(rgb, (1.0, 1.0, 1.0), sparkle * 0.9)
    emit = foil * 0.22 + sparkle[..., None] * 0.6
    height = lines * 0.25 + smoothstep(0.0, 0.05, edge) * 0.4
    return done(m, rgb, "mirror", emit=emit, metal=np.full(m.y.shape, 0.75, np.float32), detail=0.6, relief=1.2, height=height)


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
    m = smooth(m)  # edges along the body, not stepped per slice (playtest 2026-10-10)
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


# ---------------------------------------------------------------------------
# Helpers for the per-fish skin lines (owner, 2026-10-10)
# ---------------------------------------------------------------------------


def cache(m: Fish, key, make):
    """A map made once per fish and shared by every skin that needs it."""
    store = m.__dict__.setdefault("_cache", {})
    if key not in store:
        store[key] = make()
    return store[key]


class Smooth:
    """The fish with its body frame smooth along its length. Fish._cross_section and
    girth() fit the body per slice (48 and 40 along it) and look each texel's slice
    up, so ez, up, r2 (the fins' outline), theta and the flank height all step at
    every slice, and an edge drawn on them is a staircase a slice long (playtest
    2026-10-10: the 'Cuda's Tiger belly line, the Puffer's Tetra stripe, the Moray's
    Void swirl, the Reef Shark's Aurora stripes). Here every fit is interpolated
    between the slices' middles, so edges follow the body. Everything else is the
    fish's own, the fins from blades() too. A recipe opts in with `m = smooth(m)`;
    the skins that don't opt in keep the stepped frame and stay exactly as they
    were."""

    def __init__(self, m: Fish, flatten=0.0):
        self.base = m
        ys, xc, zc, wx, wz = m.slices
        if flatten:
            # Fits smoothed further along the body (in slices), for a line that should
            # run straight down a lumpy body (the Puffer's spines and fins pull its
            # per-slice middle up and down)
            xc, zc, wx, wz = (ndimage.gaussian_filter1d(a, flatten, mode="nearest") for a in (xc, zc, wx, wz))
        y = m.y

        def along(a):
            return np.interp(y, ys, a).astype(np.float32)

        self.xc, self.zc = along(xc), along(zc)
        x, z = m.p[..., 0], m.p[..., 2]
        self.ex = (x - self.xc) / np.maximum(along(wx), 1e-4)
        self.ez = (z - self.zc) / np.maximum(along(wz), 1e-4)
        self.r2 = self.ex * self.ex + self.ez * self.ez
        self.fin = smoothstep(2.2, 3.4, self.r2) * m.cov
        zrel = np.clip(self.ez * 0.5 + 0.5, 0, 1)
        self.up = np.clip(0.6 * zrel + 0.4 * (m.nrm[..., 2] * 0.5 + 0.5), 0, 1)
        self.theta = np.arctan2(z - self.zc, x - self.xc)

    def __getattr__(self, name):
        return getattr(self.base, name)


def smooth(m, flatten=0.0):
    """The fish on the smooth body frame (Smooth), made once per fish (and per
    `flatten`: how many slices more to smooth its fits over)."""
    if isinstance(m, Smooth):
        m = m.base
    return cache(m, f"smooth{flatten}", lambda: Smooth(m, flatten))


def texel_step(m, field):
    """How much `field` changes from a texel to its neighbours on the same piece of
    skin (the largest change to the four round it; across a UV seam the neighbour is
    somewhere else on the body and doesn't count)."""
    f = np.asarray(field, np.float32)
    near = cache(m, "texel_near", lambda: _texel_near(m))
    out = np.zeros_like(f)
    for axis, ok in enumerate(near):
        d = np.where(ok, np.abs(np.diff(f, axis=axis)), 0)
        lo = [(0, 1), (0, 0)] if axis == 0 else [(0, 0), (0, 1)]
        hi = [(1, 0), (0, 0)] if axis == 0 else [(0, 0), (1, 0)]
        out = np.maximum(out, np.maximum(np.pad(d, lo), np.pad(d, hi)))
    return out


def _texel_near(m):
    """Which neighbouring texels (down, right) sit next to each other on the body."""
    p, real = m.p, m.real
    steps = []
    for axis in (0, 1):
        dp = np.linalg.norm(np.diff(p, axis=axis), axis=-1)
        both = (real[1:] & real[:-1]) if axis == 0 else (real[:, 1:] & real[:, :-1])
        steps.append((dp, both))
    typical = float(np.median(np.concatenate([dp[b] for dp, b in steps])))
    return [b & (dp < typical * 4) for dp, b in steps]


def crisp(m, field, at=0.0, texels=1.4, soft=0.0):
    """A hard edge where `field` (drawn on the body in 3D) crosses `at`, anti-aliased:
    a straight ramp at least `texels` texels wide (measured on the skin round each
    texel, so it is as wide as it must be on a thin or a round fish), or `soft` in
    the field's own units where that is wider. A hard edge is still the rule between
    a warm colour and a pale one (orange or gold blended softly into white makes
    peach or beige); a ramp a texel or two wide is far under what the screen counts."""
    w = np.maximum(texel_step(m, field) * texels, soft) * 0.5 + 1e-6
    return np.clip((np.asarray(field, np.float32) - at) / (2 * w) + 0.5, 0, 1).astype(np.float32)


def blades(m: Fish):
    """The fins as they really are, thin blades of the mesh (Fish.fin guesses from the
    body's outline alone and takes a gill cover or a deep head for a fin): (mask 0..1,
    reach 0..1 from the fin's root to its tip, which fin each texel is on, -1 off
    them). A texel is thin when a short step through the skin, either way, lands
    next to the skin again; the meshes hold stray inner faces, so a texel counts as
    fin only where most of the skin round it is thin and it stands out from the
    body's core. Each fin's reach is its distance from the body over its own
    furthest."""
    if isinstance(m, Smooth):
        return blades(m.base)  # the same fins on either frame

    def make():
        rng = np.random.default_rng(17)
        flat_p = m.p.reshape(-1, 3)
        flat_n = m.nrm.reshape(-1, 3)
        real = np.flatnonzero(m.real.reshape(-1))
        rules = FISH.get(m.name, {})
        hint = rules.get("fins")
        if hint == "yellow":
            # The 'Cuda's fins are painted yellow, all of them (its tail is too thick
            # for the blade test)
            hue, sat, val = m.hsv[..., 0], m.hsv[..., 1], m.hsv[..., 2]
            mask = ((hue > 0.08) & (hue < 0.22) & (sat > 0.28) & (val > 0.35)).astype(np.float32)
            mask = ndimage.binary_opening(mask > 0.5, iterations=1).astype(np.float32) * (1 - m.keep)
        elif hint == "ridge":
            # The eel's fin is the ridge along its back, to the tail
            u, v = flank(m)
            hh, _ = girth(m)
            mask = smoothstep(0.8, 0.9, v / np.maximum(hh, 1e-4)) * smoothstep(0.12, 0.18, u)
        else:
            pts = flat_p[real[rng.choice(len(real), size=min(300000, len(real)), replace=False)]]
            tree = cKDTree(pts)
            limit = rules.get("blade", 0.02)
            thin = np.zeros(len(flat_p), bool)
            for depth in (limit * 0.35, limit * 0.6, limit):
                for sign in (1, -1):
                    dist, _ = tree.query(flat_p[real] - sign * flat_n[real] * depth)
                    thin[real[dist < depth * 0.35]] = True
            # The vote: the share of thin skin round each texel (3D, about a fin's width)
            sub = real[rng.choice(len(real), size=min(120000, len(real)), replace=False)]
            _, near = cKDTree(flat_p[sub]).query(flat_p, k=24)
            vote = thin[sub][near].mean(-1).reshape(m.y.shape)
            out = np.sqrt(m.r2)
            mask = smoothstep(0.5, 0.7, vote) * smoothstep(1.0, 1.2, out)
            if rules.get("tail_from"):
                mask = np.maximum(mask, smoothstep(rules["tail_from"], rules["tail_from"] + 0.02, m.y))
        if rules.get("mirror"):
            # Stray inner faces under the Puffer's left flank: its right side's fins,
            # mirrored, are both sides' fins (it's symmetric; posed fish aren't)
            right = real[(flat_p[real, 0] >= m.xc.reshape(-1)[real])]
            right = right[rng.choice(len(right), size=min(200000, len(right)), replace=False)]
            mirror = flat_p.copy()
            mirror[:, 0] = 2 * m.xc.reshape(-1) - mirror[:, 0]
            _, j = cKDTree(flat_p[right]).query(mirror)
            left = (flat_p[:, 0] < m.xc.reshape(-1)).reshape(m.y.shape)
            mask = np.where(left, mask.reshape(-1)[right][j].reshape(m.y.shape), mask)
        mask = np.clip(ndimage.gaussian_filter(mask * m.real, 0.8), 0, 1).astype(np.float32)
        min_top = rules.get("blade_top", 0.02)
        # Body is what's clearly not fin (holes in a fin would pull its reach down)
        solid = ndimage.binary_closing(mask >= 0.5, iterations=3)
        body = ~solid & (mask < 0.3) & m.real
        pts_body = m.p[body]
        pts_body = pts_body[rng.choice(len(pts_body), size=min(150000, len(pts_body)), replace=False)]
        from_body = cKDTree(pts_body).query(flat_p)[0]
        fin_idx = np.flatnonzero(((mask >= 0.5) & m.real).reshape(-1))
        reach_ = np.zeros(len(flat_p), np.float32)
        label = np.full(len(flat_p), -1, int)
        if len(fin_idx) > 50:
            from scipy.sparse.csgraph import connected_components

            sub = fin_idx[rng.choice(len(fin_idx), size=min(40000, len(fin_idx)), replace=False)]
            sub_tree = cKDTree(flat_p[sub])
            graph = sub_tree.sparse_distance_matrix(sub_tree, 0.01, output_type="coo_matrix")
            count, labels = connected_components(graph, directed=False)
            far = from_body[sub]
            sizes = np.bincount(labels, minlength=count)
            order = np.lexsort((far, labels))
            starts = np.searchsorted(labels[order], np.arange(count))
            top = far[order][starts + np.floor((sizes - 1) * 0.97).astype(int)].astype(np.float32)
            dist, j = sub_tree.query(flat_p)
            lab = labels[j]
            # A real fin stands well clear of the body; a patch of stray thin skin
            # lies on it
            ok = (sizes[lab] >= 60) & (top[lab] >= min_top) & (mask.reshape(-1) > 0.05) & (dist < 0.01)
            reach_ = np.where(ok, np.clip(from_body / np.maximum(top[lab], 0.008), 0, 1), 0).astype(np.float32)
            label = np.where(ok, lab, -1)
            # Smoothed over the skin round each texel, so a fin's margin is an even band
            _, near = sub_tree.query(flat_p, k=12)
            reach_ = np.where(ok, reach_[sub][near].mean(-1), 0).astype(np.float32)
        keep = ndimage.gaussian_filter((label >= 0).reshape(m.y.shape).astype(np.float32), 1.0)
        mask = mask * np.clip(keep * 1.6, 0, 1)
        return mask, reach_.reshape(m.y.shape), label.reshape(m.y.shape)

    return cache(m, "blades", make)


def fin_reach(m: Fish):
    """How far out along its fin each fin texel is, 0 at the root .. 1 at the free
    edge, smooth (v12): blades()'s reach measures to the nearest body texel, and on a
    chunky fin (the Nibbler's dorsal) the body test leaves holes, so the reach wanders
    across the fin in patches and a margin drawn on it came out as blotches. Here it
    is the distance from the body's core (the smooth frame's cross-section ellipse),
    spread over each fin's own range; the tail fin also counts its length behind its
    root, so its trailing edge is the edge. 0 off the fins."""
    if isinstance(m, Smooth):
        m = m.base

    def make():
        sm = smooth(m)
        _, _, label = blades(m)
        radial = np.sqrt(sm.r2)
        out = np.zeros(m.y.shape, np.float32)
        for k in np.unique(label):
            if k < 0:
                continue
            sel = (label == k) & m.real
            if sel.sum() < 50:
                continue
            lo, hi = np.percentile(radial[sel], [3, 97])
            r_n = np.clip((radial - lo) / max(hi - lo, 1e-4), 0, 1)
            ys = m.y[sel]
            if np.median(ys) > 0.8:  # the tail fin
                y0 = np.percentile(ys, 3)
                r_n = np.maximum(r_n, np.clip((m.y - y0) / max(np.percentile(ys, 99) - y0, 1e-4), 0, 1))
            out = np.where(label == k, r_n, out)
        on = (label >= 0).astype(np.float32)
        out = ndimage.gaussian_filter(out * on, 1.5) / np.maximum(ndimage.gaussian_filter(on, 1.5), 1e-3)
        return (out * on).astype(np.float32)

    return cache(m, "fin_reach", make)


def flank(m: Fish):
    """Print coordinates, in body lengths: u along the body from the snout, v up from
    the body's mid-line. Both flanks share them, like the same print on each side."""
    return m.y, m.p[..., 2] - m.zc


def side(m: Fish):
    """+1 on the fish's right flank, -1 on its left (to make a print read the same
    way round on both, like a hull number)."""
    return np.where(m.p[..., 0] >= m.xc, 1.0, -1.0).astype(np.float32)


def girth(m: Fish):
    """(per texel, and a function of u) half the body's height in body lengths at that
    place along it, fins left out, so prints can be sized to a thin or a round fish."""

    def make():
        u, v = flank(m)
        body = m.cov & (m.fin < 0.3)
        bins = 40
        idx = np.clip((u * bins).astype(int), 0, bins - 1)
        h = np.zeros(bins)
        for b in range(bins):
            sel = body & (idx == b)
            h[b] = np.percentile(np.abs(v[sel]), 92) if sel.sum() > 50 else 0
        good = h > 0
        h = np.interp(np.arange(bins), np.flatnonzero(good), h[good])
        h = ndimage.gaussian_filter1d(h, 1.5, mode="nearest")
        centres = (np.arange(bins) + 0.5) / bins
        # On the smooth frame, between the slices' middles (not stepped per slice)
        per = np.interp(u, centres, h) if isinstance(m, Smooth) else h[idx]
        return per.astype(np.float32), (lambda at: float(np.interp(at, centres, h)))

    return cache(m, "girth", make)


def segment(u, v, a, b):
    """Distance from (u, v) to the segment a-b, and how far along it (0..1)."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    t = np.clip(((u - a[0]) * dx + (v - a[1]) * dy) / max(dx * dx + dy * dy, 1e-12), 0, 1)
    return np.hypot(u - a[0] - t * dx, v - a[1] - t * dy), t


def scatter(m: Fish, count, seed, weight=None):
    """`count` places on the skin (texel positions, body lengths), more of them where
    `weight` is higher."""
    rng = np.random.default_rng(seed)
    flat = m.p.reshape(-1, 3)
    w = m.real.reshape(-1).astype(np.float64)
    if weight is not None:
        w = w * np.clip(np.asarray(weight, np.float64).reshape(-1), 0, None)
    w /= w.sum()
    idx = rng.choice(len(flat), size=min(count, int((w > 0).sum())), replace=False, p=w)
    return flat[idx].astype(np.float32)


def nearest(m: Fish, pts):
    """Distances to the nearest and second-nearest of `pts`, and the nearest's index."""
    tree = cKDTree(pts)
    d, i = tree.query(m.p.reshape(-1, 3), k=2)
    shape = m.y.shape
    return d[:, 0].reshape(shape), d[:, 1].reshape(shape), i[:, 0].reshape(shape)


def offsets(m: Fish, pts, i):
    """Each texel's offset from its point, flattened onto the skin: (a) along the body
    toward the tail, (b) round it, up on the flanks."""
    o = m.p - pts[i]
    n = m.nrm
    fwd = np.array([0, 1, 0], np.float32) - n * n[..., 1:2]
    fwd /= np.maximum(np.linalg.norm(fwd, axis=-1, keepdims=True), 1e-4)
    up = np.cross(n, fwd) * side(m)[..., None]
    return (o * fwd).sum(-1), (o * up).sum(-1)


def own_lum(m: Fish):
    """The fish's own painted pattern as a tone: 0 its darkest, 1 its lightest."""

    def make():
        sel = m.cov & (m.keep < 0.5)
        lo, hi = np.percentile(m.lum[sel], [3, 97])
        return np.clip((m.lum - lo) / max(hi - lo, 1e-3), 0, 1).astype(np.float32)

    return cache(m, "own_lum", make)


def own_lines(m: Fish):
    """The fish's own painted lines and the edges of its markings (0..1), from the
    texture's color edges (eyes, teeth and lure left out)."""

    def make():
        g = np.zeros(m.y.shape, np.float32)
        for k in range(3):
            c = ndimage.gaussian_filter(m.color[..., k], 1.2)
            g += ndimage.sobel(c, 0) ** 2 + ndimage.sobel(c, 1) ** 2
        g = np.sqrt(g) * (1 - m.keep)
        s = np.percentile(g[m.cov], 96)
        return np.clip(g / max(s, 1e-4), 0, 1).astype(np.float32)

    return cache(m, "own_lines", make)


def polar(m: Fish, yc, vc=0.0, squash=1.0):
    """Polar coordinates on the flanks round a point (yc along the body, vc above the
    mid-line): distance in body lengths and angle."""
    u, v = flank(m)
    du, dv = u - yc, (v - vc) / squash
    return np.hypot(du, dv), np.arctan2(dv, du)


def rays(m: Fish, rho, phi, count, width, seed, length=(0.6, 1.0), taper=0.0):
    """`count` rays bursting from a centre (rho, phi from polar), each of its own
    length (a fraction of `length`, body lengths): returns the ray mask and how far
    out along its ray each texel is (0..1)."""
    rng = np.random.default_rng(seed)
    k = phi / (2 * np.pi) * count
    idx = np.round(k).astype(int) % count
    lens = (length[0] + (length[1] - length[0]) * rng.random(count)).astype(np.float32)
    jitter = ((rng.random(count) - 0.5) * 0.35).astype(np.float32)
    ang = np.abs(k - np.round(k) - jitter[idx]) * 2 * np.pi / count
    out = rho / lens[idx]
    w = width * (1 - taper * np.clip(out, 0, 1))
    mask = smoothstep(w, w * 0.55, rho * ang) * smoothstep(1.0, 0.94, out)
    return mask, np.clip(out, 0, 1)


def hard(mask, lo=0.45, hi=0.55):
    """A mask with a hard edge (no wide blends: an orange or gold blended softly into
    a pale tone makes peach or beige)."""
    return smoothstep(lo, hi, mask)


def round_scales(m: Fish, size):
    """Overlapping scales laid round the body in its own girth (a thin eel gets round
    scales too): each texel's distance from its scale's middle (the rim at 0.5)."""
    hh, _ = girth(m)
    u = m.y / size
    arc = round_angle(m) * np.maximum(hh, 0.02) / size
    row = np.floor(u)
    arc = arc + 0.5 * (row % 2)
    fu, fv = u - row, arc - np.floor(arc)
    return np.sqrt(((fu - 0.15) / 1.1) ** 2 + (fv - 0.5) ** 2)


def own_dark_fins(m: Fish):
    """The fish's own painted dark fin tips (the Reef Shark's), to hush where a skin
    paints its fins another way."""
    fins, _ = fin_parts(m)
    return np.clip(ndimage.gaussian_filter(fins * smoothstep(0.34, 0.2, m.hsv[..., 2]), 1.5) * 1.5, 0, 1)


def fin_parts(m: Fish):
    """(fins 0..1, reach 0..1 along them) from blades()."""
    mask, out, _ = blades(m)
    return mask, out * mask


def body_coat(m: Fish, back, belly, soft=0.25, line=0.5):
    """Countershading only: back to belly about `line` up the body (fins are laid on
    after, from blades())."""
    w = smoothstep(line - soft, line + soft, m.up)
    return mix(board(m, belly), back, w)


def height(m: Fish):
    """(u, v, vn): the print coordinates plus the height up the flank as a share of the
    body's half-height there (-1 belly .. +1 back, fins beyond)."""
    u, v = flank(m)
    hh, _ = girth(m)
    return u, v, v / np.maximum(hh, 1e-4)


def round_angle(m: Fish):
    """The angle round the body, 0 under the belly, +-pi on the back (its seam runs
    along the dorsal ridge, where fins and spines hide it)."""
    return np.arctan2(m.p[..., 0] - m.xc, -(m.p[..., 2] - m.zc))


def at_points(m: Fish, pts, values):
    """A map's value at each of `pts` (nearest texel)."""
    flat = m.p.reshape(-1, 3)
    real = np.flatnonzero(m.real.reshape(-1))
    _, j = cKDTree(flat[real]).query(pts)
    return np.asarray(values).reshape(-1)[real[j]]


def stroke(u, v, a, b, width, taper=0.6, rough=None):
    """A brush stroke from a to b (print coordinates): 0..1, its ends tapered, its
    edge roughened by `rough` (a noise field in body lengths)."""
    d, t = segment(u, v, a, b)
    w = width * (1 - taper + taper * np.sqrt(np.clip(np.sin(np.pi * t), 0, 1)))
    if rough is not None:
        d = d + rough
    return smoothstep(w, w * 0.75, d)


def spiral(u, v, centre, radius, turns_rate=4.0, width=0.0018, flip=1.0):
    """A scroll: a log spiral curling into `centre` (print coordinates), out to
    `radius`, as a thin line."""
    du, dv = u - centre[0], (v - centre[1]) * flip
    r = np.hypot(du, dv) + 1e-6
    th = np.arctan2(dv, du)
    s = (th + turns_rate * np.log(r / radius)) / (2 * np.pi)
    ds = np.abs(s - np.round(s))
    gap = r * (1 - np.exp(-2 * np.pi / turns_rate))
    line = smoothstep(width, width * 0.55, ds * gap)
    return line * smoothstep(radius * 1.02, radius * 0.96, r) * smoothstep(radius * 0.06, radius * 0.12, r)


# ---------------------------------------------------------------------------
# The Nibbler's line: clownfish morphs from its own three painted bands, then wilder
# ---------------------------------------------------------------------------


def nib_bands(m: Fish):
    """The Nibbler's own white bands (head, middle, tail), fitted to its texture: each
    band's middle and half-width all the way round the body, so the bands are crisp
    and follow the painted ones. Returns the band mask, which band each texel is
    nearest (1 head, 2 middle, 3 tail), the distance outside a band and inside one
    (along the body, body lengths) and the face (in front of the head band)."""

    def make():
        s, val = m.hsv[..., 1], m.hsv[..., 2]
        cream = (s < 0.42) & (val > 0.55) & (m.keep < 0.3) & m.real
        spans = ((0.12, 0.32), (0.40, 0.62), (0.71, 0.87))
        nt = 24
        tb = ((m.theta + np.pi) / (2 * np.pi) * nt).astype(int) % nt
        tt = (m.theta + np.pi) / (2 * np.pi) * nt - 0.5
        idx = np.arange(nt)
        dists, fronts = [], []
        for lo, hi in spans:
            sel = cream & (m.y > lo) & (m.y < hi)
            c, w = np.full(nt, np.nan), np.full(nt, np.nan)
            for b in range(nt):
                ys = m.y[sel & (tb == b)]
                if len(ys) > 150:
                    c[b] = np.median(ys)
                    w[b] = 2 * np.median(np.abs(ys - c[b]))
            good = ~np.isnan(c)
            for arr in (c, w):
                arr[~good] = np.interp(idx[~good], idx[good], arr[good], period=nt)
            c = ndimage.gaussian_filter1d(c, 1.0, mode="wrap")
            w = ndimage.gaussian_filter1d(w, 1.0, mode="wrap")
            cc = np.interp(tt, idx, c, period=nt)
            ww = np.interp(tt, idx, w, period=nt)
            dists.append(np.abs(m.y - cc) - ww)
            fronts.append(cc - ww)
        dist = np.stack(dists)
        which = np.argmin(dist, 0) + 1
        d = dist.min(0)
        fins, _ = fin_parts(m)
        paired = hard(fins * smoothstep(0.8, 0.65, m.up))
        band = smoothstep(0.0015, -0.0015, d) * (1 - paired)
        outside = np.where(band > 0.5, 0.0, np.maximum(d, 0)).astype(np.float32)
        depth = np.maximum(-d, 0).astype(np.float32) * band
        face = (m.y < fronts[0]).astype(np.float32) * (1 - band)
        return band.astype(np.float32), which, outside, depth, face

    return cache(m, "nib_bands", make)


def nib_percula(m):  # Percula: vivid orange, three crisp white bands edged in black
    band, which, outside, depth, face = nib_bands(m)
    fins, tip = fin_parts(m)
    rgb = body_coat(m, (0.96, 0.34, 0.0), (1.0, 0.50, 0.02), soft=0.35)
    rgb = mix(rgb, (1.0, 0.46, 0.0), fins)
    rgb = mix(rgb, SNOW, band)
    rim = smoothstep(0.0072, 0.0052, outside) * (1 - band)
    rgb = mix(rgb, INKY, rim)
    edge = hard(smoothstep(0.86, 0.92, tip)) * (1 - band)
    rgb = mix(rgb, INKY, edge)
    return done(m, rgb, "gloss", detail=0.9)


def nib_tomato(m):  # Tomato clownfish: red-orange darkening to red-black, one head band
    band, which, outside, depth, face = nib_bands(m)
    fins, tip = fin_parts(m)
    head = band * (which == 1)
    dark = smoothstep(0.34, 0.68, m.y) * smoothstep(0.98, 0.6, m.up) * (1 - fins)
    rgb = body_coat(m, (0.88, 0.14, 0.02), (1.0, 0.30, 0.02), soft=0.35)
    rgb = mix(rgb, (0.22, 0.012, 0.02), dark * 0.94)
    rgb = mix(rgb, (0.82, 0.08, 0.03), fins)
    rgb = mix(rgb, SNOW, head)
    rim = smoothstep(0.0062, 0.0044, outside) * (which == 1) * (1 - band)
    rgb = mix(rgb, INKY, rim)
    # The other two painted bands' edges would show as ghost lines through the red
    hush = smoothstep(0.012, 0.0, outside + depth) * (which > 1)
    return done(m, rgb, "gloss", detail=0.9, hush=hush)


def nib_maroon(m):  # Maroon clownfish: deep wine body, three thin golden bands
    band, which, outside, depth, face = nib_bands(m)
    fins, tip = fin_parts(m)
    gold = hard(smoothstep(0.022, 0.028, depth)) * band
    # A deep garnet wine: the browner maroons scored 0.15-0.6 on the moderation
    # classifier with the pale eyes on them (screen, 2026-10-10); this one 0.08.
    # v12: with the whole eye kept, the sclera's own UV islands sit pale on the wine
    # in the atlas, and the old wine (0.28, 0.0, 0.08) scored 0.31 once JPEG-packed;
    # a brighter garnet scores 0.09
    rgb = body_coat(m, (0.36, 0.0, 0.10), (0.60, 0.02, 0.14), soft=0.35)
    rgb = mix(rgb, (0.40, 0.0, 0.10), fins)
    rgb = mix(rgb, (1.0, 0.76, 0.0), gold)
    hush = smoothstep(0.01, 0.0, outside) + smoothstep(0.01, 0.0, depth) * band
    return done(m, rgb, "satin", detail=0.7, hush=np.clip(hush, 0, 1))


def nib_midnight(m):  # Black ocellaris: glossy black, bright white bands, an orange face
    band, which, outside, depth, face = nib_bands(m)
    fins, tip = fin_parts(m)
    rgb = body_coat(m, (0.025, 0.025, 0.035), (0.05, 0.05, 0.065), soft=0.3)
    orange = hard(face * smoothstep(0.0075, 0.0095, outside)) * (1 - fins)
    rgb = mix(rgb, (1.0, 0.40, 0.0), orange)
    rgb = mix(rgb, (0.03, 0.03, 0.045), fins)
    rgb = mix(rgb, SNOW, band)
    return done(m, rgb, "gloss", detail=0.8)


# ---------------------------------------------------------------------------
# The 'Cuda's line: barracuda species, then chrome and a comet
# ---------------------------------------------------------------------------


def cuda_great(m):  # Great barracuda: steel flank, slanted bars, black blotches
    fins, tip = fin_parts(m)
    u, v, vn = height(m)
    rgb = body_coat(m, (0.28, 0.36, 0.46), (0.80, 0.84, 0.90), soft=0.2)
    rgb = sheen(m, rgb, 0.3, (0.88, 0.94, 1.0))
    bars = stripes(m, 27, 0.32, wobble=0.1, slant=-0.22, seed=101, edge=0.07)
    bars *= smoothstep(0.0, 0.3, vn) * smoothstep(0.13, 0.19, u) * smoothstep(0.84, 0.74, u)
    rgb = mix(rgb, (0.14, 0.18, 0.25), bars * (1 - fins) * 0.9)
    zone = smoothstep(0.48, 0.56, m.y) * smoothstep(0.9, 0.82, m.y) * smoothstep(0.1, -0.35, vn) * (1 - fins)
    pts = scatter(m, 22, 102, weight=zone)
    d1, _, i = nearest(m, pts)
    r = (0.005 + 0.006 * np.random.default_rng(103).random(len(pts)))[i]
    rgb = mix(rgb, INKY, smoothstep(r * 1.15, r * 0.85, d1) * (1 - fins))
    rgb = mix(rgb, (0.34, 0.40, 0.46), fins)
    rgb = mix(rgb, (0.10, 0.12, 0.16), fins * smoothstep(0.84, 0.88, m.y))
    silver = smoothstep(0.55, 0.3, m.up) * (1 - fins)
    return done(m, rgb, "gloss", metal=silver * 0.45)


def cuda_yellowtail(m):  # Yellowtail barracuda: blue back, silver flank, one yellow stripe
    # On the smooth frame, the stripe's and tail's hard edges anti-aliased (crisp):
    # stepped per slice and squeezed under a texel, they stair-stepped (2026-10-11)
    m = smooth(m)
    fins, tip = fin_parts(m)
    u, v, vn = height(m)
    rgb = body_coat(m, (0.16, 0.32, 0.62), (0.82, 0.86, 0.94), soft=0.12, line=0.56)
    rgb = sheen(m, rgb, 0.3, (0.88, 0.94, 1.0))
    stripe = crisp(m, 0.175 - np.abs(vn - 0.02)) * smoothstep(0.03, 0.06, u) * (1 - fins)
    rgb = mix(rgb, (1.0, 0.80, 0.0), stripe)
    rgb = mix(rgb, (0.50, 0.58, 0.70), fins)
    rgb = mix(rgb, (1.0, 0.78, 0.0), crisp(m, fins * smoothstep(0.84, 0.87, m.y) - 0.5))
    silver = smoothstep(0.55, 0.3, m.up) * (1 - fins) * (1 - stripe)
    return done(m, rgb, "gloss", metal=silver * 0.4)


def cuda_chevron(m):  # Chevron barracuda: bronze-olive back with dark chevrons pointing forward
    # Its own colour among the 'Cuda's Commons (playtest 2026-10-10: Great, Chevron and
    # Blackfin were all silver with dark marks): a bronze-olive back over a silver
    # belly. Almost no blue in the bronze (blue in a bronze is tan, a skin tone), and
    # red only a little over green, so its blend into the silver stays olive-grey
    m = smooth(m)
    fins, tip = fin_parts(m)
    u, v, vn = height(m)
    rgb = body_coat(m, (0.42, 0.355, 0.05), (0.70, 0.74, 0.80), soft=0.07, line=0.47)
    rgb = mix(rgb, (0.30, 0.25, 0.035), smoothstep(0.7, 0.95, m.up) * 0.6)
    rgb = sheen(m, rgb, 0.25, (0.85, 0.9, 1.0))
    t = (u - 0.9 * np.abs(v - 0.008)) * 22 + 0.15 * (fbm(m, 6, 104) - 0.5)
    chev = smoothstep(0.62, 0.7, 0.5 + 0.5 * np.cos(2 * np.pi * t))
    chev *= smoothstep(0.15, 0.2, u) * smoothstep(0.86, 0.78, u) * smoothstep(-0.75, -0.5, vn) * smoothstep(1.0, 0.8, vn)
    rgb = mix(rgb, (0.085, 0.075, 0.025), chev * (1 - fins))
    rgb = mix(rgb, (0.27, 0.25, 0.12), fins)
    rgb = mix(rgb, (0.10, 0.09, 0.04), fins * smoothstep(0.6, 0.85, tip))
    silver = smoothstep(0.5, 0.3, m.up) * (1 - fins)
    return done(m, rgb, "satin", metal=silver * 0.35)


def cuda_blackfin(m):  # Blackfin barracuda: deep navy back, silver belly, black fins
    # Deep navy down past the middle over a bright silver belly, so it reads as a dark
    # fish from far off (playtest 2026-10-11: steel blue was still Great's twin at a
    # distance, where Great's bars blur into silver), and fins black from a dusky root
    m = smooth(m)
    fins, tip = fin_parts(m)
    u, v, vn = height(m)
    rgb = body_coat(m, (0.07, 0.12, 0.24), (0.80, 0.84, 0.90), soft=0.06, line=0.44)
    rgb = mix(rgb, (0.03, 0.06, 0.13), smoothstep(0.7, 0.95, m.up) * 0.8)
    rgb = sheen(m, rgb, 0.4, (0.88, 0.94, 1.0))
    lateral = smoothstep(0.06, 0.025, np.abs(vn - 0.04)) * smoothstep(0.12, 0.2, u) * smoothstep(0.9, 0.82, u)
    rgb = mix(rgb, (0.22, 0.30, 0.42), lateral * (1 - fins) * 0.6)
    rgb = mix(rgb, (0.12, 0.14, 0.18), fins)
    black = hard(smoothstep(0.18, 0.34, tip)) * fins
    rgb = mix(rgb, (0.02, 0.02, 0.03), black)
    metal = 0.55 * (1 - fins)
    rough = 0.22 + 0.5 * fins
    return done(m, rgb, "gloss", metal=metal, rough=rough)


def cuda_chrome(m):  # Gunmetal chrome: dark mirror metal, blue-violet speed streaks raking back
    # Dark gunmetal, not the pale silver-blue it shared with Lunar (playtest
    # 2026-10-10). The streaks are blue-violet in a wide soft glow: thin near-white
    # lines on black score high on the moderation classifier
    m = smooth(m)
    fins, tip = fin_parts(m)
    u, v, vn = height(m)
    e = m.nrm[..., 2] * 0.6 + np.clip(vn, -1, 1) * 0.4
    # Still gunmetal, lifted (playtest 2026-10-16: dark and flat from the side): the
    # sky and ground reflections are mid-toned, and two bright cool bands (the sky
    # just over the horizon line, a lower reflection under it) make it read as
    # polished metal at a distance. Cool and a little blue-violet: neutral grey lines
    # on grey scored high on the classifier (Battle-Scarred)
    sky = mix(board(m, (0.62, 0.66, 0.76)), (0.32, 0.36, 0.48), smoothstep(0.1, 0.95, e))
    ground = mix(board(m, (0.24, 0.25, 0.31)), (0.48, 0.51, 0.59), smoothstep(-0.15, -0.9, e))
    rgb = mix(ground, sky, crisp(m, e - 0.02))
    band_hi = crisp(m, 0.035 - np.abs(e - 0.2))
    band_lo = crisp(m, 0.04 - np.abs(e + 0.55))
    rgb = mix(rgb, (0.78, 0.82, 0.96), band_hi * 0.9)
    rgb = mix(rgb, (0.60, 0.64, 0.80), band_lo * 0.8)
    rgb = mix(rgb, (0.04, 0.05, 0.08), smoothstep(0.05, 0.0, np.abs(e)))
    streak_p = np.stack([m.ex * 0.05, u * 2.2, vn * 16], -1).astype(np.float32)
    n1 = value_noise(streak_p, 1.0, 105)
    fade = smoothstep(0.95, 0.15, u) * smoothstep(0.0, 0.05, u) * (1 - fins)
    streak = smoothstep(0.70, 0.79, n1) * fade
    halo = glow_halo(streak, 4) * fade
    rgb = mix(rgb, (0.20, 0.18, 0.56), halo * 0.55)
    rgb = mix(rgb, (0.46, 0.42, 0.98), streak)
    rgb = mix(rgb, (0.12, 0.10, 0.34), smoothstep(0.26, 0.2, n1) * fade * 0.6)
    edge = hard(smoothstep(0.7, 0.78, tip))
    rgb = mix(rgb, (0.02, 0.02, 0.03), edge)
    # Little metal (0.7 before): metal shows the dark blue water, not its own colour,
    # so the polish is painted in (the bands) and the metal only adds a sheen
    metal = 0.2 * (1 - edge) * (1 - 0.5 * streak)
    return done(m, rgb, "mirror", metal=metal, rough=0.14 + 0.6 * edge + 0.12 * streak, detail=0.4)


def cuda_comet(m):  # A comet: a blazing cyan head, a tail of sparks pouring back
    fins, tip = fin_parts(m)
    u, v, vn = height(m)
    rgb = body_coat(m, (0.012, 0.025, 0.11), (0.03, 0.06, 0.20), soft=0.3)
    core = smoothstep(0.24, 0.06, u)
    hot = smoothstep(0.1, 0.02, u)
    spread = 0.35 + 1.1 * u
    cone = smoothstep(1.0, 0.4, np.abs(vn) / spread)
    env = np.exp(-np.clip(u - 0.12, 0, None) * 2.0) * smoothstep(0.05, 0.16, u)
    streak_p = np.stack([m.ex * 0.05, u * 2.6, vn / spread * 6], -1).astype(np.float32)
    lines = smoothstep(0.48, 0.74, value_noise(streak_p, 1.0, 106))
    tail = np.clip(env * cone * (0.3 + 0.9 * lines), 0, 1)
    pts = scatter(m, 320, 107, weight=env * cone + 0.02)
    d1, _, i = nearest(m, pts)
    r = (0.002 + 0.003 * np.random.default_rng(108).random(len(pts)))[i]
    sparks = smoothstep(r, r * 0.4, d1)
    tail_col = mix(board(m, (0.05, 0.72, 1.0)), (0.30, 0.30, 1.0), smoothstep(0.3, 0.85, u))
    core_col = mix(board(m, (0.10, 0.70, 1.0)), (0.62, 0.93, 1.0), hot)
    stars = speckle(m, 220, 0.9, seed=109) * (1 - core)
    rgb = mix(rgb, (0.45, 0.55, 0.95), stars * 0.6)
    rgb = mix(rgb, tail_col, tail)
    rgb = mix(rgb, (0.55, 0.90, 1.0), sparks)
    rgb = mix(rgb, core_col, core)
    edge = smoothstep(0.6, 0.9, tip)
    rgb = mix(rgb, (0.20, 0.45, 1.0), edge * 0.7)
    halo = glow_halo(np.clip(sparks, 0, 1), 4)
    emit = (
        core_col * (core * 0.65)[..., None]
        + tail_col * (tail * 0.6)[..., None]
        + C(0.4, 0.85, 1.0) * (sparks * 0.8)[..., None]
        + C(0.1, 0.4, 1.0) * (halo * 0.3)[..., None]
        + C(0.2, 0.45, 1.0) * (edge * 0.4)[..., None]
        + C(0.4, 0.5, 0.9) * (stars * 0.3)[..., None]
    )
    return done(m, rgb, "gloss", emit=emit, detail=0.5)


# ---------------------------------------------------------------------------
# The Puffer's line: real puffers, then an urchin, a reef and a sun
# ---------------------------------------------------------------------------


def point_y(m: Fish, pts):
    """Body-frame y (0 snout .. 1 tail) of points from scatter()."""
    return pts[:, 1] - m.mn[1] / max(m.length, 1e-6)


def puf_guineafowl(m):  # Guineafowl puffer: charcoal, densely spotted white, finer on the face
    fins, tip = fin_parts(m)
    rgb = body_coat(m, (0.07, 0.07, 0.09), (0.11, 0.11, 0.14), soft=0.3)
    face = smoothstep(0.3, 0.12, m.y)
    pts = scatter(m, 1300, 201, weight=1 + 2.5 * face)
    d1, _, i = nearest(m, pts)
    py = point_y(m, pts)
    rng = np.random.default_rng(202)
    r = (0.0072 * (0.5 + 0.5 * smoothstep(0.12, 0.34, py)) * (0.8 + 0.4 * rng.random(len(pts))))[i]
    dots = smoothstep(r * 1.12, r * 0.86, d1)
    rgb = mix(rgb, (0.08, 0.08, 0.10), fins)
    rgb = mix(rgb, (0.80, 0.85, 0.94), dots * (1 - fins * 0.5))
    return done(m, rgb, "satin", detail=0.8)


def puf_golden(m):  # Golden puffer: saturated lemon yellow, a few dark speckles on the back
    fins, tip = fin_parts(m)
    rgb = body_coat(m, (1.0, 0.78, 0.0), (1.0, 0.88, 0.08), soft=0.3)
    rgb = mix(rgb, (1.0, 0.72, 0.0), fins)
    pts = scatter(m, 45, 203, weight=smoothstep(0.6, 0.8, m.up) * (1 - fins))
    d1, _, i = nearest(m, pts)
    r = (0.0035 + 0.003 * np.random.default_rng(204).random(len(pts)))[i]
    rgb = mix(rgb, (0.10, 0.10, 0.04), smoothstep(r * 1.15, r * 0.8, d1))
    return done(m, rgb, "gloss", detail=0.9)


def puf_starry(m):  # Starry puffer: blue-grey back with large black spots, cool white belly
    fins, tip = fin_parts(m)
    rgb = body_coat(m, (0.36, 0.44, 0.54), (0.84, 0.88, 0.96), soft=0.16, line=0.42)
    pts = scatter(m, 150, 205, weight=smoothstep(0.38, 0.55, m.up))
    d1, _, i = nearest(m, pts)
    r = (0.012 + 0.008 * np.random.default_rng(206).random(len(pts)))[i]
    spot = smoothstep(r * 1.08, r * 0.92, d1) * smoothstep(0.3, 0.42, m.up)
    rgb = mix(rgb, (0.46, 0.50, 0.56), fins)
    rgb = mix(rgb, (0.04, 0.04, 0.06), spot)
    return done(m, rgb, "satin", detail=0.9)


def puf_green(m):  # Green spotted puffer: lime-olive back, round dark spots, pale belly
    fins, tip = fin_parts(m)
    rgb = body_coat(m, (0.40, 0.54, 0.05), (0.72, 0.84, 0.16), soft=0.12, line=0.48)
    rgb = mix(rgb, (0.84, 0.90, 0.96), smoothstep(0.26, 0.16, m.up))
    pts = scatter(m, 190, 207, weight=smoothstep(0.42, 0.6, m.up))
    d1, _, i = nearest(m, pts)
    r = (0.010 + 0.006 * np.random.default_rng(208).random(len(pts)))[i]
    rgb = mix(rgb, (0.05, 0.10, 0.04), smoothstep(r * 1.1, r * 0.9, d1) * smoothstep(0.36, 0.46, m.up) * (1 - fins))
    rgb = mix(rgb, (0.40, 0.66, 0.30), fins)
    rgb = mix(rgb, (0.60, 0.82, 0.40), fins * smoothstep(0.6, 0.95, tip) * 0.6)
    return done(m, rgb, "gloss", detail=0.9)


def puf_urchin(m):  # A sea urchin: purple-black, teal spines bursting from each flank
    fins, tip = fin_parts(m)
    rgb = body_coat(m, (0.07, 0.02, 0.11), (0.12, 0.04, 0.17), soft=0.3)
    rho, phi = polar(m, 0.42, 0.0)
    long_, out = rays(m, rho, phi, 44, 0.0065, seed=210, length=(0.24, 0.40), taper=0.6)
    short, out2 = rays(m, rho, phi + np.pi / 44, 44, 0.005, seed=211, length=(0.10, 0.2), taper=0.6)
    start = smoothstep(0.04, 0.055, rho)
    spines = np.clip(np.maximum(long_, short) * start, 0, 1)
    along = np.where(long_ >= short, out, out2)
    col = mix(board(m, (0.0, 0.55, 0.82)), (0.28, 1.0, 0.90), smoothstep(0.45, 0.9, along))
    halo = glow_halo(spines, 6)
    rgb = mix(rgb, (0.16, 0.12, 0.50), halo * 0.55)
    rgb = mix(rgb, col, spines)
    centre = smoothstep(0.04, 0.035, rho)
    rgb = mix(rgb, (0.03, 0.01, 0.05), centre)
    rgb = mix(rgb, (0.08, 0.66, 0.78), smoothstep(0.005, 0.0, np.abs(rho - 0.037)))
    rgb = mix(rgb, (0.14, 0.05, 0.22), fins * (1 - spines))
    return done(m, rgb, "gloss", detail=0.6)


def puf_coral_bloom(m):  # Living coral: colonies of star polyps and branching coral over teal
    fins, tip = fin_parts(m)
    rgb = body_coat(m, (0.0, 0.38, 0.42), (0.04, 0.52, 0.52), soft=0.3)
    palette = np.array([(1.0, 0.46, 0.0), (0.52, 0.18, 0.92), (1.0, 0.82, 0.0)], np.float32)
    bright = np.array([(1.0, 0.76, 0.0), (0.78, 0.60, 1.0), (1.0, 0.96, 0.32)], np.float32)
    rng = np.random.default_rng(221)
    heads = scatter(m, 12, 224, weight=1 - fins)
    hd, _, hi = nearest(m, heads)
    R = (0.11 + 0.06 * rng.random(len(heads)))[hi]
    edge_noise = 1 + 0.35 * (fbm(m, 12, 225) - 0.5)
    colony = hard(smoothstep(R * 1.02, R * 0.97, hd * edge_noise))
    kind = rng.integers(0, 3, len(heads))[hi]
    pts = scatter(m, 1300, 222)
    d1, d2, i = nearest(m, pts)
    a, b = offsets(m, pts, i)
    ang = np.arctan2(b, a) + i * 1.3
    cell = (d1 + d2) * 0.5
    star_r = cell * (0.44 + 0.28 * np.cos(5 * ang))
    star = smoothstep(star_r * 1.05, star_r * 0.85, d1)
    eye = smoothstep(cell * 0.13, cell * 0.08, d1)
    rim = smoothstep(cell * 0.14, cell * 0.05, d2 - d1)
    polyp = palette[kind] * (0.62 + 0.38 * smoothstep(1.0, 0.3, d1 / np.maximum(cell, 1e-5)))[..., None]
    polyp = mix(polyp, bright[kind], star)
    polyp = mix(polyp, palette[kind] * 0.55, eye)
    polyp = mix(polyp, (0.02, 0.18, 0.20), rim * 0.85)
    rgb = mix(rgb, polyp, colony * (1 - fins * 0.5))
    ridge = 1 - np.abs(fbm_at(body_coords(m), 6, 223) * 2 - 1)
    rlo, rhi = np.percentile(ridge[m.real], [90, 95])
    branch = smoothstep(rlo, rhi, ridge) * (1 - colony)
    bkind = (kind + 1) % 3
    rgb = mix(rgb, palette[bkind], branch)
    rgb = mix(rgb, bright[bkind], smoothstep(rhi, rhi + (1 - rhi) * 0.5, ridge) * (1 - colony))
    rgb = mix(rgb, (0.0, 0.30, 0.36), fins * (1 - colony))
    return done(m, rgb, "satin", detail=0.6)


def puf_sunburst(m):  # A sun: gold rays over deep orange, a glowing gold core
    fins, tip = fin_parts(m)
    rgb = body_coat(m, (0.86, 0.24, 0.0), (0.98, 0.38, 0.0), soft=0.3)
    rho, phi = polar(m, 0.46, 0.0)
    spec_long = dict(count=10, width=0.07, seed=230, length=(0.33, 0.40), taper=0.93)
    spec_short = dict(count=10, width=0.05, seed=231, length=(0.21, 0.26), taper=0.93)

    def burst(spec, grow=0.0, turn=0.0):
        return rays(m, rho, phi + turn, spec["count"], spec["width"] + grow, spec["seed"], spec["length"], spec["taper"])[0]

    ray = hard(np.maximum(burst(spec_long), burst(spec_short, turn=np.pi / 10)))
    outline = hard(np.maximum(burst(spec_long, 0.012), burst(spec_short, 0.012, np.pi / 10))) * (1 - ray)
    core = hard(smoothstep(0.08, 0.075, rho))
    ring = hard(smoothstep(0.005, 0.003, np.abs(rho - 0.09)))
    gold = (1.0, 0.70, 0.0)
    rgb = mix(rgb, (0.62, 0.10, 0.0), outline)
    rgb = mix(rgb, gold, ray)
    rgb = mix(rgb, (1.0, 0.86, 0.10), ray * smoothstep(0.35, 0.0, rho) * 0.5)
    rgb = mix(rgb, (0.56, 0.08, 0.0), ring)
    rgb = mix(rgb, (1.0, 0.84, 0.12), core)
    rgb = mix(rgb, (0.92, 0.22, 0.0), fins * (1 - ray))
    rgb = mix(rgb, gold, hard(smoothstep(0.72, 0.8, tip)))
    glow = glow_halo(core, 6)
    emit = C(1.0, 0.62, 0.0) * core[..., None] + C(0.9, 0.42, 0.0) * (glow * 0.4 * (1 - core))[..., None]
    emit = emit + C(0.5, 0.3, 0.0) * (ray * 0.2)[..., None]
    metal = np.clip(ray * 0.3 + core * 0.2, 0, 1)
    return done(m, rgb, "gloss", emit=emit, metal=metal, rough=0.25 - 0.1 * ray, detail=0.6)


# ---------------------------------------------------------------------------
# The Moray's line: moray species, then a serpent, a ribbon eel and jade
# ---------------------------------------------------------------------------


def mor_green(m):  # Green moray: rich olive-green, subtle mottling, a yellower throat
    fins, tip = fin_parts(m)
    u, v, vn = height(m)
    rgb = body_coat(m, (0.18, 0.30, 0.04), (0.38, 0.48, 0.07), soft=0.3)
    mott = fbm_at(body_coords(m), 9, 240)
    rgb = mix(rgb, (0.11, 0.19, 0.03), smoothstep(0.5, 0.64, mott) * 0.45)
    throat = smoothstep(0.26, 0.1, u) * smoothstep(0.5, 0.25, m.up)
    rgb = mix(rgb, (0.56, 0.60, 0.05), throat * 0.75)
    edge = smoothstep(0.94, 0.99, vn) * fins * smoothstep(0.24, 0.32, u)
    rgb = mix(rgb, (0.30, 0.54, 0.08), np.clip(edge * 1.5, 0, 1))
    return done(m, rgb, "gloss", detail=0.7)


def mor_zebra(m):  # Zebra moray: near-black with about 30 thin cool-white rings
    u, v, vn = height(m)
    rgb = body_coat(m, (0.06, 0.06, 0.09), (0.09, 0.08, 0.12), soft=0.3)
    ring = stripes(m, 32, 0.24, wobble=0.18, slant=0.3, seed=241, edge=0.05) * smoothstep(0.03, 0.06, u)
    halo = glow_halo(ring, 3)
    rgb = mix(rgb, (0.18, 0.22, 0.34), halo * 0.35)
    rgb = mix(rgb, (0.74, 0.82, 0.95), ring)
    return done(m, rgb, "gloss", detail=0.6)


def mor_snowflake(m):  # Snowflake moray: cool grey, black dendritic blotches with yellow hearts
    rgb = body_coat(m, (0.48, 0.52, 0.58), (0.62, 0.66, 0.72), soft=0.3)
    pts = scatter(m, 85, 242)
    d1, _, i = nearest(m, pts)
    a, b = offsets(m, pts, i)
    ang = np.arctan2(b, a)
    rng = np.random.default_rng(243)
    n = len(pts)
    R = (0.042 * (0.7 + 0.6 * rng.random(n)))[i]
    k = rng.integers(5, 8, n)[i]
    rot = (rng.random(n) * 2 * np.pi)[i]
    arm = np.abs(np.cos((ang + rot) * k / 2)) ** 1.6
    twig = np.abs(np.cos((ang + rot) * k * 1.5 + d1 / R * 5)) ** 3
    wobble = 0.85 + 0.3 * (fbm(m, 30, 244) - 0.5) * 2
    rr = R * (0.36 + 0.5 * arm + 0.14 * twig) * wobble
    blot = smoothstep(rr * 1.04, rr * 0.9, d1)
    heart = smoothstep(R * 0.15, R * 0.1, d1)
    rgb = mix(rgb, (0.04, 0.04, 0.06), blot)
    rgb = mix(rgb, (1.0, 0.82, 0.0), heart)
    rgb = mix(rgb, (0.08, 0.08, 0.10), speckle(m, 160, 0.86, seed=245) * 0.7)
    return done(m, rgb, "gloss", detail=0.7)


def mor_honeycomb(m):  # Honeycomb moray: golden cells under a dark net, small on the head
    w = 1 + 7 * smoothstep(0.26, 0.06, m.y)
    pts = scatter(m, 360, 250, weight=w)
    d1, d2, i = nearest(m, pts)
    rel = (d2 - d1) / (d2 + d1 + 1e-6)
    netm = smoothstep(0.17, 0.12, rel)
    rgb = body_coat(m, (0.96, 0.66, 0.0), (1.0, 0.80, 0.0), soft=0.3)
    rgb = mix(rgb, (0.84, 0.50, 0.0), smoothstep(0.45, 0.2, rel) * 0.45)
    rgb = mix(rgb, (0.05, 0.05, 0.06), netm)
    return done(m, rgb, "gloss", detail=0.7)


def mor_serpent(m):  # A sea serpent: emerald dragon scales, each edged in gold
    rgb = body_coat(m, (0.0, 0.24, 0.13), (0.06, 0.58, 0.32), soft=0.3)
    d = round_scales(m, 0.042)
    rgb = rgb * (1.12 - 0.5 * smoothstep(0.15, 0.5, d))[..., None]
    gold = hard(smoothstep(0.07, 0.03, np.abs(d - 0.5)), 0.4, 0.6)
    rgb = mix(rgb, (1.0, 0.70, 0.0), gold)
    rgb = sheen(m, rgb, 0.18, (0.80, 1.0, 0.86))
    # An even metal map: thin lines of metal on black read as line art to the
    # moderation classifier (0.17 here, 0.5-0.98 for a traced pattern)
    return done(m, rgb, "gloss", metal=np.full(m.y.shape, 0.3, np.float32), detail=0.6)


def mor_ribbon(m):  # Ribbon eel: electric cobalt, a yellow dorsal fin edge and jaw
    m = smooth(m)  # the lateral line along the body, not stepped per slice
    fins, tip = fin_parts(m)
    u, v, vn = height(m)
    # More contrast down the flank (playtest 2026-10-16: "mostly plain blue" from the
    # side): a deep navy-cobalt back, an electric blue flank, a bright blue belly, a
    # crisp bright cyan lateral line in a navy groove, and a wider yellow dorsal edge
    rgb = body_coat(m, (0.0, 0.07, 0.48), (0.16, 0.50, 1.0), soft=0.22)
    rgb = mix(rgb, (0.03, 0.30, 1.0), smoothstep(0.45, 0.0, np.abs(vn + 0.05)) * 0.6)
    lateral = crisp(m, 0.07 - np.abs(vn + 0.08)) * (1 - fins) * smoothstep(0.09, 0.14, u) * smoothstep(0.98, 0.9, u)
    rgb = mix(rgb, (0.0, 0.08, 0.40), crisp(m, 0.14 - np.abs(vn + 0.08)) * (1 - fins) * smoothstep(0.09, 0.14, u) * 0.6)
    rgb = mix(rgb, (0.22, 0.86, 1.0), lateral)
    jaw = hard(smoothstep(0.075, 0.065, u) + smoothstep(0.16, 0.14, u) * smoothstep(0.42, 0.36, m.up))
    rgb = mix(rgb, (1.0, 0.84, 0.0), jaw)
    edge = hard(smoothstep(0.86, 0.9, vn) * fins)
    rgb = mix(rgb, (1.0, 0.84, 0.0), edge)
    return done(m, rgb, "gloss", detail=0.6)


def mor_jade(m):  # Jade dragon: polished jade, glowing gold filigree scrolls on the flanks
    u, v, vn = height(m)
    hh, at = girth(m)
    P = body_coords(m)
    f = fbm_at(P, 5, 260) + 0.25 * (fbm_at(P, 14, 261) - 0.5)
    # A cool teal jade: the greener jades scored 0.26-0.6 on the moderation classifier
    # once JPEG-packed (screen, 2026-10-10); this one 0.01
    rgb = mix(board(m, (0.0, 0.24, 0.24)), (0.24, 0.66, 0.62), smoothstep(0.38, 0.7, f))
    vein = smoothstep(0.018, 0.0, np.abs(fbm_at(P, 7, 262) - 0.5))
    rgb = mix(rgb, (0.0, 0.18, 0.14), vein * 0.4)
    rgb = mix(rgb, (0.50, 0.84, 0.74), smoothstep(0.012, 0.0, np.abs(fbm_at(P, 11, 263) - 0.5)) * 0.25)
    rgb = mix(rgb, (0.46, 0.86, 0.68), smoothstep(0.6, 1.0, m.nrm[..., 2]) * 0.18)
    fil = np.zeros_like(u)
    period = 0.17
    for k, uc in enumerate(np.arange(0.17, 0.92, period / 2)):
        h = at(uc)
        up_ = 1 if k % 2 == 0 else -1
        centre = (uc, up_ * 0.42 * h)
        fil = np.maximum(fil, spiral(u, v, centre, 0.5 * h, 3.6, 0.0016, flip=up_))
    # The vine the scrolls hang from, crest to trough
    vine = smoothstep(0.0017, 0.001, np.abs(v - 0.42 * hh * np.cos(2 * np.pi * (u - 0.17) / period)))
    fil = np.maximum(fil, vine * smoothstep(0.14, 0.17, u) * smoothstep(0.95, 0.92, u))
    fil = hard(fil, 0.35, 0.6)
    rgb = mix(rgb, (1.0, 0.72, 0.0), fil)
    rgb = sheen(m, rgb, 0.22, (0.86, 1.0, 0.92))
    emit = C(0.6, 0.4, 0.0) * fil[..., None] + C(0.4, 0.26, 0.0) * (glow_halo(fil, 2) * 0.25)[..., None]
    return done(m, rgb, "gloss", emit=emit, metal=np.full(m.y.shape, 0.25, np.float32), detail=0.5)


# ---------------------------------------------------------------------------
# The Reef Shark's line: reef sharks, then warpaint, scars and bone armour
# ---------------------------------------------------------------------------


def shk_blacktip(m):  # Blacktip reef shark: warm bronze back, white belly and flank band, black tips
    # Bronze, not grey (playtest 2026-10-10: Blacktip, Whitetip and Grey Reef were one
    # grey). A bronze with no blue in it (blue makes it tan, a skin tone) and a hard,
    # anti-aliased edge into the white (a soft one is beige)
    m = smooth(m)
    fins, tip = fin_parts(m)
    u, v, vn = height(m)
    bump = np.exp(-(((u - 0.56) / 0.08) ** 2)) * (1 - fins)
    line = 0.5 + 0.16 * bump
    back = mix(board(m, (0.58, 0.34, 0.05)), (0.40, 0.22, 0.03), smoothstep(0.62, 0.97, m.up))
    rgb = mix(board(m, (0.90, 0.93, 0.98)), back, crisp(m, m.up - line))
    rgb = mix(rgb, back, fins * crisp(m, m.up - 0.42))
    tips = hard(smoothstep(0.66, 0.73, tip))
    rgb = mix(rgb, (0.03, 0.03, 0.04), tips)
    return done(m, rgb, "satin", detail=1.0)


def shk_whitetip(m):  # Whitetip reef shark: dark charcoal-slate, small dark spots, bold white dorsal and tail tips
    # Dark charcoal-slate with bold white tips on the first dorsal and the tail's upper
    # lobe (playtest 2026-10-10: it was a twin of Grey Reef)
    m = smooth(m)
    fins, tip = fin_parts(m)
    u, v, vn = height(m)
    rgb = body_coat(m, (0.12, 0.14, 0.17), (0.44, 0.48, 0.55), soft=0.14)
    pts = scatter(m, 45, 260, weight=(1 - fins) * smoothstep(0.35, 0.6, m.up))
    d1, _, i = nearest(m, pts)
    r = (0.003 + 0.003 * np.random.default_rng(261).random(len(pts)))[i]
    rgb = mix(rgb, (0.05, 0.06, 0.08), smoothstep(r * 1.15, r * 0.8, d1) * 0.85)
    rgb = mix(rgb, (0.13, 0.15, 0.18), fins)
    dorsal = smoothstep(0.7, 0.85, m.up) * smoothstep(0.22, 0.27, u) * smoothstep(0.58, 0.52, u)
    tail = smoothstep(0.82, 0.86, u) * smoothstep(0.0, 0.03, v)
    tips = hard(smoothstep(0.5, 0.58, tip) * np.clip(dorsal + tail, 0, 1))
    rgb = mix(rgb, (0.86, 0.90, 0.97), tips)
    return done(m, rgb, "satin", detail=1.0, hush=np.maximum(own_dark_fins(m), tips))


def shk_grey(m):  # Grey reef shark: steel blue-grey, white belly, a broad black trailing edge on the tail
    # Steel blue-grey (playtest 2026-10-10: it was the same grey as Blacktip and
    # Whitetip), the tail's whole trailing edge broad and black, dusky pectorals
    m = smooth(m)
    fins, tip = fin_parts(m)
    u, v, vn = height(m)
    rgb = body_coat(m, (0.27, 0.37, 0.51), (0.90, 0.93, 0.98), soft=0.05)
    rgb = mix(rgb, (0.19, 0.27, 0.39), smoothstep(0.75, 0.97, m.up) * 0.6)
    rgb = mix(rgb, (0.26, 0.35, 0.48), fins * smoothstep(0.3, 0.6, m.up))
    tail = (fins > 0.4) & (u > 0.8) & m.real
    lo, span = v[tail].min(), max(np.ptp(v[tail]), 1e-4)
    nb = 60
    vb = np.clip(((v - lo) / span * nb).astype(int), 0, nb - 1)
    umax = np.full(nb, np.nan)
    for b in range(nb):
        sel = tail & (vb == b)
        if sel.sum() > 15:
            umax[b] = np.percentile(u[sel], 97)
    good = ~np.isnan(umax)
    umax = np.interp(np.arange(nb), np.flatnonzero(good), umax[good])
    umax = ndimage.gaussian_filter1d(umax, 2.0, mode="nearest")
    at_v = np.interp((v - lo) / span * nb - 0.5, np.arange(nb), umax)
    trailing = hard(smoothstep(0.075, 0.065, at_v - u)) * smoothstep(0.78, 0.82, u) * fins
    rgb = mix(rgb, (0.04, 0.04, 0.05), trailing)
    dusky = smoothstep(0.62, 0.9, tip) * smoothstep(0.75, 0.7, u)
    rgb = mix(rgb, (0.07, 0.08, 0.10), dusky * 0.85)
    return done(m, rgb, "satin", detail=1.0, hush=own_dark_fins(m) * (1 - trailing))


def shk_lemon(m):  # Lemon shark: mustard-olive yellow, paler cool yellow belly
    fins, tip = fin_parts(m)
    rgb = body_coat(m, (0.58, 0.53, 0.11), (0.82, 0.84, 0.40), soft=0.18)
    rgb = mix(rgb, (0.50, 0.46, 0.09), smoothstep(0.75, 0.95, m.up) * 0.6)
    rgb = mix(rgb, (0.62, 0.56, 0.13), fins)
    return done(m, rgb, "satin", detail=1.0, hush=own_dark_fins(m))


def shk_warpaint(m):  # Tribal warpaint: charcoal hide, bold teal and black slashes
    fins, tip = fin_parts(m)
    u, v, vn = height(m)
    hh, at = girth(m)
    rgb = body_coat(m, (0.11, 0.12, 0.14), (0.26, 0.28, 0.31), soft=0.25)
    rough = (fbm(m, 40, 270) - 0.5) * 0.008

    def pt(uu, nn):
        return (uu, nn * at(uu))

    teal_strokes = [
        (pt(0.2, 0.9), pt(0.245, -0.8), 0.012),
        (pt(0.245, 0.9), pt(0.29, -0.8), 0.012),
        (pt(0.29, 0.9), pt(0.335, -0.8), 0.012),
        (pt(0.035, -0.1), pt(0.17, 0.5), 0.01),
        (pt(0.42, 0.9), pt(0.57, -0.4), 0.019),
        (pt(0.70, 0.8), pt(0.765, -0.65), 0.013),
    ]
    black_strokes = [
        (pt(0.455, 0.95), pt(0.61, -0.3), 0.009),
        (pt(0.02, -0.4), pt(0.15, 0.08), 0.007),
        (pt(0.745, 0.8), pt(0.805, -0.6), 0.008),
    ]
    teal = np.zeros_like(u)
    for a, b, w in teal_strokes:
        teal = np.maximum(teal, stroke(u, v, a, b, w, rough=rough))
    black = np.zeros_like(u)
    for a, b, w in black_strokes:
        black = np.maximum(black, stroke(u, v, a, b, w, rough=rough))
    dry = 0.8 + 0.2 * smoothstep(0.3, 0.7, value_noise(np.stack([m.ex * 0.1, u * 40, vn * 3], -1).astype(np.float32), 1.0, 271))
    teal = hard(teal) * (1 - fins * 0.7)
    black = hard(black) * (1 - fins * 0.7) * (1 - teal)
    rgb = mix(rgb, (0.01, 0.01, 0.015), black)
    rgb = mix(rgb, C(0.0, 0.74, 0.72) * dry[..., None], teal)
    rgb = mix(rgb, (0.10, 0.11, 0.13), fins * (1 - teal))
    rgb = mix(rgb, (0.0, 0.62, 0.60), hard(smoothstep(0.8, 0.86, tip)))
    return done(m, rgb, "matte", detail=0.9, hush=own_dark_fins(m))


def shk_scarred(m):  # A veteran: healed rake scars, crescent bites with tooth gouges, torn fins
    fins, tip = fin_parts(m)
    u, v, vn = height(m)
    hh, at = girth(m)
    # Scars that read from the side (playtest 2026-10-16: grey-blue with faint scars):
    # about 1.7x wider and longer, brighter cool cores in darker rims, on a slightly
    # darker back, and more of them on the upper flank and the front half, which a
    # side view shows most (the first ones kept their places)
    rgb = body_coat(m, (0.27, 0.32, 0.40), (0.56, 0.62, 0.71), soft=0.15)
    rgb = mix(rgb, (0.27, 0.32, 0.40), fins * smoothstep(0.3, 0.6, m.up))
    rng = np.random.default_rng(280)
    core = np.zeros_like(u)
    rim = np.zeros_like(u)

    def scar(a, b, w):
        d, t = segment(u, v, a, b)
        ww = w * np.sqrt(np.clip(np.sin(np.pi * t), 0, 1)) + 0.0004
        return smoothstep(ww, ww * 0.6, d), smoothstep(ww * 1.8, ww * 1.3, d)

    for _ in range(6):  # rakes: three parallel claw lines
        uc = rng.uniform(0.15, 0.8)
        h = at(uc)
        vc = rng.uniform(-0.5, 0.7) * h
        ang = rng.uniform(-1.1, -0.4) if rng.random() < 0.6 else rng.uniform(0.4, 1.1)
        half = rng.uniform(0.035, 0.06)
        nx, ny = -np.sin(ang), np.cos(ang)
        for k in (-1, 0, 1):
            off = k * 0.012
            a = (uc - half * np.cos(ang) + off * nx, vc - half * np.sin(ang) + off * ny)
            b = (uc + half * np.cos(ang) + off * nx, vc + half * np.sin(ang) + off * ny)
            c_, r_ = scar(a, b, 0.0045)
            core, rim = np.maximum(core, c_), np.maximum(rim, r_)
    for _ in range(9):  # single scars
        uc = rng.uniform(0.1, 0.86)
        h = at(uc)
        vc = rng.uniform(-0.8, 0.9) * h
        ang = rng.uniform(-1.3, 1.3)
        half = rng.uniform(0.025, 0.055)
        a = (uc - half * np.cos(ang), vc - half * np.sin(ang))
        b = (uc + half * np.cos(ang), vc + half * np.sin(ang))
        c_, r_ = scar(a, b, 0.0048)
        core, rim = np.maximum(core, c_), np.maximum(rim, r_)
    more = np.random.default_rng(282)
    for _ in range(4):  # more rakes, higher up and further forward
        uc = more.uniform(0.18, 0.6)
        h = at(uc)
        vc = more.uniform(0.15, 0.75) * h
        ang = more.uniform(-1.1, -0.4) if more.random() < 0.5 else more.uniform(0.4, 1.1)
        half = more.uniform(0.035, 0.055)
        nx, ny = -np.sin(ang), np.cos(ang)
        for k in (-1, 0, 1):
            off = k * 0.012
            a = (uc - half * np.cos(ang) + off * nx, vc - half * np.sin(ang) + off * ny)
            b = (uc + half * np.cos(ang) + off * nx, vc + half * np.sin(ang) + off * ny)
            c_, r_ = scar(a, b, 0.0045)
            core, rim = np.maximum(core, c_), np.maximum(rim, r_)
    for _ in range(6):  # more single scars there
        uc = more.uniform(0.12, 0.6)
        h = at(uc)
        vc = more.uniform(0.0, 0.85) * h
        ang = more.uniform(-1.3, 1.3)
        half = more.uniform(0.025, 0.05)
        a = (uc - half * np.cos(ang), vc - half * np.sin(ang))
        b = (uc + half * np.cos(ang), vc + half * np.sin(ang))
        c_, r_ = scar(a, b, 0.0048)
        core, rim = np.maximum(core, c_), np.maximum(rim, r_)
    gouge = np.zeros_like(u)
    for _ in range(4):  # crescent bites
        uc = rng.uniform(0.28, 0.72)
        h = at(uc)
        vc = rng.uniform(-0.2, 0.5) * h
        R = rng.uniform(0.75, 1.0) * h
        start = rng.uniform(0, 2 * np.pi)
        du, dv = u - uc, v - vc
        r = np.hypot(du, dv)
        th = (np.arctan2(dv, du) - start) % (2 * np.pi)
        on_arc = smoothstep(2.6, 2.45, th)
        core = np.maximum(core, smoothstep(0.0052, 0.0032, np.abs(r - R)) * on_arc)
        rim = np.maximum(rim, smoothstep(0.0105, 0.008, np.abs(r - R)) * on_arc)
        for k in np.linspace(0.12, 2.4, 10):
            tu = uc + (R - 0.011) * np.cos(start + k)
            tv = vc + (R - 0.011) * np.sin(start + k)
            gouge = np.maximum(gouge, smoothstep(0.0055, 0.0036, np.hypot((u - tu) * 1.4, v - tv)))
    body = 1 - fins * 0.8
    # Cool blue-grey scars: neutral grey lines with dark rims scored 0.55 on the
    # moderation classifier (screen, 2026-10-10)
    # Navy rims and blue cores, not near-black and near-white: bold black-and-white
    # rake stripes scored 0.61 (screen 2026-10-16)
    rgb = mix(rgb, (0.14, 0.20, 0.36), rim * body)
    rgb = mix(rgb, (0.56, 0.72, 0.96), core * body)
    rgb = mix(rgb, (0.12, 0.17, 0.32), gouge * body)
    torn = hard(smoothstep(0.8, 0.88, tip) * smoothstep(0.5, 0.56, fbm(m, 30, 281)))
    rgb = mix(rgb, (0.08, 0.09, 0.10), torn)
    return done(m, rgb, "matte", detail=0.9, hush=own_dark_fins(m))


def shk_boneplate(m):  # Placoderm armour: bone-grey plates over the head and back, dark seams
    fins, tip = fin_parts(m)
    u, v, vn = height(m)
    rgb = body_coat(m, (0.17, 0.20, 0.24), (0.28, 0.31, 0.35), soft=0.25)
    region = np.clip(smoothstep(0.32, 0.26, u) + smoothstep(0.25, 0.4, vn) * smoothstep(0.82, 0.74, u), 0, 1) * (1 - fins)
    pts = scatter(m, 230, 290, weight=0.15 + region)
    d1, d2, i = nearest(m, pts)
    member = at_points(m, pts, region) > 0.5
    plate = member[i].astype(np.float32)
    rng = np.random.default_rng(291)
    tone = (0.86 + 0.14 * rng.random(len(pts)))[i]
    a, b = offsets(m, pts, i)
    cell = (d1 + d2) * 0.5
    rear = smoothstep(-0.3, 1.0, a / np.maximum(cell, 1e-5))
    bone = C(0.66, 0.70, 0.74) * (tone * (1.05 - 0.35 * rear))[..., None]
    bone = mix(bone, (0.42, 0.45, 0.49), speckle(m, 240, 0.8, seed=292) * 0.5)
    seam = smoothstep(0.0032, 0.0016, d2 - d1)
    rgb = mix(rgb, bone, plate)
    rgb = mix(rgb, (0.06, 0.07, 0.08), seam * plate)
    rgb = mix(rgb, (0.22, 0.25, 0.29), fins)
    rgb = mix(rgb, (0.58, 0.62, 0.66), hard(smoothstep(0.85, 0.92, tip)))
    metal = (1 - plate) * (1 - fins) * 0.35
    return done(m, rgb, "satin", metal=metal, rough=0.5 + 0.25 * plate, detail=0.8, hush=own_dark_fins(m))


# ---------------------------------------------------------------------------
# The Angler's line: deep-sea anglers, then murk, driftwood and glowing horrors
# ---------------------------------------------------------------------------


def ang_seadevil(m):  # Black seadevil: velvet black with a faint navy sheen on the ridges and back
    m = smooth(m)
    fins, tip = fin_parts(m)
    rgb = body_coat(m, (0.035, 0.04, 0.075), (0.028, 0.028, 0.04), soft=0.3)
    ridge = smoothstep(0.02, 0.14, m.fine)
    top = smoothstep(0.3, 0.9, m.nrm[..., 2])
    rgb = mix(rgb, (0.10, 0.15, 0.32), ridge * 0.8)
    rgb = mix(rgb, (0.06, 0.09, 0.19), top * 0.5)
    rgb = mix(rgb, (0.09, 0.13, 0.28), smoothstep(0.75, 0.95, tip) * 0.7)
    return done(m, rgb, "matte", detail=0.3)


def ang_humpback(m):  # Humpback angler: dark umber brown, boldly mottled, darker on the back
    # Umber, not another near-black (playtest 2026-10-10: the four Commons read the
    # same). Blue kept near zero, so even the painted strokes' brightest stay out of
    # the skin-tone rules (a brown with blue in it is tan)
    m = smooth(m)
    fins, tip = fin_parts(m)
    rgb = body_coat(m, (0.17, 0.105, 0.03), (0.31, 0.195, 0.045), soft=0.3, line=0.62)
    blot = smoothstep(0.5, 0.6, fbm(m, 6, 300))
    rgb = mix(rgb, (0.085, 0.052, 0.016), blot * 0.85)
    fleck = smoothstep(0.58, 0.68, fbm(m, 11, 305)) * (1 - blot)
    rgb = mix(rgb, (0.36, 0.235, 0.05), fleck * 0.6)
    rgb = mix(rgb, (0.13, 0.085, 0.025), fins)
    return done(m, rgb, "matte", detail=0.6)


def ang_warty(m):  # Warty angler: olive-ochre frogfish skin under darker raised warts
    # Olive-ochre (playtest 2026-10-10: it was near-black like the others). The ochre
    # has no blue in it (blue in it is tan, a skin tone)
    m = smooth(m)
    fins, tip = fin_parts(m)
    mott = smoothstep(0.44, 0.56, fbm(m, 5, 301))
    rgb = mix(board(m, (0.30, 0.29, 0.05)), (0.46, 0.35, 0.03), mott)
    rgb = mix(rgb, (0.21, 0.20, 0.035), smoothstep(0.6, 0.95, m.up) * 0.5)
    pts = scatter(m, 1700, 302, weight=1 - fins * 0.8)
    d1, _, i = nearest(m, pts)
    a, b = offsets(m, pts, i)
    R = (0.0035 + 0.0065 * np.random.default_rng(303).random(len(pts)) ** 2)[i]
    bump = smoothstep(R, R * 0.7, d1)
    lit = np.clip(0.5 + 0.6 * b / R, 0, 1)
    shade = smoothstep(R * 1.45, R * 1.05, d1) * (1 - bump) * smoothstep(0.0, -0.5, b / R)
    rgb = mix(rgb, (0.07, 0.065, 0.015), shade * 0.7)
    rgb = mix(rgb, C(0.19, 0.16, 0.025) * (0.75 + 0.5 * lit)[..., None], bump)
    rgb = mix(rgb, (0.24, 0.22, 0.04), fins * (1 - bump))
    return done(m, rgb, "matte", detail=0.6)


def ang_football(m):  # Footballfish: slate blue-grey with a grid of pale-blue bony spots
    # Slate blue-grey (playtest 2026-10-10: it was near-black like the others); the
    # spots pale blue but on a mid-dark body (a pale skin on the Angler's dark parts
    # trips the classifier)
    m = smooth(m)
    fins, tip = fin_parts(m)
    rgb = body_coat(m, (0.16, 0.21, 0.29), (0.26, 0.32, 0.41), soft=0.25)
    step = 0.03
    gu = m.y / step
    row = np.floor(gu)
    gv = round_angle(m) * 0.24 / step + 0.5 * (row % 2)
    fu, fv = gu - row, gv - np.floor(gv)
    d = np.hypot(fu - 0.5, fv - 0.5) * step
    point = smoothstep(0.0056, 0.0042, d) * (1 - fins)
    ring = smoothstep(0.0084, 0.0066, d) * (1 - point) * (1 - fins)
    rgb = mix(rgb, (0.08, 0.10, 0.15), ring * 0.6)
    rgb = mix(rgb, (0.54, 0.68, 0.88), point)
    rgb = mix(rgb, (0.13, 0.17, 0.24), fins)
    return done(m, rgb, "satin", detail=0.7)


def ang_murk(m):  # Murk: silt-grey with drifting sediment streaks and floating specks
    fins, tip = fin_parts(m)
    u, v, vn = height(m)
    rgb = body_coat(m, (0.28, 0.30, 0.32), (0.40, 0.42, 0.44), soft=0.3)
    warp = (fbm(m, 3, 310) - 0.5) * 1.2
    sp = np.stack([m.ex * 0.1, u * 1.6 + warp * 0.3, vn * 7 + warp * 2.5], -1).astype(np.float32)
    n1 = value_noise(sp, 1.0, 311)
    rgb = mix(rgb, (0.16, 0.17, 0.18), smoothstep(0.6, 0.72, n1) * 0.75)
    rgb = mix(rgb, (0.48, 0.50, 0.52), smoothstep(0.32, 0.22, n1) * 0.35)
    rgb = mix(rgb, (0.58, 0.62, 0.66), speckle(m, 240, 0.87, seed=312) * 0.8)
    rgb = mix(rgb, (0.12, 0.13, 0.14), speckle(m, 190, 0.85, seed=313) * 0.7)
    rgb = mix(rgb, (0.24, 0.26, 0.28), fins * 0.6)
    return done(m, rgb, "matte", detail=0.9)


def ang_driftwood(m):  # Driftwood: bleached grey grain and knots, barnacle clusters on the back
    fins, tip = fin_parts(m)
    u, v, vn = height(m)
    gp = np.stack([m.ex * 0.12, u * 0.55, vn * 0.6], -1).astype(np.float32)
    knots = scatter(m, 7, 320, weight=1 - fins)
    kd, _, _ = nearest(m, knots)
    f = fbm_at(gp, 3, 321) + 0.08 * np.exp(-((kd / 0.02) ** 2))
    g = np.abs(((f * 26) % 1.0) - 0.5)
    rgb = board(m, (0.50, 0.52, 0.54))
    rgb = mix(rgb, (0.30, 0.32, 0.34), smoothstep(0.14, 0.04, g))
    rgb = mix(rgb, (0.60, 0.62, 0.64), smoothstep(0.42, 0.5, g) * 0.5)
    rgb = mix(rgb, (0.24, 0.25, 0.27), smoothstep(0.012, 0.004, kd))
    centres = scatter(m, 5, 322, weight=smoothstep(0.7, 0.85, m.up) * (1 - fins))
    cd, _, _ = nearest(m, centres)
    pts = scatter(m, 110, 323, weight=np.exp(-((cd / 0.03) ** 2)) * (1 - fins))
    d1, _, i = nearest(m, pts)
    R = (0.004 + 0.003 * np.random.default_rng(324).random(len(pts)))[i]
    shell = smoothstep(R * 1.05, R * 0.9, d1)
    ring = smoothstep(R * 0.3, R * 0.15, np.abs(d1 - R * 0.75))
    hole = smoothstep(R * 0.4, R * 0.3, d1)
    rgb = mix(rgb, (0.58, 0.64, 0.74), shell)
    rgb = mix(rgb, (0.76, 0.82, 0.92), ring * shell)
    rgb = mix(rgb, (0.12, 0.14, 0.18), hole)
    rgb = mix(rgb, (0.40, 0.42, 0.44), fins * 0.6)
    return done(m, rgb, "matte", detail=0.8)


def ang_bioglow(m):  # Bioglow: near-black, tiny faint blue glowing freckles, densest on the belly
    rgb = body_coat(m, (0.02, 0.025, 0.05), (0.03, 0.04, 0.09), soft=0.3)
    pts = scatter(m, 1000, 330, weight=0.4 + 2.5 * smoothstep(0.6, 0.15, m.up))
    d1, _, i = nearest(m, pts)
    r = (0.0026 * (0.7 + 0.6 * np.random.default_rng(331).random(len(pts))))[i]
    dot = smoothstep(r * 1.2, r * 0.7, d1)
    halo = glow_halo(dot, 3)
    col = C(0.28, 0.55, 1.0)
    rgb = mix(rgb, (0.05, 0.12, 0.30), halo * 0.45)
    rgb = mix(rgb, col, dot * 0.9)
    emit = col * (dot * 0.8)[..., None] + C(0.05, 0.12, 0.35) * (halo * 0.5)[..., None]
    return done(m, rgb, "satin", emit=emit, detail=0.6)


def ang_glassveins(m):  # Glassveins: deep indigo lit from inside by branching cyan veins
    rgb = body_coat(m, (0.06, 0.04, 0.24), (0.10, 0.07, 0.32), soft=0.3)
    P = body_coords(m)
    r1 = 1 - np.abs(fbm_at(P, 4, 340) * 2 - 1)
    lo, hi = np.percentile(r1[m.real], [92, 96.5])
    major = smoothstep(lo, hi, r1)
    r2 = 1 - np.abs(fbm_at(P, 9, 341) * 2 - 1)
    lo2, hi2 = np.percentile(r2[m.real], [95, 98])
    minor = smoothstep(lo2, hi2, r2) * 0.65
    veins = np.maximum(major, minor)
    halo = glow_halo(veins, 6)
    rgb = mix(rgb, (0.10, 0.30, 0.75), halo * 0.55)
    rgb = mix(rgb, (0.25, 0.88, 1.0), veins)
    emit = C(0.2, 0.85, 1.0) * veins[..., None] + C(0.05, 0.25, 0.7) * (halo * 0.5)[..., None]
    return done(m, rgb, "gloss", emit=emit, detail=0.6)


def ang_abyss_eye(m):  # Abyss eye: a black body covered in glowing amber eyes with slit pupils
    fins, tip = fin_parts(m)
    rgb = body_coat(m, (0.025, 0.022, 0.03), (0.05, 0.03, 0.07), soft=0.3)
    free = (m.keep < 0.05).astype(np.float32) * (1 - fins)
    free = ndimage.minimum_filter(free, 9)
    pts = scatter(m, 48, 350, weight=free)
    d1, _, i = nearest(m, pts)
    a, b = offsets(m, pts, i)
    R = (0.010 + 0.026 * np.random.default_rng(351).random(len(pts)) ** 2.2)[i]
    t = d1 / R
    inside = smoothstep(1.02, 0.97, t)
    socket = smoothstep(1.28, 1.06, t) * (1 - inside)
    ang = np.arctan2(b, a)
    iris = mix(board(m, (1.0, 0.72, 0.0)), (0.86, 0.32, 0.0), smoothstep(0.25, 0.95, t))
    iris = iris * (0.86 + 0.14 * np.cos(ang * 22))[..., None]
    iris = mix(iris, (0.32, 0.08, 0.0), smoothstep(0.86, 0.96, t))
    pupil = smoothstep(0.03, 0.0, np.abs(a) / R - 0.17 * np.sqrt(np.clip(1 - (b / (0.86 * R)) ** 2, 0, 1)))
    glint = smoothstep(0.13, 0.09, np.hypot(a + 0.35 * R, b - 0.35 * R) / R)
    rgb = mix(rgb, (0.09, 0.03, 0.11), socket)
    rgb = mix(rgb, iris, inside)
    rgb = mix(rgb, (0.01, 0.0, 0.01), pupil * inside)
    rgb = mix(rgb, (0.78, 0.84, 1.0), glint * inside)
    lit = inside * (1 - pupil) * (1 - glint)
    emit = iris * (lit * 0.9)[..., None] + C(0.5, 0.2, 0.0) * (glow_halo(inside, 3) * 0.2 * (1 - inside))[..., None]
    return done(m, rgb, "gloss", emit=emit, detail=0.5)


def ang_lantern_king(m):  # Lantern King: gold lantern filigree on navy, a crown of glowing gold spines
    fins, tip = fin_parts(m)
    u, v, vn = height(m)
    rgb = body_coat(m, (0.02, 0.04, 0.16), (0.04, 0.07, 0.22), soft=0.3)
    P = 0.07
    a = 2 * np.pi * u / P
    b = 2 * np.pi * v / P
    trellis = smoothstep(0.16, 0.07, np.abs(np.cos(a) + np.cos(b)))
    cu, cv = (u / P) % 1.0 - 0.5, (v / P) % 1.0 - 0.5
    node = np.hypot(cu, cv) * P
    ring = smoothstep(0.0016, 0.0008, np.abs(node - 0.012))
    dot = smoothstep(0.0032, 0.0022, node)
    fil = hard(np.clip(trellis + ring + dot, 0, 1)) * (1 - fins) * smoothstep(0.1, 0.16, u)
    gold = (1.0, 0.70, 0.0)
    rgb = mix(rgb, gold, fil)
    crown = hard(fins * smoothstep(0.45, 0.65, vn) * smoothstep(0.08, 0.2, tip))
    trim = hard(smoothstep(0.78, 0.85, tip)) * (1 - crown)
    rgb = mix(rgb, (0.03, 0.05, 0.18), fins * (1 - crown) * (1 - trim))
    rgb = mix(rgb, gold, trim)
    rgb = mix(rgb, (1.0, 0.78, 0.04), crown)
    glow = glow_halo(crown, 4)
    emit = C(1.0, 0.6, 0.0) * crown[..., None] + C(0.8, 0.4, 0.0) * (glow * 0.4 * (1 - crown))[..., None]
    emit = emit + C(0.5, 0.32, 0.0) * (fil * 0.25)[..., None]
    metal = np.clip(fil + trim + crown * 0.6, 0, 1)
    return done(m, rgb, "gloss", emit=emit, metal=metal, rough=0.28 - 0.12 * metal, detail=0.5)


def ang_starfall(m):  # Starfall: constellations joined by glowing lines, falling stars
    u, v, vn = height(m)
    hh, at = girth(m)
    rgb = body_coat(m, (0.012, 0.012, 0.035), (0.02, 0.02, 0.06), soft=0.3)
    rng = np.random.default_rng(360)
    n = 30
    su = rng.uniform(0.14, 0.9, n)
    sv = np.array([rng.uniform(-0.8, 0.85) * at(x) for x in su])
    mag = rng.uniform(0.55, 1.0, n)
    from scipy.sparse.csgraph import minimum_spanning_tree

    gap = np.hypot(su[:, None] - su[None], sv[:, None] - sv[None])
    tree = minimum_spanning_tree(gap).tocoo()
    lines = np.zeros_like(u)
    for i, j, w in zip(tree.row, tree.col, tree.data):
        if w < 0.15:
            d, _ = segment(u, v, (su[i], sv[i]), (su[j], sv[j]))
            lines = np.maximum(lines, smoothstep(0.0022, 0.0012, d))
    stars = np.zeros_like(u)
    for k in range(n):
        du, dv = u - su[k], v - sv[k]
        d = np.hypot(du, dv)
        core = smoothstep(0.0065 * mag[k], 0.0028 * mag[k], d)
        arms = smoothstep(0.0012, 0.0005, np.minimum(np.abs(du), np.abs(dv))) * smoothstep(0.02 * mag[k], 0.0, d)
        stars = np.maximum(stars, np.maximum(core, arms * 0.85))
    falling = np.zeros_like(u)
    for k in range(4):
        u0 = rng.uniform(0.25, 0.8)
        h = at(u0)
        a = (u0, 0.9 * h)
        b = (u0 + rng.uniform(0.05, 0.09), -0.5 * h)
        d, t = segment(u, v, a, b)
        w = 0.001 + 0.004 * t
        falling = np.maximum(falling, smoothstep(w, w * 0.4, d) * t**1.3)
    dust = speckle(m, 260, 0.9, seed=361)
    halo = glow_halo(np.clip(lines + stars + falling, 0, 1), 5)
    line_col, star_col, fall_col = C(0.52, 0.46, 1.0), C(0.74, 0.80, 1.0), C(0.55, 0.62, 1.0)
    rgb = mix(rgb, (0.35, 0.38, 0.70), dust * 0.5)
    rgb = mix(rgb, (0.20, 0.13, 0.55), halo * 0.55)
    rgb = mix(rgb, line_col, lines)
    rgb = mix(rgb, fall_col, falling)
    rgb = mix(rgb, star_col, stars)
    emit = (
        line_col * (lines * 0.8)[..., None]
        + star_col * stars[..., None]
        + fall_col * falling[..., None]
        + C(0.2, 0.14, 0.6) * (halo * 0.5)[..., None]
        + C(0.3, 0.32, 0.6) * (dust * 0.3)[..., None]
    )
    return done(m, rgb, "gloss", emit=emit, detail=0.4)


# ---------------------------------------------------------------------------
# The universal skins: the catch track and the weekly skins. Earned, so never elite
# (owner, 2026-10-10: Uncommon to Epic; the top looks come from rolls, bosses and
# treasure): restrained finishes, a modest glow at most, nothing full-body flashy
# ---------------------------------------------------------------------------


def catch_golden(m):  # Golden (v13): polished gold, its own pattern engraved, reflections and a gloss
    """Owner, 2026-10-18: "The gold skin needs more of a gold sheen." v10's even
    orange-gold (satin, a faint even glow) read gold through the water but flat, a
    painted yellow. Polished gold reads as gold by its reflections: a bright streak
    along the upper flank where it faces the light, a deep amber band under it where
    it faces the dark water, a warm bounce lower down, crisp edges between them, all
    brushed along the body; and a gloss finish so the game's lights (the sun and the
    shine that runs down it, SkinFx `sheen`) lay real highlights on it. Every tone is
    a saturated gold or amber with no blue in it (a pale gold reads cream to the
    screen, and orange or gold blended into white makes peach), the hottest
    highlight a lemon gold. Still about 33-37 degrees through the middle tones, so
    the shallows' blue-green haze leaves it gold, not olive (v10), with a faint glow
    under it, stronger in the streak, so the streak burns through the water."""
    L = own_lum(m)
    lines = own_lines(m)
    sm = smooth(m)
    gold = mix(board(m, (0.96, 0.52, 0.0)), (1.0, 0.63, 0.02), smoothstep(0.1, 0.85, L))
    engraved = hard(smoothstep(0.4, 0.62, lines))
    # A fine brushed grain nose to tail (the smooth frame; it also breaks up the big
    # smooth fields the classifier read as skin once JPEG-packed, 2026-10-11). v13's
    # bands leave bigger even fields than v10's, so the grain is stronger and has a
    # finer third octave: at v10's strength the Reef Shark's packed image scored 0.23
    # (one tile, round its eye), with this 0.03
    gp = np.stack([sm.ex * 0.02, m.y * 3.0, sm.ez * 40], -1).astype(np.float32)
    grain = value_noise(gp, 1.0, 410) * 0.45 + value_noise(gp, 2.3, 411) * 0.35 + value_noise(gp, 5.1, 412) * 0.2
    # The reflections, from which way the skin faces (both flanks alike): up the
    # flank the streak, round the middle the dark horizon, under it the bounce. Each
    # band's edge wanders a little with the grain, as on brushed metal
    nz = m.nrm[..., 2] + 0.06 * (grain - 0.5)
    streak = smoothstep(0.36, 0.5, nz) * smoothstep(0.97, 0.8, nz)
    core = smoothstep(0.5, 0.6, nz) * smoothstep(0.86, 0.74, nz)
    horizon = smoothstep(0.3, 0.16, nz) * smoothstep(-0.32, -0.12, nz)
    bounce = smoothstep(-0.42, -0.62, nz)
    # The highlights stay as orange as the gold's light end (green no more than 0.64
    # of red): the haze adds the same teal to everything, so a highlight more yellow
    # than the gold went lime through it (a first try at (1, 0.8, 0.16) did), and a
    # shadow darker than amber went olive. The streak burns brighter by its glow
    # (below), which keeps its hue
    gold = mix(gold, (0.84, 0.40, 0.0), horizon * 0.45)
    gold = mix(gold, (1.0, 0.60, 0.03), bounce * 0.4)
    gold = mix(gold, (1.0, 0.63, 0.04), streak * 0.9)
    gold = mix(gold, (1.0, 0.66, 0.08), core * 0.8)
    gold = mix(gold, (0.6, 0.24, 0.0), engraved * 0.7)
    gold = gold * (0.84 + 0.32 * grain)[..., None]
    gold = np.clip(gold, 0, 1)
    # A faint, even self-glow over it, stronger in the streak, less in the engraving
    # (the importer turns this into a mask on the colour map)
    emit = gold * (0.5 * (1 - 0.4 * engraved) * (1 + 0.8 * streak + 0.4 * core))[..., None]
    # An even metal map, and little of it: metal reflects the water's blue through
    # the gold's own colour, which comes out green (v10). The polish is a semi-gloss,
    # glossier in the streak: a full gloss mirrored the teal water at the edges and
    # went lime there too
    rough = np.full(m.y.shape, 0.48, np.float32) - 0.1 * streak
    return done(m, gold, "satin", emit=emit, metal=np.full(m.y.shape, 0.15, np.float32), rough=rough, detail=0.4)


def mirror_scales(m: Fish, size, radius=0.75):
    """Overlapping scales laid round the body in its own girth, each its own flat
    mirror (v14, Silver). Rows run nose to tail, a row's scales offset half a scale
    from the row ahead, and each scale's front lies under the scale ahead of it (a
    fish's own imbrication), so every scale shows its free back edge. Returns, per
    texel: its scale's own random number (0..1, the same over the whole scale: how
    that mirror is tilted), how far out from its scale's middle it lies (1 at the
    free edge), and the crease behind the free edge of the scale ahead (1 right at
    it .. 0 a sixth of a scale back), where that scale shades this one."""
    hh, _ = girth(m)
    U = (m.y / size).astype(np.float64)
    A = (round_angle(m) * np.maximum(hh, 0.02) / size).astype(np.float64)
    r0 = np.floor(U)

    def nearest_in(row):
        off = 0.5 * (row % 2)
        col = np.round(A - off)
        return np.hypot(U - row, A - (col + off)), col

    d0, c0 = nearest_in(r0)
    d1, c1 = nearest_in(r0 + 1)
    mine = d0 < radius
    row = np.where(mine, r0, r0 + 1)
    col = np.where(mine, c0, c1)
    out = np.where(mine, d0, d1) / radius
    h = np.sin(row * 127.1 + col * 311.7) * 43758.5453
    h = h - np.floor(h)
    crease = np.where(mine, 0.0, smoothstep(radius + 0.16, radius, d0))
    return h.astype(np.float32), out.astype(np.float32), crease.astype(np.float32)


# Silver's tones (v14), with a fish's own where it needs them. Each entry is a colour
# and how far it's mixed in; `glow` is the body's glow (0 for none)
SILVER = {
    "lo": (0.62, 0.66, 0.72),
    "hi": (0.70, 0.73, 0.78),
    "horizon": ((0.17, 0.24, 0.37), 0.8),
    "bounce": ((0.66, 0.70, 0.77), 0.45),
    "streak": ((0.82, 0.85, 0.90), 0.9),
    "core": ((0.86, 0.88, 0.93), 0.8),
    "flash": ((0.85, 0.88, 0.94), 0.7),
    "behind": ((0.20, 0.28, 0.42), 0.55),
    "crease": ((0.24, 0.32, 0.46), 0.5),
    "engraved": ((0.24, 0.31, 0.45), 0.6),
    "glow": 0.45,
}
# v14.1 (PC 2026-10-19, SV1): on the Anglerfish, a dark fish whose lure lamp is
# always lit, v14's silver read near-white and glowing, "almost glowing pale
# blue-white". Its silver is a step darker (mid-toned like the other five in the
# water), its bands and creases deeper, and its body doesn't glow: only the lure
# does, as in every Angler skin (done() adds it)
SILVER_FISH = {
    "Angler": {
        "lo": (0.55, 0.60, 0.67),
        "hi": (0.63, 0.67, 0.74),
        "horizon": ((0.13, 0.19, 0.31), 0.85),
        "bounce": ((0.59, 0.64, 0.71), 0.45),
        "streak": ((0.77, 0.81, 0.87), 0.9),
        "core": ((0.81, 0.84, 0.90), 0.8),
        "flash": ((0.80, 0.84, 0.90), 0.7),
        "behind": ((0.15, 0.22, 0.35), 0.62),
        "crease": ((0.18, 0.25, 0.38), 0.58),
        "engraved": ((0.18, 0.24, 0.37), 0.68),
        "glow": 0.0,
    },
}


def catch_silver(m):  # Silver (v14): polished silver, mirror scales catching the light, steel-blue creases
    """The commonest catch track's skin (Silver prey, 2026-10-18): Golden's polish in
    silver. Not the plain silvery prey (a dark back over a silver belly) and not
    Chrome's dark gunmetal: the whole fish is bright polished silver from back to
    belly, read by its reflections as Golden is (a bright streak along the upper
    flank, a deep steel-blue horizon band under it, a cool bounce lower down), over
    big mirror scales, each tilted its own way, so the bands break into steps scale
    by scale and a few scales flash bright, like a tarpon's. Cool steel-blue in the
    creases (behind each scale's free edge, the fish's own painted creases and its
    pattern engraved), a fine brushed grain nose to tail, a semi-gloss and a faint
    glow so it stays silver through the water's haze. Mid-toned and cool throughout:
    the brightest flash is a blue-white well under white (a near-white skin on a fish
    with dark parts trips the classifier), blue above green above red everywhere (no
    cream or beige), and little metal (metal shows the dark water, not its colour:
    Chrome went dark that way). The moving shine is the game's: Config/Shades FX
    `sheen` in silver. The tones are SILVER's, or the fish's own in SILVER_FISH (the
    Angler's: darker, with no body glow, v14.1)."""
    base = m.base if isinstance(m, Smooth) else m
    tone = {**SILVER, **SILVER_FISH.get(base.name, {})}
    sm = smooth(base)
    L = own_lum(base)
    lines = own_lines(base)
    fins, _ = fin_parts(base)
    u, _, _ = height(sm)
    engraved = hard(smoothstep(0.4, 0.62, lines))
    # Brushed nose to tail, as Golden (it also breaks up the big even fields the
    # classifier reads as skin)
    gp = np.stack([sm.ex * 0.02, base.y * 3.0, sm.ez * 40], -1).astype(np.float32)
    grain = value_noise(gp, 1.0, 420) * 0.45 + value_noise(gp, 2.3, 421) * 0.35 + value_noise(gp, 5.1, 422) * 0.2
    # Scales on the body only (not the face or the fins)
    on = smoothstep(0.17, 0.25, u) * (1 - hard(fins))
    h, out, behind = mirror_scales(sm, 0.055)
    tilt = (h - 0.5) * on
    # The reflections from which way the skin faces (both flanks alike), each scale's
    # own tilt shifting them a little, so a band's edge steps from scale to scale
    nz = base.nrm[..., 2] + 0.06 * (grain - 0.5) + 0.12 * tilt
    streak = smoothstep(0.36, 0.5, nz) * smoothstep(0.97, 0.8, nz)
    core = smoothstep(0.5, 0.6, nz) * smoothstep(0.86, 0.74, nz)
    horizon = smoothstep(0.3, 0.16, nz) * smoothstep(-0.32, -0.12, nz)
    bounce = smoothstep(-0.42, -0.62, nz)
    rgb = mix(board(base, tone["lo"]), tone["hi"], smoothstep(0.1, 0.85, L))
    rgb = mix(rgb, tone["horizon"][0], horizon * tone["horizon"][1])
    rgb = mix(rgb, tone["bounce"][0], bounce * tone["bounce"][1])
    rgb = mix(rgb, tone["streak"][0], streak * tone["streak"][1])
    rgb = mix(rgb, tone["core"][0], core * tone["core"][1])
    # Each scale a flat mirror: lighter toward its free edge (a sequin's tilt), a
    # few tilted to the light flashing bright
    rgb = rgb * (0.93 + 0.14 * out * on)[..., None]
    flash = smoothstep(0.82, 0.9, h) * on * smoothstep(-0.3, 0.2, nz)
    rgb = mix(rgb, tone["flash"][0], flash * tone["flash"][1])
    # The crease behind each free edge steel-blue
    rgb = mix(rgb, tone["behind"][0], behind * on * tone["behind"][1])
    crease = smoothstep(-0.02, -0.14, base.fine)
    rgb = mix(rgb, tone["crease"][0], crease * tone["crease"][1])
    rgb = mix(rgb, tone["engraved"][0], engraved * tone["engraved"][1])
    rgb = np.clip(rgb * (0.9 + 0.2 * grain)[..., None], 0, 1)
    # A faint even glow, stronger in the streak and on the flashing scales (none on
    # the Angler: its lure's glow is its only one, done() adds it)
    glow = tone["glow"]
    emit = rgb * (glow * (1 - 0.5 * engraved) * (1 + 0.8 * streak + 0.4 * core + 0.6 * flash))[..., None] if glow > 0 else None
    rough = 0.42 - 0.1 * streak - 0.08 * flash + 0.12 * behind * on
    metal = np.full(base.y.shape, 0.25, np.float32)
    return done(base, rgb, "satin", emit=emit, metal=metal, rough=rough, detail=0.4)


def catch_glowing(m):  # Glowing: deep navy, the fish's own lines softly glowing cyan-green
    lines = own_lines(m)
    L = own_lum(m)
    rgb = body_coat(m, (0.02, 0.05, 0.15), (0.03, 0.08, 0.21), soft=0.3)
    rgb = mix(rgb, (0.03, 0.12, 0.20), smoothstep(0.55, 0.9, L) * 0.6)
    glow_line = smoothstep(0.3, 0.7, lines)
    halo = glow_halo(glow_line, 3)
    wide = glow_halo(glow_line, 7)
    col = C(0.10, 0.95, 0.70)
    rgb = mix(rgb, (0.02, 0.22, 0.26), halo * 0.4)
    rgb = mix(rgb, col, glow_line * 0.9)
    # The glow map in blue-violet with a wide soft glow: thin cyan-green lines on
    # black scored up to 0.25 on the moderation classifier, these 0.001-0.003
    # (screen, 2026-10-10). In game the glow takes the color map's cyan-green; the
    # glow map only says where and how much
    emit = C(0.30, 0.40, 0.95) * (glow_line * 0.5)[..., None] + C(0.18, 0.16, 0.55) * (wide * 0.5)[..., None]
    return done(m, rgb, "satin", emit=emit, detail=0.5)


def texel_size(m: Fish):
    """A texel's typical width on the body, in body lengths."""

    def make():
        near = cache(m, "texel_near", lambda: _texel_near(m))
        steps = [np.linalg.norm(np.diff(m.p, axis=a), axis=-1)[ok] for a, ok in enumerate(near)]
        return float(np.median(np.concatenate(steps)))

    return cache(m, "texel_size", make)


def crystal_matrix(m: Fish, size, seed):
    """Druzy: a crust of tiny crystal facets (cells about `size` across), each catching
    the light at its own angle, darker seams between. Returns (rgb, cell tone 0..1)."""
    texel = texel_size(m)
    area = float(m.real.sum()) * texel * texel
    count = int(np.clip(area / (size * size), 300, 60000))
    d1, d2, i, n = worley(m, count, seed)
    rng = np.random.default_rng(seed + 1)
    dirs = rng.normal(size=(n, 3)).astype(np.float32)
    dirs /= np.linalg.norm(dirs, axis=1, keepdims=True)
    facet = np.clip(0.5 + 0.5 * (dirs[i] * m.nrm).sum(-1), 0, 1)
    tone = (rng.random(n).astype(np.float32))[i]
    rgb = mix(board(m, (0.12, 0.30, 0.45)), (0.28, 0.54, 0.67), smoothstep(0.1, 0.95, facet * 0.7 + tone * 0.3))
    seam = smoothstep(texel * 1.4, texel * 0.4, d2 - d1)
    rgb = mix(rgb, (0.06, 0.16, 0.28), seam * 0.45)
    return rgb, facet


def catch_crystal(m):  # Crystal: clusters of long faceted quartz shards grown along the body
    """Owner, 2026-10-16: "crystal should have a crystal texture" (v8's was a flat
    mosaic). Clusters of elongated, double-terminated prisms fan back along the body
    over a druzy crust, drawn one over another so they overlap like a real growth:
    each shard a lit face and a shadowed face meeting at a bright ridge, faceted
    tips, a dark seam round it and a soft cast shadow below, a milky veil and bright
    refraction planes inside, now and then a spark of fire at a tip. Icy blue to aqua,
    mid-toned (large near-white areas trip the classifier on dark-part fish), cool
    whites only. Clearly not Diamond: long prisms, not bevelled cut facets. All of the
    depth is painted in the colour map (no normal maps, ever: 2026-10-13)."""
    rng = np.random.default_rng(420)
    texel = texel_size(m)
    hh, _ = girth(m)
    fins, reach = fin_parts(m)
    shape = m.y.shape
    P = m.p.reshape(-1, 3)
    N = m.nrm.reshape(-1, 3)
    body = (m.real & (fins < 0.4) & (m.eyes < 0.5)).reshape(-1)
    idx_body = np.flatnonzero(body)
    tree = cKDTree(P[idx_body])
    # Shard width follows the body's girth (an eel gets slim ones), within limits
    w_here = np.clip(0.2 * hh, 0.007, 0.06).reshape(-1)
    w_mean = float(np.mean(w_here[idx_body]))
    area = float(body.sum()) * texel * texel
    shard_area = 8.0 * w_mean * w_mean
    count = int(np.clip(2.5 * area / shard_area, 100, 2400))
    matrix, _ = crystal_matrix(m, w_mean * 0.32, 421)
    rgb = matrix.reshape(-1, 3).copy()
    covered = np.zeros(len(P), np.float32)
    light2 = np.array([-0.35, 1.0], np.float32)
    light2 /= np.linalg.norm(light2)
    xc = m.xc.reshape(-1)
    centres = scatter(m, max(count // 6, 12), 422, weight=(1 - fins) * m.real)
    # Each cluster's fan points back along the body, tipped up or down a little
    order = rng.permutation(len(centres))
    made = 0
    for ci in order:
        c0 = centres[ci]
        _, j = tree.query(c0)
        j = idx_body[j]
        n0 = N[j]
        # Along the body, or (on a face looking straight ahead or back) up it
        ref = np.array([0, 1, 0], np.float32) if abs(n0[1]) < 0.8 else np.array([0, 0, 1], np.float32)
        fwd = ref - n0 * float(n0 @ ref)
        fwd /= max(np.linalg.norm(fwd), 1e-6)
        sgn = 1.0 if P[j, 0] >= xc[j] else -1.0
        up = np.cross(n0, fwd) * sgn
        w0 = w_here[j]
        # Mostly back along the body; some forward (most of them on the snout, where a
        # fan pointing back would leave the very front bare)
        y0 = float(m.y.reshape(-1)[j])
        forward = rng.random() < 0.2 + 0.6 * float(smoothstep(0.16, 0.04, y0))
        theta0 = rng.normal(0, 0.45) + (np.pi if forward else 0.0)
        k = int(rng.integers(5, 10))
        for _ in range(k):
            theta = theta0 + rng.uniform(-0.95, 0.95)
            W = w0 * rng.uniform(0.55, 1.15)
            Lb = W * rng.uniform(1.0, 2.6)
            T = W * rng.uniform(0.8, 1.3)
            e_s = np.cos(theta) * fwd + np.sin(theta) * up
            e_t = -np.sin(theta) * fwd + np.cos(theta) * up
            base = c0 + (rng.uniform(-0.6, 0.6) * W) * up + (rng.uniform(-0.6, 0.6) * W) * fwd
            ctr = base + e_s * (Lb + T) * rng.uniform(0.35, 0.85)
            reach_r = Lb + T + 0.6 * W
            hits = tree.query_ball_point(ctr, reach_r)
            if len(hits) < 8:
                continue
            ids = idx_body[np.asarray(hits)]
            d = P[ids] - ctr
            same = (N[ids] @ n0) > 0.25
            ids, d = ids[same], d[same]
            if len(ids) < 8:
                continue
            sl, tl = d @ e_s, d @ e_t
            a = np.abs(sl)
            f = np.abs(tl) / W + np.maximum(0, (a - Lb) / T)
            aa = texel * 1.3 * (1 / W + 1 / T) * 0.6
            cov = np.clip((1 - f) / (2 * aa) + 0.5, 0, 1)
            # A soft shadow cast below and behind it (the light is above and ahead)
            delta = up * (0.3 * W) - fwd * (0.15 * W)
            ss, ts = sl + delta @ e_s, tl + delta @ e_t
            fs = np.abs(ts) / W + np.maximum(0, (np.abs(ss) - Lb) / T)
            shadow = np.clip((1 - fs) / 0.25, 0, 1) * (1 - cov)
            # The faces: body (two long faces) and tips (four facets), lit by their tilt
            tip = a > Lb
            ts_sign = np.where(tl >= 0, 1.0, -1.0)
            ss_sign = np.where(sl >= 0, 1.0, -1.0)
            et2 = np.array([-np.sin(theta), np.cos(theta)], np.float32)
            es2 = np.array([np.cos(theta), np.sin(theta)], np.float32)
            tilt_body = ts_sign[:, None] * et2
            tilt_tip = ss_sign[:, None] * es2 + 0.7 * ts_sign[:, None] * et2
            tilt_tip /= np.linalg.norm(tilt_tip, axis=1, keepdims=True)
            tilt = np.where(tip[:, None], tilt_tip, tilt_body)
            lit = np.clip(0.5 + 0.5 * (tilt @ light2) + rng.uniform(-0.08, 0.08), 0, 1)
            hue = rng.uniform(0.49, 0.58)
            hi = hsv_to_rgb(np.array([[hue - 0.01, 0.36, 0.92]], np.float32))[0]
            lo = hsv_to_rgb(np.array([[hue + 0.02, 0.70, 0.46]], np.float32))[0]
            col = lo + (hi - lo) * (lit ** 1.3)[:, None]
            # Across a face: brighter toward the ridge on the lit face, a soft reflection band
            across = np.abs(tl) / W
            col = col * (1 + 0.18 * (lit - 0.5)[:, None] * (1 - across)[:, None])
            band = np.exp(-(((across - 0.42) / 0.12) ** 2)) * (lit > 0.6) * (~tip)
            col = mix(col, (0.70, 0.90, 0.98), band * 0.35)
            # The milky veil inside, thicker toward the base
            veil = smoothstep(0.42, 0.72, fbm_at(P[ids] / W * 0.08, 9, 423 + made % 7, 3))
            veil = veil * np.clip(1 - f, 0, 1) * (0.5 + 0.5 * np.clip(-sl / (Lb + T) + 0.5, 0, 1))
            col = mix(col, (0.60, 0.78, 0.88), veil * 0.4)
            # Refraction planes: a line along it and one across at a slant, bright with a dark twin
            rw = texel * 1.1
            t1 = rng.uniform(-0.65, 0.65) * W
            along = np.exp(-(((tl - t1) / rw) ** 2)) * smoothstep(Lb * 1.1, Lb * 0.4, np.abs(sl - rng.uniform(-0.5, 0.5) * Lb))
            phi = rng.uniform(0.5, 1.2) * rng.choice([-1, 1])
            off = rng.uniform(-0.6, 0.6) * Lb
            dist = (sl - off) * np.sin(phi) - tl * np.cos(phi)
            slant = np.exp(-((dist / rw) ** 2)) * (f < 0.85)
            dark = np.exp(-(((dist - 2.2 * rw) / rw) ** 2)) * (f < 0.85)
            col = mix(col, (0.06, 0.20, 0.38), dark * 0.45)
            col = mix(col, (0.80, 0.95, 1.0), np.clip(along * 0.55 + slant * 0.7, 0, 1))
            # The ridge where the two faces meet, to the tips, and the line where the tips start
            ridge = np.exp(-((tl / (texel * 1.2)) ** 2)) * (a < Lb + T)
            shoulder = np.exp(-(((a - Lb) / (texel * 1.1)) ** 2)) * (np.abs(tl) < W)
            col = mix(col, (0.84, 0.96, 1.0), ridge * 0.85)
            col = mix(col, (0.72, 0.90, 1.0), shoulder * 0.45 * (lit > 0.5) + 0.0)
            col = mix(col, lo * 0.55, shoulder * 0.4 * (lit <= 0.5))
            # A dark seam round it, so overlapping shards read apart
            seam = smoothstep(1 - 2.4 * texel / W, 1.0, f)
            col = mix(col, lo * 0.45, seam * 0.7)
            # Fire: a spark of colour at a tip, now and then
            if rng.random() < 0.4:
                tipx = (Lb + T) * rng.choice([-1, 1])
                r = np.hypot(sl - tipx * 0.9, tl)
                spark = np.exp(-((r / (texel * 2.2)) ** 2)) + 0.35 * np.exp(-((r / (texel * 6)) ** 2))
                fire_hue = rng.uniform(0.13, 0.75)
                fire = hsv_to_rgb(np.array([[fire_hue, 0.85, 1.0]], np.float32))[0]
                col = mix(col, fire, np.clip(spark, 0, 1) * 0.85)
            cur = rgb[ids]
            # Translucent: a little of what lies under it shows through (not the ridge)
            col = mix(col, cur, 0.16 * (1 - ridge) * (1 - seam))
            cur = cur * (1 - 0.45 * shadow)[:, None]
            rgb[ids] = cur * (1 - cov)[:, None] + col * cov[:, None]
            covered[ids] = np.maximum(covered[ids], cov)
            made += 1
    rgb = rgb.reshape(shape + (3,))
    # The fins: frosted crystal blades, deeper at the root, clear and bright at the edge
    fin_rgb, _ = crystal_matrix(m, w_mean * 0.22, 424)
    fin_rgb = mix(fin_rgb, (0.30, 0.62, 0.78), 0.62)
    streak = smoothstep(0.86, 0.97, value_noise(m.p * np.array([1.0, 0.25, 1.0], np.float32), 90, 426))
    fin_rgb = mix(fin_rgb, (0.66, 0.88, 0.97), streak * 0.5)
    fin_rgb = mix(fin_rgb, (0.62, 0.86, 0.96), smoothstep(0.75, 0.98, reach) * 0.6)
    rgb = mix(rgb, fin_rgb, np.clip(fins * 1.2, 0, 1))
    # A few glints on the druzy between the shards
    glint = speckle(m, 150, 0.9, seed=425) * (1 - covered.reshape(shape)) * (1 - fins)
    rgb = mix(rgb, (0.78, 0.92, 1.0), glint * 0.7)
    # The fish's own band edges and creases stay on the crust, not drawn across a shard
    cover = covered.reshape(shape) * (1 - fins)
    return done(m, rgb, "gloss", metal=np.full(m.y.shape, 0.2, np.float32), detail=0.4, hush=cover * 0.85, relief=0)


def catch_prism(m):  # Prism: brushed silver with a soft cool rainbow film, its own pattern in full colour
    lines = own_lines(m)
    n = m.nrm
    rgb = body_coat(m, (0.50, 0.55, 0.62), (0.64, 0.68, 0.76), soft=0.3)
    # Cool hues only (green, cyan, blue, violet): a warm or pink film on silver is the
    # pale tone the skin screen exists for
    t = 0.5 + 0.5 * np.sin(2.4 * (n[..., 0] * 0.6 + n[..., 2] * 0.5) + m.y * 5)
    hue = 0.3 + 0.48 * t
    film = hsv_to_rgb(np.stack([hue, np.full_like(hue, 0.42), np.full_like(hue, 0.88)], -1))
    rgb = mix(rgb, film, 0.32)
    emboss = smoothstep(0.35, 0.65, lines)
    vivid = hsv_to_rgb(np.stack([hue, np.full_like(hue, 0.85), np.full_like(hue, 0.95)], -1))
    rgb = mix(rgb, vivid, emboss * 0.85)
    grating = 0.94 + 0.06 * np.sin(m.y * 900 + m.p[..., 2] * 600)
    rgb = rgb * grating[..., None]
    emit = vivid * (emboss * 0.3)[..., None]
    return done(m, rgb, "satin", emit=emit, metal=np.full(m.y.shape, 0.3, np.float32), detail=0.4)


def week_wave(m):  # The Great Wave (v12): breaking-wave crests sweeping tail-ward, pale-blue foam
    """Owner, 2026-10-17: the patterns "look like mesh slapped onto the fish". Now the
    whole fish is the sea: wave after wave wrapping it from belly to back, each crest
    an S that pitches forward at the top like a breaking lip, each wave a gradient
    from a deep trough up a sunlit face to the crest, its leading edge a scalloped
    band of pale-blue foam (never white-on-dark lines), thickest where it breaks,
    with spray thrown ahead and a shadowed hollow under it.
    Countershaded (deeper on the back), lighter as in v11, the fins a deep sea blue
    rimmed in foam, and a faint even glow so the water can't drag it dark."""
    sm = smooth(m)
    fins, _ = fin_parts(m)
    reach = fin_reach(m)
    on_fin = hard(fins)
    u, v, vn = height(sm)
    hh, at = girth(sm)
    # How many waves: about one per 0.21 of the length, fewer on a short round fish
    period = 0.21
    # Each crest an S: upright low on the flank, its top pitching forward (tail-ward)
    # over the face like a breaking wave's lip
    vc = np.clip(vn, -1.2, 1.2)
    bend = 0.025 * vc + 0.075 * smoothstep(0.1, 1.0, vc) ** 2 - 0.02 * smoothstep(-0.2, -1.0, vc)
    wob = 0.012 * np.sin(vn * 5.0 + u * 9.0)
    phase = (u - bend - wob) / period
    t = phase - np.floor(phase)  # 0 just behind a crest's face .. 1 at the next crest
    which = np.floor(phase)
    # The sea: deep in the trough, rising lighter up the wave's back to the crest
    trough, face, light = C(0.05, 0.36, 0.68), C(0.14, 0.58, 0.86), C(0.40, 0.81, 0.96)
    ramp = smoothstep(0.0, 0.85, t)
    sea = mix(board(m, trough), face, smoothstep(0.0, 0.45, t))
    sea = mix(sea, light, smoothstep(0.45, 0.9, t))
    sea = sea * (1.06 - 0.16 * smoothstep(0.3, 1.0, sm.up))[..., None]  # countershaded
    # Long streaks in the water running up each wave's back
    streak = smoothstep(0.62, 0.8, value_noise(np.stack([u * 3.0, vn * 1.2, which * 3.1], -1).astype(np.float32), 9.0, 2601))
    sea = mix(sea, (0.46, 0.84, 0.97), streak * ramp * 0.35)
    # The foam: a scalloped band on the crest's leading edge, thickest at the top of
    # the wave where it breaks, pale blue
    claws = 0.5 + 0.5 * np.cos(2 * np.pi * vn / 0.22 + which * 1.7)
    foam_w = (0.06 + 0.13 * smoothstep(-0.3, 1.0, vn)) * (0.55 + 0.45 * claws)
    foam_f = t - (1 - foam_w)
    calm = smoothstep(0.07, 0.15, u)  # calm water over the face (no foam round the eyes)
    foam = crisp(m, foam_f, texels=1.4) * calm
    foam_line = crisp(m, foam_f + 0.025, texels=1.4) * (1 - foam) * calm  # its shadow just behind
    hollow = smoothstep(0.08, 0.0, t) * smoothstep(-0.2, 0.6, vn)  # under the crest that just passed
    spray = smoothstep(0.0034, 0.0018, nearest_dots(m, 2602, 1100)) * smoothstep(0.0, 0.06, t) * smoothstep(0.16, 0.06, t) * smoothstep(0.0, 0.6, vn)
    foam_col = C(0.80, 0.93, 1.0)
    rgb = mix(sea, (0.05, 0.30, 0.58), hollow * 0.6)
    rgb = mix(rgb, (0.22, 0.56, 0.84), foam_line)
    rgb = mix(rgb, foam_col, foam)
    rgb = mix(rgb, foam_col, spray * (1 - foam))
    # Fins: a deep sea blue, lighter outward, a crisp foam rim on the free edge
    fin_rgb = mix(board(m, (0.08, 0.40, 0.72)), (0.24, 0.64, 0.90), smoothstep(0.2, 0.85, reach))
    fin_rgb = mix(fin_rgb, (0.05, 0.30, 0.60), smoothstep(0.25, 0.8, own_lines(m)) * on_fin * 0.5)
    rgb = mix(rgb, fin_rgb, on_fin)
    rim = crisp(m, reach - 0.86, texels=1.5) * on_fin
    rgb = mix(rgb, foam_col, rim)
    # A faint, even self-glow (v11), less in the hollows and the foam's shadow
    emit = rgb * (0.48 * (1 - 0.6 * np.maximum(hollow * (1 - on_fin), foam_line)))[..., None]
    return done(m, rgb, "satin", emit=emit, detail=0.5)


def nearest_dots(m: Fish, seed, count=900):
    """Distance to the nearest of `count` random dots (for spray, bubbles)."""
    return cache(m, ("dots", seed, count), lambda: nearest(m, scatter(m, count, seed))[0])


def week_reef(m):  # A living reef: brain coral, sea fans and tiny fish over turquoise
    fins, tip = fin_parts(m)
    u, v, vn = height(m)
    hh, at = girth(m)
    rgb = body_coat(m, (0.04, 0.70, 0.72), (0.0, 0.50, 0.62), soft=0.3)
    rgb = mix(rgb, (0.40, 0.90, 0.86), net(m, 240, 0.004, seed=415) * 0.3)
    rng = np.random.default_rng(411)
    low = smoothstep(0.6, -0.3, vn) * (1 - fins)
    pts = scatter(m, 13, 412, weight=low + 0.02)
    d1, _, i = nearest(m, pts)
    pu = point_y(m, pts)
    R = np.array([0.62 * at(x) for x in pu]) * (0.8 + 0.4 * rng.random(len(pts)))
    R = np.maximum(R, 0.022)[i]
    blob = hard(smoothstep(R * 1.02, R * 0.96, d1 * (1 + 0.3 * (fbm(m, 14, 413) - 0.5))))
    kinds = np.array([(0.72, 0.86, 0.0), (1.0, 0.50, 0.0), (1.0, 0.80, 0.0)], np.float32)
    grooves = np.array([(0.16, 0.30, 0.0), (0.46, 0.10, 0.0), (0.50, 0.28, 0.0)], np.float32)
    kind = rng.integers(0, 3, len(pts))[i]
    maze = contours(m, 7, 9, seed=414, warp=0.8)
    coral = mix(kinds[kind], grooves[kind], smoothstep(0.14, 0.06, maze))
    coral = coral * (0.78 + 0.22 * smoothstep(1.0, 0.4, d1 / R))[..., None]
    rgb = mix(rgb, coral, blob)
    fans = np.zeros_like(u)
    for k in range(4):
        uc = 0.24 + 0.17 * k + rng.uniform(-0.03, 0.03)
        h = at(uc)
        base_v = -0.55 * h
        du, dv = u - uc, v - base_v
        r = np.hypot(du, dv)
        th = np.arctan2(dv, du)
        reach_ = 1.0 * h
        sector = smoothstep(0.5, 0.65, th) * smoothstep(2.65, 2.5, th)
        spoke = smoothstep(0.0016, 0.0008, r * np.abs(np.sin((th - 0.5) * 6)))
        ring_gap = reach_ / 5
        arcs = smoothstep(0.0014, 0.0007, np.abs(r - np.round(r / ring_gap) * ring_gap)) * (r > ring_gap * 0.5)
        stem = smoothstep(0.0028, 0.0016, segment(u, v, (uc, base_v - 0.3 * h), (uc, base_v + 0.2 * reach_))[0])
        fans = np.maximum(fans, np.clip(spoke + arcs, 0, 1) * sector * smoothstep(reach_, reach_ * 0.96, r) + stem)
    fans = hard(fans) * (1 - blob) * (1 - fins)
    rgb = mix(rgb, (0.50, 0.12, 0.88), fans)
    school = np.zeros_like(u)
    school_col = np.zeros_like(u)
    for g, (cu, cn, col) in enumerate(((0.34, 0.5, 1.0), (0.64, 0.45, 0.0))):
        h = at(cu)
        L = max(0.3 * h, 0.012)
        placed = []
        tries = 0
        while len(placed) < 7 and tries < 200:
            tries += 1
            fu = cu + rng.uniform(-3.0, 3.0) * L
            fv = (cn + rng.uniform(-0.3, 0.3)) * at(fu)
            if all(np.hypot((fu - a) / 1.3, fv - b) > 1.25 * L for a, b in placed):
                placed.append((fu, fv))
        for fu, fv in placed:
            du, dv = (u - fu) / L, (v - fv) / L
            body_ = ((du / 0.5) ** 2 + (dv / 0.24) ** 2) < 1
            tail_ = (du > 0.42) & (du < 0.85) & (np.abs(dv) < (du - 0.42) * 0.75)
            shape = (body_ | tail_).astype(np.float32)
            school = np.maximum(school, shape)
            school_col = np.where(shape > 0, col, school_col)
    school = school * (1 - blob) * (1 - fins)
    fish_col = mix(board(m, (0.02, 0.10, 0.34)), (1.0, 0.80, 0.0), school_col)
    rgb = mix(rgb, fish_col, school)
    return done(m, rgb, "satin", detail=0.5)



def barnacle_field(m: Fish, pts, radii, light=(0.35, 0.94)):
    """Barnacles at `pts` (texel positions) of `radii` (body lengths): (shell 0..1, a
    colour layer, the openings 0..1). Each is a low cone seen from outside: six
    plates with dark seams, the side toward the light lit and the far side shaded, a
    bright rim round the top, a dark diamond slit in it (the shut beak plates, a paler
    seam between them, each barnacle turned its own way), and a soft shadow on the
    skin round its foot. Nearest-first, so a cluster packs like real barnacles do."""
    d1, d2, i = nearest(m, pts)
    a, b = offsets(m, pts, i)
    R = radii[i]
    rr = d1 / np.maximum(R, 1e-5)
    ang = np.arctan2(b, a)
    lx, ly = light
    facing = (np.cos(ang) * lx + np.sin(ang) * ly)  # -1 away from the light .. 1 toward it
    shell = crisp(m, 1.0 - rr, texels=1.3)
    plates = (ang / (2 * np.pi) * 6 + (i % 7) * 0.13) % 1.0
    seam = smoothstep(0.06, 0.0, np.abs(plates - 0.5) - 0.42) * smoothstep(0.42, 0.55, rr)
    cone = 0.78 + 0.32 * facing * smoothstep(0.35, 1.0, rr)
    base_col = mix(board(m, (0.50, 0.58, 0.62)), (0.64, 0.72, 0.76), smoothstep(0.9, 0.5, rr))
    col = base_col * cone[..., None]
    col = mix(col, (0.36, 0.42, 0.45), seam * 0.6)
    rim = smoothstep(0.1, 0.0, np.abs(rr - 0.46)) * (0.55 + 0.45 * np.clip(facing * 0.5 + 0.6, 0, 1))
    col = mix(col, (0.80, 0.88, 0.92), rim * 0.8)
    # The opening: a diamond slit (the shut beak plates), each barnacle turned its own
    # way, with the seam between its plates a paler line: never a round dark hole,
    # which next to a fish's eye read as more eyes
    turn = (i * 2.399).astype(np.float32) % np.pi
    ca, sa = np.cos(turn), np.sin(turn)
    ra = (a * ca + b * sa) / np.maximum(R, 1e-5)
    rb = (-a * sa + b * ca) / np.maximum(R, 1e-5)
    slit = np.abs(ra) / 0.4 + np.abs(rb) / 0.17
    opening = crisp(m, 1.0 - slit, texels=1.2)
    beak = smoothstep(0.05, 0.015, np.abs(rb)) * (slit < 1.0)
    inner = mix(board(m, (0.10, 0.20, 0.22)), (0.42, 0.52, 0.54), beak * 0.85)
    col = mix(col, inner, opening)
    foot = smoothstep(1.45, 1.0, rr) * (1 - shell)
    return shell, col, opening, foot


def surface_polar(m: Fish, u, v, cu, cv):
    """Polar coordinates on the skin round the flank point (cu along the body, cv up
    from the mid-line), one point on each side: (distance in body lengths, angle,
    which side's point). The distance is straight through 3D from the point and the
    angle is in the skin's tangent plane there (forward toward the tail, up), so a
    circle drawn with them stays round on a round fish (the Puffer, the Angler)
    where print coordinates stretch it toward the back and belly. Each texel takes
    its own side's point."""
    sd = side(m)
    out_r = np.full(u.shape, 10.0, np.float32)  # far from both points
    out_t = np.zeros(u.shape, np.float32)
    for s_ in (1.0, -1.0):
        # On the outer skin facing out that way (the meshes hold stray inner faces:
        # the Angler's right flank picked one facing in)
        sel = m.real & (sd == s_) & (m.fin < 0.3) & (m.nrm[..., 0] * s_ > 0.35)
        cost = np.where(sel, (u - cu) ** 2 + (v - cv) ** 2, np.inf)
        k = np.unravel_index(np.argmin(cost), cost.shape)
        P, N = m.p[k], m.nrm[k]
        fwd = np.array([0, 1, 0], np.float32) - N * N[1]
        fwd /= max(float(np.linalg.norm(fwd)), 1e-6)
        up = np.cross(N, fwd) * s_
        o = m.p - P
        here = (sd == s_) & ((m.nrm * N).sum(-1) > -0.2)
        out_r = np.where(here, np.linalg.norm(o, axis=-1), out_r)
        out_t = np.where(here, np.arctan2((o * up).sum(-1), (o * fwd).sum(-1)), out_t)
    return out_r, out_t


def whirl(r, th, radius, arms=3, turns=4.6, width=0.42):
    """A whirlpool from polar coordinates (r, th) round its centre: `arms` bold arms of
    a log spiral winding about a turn and a half into the middle (`turns`: radians of
    turn per e-fold of radius), each `width` of the gap between arms wide at the rim
    and thinning toward the middle. Returns (the arms' signed distance in arm-gaps,
    positive inside an arm; the distance from the centre over `radius`; the arm's
    leading side 0..1)."""
    rn = r / radius
    s = (th * arms + turns * arms * np.log(np.maximum(rn, 1e-3))) / (2 * np.pi)
    f = s - np.round(s)  # -0.5 .. 0.5 across the gap, 0 on an arm's spine
    w = width * (0.3 + 0.7 * smoothstep(0.08, 0.95, rn)) * 0.5
    return w - np.abs(f), rn, smoothstep(-w * 0.2, w, f)


def week_wreck(m):  # Barnacled (v12; the id stays WeekWreck): a weathered wreck-dweller crusted with barnacles
    """Owner, 2026-10-17: "what the hell is a shipwreck skin doing" on a fish. Now a fish
    that lives on a wreck, not the wreck: a weathered slate-green hide, countershaded,
    mottled and pitted, with clusters of barnacles (cones with lit rims and dark
    slit openings) crusted along the back and over the head, kept clear of the eyes
    (round dark holes beside an eye read as more eyes), crusts of violet coralline
    algae on the flanks, and a few streaks of kelp trailing back from the clusters.
    Fins weathered darker with ragged paler tips. The palette stays saturated (screen
    2026-10-16: a greyer verdigris scored 0.83 on the Nibbler), the pale parts are the
    barnacles' cool grey rims, and a faint even glow keeps it from going dark in the
    water (v11)."""
    sm = smooth(m)
    fins, _ = fin_parts(m)
    reach = fin_reach(m)
    on_fin = hard(fins)
    u, v, vn = height(sm)
    hh, at = girth(sm)
    rng = np.random.default_rng(2501)
    # The hide: slate-green, darker on the back, mottled and pitted
    # Lighter than a real slate so it reads in the water (v11: the weekly skins read
    # dark there), with little red in it (a light teal with more red scored 0.19 on
    # the Nibbler's atlas once JPEG-packed, v11)
    rgb = body_coat(sm, (0.13, 0.52, 0.47), (0.24, 0.70, 0.61), soft=0.35)
    mottle = fbm(m, 7, 2502)
    rgb = rgb * (0.82 + 0.3 * mottle)[..., None]
    rgb = mix(rgb, (0.09, 0.38, 0.35), smoothstep(0.62, 0.72, fbm(m, 16, 2503)) * 0.4)
    pits = speckle(m, 300, 0.86, seed=2504)
    rgb = mix(rgb, (0.06, 0.24, 0.24), pits * 0.5)
    # Fins: a darker weathered slate, ragged paler tips (worn)
    fin_rgb = mix(board(m, (0.11, 0.46, 0.42)), (0.19, 0.60, 0.53), smoothstep(0.55, 0.95, reach))
    ragged = smoothstep(0.84, 0.9, reach + 0.12 * (fbm(m, 40, 2505) - 0.5))
    fin_rgb = mix(fin_rgb, (0.34, 0.60, 0.56), ragged)
    rgb = mix(rgb, fin_rgb, on_fin)
    body = (1 - on_fin) * m.real
    # Coralline algae: violet crusts on the flanks with knobbly lighter growth and a
    # darker margin (a cool violet, never pink)
    crust_f = fbm(m, 11, 2506, octaves=2) + 0.18 * smoothstep(0.62, 0.3, sm.up) - 0.2 * smoothstep(0.22, 0.0, u)
    crust = crisp(m, crust_f - 0.745, texels=1.4) * body
    margin = crisp(m, crust_f - 0.737, texels=1.4) * (1 - crust) * body
    knobs = smoothstep(0.55, 0.75, value_noise(m.p, 150, 2507))
    crust_col = mix(board(m, (0.48, 0.32, 0.70)), (0.64, 0.50, 0.86), knobs * 0.8)
    rgb = mix(rgb, (0.24, 0.12, 0.40), margin)
    rgb = mix(rgb, crust_col, crust)
    # Barnacle clusters along the back and over the head
    on_back = smoothstep(0.58, 0.8, sm.up) * body
    on_head = smoothstep(0.32, 0.18, u) * smoothstep(0.35, 0.6, sm.up) * body
    weight = np.clip(on_back + on_head, 0, 1) * smoothstep(0.03, 0.08, u) * smoothstep(0.92, 0.82, u)
    weight = weight * smoothstep(0.03, 0.06, m.eye_clear)  # none crowding an eye
    centres = scatter(m, 9, 2508, weight=weight)
    cd, _, _ = nearest(m, centres)
    near_centre = np.exp(-((cd / 0.05) ** 2)) * weight
    pts = scatter(m, 110, 2509, weight=near_centre + 0.01 * weight)
    size = np.clip(at_points(m, pts, hh) * 0.2, 0.007, 0.019)
    radii = (size * (0.6 + 0.6 * rng.random(len(pts)))).astype(np.float32)
    shell, shell_col, opening, foot = barnacle_field(m, pts, radii)
    shell = shell * body
    rgb = rgb * (1 - 0.35 * foot * body)[..., None]
    rgb = mix(rgb, shell_col, shell)
    # Kelp: a few fronds trailing back from the clusters, wavy ribbons with a darker
    # midrib, wider near their holdfast
    kelp = np.zeros(u.shape, np.float32)
    rib = np.zeros(u.shape, np.float32)
    cu, cv = at_points(m, centres, u), at_points(m, centres, v)
    for k in range(min(4, len(centres))):
        u0, v0 = float(cu[k]), float(cv[k])
        length = 0.2 + 0.12 * rng.random()
        t = np.clip((u - u0) / length, 0, 1)
        wave = 0.3 * at(u0) * np.sin(t * 2.2 * np.pi + k) * t
        dv = np.abs(v - (v0 - 0.3 * at(u0) * t + wave))
        width = (0.022 * (1 - 0.6 * t) * smoothstep(0.0, 0.08, t) + 0.003) * min(1.0, at(u0) / 0.1)
        span = (u > u0) & (u < u0 + length)
        kelp = np.maximum(kelp, crisp(m, width - dv, texels=1.3) * span)
        rib = np.maximum(rib, crisp(m, width * 0.2 - dv, texels=1.0) * span)
    kelp = kelp * body * (1 - shell)
    rgb = mix(rgb, (0.30, 0.50, 0.10), kelp)
    rgb = mix(rgb, (0.18, 0.32, 0.06), rib * kelp)
    # A faint, even self-glow (v11): less in the openings, the seams and the pits
    dark = np.maximum(opening * shell, pits * 0.5)
    emit = rgb * (0.55 * (1 - 0.8 * dark))[..., None]
    return done(m, rgb, "matte", emit=emit, detail=0.6)


SEGMENTS = {  # a seven-segment digit: (a top, b top right, c bottom right, d bottom, e bottom left, f top left, g middle)
    "0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc",
    "5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg",
}


def hull_number(m: Fish, rgb, text, u_mid, vn_mid, paint_rgb=(0.58, 0.64, 0.72), edge=None, chip=0.4):
    """Paints a stencilled number on both flanks, reading the right way round on each.
    With `edge` (a colour) it also draws a dark rim round the strokes so the number
    reads on a light hull, and returns (rgb, paint mask); `chip` is how much of the
    stencil has flaked off (the fbm cut: lower keeps more)."""
    u, v, vn = height(m)
    hh, at = girth(m)
    h = 0.55 * at(u_mid)
    w = 0.55 * h
    x = (u - u_mid) * side(m)
    y = v - vn_mid * at(u_mid)
    paint = np.zeros_like(u)
    rim = np.zeros_like(u)
    gap = w * 1.45
    for k, ch in enumerate(text):
        cx = (k - (len(text) - 1) / 2) * gap
        lx, ly = x - cx, y
        bars = {
            "a": ((-w / 2, h / 2), (w / 2, h / 2)),
            "d": ((-w / 2, -h / 2), (w / 2, -h / 2)),
            "g": ((-w / 2, 0), (w / 2, 0)),
            "b": ((w / 2, 0), (w / 2, h / 2)),
            "c": ((w / 2, -h / 2), (w / 2, 0)),
            "e": ((-w / 2, -h / 2), (-w / 2, 0)),
            "f": ((-w / 2, 0), (-w / 2, h / 2)),
        }
        for seg_ in SEGMENTS[ch]:
            a, b = bars[seg_]
            d, _ = segment(lx, ly, a, b)
            paint = np.maximum(paint, smoothstep(h * 0.11, h * 0.08, d))
            if edge is not None:
                rim = np.maximum(rim, smoothstep(h * 0.17, h * 0.13, d))
    chipped = hard(paint * smoothstep(chip, chip + 0.06, fbm(m, 30, 425)))
    if edge is None:
        return mix(rgb, paint_rgb, chipped)
    rgb = mix(rgb, edge, hard(rim) * (1 - chipped))
    return mix(rgb, paint_rgb, chipped), chipped


def week_sea_glass(m):  # Sea glass: frosted pebbles of bottle green, cobalt and amber, dark grout
    pts = scatter(m, 420, 430)
    d1, d2, i = nearest(m, pts)
    rng = np.random.default_rng(431)
    palette = np.array(
        [(0.08, 0.46, 0.26), (0.16, 0.56, 0.34), (0.10, 0.24, 0.72), (0.18, 0.34, 0.82), (0.96, 0.56, 0.0), (0.86, 0.44, 0.0)],
        np.float32,
    )
    light = np.array(
        [(0.36, 0.74, 0.56), (0.44, 0.80, 0.62), (0.40, 0.56, 0.92), (0.48, 0.62, 0.96), (1.0, 0.74, 0.08), (1.0, 0.66, 0.04)],
        np.float32,
    )
    kind = rng.integers(0, len(palette), len(pts))[i]
    rel = (d2 - d1) / (d2 + d1 + 1e-6)
    dome = smoothstep(0.0, 0.5, rel)
    rgb = mix(palette[kind], light[kind], dome * 0.55)
    frost = value_noise(m.p, 260, 432)
    rgb = rgb * (0.94 + 0.12 * frost)[..., None]
    grout = smoothstep(0.09, 0.03, rel)
    rgb = mix(rgb, (0.07, 0.09, 0.11), grout)
    return done(m, rgb, "satin", detail=0.4)


# ---------------------------------------------------------------------------
# The Tide Pass's skins (Config/Pass season 1; owner, 2026-10-12)
# ---------------------------------------------------------------------------


def pass_tideglass(m):  # Tideglass: frosted sea glass in teal, pale ripple lines, a pearl film
    m = smooth(m)
    rgb = body_coat(m, (0.08, 0.40, 0.42), (0.34, 0.66, 0.64), soft=0.3)
    rgb = mix(rgb, (0.10, 0.34, 0.40), m.fin * 0.8)
    ripple = smoothstep(0.08, 0.02, contours(m, 3.5, 7, 51, warp=0.25))
    rgb = mix(rgb, (0.62, 0.90, 0.86), ripple * 0.75)
    frost = value_noise(m.p, 220, 52)
    rgb = rgb * (0.92 + 0.16 * frost)[..., None]
    rgb = pearl(m, rgb, 0.22, 0.10, 0.50)
    return done(m, rgb, "gloss", detail=0.6)


def pass_riptide(m):  # Riptide (v12): a glowing rip current flowing head to tail over deep ocean blue
    """Owner, 2026-10-17, of the pass skins: "random lines" read as "mesh slapped onto
    the fish". v8's Riptide was short foam streaks scattered over navy. Now one
    designed current: a broad band of glowing cyan water that rises from under the
    gills and flows along the flank to the tail in a long S, narrowing as it goes,
    with a few clean streamlines running inside it and tapered speed lines raking back
    above and below it, over a countershaded deep ocean blue. The fins are deep blue
    with cyan tips. Pale lines sit only on the mid-cyan band, never on the dark body
    (the skin screen reads thin pale lines on a dark body as skin)."""
    sm = smooth(m)
    fins, _ = fin_parts(m)
    reach = fin_reach(m)
    on_fin = hard(fins)
    body = 1 - on_fin
    u, v, vn = height(sm)
    hh, at = girth(sm)
    rgb = body_coat(sm, (0.03, 0.13, 0.38), (0.10, 0.30, 0.60), soft=0.3)
    # The current's path: from low behind the head, an S along the flank to the tail
    s_ = np.clip((u - 0.12) / 0.86, 0, 1)
    path = -0.35 + 0.42 * s_ + 0.24 * np.sin(2 * np.pi * (s_ * 1.1 + 0.08))
    half = 0.36 * (1 - 0.55 * s_) * smoothstep(0.08, 0.2, u)
    off = (vn - path) / np.maximum(half, 1e-3)  # -1 .. 1 across the band
    band = crisp(sm, 1.0 - np.abs(off), texels=1.5) * body
    core = smoothstep(1.0, 0.0, np.abs(off))
    water = mix(board(m, (0.06, 0.48, 0.80)), (0.22, 0.80, 0.96), core)
    rgb = mix(rgb, water, band)
    # Streamlines inside it, parallel to its edges, flowing tail-ward
    lines = np.zeros(u.shape, np.float32)
    for k, at_ in enumerate((-0.55, -0.1, 0.4)):
        d = np.abs(off - at_ - 0.06 * np.sin(2 * np.pi * (u * 4.0 + k * 0.3)))
        gap = 0.5 + 0.5 * np.sin(2 * np.pi * (u * 3.2 - k * 0.37))
        lines = np.maximum(lines, crisp(sm, 0.07 - d, texels=1.2) * smoothstep(0.25, 0.55, gap))
    lines = lines * band
    rgb = mix(rgb, (0.62, 0.94, 1.0), lines * 0.85)
    # Speed lines: a few long tapered dashes raking back above and below the band
    rng = np.random.default_rng(2701)
    dash = np.zeros(u.shape, np.float32)
    for k in range(7):
        side_ = 1.0 if k % 2 == 0 else -1.0
        gap = 1.25 + 0.35 * rng.random()
        u0 = 0.2 + 0.62 * rng.random()
        length = 0.1 + 0.08 * rng.random()
        t = np.clip((u - u0) / length, 0, 1)
        within = (u > u0) & (u < u0 + length)
        lane = path + side_ * half * gap
        d = np.abs(vn - lane) * hh
        width = 0.006 * np.clip(np.sin(np.pi * t), 0, 1) ** 0.6 * min(1.0, at(u0) / 0.1) + 1e-5
        dash = np.maximum(dash, crisp(sm, width - d, texels=1.2) * within)
    dash = dash * body * (1 - band)
    halo = glow_halo(dash > 0.5, 3) * (1 - dash) * body * (1 - band)
    rgb = mix(rgb, (0.10, 0.40, 0.72), halo * 0.6)
    rgb = mix(rgb, (0.40, 0.80, 0.98), dash)
    # Fins: deep blue, cyan toward the tips
    fin_rgb = mix(board(m, (0.04, 0.16, 0.44)), (0.12, 0.56, 0.86), smoothstep(0.55, 0.98, reach))
    rgb = mix(rgb, fin_rgb, on_fin)
    emit = (band * (0.25 + 0.5 * core))[..., None] * C(0.10, 0.60, 0.95) + lines[..., None] * C(0.3, 0.8, 1.0) * 0.6 + (dash * 0.5)[..., None] * C(0.2, 0.6, 0.95)
    return done(m, rgb, "satin", emit=emit, detail=0.6)


def pass_undertow(m):  # Undertow (v12): bold teal whirlpools over mid-toned violet
    """Owner, 2026-10-17: "Undertow should have the swirls moving not just a bunch of
    random lines on it." A few bold, clean whirlpools instead of v8's five thin spiral
    lines: one large on each flank, centred where the body is deepest, smaller ones on
    the cheek behind the eye, the tail fin and the dorsal fin (a long fish gets a
    second, smaller one along its flank). Each is three thick teal arms winding into a
    deep violet eye, their leading edges lighter, under a soft teal halo, on a
    mid-toned violet body (no near-white lines on a dark one: the skin screen read
    those as skin, 0.21-0.24). The game turns swirl particles over the whirlpools
    (Config/Shades), so they read as moving water."""
    sm = smooth(m)
    fins, _ = fin_parts(m)
    reach = fin_reach(m)
    on_fin = hard(fins)
    u, v, vn = height(sm)
    hh, at = girth(sm)
    flip = side(m)
    rgb = body_coat(sm, (0.26, 0.15, 0.52), (0.40, 0.28, 0.66), soft=0.32)
    fin_rgb = mix(board(m, (0.22, 0.12, 0.46)), (0.30, 0.20, 0.58), smoothstep(0.3, 0.9, reach))
    rgb = mix(rgb, fin_rgb, on_fin)
    # Where the whirlpools go: the deepest place along the middle of the flank (a
    # second along a long fish), the cheek, the tail fin and the dorsal fin's middles.
    # On the body they're drawn round a point on the skin (surface_polar, so a big one
    # stays round on a round fish); on a fin, flat in its own plane
    grid_u = np.linspace(0.32, 0.66, 35)
    peak = max(at(x) for x in grid_u)
    deep = float(grid_u[np.argmax([at(x) - 1.5 * peak * abs(x - 0.51) for x in grid_u])])
    big_r = float(np.clip(0.72 * at(deep), 0.035, 0.19))
    body = on_fin < 0.5
    spots = [(deep, 0.0, big_r, 3, 1.0, body, True)]
    if big_r < 0.12:  # a long, thin fish: a second, smaller one behind the first
        u2 = min(deep + 2.2 * big_r + 0.05, 0.78)
        spots.append((u2, 0.0, float(np.clip(0.72 * at(u2), 0.03, 0.18)), 3, -1.0, body, True))
    eye = m.eyes > 0.5
    if eye.any():
        eu = float(np.median(u[eye]))
        cu = min(eu + 0.1 + 0.35 * at(eu + 0.1), deep - big_r * 1.05)
        spots.append((cu, -0.35 * at(cu), float(np.clip(0.4 * at(cu), 0.02, 0.1)), 2, -1.0, body, True))
    tail = (on_fin > 0.5) & (u > 0.8) & m.real
    if tail.sum() > 200:
        tu, tv = float(np.median(u[tail])), float(np.median(v[tail]))
        tr = 0.32 * (np.percentile(v[tail], 95) - np.percentile(v[tail], 5))
        spots.append((tu, tv, float(np.clip(tr, 0.02, 0.09)), 2, -1.0, ~body, False))
    dorsal = (on_fin > 0.5) & (u > 0.25) & (u < 0.78) & (vn > 0.85) & m.real
    if dorsal.sum() > 200:
        du_, dv_ = float(np.median(u[dorsal])), float(np.median(v[dorsal]))
        dr = 0.34 * min(np.percentile(u[dorsal], 95) - np.percentile(u[dorsal], 5), 2 * (np.percentile(v[dorsal], 95) - np.percentile(v[dorsal], 5)))
        spots.append((du_, dv_, float(np.clip(dr, 0.02, 0.08)), 2, 1.0, ~body, False))
    arms_m = np.zeros(u.shape, np.float32)
    lead_m = np.zeros(u.shape, np.float32)
    eye_m = np.zeros(u.shape, np.float32)
    for cu, cv, radius, arms, turn, where, on_body in spots:
        if on_body:
            r, th = surface_polar(sm, u, v, cu, cv)
        else:  # a fin: flat in its own plane
            r, th = np.hypot(u - cu, v - cv), np.arctan2(v - cv, u - cu)
        field, rn, lead = whirl(r, th * flip * turn, radius, arms=arms)
        inside = smoothstep(1.0, 0.82, rn) * where
        arm = crisp(m, field, texels=1.4) * inside * smoothstep(0.1, 0.2, rn)
        arms_m = np.maximum(arms_m, arm)
        lead_m = np.maximum(lead_m, arm * lead * smoothstep(0.25, 0.6, rn))
        eye_m = np.maximum(eye_m, smoothstep(0.22, 0.1, rn) * where)
    arms_m *= m.cov
    halo = glow_halo(arms_m > 0.5, 7) * (1 - arms_m)
    rgb = mix(rgb, (0.12, 0.05, 0.28), eye_m * 0.8)  # the deep eye of each whirlpool
    rgb = mix(rgb, (0.20, 0.52, 0.62), halo * 0.55)
    rgb = mix(rgb, (0.12, 0.74, 0.72), arms_m)
    rgb = mix(rgb, (0.36, 0.88, 0.84), lead_m * 0.7)
    # Teal fin tips, soft
    rgb = mix(rgb, (0.14, 0.56, 0.62), smoothstep(0.8, 0.98, reach) * on_fin * 0.6)
    emit = arms_m[..., None] * C(0.14, 0.78, 0.74) + (halo * 0.4)[..., None] * C(0.10, 0.52, 0.56) + (lead_m * 0.3)[..., None] * C(0.3, 0.9, 0.85)
    return done(m, rgb, "gloss", emit=emit, detail=0.6, floor=0.5)


def pass_abyssal_current(m):  # Abyssal Current: the deep's black-green water, a drifting current, bioluminescent motes
    m = smooth(m)
    u, v, vn = height(m)
    # Lifted out of near-black (playtest 2026-10-16: very dark, navy with faint specks
    # from the side): a deep teal-green water, the current wider and brighter, more
    # motes, a second faint current lower down. Still the deep: no pale fields
    rgb = body_coat(m, (0.05, 0.21, 0.23), (0.10, 0.36, 0.36), soft=0.3)
    rgb = mix(rgb, (0.04, 0.16, 0.19), m.fin * 0.6)
    drift = fbm(m, 4, 56)
    band = smoothstep(0.32, 0.0, np.abs(vn + 0.1 + (drift - 0.5) * 0.6)) * (1 - m.fin)
    under = smoothstep(0.16, 0.0, np.abs(vn + 0.62 - (drift - 0.5) * 0.4)) * (1 - m.fin)
    rgb = mix(rgb, (0.07, 0.64, 0.56), band * 0.75)
    rgb = mix(rgb, (0.05, 0.50, 0.48), under * 0.55)
    motes = speckle(m, 130, 0.865, seed=57) * (1 - m.fin * 0.5) * m.cov
    halo = glow_halo(motes, 4)
    rgb = mix(rgb, (0.16, 0.78, 0.68), halo * 0.6)
    rgb = mix(rgb, (0.62, 1.0, 0.88), motes)
    rgb = sheen(m, rgb, 0.14, (0.5, 0.9, 0.85))
    emit = (
        motes[..., None] * C(0.55, 1.0, 0.85)
        + (halo * 0.4)[..., None] * C(0.15, 0.75, 0.65)
        + (band * 0.35 + under * 0.2)[..., None] * C(0.05, 0.5, 0.45)
    )
    return done(m, rgb, "satin", emit=emit, detail=0.7)


# ---------------------------------------------------------------------------
# X-Ray (v13; owner, 2026-10-18: "X ray needs to be an actual skeleton too this looks
# rough"): an anatomical skeleton laid out on the body's own side silhouette
# ---------------------------------------------------------------------------


def outline(m: Fish):
    """The body's side silhouette with the fins left out, smooth along it: (u at the
    bins' middles, the middle height there, half the height there), all in body
    lengths (u along the body from the snout, heights in the print coordinates'
    v, so on both flanks alike). Fish._cross_section's middle follows the median
    texel and the fins pull it about (a straight spine drawn on it wandered with
    the dorsal fins); this is the midpoint of the body's own top and bottom."""
    if isinstance(m, Smooth):
        m = m.base

    def make():
        mask, _, _ = blades(m)
        body = m.real & (mask < 0.3)
        u, z = m.y, m.p[..., 2]
        bins = 64
        idx = np.clip((u * bins).astype(int), 0, bins - 1)
        top = np.full(bins, np.nan)
        bot = np.full(bins, np.nan)
        for b in range(bins):
            sel = body & (idx == b)
            if sel.sum() > 40:
                top[b], bot[b] = np.percentile(z[sel], 97), np.percentile(z[sel], 3)
        good = np.isfinite(top)
        at = np.arange(bins)
        top = np.interp(at, at[good], top[good])
        bot = np.interp(at, at[good], bot[good])
        top = ndimage.gaussian_filter1d(top, 1.6, mode="nearest")
        bot = ndimage.gaussian_filter1d(bot, 1.6, mode="nearest")
        centres = (at + 0.5) / bins
        return centres, (top + bot) / 2, np.maximum((top - bot) / 2, 1e-3)

    return cache(m, "outline", make)


def curve(points, steps=6):
    """A smooth polyline through `points` (Catmull-Rom, `steps` pieces between each
    pair), for bones that bend."""
    pts = np.asarray(points, np.float32)
    if len(pts) < 3:
        return pts
    ext = np.concatenate([2 * pts[:1] - pts[1:2], pts, 2 * pts[-1:] - pts[-2:-1]])
    out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for t in np.linspace(0, 1, steps, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3))
    out.append(pts[-1])
    return np.asarray(out, np.float32)


def bones_along(m: Fish, U, V, bones, texel):
    """Bones drawn along polylines in print coordinates (U along the body, V up, both
    in body lengths): each bone is (points (k, 2), half-width at its start, at its
    end). Returns (core 0..1 anti-aliased over about a texel and a half, roundness
    0..1: 1 down a bone's middle, 0 at its edges, so it can be shaded as a rod)."""
    core = np.zeros(U.shape, np.float32)
    round_ = np.zeros(U.shape, np.float32)
    real = m.real
    for pts, w0, w1 in bones:
        pts = np.asarray(pts, np.float32)
        pad = max(w0, w1) + 3 * texel
        lo, hi = pts.min(0) - pad, pts.max(0) + pad
        sel = real & (U >= lo[0]) & (U <= hi[0]) & (V >= lo[1]) & (V <= hi[1])
        if not sel.any():
            continue
        uu, vv = U[sel], V[sel]
        seg = np.diff(pts, axis=0)
        lens = np.linalg.norm(seg, axis=1)
        total = max(float(lens.sum()), 1e-6)
        cum = np.concatenate([[0.0], np.cumsum(lens)])
        best = np.full(uu.shape, np.inf, np.float32)
        ratio = np.full(uu.shape, np.inf, np.float32)
        for k in range(len(seg)):
            a, d = pts[k], seg[k]
            t = np.clip(((uu - a[0]) * d[0] + (vv - a[1]) * d[1]) / max(float(d @ d), 1e-12), 0, 1)
            dist = np.hypot(uu - a[0] - t * d[0], vv - a[1] - t * d[1])
            s_ = (cum[k] + t * lens[k]) / total
            w = w0 + (w1 - w0) * s_
            edge = dist - w
            better = edge < best
            best = np.where(better, edge, best)
            ratio = np.where(better, dist / np.maximum(w, 1e-6), ratio)
        c = np.clip(0.5 - best / (1.5 * texel), 0, 1)
        r = np.clip(1 - ratio, 0, 1) ** 0.5
        core[sel] = np.maximum(core[sel], c)
        round_[sel] = np.maximum(round_[sel], r * c)
    return core, round_


def fin_rays(m: Fish, texel, spacing=0.016, width=(0.0022, 0.0011)):
    """The rays in every fin, fanning out from its root to its edge, in the fin's own
    plane (a fin's texels' two main axes in 3D, so a pectoral that stands out
    sideways is drawn flat on itself and both its faces agree): each ray a line from
    a centre a little inside the body behind the root, one every `spacing` body
    lengths at mid-fin, thinning out to the edge. (rays 0..1, membrane 0..1)."""
    _, _, label = blades(m)
    reach = fin_reach(m)
    rays_ = np.zeros(m.y.shape, np.float32)
    for k in np.unique(label):
        if k < 0:
            continue
        sel = (label == k) & m.real
        if sel.sum() < 200:
            continue
        P = m.p[sel]
        mean = P.mean(0)
        _, _, axes = np.linalg.svd(P - mean, full_matrices=False)
        a, b = (P - mean) @ axes[0], (P - mean) @ axes[1]
        r_sel = reach[sel]
        root = r_sel < 0.12
        tip = r_sel > 0.7
        if root.sum() < 10 or tip.sum() < 10:
            continue
        ra, rb = float(a[root].mean()), float(b[root].mean())
        ta, tb = float(a[tip].mean()), float(b[tip].mean())
        da, db = ta - ra, tb - rb
        span = max(float(np.hypot(da, db)), 1e-4)
        da, db = da / span, db / span
        # The fan's centre: back from the root, inside the body, about half the
        # fin's length (a long-based fin gets nearly parallel rays)
        root_len = float(np.ptp(-db * a[root] + da * b[root]))
        back = 0.45 * span + 0.6 * root_len
        ca, cb = ra - da * back, rb - db * back
        rho = np.hypot(a - ca, b - cb)
        phi = np.arctan2(b - cb, a - ca)
        lo, hi = np.percentile(phi, [1, 99])
        if hi - lo > np.pi:  # wrapped round
            phi = np.where(phi < 0, phi + 2 * np.pi, phi)
            lo, hi = np.percentile(phi, [1, 99])
        mid = back + 0.5 * span
        step = spacing / mid
        count = max(int(round((hi - lo) / step)), 3)
        step = (hi - lo) / count
        f = (phi - lo) / step
        off = np.abs(f - np.round(f)) * step * rho  # body lengths from the nearest ray
        w = width[0] + (width[1] - width[0]) * np.clip(r_sel, 0, 1)
        ray = np.clip(0.5 - (off - w) / (1.5 * texel), 0, 1)
        # Each ray stops just short of the fin's free edge
        ray *= smoothstep(1.0, 0.9, r_sel)
        rays_[sel] = np.maximum(rays_[sel], ray)
    return rays_


def xray(m):  # X-Ray (v13): an anatomical skeleton glowing through a translucent deep-blue body
    """The fish seen through an X-ray (owner, 2026-10-18: "X ray needs to be an actual
    skeleton too this looks rough"; v3 was wavy stripes on a dark body). Laid out on
    the body's own side silhouette (outline), so it reads side-on on both flanks:
    the skull (the braincase over the eye, a bony ring round the eye, the skull's
    floor running into the spine, upper and lower jaws to the jaw joint, the
    preopercle and the gill cover's edge, the shoulder girdle behind it), the
    vertebral column from the back of the skull to the tail (spool-shaped centra with
    dark joints between), neural spines up from every vertebra, ribs curving down
    and back round the belly cavity (a faint swim bladder under the spine), haemal
    spines down the tail, the supports under the dorsal and anal fins, and rays in
    every fin and the tail. Bones are ice-cyan with a wide soft blue glow on a
    mid-toned deep-blue body, lighter where the body is thickest like an X-ray,
    never thin near-white lines on black (the classifier reads those as skin); the
    eyes and the bone-white teeth are the fish's own (done())."""
    sm = smooth(m)
    texel = texel_size(m)
    fins, _ = fin_parts(m)
    reach = fin_reach(m)
    on_fin = hard(fins)
    body = 1 - on_fin
    U = m.y.astype(np.float32)
    Z = m.p[..., 2].astype(np.float32)
    cu, cmid, chalf = outline(m)
    mid = np.interp(U, cu, cmid).astype(np.float32)
    half = np.interp(U, cu, chalf).astype(np.float32)
    W = (Z - mid) / half  # -1 belly .. +1 back, on the body's own silhouette

    def mid_at(u):
        return float(np.interp(u, cu, cmid))

    def half_at(u):
        return float(np.interp(u, cu, chalf))

    def P(u, w):
        """A point at `u` along the body, `w` up its height (-1 belly .. 1 back)."""
        return (u, mid_at(u) + w * half_at(u))

    # Landmarks from the fish itself: the eye, the mouth (its teeth), the fins
    eye = (m.eyes > 0.5) & m.real
    eu = float(np.median(U[eye])) if eye.any() else 0.16
    ew = float(np.median(W[eye])) if eye.any() else 0.4
    toothy = (m.teeth > 0.5) & m.real & (m.y < 0.3)
    mw = float(np.median(W[toothy])) if toothy.any() else ew - 0.55
    mouth_end = float(np.percentile(U[toothy], 97)) if toothy.any() else eu * 0.7
    _, _, label = blades(m)
    fins_at = []  # (u, w, |x|) at each fin's root
    for k in np.unique(label):
        if k < 0:
            continue
        sel = (label == k) & m.real & (reach < 0.15)
        if sel.sum() < 20:
            continue
        fins_at.append((float(np.median(U[sel])), float(np.median(W[sel])), float(np.median(np.abs(sm.ex[sel]))), sel))
    # The skull ends at the gill cover's edge: the fish's own painted gill line, the
    # strongest painted line across the flank a little behind the eye
    lines = own_lines(m)
    band = m.real & (fins < 0.3) & (np.abs(W) < 0.6) & (U > eu + 0.03) & (U < eu + 0.16)
    gill_u = eu * 1.48
    if band.sum() > 200:
        hist, edges = np.histogram(U[band], bins=40, range=(eu + 0.03, eu + 0.16), weights=lines[band])
        counts, _ = np.histogram(U[band], bins=40, range=(eu + 0.03, eu + 0.16))
        dens = ndimage.gaussian_filter1d(hist / np.maximum(counts, 1), 1.0)
        gill_u = float((edges[:-1] + edges[1:])[np.argmax(dens)] / 2)
    skull = gill_u + 0.004
    tail = float(np.percentile(U[(m.real & (fins < 0.3))], 99.3)) - 0.01
    tail = max(tail, skull + 0.3)

    bones = []
    # -- The vertebral column: a little above the middle, down to the middle at the tail
    def spine_w(u):
        k = np.clip((u - skull) / max(tail - skull, 1e-3), 0, 1)
        return 0.12 * (1 - k**1.5)

    count = int(np.clip(round((tail - skull) / 0.021), 18, 40))
    step = (tail - skull) / count
    col_w = lambda u: (0.0105 - 0.0045 * np.clip((u - skull) / max(tail - skull, 1e-3), 0, 1)) * min(1.0, half_at(0.45) / 0.09)  # noqa: E731
    # Centra drawn as spools: a rounded box per vertebra, a little waisted, with a dark
    # joint between each
    s_ = (U - skull) / step
    i_ = np.floor(s_)
    frac = s_ - i_
    along = (frac - 0.5) * step
    vc = np.array([mid_at(u) + spine_w(u) * half_at(u) for u in cu], np.float32)
    v_col = np.interp(U, cu, vc).astype(np.float32)
    cw = np.array([col_w(u) for u in cu], np.float32)
    colw = np.interp(U, cu, cw).astype(np.float32)
    a_ = 0.42 * step
    waist = 1 - 0.22 * (1 - (2 * np.abs(along) / step) ** 2)
    b_ = colw * waist
    rr = 0.45 * np.minimum(a_, b_)
    qx = np.abs(along) - (a_ - rr)
    qy = np.abs(Z - v_col) - (b_ - rr)
    sd = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - rr
    in_col = (U > skull - 0.002) & (U < tail + 0.004)
    centra = np.clip(0.5 - sd / (1.5 * texel), 0, 1) * in_col
    centra_round = np.clip(1 - np.abs(Z - v_col) / np.maximum(b_, 1e-4), 0, 1) ** 0.5 * centra
    # The notochord's line through them, faint
    cord = np.clip(0.5 - (np.abs(Z - v_col) - 0.0012) / (1.5 * texel), 0, 1) * in_col

    # -- Neural spines (up), ribs (down and back round the cavity), haemal spines (down
    # the tail)
    cavity_end = skull + 0.55 * (tail - skull)
    for j in range(count):
        u = skull + (j + 0.5) * step
        top = spine_w(u)
        k = (u - skull) / (tail - skull)
        lean = 0.028 + 0.03 * k
        # Neural spine from the column's top up toward the back
        bones.append(([P(u, top + 0.08), P(u + lean * 0.5, 0.5), P(u + lean, 0.8)], 0.0021, 0.0011))
        if u < cavity_end:
            # A rib: down from the column, bowing forward, then back round the belly
            pts = []
            for t in np.linspace(0, 1, 9):
                du = -0.012 * np.sin(np.pi * t) + 0.055 * t**1.4
                pts.append(P(u + du, top - 0.1 - (top + 0.72) * t))
            bones.append((pts, 0.0025, 0.0012))
        else:
            # A haemal spine down from the tail's column
            bones.append(([P(u, top - 0.08), P(u + lean * 0.5, -0.5), P(u + lean, -0.8)], 0.0021, 0.0011))
    # Supports under the median fins (dorsal, anal): short rods into the body under
    # each fin's base, between the spines
    for fu, fw, fx, sel in fins_at:
        if fx > 0.35 or fu > tail - 0.02 or abs(fw) < 0.5:
            continue  # a paired fin, or the tail
        lo, hi = np.percentile(U[sel], [5, 95])
        sign = 1.0 if fw > 0 else -1.0
        for uu in np.linspace(lo, hi, max(int((hi - lo) / 0.012), 3)):
            bones.append(([P(uu, sign * 0.95), P(uu - 0.012, sign * 0.62)], 0.0022, 0.0013))

    # -- The skull
    ew_ = float(np.clip(ew, 0.1, 0.7))
    occ = skull - 0.008
    # The braincase: an arc over the eye from the snout to the back of the skull,
    # curving down behind into the column
    bones.append((curve([P(0.02, mw + 0.35), P(eu * 0.5, ew_ + 0.3), P(eu, ew_ + 0.44), P((eu + occ) / 2, 0.78), P(occ, 0.58), P(skull + 0.004, spine_w(skull) + 0.22)]), 0.0042, 0.0058))
    # Its floor (the parasphenoid), from the snout under the eye into the column
    bones.append((curve([P(0.03, mw + 0.12), P(eu * 0.6, ew_ - 0.3), P(eu + 0.03, ew_ - 0.42), P(skull, spine_w(skull))]), 0.0036, 0.0068))
    # Upper jaw along the mouth, lower jaw under it back to the jaw joint
    joint = (min(mouth_end + 0.02, eu + 0.01), mw - 0.15)
    bones.append((curve([P(0.004, mw + 0.08), P(mouth_end * 0.6, mw + 0.14), P(joint[0] - 0.01, mw + 0.04)]), 0.0028, 0.0046))
    bones.append((curve([P(0.006, mw - 0.1), P(mouth_end * 0.5, mw - 0.32), P(mouth_end, mw - 0.42), P(*joint)]), 0.0032, 0.0055))
    # The bone from the braincase down behind the eye to the jaw joint (the
    # hyomandibular), the preopercle's curve behind it and the gill cover's edge
    pre = eu + 0.035 + 0.25 * (occ - eu)
    bones.append((curve([P(eu + 0.028, ew_ + 0.4), P(eu + 0.03, ew_ - 0.1), P(*joint)]), 0.0028, 0.0034))
    bones.append((curve([P(pre, ew_ + 0.12), P(pre + 0.004, mw - 0.25), P(pre - 0.012, -0.62), P(joint[0] + 0.004, -0.66)]), 0.0032, 0.0026))
    gill = occ + 0.006
    bones.append((curve([P(pre + 0.01, ew_ + 0.22), P(gill - 0.008, 0.38), P(gill, 0.0), P(gill - 0.006, -0.42), P(gill - 0.022, -0.74)]), 0.0024, 0.0018))
    # Rays fanning under the gill cover (the branchiostegals)
    for i in range(4):
        bones.append((curve([P(joint[0] + 0.006 + 0.004 * i, -0.68 - 0.04 * i), P((joint[0] + gill) / 2 + 0.006 * i, -0.8 - 0.03 * i), P(gill - 0.02 + 0.004 * i, -0.86 - 0.02 * i)]), 0.0016, 0.0011))
    # The shoulder girdle (cleithrum) behind the gill cover, down to the belly
    cl = gill + 0.014
    bones.append((curve([P(cl - 0.004, 0.62), P(cl + 0.003, 0.2), P(cl + 0.008, -0.3), P(cl + 0.002, -0.72), P(cl - 0.012, -0.9)]), 0.0036, 0.0026))
    # Rods from it to each paired fin's root (pectorals, pelvics)
    for fu, fw, fx, sel in fins_at:
        if fx <= 0.35 or fu > tail - 0.05:
            continue
        w_root = float(np.clip(fw, -0.95, 0.6))
        start = P(cl + 0.006, float(np.clip(w_root * 0.6, -0.8, 0.1)))
        bones.append(([start, P(fu, w_root)], 0.0028, 0.0022))

    core, rnd = bones_along(m, U, Z, bones, texel)
    # The eye's bony ring (in the eye's own radius, round it)
    ring_core = smoothstep(0.24, 0.12, np.abs(m.eye_dist - 1.5)) * (m.eyes < 0.5)
    bones_ = np.maximum(np.maximum(core, centra), ring_core) * body
    rnd = np.maximum(np.maximum(rnd, centra_round), ring_core * 0.6) * body
    rays_ = fin_rays(m, texel) * on_fin
    bone = np.clip(np.maximum(bones_, rays_ * 0.92), 0, 1)

    # -- The body: translucent deep blue, lighter where it's thickest, as an X-ray shows
    # flesh; a darker cavity under the spine with a faint swim bladder in it; fins a
    # thin blue membrane
    thick = np.clip(1 - np.abs(W) ** 1.6, 0, 1)
    rgb = mix(board(m, (0.035, 0.10, 0.26)), (0.09, 0.25, 0.50), thick * 0.85)
    cloud = fbm(m, 9, 1301)
    rgb = rgb * (0.9 + 0.2 * cloud)[..., None]
    cavity = smoothstep(skull + 0.01, skull + 0.04, U) * smoothstep(cavity_end + 0.02, cavity_end - 0.03, U)
    cavity *= smoothstep(0.05, -0.05, W - np.interp(U, cu, [spine_w(x) for x in cu]) + 0.08) * smoothstep(-0.95, -0.7, W)
    rgb = mix(rgb, (0.05, 0.12, 0.32), cavity * 0.45 * body)
    bu = skull + 0.4 * (cavity_end - skull)
    bl = 0.32 * (cavity_end - skull)
    bladder = np.hypot((U - bu) / max(bl, 1e-3), (W + 0.12) / 0.26)
    bladder = smoothstep(1.0, 0.75, bladder) * body
    rgb = mix(rgb, (0.12, 0.34, 0.62), bladder * 0.55)
    membrane = mix(board(m, (0.06, 0.20, 0.44)), (0.10, 0.30, 0.58), smoothstep(0.3, 1.0, reach))
    rgb = mix(rgb, membrane, on_fin)
    # The joints between the centra, dark
    joints = smoothstep(0.1, 0.0, np.minimum(frac, 1 - frac)) * in_col * smoothstep(colw * 1.3, colw * 0.7, np.abs(Z - v_col))
    rgb = mix(rgb, (0.03, 0.07, 0.2), joints * 0.6 * body)

    # -- The bones: ice-cyan, lit down their middles, in a wide soft blue glow
    halo = np.clip(ndimage.gaussian_filter(bone, 3.5) * 2.2, 0, 1)
    wide = np.clip(ndimage.gaussian_filter(bone, 11) * 2.6, 0, 1)
    rgb = mix(rgb, (0.10, 0.36, 0.82), wide * 0.35)
    rgb = mix(rgb, (0.16, 0.50, 0.95), halo * 0.45)
    bone_rgb = mix(board(m, (0.30, 0.62, 0.98)), (0.62, 0.88, 1.0), np.clip(rnd * 1.2, 0, 1))
    rgb = mix(rgb, bone_rgb, bone)
    rgb = mix(rgb, (0.66, 0.9, 1.0), cord * 0.35 * body)
    emit = (
        C(0.30, 0.58, 1.0) * bone[..., None]
        + C(0.12, 0.32, 0.95) * (halo * 0.45)[..., None]
        + C(0.08, 0.18, 0.7) * (wide * 0.3)[..., None]
        + C(0.06, 0.18, 0.5) * (bladder * 0.25)[..., None]
    )
    return done(m, rgb, "satin", emit=emit, detail=0.8)


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
    # The per-fish lines (lines.json)
    "NibPercula": nib_percula,
    "NibTomato": nib_tomato,
    "NibMaroon": nib_maroon,
    "NibMidnight": nib_midnight,
    "CudaGreat": cuda_great,
    "CudaYellowtail": cuda_yellowtail,
    "CudaChevron": cuda_chevron,
    "CudaBlackfin": cuda_blackfin,
    "CudaChrome": cuda_chrome,
    "CudaComet": cuda_comet,
    "PufGuineafowl": puf_guineafowl,
    "PufGolden": puf_golden,
    "PufStarry": puf_starry,
    "PufGreen": puf_green,
    "PufUrchin": puf_urchin,
    "PufCoralBloom": puf_coral_bloom,
    "PufSunburst": puf_sunburst,
    "MorGreen": mor_green,
    "MorZebra": mor_zebra,
    "MorSnowflake": mor_snowflake,
    "MorHoneycomb": mor_honeycomb,
    "MorSerpent": mor_serpent,
    "MorRibbon": mor_ribbon,
    "MorJade": mor_jade,
    "ShkBlacktip": shk_blacktip,
    "ShkWhitetip": shk_whitetip,
    "ShkGrey": shk_grey,
    "ShkLemon": shk_lemon,
    "ShkWarpaint": shk_warpaint,
    "ShkScarred": shk_scarred,
    "ShkBoneplate": shk_boneplate,
    "AngSeadevil": ang_seadevil,
    "AngHumpback": ang_humpback,
    "AngWarty": ang_warty,
    "AngFootball": ang_football,
    "AngMurk": ang_murk,
    "AngDriftwood": ang_driftwood,
    "AngBioglow": ang_bioglow,
    "AngGlassveins": ang_glassveins,
    "AngAbyssEye": ang_abyss_eye,
    "AngLanternKing": ang_lantern_king,
    "AngStarfall": ang_starfall,
    # Universal: the catch track and the weekly skins
    "CatchSilver": catch_silver,
    "CatchGolden": catch_golden,
    "CatchGlowing": catch_glowing,
    "CatchCrystal": catch_crystal,
    "CatchPrism": catch_prism,
    "WeekWave": week_wave,
    "WeekReef": week_reef,
    "WeekWreck": week_wreck,
    "WeekSeaGlass": week_sea_glass,
    "PassTideglass": pass_tideglass,
    "PassRiptide": pass_riptide,
    "PassUndertow": pass_undertow,
    "PassAbyssalCurrent": pass_abyssal_current,
}


def save_rgb(path, arr):
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).save(path)


def save_gray(path, arr):
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "L").save(path)


STALE_SKIP = {"eyes_debug"}


def prune(folder: pathlib.Path, keep: list[str]):
    """Removes skins a fish no longer gets (a shade moved to another fish's line), so
    nothing stale is screened or packed."""
    for path in folder.glob("*.png"):
        stem = path.stem
        if stem in STALE_SKIP or stem.startswith("finish_"):
            continue
        shade = stem
        for suffix in ("_emit", "_metal", "_rough", "_normal"):
            shade = shade.removesuffix(suffix)
        if shade not in keep:
            path.unlink()


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    only = None
    for a in sys.argv[1:]:
        if a.startswith("--only="):
            only = set(a.split("=", 1)[1].split(","))
    maps, out = pathlib.Path(args[0]), pathlib.Path(args[1])
    names = args[2:] or [p.stem for p in sorted(maps.glob("*.npz"))]
    eyes = json.loads((HERE / "eyes.json").read_text())
    teeth = json.loads((HERE / "teeth.json").read_text())
    todo = {s for f in names for s in shade_lines.shades(f) if not only or s in only}
    missing = sorted(todo - set(RECIPES))
    if missing:
        raise SystemExit(f"[shades] lines.json names shades with no recipe: {', '.join(missing)}")
    for name in names:
        wanted = shade_lines.shades(name)
        fish = Fish(name, maps / f"{name}.npz", eyes.get(name, {}).get("picks", []), teeth.get(name))
        folder = out / name
        folder.mkdir(parents=True, exist_ok=True)
        dbg = fish.color.copy()
        dbg = mix(dbg, (1, 0, 1), fish.keep * 0.8)
        dbg = mix(dbg, (0, 1, 0), fish.fin * 0.5)
        dbg = mix(dbg, (1, 0.5, 0), fish.teeth * 0.9)
        Image.fromarray((np.clip(dbg, 0, 1) * 255).astype(np.uint8)).save(folder / "eyes_debug.png")
        manifest_path = folder / "skins.json"
        manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
        manifest = {k: v for k, v in manifest.items() if k in wanted or k == "Natural"}
        # The Natural skin (own look, white teeth) for a fish with teeth
        natural_wanted = name in teeth
        prune(folder, wanted + (["Natural"] if natural_wanted else []))
        if natural_wanted and (not only or "Natural" in only):
            skin = natural(fish)
            save_rgb(folder / "Natural.png", skin["rgb"])
            (folder / "Natural_emit.png").unlink(missing_ok=True)
            if skin["emit"] is not None:
                save_rgb(folder / "Natural_emit.png", skin["emit"])
            manifest["Natural"] = {"finish": "satin", "emit": skin["emit"] is not None, "metal": False, "rough": False, "normal": False}
            print(f"[shades] {name}: Natural", flush=True)
        elif not natural_wanted:
            manifest.pop("Natural", None)
        made = 0
        for shade in wanted:
            if only and shade not in only:
                continue
            skin = RECIPES[shade](fish)
            save_rgb(folder / f"{shade}.png", skin["rgb"])
            for suffix in ("_emit", "_metal", "_rough", "_normal"):
                (folder / f"{shade}{suffix}.png").unlink(missing_ok=True)
            if skin["emit"] is not None:
                save_rgb(folder / f"{shade}_emit.png", skin["emit"])
            if skin.get("normal") is not None:
                save_rgb(folder / f"{shade}_normal.png", skin["normal"])
            if skin["metal"] is not None:
                save_gray(folder / f"{shade}_metal.png", skin["metal"])
            if skin["rough"] is not None:
                save_gray(folder / f"{shade}_rough.png", skin["rough"])
            manifest[shade] = {
                "finish": skin["finish"],
                "emit": skin["emit"] is not None,
                "metal": skin["metal"] is not None,
                "rough": skin["rough"] is not None,
                "normal": skin.get("normal") is not None,
            }
            made += 1
            print(f"[shades] {name}: {shade}", flush=True)
        # The finish maps every shade without its own roughness shares
        for finish in sorted({v["finish"] for v in manifest.values()}):
            save_gray(folder / f"finish_{finish}.png", finish_map(fish, finish))
        for stale in folder.glob("finish_*.png"):
            if stale.stem.removeprefix("finish_") not in {v["finish"] for v in manifest.values()}:
                stale.unlink()
        manifest_path.write_text(json.dumps(manifest, indent=1, sort_keys=True) + "\n")
        print(f"[shades] {name}: {made} skins ({len(wanted)} in its list)")


if __name__ == "__main__":
    main()
