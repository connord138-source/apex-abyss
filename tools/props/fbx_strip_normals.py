"""Byte-preserving removal of normal maps from binary FBX (7.x, 32-bit offsets).

Every record is kept byte for byte (its property bytes are copied raw, never decoded and
re-encoded); only the records that make up a normal map are left out, the Definitions
counts are lowered to match, and end offsets and the footer padding are recomputed.
A normal map is a Texture connected to a Material through the 'NormalMap' (or 'Bump')
property, the Video(s) only those textures use, and their connections. Also dropped:
any Video/Texture named like a normal map ('normal' in its name) that nothing else uses.

    python3.11 -I fbx_strip_normals.py --out <dir> a.fbx b.fbx ...
    python3.11 -I fbx_strip_normals.py --noop --out <dir> a.fbx   (rewrite nothing: must be identical)
"""
import argparse, pathlib, struct, sys, zlib

HEAD = b"Kaydara FBX Binary  \x00\x1a\x00"
FOOT_MAGIC = b"\xf8\x5a\x8c\x6a\xde\xf5\xd9\x7e\xec\xe9\x0c\xe3\x75\x8f\x29\x0b"
NORMAL_PROPS = {b"NormalMap", b"Bump"}


class Rec:
    __slots__ = ("name", "nprops", "props_raw", "children", "sentinel")

    def __init__(self, name, nprops, props_raw, children, sentinel):
        self.name, self.nprops, self.props_raw, self.children, self.sentinel = name, nprops, props_raw, children, sentinel


def parse_records(data, off, end):
    """Records from off until a null record (returns them, offset after it, sentinel seen) or end."""
    out = []
    while off < end:
        end_off, nprops, plen = struct.unpack_from("<3I", data, off)
        if end_off == 0:
            assert data[off:off + 13] == b"\0" * 13
            return out, off + 13, True
        nlen = data[off + 12]
        name = data[off + 13: off + 13 + nlen]
        pstart = off + 13 + nlen
        props_raw = data[pstart: pstart + plen]
        children, after, sentinel = parse_records(data, pstart + plen, end_off) if pstart + plen < end_off else ([], end_off, False)
        assert after == end_off, (name, after, end_off)
        out.append(Rec(name, nprops, props_raw, children, sentinel))
        off = end_off
    return out, off, False


def decode_props(raw, n):
    """Decode the properties (for reading uids, names, counts); returns [(type, value, start, end)]."""
    out, o = [], 0
    for _ in range(n):
        t = raw[o:o + 1]; o += 1; s = o
        if t == b"Y": v = struct.unpack_from("<h", raw, o)[0]; o += 2
        elif t == b"C": v = raw[o]; o += 1
        elif t == b"I": v = struct.unpack_from("<i", raw, o)[0]; o += 4
        elif t == b"F": v = struct.unpack_from("<f", raw, o)[0]; o += 4
        elif t == b"D": v = struct.unpack_from("<d", raw, o)[0]; o += 8
        elif t == b"L": v = struct.unpack_from("<q", raw, o)[0]; o += 8
        elif t in (b"S", b"R"):
            ln = struct.unpack_from("<I", raw, o)[0]; v = raw[o + 4:o + 4 + ln]; o += 4 + ln
        elif t in (b"f", b"d", b"l", b"i", b"b"):
            alen, enc, clen = struct.unpack_from("<3I", raw, o); v = None; o += 12 + clen
        else:
            raise ValueError(f"unknown property type {t!r}")
        out.append((t, v, s, o))
    assert o == len(raw), "property bytes left over"
    return out


def serialize(recs, base, sentinel_after):
    """Bytes for a record list starting at file offset `base`."""
    buf = bytearray()
    for r in recs:
        start = base + len(buf)
        inner = r.name and (len(r.name).to_bytes(1, "little") + r.name + r.props_raw)
        body_start = start + 12 + len(inner)
        kids = serialize(r.children, body_start, r.sentinel) if (r.children or r.sentinel) else b""
        end_off = body_start + len(kids)
        buf += struct.pack("<3I", end_off, r.nprops, len(r.props_raw)) + inner + kids
    if sentinel_after:
        buf += b"\0" * 13
    return bytes(buf)


def obj_name(r):
    p = decode_props(r.props_raw, r.nprops)
    return p[1][1].split(b"\x00\x01")[0].decode(errors="replace") if len(p) > 1 else "?"


def strip(top, log):
    objects = next(r for r in top if r.name == b"Objects")
    conns = next(r for r in top if r.name == b"Connections")
    defs = next((r for r in top if r.name == b"Definitions"), None)
    uid = {}
    for r in objects.children:
        p = decode_props(r.props_raw, r.nprops)
        uid[p[0][1]] = r
    C = []  # (rec, kind, src, dst, prop)
    for c in conns.children:
        p = decode_props(c.props_raw, c.nprops)
        C.append((c, p[0][1], p[1][1], p[2][1], p[3][1] if len(p) > 3 else b""))
    drop_tex = {src for _, k, src, dst, prop in C if k == b"OP" and prop in NORMAL_PROPS and src in uid and uid[src].name == b"Texture"}
    for u, r in uid.items():
        if r.name == b"Texture" and "normal" in obj_name(r).lower():
            drop_tex.add(u)
    # Videos feeding only dropped textures
    feeds = {}
    for _, k, src, dst, prop in C:
        if src in uid and uid[src].name == b"Video":
            feeds.setdefault(src, set()).add(dst)
    drop_vid = {v for v, dsts in feeds.items() if dsts and dsts <= drop_tex}
    for u, r in uid.items():
        if r.name == b"Video" and "normal" in obj_name(r).lower() and not (feeds.get(u, set()) - drop_tex):
            drop_vid.add(u)
    drop = drop_tex | drop_vid
    for u in sorted(drop):
        log.append(f"drop {uid[u].name.decode()} {obj_name(uid[u])!r}")
    objects.children = [r for r in objects.children if decode_props(r.props_raw, r.nprops)[0][1] not in drop]
    kept = []
    for c, k, src, dst, prop in C:
        if src in drop or dst in drop:
            log.append(f"drop connection {k.decode()} {uid[src].name.decode() if src in uid else src}->{uid[dst].name.decode() if dst in uid else dst} {prop.decode()!r}")
        else:
            kept.append(c)
    conns.children = kept
    # Definitions: lower the per-type counts and the total
    removed = {}
    for u in drop:
        removed[uid[u].name] = removed.get(uid[u].name, 0) + 1
    if defs is not None and drop:
        total = sum(removed.values())
        for d in defs.children:
            if d.name == b"Count":
                set_int(d, -total)
            elif d.name == b"ObjectType":
                t = decode_props(d.props_raw, d.nprops)[0][1]
                if t in removed:
                    cnt = next(x for x in d.children if x.name == b"Count")
                    set_int(cnt, -removed[t])
        log.append(f"definitions: -{total} " + ", ".join(f"{k.decode()} -{v}" for k, v in removed.items()))
    return len(drop_tex), len(drop_vid)


def set_int(rec, delta):
    p = decode_props(rec.props_raw, rec.nprops)
    assert len(p) == 1 and p[0][0] == b"I"
    rec.props_raw = b"I" + struct.pack("<i", p[0][1] + delta)


def rewrite(data, noop, log):
    assert data[:23] == HEAD
    version = struct.unpack_from("<I", data, 23)[0]
    assert version < 7500, "64-bit offset FBX not handled"
    top, after, sentinel = parse_records(data, 27, len(data))
    assert sentinel
    footer = data[after:]
    # Footer as Blender writes it: 16-byte id, 4 zero bytes, pad to 16 (16 if aligned), version, 120 zeros, magic
    foot_id = footer[:16]
    assert footer[16:20] == b"\0" * 4
    assert footer.endswith(struct.pack("<I", version) + b"\0" * 120 + FOOT_MAGIC), "unexpected footer"
    counts = (0, 0) if noop else strip(top, log)
    body = serialize(top, 27, True)
    out = bytearray(data[:27]) + body + foot_id + b"\0" * 4
    pad = ((len(out) + 15) & ~15) - len(out) or 16
    out += b"\0" * pad + struct.pack("<I", version) + b"\0" * 120 + FOOT_MAGIC
    return bytes(out), counts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("fbx", nargs="+")
    ap.add_argument("--out", required=True)
    ap.add_argument("--noop", action="store_true")
    a = ap.parse_args()
    bad = 0
    for p in map(pathlib.Path, a.fbx):
        data = p.read_bytes()
        log = []
        new, (nt, nv) = rewrite(data, a.noop, log)
        dst = pathlib.Path(a.out) / p.parent.name / p.name
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(new)
        same = new == data
        if a.noop and not same:
            bad += 1
        print(f"{p.parent.name}/{p.name}: {'identical' if same else f'{len(data)} -> {len(new)} bytes'}; dropped {nt} texture(s), {nv} video(s)")
        for line in log:
            print("   ", line)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
