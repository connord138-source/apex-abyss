"""Builds the rolled parts as per-fish models: five parts on six fish, thirty models, each
authored against that fish's own mesh (owner, 2026-11-03: "These will need slight
redesigns with the mesh of the fish itself to make it actual blend as a variant/mutation
of that fish. Check that all parts look good and mesh correctly to the fish").

    blender --background --python tools/props/parts_fit.py -- build [Fish[:Part]]   # GLBs, seats.json
    blender --background --python tools/props/parts_fit.py -- luau src/shared/PartFits.luau
    blender --background --python tools/props/parts_fit.py -- sheet [Fish] [--draft]  # picture cells
    blender --background --python tools/props/parts_fit.py -- closeups Fish:Part[,Fish:Part]
    blender --background --python tools/props/parts_fit.py -- before
    blender --background --python tools/props/parts_fit.py -- swim Fish[:Part]
    python tools/props/parts_fit_check.py board [Fish | before | swim_<Fish>]         # the boards
    python tools/props/parts_fit_check.py check                                       # manifest, screen

Why the old models looked pasted on: one Tripo model for six fish, with its own foot
(the horn's plate and gold collar, the sail's plank, the veil's sleeve, the lure's block,
the saw's bulb), hung by a single point at x = 0 and stretched as a box. The fish are not
straight (the Reef Shark's tail sits 0.04 of its length off the bone line and the Moray
waves), so a part at x = 0 misses the ridge it should grow from, and a rigid foot can't
follow a curved back.

So nothing of the old geometry is kept but the design. Each model is lofted here from what
the ray casts find on the fish:

  * The root is conformed: its first ring of vertices is cast onto the fish's surface along
    the part's own axis and pushed `SINK` under it, the next rings hug the skin as a low
    fillet, then it leaves as the part. There's no collar, plate or stub, and no gap.
  * The fish's own fin stays inside: a sail or a veil is a shell whose thickness at each
    vertex is cast from the fish (`FIN_MARGIN` over the fin's surface), so the dorsal or
    tail fin under it never pokes through, and it runs along the fish's centre line.
  * The colour map's base is the fish's own colour map: every texel near the root takes the
    colour at the nearest point on the fish's surface, stripes and spots included, and
    blends into the part's colours toward the tip. It's laid out as a mosaic of quads
    (TILE_GAP), so no broad smooth stretch of one tone reaches the image screen.

Frames. "Fish space" (F here) is Blender's for the species FBX scaled to its unit box: x to
the side, head at y -0.5, tail at y +0.5, up z, the box centred on the origin. The game's
root space (the fish at 1 stud long) is g = (-x, z, y) (Shared/FishBuilder centres the box
on the root, FishBuilder.buildMesh). A GLB is authored in that same unit box, turned half
round about the vertical, so its front is on glTF -Z like every static model here (the
Roblox import then faces +Z, and Cosmetics turns it round). Roblox centres a MeshPart on its
mesh's bounding box, so `seats` holds that box's centre and size in g: the game sets
part.Size = size * length and puts the part at center * length with its rest frame turned
half round, and every vertex lands exactly where it was authored. A model rides one bone
(the head, the Tail, or the spine bone under a sail's middle), rigidly, as Cosmetics.follow
moves it. No normal map, ever: each GLB has a colour map, a metal-rough map and (if the source
part glowed) an emissive map.
"""

import json
import math
import pathlib
import sys

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

ROOT = pathlib.Path(__file__).resolve().parents[2]
FBX_DIR = ROOT / "assets/fbx/species"
OUT = ROOT / "assets/glb/parts/fit"
PREVIEWS = OUT / "previews"
SEATS_JSON = OUT / "seats.json"

FISH = ["Nibbler", "Cuda", "Puffer", "MorayEel", "ReefShark", "Angler"]
PARTS = ["AnglerLure", "NarwhalHorn", "SawSnout", "SailFin", "VeilTail"]
SIZE = 512
SINK = 0.012  # how far a root ring sits under the skin, in fish lengths
FIN_MARGIN = 0.008  # how far a shell stands over the fin inside it
# The colour map is a mosaic: every quad of the model has its own tile, with a dark line round
# it. A smooth atlas (one big gradient per part) reads as a broad stretch of skin to the image
# screen (scores up to 0.69, tools/shades/screen_shades.py), and a pale flesh-toned sheet is
# what got an account suspended once; the tiles keep each colour's stretch small
TILE_GAP = 1.5  # pixels of dark line on each side of a tile
TILE_INSET = 1.0  # pixels its UVs stay inside the tile, so filtering doesn't reach the line
TILE_DARK = 0.3  # the line's brightness over the tile's colour
PALE_SHARE = 0.015  # of a colour map, before clear_pale moves its pale texels (the screen's limit is 2%)

# ---------------------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------------------


def rgb(r, g, b):
    return np.array([r, g, b], dtype=np.float32) / 255.0


def normalize(v):
    v = np.asarray(v, dtype=np.float64)
    return v / max(float(np.linalg.norm(v)), 1e-9)


def smoothstep(a, b, x):
    t = np.clip((x - a) / max(b - a, 1e-6), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def ramp(t, stops):
    xs = [a for a, _ in stops]
    cs = np.array([c for _, c in stops], dtype=np.float32)
    return np.stack([np.interp(t, xs, cs[:, i]) for i in range(3)], -1).astype(np.float32)


def mix(a, b, t):
    t = np.asarray(t)[..., None] if np.ndim(t) else t
    return a * (1 - t) + b * t


def axis_frame(d):
    """Two unit vectors across a direction: U to the fish's side, V as near up as it goes."""
    d = normalize(d)
    u = normalize(np.array([1.0, 0, 0]) - d[0] * d)
    v = np.cross(d, u)
    if v[2] < 0 and abs(d[2]) < 0.9:
        u, v = -u, -v
    return u, v


def catmull(points, per=6):
    """A Catmull-Rom curve through the points, `per` samples a span."""
    p = [np.asarray(a, dtype=np.float64) for a in points]
    p = [2 * p[0] - p[1]] + p + [2 * p[-1] - p[-2]]
    out = []
    for i in range(1, len(p) - 2):
        for k in range(per):
            t = k / per
            a, b, c, d = p[i - 1], p[i], p[i + 1], p[i + 2]
            out.append(
                0.5
                * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (3 * b - a - 3 * c + d) * t * t * t)
            )
    out.append(p[-2])
    return np.array(out)


def transported_frames(path):
    """A frame per path point that doesn't twist along it."""
    tangents = np.gradient(path, axis=0)
    tangents = np.array([normalize(t) for t in tangents])
    u, v = axis_frame(tangents[0])
    us, vs = [u], [v]
    for i in range(1, len(path)):
        t = tangents[i]
        u = normalize(u - np.dot(u, t) * t)
        v = np.cross(t, u)
        us.append(u)
        vs.append(v)
    return tangents, np.array(us), np.array(vs)


# ---------------------------------------------------------------------------------------
# A fish: its rest mesh in the unit box, its texture, and what the rays find on it
# ---------------------------------------------------------------------------------------


class Fish:
    def __init__(self, name: str):
        self.name = name
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=str(FBX_DIR / f"{name}.fbx"))
        new = [o for o in bpy.data.objects if o not in before]
        obj = next(o for o in new if o.type == "MESH")
        arm = next(o for o in new if o.type == "ARMATURE")
        world = np.array(obj.matrix_world)
        n = len(obj.data.vertices)
        co = np.empty(n * 3)
        obj.data.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3) @ world[:3, :3].T + world[:3, 3]
        lo, hi = co.min(0), co.max(0)
        self.centre, self.scale = (lo + hi) / 2, 1 / (hi - lo)[1]
        self.co = (co - self.centre) * self.scale
        self.dims = (hi - lo) * self.scale
        mesh = obj.data
        mesh.calc_loop_triangles()
        uv_data = mesh.uv_layers.active.data
        self.tris = np.array([t.vertices[:] for t in mesh.loop_triangles], dtype=np.int64)
        self.uv = np.array([[uv_data[i].uv[:] for i in t.loops] for t in mesh.loop_triangles], dtype=np.float32)
        self.bvh = BVHTree.FromPolygons([Vector(p) for p in self.co.tolist()], self.tris.tolist(), all_triangles=True)
        self.groups = [g.name for g in obj.vertex_groups]
        weights = np.zeros((n, len(self.groups)), dtype=np.float32)
        for v in mesh.vertices:
            for g in v.groups:
                weights[v.index, g.group] = g.weight
        self.weights = weights
        self.bones = {}
        arm_world = np.array(arm.matrix_world)
        for b in arm.data.bones:
            head = arm_world[:3, :3] @ np.array(b.head_local) + arm_world[:3, 3]
            self.bones[b.name] = (head - self.centre) * self.scale
        mat = obj.material_slots[0].material
        bsdf = next(nd for nd in mat.node_tree.nodes if nd.type == "BSDF_PRINCIPLED")
        image = bsdf.inputs["Base Color"].links[0].from_node.image
        w, h = image.size
        self.tex = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)[..., :3]
        for o in new:
            bpy.data.objects.remove(o, do_unlink=True)
        self._measure()
        # The skin's smooth normal per vertex, for where a root leaves it
        corners = self.co[self.tris]
        face = np.cross(corners[:, 1] - corners[:, 0], corners[:, 2] - corners[:, 0])
        self.vnormals = np.zeros_like(self.co)
        for k in range(3):
            np.add.at(self.vnormals, self.tris[:, k], face)
        self.vnormals /= np.maximum(np.linalg.norm(self.vnormals, axis=1, keepdims=True), 1e-9)
        # The body without the fins standing on its back: a sail's skin colour comes from here,
        # so the dorsal fin inside it doesn't print a ghost of itself on the sail
        mid = corners.mean(1)
        keep = mid[:, 2] < np.interp(mid[:, 1], self.ys, self.back) + 0.012
        self.body_tris, self.body_uv = self.tris[keep], self.uv[keep]
        self.body_bvh = BVHTree.FromPolygons([Vector(p) for p in self.co.tolist()], self.body_tris.tolist(), all_triangles=True)

    # --- rays ---------------------------------------------------------------------------

    def ray(self, origin, direction, reach=4.0):
        hit = self.bvh.ray_cast(Vector(origin), Vector(direction), reach)
        return None if hit[0] is None else np.array(hit[0][:])

    def inside(self, p) -> bool:
        loc, nor, _, _ = self.bvh.find_nearest(Vector(p))
        return (Vector(p) - loc).dot(nor) < 0

    def _measure(self):
        """The body's midline, back and belly per station down its length, leaving thin
        fins out: a fish's x-extent at a height is `width`, and a fin is much narrower
        than the body."""
        ys = np.arange(-0.5, 0.5001, 0.01)
        zs = np.arange(-0.5, 0.5001, 0.006)
        cx, back, belly = np.full(len(ys), np.nan), np.full(len(ys), np.nan), np.full(len(ys), np.nan)
        for i, y in enumerate(ys):
            hi_x, lo_x = np.full(len(zs), np.nan), np.full(len(zs), np.nan)
            for j, z in enumerate(zs):
                r = self.ray((2.0, y, z), (-1.0, 0, 0))
                if r is None:
                    continue
                hi_x[j] = r[0]
                l = self.ray((-2.0, y, z), (1.0, 0, 0))
                lo_x[j] = l[0] if l is not None else r[0]
            width = hi_x - lo_x
            valid = ~np.isnan(width)
            if not valid.any():
                continue
            limit = max(0.03, 0.45 * float(np.median(width[valid])))
            body = np.where(valid & (width >= limit))[0]
            if len(body) == 0:
                body = np.where(valid)[0]
            cx[i] = float(np.median((hi_x[body] + lo_x[body]) / 2))
            back[i], belly[i] = zs[body.max()], zs[body.min()]

        def filled(a):
            good = ~np.isnan(a)
            a = np.interp(ys, ys[good], a[good])
            med = np.array([np.median(a[max(0, i - 2) : i + 3]) for i in range(len(a))])
            return np.convolve(np.pad(med, 2, mode="edge"), np.ones(5) / 5, mode="valid")

        self.ys, self.cx, self.back, self.belly = ys, filled(cx), filled(back), filled(belly)

    def cx_at(self, y):
        return np.interp(y, self.ys, self.cx)

    def back_at(self, y):
        return np.interp(y, self.ys, self.back)

    def surf_down(self, x, y, z_from, fallback):
        """The skin's height under a point, from just over the back, so a fin standing on
        it isn't taken for it."""
        hit = self.ray((x, y, z_from), (0, 0, -1.0), 0.3)
        return fallback if hit is None else float(hit[2])

    def extent(self, q, n, reach=0.25):
        """How far the fish stands out of q along n: the first hit from outside, as an
        offset along n, or None."""
        q = np.asarray(q)
        hit = self.ray(q + n * reach, -n, reach * 2)
        return None if hit is None else float(np.dot(hit - q, n))

    def conform(self, centre, d, offset, sink=0.0):
        """A point of a root ring: cast along the part's axis -d from over `offset` round
        its centre, onto the skin, moved `sink` along d (minus: under it). A ray that
        misses the fish walks in toward the centre until it hits."""
        for k in range(8):
            scale = 0.82**k
            hit = self.ray(centre + d * 0.7 + offset * scale, -d, 1.6)
            if hit is not None:
                return hit + d * sink, scale
        return centre + d * sink, 0.0

    # --- colour ----------------------------------------------------------------------

    def _barycentric(self, tris, loc):
        corners = self.co[tris]
        v0, v1, v2 = corners[:, 1] - corners[:, 0], corners[:, 2] - corners[:, 0], loc - corners[:, 0]
        d00, d01, d11 = (v0 * v0).sum(1), (v0 * v1).sum(1), (v1 * v1).sum(1)
        d20, d21 = (v2 * v0).sum(1), (v2 * v1).sum(1)
        den = np.maximum(d00 * d11 - d01 * d01, 1e-12)
        b1, b2 = (d11 * d20 - d01 * d21) / den, (d00 * d21 - d01 * d20) / den
        return 1 - b1 - b2, b1, b2

    def skin(self, points, body_only=False):
        """For (N, 3) points: the distance to the fish and its colour there."""
        bvh, tris, uvs = (self.body_bvh, self.body_tris, self.body_uv) if body_only else (self.bvh, self.tris, self.uv)
        n = len(points)
        loc = np.empty((n, 3), dtype=np.float64)
        idx = np.empty(n, dtype=np.int64)
        dist = np.empty(n, dtype=np.float32)
        find = bvh.find_nearest
        for i, q in enumerate(points.tolist()):
            hit = find(q)
            loc[i], idx[i], dist[i] = hit[0], hit[2], hit[3]
        b0, b1, b2 = self._barycentric(tris[idx], loc)
        # (a little toward the triangle's middle: the fish's map is black between its islands)
        b0, b1, b2 = b0 * 0.92 + 0.08 / 3, b1 * 0.92 + 0.08 / 3, b2 * 0.92 + 0.08 / 3
        uv = uvs[idx]
        u = b0 * uv[:, 0, 0] + b1 * uv[:, 1, 0] + b2 * uv[:, 2, 0]
        v = b0 * uv[:, 0, 1] + b1 * uv[:, 1, 1] + b2 * uv[:, 2, 1]
        h, w = self.tex.shape[:2]
        return dist, self.tex[(np.mod(v, 1) * h).astype(int) % h, (np.mod(u, 1) * w).astype(int) % w]

    def normal_at(self, q):
        """The skin's smooth normal at the point on it nearest q."""
        loc, _, idx, _ = self.bvh.find_nearest(Vector(q))
        tri = self.tris[idx]
        b0, b1, b2 = self._barycentric(tri[None], np.array([loc[:]]))
        return normalize(b0[0] * self.vnormals[tri[0]] + b1[0] * self.vnormals[tri[1]] + b2[0] * self.vnormals[tri[2]])

    def mean_colour(self, points) -> np.ndarray:
        _, c = self.skin(np.asarray(points, dtype=np.float64))
        return np.median(c, 0)

    def bone_over(self, y) -> str:
        """The spine bone whose stretch of the body holds this station: a rigid piece on a long
        back rides the bone under its middle, so its two ends stray the least."""
        spine = sorted(
            ((pos[1], name) for name, pos in self.bones.items() if name.startswith("Spine") or name == "Tail"),
        )
        best = spine[0][1]
        for at, name in spine:
            if at <= y:
                best = name
        return best


# ---------------------------------------------------------------------------------------
# A model: grids of vertices (patches), each with its rectangle of the colour map
# ---------------------------------------------------------------------------------------


class Patch:
    """R rows by C columns of vertices. `rect` is (u0, v0, u1, v1) of the texture: columns
    run along u, rows along v. `fields` are scalars per vertex for `paint`. `out` gives a
    triangle's outward direction, so the winding comes out right whatever the grid's
    orientation (Roblox culls back faces). The rows up to `smooth_rows` shade smooth, from the
    skin's own normal at row 0 to the part's own by that row, so the light doesn't break where
    the part leaves the fish; every row past it is flat, the fish's chunky facets."""

    def __init__(self, points, rect, paint, out, fields=None, skin=None, shared=False, smooth_rows=0, closed=False, body_only=False, flat_ends=0, one_diagonal=False, row_weights=None):
        self.points = np.asarray(points, dtype=np.float64)
        self.rect = rect
        self.paint = paint
        self.out = out
        self.fields = fields or {}
        self.skin = skin  # (d0, d1, p0, p1): full skin nearer than d0, none past d1; and by `p`
        self.shared = shared  # a later patch with the same rect paints nothing
        self.smooth_rows = smooth_rows
        self.closed = closed  # a tube: its first and last column are the same vertices
        self.body_only = body_only  # its skin colour comes from the body, not the fins on it
        self.flat_ends = flat_ends  # how many columns at each end stay flat (a sail's foot sinking in)
        self.one_diagonal = one_diagonal  # every quad split the same way: a twist reads as a spiral
        self.row_weights = row_weights  # how much of the rect each row of tiles takes (equal if None)

    def tile_edges(self):
        """The tiles' edges in texture pixels: across (C) and up (R)."""
        R, C = self.points.shape[:2]
        u0, v0, u1, v1 = self.rect
        cols = u0 * SIZE + (u1 - u0) * SIZE * np.arange(C) / max(C - 1, 1)
        w = np.ones(R - 1) if self.row_weights is None else np.asarray(self.row_weights, dtype=np.float64)
        rows = v0 * SIZE + (v1 - v0) * SIZE * np.concatenate([[0.0], np.cumsum(w) / w.sum()])
        return cols, rows


class Model:
    def __init__(self, fish: str, part: str, bone: str):
        self.fish, self.part, self.bone = fish, part, bone
        self.patches: list[Patch] = []
        self.root_points = []  # points of the root, for its colour and the check
        self.gem = None  # a lure's crystal: (middle, half-width, length), fish space

    def triangles(self, fish):
        """(tris x 3 x 3 positions, tris x 3 x 2 uvs, tris x 3 x 3 normals)."""
        verts, uvs, normals = [], [], []
        margin = TILE_GAP + TILE_INSET
        for patch in self.patches:
            P = patch.points
            R, C = P.shape[:2]
            col_edge, row_edge = patch.tile_edges()
            tris = []
            for r in range(R - 1):
                for c in range(C - 1):
                    a, b, d, e = (r, c), (r, c + 1), (r + 1, c + 1), (r + 1, c)
                    same = patch.one_diagonal or (r + c) % 2 == 0
                    pair = ((a, b, d), (a, d, e)) if same else ((a, b, e), (b, d, e))
                    tris.extend((t, r, c) for t in pair)

            def corner_uv(i, r, c):
                # (a vertex's place in the tile of the quad (r, c) it's a corner of)
                x = col_edge[c] + margin if i[1] == c else col_edge[c + 1] - margin
                y = row_edge[r] + margin if i[0] == r else row_edge[r + 1] - margin
                return np.array([x / SIZE, y / SIZE])

            vote = 0.0
            kept = []
            for t, qr, qc in tris:
                p0, p1, p2 = P[t[0]], P[t[1]], P[t[2]]
                nrm = np.cross(p1 - p0, p2 - p0)
                if np.linalg.norm(nrm) < 1e-7:
                    continue
                centre = (p0 + p1 + p2) / 3
                vote += float(np.dot(nrm, patch.out(centre, t[0][0], t[0][1])))
                kept.append((t, qr, qc))
            flip = vote < 0
            smooth = self._smooth_normals(patch, fish, flip) if patch.smooth_rows else None
            for t, qr, qc in kept:
                order = (t[0], t[2], t[1]) if flip else t
                corners = [P[i] for i in order]
                verts.append(corners)
                uvs.append([corner_uv(i, qr, qc) for i in order])
                face = normalize(np.cross(corners[1] - corners[0], corners[2] - corners[0]))
                ends = patch.flat_ends
                if (
                    smooth is not None
                    and max(i[0] for i in order) <= patch.smooth_rows
                    and min(i[1] for i in order) >= ends
                    and max(i[1] for i in order) <= C - 1 - ends
                ):
                    # (a triangle folded under the skin keeps its own normal: an interpolated one
                    # pointing away from its face shades black)
                    normals.append([smooth[i] if np.dot(smooth[i], face) > 0.15 else face for i in order])
                else:
                    normals.append([face, face, face])
        return np.array(verts, dtype=np.float64), np.array(uvs, dtype=np.float64), np.array(normals, dtype=np.float64)

    @staticmethod
    def _smooth_normals(patch, fish, flip):
        P = patch.points
        R, C = P.shape[:2]
        out = np.zeros((R, C, 3))
        last = patch.smooth_rows
        for r in range(min(last + 1, R)):
            for c in range(C):
                if patch.closed:
                    before, after = (c - 1) % (C - 1), (c + 1) % (C - 1)
                else:
                    before, after = max(c - 1, 0), min(c + 1, C - 1)
                across = P[r, after] - P[r, before]
                along = P[min(r + 1, R - 1), c] - P[max(r - 1, 0), c]
                own = np.cross(across, along)
                if flip:
                    own = -own
                if np.linalg.norm(own) < 1e-9:
                    own = patch.out(P[r, c], r, c)
                k = r / max(last, 1)
                skin = fish.normal_at(P[r, c].tolist())
                out[r, c] = normalize(skin * (1 - k) + normalize(own) * k)
        return out


def facet_noise(r, c, seed, amount):
    """A steady brightness per grid cell, for the fish's painted-facet look."""
    ri, ci = np.floor(r).astype(np.int64), np.floor(c).astype(np.int64)
    h = (ri * 73856093 ^ ci * 19349663 ^ (seed * 83492791)) & 0xFFFF
    return (1 + amount * (h / 65535.0 * 2 - 1)).astype(np.float32)


def clear_pale(color):
    """A map with more than the image screen's share of pale (bright, warm, little chroma: cream,
    peach; skin_masks in screen_shades.py) has those texels moved out of it with their hue kept: a
    tone with some colour is made a little richer, a near-white goes neutral. The mix of a pale fin
    colour with the fish's skin lands there. Maps under the limit stay as painted."""
    r, g, b = color[..., 0] * 255, color[..., 1] * 255, color[..., 2] * 255
    y = 0.299 * r + 0.587 * g + 0.114 * b
    dcb = -0.168736 * r - 0.331264 * g + 0.5 * b
    dcr = 0.5 * r - 0.418688 * g - 0.081312 * b
    chroma = np.hypot(dcr, dcb)
    pale = (y >= 148) & (dcr >= 0) & (dcb <= 0) & (dcr - dcb >= 2) & (chroma <= 32)
    if pale.mean() < PALE_SHARE:
        return color
    scale = np.where(chroma >= 12, 33.0 / np.maximum(chroma, 1e-3), 0.0)
    new_dcr, new_dcb = dcr * scale, dcb * scale
    out = color.copy()
    out[..., 0] = np.where(pale, (y + 1.402 * new_dcr) / 255, color[..., 0])
    out[..., 1] = np.where(pale, (y - 0.344136 * new_dcb - 0.714136 * new_dcr) / 255, color[..., 1])
    out[..., 2] = np.where(pale, (y + 1.772 * new_dcb) / 255, color[..., 2])
    return np.clip(out, 0, 1)


def bake(model: Model, fish: Fish):
    """Paints the colour, glow and roughness maps: each patch's own colours from its `paint`,
    then the fish's own colour near its root (Fish.skin)."""
    color = np.empty((SIZE, SIZE, 3), dtype=np.float32)
    color[:] = rgb(22, 28, 38)
    glow = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    rough = np.full((SIZE, SIZE), 0.72, dtype=np.float32)
    done = set()
    for patch in model.patches:
        if patch.rect in done:
            continue
        done.add(patch.rect)
        P = patch.points
        R, C = P.shape[:2]
        u0, v0, u1, v1 = patch.rect
        x0, x1 = int(round(u0 * SIZE)), int(round(u1 * SIZE))
        y0, y1 = int(round(v0 * SIZE)), int(round(v1 * SIZE))
        col_edge, row_edge = patch.tile_edges()

        def param(edges, pixels):
            # Each texel's place in the grid, clamped to its tile; and whether it's in the line
            at = pixels + 0.5
            idx = np.clip(np.searchsorted(edges, at, side="right") - 1, 0, len(edges) - 2)
            lo, hi = edges[idx], edges[idx + 1]
            margin = TILE_GAP + TILE_INSET
            span = np.maximum(hi - lo - 2 * margin, 1e-3)
            local = np.clip((at - lo - margin) / span, 0.0, 0.999)
            line = (at - lo < TILE_GAP) | (hi - at < TILE_GAP)
            return idx + local, line

        col_at, col_line = param(col_edge, np.arange(x0, x1))
        row_at, row_line = param(row_edge, np.arange(y0, y1))
        cc, rr = np.meshgrid(col_at, row_at)
        line = np.logical_or.outer(row_line, col_line)

        def sample(grid):
            i, j = np.minimum(rr.astype(int), R - 2 if R > 1 else 0), np.minimum(cc.astype(int), C - 2 if C > 1 else 0)
            fr, fc = rr - i, cc - j
            if grid.ndim == 3:
                fr, fc = fr[..., None], fc[..., None]
            return (
                grid[i, j] * (1 - fr) * (1 - fc)
                + grid[i, j + 1] * (1 - fr) * fc
                + grid[i + 1, j] * fr * (1 - fc)
                + grid[i + 1, j + 1] * fr * fc
            )

        pos = sample(P)
        f = {k: sample(np.asarray(v, dtype=np.float64)) for k, v in patch.fields.items()}
        f["r"], f["c"] = rr, cc
        f["pos"] = pos
        c, g, ro = patch.paint(f)
        if patch.skin is not None:
            d0, d1, p0, p1 = patch.skin
            # (softened a little: a point sample of the fish's map is noisy at its seams)
            dist, tone = fish.skin(pos.reshape(-1, 3), patch.body_only)
            dist = dist.reshape(pos.shape[:2])
            tone = tone.reshape(pos.shape).astype(np.float32)
            k = np.ones((3, 3), dtype=np.float32) / 9
            for ch in range(3):
                pad_t = np.pad(tone[..., ch], 1, mode="edge")
                tone[..., ch] = sum(
                    pad_t[1 + a : pad_t.shape[0] - 1 + a, 1 + b : pad_t.shape[1] - 1 + b] * k[a + 1, b + 1]
                    for a in (-1, 0, 1)
                    for b in (-1, 0, 1)
                )
            w = (1 - smoothstep(d0, d1, dist)) * (1 - smoothstep(p0, p1, f.get("p", np.zeros_like(dist))))
            c = mix(c, tone, w)
            if g is not None:
                g = g * (1 - w[..., None])
        c = np.where(line[..., None], c * TILE_DARK, c)
        color[y0:y1, x0:x1] = c
        if g is not None:
            glow[y0:y1, x0:x1] = g
        rough[y0:y1, x0:x1] = ro
    return clear_pale(color), glow, rough


# ---------------------------------------------------------------------------------------
# The parts. All sizes are in fish lengths, positions in fish space. Colours: PartFit's own
# averages for the parts, the concept boards' accents, and each fish's own (LOOKS).
# ---------------------------------------------------------------------------------------

LOOKS = {
    "Nibbler": {"back": rgb(209, 131, 77), "belly": rgb(204, 160, 89), "fin": rgb(214, 123, 46)},
    "Cuda": {"back": rgb(99, 120, 131), "belly": rgb(190, 196, 201), "fin": rgb(181, 166, 105)},
    "Puffer": {"back": rgb(134, 97, 72), "belly": rgb(195, 181, 162), "fin": rgb(172, 133, 103)},
    "MorayEel": {"back": rgb(78, 86, 10), "belly": rgb(120, 122, 97), "fin": rgb(80, 91, 16)},
    "ReefShark": {"back": rgb(104, 111, 117), "belly": rgb(173, 180, 188), "fin": rgb(61, 64, 65)},
    "Angler": {"back": rgb(51, 65, 99), "belly": rgb(35, 36, 68), "fin": rgb(63, 85, 119)},
}
CYAN = rgb(110, 238, 255)
GOLD = rgb(226, 186, 72)
BONE = rgb(226, 230, 232)  # cool: a pale warm cream is what the image screen distrusts


def tube_out(axis):
    return lambda centre, r, c: centre - axis[min(r, len(axis) - 1)]


def base_ring(fish, centre, d, offsets, sink):
    pts = []
    for off in offsets:
        q, _ = fish.conform(centre, d, off, sink)
        if sink < 0:
            # (on a thin snout a slanted skin can leave it outside: on until it's in)
            for _ in range(8):
                if fish.inside(q):
                    break
                q = q - d * 0.008
        pts.append(q)
    return np.array(pts)


def fillet_rows(fish, centre, d, offsets, levels):
    """The rows a loft leaves the skin by: each is the base shape scaled by `k`, cast on the
    skin and lifted by `lift` (negative: under it)."""
    rows = []
    for k, lift in levels:
        rows.append(base_ring(fish, centre, d, [o * k for o in offsets], lift))
    return rows


def hull(off, keep):
    """Smooths a shell's thickness over the fin inside it: never thinner than it was, a pillow
    rather than a crumple of the fin's ridges. `keep` marks the cells left alone (its edge)."""
    R, C = off.shape
    pad = np.pad(off, 1, mode="edge")
    near = np.stack([pad[1 + a : R + 1 + a, 1 + b : C + 1 + b] for a in (-1, 0, 1) for b in (-1, 0, 1)])
    dilated = near.max(0)
    pad = np.pad(dilated, 1, mode="edge")
    near = np.stack([pad[1 + a : R + 1 + a, 1 + b : C + 1 + b] for a in (-1, 0, 1) for b in (-1, 0, 1)])
    out = np.maximum(off, near.mean(0))
    out[keep] = off[keep]
    return out


# --- Sail Fin ----------------------------------------------------------------------------

SAILS = {
    # y0, y1: where its foot runs on the back; height above the back at its peak; shape:
    # (along the foot, share of height); lean: its spines' rearward lean, `fan` how much more at
    # the rear than the front (a fan on the round fish, a rake on the slender); flare: half-width
    # of the root's mound. `spots`, `spot`: its spots (gold on the source part), `mid` the fin
    # colour it runs through and `tip` the colour it reaches at the top
    "Nibbler": dict(
        y0=-0.33, y1=0.2, height=0.34, shape=[(0, -0.03), (0.1, 0.6), (0.3, 0.94), (0.5, 1.0), (0.76, 0.8), (1, -0.03)],
        lean=0.14, fan=0.75, spines=11, flare=0.05, tm=0.007, spots=18, blend=(0.03, 0.12, 0.12, 0.34), finmax=0.06,
        mid=rgb(214, 96, 40), tip=rgb(44, 54, 96),
    ),
    "Cuda": dict(
        y0=-0.2, y1=0.08, height=0.25, shape=[(0, -0.03), (0.1, 0.62), (0.3, 0.96), (0.46, 1.0), (0.78, 0.64), (1, -0.03)],
        lean=0.26, spines=8, flare=0.022, tm=0.004, spots=12, blend=(0.02, 0.09, 0.1, 0.32), finmax=0.04,
        mid=rgb(190, 170, 96), tip=rgb(52, 70, 96), spot=rgb(232, 216, 130),
    ),
    "Puffer": dict(
        y0=-0.31, y1=0.13, height=0.27, shape=[(0, -0.03), (0.1, 0.6), (0.3, 0.94), (0.5, 1.0), (0.76, 0.8), (1, -0.03)],
        lean=0.12, fan=0.6, spines=10, flare=0.05, tm=0.007, spots=16, blend=(0.02, 0.07, 0.07, 0.2), finmax=0.014, row_weights=[0.2, 0.2, 0.5, 1.0, 1.0, 1.4],
        mid=rgb(104, 93, 70), tip=rgb(50, 46, 64), spot=rgb(206, 170, 96),
    ),
    "MorayEel": dict(
        y0=-0.36, y1=0.22, bone="Spine3", height=0.17, shape=[(0, -0.03), (0.08, 0.6), (0.26, 0.98), (0.44, 1.0), (0.68, 0.76), (0.88, 0.46), (1, -0.03)],
        lean=0.26, spines=12, flare=0.022, tm=0.004, spots=26, blend=(0.02, 0.08, 0.1, 0.34), finmax=0.05,
        mid=rgb(92, 104, 24), tip=rgb(30, 54, 58), spot=rgb(58, 68, 12), spot_h=(0.12, 0.72), spot_r=(0.011, 0.02),
    ),
    "ReefShark": dict(
        y0=-0.24, y1=0.105, height=0.31, shape=[(0, -0.03), (0.08, 0.58), (0.26, 0.94), (0.44, 1.0), (0.76, 0.62), (1, -0.03)],
        lean=0.26, spines=9, flare=0.03, tm=0.005, spots=0, blend=(0.03, 0.12, 0.15, 0.45), finmax=0.04,
        mid=rgb(106, 112, 118), tip=rgb(38, 41, 46),
    ),
    "Angler": dict(
        y0=-0.13, y1=0.25, height=0.3, shape=[(0, -0.03), (0.1, 0.6), (0.3, 0.96), (0.46, 1.0), (0.78, 0.66), (1, -0.03)],
        lean=0.2, spines=9, flare=0.035, tm=0.006, spots=14, blend=(0.04, 0.14, 0.15, 0.45), finmax=0.05,
        mid=rgb(58, 80, 118), tip=rgb(24, 40, 74), spot=rgb(96, 206, 204),
    ),
}


def build_sail(fish: Fish, cfg) -> Model:
    n = cfg["spines"]
    cols = 2 * n + 1
    s = np.linspace(0, 1, cols)
    ridge = (np.arange(cols) % 2 == 1).astype(np.float64)
    shape = np.interp(s, [a for a, _ in cfg["shape"]], [b for _, b in cfg["shape"]])
    H = cfg["height"]
    y_foot = cfg["y0"] + (cfg["y1"] - cfg["y0"]) * s
    z_back = fish.back_at(y_foot)
    top_h = H * shape * (1 + 0.07 * ridge - 0.03 * (1 - ridge))
    hs = [0.1, 0.28, 0.5, 0.74, 1.0]
    rows = 2 + len(hs)
    model = Model(fish.name, "SailFin", cfg.get("bone") or fish.bone_over((cfg["y0"] + cfg["y1"]) / 2))
    root = []
    rng = np.random.default_rng(abs(hash_name(fish.name)) % (2**31))
    h_lo, h_hi = cfg.get("spot_h", (0.46, 0.92))
    r_lo, r_hi = cfg.get("spot_r", (0.009, 0.015))
    picks = [
        (rng.uniform(0.08, 0.92), rng.uniform(h_lo, h_hi), rng.uniform(r_lo, r_hi)) for _ in range(cfg["spots"])
    ]
    spots: list = []  # 3D, so they're round on the sail and through both its sides
    cell_y = (cfg["y1"] - cfg["y0"]) / (cols - 1) / 2
    for side, sgn in enumerate((1.0, -1.0)):
        P = np.zeros((rows, cols, 3))
        hf, pf = np.zeros((rows, cols)), np.zeros((rows, cols))
        shell = len(hs)
        centres, ys_at, zs_at, off = np.zeros((shell, cols)), np.zeros((shell, cols)), np.zeros((shell, cols)), np.zeros((shell, cols))
        live = top_h > 0
        for j in range(cols):
            y, zb = y_foot[j], z_back[j]
            lean = cfg["lean"] + cfg.get("fan", 0.0) * (s[j] - 0.5)
            z_low = zb + 0.012
            for i, h in enumerate(hs):
                dz = max(top_h[j], 0.0) * h
                z = max(z_low + 0.012 * h, zb + dz) if live[j] else zb - SINK - 0.01
                dz_total = z - zb
                yy = y + lean * dz_total
                fold = 0.006 * (1 if j % 4 == 1 else (-1 if j % 4 == 3 else 0)) * h
                centre = float(fish.cx_at(yy)) + fold
                tm = cfg["tm"] * (1.7 - 1.3 * h) * (1.5 if ridge[j] else 1.0)
                half = 0.0 if h >= 1.0 else tm
                if h < 1.0:
                    # The fish's own fin stays inside the shell, cast over its neighbourhood so the
                    # fin's ridges between two vertices stay in too. (Close over the back the rays
                    # find the body's own shoulders, which the root's mound meets: left out.)
                    cell_z = max(top_h[j], 0.02) * 0.1
                    for dy, dzz in ((0, 0), (cell_y, 0), (-cell_y, 0), (0, cell_z), (0, -cell_z)):
                        if z + dzz <= zb + cfg.get("crest", 0.022):
                            continue
                        e = fish.extent((centre, yy + dy, z + dzz), np.array([sgn, 0.0, 0.0]))
                        if e is not None and abs(e) < cfg["finmax"]:
                            half = max(half, e + FIN_MARGIN)
                centres[i, j], ys_at[i, j], zs_at[i, j], off[i, j] = centre, yy, z, half
                hf[2 + i, j] = h
                pf[2 + i, j] = dz_total / max(H, 1e-3)
        keep = np.zeros_like(off, dtype=bool)
        keep[-1, :] = True
        keep[:, ~live] = True
        off = hull(off, keep)
        for i in range(shell):
            for j in range(cols):
                P[2 + i, j] = (centres[i, j] + sgn * off[i, j], ys_at[i, j], zs_at[i, j])
        for j in range(cols):
            y, zb = y_foot[j], z_back[j]
            cx = float(fish.cx_at(y))
            # The root's mound under it, always wider than the shell it carries: an overhang
            # here reads as a dark seam line. Row 0 is under the skin, row 1 just on it
            first_half = abs(P[2, j, 0] - cx)
            flare = cfg["flare"] * math.sin(math.pi * s[j]) ** 0.6 + 0.002
            half1 = max(flare * 0.5, first_half + 0.003) if live[j] else flare * 0.5
            half0 = max(flare, half1 + 0.008) if live[j] else flare
            x1 = cx + sgn * half1
            z_skin1 = min(fish.surf_down(x1, y, zb + 0.06, zb), zb + 0.015)
            P[1, j] = (x1, y, z_skin1 + 0.003 if live[j] else z_skin1 - SINK)
            x0 = cx + sgn * half0
            z_skin0 = min(fish.surf_down(x0, y, zb + 0.06, zb), zb + 0.012)
            P[0, j] = (x0, y, z_skin0 - SINK - 0.006)
            for _ in range(8):  # (a corner of the body can leave it outside: on down until it's in)
                if fish.inside(P[0, j]):
                    break
                P[0, j, 2] -= 0.006
            root.append(P[0, j])
            if not live[j]:
                # (a dead end column stacks upward under the skin, so nothing folds back on itself
                # and shows its back through the foot)
                for i in range(shell):
                    P[2 + i, j] = (cx + sgn * half1 * (1 - (i + 1) / (shell + 1)), y, z_skin1 - SINK + 0.0008 * (i + 1))
        if side == 0:
            for sx, hx, rad in picks:
                j = min(int(sx * (cols - 1)), cols - 2)
                f = sx * (cols - 1) - j
                i = min(int(np.interp(hx, hs, np.arange(shell))), shell - 2)
                g = float(np.interp(hx, hs, np.arange(shell))) - i
                a = P[2 + i, j] * (1 - f) + P[2 + i, j + 1] * f
                b = P[3 + i, j] * (1 - f) + P[3 + i, j + 1] * f
                spots.append((a * (1 - g) + b * g, rad))
        fields = {"h": hf, "p": pf, "s": np.tile(s, (rows, 1)), "ridge": np.tile(ridge, (rows, 1))}
        rect = (0.0, 0.0, 1.0, 0.5) if side == 0 else (0.0, 0.5, 1.0, 1.0)
        model.patches.append(
            Patch(
                P,
                rect,
                sail_paint(fish, cfg, spots, side),
                (lambda sg: (lambda centre, r, c: np.array([sg, 0.0, 0.0])))(sgn),
                fields,
                cfg["blend"],
                smooth_rows=2,
                body_only=True,
                flat_ends=2,
                row_weights=cfg.get("row_weights"),
            )
        )
    model.root_points = np.array(root)
    return model


def hash_name(name: str) -> int:
    return sum((i + 1) * ord(ch) for i, ch in enumerate(name)) * 2654435761


def sail_paint(fish: Fish, cfg, spots, side: int):
    mid, tip = cfg["mid"], cfg["tip"]

    def paint(f):
        h, s, ridge = f["h"], f["s"], f["ridge"]
        # (the dark top is by height over the back too: the low ends stay the fish's colour)
        base = ramp(h * smoothstep(0.1, 0.55, f["p"]), [(0.0, mid), (0.5, mid), (0.9, tip), (1.0, tip)])
        spine_line = smoothstep(0.62, 0.92, ridge)
        spine = ramp(h, [(0.0, mid * 1.1), (0.7, mix(mid, tip, 0.45) * 1.3), (0.93, mix(tip, CYAN, 0.45)), (1.0, CYAN)])
        low_tip = 1 - smoothstep(0.35, 0.6, f["p"])
        spine = mix(spine, mid * 1.1, low_tip)
        c = mix(base, spine, spine_line)
        for at, rad in spots:
            d = np.linalg.norm(f["pos"] - at, axis=-1)
            on = (1 - smoothstep(rad * 0.7, rad, d)) * (1 - spine_line * 0.8)
            c = mix(c, cfg.get("spot", GOLD), on)
        c = c * facet_noise(f["r"], f["c"], side + 1, 0.05)[..., None]
        # (its low front and rear spines don't light up down by the skin)
        high = smoothstep(0.35, 0.6, f["p"])
        glow = CYAN * (spine_line * smoothstep(0.9, 0.99, h) * high)[..., None]
        rough = np.full(h.shape, 0.68, dtype=np.float32)
        return np.clip(c, 0, 1), glow.astype(np.float32), rough

    return paint


# --- Veil Tail ---------------------------------------------------------------------------

VEILS = {
    # y, z: the pivot, buried in the peduncle; fin_y: where the fish's own fin starts, behind
    # which the shell wraps it. lobes: (angle in degrees over the tail's line, length, width in
    # degrees, curl in degrees), span: the first and last ray's angles. mid, far, tip: its
    # colours going out from the fish's own fin
    "Nibbler": dict(
        y=0.285, z=-0.02, fin_y=0.33, span=(-84, 80), rays=15, base=0.32,
        lobes=[(40, 0.53, 36, 20), (-40, 0.55, 38, -26), (0, 0.5, 34, -6)],
        tm=0.006, wave=0.012, blend=(0.03, 0.12, 0.42, 0.7),
        mid=rgb(226, 112, 40), far=rgb(214, 74, 56), tip=rgb(92, 60, 160), rim=0.5,
    ),
    "Cuda": dict(
        y=0.325, z=-0.002, fin_y=0.365, span=(-72, 72), rays=14, base=0.22,
        lobes=[(46, 0.49, 26, 12), (-46, 0.49, 26, -14), (0, 0.27, 22, 0)],
        tm=0.004, wave=0.008, blend=(0.02, 0.08, 0.4, 0.7),
        mid=rgb(198, 182, 104), far=rgb(180, 164, 98), tip=rgb(70, 88, 112), rim=0.45,
    ),
    "Puffer": dict(
        y=0.34, z=0.04, fin_y=0.37, span=(-76, 76), rays=14, base=0.26,
        lobes=[(30, 0.43, 30, 4), (-24, 0.48, 32, -24), (-58, 0.38, 22, -26)],
        tm=0.006, wave=0.012, blend=(0.02, 0.07, 0.1, 0.26), spots=22, spot=rgb(62, 54, 42), row_weights=[0.4, 0.6, 1.0, 1.0, 1.0, 1.0],
        mid=rgb(104, 93, 70), far=rgb(88, 79, 66), tip=rgb(60, 48, 78), rim=0.3,
    ),
    "MorayEel": dict(
        y=0.35, z=0.005, fin_y=0.4, span=(-50, 50), rays=11, base=0.18,
        lobes=[(20, 0.36, 18, 10), (-20, 0.36, 18, -10), (0, 0.26, 16, 0)],
        tm=0.004, wave=0.009, blend=(0.02, 0.07, 0.3, 0.6), spots=16, spot=rgb(58, 68, 12),
        mid=rgb(100, 114, 28), far=rgb(70, 100, 44), tip=rgb(26, 66, 76), rim=0.4,
    ),
    "ReefShark": dict(
        y=0.29, z=0.0, fin_y=0.33, span=(-76, 68), rays=14, base=0.22,
        lobes=[(42, 0.5, 24, 8), (-50, 0.41, 24, -12), (-6, 0.28, 24, 0)],
        tm=0.005, wave=0.01, blend=(0.02, 0.09, 0.18, 0.4),
        mid=rgb(108, 114, 120), far=rgb(100, 105, 111), tip=rgb(36, 38, 42), rim=0.18,
    ),
    "Angler": dict(
        y=0.325, z=0.015, fin_y=0.355, span=(-78, 78), rays=14, base=0.28,
        lobes=[(36, 0.46, 30, 14), (-36, 0.46, 30, -16), (0, 0.39, 26, 0)],
        tm=0.006, wave=0.012, blend=(0.03, 0.1, 0.34, 0.6),
        mid=rgb(70, 92, 130), far=rgb(54, 62, 130), tip=rgb(42, 42, 120), rim=0.6,
    ),
}


def tail_frame(fish: Fish, cfg):
    """The real tail fin's plane: the pivot in its peduncle, b along its line away from the
    body, up within its plane, n through it (the fish's tail isn't square to its bones)."""
    co = fish.co
    pts = co[co[:, 1] > cfg["y"] + 0.03]
    mid = pts.mean(0)
    values, vectors = np.linalg.eigh(np.cov((pts - mid).T))
    n = vectors[:, int(np.argmin(values))]
    if n[0] < 0:
        n = -n
    origin = np.array([float(fish.cx_at(cfg["y"])), cfg["y"], cfg["z"]])
    origin = origin - np.dot(origin - mid, n) * n * 0.7
    b = np.array([0.0, 1.0, 0.0])
    b = normalize(b - np.dot(b, n) * n)
    up = np.cross(n, b)
    if up[2] < 0:
        up = -up
    return origin, b, up, n


def tail_outline(fish: Fish, origin, b, up):
    """How far the real tail fin reaches at each angle round the pivot, by 4-degree bins."""
    co = fish.co
    pts = co[co[:, 1] > origin[1] - 0.01] - origin
    a, c = pts @ b, pts @ up
    ang, rad = np.degrees(np.arctan2(c, a)), np.hypot(a, c)
    bins = np.arange(-90, 91, 4.0)
    reach = np.zeros(len(bins))
    for i, t in enumerate(bins):
        near = np.abs(ang - t) < 7
        reach[i] = rad[near].max() if near.any() else 0.0
    return bins, reach


def build_veil(fish: Fish, cfg) -> Model:
    origin, b, up, n = tail_frame(fish, cfg)
    bins, reach = tail_outline(fish, origin, b, up)
    rays = cfg["rays"]
    cols = 2 * rays + 1
    theta = np.linspace(cfg["span"][0], cfg["span"][1], cols)
    ridge = (np.arange(cols) % 2 == 1).astype(np.float64)
    length, curl = np.zeros(cols), np.zeros(cols)
    for j, t in enumerate(theta):
        best, weight, total = cfg["base"], 0.0, 0.0
        for centre, ln, width, bend in cfg["lobes"]:
            k = math.exp(-(((t - centre) / width) ** 2))
            best = max(best, ln * k)
            weight += bend * k
            total += k
        length[j] = max(best, float(np.interp(t, bins, reach)) + 0.018)
        curl[j] = weight / max(total, 1e-3) * min(total, 1.0)
    length *= 1 + 0.035 * ridge - 0.035 * (1 - ridge)
    # Its first and last rays run along the peduncle and sink into it
    length[0] = length[-1] = 0.05
    length[1] = min(length[1], 0.5 * length[2])
    length[-2] = min(length[-2], 0.5 * length[-3])
    rhos = [0.0, 0.13, 0.28, 0.46, 0.64, 0.82, 1.0]
    rows = len(rhos)
    model = Model(fish.name, "VeilTail", "Tail")
    finmax = 0.05
    rng = np.random.default_rng(abs(hash_name(fish.name)) % (2**31))
    streak = set(rng.choice(np.arange(1, cols - 1, 2), size=min(4, rays // 2), replace=False).tolist())
    streak_f = np.tile(np.array([1.0 if j in streak else 0.0 for j in range(cols)]), (rows, 1))
    spots: list = []
    for side, sgn in enumerate((1.0, -1.0)):
        P = np.zeros((rows, cols, 3))
        rf, pf = np.zeros((rows, cols)), np.zeros((rows, cols))
        Q, off = np.zeros((rows, cols, 3)), np.zeros((rows, cols))
        for i, rho in enumerate(rhos):
            for j in range(cols):
                r = rho * length[j] + 0.008
                t = math.radians(theta[j] + curl[j] * rho * rho)
                radial = math.cos(t) * b + math.sin(t) * up
                across = -math.sin(t) * b + math.cos(t) * up
                q = origin + r * radial
                wave = cfg["wave"] * rho**1.5 * math.sin(1.1 + 5.2 * rho + j * 0.8)
                pleat = (0.006 * (1 if j % 4 == 1 else (-1 if j % 4 == 3 else 0))) * rho**0.7
                q = q + n * (wave + pleat)
                tm = cfg["tm"] * (1.5 - 1.1 * rho) * (1.35 if ridge[j] else 1.0)
                half = tm
                if rho >= 1.0 or j == 0 or j == cols - 1:
                    half = 0.0
                else:
                    # The fish's own fin stays inside, cast over this vertex's neighbourhood; in
                    # the peduncle it stays thin and out of sight, it doesn't sleeve it
                    step_r = 0.09 * length[j]
                    step_a = max(r, 0.02) * math.radians((cfg["span"][1] - cfg["span"][0]) / (cols - 1)) * 0.5
                    for offset in (
                        np.zeros(3),
                        radial * step_r,
                        -radial * step_r,
                        across * step_a,
                        -across * step_a,
                    ):
                        sample = q + offset
                        if sample[1] <= cfg["fin_y"]:
                            continue
                        e = fish.extent(sample, n * sgn)
                        if e is not None and abs(e) < finmax:
                            half = max(half, e + FIN_MARGIN)
                Q[i, j], off[i, j] = q, half
                rf[i, j], pf[i, j] = rho, r / max(float(length.max()), 1e-3)
        keep = np.zeros_like(off, dtype=bool)
        keep[-1, :] = True
        keep[:, 0] = True
        keep[:, -1] = True
        off = hull(off, keep)
        P = Q + (n * sgn)[None, None, :] * off[..., None]
        if side == 0:
            # Its spots (the fish's own markings, carried out onto it) lie in 3D, through both sides
            for _ in range(cfg.get("spots", 0)):
                i = int(rng.integers(1, rows - 1))
                j = int(rng.integers(1, cols - 1))
                spots.append((P[i, j] * 0.6 + P[i + 1, j] * 0.4, rng.uniform(0.011, 0.02)))
        fields = {"rho": rf, "p": pf, "ridge": np.tile(ridge, (rows, 1)), "streak": streak_f}
        rect = (0.0, 0.0, 1.0, 0.5) if side == 0 else (0.0, 0.5, 1.0, 1.0)
        model.patches.append(
            Patch(
                P,
                rect,
                veil_paint(cfg, side, spots),
                (lambda v: (lambda centre, rr, cc: v))(n * sgn),
                fields,
                cfg["blend"],
                row_weights=cfg.get("row_weights"),
            )
        )
    model.root_points = np.array([origin + r * 0.03 * up for r in (-1, 0, 1)])
    return model


def veil_paint(cfg, side: int, spots):
    mid, far, tip = cfg["mid"], cfg["far"], cfg["tip"]
    rim_amount = cfg["rim"]

    def paint(f):
        rho, ridge, streak = f["rho"], f["ridge"], f["streak"]
        base = ramp(rho, [(0.0, mid), (0.55, mid), (0.84, far), (0.98, tip), (1.0, tip)])
        ray_line = smoothstep(0.6, 0.95, ridge)
        c = base * (1 - 0.18 * (1 - ridge[..., None]))
        c = mix(c, base * 1.28, ray_line * 0.75)
        on_streak = smoothstep(0.55, 0.95, streak) * smoothstep(0.4, 0.55, rho) * (1 - smoothstep(0.78, 0.94, rho))
        c = mix(c, CYAN, on_streak * rim_amount * 0.75)
        rim = smoothstep(0.95, 0.99, rho) * rim_amount
        c = mix(c, CYAN, rim)
        for at, rad in spots:
            d = np.linalg.norm(f["pos"] - at, axis=-1)
            c = mix(c, cfg["spot"], (1 - smoothstep(rad * 0.7, rad, d)) * (1 - smoothstep(0.82, 0.92, rho)))
        c = c * facet_noise(f["r"], f["c"], side + 11, 0.05)[..., None]
        glow = CYAN * (rim + on_streak * rim_amount * 0.6)[..., None]
        rough = np.full(rho.shape, 0.62, dtype=np.float32)
        return np.clip(c, 0, 1), np.clip(glow, 0, 1).astype(np.float32), rough

    return paint


# --- Narwhal Horn ------------------------------------------------------------------------

HORNS = {
    # at: where its axis enters the head (y, z on the centre line), pitch up from level,
    # length, r: half-widths of the root (side, up) and the shaft's radius where it leaves it
    "Nibbler": dict(at=(-0.44, 0.1), pitch=27, length=0.56, base=(0.085, 0.085), r=0.033, tone=rgb(238, 150, 70)),
    "Cuda": dict(at=(-0.46, -0.025), pitch=4, length=0.36, base=(0.032, 0.028), r=0.016, tone=rgb(170, 186, 200)),
    "Puffer": dict(at=(-0.46, 0.09), pitch=30, length=0.5, base=(0.07, 0.07), r=0.03, tone=rgb(190, 150, 112), fade=(0.14, 0.28)),
    "MorayEel": dict(at=(-0.47, -0.012), pitch=5, length=0.3, base=(0.032, 0.024), r=0.015, tone=rgb(140, 148, 60)),
    "ReefShark": dict(at=(-0.48, -0.03), pitch=2, length=0.38, base=(0.034, 0.024), r=0.0175, tone=rgb(146, 152, 158)),
    "Angler": dict(at=(-0.285, 0.115), pitch=-7, length=0.42, base=(0.05, 0.036), r=0.022, tone=rgb(86, 110, 150)),
}


def head_axis(fish, at, pitch):
    y, z = at
    p = math.radians(pitch)
    slope = (float(fish.cx_at(y)) - float(fish.cx_at(y + 0.12))) / 0.12
    d = normalize((slope * math.cos(p), -math.cos(p), math.sin(p)))
    return np.array([float(fish.cx_at(y)), y, z]), d


def build_horn(fish: Fish, cfg) -> Model:
    centre, d = head_axis(fish, cfg["at"], cfg["pitch"])
    u, v = axis_frame(d)
    sides = 9
    bx, bz = cfg["base"]
    angles = np.linspace(0, 2 * math.pi, sides, endpoint=False)
    offsets = [u * bx * math.cos(a) + v * bz * math.sin(a) for a in angles]
    levels = [(1.0, -SINK), (0.82, 0.002), (0.6, 0.012), (0.42, 0.028)]
    root_rows = fillet_rows(fish, centre, d, offsets, levels)
    # Its shaft starts where the fillet ends, on the same axis
    start_pts = root_rows[-1]
    t0 = float(np.dot(start_pts.mean(0) - centre, d)) + 0.02
    L = cfg["length"]
    r0 = cfg["r"]
    twist = 2 * math.pi * 1.7
    rows = list(root_rows)
    us, ps, bands, axes = [0.0] * len(rows), [0.0] * len(rows), [0.0] * len(rows), [
        rr.mean(0) for rr in root_rows
    ]
    for k in range(1, 15):
        t = k / 14
        along = t0 + (L - t0) * t
        rad = r0 * (1 + 0.55 * math.exp(-t / 0.1)) * (1 - t) ** 0.85 * (1.0 if k % 2 else 1.12)
        phase = twist * t
        c = centre + d * along
        ring = np.array(
            [c + (u * math.cos(a + phase) + v * math.sin(a + phase)) * max(rad, 0.0006) for a in angles]
        )
        rows.append(ring)
        us.append(t)
        ps.append(along / L)
        bands.append(0.0 if k % 2 else 1.0)
        axes.append(c)
    points = np.array([np.vstack([ring, ring[:1]]) for ring in rows])
    R, C = points.shape[:2]
    fields = {
        "u": np.tile(np.array(us)[:, None], (1, C)),
        "p": np.tile(np.array(ps)[:, None], (1, C)),
        "band": np.tile(np.array(bands)[:, None], (1, C)),
    }
    model = Model(fish.name, "NarwhalHorn", "Head")
    tone = cfg["tone"]
    fade = cfg.get("fade", (0.2, 0.36))

    def paint(f):
        t = f["u"]
        # (through a cool grey: halfway from a tan to white is the pale warm tone the screen distrusts)
        grey = mix(tone, rgb(112, 126, 146), 0.88)
        c = ramp(t, [(0.0, tone), (fade[0], tone), (fade[1], grey), (0.6, mix(grey, BONE, 0.8)), (1.0, rgb(238, 243, 248))])
        groove = np.abs(((f["c"] + 0.5) % (sides / 2)) - (sides / 4)) > (sides / 4 - 0.22)
        c = c * (1 - 0.26 * groove[..., None] * smoothstep(0.02, 0.2, t)[..., None])
        c = c * (1 + 0.1 * f["band"][..., None])
        c = c * facet_noise(f["r"], f["c"], 3, 0.03)[..., None]
        rough = (0.7 - 0.28 * smoothstep(0.1, 0.4, t)).astype(np.float32)
        return np.clip(c, 0, 1), None, rough

    model.patches.append(
        Patch(
            points, (0.0, 0.0, 1.0, 1.0), paint, tube_out(axes), fields, (0.02, 0.09, 0.22, 0.42),
            smooth_rows=len(root_rows), closed=True, one_diagonal=True,
            row_weights=[0.4] * len(root_rows) + [1.0] * (R - 1 - len(root_rows)),
        )
    )
    model.root_points = root_rows[0]
    return model


# --- Sawblade Snout ----------------------------------------------------------------------

SAWS = {
    # as the horn; base: half-width and half-height of the root, w and th the blade's
    "Nibbler": dict(at=(-0.46, -0.035), pitch=-2, length=0.62, base=(0.085, 0.05), w=0.05, th=0.027, teeth=9, tone=rgb(232, 118, 50), own=rgb(96, 100, 116), fade=(0.14, 0.28)),
    "Cuda": dict(at=(-0.46, -0.028), pitch=1, length=0.42, base=(0.034, 0.024), w=0.027, th=0.014, teeth=9, tone=rgb(120, 140, 152), own=rgb(92, 104, 118)),
    "Puffer": dict(at=(-0.46, 0.05), pitch=-1, length=0.58, base=(0.075, 0.042), w=0.046, th=0.024, teeth=9, tone=rgb(170, 128, 96), own=rgb(92, 92, 96), fade=(0.14, 0.28)),
    "MorayEel": dict(at=(-0.47, -0.012), pitch=1, length=0.36, base=(0.034, 0.022), w=0.025, th=0.014, teeth=8, tone=rgb(120, 128, 40), own=rgb(70, 88, 56)),
    "ReefShark": dict(at=(-0.48, -0.032), pitch=-1, length=0.44, base=(0.036, 0.024), w=0.03, th=0.015, teeth=10, tone=rgb(116, 122, 128), own=rgb(84, 90, 100)),
    "Angler": dict(at=(-0.285, 0.112), pitch=-6, length=0.5, base=(0.05, 0.03), w=0.036, th=0.018, teeth=9, tone=rgb(66, 86, 124), own=rgb(50, 62, 100)),
}
# The blade's cross-section: (across, up), the centre lines (where the glow runs) at 2 and 6
SAW_SECTION = [(1, 0), (0.72, 0.85), (0, 1), (-0.72, 0.85), (-1, 0), (-0.72, -0.85), (0, -1), (0.72, -0.85)]


def build_saw(fish: Fish, cfg) -> Model:
    centre, d = head_axis(fish, cfg["at"], cfg["pitch"])
    u, v = axis_frame(d)
    bx, bz = cfg["base"]
    offsets = [u * bx * a + v * bz * b for a, b in SAW_SECTION]
    levels = [(1.0, -SINK), (0.84, 0.002), (0.66, 0.012), (0.52, 0.03)]
    root_rows = fillet_rows(fish, centre, d, offsets, levels)
    L, w, th = cfg["length"], cfg["w"], cfg["th"]
    t0 = float(np.dot(root_rows[-1].mean(0) - centre, d)) + 0.03
    rows, us, axes = list(root_rows), [0.0] * len(root_rows), [rr.mean(0) for rr in root_rows]
    for k in range(1, 12):
        t = k / 11
        along = t0 + (L - t0) * t
        taper = (1 + 0.5 * math.exp(-t / 0.08)) * (1 - 0.3 * t)
        if t >= 0.93:
            taper *= 1 - (t - 0.93) / 0.07 * 0.72
        c = centre + d * along
        rows.append(np.array([c + u * w * taper * a + v * th * taper * b for a, b in SAW_SECTION]))
        us.append(along / L)
        axes.append(c)
    # The square tip closes on its centre
    tip = centre + d * (L + 0.004)
    rows.append(np.array([tip] * len(SAW_SECTION)))
    us.append(1.0)
    axes.append(tip)
    points = np.array([np.vstack([ring, ring[:1]]) for ring in rows])
    R, C = points.shape[:2]
    model = Model(fish.name, "SawSnout", "Head")
    tone, own = cfg["tone"], cfg["own"]
    fade = cfg.get("fade", (0.2, 0.5))

    def paint(f):
        t, col = f["p"], f["c"]
        c = ramp(t, [(0.0, tone), (fade[0], tone), (fade[1], mix(tone, own, 0.86)), (1.0, own)])
        edge = np.minimum(np.abs(col - 0), np.minimum(np.abs(col - 4), np.abs(col - 8)))
        c = c * (1 - 0.06 * (1 - smoothstep(0.0, 0.7, edge))[..., None])
        line = np.minimum(np.abs(col - 2), np.abs(col - 6))
        on = (1 - smoothstep(0.1, 0.24, line)) * smoothstep(0.2, 0.3, t) * (1 - smoothstep(0.93, 0.98, t))
        c = mix(c, CYAN, on)
        c = c * facet_noise(f["r"], f["c"], 5, 0.04)[..., None]
        glow = CYAN * on[..., None]
        rough = np.full(t.shape, 0.55, dtype=np.float32)
        return np.clip(c, 0, 1), glow.astype(np.float32), rough

    fields = {"p": np.tile(np.array(us)[:, None], (1, C))}
    model.patches.append(
        Patch(
            points, (0.0, 0.0, 1.0, 0.9), paint, tube_out(axes), fields, (0.02, 0.08, 0.2, 0.36),
            smooth_rows=len(root_rows), closed=True,
            row_weights=[0.4] * len(root_rows) + [1.0] * (R - 1 - len(root_rows)),
        )
    )

    # Teeth: bone wedges out of both edges, leaning back toward the fish, their feet in the blade
    def tooth_paint(f):
        t = f["u"]
        c = ramp(t, [(0.0, mix(own, BONE, 0.25)), (0.4, mix(own, BONE, 0.7)), (0.75, BONE), (1.0, rgb(240, 244, 246))])
        return np.clip(c, 0, 1), None, np.full(t.shape, 0.45, dtype=np.float32)

    rect = (0.0, 0.92, 1.0, 1.0)
    count = cfg["teeth"]
    size = w * 0.95
    for sgn in (1.0, -1.0):
        for k in range(count):
            t = 0.17 + 0.78 * (k + (0.25 if sgn > 0 else 0.75)) / count
            along = t0 + (L - t0) * t
            taper = 1 - 0.3 * t
            c = centre + d * along
            foot = c + u * sgn * w * taper * 0.8
            tip_at = foot + u * sgn * size * (0.85 + 0.2 * (k % 2)) - v * size * 0.42 - d * size * 0.3
            half = size * 0.34
            base = [
                foot + d * half + v * th * 0.35,
                foot - d * half + v * th * 0.35,
                foot - d * half - v * th * 0.35,
                foot + d * half - v * th * 0.35,
            ]
            ring0 = np.array(base + base[:1])
            ring1 = np.array([tip_at] * 5)
            grid = np.array([ring0, ring1])
            axis = [foot, tip_at]
            f_u = np.array([[0.0] * 5, [1.0] * 5])
            model.patches.append(Patch(grid, rect, tooth_paint, tube_out(axis), {"u": f_u}, None, shared=True))
    model.root_points = root_rows[0]
    return model


# --- Angler Lure ---------------------------------------------------------------------------

LURES = {
    # path: the stalk's line (y, z) from inside the head to the crystal's neck; r: its radius at
    # the foot and at the neck; gem: the crystal's half-width and length; hang: its lean ahead
    "Nibbler": dict(path=[(-0.315, 0.2), (-0.34, 0.33), (-0.42, 0.46), (-0.54, 0.47), (-0.63, 0.37), (-0.655, 0.25)], r=(0.03, 0.014), base=0.058, gem=(0.05, 0.13), tone=rgb(220, 120, 60)),
    "Cuda": dict(path=[(-0.305, 0.02), (-0.325, 0.095), (-0.385, 0.17), (-0.46, 0.18), (-0.525, 0.12), (-0.545, 0.05)], r=(0.0145, 0.0075), base=0.028, gem=(0.027, 0.075), tone=rgb(110, 128, 140)),
    "Puffer": dict(path=[(-0.295, 0.29), (-0.32, 0.4), (-0.4, 0.5), (-0.52, 0.5), (-0.6, 0.41), (-0.625, 0.3)], r=(0.027, 0.013), base=0.052, gem=(0.046, 0.12), tone=rgb(136, 100, 74)),
    "MorayEel": dict(path=[(-0.355, 0.035), (-0.37, 0.105), (-0.42, 0.165), (-0.49, 0.165), (-0.545, 0.115), (-0.56, 0.055)], r=(0.0135, 0.007), base=0.026, gem=(0.024, 0.065), tone=rgb(100, 110, 26)),
    "ReefShark": dict(path=[(-0.325, 0.02), (-0.345, 0.1), (-0.405, 0.175), (-0.49, 0.18), (-0.555, 0.12), (-0.575, 0.05)], r=(0.0155, 0.008), base=0.03, gem=(0.03, 0.08), tone=rgb(108, 114, 120)),
    # The Anglerfish's own lure, grown: the stalk lies over its stalk and the crystal round its bulb
    "Angler": dict(path=[(-0.15, 0.16), (-0.187, 0.233), (-0.235, 0.295), (-0.298, 0.336), (-0.367, 0.346), (-0.431, 0.301), (-0.45, 0.26)], r=(0.036, 0.024), base=0.06, gem=(0.062, 0.19), tone=rgb(50, 72, 110), own_stalk=True),
}


def build_lure(fish: Fish, cfg) -> Model:
    yz = np.array(cfg["path"])
    if cfg.get("own_stalk"):
        # The stalk's x where it really is
        xs = []
        for y, z in yz:
            near = np.linalg.norm(fish.co[:, 1:] - np.array([y, z]), axis=1) < 0.05
            xs.append(float(np.median(fish.co[near, 0])) if near.any() else float(fish.cx_at(y)))
    else:
        xs = [float(fish.cx_at(y)) for y, _ in yz]
    ctrl = [np.array([x, y, z]) for x, (y, z) in zip(xs, yz)]
    path = catmull(ctrl, per=4)
    tangents, us_, vs_ = transported_frames(path)
    sides = 6
    angles = np.linspace(0, 2 * math.pi, sides, endpoint=False)
    # The foot: find where the path leaves the head
    # (the Anglerfish's stalk is inside its own stalk all the way up: its foot is known)
    leave = 3 if cfg.get("own_stalk") else max(next((i for i, q in enumerate(path) if not fish.inside(q)), 1), 1)
    d = normalize(path[min(leave + 1, len(path) - 1)] - path[leave - 1])
    u, v = axis_frame(d)
    foot = path[leave]
    b = cfg["base"]
    offsets = [u * b * math.cos(a) + v * b * math.sin(a) for a in angles]
    levels = [(1.0, -SINK), (0.78, 0.003), (0.56, 0.012)]
    root_rows = fillet_rows(fish, foot, d, offsets, levels)
    rows, ts, axes, bands = list(root_rows), [0.0] * len(root_rows), [rr.mean(0) for rr in root_rows], [0.0] * len(
        root_rows
    )
    r_foot, r_neck = cfg["r"]
    start = leave + 2
    count = len(path) - start
    for k, i in enumerate(range(start, len(path))):
        t = (k + 1) / max(count, 1)
        rad = (r_foot + (r_neck - r_foot) * t) * (1.1 if k % 2 == 0 else 0.92)
        ring = np.array([path[i] + (us_[i] * math.cos(a) + vs_[i] * math.sin(a)) * rad for a in angles])
        rows.append(ring)
        ts.append(t)
        axes.append(path[i])
        bands.append(1.0 if k % 2 == 0 else 0.0)
    points = np.array([np.vstack([ring, ring[:1]]) for ring in rows])
    R, C = points.shape[:2]
    model = Model(fish.name, "AnglerLure", "Head")
    tone = cfg["tone"]
    own = rgb(95, 121, 127)

    def stalk_paint(f):
        t = f["u"]
        c = ramp(t, [(0.0, tone), (0.45, tone), (0.78, mix(tone, own, 0.7)), (1.0, rgb(120, 190, 196))])
        c = c * (1 - 0.14 * f["band"][..., None])
        c = c * facet_noise(f["r"], f["c"], 7, 0.04)[..., None]
        glow = CYAN * (smoothstep(0.86, 1.0, t) * 0.55)[..., None]
        return np.clip(c, 0, 1), glow.astype(np.float32), np.full(t.shape, 0.6, dtype=np.float32)

    fields = {
        "u": np.tile(np.array(ts)[:, None], (1, C)),
        "p": np.tile(np.array(ts)[:, None], (1, C)),
        "band": np.tile(np.array(bands)[:, None], (1, C)),
    }
    model.patches.append(
        Patch(
            points, (0.0, 0.0, 0.5, 1.0), stalk_paint, tube_out(axes), fields, (0.02, 0.07, 0.12, 0.34),
            smooth_rows=len(root_rows), closed=True,
            row_weights=[0.4] * len(root_rows) + [1.0] * (R - 1 - len(root_rows)),
        )
    )

    # The crystal: a faceted gem on the stalk's end, hanging down from it
    neck = path[-1]
    hang = np.array([0.0, 0.0, -1.0]) if cfg.get("own_stalk") else normalize(0.45 * tangents[-1] + np.array([0.0, 0.0, -1.0]))
    gu, gv = axis_frame(hang)
    gw, gl = cfg["gem"]
    gem_rows = [(0.0, 0.25), (0.14, 0.72), (0.36, 1.0), (0.62, 0.94), (0.84, 0.42), (1.0, 0.0)]
    gem_sides = 6
    gem_angles = np.linspace(0, 2 * math.pi, gem_sides, endpoint=False)
    rings, gem_axes = [], []
    start_at = neck - hang * 0.01
    model.gem = (start_at + hang * gl * 0.42, gw, gl)
    for k, (t, rad) in enumerate(gem_rows):
        c = start_at + hang * gl * t
        turn = 0.5 * (k % 2) * (2 * math.pi / gem_sides)
        rings.append(
            np.array([c + (gu * math.cos(a + turn) + gv * math.sin(a + turn)) * gw * max(rad, 0.001) for a in gem_angles])
        )
        gem_axes.append(c)
    gem_points = np.array([np.vstack([ring, ring[:1]]) for ring in rings])

    def gem_paint(f):
        t = f["t"]
        c = ramp(t, [(0.0, rgb(40, 150, 200)), (0.3, CYAN), (0.7, rgb(170, 248, 255)), (1.0, rgb(60, 190, 230))])
        c = c * facet_noise(f["r"], f["c"], 9, 0.2)[..., None]
        glow = np.clip(c, 0, 1) * 0.5
        return np.clip(c, 0, 1), glow.astype(np.float32), np.full(t.shape, 0.2, dtype=np.float32)

    gR, gC = gem_points.shape[:2]
    model.patches.append(
        Patch(
            gem_points,
            (0.5, 0.5, 1.0, 1.0),
            gem_paint,
            tube_out(gem_axes),
            {"t": np.tile(np.linspace(0, 1, gR)[:, None], (1, gC))},
        )
    )

    # Two wisps trailing from the neck
    def wisp_paint(f):
        t = f["t"]
        c = ramp(t, [(0.0, rgb(120, 200, 210)), (1.0, rgb(190, 238, 244))])
        return c, (c * (0.25 * (1 - t))[..., None]).astype(np.float32), np.full(t.shape, 0.55, dtype=np.float32)

    for sgn in (1.0, -1.0):
        length = gl * 1.5
        pts = []
        for k in range(8):
            t = k / 7
            pts.append(
                neck
                + np.array([sgn * (gw * 1.05 * math.sin(min(t * 2.2, 1.0) * math.pi / 2)), 0.0, 0.0])
                + np.array([sgn * gw * 0.28 * math.sin(t * 7.0), gw * 0.3 * math.sin(t * 5.0 + sgn), 0.0])
                + np.array([0.0, 0.0, -1.0]) * length * t
            )
        pts = np.array(pts)
        _, wu, wv = transported_frames(pts)
        ring_a = np.linspace(0, 2 * math.pi, 3, endpoint=False)
        grid = []
        for k in range(8):
            rad = max(gw * 0.075 * (1 - k / 7.5), 0.0007)
            ring = [pts[k] + (wu[k] * math.cos(a) + wv[k] * math.sin(a)) * rad for a in ring_a]
            grid.append(np.array(ring + ring[:1]))
        grid = np.array(grid)
        model.patches.append(
            Patch(
                grid,
                (0.5, 0.0, 1.0, 0.46),
                wisp_paint,
                tube_out(list(pts)),
                {"t": np.tile(np.linspace(0, 1, 8)[:, None], (1, 4))},
                None,
                shared=True,
            )
        )
    model.root_points = root_rows[0]
    return model


BUILDERS = {
    "SailFin": lambda fish: build_sail(fish, SAILS[fish.name]),
    "VeilTail": lambda fish: build_veil(fish, VEILS[fish.name]),
    "NarwhalHorn": lambda fish: build_horn(fish, HORNS[fish.name]),
    "SawSnout": lambda fish: build_saw(fish, SAWS[fish.name]),
    "AnglerLure": lambda fish: build_lure(fish, LURES[fish.name]),
}
# Which source parts glow (parts_prep.py's emissive maps): the horn has none
GLOWS = {"AnglerLure", "SawSnout", "SailFin", "VeilTail"}


# ---------------------------------------------------------------------------------------
# Writing a model out
# ---------------------------------------------------------------------------------------


def new_image(name: str, pixels: np.ndarray, colour: bool):
    h, w = pixels.shape[:2]
    image = bpy.data.images.new(name, w, h, alpha=False)
    image.colorspace_settings.name = "sRGB" if colour else "Non-Color"
    out = np.ones((h, w, 4), dtype=np.float32)
    out[..., :3] = np.clip(pixels, 0, 1)
    image.pixels.foreach_set(out.ravel())
    image.file_format = "PNG"
    image.pack()
    return image


def export_glb(model: Model, verts_f: np.ndarray, uvs: np.ndarray, normals_f: np.ndarray, color, glow, rough, path: pathlib.Path):
    """Writes the GLB, its geometry turned half round about the vertical (front on glTF -Z),
    and returns the box's centre and size in the game's root space."""
    name = f"{model.fish}_{model.part}"
    # F -> the part frame every static GLB here uses (front +Y, up +Z): (-x, -y, z)
    flat = verts_f.reshape(-1, 3)
    part = flat * np.array([-1.0, -1.0, 1.0])
    mesh = bpy.data.meshes.new(name)
    faces = np.arange(len(part)).reshape(-1, 3).tolist()
    mesh.from_pydata(part.tolist(), [], faces)
    mesh.update()
    layer = mesh.uv_layers.new(name="UVMap")
    layer.data.foreach_set("uv", uvs.reshape(-1).astype(np.float32))
    # (each triangle has its own vertices: flat where its normals are its face's, and smooth
    # where the root leaves the skin)
    mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
    mesh.normals_split_custom_set((normals_f.reshape(-1, 3) * np.array([-1.0, -1.0, 1.0])).tolist())
    mesh.update()

    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    tree = mat.node_tree
    bsdf = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = new_image(f"{name}_Color", color, True)
    tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    orm = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    orm[..., 0], orm[..., 1], orm[..., 2] = 1.0, rough, 0.0
    orm_tex = tree.nodes.new("ShaderNodeTexImage")
    orm_tex.image = new_image(f"{name}_ORM", orm, False)
    sep = tree.nodes.new("ShaderNodeSeparateColor")
    tree.links.new(orm_tex.outputs["Color"], sep.inputs["Color"])
    tree.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    tree.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    if model.part in GLOWS and float(glow.max()) > 0.01:
        glow_tex = tree.nodes.new("ShaderNodeTexImage")
        glow_tex.image = new_image(f"{name}_Glow", glow, True)
        tree.links.new(glow_tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_tangents=False,
        export_image_format="AUTO",
    )
    for image in list(bpy.data.images):
        if image.name.startswith(name):
            bpy.data.images.remove(image)
    bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.meshes.remove(mesh)
    bpy.data.materials.remove(mat)
    lo, hi = flat.min(0), flat.max(0)
    centre, size = (lo + hi) / 2, hi - lo
    # F (x, y, z) -> game (-x, z, y)
    return [-centre[0], centre[2], centre[1]], [size[0], size[2], size[1]]


def build_all(only: str):
    want_fish, _, want_part = only.partition(":")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    seats = json.loads(SEATS_JSON.read_text()) if SEATS_JSON.exists() else {}
    for fish_name in FISH:
        if want_fish and fish_name != want_fish:
            continue
        fish = Fish(fish_name)
        print(
            f"[parts_fit] {fish_name}: box {fish.dims.round(3).tolist()},"
            f" midline x {fish.cx.min():+.3f}..{fish.cx.max():+.3f}"
        )
        for part in PARTS:
            if want_part and part != want_part:
                continue
            model = BUILDERS[part](fish)
            verts, uvs, normals = model.triangles(fish)
            color, glow, rough = bake(model, fish)
            path = OUT / f"{fish_name}_{part}.glb"
            centre, size = export_glb(model, verts, uvs, normals, color, glow, rough, path)
            root = np.asarray(model.root_points, dtype=np.float64)
            skin = fish.mean_colour(root)
            buried = sum(fish.inside(p) for p in root.tolist()) / max(len(root), 1)
            seats.setdefault(fish_name, {})[part] = {
                "bone": model.bone,
                "center": [round(float(a), 5) for a in centre],
                "size": [round(float(a), 5) for a in size],
                "skin": [int(round(float(a) * 255)) for a in skin],
                "buried": round(float(buried), 3),
                "tris": len(verts),
                "root": [round(float(a), 4) for a in root.mean(0)],
            }
            if model.gem is not None:
                at, half_width, gem_length = model.gem
                # F (x, y, z) -> game (-x, z, y)
                seats[fish_name][part]["gem"] = [round(float(a), 5) for a in (-at[0], at[2], at[1])]
                seats[fish_name][part]["gem_size"] = [round(float(half_width) * 2, 5), round(float(gem_length), 5)]
            print(
                f"[parts_fit] {fish_name}_{part}: {len(verts)} tris, bone {model.bone},"
                f" root {buried * 100:.0f}% under the skin"
            )
    SEATS_JSON.parent.mkdir(parents=True, exist_ok=True)
    SEATS_JSON.write_text(json.dumps(seats, indent=1) + "\n")


# ---------------------------------------------------------------------------------------
# Pictures: the models read back from their GLBs and seated by the game's arithmetic
# ---------------------------------------------------------------------------------------


def scene_setup(draft: bool):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.engine = "CYCLES"
    s.cycles.device = "CPU"
    s.cycles.samples = 10 if draft else 28
    s.cycles.use_denoising = not draft
    s.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("Water")
    s.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.2, 0.42, 0.42, 1)
    bg.inputs["Strength"].default_value = 1.0
    for name, energy, rot, colour in (
        ("Key", 2.6, (35, 10, 30), (1, 1, 1)),
        ("Fill", 0.9, (110, 0, -70), (0.8, 0.9, 1.0)),
        ("Rim", 1.4, (-70, 0, 180), (0.7, 0.95, 1.0)),
    ):
        data = bpy.data.lights.new(name, "SUN")
        data.energy = energy
        data.color = colour
        obj = bpy.data.objects.new(name, data)
        obj.rotation_euler = tuple(math.radians(a) for a in rot)
        s.collection.objects.link(obj)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("Cam", cam_data)
    s.collection.objects.link(cam)
    s.camera = cam
    return s, cam


def load_fish_mesh(name: str):
    """The fish at rest in its unit box, with its texture; the armature too, for `swim`."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(FBX_DIR / f"{name}.fbx"))
    new = [o for o in bpy.data.objects if o not in before]
    obj = next(o for o in new if o.type == "MESH")
    world = obj.matrix_world.copy()
    obj.parent = None
    for m in list(obj.modifiers):
        obj.modifiers.remove(m)
    obj.data.transform(world)
    obj.matrix_world = Matrix.Identity(4)
    for o in new:
        if o is not obj:
            bpy.data.objects.remove(o, do_unlink=True)
    co = np.array([v.co[:] for v in obj.data.vertices])
    lo, hi = co.min(0), co.max(0)
    obj.data.transform(Matrix.Scale(1 / (hi - lo)[1], 4) @ Matrix.Translation(-Vector(((lo + hi) / 2).tolist())))
    return obj


def cull_back_faces(material):
    """Roblox doesn't draw a triangle's back: neither does the proof."""
    tree = material.node_tree
    out = next(n for n in tree.nodes if n.type == "OUTPUT_MATERIAL")
    surface = out.inputs["Surface"].links[0].from_node
    geom = tree.nodes.new("ShaderNodeNewGeometry")
    clear = tree.nodes.new("ShaderNodeBsdfTransparent")
    mix_node = tree.nodes.new("ShaderNodeMixShader")
    tree.links.new(geom.outputs["Backfacing"], mix_node.inputs[0])
    tree.links.new(surface.outputs[0], mix_node.inputs[1])
    tree.links.new(clear.outputs[0], mix_node.inputs[2])
    tree.links.new(mix_node.outputs[0], out.inputs["Surface"])
    material.surface_render_method = "DITHERED"


def load_fit(fish: str, part: str, seat: dict):
    """A fit GLB put where the game puts it: the mesh centred on its box and stretched to
    `size`, its centre at `center`, turned half round about up (game -> Blender (-x, z, y))."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(OUT / f"{fish}_{part}.glb"))
    new = [o for o in bpy.data.objects if o not in before]
    obj = next(o for o in new if o.type == "MESH")
    world = obj.matrix_world.copy()
    obj.parent = None
    obj.data.transform(world)
    obj.matrix_world = Matrix.Identity(4)
    for o in new:
        if o is not obj:
            bpy.data.objects.remove(o, do_unlink=True)
    co = np.array([v.co[:] for v in obj.data.vertices])
    lo, hi = co.min(0), co.max(0)
    mid = (lo + hi) / 2
    # The glTF import's frame is the part frame (front +Y, up +Z). In the game the mesh's axes
    # after its half-turn are (x, z, -y) of that, so box axes (x, y, z in the game) = its (x, z, y)
    want = seat["size"]
    have = hi - lo
    stretch = Matrix.Diagonal((want[0] / have[0], want[2] / have[1], want[1] / have[2], 1.0))
    # Part frame -> game: (x, z, -y); game -> Blender fish frame: (-x, z, y); so the part
    # frame -> fish frame is (-x, -y, z), a half turn about Z
    half = Matrix.Rotation(math.pi, 4, "Z")
    c = seat["center"]
    place = Matrix.Translation((-c[0], c[2], c[1]))
    obj.data.transform(place @ half @ stretch @ Matrix.Translation(Vector((-mid).tolist())))
    for slot in obj.material_slots:
        cull_back_faces(slot.material)
    return obj


def bounds(objs):
    pts = []
    for o in objs:
        co = np.empty(len(o.data.vertices) * 3)
        o.data.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        m = np.array(o.matrix_world)
        pts.append(co @ m[:3, :3].T + m[:3, 3])
    pts = np.concatenate(pts)
    return pts.min(0), pts.max(0)


def shoot(scene, cam, objs, direction, path, w, h, centre=None, span=None):
    lo, hi = bounds(objs)
    mid = Vector(((lo + hi) / 2).tolist()) if centre is None else Vector(list(centre))
    d = Vector(direction).normalized()
    cam.location = mid + d * 6
    cam.rotation_euler = (mid - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.view_layer.update()
    if span is None:
        inv = cam.matrix_world.inverted()
        corners = [Vector((x, y, z)) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]
        local = np.array([(inv @ c)[:2] for c in corners])
        span = max(np.ptp(local[:, 0]), np.ptp(local[:, 1]) * w / h) * 1.08
    cam.data.ortho_scale = span
    scene.render.resolution_x, scene.render.resolution_y = w, h
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


VIEWS = {
    "side": (1.0, 0.0, 0.0),
    "three": (0.9, -0.85, 0.55),
    "behind": (0.75, 0.95, 0.5),
    "top": (0.0, 0.001, 1.0),
    "front": (0.0, -1.0, 0.15),
}
# What each close-up looks at: the root, a bit further out on a sail or a veil
FOCUS = {"AnglerLure": 0.22, "NarwhalHorn": 0.24, "SawSnout": 0.24, "SailFin": 0.42, "VeilTail": 0.42}
CELL = (640, 440)


def sheet(only: str, draft: bool):
    """Renders each fish's cells (side, three-quarter, close on the seat) into previews/_cells;
    parts_fit_check.py board lays them out (Blender's Python has no PIL)."""
    seats = json.loads(SEATS_JSON.read_text())
    cells = PREVIEWS / "_cells"
    cells.mkdir(parents=True, exist_ok=True)
    w, h = (400, 280) if draft else CELL
    for fish in FISH:
        if only and fish != only:
            continue
        scene, cam = scene_setup(draft)
        body = load_fish_mesh(fish)
        for part in PARTS:
            seat = seats[fish][part]
            obj = load_fit(fish, part, seat)
            shoot(scene, cam, [body, obj], VIEWS["side"], cells / f"{fish}_{part}_side.png", w, h)
            shoot(scene, cam, [body, obj], VIEWS["three"], cells / f"{fish}_{part}_three.png", w, h)
            shoot(
                scene, cam, [body, obj], VIEWS["three"], cells / f"{fish}_{part}_close.png", w, h, seat["root"], FOCUS[part]
            )
            bpy.data.objects.remove(obj, do_unlink=True)
        print(f"[parts_fit] cells: {fish}")


def closeups(spec: str):
    """Bigger shots of named pairs, into previews/_cells, for looking hard at a model."""
    seats = json.loads(SEATS_JSON.read_text())
    cells = PREVIEWS / "_cells"
    cells.mkdir(parents=True, exist_ok=True)
    for pair in spec.split(","):
        fish, _, part = pair.partition(":")
        scene, cam = scene_setup(False)
        body = load_fish_mesh(fish)
        seat = seats[fish][part]
        obj = load_fit(fish, part, seat)
        for view in ("side", "three", "behind", "top", "front"):
            shoot(scene, cam, [body, obj], VIEWS[view], cells / f"big_{fish}_{part}_{view}.png", 800, 560)


# --- The old hang, for the before pictures: PartFit's table on the old models --------------

# (Shared/PartFit.MODELS, the numbers the game draws today)
OLD_MODELS = {
    "SailFin": dict(attach=(0, -0.2459, 0.0002), tint="fin", own=(47, 58, 78), strength=1.0, reversed=False, transparency=0.0),
    "VeilTail": dict(attach=(0.07, 0.0079, -0.5), tint="fin", own=(52, 59, 128), strength=1.0, reversed=False, transparency=0.2),
}
OLD_SHAPES = {
    ("Nibbler", "SailFin"): (0, 0.18, -0.13, 0, 0.55, 1, 1.3, 0.65),
    ("ReefShark", "SailFin"): (0, -0.01, -0.12, 2, 0.55, 1.4, 1.15, 0.8),
    ("Nibbler", "VeilTail"): (0, -0.02, 0.25, 0, 0.6, 0.7, 1, 1),
    ("ReefShark", "VeilTail"): (0, 0, 0.27, -8, 0.5, 0.3, 0.38, 1.7),
}
OLD_LOOKS = {
    "Nibbler": (214, 123, 46),
    "ReefShark": (61, 64, 65),
}


def old_tint(part, fish):
    """PartFit.tint, in Python."""
    m = OLD_MODELS[part]
    own = np.array(m["own"]) / 255
    colour = np.array(OLD_LOOKS[fish]) / 255

    def lum(c):
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

    k = lum(own) / max(lum(colour), 0.02)
    want = colour * k
    ratio = np.clip(want / np.maximum(own, 0.02), 0, 1)
    miss, away = ((own * ratio - want) ** 2).sum(), ((own - want) ** 2).sum()
    reach = 1.0 if away < 0.04**2 else 1 - math.sqrt(miss) / math.sqrt(away)
    t = np.clip((reach - 0.3) / 0.6, 0, 1)
    share = m["strength"] * t * t * (3 - 2 * t)
    return 1 + (ratio - 1) * share


def load_old(fish: str, part: str):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / "assets/glb/parts" / f"{part}.glb"))
    new = [o for o in bpy.data.objects if o not in before]
    obj = next(o for o in new if o.type == "MESH")
    world = obj.matrix_world.copy()
    obj.parent = None
    obj.data.transform(world)
    obj.matrix_world = Matrix.Identity(4)
    for o in new:
        if o is not obj:
            bpy.data.objects.remove(o, do_unlink=True)
    co = np.array([v.co[:] for v in obj.data.vertices])
    lo, hi = co.min(0), co.max(0)
    unit = float((hi - lo).max())
    mid = (lo + hi) / 2
    to_json = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))
    obj.data.transform(to_json @ Matrix.Scale(1 / unit, 4) @ Matrix.Translation(Vector((-mid).tolist())))
    m = OLD_MODELS[part]
    x, y, z, pitch, length, across, up, along = OLD_SHAPES[(fish, part)]
    a = math.radians(pitch)
    frame = Matrix(
        (
            (1, 0, 0, x),
            (0, math.cos(a), -math.sin(a), y),
            (0, math.sin(a), math.cos(a), z),
            (0, 0, 0, 1),
        )
    )
    scale = Matrix.Diagonal((length * across, length * up, length * along, 1))
    g2r = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    obj.data.transform(g2r @ frame @ scale @ Matrix.Translation(Vector(m["attach"]) * -1))
    tint = old_tint(part, fish)
    for slot in obj.material_slots:
        tree = slot.material.node_tree
        bsdf = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")
        multiply = tree.nodes.new("ShaderNodeMix")
        multiply.data_type = "RGBA"
        multiply.blend_type = "MULTIPLY"
        multiply.inputs[0].default_value = 1.0
        if bsdf.inputs["Base Color"].links:
            src = bsdf.inputs["Base Color"].links[0].from_socket
            tree.links.new(src, next(s for s in multiply.inputs if s.identifier == "A_Color"))
        next(s for s in multiply.inputs if s.identifier == "B_Color").default_value = (*tint, 1)
        tree.links.new(next(s for s in multiply.outputs if s.identifier == "Result_Color"), bsdf.inputs["Base Color"])
        bsdf.inputs["Alpha"].default_value = 1 - m["transparency"]
    return obj


def before():
    seats = json.loads(SEATS_JSON.read_text())
    cells = PREVIEWS / "_cells"
    cells.mkdir(parents=True, exist_ok=True)
    w, h = CELL
    for fish, part in OLD_SHAPES:
        scene, cam = scene_setup(False)
        body = load_fish_mesh(fish)
        old = load_old(fish, part)
        shoot(scene, cam, [body, old], VIEWS["side"], cells / f"before_{fish}_{part}_side.png", w, h)
        shoot(scene, cam, [body, old], VIEWS["three"], cells / f"before_{fish}_{part}_three.png", w, h)
        bpy.data.objects.remove(old, do_unlink=True)
        new = load_fit(fish, part, seats[fish][part])
        shoot(scene, cam, [body, new], VIEWS["side"], cells / f"after_{fish}_{part}_side.png", w, h)
        shoot(scene, cam, [body, new], VIEWS["three"], cells / f"after_{fish}_{part}_three.png", w, h)
        print(f"[parts_fit] before/after cells: {fish} {part}")


# --- A fish in mid-swim: the fish skinned by SwimWave's pose, the part riding its bone ------


def swim(spec: str):
    """Poses the rig at the top of a hard swim (FishAnimator: a = 0.44 boosting, SwimWave's
    yaw per joint, chain Head -> Spine1 -> ... -> Tail) and rigidly moves the part with its
    bone, as Cosmetics.follow does, at a few phases: does the root stay in the skin?"""
    seats = json.loads(SEATS_JSON.read_text())
    fish_name, _, want = spec.partition(":")
    parts = [want] if want else PARTS
    cells = PREVIEWS / "_cells"
    cells.mkdir(parents=True, exist_ok=True)
    w, h = 560, 380
    for part in parts:
        for phase in (0.0, 2.1, 4.2):
            scene, cam = scene_setup(True)
            before_objs = set(bpy.data.objects)
            bpy.ops.import_scene.fbx(filepath=str(FBX_DIR / f"{fish_name}.fbx"))
            new = [o for o in bpy.data.objects if o not in before_objs]
            obj = next(o for o in new if o.type == "MESH")
            arm = next(o for o in new if o.type == "ARMATURE")
            bone_names = [b.name for b in arm.data.bones]
            spine = [f"Spine{i}" for i in range(1, 12) if f"Spine{i}" in bone_names] + ["Tail"]
            n = len(spine)
            soften = (3 / n) ** 0.6
            amp = 0.44 * 1.6 * soften
            spread = 2.0 + 0.3 * max(n - 3, 0)
            arm.rotation_mode = "XYZ"
            scene.frame_set(1)
            bpy.context.view_layer.objects.active = arm
            for i, name in enumerate(spine, 1):
                t = i / n
                yaw = math.sin(phase - spread * t) * amp * (0.06 + 0.94 * t**1.9)
                pb = arm.pose.bones[name]
                pb.rotation_mode = "QUATERNION"
                # the turn is about the fish's up, put into the bone's own axes
                rest = (arm.matrix_world @ pb.bone.matrix_local).to_3x3()
                axis = rest.inverted() @ Vector((0, 0, 1))
                pb.rotation_quaternion = Quaternion(axis.normalized(), -yaw)
            bpy.context.view_layer.update()
            # Scale from the mesh's own box to the unit box, about its centre
            deps = bpy.context.evaluated_depsgraph_get()
            co = np.array([obj.matrix_world @ v.co for v in obj.data.vertices])
            lo, hi = co.min(0), co.max(0)
            ctr, sc = (lo + hi) / 2, 1 / (hi - lo)[1]
            root_tf = Matrix.Scale(sc, 4) @ Matrix.Translation(Vector((-ctr).tolist()))
            ev = obj.evaluated_get(deps)
            baked = bpy.data.meshes.new_from_object(ev)
            baked.transform(root_tf @ obj.matrix_world)
            body = bpy.data.objects.new("BodyPosed", baked)
            scene.collection.objects.link(body)
            pose = arm.pose.bones[seats[fish_name][part]["bone"]]
            rest_m = root_tf @ arm.matrix_world @ pose.bone.matrix_local
            now_m = root_tf @ arm.matrix_world @ pose.matrix
            rider = now_m @ rest_m.inverted()
            obj.hide_render = True
            fit = load_fit(fish_name, part, seats[fish_name][part])
            fit.data.transform(rider)
            path = cells / f"swim_{fish_name}_{part}_{phase}.png"
            shoot(scene, cam, [body, fit], VIEWS["three"], path, w, h)
    print(f"[parts_fit] swim cells: {spec}")


def write_luau(path: pathlib.Path):
    """Shared/PartFits, from seats.json: plain data."""
    seats = json.loads(SEATS_JSON.read_text())
    lines = [
        "--!strict",
        "-- Where each per-fish rolled part model sits on its fish (owner, 2026-11-03: parts must",
        "-- \"actual blend as a variant/mutation of that fish\"). Written by tools/props/parts_fit.py",
        "-- from assets/glb/parts/fit/seats.json; rebuild rather than edit by hand.",
        "--",
        "-- Each model (assets/glb/parts/fit/<Fish>_<PartId>.glb, ReplicatedStorage.PartModels.",
        "-- <Fish>_<PartId>) was authored in its fish's unit box, seated into that fish's own mesh.",
        "-- A MeshPart is centred on its mesh's box, so a seat is just that box in the fish's root",
        "-- space at 1 stud long (nose at z -0.5): `center` and `size`. `bone` is the bone it rides",
        "-- (Cosmetics.follow), `skin` the fish's natural colour at its root, `gem` and `gemSize` where a",
        "-- lure's crystal is (its middle; across and long).",
        "local PartFits = {}",
        "",
        "export type Seat = {",
        "\tbone: string,",
        "\tcenter: Vector3,",
        "\tsize: Vector3,",
        "\tskin: Color3,",
        "\tgem: Vector3?,",
        "\tgemSize: Vector2?,",
        "}",
        "",
        "PartFits.SEATS = {",
    ]
    for fish in FISH:
        lines.append(f"\t{fish} = {{")
        for part in PARTS:
            s = seats[fish][part]
            c, z, k = s["center"], s["size"], s["skin"]
            lines.append(f"\t\t{part} = {{")
            lines.append(f'\t\t\tbone = "{s["bone"]}",')
            lines.append(f"\t\t\tcenter = Vector3.new({c[0]}, {c[1]}, {c[2]}),")
            lines.append(f"\t\t\tsize = Vector3.new({z[0]}, {z[1]}, {z[2]}),")
            lines.append(f"\t\t\tskin = Color3.fromRGB({k[0]}, {k[1]}, {k[2]}),")
            if "gem" in s:
                g, w = s["gem"], s["gem_size"]
                lines.append(f"\t\t\tgem = Vector3.new({g[0]}, {g[1]}, {g[2]}),")
                lines.append(f"\t\t\tgemSize = Vector2.new({w[0]}, {w[1]}),")
            lines.append("\t\t},")
        lines.append("\t},")
    lines += [
        "} :: { [string]: { [string]: Seat } }",
        "",
        "-- The seat of a part on a fish model (Body's MeshPlan), and the name its model is filed",
        "-- under; nil for a body with no fitted models (a variant's own mesh)",
        "function PartFits.seat(meshPlan: string?, partId: string): (Seat?, string)",
        "\tlocal seats = if meshPlan then PartFits.SEATS[meshPlan] else nil",
        '\treturn if seats then seats[partId] else nil, `{meshPlan or ""}_{partId}`',
        "end",
        "",
        "return PartFits",
        "",
    ]
    path.write_text("\r\n".join(lines), newline="")


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :]
    mode = argv[0]
    args = [a for a in argv[1:] if not a.startswith("--")]
    draft = "--draft" in argv
    only = args[0] if args else ""
    if mode == "build":
        build_all(only)
    elif mode == "sheet":
        sheet(only, draft)
    elif mode == "closeups":
        closeups(only)
    elif mode == "before":
        before()
    elif mode == "swim":
        swim(only)
    elif mode == "luau":
        write_luau(pathlib.Path(only))
    else:
        raise SystemExit(f"unknown mode {mode}")


if __name__ == "__main__":
    main()
