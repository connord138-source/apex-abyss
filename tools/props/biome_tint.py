"""Re-tints the base colour of a biome landmark GLB the moderation screen flagged
(tools/shades/screen_shades.py with the classifier), after strip_normals.py and
safe_colors.py, before it's bundled (owner, 2026-10-21: the biome detail boards).

    python3.11 tools/props/biome_tint.py <in.glb> <out.glb> <recipe>

Recipes:
  aged   old bone: pale texels (light, little colour) to a mossy grey-green at 70%
         of their brightness, flecked (BoneHeap scored 0.57 as a near-white field
         with thin cyan worms; the pale-bone lesson of the X-Ray skin)
  flecks only the speckle: a few thousand darker and lighter texels over the map, the
         toon materials' lesson (a big smooth even area can read as skin)
Everything but the base colour image is copied as it is.
"""

import io
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from safe_colors import base_color_images, read_glb, write_glb  # noqa: E402


def views_of(doc: dict, blob: bytes) -> list[bytes]:
    out = []
    for view in doc["bufferViews"]:
        start = view.get("byteOffset", 0)
        out.append(blob[start : start + view["byteLength"]])
    return out


def flecks(rgb: np.ndarray, count: int, seed: int = 11) -> np.ndarray:
    rng = np.random.default_rng(seed)
    h, w, _ = rgb.shape
    out = rgb.astype(np.float32)
    ys, xs = rng.integers(0, h, count), rng.integers(0, w, count)
    shade = rng.choice([0.78, 0.86, 1.12], count)
    for dy in (0, 1):
        for dx in (0, 1):
            yy, xx = np.clip(ys + dy, 0, h - 1), np.clip(xs + dx, 0, w - 1)
            out[yy, xx] *= shade[:, None]
    return np.clip(out, 0, 255).astype(np.uint8)


def aged(rgb: np.ndarray) -> np.ndarray:
    f = rgb.astype(np.float32)
    light = f.mean(axis=2)
    chroma = f.max(axis=2) - f.min(axis=2)
    pale = (light > 120) & (chroma < 60)
    moss = np.array([0.62, 0.70, 0.62], dtype=np.float32)
    out = np.where(pale[..., None], f * moss, f)
    return flecks(np.clip(out, 0, 255).astype(np.uint8), rgb.shape[0] * rgb.shape[1] // 90)


RECIPES = {"aged": aged, "flecks": lambda rgb: flecks(rgb, rgb.shape[0] * rgb.shape[1] // 90)}


def main() -> int:
    src, dst, recipe = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
    doc, blob = read_glb(src)
    views = views_of(doc, blob)
    for index in base_color_images(doc):
        image = doc["images"][index]
        raw = views[image["bufferView"]]
        picture = Image.open(io.BytesIO(raw))
        alpha = picture.getchannel("A") if picture.mode == "RGBA" else None
        rgb = np.asarray(picture.convert("RGB"))
        out = Image.fromarray(RECIPES[recipe](rgb))
        if alpha is not None:
            out.putalpha(alpha)
        buffer = io.BytesIO()
        if image.get("mimeType") == "image/jpeg":
            out.convert("RGB").save(buffer, "JPEG", quality=92)
        else:
            out.save(buffer, "PNG")
        views[image["bufferView"]] = buffer.getvalue()
    dst.parent.mkdir(parents=True, exist_ok=True)
    write_glb(dst, doc, views)
    print("wrote", dst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
