#!/usr/bin/env python3
"""Tiling sheen textures for the top skins (owner, 2026-10-12: "prismatic needs to
be moving across the fish not just static. same with the other highest rarity
skins"). Each is a 512x512 PNG that tiles in both directions; in game a Texture of
it sits on each face of the fish's mesh and slides (Shared/Cosmetics `sheen`), so
the pattern sweeps across the body while the skin underneath stays put. Upload
each as an Image (Decal) and paste its id into src/shared/Config/Textures.luau.

  python3 tools/shades/make_sheens.py            # writes assets/textures/sheen_*.png

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


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    prismatic()
    rgb, alpha = sparkle(7, 90, False)
    save("sheen_sparkle", rgb, alpha)
    rgb, alpha = sparkle(11, 60, True)
    save("sheen_gold", rgb, alpha)
    veil()


if __name__ == "__main__":
    main()
