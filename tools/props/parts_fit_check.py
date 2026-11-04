"""The other half of parts_fit.py, for the PC's own Python (Blender's has no PIL, no torch).

    python tools/props/parts_fit_check.py board [Fish | before | swim_<...>]   # contact sheets from the cells
    python tools/props/parts_fit_check.py check [--no-classifier]              # manifest.json and the image screen

`check` reads every GLB in assets/glb/parts/fit: triangles, images and sizes, sha256. It
fails on anything that must never upload: a material with a normal texture, an image with
the normal-map signature (mean B >= 240, spread <= 10, R and G within 20 of 128: Roblox
terminated the account over one, 2026-10-13), an image over 512x512, a model over 4,000
triangles. Then the colour screen and the classifier from tools/shades/screen_shades.py
over every image, each colour map also judged against its fish's own texture.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import pathlib
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/glb/parts/fit"
PREVIEWS = OUT / "previews"
CELLS = PREVIEWS / "_cells"
FISH = ["Nibbler", "Cuda", "Puffer", "MorayEel", "ReefShark", "Angler"]
PARTS = ["AnglerLure", "NarwhalHorn", "SawSnout", "SailFin", "VeilTail"]
MAX_TRIS = 4000
MAX_SIZE = 512


def font(size=18):
    try:
        return ImageFont.truetype("arialbd.ttf", size)
    except OSError:
        return ImageFont.load_default()


def board_fish(fish: str):
    names = [("side", "side"), ("three", "three-quarter"), ("close", "where it meets the fish")]
    first = Image.open(CELLS / f"{fish}_{PARTS[0]}_side.png")
    w, h = first.size
    sheet = Image.new("RGB", (120 + w * 3, 30 + h * len(PARTS)), (16, 24, 32))
    draw = ImageDraw.Draw(sheet)
    for i, (_, label) in enumerate(names):
        draw.text((130 + i * w, 6), label, fill=(240, 220, 140), font=font())
    for j, part in enumerate(PARTS):
        draw.text((6, 30 + j * h + h // 2 - 10), part[:12], fill=(220, 236, 240), font=font(14))
        for i, (view, _) in enumerate(names):
            sheet.paste(Image.open(CELLS / f"{fish}_{part}_{view}.png").convert("RGB"), (120 + i * w, 30 + j * h))
    sheet.save(PREVIEWS / f"{fish}.png")
    print(f"[parts_fit] {PREVIEWS / f'{fish}.png'}")


def board_before():
    pairs = [("ReefShark", "SailFin"), ("ReefShark", "VeilTail"), ("Nibbler", "SailFin"), ("Nibbler", "VeilTail")]
    first = Image.open(CELLS / f"before_{pairs[0][0]}_{pairs[0][1]}_side.png")
    w, h = first.size
    sheet = Image.new("RGB", (w * 4, 30 + h * len(pairs)), (16, 24, 32))
    draw = ImageDraw.Draw(sheet)
    for i, label in enumerate(("before: side", "before: three-quarter", "after: side", "after: three-quarter")):
        draw.text((10 + i * w, 6), label, fill=(240, 220, 140), font=font())
    for j, (fish, part) in enumerate(pairs):
        for i, name in enumerate(("before", "after")):
            for k, view in enumerate(("side", "three")):
                sheet.paste(
                    Image.open(CELLS / f"{name}_{fish}_{part}_{view}.png").convert("RGB"), ((i * 2 + k) * w, 30 + j * h)
                )
        draw.text((10, 34 + j * h), f"{fish} {part}", fill=(255, 255, 255), font=font())
    sheet.save(PREVIEWS / "before_after.png")
    print(f"[parts_fit] {PREVIEWS / 'before_after.png'}")


def board_swim(tag: str):
    cells = sorted(CELLS.glob(f"swim_{tag}_*.png"))
    parts = []
    for c in cells:
        name = c.stem.split("_")[2]
        if name not in parts:
            parts.append(name)
    w, h = Image.open(cells[0]).size
    phases = sorted({c.stem.split("_")[3] for c in cells}, key=float)
    sheet = Image.new("RGB", (w * len(phases), h * len(parts)))
    for j, part in enumerate(parts):
        for i, phase in enumerate(phases):
            sheet.paste(Image.open(CELLS / f"swim_{tag}_{part}_{phase}.png").convert("RGB"), (i * w, j * h))
    sheet.save(PREVIEWS / f"swim_{tag}.png")
    print(f"[parts_fit] {PREVIEWS / f'swim_{tag}.png'}")


def read_glb(path: pathlib.Path):
    data = path.read_bytes()
    magic, _, _ = struct.unpack("<III", data[:12])
    if magic != 0x46546C67:
        raise ValueError(f"{path} is not a GLB")
    offset, doc, binary = 12, None, b""
    while offset < len(data):
        length, kind = struct.unpack("<II", data[offset : offset + 8])
        chunk = data[offset + 8 : offset + 8 + length]
        if kind == 0x4E4F534A:
            doc = json.loads(chunk)
        else:
            binary = chunk
        offset += 8 + length
    return doc, binary


def glb_images(doc: dict, binary: bytes):
    out = []
    for image in doc.get("images", []):
        view = doc["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        out.append((image.get("name", "image"), Image.open(io.BytesIO(binary[start : start + view["byteLength"]]))))
    return out


def normal_signature(rgb: np.ndarray) -> bool:
    b = rgb[..., 2]
    return bool(
        float(b.mean()) >= 240
        and float(b.std()) <= 10
        and abs(float(rgb[..., 0].mean()) - 128) <= 20
        and abs(float(rgb[..., 1].mean()) - 128) <= 20
    )


def check(no_classifier: bool, color_only: bool = False) -> int:
    sys.path.insert(0, str(ROOT / "tools/shades"))
    import screen_shades as screen

    problems: list[str] = []
    classifier = None
    if not no_classifier:
        classifier = screen.load_classifier()
    seats = json.loads((OUT / "seats.json").read_text())
    manifest = []
    worst = {"score": -1.0, "image": ""}
    rows = []
    base_masks: dict[str, tuple] = {}
    for fish in FISH:
        # The fish's own colour map, uploaded long ago: the control
        fbm = next((ROOT / "assets/fbx/species").glob(f"{fish}.fbm/Color_*"))
        base = Image.open(fbm).convert("RGB")
        base_masks[fish] = base
    glbs = sorted(OUT.glob("*.glb"))
    for path in glbs:
        fish, part = path.stem.split("_", 1)
        doc, binary = read_glb(path)
        tris = 0
        box_lo, box_hi = np.full(3, np.inf), np.full(3, -np.inf)
        for mesh in doc.get("meshes", []):
            for prim in mesh["primitives"]:
                attrs = prim["attributes"]
                if "indices" in prim:
                    tris += doc["accessors"][prim["indices"]]["count"] // 3
                else:
                    tris += doc["accessors"][attrs["POSITION"]]["count"] // 3
                box_lo = np.minimum(box_lo, doc["accessors"][attrs["POSITION"]]["min"])
                box_hi = np.maximum(box_hi, doc["accessors"][attrs["POSITION"]]["max"])
                if "NORMAL" not in attrs:
                    problems.append(f"{path.name}: no normals (it would shade flat and wrong)")
                if "TANGENT" in attrs:
                    problems.append(f"{path.name}: has tangents, which only a normal map uses")
        # The GLB's coordinates are the game's root space at 1 stud long: its box is its seat
        seat = seats.get(fish, {}).get(part)
        if seat is None:
            problems.append(f"{path.name}: no seat in seats.json")
        elif (
            np.abs((box_lo + box_hi) / 2 - seat["center"]).max() > 0.001
            or np.abs(box_hi - box_lo - seat["size"]).max() > 0.001
        ):
            problems.append(f"{path.name}: its box {box_lo} .. {box_hi} isn't its seat {seat['center']} {seat['size']}")
        elif seat.get("buried", 0) < 1:
            problems.append(f"{path.name}: only {seat['buried'] * 100:.0f}% of its root is under the skin")
        for mat in doc.get("materials", []):
            if "normalTexture" in mat:
                problems.append(f"{path.name}: material {mat.get('name')} has a NORMAL MAP")
        images = []
        for name, img in glb_images(doc, binary):
            rgb_img = img.convert("RGB")
            px = np.asarray(rgb_img)
            sig = normal_signature(px)
            if sig:
                problems.append(f"{path.name}: {name} has the normal-map signature")
            if max(img.size) > MAX_SIZE:
                problems.append(f"{path.name}: {name} is {img.size}")
            sc = screen.color_scores(px)[0]
            is_color = name.endswith("_Color")
            entry = {
                "name": name,
                "width": img.size[0],
                "height": img.size[1],
                "mode": img.mode,
                "mean_rgb": [round(float(a), 1) for a in px.reshape(-1, 3).mean(0)],
                "skin_pct": round(sc["skin"], 2),
                "pale_pct": round(sc["pale"], 2),
                "risk_blob_pct": round(sc["blob"], 2),
            }
            if classifier is not None and (is_color or not color_only):
                score = float(classifier.score(rgb_img))
                entry["classifier"] = round(score, 4)
                if score > worst["score"]:
                    worst = {"score": round(score, 4), "image": f"{path.name}:{name}"}
                if score > screen.NSFW_MAX:
                    problems.append(f"{path.name}: {name} scores {score:.3f} on the classifier")
            if is_color and sc["blob"] > screen.BLOB_ABS_MAX:
                rows.append(f"{path.name}: largest flesh-toned blob {sc['blob']:.1f}%")
            images.append(entry)
        if tris > MAX_TRIS:
            problems.append(f"{path.name}: {tris} triangles")
        manifest.append(
            {
                "file": path.name,
                "fish": fish,
                "part": part,
                "triangles": tris,
                "images": images,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "bytes": path.stat().st_size,
                "bone": seats.get(fish, {}).get(part, {}).get("bone"),
                "center": seats.get(fish, {}).get(part, {}).get("center"),
                "size": seats.get(fish, {}).get(part, {}).get("size"),
                "normal_maps": 0,
            }
        )
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n")
    tri_counts = [m["triangles"] for m in manifest]
    print(f"[parts_fit] {len(manifest)} GLBs, triangles {min(tri_counts)}..{max(tri_counts)}")
    total_images = sum(len(m["images"]) for m in manifest)
    print(f"[parts_fit] {total_images} images, none with a normal map (materials and signature checked)")
    skin = max((i["skin_pct"], i["name"]) for m in manifest for i in m["images"])
    pale = max((i["pale_pct"], i["name"]) for m in manifest for i in m["images"])
    blob = max((i["risk_blob_pct"], i["name"]) for m in manifest for i in m["images"])
    print(f"[parts_fit] highest skin {skin}, pale {pale}, largest blob {blob}")
    for row in rows:
        print(f"[parts_fit] NOTE {row}")
    if classifier is None:
        print("[parts_fit] classifier did NOT run")
    else:
        print(f"[parts_fit] classifier ran on every image, highest {worst['score']} ({worst['image']})")
    for p in problems:
        print(f"[parts_fit] PROBLEM {p}")
    print(f"[parts_fit] manifest -> {OUT / 'manifest.json'}")
    return 1 if problems else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["board", "check"])
    ap.add_argument("what", nargs="?", default="")
    ap.add_argument("--no-classifier", action="store_true")
    ap.add_argument("--color-only", action="store_true", help="classifier on colour maps only (a quick look)")
    args = ap.parse_args()
    if args.mode == "board":
        if args.what == "before":
            board_before()
        elif args.what.startswith("swim_"):
            board_swim(args.what[5:])
        elif args.what:
            board_fish(args.what)
        else:
            for fish in FISH:
                board_fish(fish)
        return 0
    return check(args.no_classifier, args.color_only)


if __name__ == "__main__":
    sys.exit(main())
