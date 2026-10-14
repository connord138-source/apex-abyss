"""Byte-preserving swap of an FBX's embedded base-color image: the Content of the Video
that feeds the Texture connected to a Material's DiffuseColor gets new bytes; every other
record is copied raw (fbx_strip_normals.parse_records/serialize, footer as Blender writes it).

    python3.11 -I -B fbx_swap_color.py in.fbx new_image.jpg out.fbx
"""
import pathlib, struct, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import fbx_strip_normals as F


def swap(data: bytes, image: bytes) -> tuple[bytes, str]:
    version = struct.unpack_from("<I", data, 23)[0]
    top, after, sentinel = F.parse_records(data, 27, len(data))
    footer = data[after:]
    objects = next(r for r in top if r.name == b"Objects")
    conns = next(r for r in top if r.name == b"Connections")
    uid = {F.decode_props(r.props_raw, r.nprops)[0][1]: r for r in objects.children}
    C = [F.decode_props(c.props_raw, c.nprops) for c in conns.children]
    diffuse_tex = {p[1][1] for p in C if p[0][1] == b"OP" and len(p) > 3 and p[3][1] == b"DiffuseColor" and uid.get(p[1][1]) is not None and uid[p[1][1]].name == b"Texture"}
    videos = {p[1][1] for p in C if p[2][1] in diffuse_tex and uid.get(p[1][1]) is not None and uid[p[1][1]].name == b"Video"}
    assert len(videos) == 1, f"expected one base-color video, found {len(videos)}"
    # The video must feed nothing but the base color
    feeds = {p[2][1] for p in C if p[1][1] in videos}
    assert feeds <= diffuse_tex, "base-color video also feeds another texture"
    video = uid[videos.pop()]
    content = next(c for c in video.children if c.name == b"Content")
    assert content.nprops == 1 and content.props_raw[:1] == b"R"
    content.props_raw = b"R" + struct.pack("<I", len(image)) + image
    body = F.serialize(top, 27, True)
    out = bytearray(data[:27]) + body + footer[:16] + b"\0" * 4
    pad = ((len(out) + 15) & ~15) - len(out) or 16
    out += b"\0" * pad + struct.pack("<I", version) + b"\0" * 120 + F.FOOT_MAGIC
    return bytes(out), F.obj_name(video)


if __name__ == "__main__":
    src, img, dst = sys.argv[1:4]
    data = pathlib.Path(src).read_bytes()
    new, name = swap(data, pathlib.Path(img).read_bytes())
    pathlib.Path(dst).parent.mkdir(parents=True, exist_ok=True)
    pathlib.Path(dst).write_bytes(new)
    print(f"{src} -> {dst}: Video {name!r} content swapped, {len(data)} -> {len(new)} bytes")
