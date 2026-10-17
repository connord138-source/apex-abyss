#!/usr/bin/env python3
"""Particle textures for the in-game skin effects (2026-10-17: the swirl particles that
turn over PassUndertow, mist, bubbles, glints, flames and sparks). Each is a 512x512
PNG in assets/textures/fx_<name>.png, uploaded once as an Image and keyed in
src/shared/Config/Textures.luau (id 0 falls back to a built-in texture until then).

    python3.11 tools/shades/make_fx.py                 # every fx_*.png
    python3.11 tools/shades/make_fx.py swirl bubble    # only those
    python3.11 tools/shades/screen_shades.py assets/textures/fx_*.png   # classifier on; must exit 0

The sheen rule (docs/ASSETS.md "Sheens"): the colour is one light tint set on every
pixel and the alpha alone says where the particle shows, so a moderation classifier
sees an even coloured field, never bright lines on black. The tint is pale cyan-white
(cool, outside every skin-tone rule) and the flame's a saturated warm yellow (no blend
toward white, which reads as peach); ParticleEmitter.Color tints them in game.
Edges are soft and every shape fades to nothing well inside the square, so no
particle shows its corners. The spark is a streak along the image's vertical, which
ParticleEmitter.Orientation VelocityParallel lines up with the particle's motion.
"""

from __future__ import annotations

import pathlib
import sys

import numpy as np
from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent.parent / "assets" / "textures"
SIZE = 512
PALE = (0.86, 0.97, 1.0)  # pale cyan-white
WARM = (1.0, 0.82, 0.22)  # the flame: a saturated warm yellow


def grid():
    """x, y in -1..1 (y up), r and the angle."""
    y, x = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    x = (x + 0.5) / SIZE * 2 - 1
    y = 1 - (y + 0.5) / SIZE * 2
    return x, y, np.hypot(x, y), np.arctan2(y, x)


def smoothstep(a, b, x):
    d = np.asarray(b, np.float32) - np.asarray(a, np.float32)
    d = np.where(np.abs(d) < 1e-6, 1e-6, d)
    t = np.clip((x - a) / d, 0, 1)
    return t * t * (3 - 2 * t)


def noise(x, y, freq, seed, octaves=4):
    """Smooth value noise (fbm) on the grid, 0..1."""
    rng = np.random.default_rng(seed)
    out = np.zeros_like(x)
    total, amp = 0.0, 1.0
    for o in range(octaves):
        f = freq * 2**o
        n = 64
        lattice = rng.random((n, n)).astype(np.float32)
        gx = (x * 0.5 + 0.5) * f + o * 7.1
        gy = (y * 0.5 + 0.5) * f + o * 3.3
        i0, j0 = np.floor(gx).astype(int), np.floor(gy).astype(int)
        fx, fy = gx - i0, gy - j0
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        a = lattice[j0 % n, i0 % n]
        b = lattice[j0 % n, (i0 + 1) % n]
        c = lattice[(j0 + 1) % n, i0 % n]
        d = lattice[(j0 + 1) % n, (i0 + 1) % n]
        out += amp * ((a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy)
        total += amp
        amp *= 0.5
    return out / total


def blur(a, sigma):
    from scipy import ndimage

    return ndimage.gaussian_filter(a, sigma)


def save(name, alpha, tint=PALE):
    alpha = np.clip(alpha, 0, 1)
    rgb = np.broadcast_to(np.array(tint, np.float32), alpha.shape + (3,))
    rgba = np.concatenate([rgb, alpha[..., None]], -1)
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(OUT / f"fx_{name}.png")
    print(f"[fx] fx_{name}.png  alpha mean {alpha.mean():.3f} max {alpha.max():.2f}")


def swirl():
    """A soft whirl: three arms of a log spiral winding into a calm middle, each arm
    thick near the rim and thinning as it curls in, fading out at the edge."""
    x, y, r, th = grid()
    arms = 3
    turns = 2.1  # how tightly the arms wind (radians of turn per e-fold of radius)
    s = (th * arms + turns * arms * np.log(np.maximum(r, 1e-4))) / (2 * np.pi)
    d = np.abs(s - np.round(s))  # 0 on an arm's spine .. 0.5 between arms
    width = 0.08 + 0.2 * smoothstep(0.1, 0.85, r)  # thicker outward
    arm = smoothstep(width, width * 0.25, d)
    # A soft leading edge: each arm brighter on its inner side, like water piling up
    lead = smoothstep(0.5, 0.0, (s - np.round(s)) * 2 + 0.3)
    alpha = arm * (0.65 + 0.35 * lead)
    alpha = alpha * smoothstep(0.98, 0.7, r) * smoothstep(0.05, 0.22, r)
    alpha = alpha + 0.18 * smoothstep(0.9, 0.3, r) * smoothstep(0.02, 0.2, r)  # a faint body of water
    alpha = blur(alpha, 2.0)
    save("swirl", alpha * 0.95)


def mist():
    """A wispy cloud puff: a few soft lobes of billowing noise with a ragged, thinning
    rim and streaky wisps, denser low in the middle, never a hard ball."""
    x, y, r, th = grid()
    warp = noise(x, y, 2.0, 13, octaves=3) - 0.5
    lobes = 0.0
    for cx, cy, rad in ((-0.22, -0.08, 0.5), (0.2, -0.12, 0.46), (0.02, 0.2, 0.44), (0.32, 0.22, 0.3), (-0.35, 0.22, 0.28)):
        d = np.hypot(x - cx + 0.25 * warp, y - cy - 0.2 * warp) / rad
        lobes = np.maximum(lobes, smoothstep(1.0, 0.2, d))
    n = noise(x + 0.4 * warp, y, 3.5, 11, octaves=5)
    wisps = 1 - np.abs(noise(x * 0.8 + 0.6 * warp, y * 2.2, 3.0, 12, octaves=4) - 0.5) * 2  # ridged
    alpha = lobes * (0.35 + 0.65 * smoothstep(0.3, 0.75, n)) * (0.75 + 0.25 * wisps)
    alpha = blur(alpha, 2.5) * smoothstep(0.98, 0.8, r)
    save("mist", alpha * 0.9)


def bubble():
    """A bubble: a soft rim, a faint inside, a bright highlight up and to the left and
    a smaller rim glint opposite."""
    x, y, r, th = grid()
    R = 0.78
    rim = np.exp(-(((r - R) / 0.055) ** 2))
    inside = 0.12 * smoothstep(R, R * 0.4, r)
    # Highlight: a curved crescent near the rim, up and left
    hx, hy = x + 0.36, y - 0.38
    spot = np.exp(-((hx / 0.16) ** 2 + (hy / 0.1) ** 2) * 1.0)
    rot = np.cos(th - np.deg2rad(135))
    crescent = np.exp(-(((r - R * 0.82) / 0.05) ** 2)) * smoothstep(0.55, 0.95, rot)
    glint = np.exp(-(((x - 0.38) / 0.07) ** 2 + ((y + 0.42) / 0.05) ** 2))
    alpha = np.maximum.reduce([rim * 0.75, inside, crescent * 0.95, spot * 0.9, glint * 0.6])
    alpha = blur(alpha, 1.2) * smoothstep(0.99, 0.9, r)
    save("bubble", alpha)


def star():
    """A four-point glint: two long thin rays and two shorter ones crossing, each
    tapering to a point, round a soft glowing core."""
    x, y, r, th = grid()
    ax, ay = np.abs(x), np.abs(y)

    def ray(along, across, length, width):
        t = np.clip(along / length, 0, 1)
        w = width * (1 - t) ** 1.6 + 1e-4
        return np.exp(-((across / w) ** 2)) * smoothstep(1.0, 0.0, t)

    rays = np.maximum(ray(ax, y, 0.92, 0.07), ray(ay, x, 0.92, 0.07))
    diag = ray(np.abs(x + y) / np.sqrt(2), (x - y) / np.sqrt(2), 0.45, 0.04)
    diag = np.maximum(diag, ray(np.abs(x - y) / np.sqrt(2), (x + y) / np.sqrt(2), 0.45, 0.04))
    core = np.exp(-((r / 0.12) ** 2))
    halo = 0.35 * np.exp(-((r / 0.38) ** 2))
    alpha = np.maximum.reduce([rays, diag * 0.5, core, halo])
    alpha = blur(alpha, 1.0) * smoothstep(1.0, 0.92, r)
    save("star", alpha)


def flame():
    """A soft flame tongue: a broad rounded base narrowing as it licks up and leans to
    a curling tip, a smaller tongue beside it, ragged by noise, densest low in the
    middle and wispy at its edges and top."""
    x, y, r, th = grid()
    n = noise(x * 1.2, y * 0.6 - 0.2, 4.0, 21, octaves=4)

    def tongue(cx, base, top, width, lean, seed_shift):
        h = (y - base) / (top - base)
        hc = np.clip(h, 0, 1)
        sway = lean * hc**1.6 + 0.05 * np.sin(hc * 5.0 + seed_shift) * hc
        half = width * (1 - hc) ** 0.75 * smoothstep(-0.25, 0.25, h) ** 0.5
        # A rounded base: below it the flame closes like a drop
        half = np.where(h < 0, width * np.sqrt(np.clip(1 - (h / 0.22) ** 2, 0, 1)), half)
        edge = half * (0.85 + 0.4 * (n - 0.5))
        dx = np.abs(x - cx - sway)
        body = smoothstep(edge, edge * 0.35, dx) * smoothstep(1.05, 0.75, h + 0.25 * (n - 0.5))
        core = smoothstep(edge * 0.6, 0.0, dx) * smoothstep(0.7, 0.1, h)
        return body, core

    b1, c1 = tongue(-0.04, -0.5, 0.92, 0.36, 0.22, 0.0)
    b2, c2 = tongue(0.2, -0.45, 0.3, 0.16, -0.12, 2.0)
    alpha = np.clip(np.maximum(b1, b2 * 0.8) * 0.78 + np.maximum(c1, c2 * 0.7) * 0.3, 0, 1)
    alpha = blur(alpha, 2.2) * smoothstep(0.99, 0.9, np.maximum(np.abs(x), np.abs(y)))
    save("flame", alpha, WARM)


def spark():
    """A short bright streak along the vertical: a hot middle tapering to both ends,
    a little longer behind (below) than ahead, with a soft glow round it."""
    x, y, r, th = grid()
    head, tail = 0.55, -0.8
    t = np.clip((y - tail) / (head - tail), 0, 1)
    width = 0.05 * np.clip(np.sin(np.pi * t), 0, 1) ** 0.7 + 1e-4
    inside = (y > tail) & (y < head)
    streak = np.exp(-((x / width) ** 2)) * inside * (0.4 + 0.6 * t)
    glow = 0.4 * np.exp(-((x / 0.14) ** 2)) * np.exp(-(((y - (head + tail) / 2) / 0.6) ** 2))
    alpha = np.maximum(streak, glow)
    alpha = blur(alpha, 1.2) * smoothstep(1.0, 0.9, np.maximum(np.abs(x), np.abs(y)))
    save("spark", alpha)


MAKERS = {"swirl": swirl, "mist": mist, "bubble": bubble, "star": star, "flame": flame, "spark": spark}


if __name__ == "__main__":
    wanted = [a.removeprefix("fx_") for a in sys.argv[1:]] or list(MAKERS)
    for name in wanted:
        MAKERS[name]()
