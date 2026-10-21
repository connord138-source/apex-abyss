"""Moves a prop GLB's base color out of the colors the moderation screen reads as
skin, before the prop goes anywhere near Roblox. Tripo's textures for warm creatures
(the octopus Den Mason, the hermit crab Outfitter, the pufferfish Shade Dyer) are
fields of salmon, peach and cream, the kind of unwrapped atlas Roblox's image
moderation once misread as human skin (Hatch & Snatch, 2026-10-03: the owner's account
was suspended for 7 days). See tools/shades/screen_shades.py for the rules.

    python tools/props/safe_colors.py assets/glb/props/KeeperMason.glb ... --out assets/glb/props_safe
    python tools/shades/screen_shades.py <folder of the extracted images>   # then screen

What it does to the base color texture only (metal/roughness and normal maps are
left alone), to each skin-tone or pale warm texel and a 2-texel ring round them:
- bright (cream, ivory, peach white, pale tan): a cool neutral white, same brightness;
- dark (brown shell, dark spots): darker, same hue, until red is under 95;
- dull (tan, beige canvas): greige, the same brightness with the red cast taken out;
- the rest (salmon, peach, orange-pink): more chroma, just enough to leave the skin
  box (Cr over 178 or Cb under 74), so salmon reads as the concept's vivid orange.
Everything else in the GLB (meshes, UVs, materials, the other images) is copied byte
for byte. Run the screen on the result and upload only what exits 0.

`--vivid` (for a yellow fish, 2026-10-19: the Butterflyfish's lemon body and fins came
out grey-white under the bright rule): a yellow texel (more yellow than red) of any
brightness gets more chroma instead, a deeper lemon at the same brightness, until it
leaves the skin box; peach, pink and the rest still go as above.

`--crimson` (2026-10-19: the Oarfish's orange-red fins over its pale blue-silver body
scored 0.99 on the classifier though no texel was skin tone; a truer red scored 0.03):
strong orange-reds lose most of their yellow and 15% of their brightness, a scarlet to
crimson red (never pink: the red keeps its chroma), before the rules above.

`--olive` (2026-10-21, the Porcupine Puffer variant: its tan body, 62% of the atlas in
the skin box, went vivid orange under the rule for "the rest", and read as the orange
Puffball beside it): tan, beige and salmon texels that aren't bright or dark become an
olive-khaki of the same brightness (yellow kept, red cast taken to a hair over
neutral), the colour of a real porcupinefish; brown spots still darken and cream still
goes cool white.

`--plum` (2026-10-19, the fourth prey batch: Tripo painted the Hatchetfish's unseen mouth
inside a plum-maroon, (110, 43, 73), though its sheet's mouth was closed; the prey
concepts' mouths had been plum too, a colour the screen distrusts): a plum, maroon or
crimson-pink texel (red well over green, blue over green) and a 2-texel ring of its
own warm neighbours become a cool navy-grey of the same brightness, before the rules
above. Orange and true red (blue under green) are left alone.
"""

from __future__ import annotations

import argparse
import io
import json
import pathlib
import struct
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "shades"))
from screen_shades import skin_masks  # noqa: E402

CR_EXIT = 178.0  # the skin box ends at Cr 173 and Cb 77; a margin past both
CB_EXIT = 74.0
K_MAX = 2.6  # never more than this much extra chroma
COOL = (3.0, -2.0)  # (dCb, dCr) of the cool white a bright texel becomes
BRIGHT = 175.0  # luma from which a warm texel turns white instead
DARK_RED = 132.0  # a texel this red or less is darkened instead (at most ~28% darker)
DULL = 26.0  # chroma under which a texel turns greige instead of more vivid
GREIGE = (0.5, -1.0)  # the greige keeps half its Cb (its yellow) and loses its red
FEATHER = 2
JPEG_QUALITY = 93
YELLOW = 0.8  # --vivid: a texel whose red cast is under this share of its yellow
K_YELLOW = 6.0  # --vivid: how far a pale yellow's chroma may be raised
CRIMSON = (0.4, 3.0, 0.85)  # --crimson: Cb offset kept, Cb added, brightness kept
PLUM = (30.0, 10.0)  # --plum: red over green, blue over green, at least
NAVY = (8.0, -5.0)  # --plum: (dCb, dCr) of the navy-grey it becomes
OLIVE = (12.0, 32.0, 1.0)  # --olive: the least and most yellow (-dCb) it keeps, and its dCr


def to_ycc(rgb: np.ndarray):
    c = rgb.astype(np.float32)
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    y = 0.299 * r + 0.587 * g + 0.114 * b
    cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b
    cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b
    return y, cb, cr


def to_rgb(y, cb, cr) -> np.ndarray:
    r = y + 1.402 * (cr - 128)
    g = y - 0.344136 * (cb - 128) - 0.714136 * (cr - 128)
    b = y + 1.772 * (cb - 128)
    return np.clip(np.stack([r, g, b], -1) + 0.5, 0, 255).astype(np.uint8)


def crimson(rgb: np.ndarray) -> np.ndarray:
    """Strong orange-reds toward a true red (see --crimson above)."""
    y, cb, cr = to_ycc(rgb)
    red = (cr - 128 > 30) & (rgb[..., 0].astype(np.float32) > rgb[..., 2].astype(np.float32) + 38)
    keep, add, bright = CRIMSON
    cb2 = np.where(red, 128 + (cb - 128) * keep + add, cb)
    return to_rgb(np.where(red, y * bright, y), cb2, cr)


def plum(rgb: np.ndarray) -> np.ndarray:
    """Plum, maroon and crimson-pink to a navy-grey (see --plum above)."""
    c = rgb.astype(np.float32)
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    core = (r > g + PLUM[0]) & (b > g + PLUM[1])
    zone = ndimage.binary_dilation(core, iterations=FEATHER) & (r > g + 6) & (b > g - 6)
    y, cb, cr = to_ycc(rgb)
    return np.where(zone[..., None], to_rgb(y, np.full_like(y, 128 + NAVY[0]), np.full_like(y, 128 + NAVY[1])), rgb)


def recolor(rgb: np.ndarray, vivid_yellow: bool = False, olive: bool = False) -> tuple[np.ndarray, dict]:
    out = rgb.copy()
    before = [m.mean() * 100 for m in skin_masks(rgb)]
    for _ in range(3):  # clipping at the gamut edge can leave a few; go again
        skin, pale = skin_masks(out)
        if not skin.any() and not pale.any():
            break
        y, cb, cr = to_ycc(out)
        dcb, dcr = cb - 128, cr - 128
        red = out[..., 0].astype(np.float32)
        # Feathered: the ring round each region is treated by its own color, but only
        # if it's warm too (a blue next to an orange patch stays blue)
        warm = (dcr > 0) & (dcb < 0)
        zone = ndimage.binary_dilation(skin | pale, iterations=FEATHER) & warm
        bright = zone & ((y >= BRIGHT) | pale)
        dark = zone & ~bright & (red <= DARK_RED)
        dull = zone & ~bright & ~dark & (np.hypot(dcb, dcr) < DULL)
        yellow = zone & ~dark & (dcr <= YELLOW * -dcb) if vivid_yellow else np.zeros_like(zone)
        bright &= ~yellow
        dull &= ~yellow
        vivid = zone & ~bright & ~dark & ~dull
        with np.errstate(divide="ignore", invalid="ignore"):
            k_cr = np.where(dcr > 0, (CR_EXIT - 128) / dcr, np.inf)
            k_cb = np.where(dcb < 0, (128 - CB_EXIT) / -dcb, np.inf)
        k = np.where(vivid, np.clip(np.minimum(k_cr, k_cb), 1.0, np.where(yellow, K_YELLOW, K_MAX)), 1.0)
        cb2, cr2 = 128 + dcb * k, 128 + dcr * k
        if olive:
            khaki = zone & ~bright & ~dark
            chroma = np.clip(np.hypot(dcb, dcr) * 0.9, OLIVE[0], OLIVE[1])
            cb2 = np.where(khaki, 128 - chroma, cb2)
            cr2 = np.where(khaki, 128 + OLIVE[2], cr2)
            dull &= ~khaki
        cb2 = np.where(bright, 128 + COOL[0], cb2)
        cb2 = np.where(dull, 128 + dcb * GREIGE[0], cb2)
        cr2 = np.where(bright, 128 + COOL[1], np.where(dull, 128 + GREIGE[1], cr2))
        result = to_rgb(y, cb2, cr2)
        shade = np.clip(94.0 / np.maximum(red, 1.0), 0.0, 1.0)[..., None]
        darker = np.clip(out.astype(np.float32) * shade + 0.5, 0, 255).astype(np.uint8)
        out = np.where(dark[..., None], darker, result)
    after = [m.mean() * 100 for m in skin_masks(out)]
    return out, {"skin": (round(before[0], 1), round(after[0], 1)), "pale": (round(before[1], 1), round(after[1], 1))}


def read_glb(path: pathlib.Path):
    data = path.read_bytes()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67 and version == 2, f"{path}: not a glTF 2 binary"
    json_len, json_type = struct.unpack_from("<II", data, 12)
    assert json_type == 0x4E4F534A
    doc = json.loads(data[20 : 20 + json_len])
    bin_header = 20 + json_len
    bin_len, bin_type = struct.unpack_from("<II", data, bin_header)
    assert bin_type == 0x004E4942
    blob = data[bin_header + 8 : bin_header + 8 + bin_len]
    return doc, blob


def write_glb(path: pathlib.Path, doc: dict, views: list[bytes]):
    """Lays the buffer views out again in order, 8-byte aligned."""
    blob = bytearray()
    for view, chunk in zip(doc["bufferViews"], views):
        while len(blob) % 8:
            blob.append(0)
        view["byteOffset"] = len(blob)
        view["byteLength"] = len(chunk)
        view["buffer"] = 0
        blob.extend(chunk)
    while len(blob) % 4:
        blob.append(0)
    doc["buffers"] = [{"byteLength": len(blob)}]
    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * ((4 - len(text) % 4) % 4)
    total = 12 + 8 + len(text) + 8 + len(blob)
    out = struct.pack("<III", 0x46546C67, 2, total)
    out += struct.pack("<II", len(text), 0x4E4F534A) + text
    out += struct.pack("<II", len(blob), 0x004E4942) + bytes(blob)
    path.write_bytes(out)


def base_color_images(doc: dict) -> set[int]:
    found = set()
    for material in doc.get("materials", []):
        info = material.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if info is not None:
            source = doc["textures"][info["index"]].get("source")
            if source is not None:
                found.add(source)
    return found


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("glbs", nargs="+")
    ap.add_argument("--out", required=True, help="folder for the safe GLBs (same file names)")
    ap.add_argument("--images", help="also write each new base color here as <Model>/baseColor.png, for the screen")
    ap.add_argument("--vivid", action="store_true", help="yellows get more chroma instead of turning white (see above)")
    ap.add_argument("--crimson", action="store_true", help="orange-reds toward a true red first (see above)")
    ap.add_argument("--olive", action="store_true", help="tan and beige to olive-khaki instead of vivid orange (see above)")
    ap.add_argument("--plum", action="store_true", help="plum and maroon (a mouth's inside) to navy-grey first (see above)")
    args = ap.parse_args()
    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    for name in args.glbs:
        path = pathlib.Path(name)
        doc, blob = read_glb(path)
        views = [
            blob[v.get("byteOffset", 0) : v.get("byteOffset", 0) + v["byteLength"]] for v in doc["bufferViews"]
        ]
        for index in sorted(base_color_images(doc)):
            image = doc["images"][index]
            view = image["bufferView"]
            rgb = np.asarray(Image.open(io.BytesIO(views[view])).convert("RGB"))
            if args.crimson:
                rgb = crimson(rgb)
            if args.plum:
                rgb = plum(rgb)
            safe, report = recolor(rgb, args.vivid, args.olive)
            buffer = io.BytesIO()
            if image.get("mimeType") == "image/png":
                Image.fromarray(safe).save(buffer, "PNG", optimize=True)
            else:
                Image.fromarray(safe).save(buffer, "JPEG", quality=JPEG_QUALITY, subsampling=0)
            views[view] = buffer.getvalue()
            print(f"{path.stem} image {index}: skin {report['skin'][0]}% -> {report['skin'][1]}%, pale {report['pale'][0]}% -> {report['pale'][1]}%")
            if args.images:
                folder = pathlib.Path(args.images) / path.stem
                folder.mkdir(parents=True, exist_ok=True)
                # What Roblox will get: the encoded image, decoded again
                Image.open(io.BytesIO(views[view])).convert("RGB").save(folder / "baseColor.png")
        write_glb(out_dir / path.name, doc, views)
    return 0


if __name__ == "__main__":
    sys.exit(main())
