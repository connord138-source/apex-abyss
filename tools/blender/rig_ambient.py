"""Rigs the ambient sea life's Tripo GLBs (the turtle, the manta, the stingray, the
humpback and the crab) for AmbientLifeController, and exports FBX.

    python3.11 tools/blender/rig_ambient.py <in.glb> <out.fbx> [--plan Name] [--weights out.png]

The plan (PLANS, by the file's stem unless --plan names it) gives the kind and the turn
about the vertical that puts the head at -Y (Tripo set each model down axis-aligned but
facing its own way; tools/preview/run_ambient.sh renders the rigged result posed). Like
rig_fish.py, the head ends at Blender -Y and the FBX export turns that into -Z in
Roblox, Y up: a rigged Model faces -Z and the game never turns it.

None of these swim with a spine wave, so each kind has its own skeleton (the bone
names are what src/shared/AmbientRigs.luau poses, by name):

    manta     Root > Body > WingL1 > WingL2 > WingL3 (and R): a chain from the body's
              edge to each tip, so a flap travels outward; HornL/HornR (the cephalic
              fins); Tail1 > Tail2
    stingray  Root > Body > three short chains a side along the disc's margin, front,
              middle and back (FinLF1 > FinLF2, FinLM1 > FinLM2, FinLB1 > FinLB2, and R),
              so a ripple runs head to tail along each edge; Tail1 > Tail2 > Tail3
    turtle    Root > Shell (rigid) > Neck > Head; FinL1 > FinL2 > FinL3 and R (the
              front flippers), HindL1 > HindL2 and R, Tail
    whale     Root > Body > Spine1 > Spine2 > Spine3 > Flukes (a vertical stroke);
              PecL1 > PecL2 and R (the long pectorals)
    crab      Root > Body > ClawL1 > ClawL2 and R; LegL1 .. LegL3 and R (the model has
              three walking legs a side); EyeL, EyeR (the eye stalks)

Weights are set from the body's own shape (how far out along a wing, flipper or leg a
vertex sits, with a soft hand-over at each joint), then smoothed along the surface (the
same smoothing on every vertex at one place, so UV seams never tear). A vertex on the
left is never weighted to a bone on the right, nor the other way, and at most four bones
weight any vertex (Roblox's limit). The turtle's shell is rigid: nothing under it bends.

`--weights out.png` renders each bone's share in its own colour from above and below,
to check the split before exporting.
"""

from __future__ import annotations

import math
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
IN_PATH, OUT_PATH = argv[0], argv[1]


def option(name: str, default=None):
    return argv[argv.index(name) + 1] if name in argv else default


# Each model: its kind and the turn (degrees about the vertical) that puts its head at -Y.
# `tail`: straighten the tail level and centred before rigging (the stingray's sheet
# drew it rising, Tripo kept the rise).
PLANS = {
    "Turtle": {"kind": "turtle", "yaw": -90},
    "Manta": {"kind": "manta", "yaw": -90},
    "Stingray": {"kind": "stingray", "yaw": -90, "tail": True},
    "Humpback": {"kind": "whale", "yaw": 0},
    "Crab": {"kind": "crab", "yaw": -90},
}
stem = IN_PATH.replace("\\", "/").rsplit("/", 1)[-1].rsplit(".", 1)[0]
PLAN = PLANS[option("--plan", stem)]
KIND = PLAN["kind"]
WEIGHTS_PNG = option("--weights")


def log(*args):
    print("[rig_ambient]", *args)


# ---------- the body, squared up: head at -Y, up +Z, centred ----------
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=IN_PATH)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
if not meshes:
    sys.exit("no mesh in " + IN_PATH)
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = "Body"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.data.objects):
    if o.type == "EMPTY":
        bpy.data.objects.remove(o)
body.matrix_world = Matrix.Rotation(math.radians(PLAN["yaw"]), 4, "Z")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def coords() -> np.ndarray:
    return np.array([v.co[:] for v in body.data.vertices])


co = coords()
middle = (co.max(0) + co.min(0)) / 2
body.matrix_world = Matrix.Translation(Vector((-middle).tolist()))
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
co = coords()
lo, hi = co.min(0), co.max(0)
EXTENT = hi - lo
log(stem, KIND, "extent", EXTENT.round(3))


def smoothstep(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def straighten_tail(tail_from: float):
    """Level and centre the tail behind `tail_from` (y): each stretch of it is moved by
    its own centre line's offset from the tail's root, eased in over the first 8%."""
    global co
    ys = co[:, 1]
    behind = ys > tail_from
    edges = np.linspace(tail_from, hi[1], 24)
    mids, cz, cx = [], [], []
    for a, b in zip(edges[:-1], edges[1:]):
        band = co[(ys >= a) & (ys <= b)]
        if len(band):
            mids.append((a + b) / 2)
            cz.append(np.median(band[:, 2]))
            cx.append(np.median(band[:, 0]))
    mids, cz, cx = np.array(mids), np.array(cz), np.array(cx)
    z0, x0 = cz[0], 0.0
    dz = np.interp(ys, mids, cz) - z0
    dx = np.interp(ys, mids, cx) - x0
    ramp = smoothstep((ys - tail_from) / (0.08 * EXTENT[1])) * behind
    mesh = body.data
    for i in np.nonzero(behind)[0]:
        v = mesh.vertices[i].co
        v.z -= dz[i] * ramp[i]
        v.x -= dx[i] * ramp[i]
    mesh.update()
    co = coords()
    log("tail straightened behind y", round(tail_from, 3), "rise taken out", round(float(cz.max() - cz.min()), 3))


# ---------- helpers ----------
def chain_weights(s: np.ndarray, pivots: list[float], h: float) -> np.ndarray:
    """A partition of unity along a chain: column 0 is the parent (before the first
    pivot), column k the bone starting at pivots[k-1]; each pivot hands over over +-h."""
    n = len(pivots)
    starts = [smoothstep((s - p + h) / (2 * h)) for p in pivots]
    out = np.zeros((len(s), n + 1))
    out[:, 0] = 1 - starts[0]
    for k in range(n):
        out[:, k + 1] = starts[k] - (starts[k + 1] if k + 1 < n else 0)
    return np.clip(out, 0, 1)


def band_centre(mask: np.ndarray, fallback) -> np.ndarray:
    pts = co[mask]
    return np.median(pts, 0) if len(pts) else np.array(fallback, float)


class Rig:
    def __init__(self):
        self.bones: list[dict] = []
        self.index: dict[str, int] = {}
        self.weights: list[np.ndarray] = []
        self.side: list[int] = []  # +1 left (+X), -1 right, 0 middle

    def bone(self, name, parent, head, tail, side=0):
        self.index[name] = len(self.bones)
        self.bones.append({"name": name, "parent": parent, "head": np.array(head, float), "tail": np.array(tail, float)})
        self.weights.append(np.zeros(len(co)))
        self.side.append(side)

    def add(self, name, w):
        self.weights[self.index[name]] += w


def half_width(ys_edges, mask=None):
    """Each y band's half width (largest |x|) and its centre line's height."""
    hw, zc = [], []
    for a, b in zip(ys_edges[:-1], ys_edges[1:]):
        sel = (co[:, 1] >= a) & (co[:, 1] < b)
        if mask is not None:
            sel &= mask
        band = co[sel]
        hw.append(np.abs(band[:, 0]).max() if len(band) else 0.0)
        mid = band[np.abs(band[:, 0]) < 0.06 * EXTENT[0]] if len(band) else band
        zc.append(float(np.median(mid[:, 2])) if len(mid) else 0.0)
    return np.array(hw), np.array(zc)


def components(mask: np.ndarray, smallest: int) -> list[np.ndarray]:
    """The connected pieces of the surface where `mask` holds (vertices at one place
    count as one, so a UV seam doesn't split a piece), biggest first."""
    keys = np.round(co / (EXTENT.max() * 1e-4)).astype(np.int64)
    _, node = np.unique(keys, axis=0, return_inverse=True)
    node = node.ravel()
    parent = np.arange(node.max() + 1)

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for e in body.data.edges:
        i, j = e.vertices
        if mask[i] and mask[j]:
            ri, rj = find(node[i]), find(node[j])
            if ri != rj:
                parent[ri] = rj
    comp = np.array([find(node[i]) for i in range(len(co))])
    found = [mask & (comp == c) for c in np.unique(comp[mask])]
    return sorted([f for f in found if f.sum() >= smallest], key=lambda f: -int(f.sum()))


def rig_ray(manta: bool) -> Rig:
    W, L = EXTENT[0], EXTENT[1]
    edges = np.linspace(lo[1], hi[1], 61)
    mids = (edges[:-1] + edges[1:]) / 2
    hw, zc = half_width(edges)
    # The disc's back edge: from the tail end forward, where the body widens past 8% of
    # the span (the tail and its root are thinner)
    wide = np.nonzero(hw > 0.08 * W)[0]
    disc_front, disc_back = lo[1], edges[wide.max() + 1]
    if PLAN.get("tail"):
        straighten_tail(disc_back)
        hw, zc = half_width(edges)
    x, y, z = co[:, 0], co[:, 1], co[:, 2]
    ax = np.abs(x)
    side = np.sign(x)
    rig = Rig()
    centre_z = float(np.interp(0.0, mids, zc))
    rig.bone("Body", "Root", (0, (disc_front + disc_back) / 2, centre_z), (0, disc_back, centre_z))
    # Tail: a chain down the tail's centre line from the disc's back edge
    tail_len = hi[1] - disc_back
    n_tail = 2 if manta else 3
    tail_at = [disc_back + tail_len * k / n_tail - (0.02 * L if k == 0 else 0) for k in range(n_tail)]
    for k, at in enumerate(tail_at):
        nxt = tail_at[k + 1] if k + 1 < n_tail else hi[1]
        zz = float(np.interp(at, mids, zc))
        rig.bone(f"Tail{k + 1}", "Body" if k == 0 else f"Tail{k}", (0, at, zz), (0, nxt, float(np.interp(nxt, mids, zc))))
    tail_s = (y - disc_back + 0.02 * L) / tail_len
    tail_w = chain_weights(tail_s * n_tail, list(range(n_tail)), 0.2)
    # (the tail's own vertices only: narrow and behind the disc)
    on_tail = (ax < 0.06 * W) & (y > disc_back - 0.06 * L)
    body_w = np.where(on_tail, tail_w[:, 0], 1.0)
    for k in range(n_tail):
        rig.add(f"Tail{k + 1}", np.where(on_tail, tail_w[:, k + 1], 0.0))
    if manta:
        # Wings: |x| from the body's edge (12% of the span out) to the tip, three bones
        e0 = 0.10 * W
        tip = W / 2
        s = (ax - e0) / (tip - e0)
        pivots = [0.0, 0.34, 0.68]
        cw = chain_weights(s, pivots, 0.09)
        # The cephalic fins: ahead of the wings' leading edge, beside the mouth
        horn_y = lo[1] + 0.15 * L
        horn = (y < horn_y) & (ax > 0.035 * W)
        hand = smoothstep((horn_y - y) / (0.05 * L))
        for sgn, tag in ((1, "L"), (-1, "R")):
            mine = side == sgn
            for k, p in enumerate(pivots):
                px = sgn * (e0 + p * (tip - e0))
                near = mine & (np.abs(ax - abs(px)) < 0.04 * W) & ~horn
                c = band_centre(near, (px, 0, centre_z))
                nxt = e0 + (pivots[k + 1] if k + 1 < len(pivots) else 1.0) * (tip - e0)
                cn = band_centre(mine & (np.abs(ax - nxt) < 0.04 * W), (sgn * nxt, c[1], c[2]))
                rig.bone(f"Wing{tag}{k + 1}", "Body" if k == 0 else f"Wing{tag}{k}", (px, c[1], c[2]), (sgn * nxt, cn[1], cn[2]), sgn)
                rig.add(f"Wing{tag}{k + 1}", np.where(mine & ~on_tail, cw[:, k + 1], 0.0) * (1 - hand * horn))
            hc = band_centre(mine & horn, (sgn * 0.07 * W, horn_y, centre_z))
            rig.bone(f"Horn{tag}", "Body", (hc[0] * 0.8, horn_y, hc[2]), (hc[0], lo[1], hc[2]), sgn)
            rig.add(f"Horn{tag}", np.where(mine & horn, hand, 0.0))
        wing_total = sum(rig.weights[rig.index[f"Wing{t}{k}"]] for t in "LR" for k in (1, 2, 3))
        horn_total = rig.weights[rig.index["HornL"]] + rig.weights[rig.index["HornR"]]
        rig.add("Body", np.clip(body_w - wing_total - horn_total, 0, 1))
    else:
        # The disc's margin: two bones out from the body's edge, at three stations along
        # it; a vertex's place along the chain is measured against the disc's own half
        # width where it sits, so the round ends ripple too
        e0 = 0.16 * (W / 2)
        local_hw = np.interp(y, mids, hw)
        s = (ax - e0) / np.maximum(local_hw - e0, 1e-4)
        cw = chain_weights(s, [0.0, 0.5], 0.14)
        span = disc_back - disc_front
        stations = [disc_front + span * f for f in (0.22, 0.5, 0.78)]
        lam = np.stack(
            [
                np.clip(1 - np.abs(y - st) / (stations[1] - stations[0]), 0, 1)
                for st in stations
            ],
            1,
        )
        lam[y < stations[0], 0] = 1
        lam[y > stations[2], 2] = 1
        lam /= lam.sum(1, keepdims=True)
        for sgn, tag in ((1, "L"), (-1, "R")):
            mine = (side == sgn) & ~on_tail
            for j, (st, sname) in enumerate(zip(stations, "FMB")):
                shw = float(np.interp(st, mids, hw))
                for k, p in enumerate((0.0, 0.5)):
                    px = e0 + p * (shw - e0)
                    nxt = e0 + (0.5 if k == 0 else 1.0) * (shw - e0)
                    c = band_centre((side == sgn) & (np.abs(ax - px) < 0.05 * W) & (np.abs(y - st) < 0.05 * L), (sgn * px, st, centre_z))
                    name = f"Fin{tag}{sname}{k + 1}"
                    parent = "Body" if k == 0 else f"Fin{tag}{sname}1"
                    rig.bone(name, parent, (sgn * px, st, c[2]), (sgn * nxt, st, c[2]), sgn)
                    rig.add(name, np.where(mine, lam[:, j] * cw[:, k + 1], 0.0))
        fin_total = sum(rig.weights[i] for i, b in enumerate(rig.bones) if b["name"].startswith("Fin"))
        rig.add("Body", np.clip(body_w - fin_total, 0, 1))
    log("disc", round(disc_front, 3), "..", round(disc_back, 3), "tail to", round(hi[1], 3))
    return rig


def rig_turtle() -> Rig:
    x, y, z = co[:, 0], co[:, 1], co[:, 2]
    ax = np.abs(x)
    side = np.sign(x)
    H = EXTENT[2]
    # The shell: the upper part of the body (the dome), less the head in front
    high = z > lo[2] + 0.42 * H
    edges = np.linspace(lo[1], hi[1], 41)
    hw_high, _ = half_width(edges, high)
    wide = np.nonzero(hw_high > 0.5 * hw_high.max())[0]
    shell_front, shell_back = edges[wide.min()], edges[wide.max() + 1]
    a = hw_high.max() * 1.06
    b = (shell_back - shell_front) / 2 * 1.04
    yc = (shell_front + shell_back) / 2
    zc = float(np.median(z[high]))
    rho = np.sqrt((x / a) ** 2 + ((y - yc) / b) ** 2)  # 1 on the shell's rim
    outside = rho - 1
    rig = Rig()
    rig.bone("Shell", "Root", (0, yc, zc - 0.15 * H), (0, shell_back, zc - 0.15 * H))
    # Head and neck: narrow, in front of the shell
    neck_hw = 0.16 * a
    head_zone = (y < yc) & (ax < neck_hw * 1.8) & (y < shell_front + 0.08 * b)
    neck_y = shell_front + 0.06 * b
    head_len = neck_y - lo[1]
    nz = band_centre(head_zone & (np.abs(y - neck_y) < 0.04 * b), (0, neck_y, zc - 0.2 * H))
    rig.bone("Neck", "Shell", (0, neck_y, nz[2]), (0, neck_y - 0.4 * head_len, nz[2]))
    hy = neck_y - 0.42 * head_len
    hz = band_centre(head_zone & (np.abs(y - hy) < 0.04 * b), (0, hy, nz[2]))
    rig.bone("Head", "Neck", (0, hy, hz[2]), (0, lo[1], hz[2]))
    hs = (neck_y - y) / head_len
    hcw = chain_weights(hs, [0.0, 0.42], 0.07)
    rig.add("Neck", np.where(head_zone, hcw[:, 1], 0.0))
    rig.add("Head", np.where(head_zone, hcw[:, 2], 0.0))
    # Limbs: the pieces of the surface outside the shell's outline (each flipper its
    # own piece), named by where they sit
    tail_zone = (y > shell_back - 0.1 * b) & (ax < 0.18 * a) & ~head_zone
    tz = band_centre(tail_zone & (y > shell_back - 0.02 * b), (0, shell_back, zc - 0.3 * H))
    rig.bone("Tail", "Shell", (0, shell_back - 0.05 * b, tz[2]), (0, hi[1], tz[2]))
    rig.add("Tail", np.where(tail_zone, smoothstep((y - shell_back + 0.1 * b) / (0.12 * b)), 0.0))
    slots: dict[str, np.ndarray] = {}
    for piece in components((outside > 0.03) & ~head_zone & ~tail_zone, 40):
        centre = co[piece].mean(0)
        key = ("Fin" if centre[1] < yc else "Hind") + ("L" if centre[0] > 0 else "R")
        slots[key] = slots[key] | piece if key in slots else piece
    log("turtle limbs", {k: int(v.sum()) for k, v in slots.items()})
    for sgn, tag in ((1, "L"), (-1, "R")):
        for kind_, pivots in (("Fin", [0.0, 0.36, 0.68]), ("Hind", [0.0, 0.5])):
            piece = slots.get(kind_ + tag)
            if piece is None:
                continue
            names = [f"{kind_}{tag}{k + 1}" for k in range(len(pivots))]
            pts = co[piece]
            # Its tip sits furthest out from the shell; its root is where the rim meets
            # it, the near-rim points nearest the tip (the shell's own outline bulges past
            # the fitted oval in places, and those bits mustn't count as the root)
            far = pts[np.argmax(outside[piece])]
            rimmed = pts[outside[piece] < 0.1]
            nearest = rimmed[np.argsort(np.linalg.norm(rimmed[:, :2] - far[:2], axis=1))[:24]]
            root = nearest.mean(0)
            axis = far[:2] - root[:2]
            length = float(np.linalg.norm(axis))
            axis /= length
            along = ((co[:, :2] - root[:2]) @ axis) / length
            piece = piece & (along > -0.12)
            log(kind_ + tag, "root", root.round(3), "tip", far.round(3), "share past half", round(float((along[piece] > 0.5).mean()), 2))
            # The piece, and the skin just inside the rim round its root
            zone = piece | ((np.linalg.norm(co[:, :2] - root[:2], axis=1) < 0.35 * length) & (outside > -0.12) & (side == sgn) & ~head_zone & ~tail_zone)
            cw = chain_weights(along, pivots, 0.06)
            rim = smoothstep((outside + 0.08) / 0.16)
            for k, name in enumerate(names):
                p = root[:2] + axis * pivots[k] * length
                pn = root[:2] + axis * (pivots[k + 1] if k + 1 < len(pivots) else 1.0) * length
                near = piece & (np.abs(along - pivots[k]) < 0.06)
                pz = float(np.median(co[near, 2])) if near.any() else root[2]
                rig.bone(name, "Shell" if k == 0 else names[k - 1], (p[0], p[1], pz), (pn[0], pn[1], pz), sgn)
                w = cw[:, k + 1] + (cw[:, 0] if k == 0 else 0)  # (before the root: the first bone, eased by `rim`)
                rig.add(name, np.where(zone, w * rim, 0.0))
    taken = sum(rig.weights[i] for i, b_ in enumerate(rig.bones) if b_["name"] != "Shell")
    rig.add("Shell", np.clip(1 - taken, 0, 1))
    log("shell", "a", round(a, 3), "b", round(b, 3), "yc", round(yc, 3), "front", round(shell_front, 3), "back", round(shell_back, 3))
    return rig


def rig_whale() -> Rig:
    x, y, z = co[:, 0], co[:, 1], co[:, 2]
    ax = np.abs(x)
    side = np.sign(x)
    L, H = EXTENT[1], EXTENT[2]
    s = (y - lo[1]) / L
    edges = np.linspace(lo[1], hi[1], 41)
    mids = (edges[:-1] + edges[1:]) / 2
    # The body's half width from its upper half (the pectorals hang low on its sides)
    upper = z > lo[2] + 0.45 * H
    hw_up, zc = half_width(edges, upper)
    _, zmid = half_width(edges)
    body_hw = np.interp(y, mids, hw_up)
    pec = (ax > body_hw * 1.12 + 0.01) & (s > 0.2) & (s < 0.72) & (z < np.interp(y, mids, zmid) + 0.05 * H)
    rig = Rig()
    stations = [0.0, 0.46, 0.6, 0.72, 0.84]
    names = ["Body", "Spine1", "Spine2", "Spine3", "Flukes"]
    for k, (st, name) in enumerate(zip(stations, names)):
        at = lo[1] + (0.32 if k == 0 else st) * L
        nxt = lo[1] + (stations[k + 1] if k + 1 < len(stations) else 1.0) * L
        zz = float(np.interp(at, mids, zmid))
        rig.bone(name, "Root" if k == 0 else names[k - 1], (0, at, zz), (0, nxt, float(np.interp(nxt, mids, zmid))))
    cw = chain_weights(s, stations[1:], 0.05)
    for k, name in enumerate(names):
        rig.add(name, np.where(pec, 0.0, cw[:, k]))
    for sgn, tag in ((1, "L"), (-1, "R")):
        zone = pec & (side == sgn)
        pts = co[zone]
        root = pts[np.argmin(np.abs(pts[:, 0]))]
        far = pts[np.argmax(np.abs(pts[:, 0]))]
        axis = far[:2] - root[:2]
        length = float(np.linalg.norm(axis))
        axis /= length
        along = ((co[:, :2] - root[:2]) @ axis) / length
        pw = chain_weights(along, [0.0, 0.5], 0.08)
        for k, piv in enumerate((0.0, 0.5)):
            p = root[:2] + axis * piv * length
            pn = root[:2] + axis * (0.5 if k == 0 else 1.0) * length
            rig.bone(f"Pec{tag}{k + 1}", "Body" if k == 0 else f"Pec{tag}1", (p[0], p[1], root[2]), (pn[0], pn[1], root[2]), sgn)
            rig.add(f"Pec{tag}{k + 1}", np.where(zone, pw[:, k + 1] + (pw[:, 0] if k == 0 else 0), 0.0))
    log("pectoral vertices", int(pec.sum()))
    return rig


def rig_crab() -> Rig:
    x, y, z = co[:, 0], co[:, 1], co[:, 2]
    ax = np.abs(x)
    side = np.sign(x)
    H = EXTENT[2]
    top = z > lo[2] + 0.72 * H
    a = np.abs(x[top]).max() * 1.02
    yf, yb = y[top].min(), y[top].max()
    b = (yb - yf) / 2 * 1.04
    yc = (yf + yb) / 2
    rho = np.sqrt((x / a) ** 2 + ((y - yc) / b) ** 2)
    outside = rho - 1
    rig = Rig()
    zc = float(np.median(z[top])) - 0.25 * H
    rig.bone("Body", "Root", (0, yc, zc), (0, yb, zc))
    # The limbs: connected pieces of the surface outside the carapace's outline, each
    # named by where it leaves the body (its root's angle round the middle)
    pieces = []
    for members in components(outside > 0.0, 80):
        root = co[members][np.argmin(outside[members])]
        tipi = co[members][np.argmax(outside[members])]
        pieces.append({"members": members, "root": root, "tip": tipi, "count": int(members.sum())})
    # The two biggest pieces whose roots are ahead of the middle are the claws
    ahead = sorted([p for p in pieces if p["root"][1] < yc], key=lambda p: -p["count"])
    claws = {}
    for p in ahead[:4]:
        tag = "L" if p["root"][0] > 0 else "R"
        if tag not in claws:
            claws[tag] = p
    legs = {"L": [], "R": []}
    for p in pieces:
        if any(p is c for c in claws.values()):
            continue
        tag = "L" if p["root"][0] > 0 else "R"
        legs[tag].append(p)
    for tag, sgn in (("L", 1), ("R", -1)):
        claw = claws.get(tag)
        if claw:
            root, tip = claw["root"], claw["tip"]
            axis = tip - root
            length = float(np.linalg.norm(axis))
            along = ((co - root) @ (axis / length)) / length
            cw = chain_weights(along, [0.0, 0.55], 0.06)
            mid = root + axis * 0.55
            rig.bone(f"Claw{tag}1", "Body", root, mid, sgn)
            rig.bone(f"Claw{tag}2", f"Claw{tag}1", mid, tip, sgn)
            rim = smoothstep((outside + 0.06) / 0.12)
            rig.add(f"Claw{tag}1", np.where(claw["members"], (cw[:, 0] + cw[:, 1]) * rim, 0.0))
            rig.add(f"Claw{tag}2", np.where(claw["members"], cw[:, 2] * rim, 0.0))
        # Legs front to back by their roots
        ordered = sorted(legs[tag], key=lambda p: p["root"][1])
        if len(ordered) > 4:
            # (stray bits: keep the four biggest, the rest stay on the body)
            keep = sorted(ordered, key=lambda p: -p["count"])[:4]
            ordered = sorted(keep, key=lambda p: p["root"][1])
        for k, p in enumerate(ordered):
            name = f"Leg{tag}{k + 1}"
            rig.bone(name, "Body", p["root"], p["tip"], sgn)
            rim = smoothstep((outside + 0.06) / 0.12)
            rig.add(name, np.where(p["members"], rim, 0.0))
        log(tag, "claw", bool(claw), "legs", len(ordered), [p["count"] for p in ordered])
        # The eye stalk: the most forward point high up near the middle on this side
        # (the stalks stand just proud of the shell's front edge); everything within a
        # short reach of its tip, ahead of the stalk's root, swivels with it
        W = EXTENT[0]
        limb = np.zeros(len(co), bool)
        for p in pieces:
            limb |= p["members"]
        near_mid = (side == sgn) & (ax > 0.03 * W) & (ax < 0.14 * W) & (z > lo[2] + 0.72 * H) & (y < yc) & ~limb
        if near_mid.any():
            pts = co[near_mid]
            tip = pts[np.argmin(pts[:, 1])]
            root = tip + np.array([0.0, 0.045 * W, -0.05 * W])
            reach = np.linalg.norm(co - tip, axis=1)
            stalk = (side == sgn) & (reach < 0.06 * W) & (y < root[1] + 0.01 * W) & (z > root[2] - 0.01 * W) & ~limb
            if stalk.sum() >= 8:
                rig.bone(f"Eye{tag}", "Body", root, tip, sgn)
                rig.add(f"Eye{tag}", np.where(stalk, smoothstep((root[1] - y) / (0.03 * W) + 0.3), 0.0))
                log(tag, "eye stalk", tip.round(3), "vertices", int(stalk.sum()))
    taken = sum(rig.weights[i] for i, b_ in enumerate(rig.bones) if b_["name"] != "Body")
    rig.add("Body", np.clip(1 - taken, 0, 1))
    return rig


rig = {"manta": lambda: rig_ray(True), "stingray": lambda: rig_ray(False), "turtle": rig_turtle, "whale": rig_whale, "crab": rig_crab}[KIND]()
co = coords()
lo, hi = co.min(0), co.max(0)

# ---------- smoothing along the surface ----------
Wt = np.stack(rig.weights, 1)
Wt = np.clip(Wt, 0, None)
n_bones = Wt.shape[1]
allowed = np.ones_like(Wt, bool)
for k, sgn in enumerate(rig.side):
    if sgn != 0:
        allowed[:, k] = np.sign(co[:, 0]) == sgn
Wt *= allowed
Wt /= np.maximum(Wt.sum(1, keepdims=True), 1e-9)
# One node per place (UV seams split vertices; they move as one)
keys = np.round(co / (EXTENT.max() * 1e-4)).astype(np.int64)
_, node = np.unique(keys, axis=0, return_inverse=True)
node = node.ravel()
n_nodes = node.max() + 1
edges = np.array([e.vertices[:] for e in body.data.edges])
ne = node[edges]
ne = ne[ne[:, 0] != ne[:, 1]]
deg = np.bincount(ne.ravel(), minlength=n_nodes).astype(float)
Wn = np.zeros((n_nodes, n_bones))
np.add.at(Wn, node, Wt)
count = np.bincount(node, minlength=n_nodes).astype(float)
Wn /= np.maximum(count, 1)[:, None]
allowed_n = np.zeros((n_nodes, n_bones), bool)
np.logical_or.at(allowed_n, node, allowed)
rigid = np.zeros(n_bones, bool)
if KIND == "turtle":
    rigid[rig.index["Shell"]] = True
ITER = {"manta": 12, "stingray": 14, "turtle": 8, "whale": 10, "crab": 4}[KIND]
start = Wn.copy()
for _ in range(ITER):
    acc = np.zeros_like(Wn)
    np.add.at(acc, ne[:, 0], Wn[ne[:, 1]])
    np.add.at(acc, ne[:, 1], Wn[ne[:, 0]])
    avg = acc / np.maximum(deg, 1)[:, None]
    Wn = np.where(deg[:, None] > 0, 0.5 * Wn + 0.5 * avg, Wn)
    Wn *= allowed_n
    if rigid.any():
        # Whatever was wholly the shell stays wholly the shell
        hard = start[:, rigid].max(1) > 0.999
        Wn[hard] = start[hard]
    Wn /= np.maximum(Wn.sum(1, keepdims=True), 1e-9)
Wt = Wn[node]
# Roblox's limit: four bones a vertex
order = np.argsort(-Wt, 1)
cut = np.zeros_like(Wt, bool)
np.put_along_axis(cut, order[:, 4:], True, 1)
Wt[cut] = 0
Wt[Wt < 0.01] = 0
Wt /= np.maximum(Wt.sum(1, keepdims=True), 1e-9)
log("bones", n_bones, "max influences", int((Wt > 0).sum(1).max()), "unweighted bones", [b["name"] for k, b in enumerate(rig.bones) if Wt[:, k].max() < 0.05])
crossed = 0
for k, sgn in enumerate(rig.side):
    if sgn != 0:
        crossed += int(((Wt[:, k] > 0) & (np.sign(co[:, 0]) != sgn)).sum())
log("vertices weighted across the middle:", crossed)

# ---------- the armature ----------
L = float(EXTENT.max())
bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
arm = bpy.context.active_object
arm.name = "Armature"
eb = arm.data.edit_bones
for b in list(eb):
    eb.remove(b)
root = eb.new("Root")
root.head = Vector((0, 0, 0))
root.tail = Vector((0, 0, 0.1 * L))
for b in rig.bones:
    made = eb.new(b["name"])
    made.head = Vector(b["head"].tolist())
    tail = b["tail"]
    if np.linalg.norm(tail - b["head"]) < 0.01 * L:
        tail = b["head"] + np.array([0, 0.03 * L, 0])
    made.tail = Vector(tail.tolist())
    made.parent = eb[b["parent"]]
    made.use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")
groups = {b["name"]: body.vertex_groups.new(name=b["name"]) for b in rig.bones}
for k, b in enumerate(rig.bones):
    g = groups[b["name"]]
    nz = np.nonzero(Wt[:, k])[0]
    for i in nz:
        g.add([int(i)], float(Wt[i, k]), "REPLACE")
mod = body.modifiers.new("Armature", "ARMATURE")
mod.object = arm
body.parent = arm

# ---------- the weights, drawn ----------
if WEIGHTS_PNG:
    palette = np.array(
        [
            (0.9, 0.9, 0.9), (0.95, 0.3, 0.2), (0.2, 0.7, 0.3), (0.2, 0.4, 0.95), (0.95, 0.8, 0.1), (0.8, 0.3, 0.9),
            (0.1, 0.85, 0.85), (0.95, 0.55, 0.1), (0.5, 0.25, 0.1), (0.6, 0.9, 0.3), (0.35, 0.35, 0.6), (0.9, 0.5, 0.6),
            (0.1, 0.5, 0.4), (0.7, 0.7, 0.2), (0.4, 0.1, 0.5), (0.2, 0.2, 0.2), (0.6, 0.6, 1.0), (1.0, 0.75, 0.6),
            (0.3, 0.6, 0.1), (0.75, 0.15, 0.4),
        ]
    )
    colours = Wt @ palette[np.arange(n_bones) % len(palette)]
    mesh = body.data
    attr = mesh.color_attributes.new("BoneShare", "FLOAT_COLOR", "POINT")
    for i, c in enumerate(colours):
        attr.data[i].color = (c[0], c[1], c[2], 1.0)
    mat = bpy.data.materials.new("Weights")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    vc = nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "BoneShare"
    emit = nodes.new("ShaderNodeEmission")
    mat.node_tree.links.new(vc.outputs["Color"], emit.inputs["Color"])
    mat.node_tree.links.new(emit.outputs["Emission"], nodes["Material Output"].inputs["Surface"])
    saved = [s.material for s in body.material_slots]
    for s in body.material_slots:
        s.material = mat
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    scene.render.resolution_x, scene.render.resolution_y = 600, 600
    cam_data = bpy.data.cameras.new("C")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = L * 1.1
    cam = bpy.data.objects.new("C", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    paths = []
    for k, (eye, up) in enumerate((((0, 0, 3 * L), (0, 1, 0)), ((0, 0, -3 * L), (0, 1, 0)), ((3 * L, 0, 0), (0, 0, 1)))):
        e = Vector(eye)
        f = (-e).normalized()
        r = f.cross(Vector(up)).normalized()
        u = r.cross(f)
        cam.matrix_world = Matrix.Translation(e) @ Matrix(((r.x, u.x, -f.x), (r.y, u.y, -f.y), (r.z, u.z, -f.z))).to_4x4()
        p = WEIGHTS_PNG.replace(".png", f"_{k}.png")
        scene.render.filepath = p
        bpy.ops.render.render(write_still=True)
        paths.append(p)
    from PIL import Image

    sheet = Image.new("RGB", (1800, 640), (30, 30, 30))
    for k, p in enumerate(paths):
        sheet.paste(Image.open(p).convert("RGB"), (k * 600, 0))
    from PIL import ImageDraw

    draw = ImageDraw.Draw(sheet)
    for k, b in enumerate(rig.bones):
        c = tuple(int(v * 255) for v in palette[k % len(palette)])
        draw.rectangle([10 + (k % 10) * 178, 604 + (k // 10) * 18, 24 + (k % 10) * 178, 616 + (k // 10) * 18], fill=c)
        draw.text((28 + (k % 10) * 178, 603 + (k // 10) * 18), b["name"], fill=(255, 255, 255))
    sheet.save(WEIGHTS_PNG)
    for s, m in zip(body.material_slots, saved):
        s.material = m
    mesh.color_attributes.remove(mesh.color_attributes["BoneShare"])
    log("wrote", WEIGHTS_PNG)

# ---------- export ----------
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.fbx(
    filepath=OUT_PATH,
    use_selection=True,
    object_types={"ARMATURE", "MESH"},
    add_leaf_bones=False,
    bake_anim=False,
    axis_forward="-Z",
    axis_up="Y",
    bake_space_transform=True,
    apply_scale_options="FBX_SCALE_ALL",
    path_mode="COPY",
    embed_textures=True,
)
log("wrote", OUT_PATH, "bones", ", ".join(["Root"] + [b["name"] for b in rig.bones]))
