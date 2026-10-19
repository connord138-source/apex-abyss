"""Rigs a Tripo fish GLB with a spine for the procedural swim, and exports an FBX.

    <bpy python> tools/blender/rig_fish.py <in.glb> <out.fbx> [--flip] [--segments N] [--head F] [--jaw] [--fins]
    <bpy python> tools/blender/rig_fish.py <in.glb> <out.glb> --static   (squared up, no rig)

The fish is squared up (its long axis becomes the body axis), the head end is found
(the deep, wide end; a tail fin is thin), and a chain of bones runs head to tail:

    Root -> Head -> Spine1 .. SpineN -> Tail

Every vertex is weighted to the two bones nearest along the body with a smooth
hand-over, so the client (FishAnimator) can wave the spine with a travelling sine
and swing the head and tail. Fins and the lure follow whatever bone they sit on.

Blender imports glTF as Z-up; the export bakes the conversion back to Y-up (Roblox),
with the fish facing -Z, the way FishBuilder's part bodies face. `--flip` swaps the
head guess when it's wrong (check tools/blender/fish_check.py's renders).

`--jaw` adds a Jaw bone (a child of Head) hinged at the corner of the mouth, so the
lower jaw opens and snaps (owner, 2026-10-19: the Megalodon's "mouth doesn't move").
The mouth is found from the mesh itself: rays cast up through the head find the
cavity between the lower jaw and the palate (Tripo models the mouth a little open),
its back end is the hinge, and the vertices under the cavity's middle line are the
lower jaw. The jaw's weights are a harmonic field solved along the welded surface
(1 on the chin, 0 on the snout, the cheeks and everything behind the hinge), so the
hand-over runs round the corners of the mouth and through the throat, every tooth
goes with the gum it grows from, and nothing tears. Needs scipy.

`--fins` adds FinL and FinR (children of the spine bone each grows from) for the
pectoral fins: the blades that stand out past the body's flank in its front half,
below its middle, weighted the same way (1 on the outer blade, 0 on the flank).
FinL is the fish's left (Blender +X, Roblox -X). PredatorController angles them.
Clean on the Megalodon's broad pectorals; the Reef Shark's long swept-back ones
kinked and pulled its gill slits out under a tilt (2026-10-19), so the species
models carry --jaw only. Check every rig with tools/blender/jaw_check.py.

Both only add weight to new bones: the spine's weights are scaled, never moved, and
the mesh, its UVs and its textures are exported exactly as before.
"""
import math
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
IN_PATH, OUT_PATH = argv[0], argv[1]
FLIP = "--flip" in argv
SEGMENTS = int(argv[argv.index("--segments") + 1]) if "--segments" in argv else 5
# --static: export a squared-up GLB with no armature (prey fish, which the client
# moves whole), instead of the rigged FBX
STATIC = "--static" in argv
# --head F: the share of the length the stiff Head bone covers (default 0.28). A long
# ribbon body with a small head (the Oarfish) takes less, so more of it waves.
HEAD = float(argv[argv.index("--head") + 1]) if "--head" in argv else 0.28
# --jaw: a Jaw bone for the lower jaw; --fins: FinL/FinR for the pectoral fins
JAW = "--jaw" in argv
FINS = "--fins" in argv


def log(*args):
    print("[rig_fish]", *args)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=IN_PATH)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
if not meshes:
    sys.exit("no mesh in " + IN_PATH)
# One body: join if Tripo split it
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

# ---------- square up: the body axis becomes +Y (Blender), length along it ----------
co = np.array([v.co[:] for v in body.data.vertices])
centre = (co.max(0) + co.min(0)) / 2
co -= centre
# Principal axis in the horizontal plane (fish swim level; the lure or a tall dorsal
# fin would otherwise tilt the guess)
flat = co[:, :2]
cov = np.cov(flat.T)
evals, evecs = np.linalg.eigh(cov)
axis = evecs[:, np.argmax(evals)]
angle = math.atan2(axis[0], axis[1])  # rotate so the axis lands on +Y
rot = Matrix.Rotation(angle, 4, "Z")
body.matrix_world = rot @ Matrix.Translation(-Vector(centre)) @ body.matrix_world
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
co = np.array([v.co[:] for v in body.data.vertices])

# ---------- head end: the deep, wide quarter (a tail fin is a thin blade) ----------
length = co[:, 1].max() - co[:, 1].min()
y0 = co[:, 1].min()


def girth(lo, hi):
    band = co[(co[:, 1] >= y0 + lo * length) & (co[:, 1] < y0 + hi * length)]
    if len(band) < 8:
        return 0.0
    return (band[:, 0].max() - band[:, 0].min()) * (band[:, 2].max() - band[:, 2].min())


# Compare the two ends' bulk a little in from the tips (snouts and tail tips are both thin)
head_at_low = girth(0.08, 0.3) > girth(0.7, 0.92)
if FLIP:
    head_at_low = not head_at_low
# Where the head must end up so the export faces -Z in Roblox: the FBX exporter maps
# Blender's -Y (its forward) onto the forward axis we give it (-Z); the glTF exporter
# maps Blender +Y onto -Z. So rigged fish keep the head at -Y, static ones at +Y.
want_low = not STATIC
if head_at_low != want_low:
    body.matrix_world = Matrix.Rotation(math.pi, 4, "Z") @ body.matrix_world
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    co = np.array([v.co[:] for v in body.data.vertices])
log("head at", "-Y" if want_low else "+Y", "length", round(length, 3), "flip" if FLIP else "")

# Stand the body on the ground plane's centre (the root sits at the body's middle)
co = np.array([v.co[:] for v in body.data.vertices])
y_min, y_max = co[:, 1].min(), co[:, 1].max()
z_mid = (co[:, 2].max() + co[:, 2].min()) / 2
x_mid = (co[:, 0].max() + co[:, 0].min()) / 2
body.matrix_world = Matrix.Translation(Vector((-x_mid, -(y_min + y_max) / 2, -z_mid))) @ body.matrix_world
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
co = np.array([v.co[:] for v in body.data.vertices])
y_min, y_max = co[:, 1].min(), co[:, 1].max()
length = y_max - y_min

if STATIC:
    # Face -Z in glTF (Y-up): Blender +Y (the head) -> glTF -Z, which the exporter does
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT_PATH, export_format="GLB", use_selection=True, export_yup=True)
    log("wrote static", OUT_PATH)
    sys.exit(0)

# ---------- the welded surface (for the jaw's and fins' harmonic weights) ----------
def welded():
    """Each vertex's index on the welded surface (UV seams split Tripo's vertices),
    the welded positions, and the graph Laplacian over its edges (1/length weights)."""
    from scipy.sparse import coo_matrix, diags

    key = np.round(co / (length * 1e-5)).astype(np.int64)
    _, weld = np.unique(key, axis=0, return_inverse=True)
    weld = weld.ravel()
    n = int(weld.max()) + 1
    at = np.zeros((n, 3))
    at[weld] = co
    pairs = set()
    for p in body.data.polygons:
        vs = [int(weld[i]) for i in p.vertices]
        for a, b in zip(vs, vs[1:] + vs[:1]):
            if a != b:
                pairs.add((min(a, b), max(a, b)))
    pairs = np.array(sorted(pairs))
    lengths = np.linalg.norm(at[pairs[:, 0]] - at[pairs[:, 1]], axis=1)
    w = 1.0 / np.maximum(lengths, length * 1e-4)
    rows = np.concatenate([pairs[:, 0], pairs[:, 1]])
    cols = np.concatenate([pairs[:, 1], pairs[:, 0]])
    W = coo_matrix((np.concatenate([w, w]), (rows, cols)), shape=(n, n)).tocsr()
    lap = diags(np.asarray(W.sum(axis=1)).ravel()) - W
    return weld, at, lap.tocsr()


def harmonic(lap, fixed, values):
    """Solves the Laplace equation on the surface: `fixed` (bool per welded vertex)
    hold `values`, every other vertex takes the average of its neighbours."""
    from scipy.sparse.linalg import spsolve

    free = ~fixed
    out = np.array(values, dtype=float)
    if free.any():
        A = lap[free][:, free]
        b = -lap[free][:, fixed] @ out[fixed]
        out[free] = spsolve(A.tocsc(), b)
    return np.clip(out, 0.0, 1.0)


def smooth01(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def find_mouth():
    """The mouth from the mesh: rays cast straight up through the head at the
    midline find the cavity between the lower jaw's top and the palate (four or more
    crossings where the head is solid has two). Returns the cavity's middle line
    [(y, z, gap)] front to back, or None when there's no mouth to open."""
    from mathutils.bvhtree import BVHTree

    verts = [v.co.copy() for v in body.data.vertices]
    bvh = BVHTree.FromPolygons(verts, [p.vertices[:] for p in body.data.polygons])
    bottom = co[:, 2].min() - length
    up = Vector((0, 0, 1))
    found_at = []
    for frac in np.arange(0.0, 0.32, 0.005):
        y = y_min + frac * length
        found = []
        for x in (0.0, 0.012 * length, -0.012 * length):
            hits = []
            origin = Vector((x, y, bottom))
            for _ in range(16):
                loc, _n, _i, _d = bvh.ray_cast(origin, up, 4 * length)
                if loc is None:
                    break
                hits.append(loc.z)
                origin = loc + up * (length * 1e-5)
            if len(hits) >= 4:
                # Air between the first solid (the lower jaw) and the last (the snout):
                # the lowest air's floor to the highest air's roof (teeth may split it)
                floor, roof = hits[1], hits[-2]
                if roof - floor > length * 0.002:
                    found.append((floor, roof))
        if found:
            floor = float(np.mean([f for f, _ in found]))
            roof = float(np.mean([r for _, r in found]))
            found_at.append((y, (floor + roof) / 2, roof - floor))
    # Runs of stations (a few misses allowed: teeth fill the cavity here and there);
    # the mouth is the run holding the most open water (a nostril pit or a gill slit
    # is a short, thin one)
    runs = []
    for entry in found_at:
        if runs and entry[0] - runs[-1][-1][0] <= 0.025 * length:
            runs[-1].append(entry)
        else:
            runs.append([entry])
    runs = [r for r in runs if len(r) >= 3]
    if not runs:
        return None
    return max(runs, key=lambda r: sum(g for _, _, g in r))


# ---------- bones ----------
# Spine stations head -> tail along Y (head at y_min). The head bone covers the front
# 28% (HEAD), the tail bone the last 14% (the fin), spine segments share the middle.
stations = [y_min, y_min + HEAD * length]
mid_len = (0.86 - HEAD) * length
for i in range(1, SEGMENTS + 1):
    stations.append(y_min + HEAD * length + mid_len * i / SEGMENTS)
stations.append(y_max)
names = ["Head"] + [f"Spine{i}" for i in range(1, SEGMENTS + 1)] + ["Tail"]

# The spine's height: follow the body's vertical middle in each stretch
def mid_z(lo, hi):
    band = co[(co[:, 1] >= min(lo, hi)) & (co[:, 1] <= max(lo, hi))]
    return float((band[:, 2].max() + band[:, 2].min()) / 2) if len(band) else 0.0


# ---------- the jaw: where it hinges, and how much of each vertex it carries ----------
jaw = None  # (hinge, tip, weight per vertex)
if JAW:
    mouth = find_mouth()
    if mouth is None:
        log("no mouth cavity found: no Jaw bone")
    else:
        my = np.array([m[0] for m in mouth])
        mz = np.array([m[1] for m in mouth])
        mg = np.array([m[2] for m in mouth])
        # The line a touch smoothed (teeth make the cavity's edges jumpy)
        if len(mz) >= 5:
            mz = np.convolve(np.pad(mz, 2, mode="edge"), np.ones(5) / 5, mode="valid")
        y_front, y_back = float(my[0]), float(my[-1])
        span = max(y_back - y_front, length * 0.02)
        hinge = (0.0, y_back + 0.01 * length, float(mz[-1]))
        tip = (0.0, y_front, float(mz[0]))
        weld, at, lap = welded()
        ay, az = at[:, 1], at[:, 2]
        line = np.interp(ay, my, mz)
        gap = max(float(np.median(mg)), length * 0.004)
        band = max(0.3 * gap, length * 0.006)
        # Sure of these: the chin and the jaw's front two thirds under the line are
        # the jaw; the snout, the cheeks over the line and everything a little way
        # behind the hinge are the head. The rest (the lips, the corners of the mouth,
        # its floor and the throat) is solved.
        chin = (az < line - band) & (ay < y_back - 0.35 * span) & (ay > y_front - 0.15 * length)
        skull = (az > line + band) | (ay > hinge[1] + 0.06 * length)
        skull &= ~chin
        field = harmonic(lap, chin | skull, np.where(chin, 1.0, 0.0))
        # Rigid where it's nearly all jaw or all head, a soft hand-over between
        weight = smooth01((field - 0.15) / 0.7)
        jaw = (hinge, tip, weight[weld])
        log(
            "mouth from",
            round((y_front - y_min) / length, 3),
            "to",
            round((y_back - y_min) / length, 3),
            "of the length, gap",
            round(gap / length, 4),
            "· jaw carries",
            int((weight > 0.5).sum()),
            "of",
            len(weight),
            "welded vertices",
        )


# ---------- the pectoral fins: which blades stand out past the flank ----------
fin_plans = []  # (name, root, tip, weight per vertex)
if FINS:
    weld, at, lap = welded()
    ax, ay, az = at[:, 0], at[:, 1], at[:, 2]
    # The body's own half-width and middle height along its length, from its upper
    # half (no pectoral fin there; the dorsal fin is thin)
    slices = 60
    edges = np.linspace(y_min, y_max, slices + 1)
    core = np.full(slices, np.nan)
    middle = np.full(slices, np.nan)
    for k in range(slices):
        inside = (co[:, 1] >= edges[k]) & (co[:, 1] <= edges[k + 1])
        if inside.sum() < 6:
            continue
        zs = co[inside, 2]
        middle[k] = float(np.median(zs))
        upper = inside & (co[:, 2] >= middle[k])
        core[k] = float(np.abs(co[upper if upper.any() else inside, 0]).max())
    centres_y = (edges[:-1] + edges[1:]) / 2
    ok = ~np.isnan(core)
    core_at = np.interp(ay, centres_y[ok], core[ok])
    middle_at = np.interp(ay, centres_y[ok], middle[ok])
    out = np.abs(ax) - core_at
    front = (ay > y_min + 0.12 * length) & (ay < y_min + 0.6 * length) & (az < middle_at + 0.02 * length)
    for name, side in (("FinL", 1.0), ("FinR", -1.0)):
        # (Blender +X is the fish's left once exported: Roblox -X)
        mine = front & (ax * side > 0) & (out > 0)
        if not mine.any():
            log(name, "no pectoral fin found")
            continue
        reach = float(out[mine].max())
        if reach < 0.03 * length:
            log(name, "no pectoral fin found (nothing stands out past the flank)")
            continue
        tip_index = int(np.argmax(np.where(mine, out, -np.inf)))
        tip_y = float(ay[tip_index])
        sure = mine & (out > 0.3 * reach) & (np.abs(ay - tip_y) < 0.15 * length)
        flank = (np.abs(ax) < core_at * 0.95) | (az > middle_at + 0.02 * length) | (np.abs(ay - tip_y) > 0.22 * length)
        # (and the flank's own relief round the fin's root: gill slits stood out as a
        # spike when they went partly with the fin)
        flank |= (out < 0.015 * length) & (az > middle_at - 0.04 * length)
        flank |= ax * side <= 0
        flank &= ~sure
        field = harmonic(lap, sure | flank, np.where(sure, 1.0, 0.0))
        weight = smooth01((field - 0.1) / 0.75)
        joint = (field > 0.3) & (field < 0.7)
        if not joint.any():
            joint = sure
        root = at[joint].mean(axis=0)
        fin_plans.append((name, tuple(map(float, root)), tuple(map(float, at[tip_index])), weight[weld]))
        log(
            name,
            "pectoral at",
            round((tip_y - y_min) / length, 3),
            "of the length, reaching",
            round(reach / length, 3),
            "past the flank ·",
            int((weight > 0.5).sum()),
            "welded vertices",
        )


bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
arm = bpy.context.active_object
arm.name = "Armature"
eb = arm.data.edit_bones
for b in list(eb):
    eb.remove(b)


def bone(name, head, tail, parent=None, connect=False):
    b = eb.new(name)
    b.head = Vector(head)
    b.tail = Vector(tail)
    if parent:
        b.parent = eb[parent]
        b.use_connect = connect
    return b


bone("Root", (0, 0, 0), (0, 0, 0.1 * length))
segments = {}
parent = "Root"
for i, name in enumerate(names):
    a, b = stations[i], stations[i + 1]
    z = mid_z(a, b)
    # Bones point tailward: head at the front station, tail at the back one
    bone(name, (0, a, z), (0, b, z), parent, connect=(i > 0))
    segments[name] = (a, b)
    parent = name
if jaw is not None:
    # Hinged at the corner of the mouth, pointing to the chin
    bone("Jaw", jaw[0], jaw[1], "Head")
for name, root, tip, _ in fin_plans:
    # On the spine bone it grows from, pointing out to its tip
    carrier = next((n for n in names if segments[n][0] <= root[1] <= segments[n][1]), "Head")
    bone(name, root, tip, carrier)
bpy.ops.object.mode_set(mode="OBJECT")

# ---------- skinning: two nearest stations along the body, smooth hand-over ----------
centres = {name: (a + b) / 2 for name, (a, b) in segments.items()}
order = names
groups = {name: body.vertex_groups.new(name=name) for name in order}
ys = co[:, 1]
cs = np.array([centres[n] for n in order])
for i in range(len(co)):
    y = ys[i]
    # Which two bone centres bracket this vertex
    j = int(np.argmin(np.abs(cs - y)))
    k = j + 1 if (j + 1 < len(cs) and y > cs[j]) else j - 1
    if k < 0 or k >= len(cs):
        groups[order[j]].add([i], 1.0, "REPLACE")
        continue
    span = abs(cs[j] - cs[k])
    t = abs(y - cs[j]) / span if span > 1e-6 else 0.0
    t = min(max(t, 0.0), 0.5)  # halfway at the boundary between the two
    # Smoothstep for a soft bend
    w = t * t * (3 - 2 * t)
    groups[order[j]].add([i], float(1 - w), "REPLACE")
    if w > 0.001:
        groups[order[k]].add([i], float(w), "REPLACE")


def hand_to(name, share):
    """Gives bone `name` `share` (0..1 per vertex) of each vertex, scaling the
    weights it had down to make room."""
    group = body.vertex_groups.new(name=name)
    for i, v in enumerate(body.data.vertices):
        s = float(share[i])
        if s <= 0.001:
            continue
        for g in v.groups:
            g.weight *= 1 - s
        group.add([i], s, "REPLACE")


extra = []
if jaw is not None:
    hand_to("Jaw", jaw[2])
    extra.append("Jaw")
for name, _, _, weight in fin_plans:
    hand_to(name, weight)
    extra.append(name)

mod = body.modifiers.new("Armature", "ARMATURE")
mod.object = arm
body.parent = arm

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
    # Bake the Z-up -> Y-up conversion into the mesh and bones (Studio drops a root
    # transform on skinned meshes; Hatch & Snatch's creatures once came in on their heads)
    bake_space_transform=True,
    apply_scale_options="FBX_SCALE_ALL",
    path_mode="COPY",
    embed_textures=True,
)
log("wrote", OUT_PATH, "bones", ", ".join(["Root"] + names + extra))
