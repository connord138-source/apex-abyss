"""Takes every normal map out of GLBs before they go anywhere near Roblox.

Never upload a normal map (2026-10-13): Roblox's moderation terminated the owner's
account over a flat lilac relief normal map that every check we have scored at zero
(it was reinstated on appeal). Tripo's GLBs all carry one (`NormalGL_*.png`, the
material's `normalTexture`), and Studio's importer uploads every texture a GLB holds,
so a Tripo model is stripped before it's bundled: the material loses its
`normalTexture`, and the image, its texture and its buffer view leave the file. The
color and ORM maps, meshes and UVs are kept, re-indexed, the binary chunk repacked.

    python tools/props/strip_normals.py assets/tripo/furniture/*.glb --out assets/glb/furniture_nonormals

Exits 1 if any output still holds a normal map (or an image no material uses).
"""

from __future__ import annotations

import argparse
import json
import pathlib
import struct
import sys

MATERIAL_TEXTURES = ("baseColorTexture", "metallicRoughnessTexture")
OTHER_TEXTURES = ("occlusionTexture", "emissiveTexture")


def read_glb(data: bytes) -> tuple[dict, bytes]:
    magic, _version, _length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, "not a GLB"
    offset = 12
    doc, binary = None, b""
    while offset < len(data):
        size, kind = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8 : offset + 8 + size]
        if kind == 0x4E4F534A:
            doc = json.loads(chunk)
        elif kind == 0x004E4942:
            binary = chunk
        offset += 8 + size
    assert doc is not None
    return doc, binary


def write_glb(doc: dict, binary: bytes) -> bytes:
    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(text) + (8 + len(binary) if binary else 0)
    out = struct.pack("<III", 0x46546C67, 2, total)
    out += struct.pack("<II", len(text), 0x4E4F534A) + text
    if binary:
        out += struct.pack("<II", len(binary), 0x004E4942) + binary
    return out


def strip(doc: dict, binary: bytes) -> tuple[dict, bytes, int]:
    textures = doc.get("textures", [])
    images = doc.get("images", [])
    normal_textures = set()
    for material in doc.get("materials", []):
        ref = material.pop("normalTexture", None)
        if ref is not None:
            normal_textures.add(ref["index"])
    # Textures and images still used by something else stay
    used_textures = set()
    for material in doc.get("materials", []):
        pbr = material.get("pbrMetallicRoughness", {})
        for key in MATERIAL_TEXTURES:
            if key in pbr:
                used_textures.add(pbr[key]["index"])
        for key in OTHER_TEXTURES:
            if key in material:
                used_textures.add(material[key]["index"])
    keep_textures = [i for i in range(len(textures)) if i in used_textures]
    used_images = {textures[i]["source"] for i in keep_textures if "source" in textures[i]}
    keep_images = [i for i in range(len(images)) if i in used_images]
    texture_map = {old: new for new, old in enumerate(keep_textures)}
    image_map = {old: new for new, old in enumerate(keep_images)}
    # Buffer views: drop those only the dropped images used
    dropped_views = {images[i]["bufferView"] for i in range(len(images)) if i not in used_images and "bufferView" in images[i]}
    views = doc.get("bufferViews", [])
    keep_views = [i for i in range(len(views)) if i not in dropped_views]
    view_map = {old: new for new, old in enumerate(keep_views)}
    # Repack the binary chunk (views into buffer 0 only; Tripo writes one buffer)
    packed = bytearray()
    new_views = []
    for old in keep_views:
        view = dict(views[old])
        assert view.get("buffer", 0) == 0, "multi-buffer GLB"
        start = view.get("byteOffset", 0)
        chunk = binary[start : start + view["byteLength"]]
        packed += b"\0" * (-len(packed) % 4)
        view["byteOffset"] = len(packed)
        packed += chunk
        new_views.append(view)
    doc["bufferViews"] = new_views
    if doc.get("buffers"):
        doc["buffers"][0]["byteLength"] = len(packed)
    for accessor in doc.get("accessors", []):
        if "bufferView" in accessor:
            accessor["bufferView"] = view_map[accessor["bufferView"]]
    new_images = []
    for old in keep_images:
        image = dict(images[old])
        if "bufferView" in image:
            image["bufferView"] = view_map[image["bufferView"]]
        new_images.append(image)
    doc["images"] = new_images
    new_textures = []
    for old in keep_textures:
        texture = dict(textures[old])
        if "source" in texture:
            texture["source"] = image_map[texture["source"]]
        new_textures.append(texture)
    doc["textures"] = new_textures
    for material in doc.get("materials", []):
        pbr = material.get("pbrMetallicRoughness", {})
        for key in MATERIAL_TEXTURES:
            if key in pbr:
                pbr[key]["index"] = texture_map[pbr[key]["index"]]
        for key in OTHER_TEXTURES:
            if key in material:
                material[key]["index"] = texture_map[material[key]["index"]]
    return doc, bytes(packed), len(images) - len(new_images)


def check(doc: dict) -> list[str]:
    problems = []
    for material in doc.get("materials", []):
        if "normalTexture" in material:
            problems.append("a material still has a normalTexture")
    for image in doc.get("images", []):
        if "normal" in str(image.get("name", "")).lower():
            problems.append(f"image {image.get('name')} is named as a normal map")
    return problems


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("glbs", nargs="+")
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    bad = 0
    for path in map(pathlib.Path, args.glbs):
        doc, binary = read_glb(path.read_bytes())
        doc, binary, dropped = strip(doc, binary)
        data = write_glb(doc, binary)
        target = out / path.name
        target.write_bytes(data)
        problems = check(read_glb(data)[0])
        bad += bool(problems)
        print(f"{path.name}: {dropped} image(s) dropped, {len(doc['images'])} kept" + (f"  PROBLEM: {problems}" if problems else ""))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
