"""Draws the rolled parts' models on every playable fish the way the game hangs them
(owner, 2026-10-28: the veil tail "doesnt make sense on the shark with that look. It
just looks slapped on. The parts need to shape to the fish and change their appearance
to fit"), as one contact sheet: a row per fish, a side view and a three-quarter view
per part.

    python3.11 tools/preview/parts_preview.py -- dims <fbx dir> <out.luau>
    python3.11 tools/preview/parts_preview.py -- colours <fbx dir> <parts dir>
    python3.11 tools/preview/parts_preview.py -- sheet <fits.json> <fbx dir> <parts dir> <out.png> [only]

(tools/preview/run_parts.sh runs dims, the Luau dump and sheet.) `dims` measures each
fish's unit box (the game's UnitW / UnitH: width and height over length) for
parts_dump.luau. `colours` prints Shared/PartFit's LOOKS (each fish model's back, belly
and tail-fin colours off its colour map) and each part's `own` (its colour map's
average outside its glow). `sheet` reads the dump: per body plan and part, the piece's
frame in the fish's unit box (Shared/PartFit's `at`), the scale of its model per axis
(length times stretch), its attach point, whether it hangs `reversed`, the colour its
SurfaceAppearance is multiplied by, its transparency and its glow's tint. `only` (e.g.
"Shark" or "Shark:VeilTail", or ":VeilTail" for one part on every fish) draws just
those, bigger. Environment: PARTS_VIEWS=side,three,behind,top picks the views (default
side,three), PARTS_FOCUS=1 frames each shot on the part where it meets the fish,
PARTS_CELL=WxH sizes a shot. Each shot is also kept in <out.png>_cells/.

Frames: the game's root space is x right, y up, z back (the nose at z -0.5, the fish
1 long); a species FBX imports into Blender head at -Y and up +Z, so a game point
(x, y, z) is drawn at (-x, z, y). A part GLB imports in parts_prep.py's frame (its
front +Y, up +Z), and parts.json's frame (the game's: x, y up, z back) is (x, z, -y)
of it; Cosmetics turns the "+Z" import back round, so the game places a model vertex
v (parts.json frame) at frame * (scale * (v - attach)), or a `reversed` one at
frame * (scale * (turned v - attach)), turned half round about y.
"""

import json
import math
import os
import pathlib
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :]
MODE = argv[0]

# Body plan -> the species model it draws (FishBuilder.meshTemplate)
MESHES = {
    "Nibbler": "Nibbler",
    "Cuda": "Cuda",
    "Puffer": "Puffer",
    "Eel": "MorayEel",
    "Shark": "ReefShark",
    "Angler": "Angler",
}
PARTS = ["AnglerLure", "NarwhalHorn", "SawSnout", "SailFin", "VeilTail"]
# game root space -> the drawing's space (the fish FBX's own Blender frame)
G2R = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def import_fish(fbx: pathlib.Path):
    """The fish's mesh at rest, centred on its box, 1 long; returns (object, w, h)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(fbx))
    new = [o for o in bpy.data.objects if o not in before]
    mesh = next(o for o in new if o.type == "MESH")
    world = mesh.matrix_world.copy()
    mesh.parent = None
    for m in list(mesh.modifiers):
        mesh.modifiers.remove(m)
    mesh.data.transform(world)
    mesh.matrix_world = Matrix.Identity(4)
    for o in new:
        if o is not mesh:
            bpy.data.objects.remove(o, do_unlink=True)
    co = np.array([v.co[:] for v in mesh.data.vertices])
    lo, hi = co.min(0), co.max(0)
    size = hi - lo
    mesh.data.transform(Matrix.Scale(1 / size[1], 4) @ Matrix.Translation(-Vector(((lo + hi) / 2).tolist())))
    return mesh, size[0] / size[1], size[2] / size[1]


if MODE == "dims":
    fbx_dir, out = pathlib.Path(argv[1]), pathlib.Path(argv[2])
    lines = ["-- UnitW / UnitH of each fish model (parts_preview.py dims)", "return {"]
    for plan, name in MESHES.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        _, w, h = import_fish(fbx_dir / f"{name}.fbx")
        lines.append(f"\t{plan} = {{ w = {w:.4f}, h = {h:.4f} }},")
    lines.append("}")
    out.write_text("\n".join(lines) + "\n")
    print(f"[parts_preview] dims -> {out}")
    sys.exit(0)


def face_colours(obj):
    """Each face's colour-map texel (at its UV middle), area, normal and middle."""
    mat = obj.material_slots[0].material
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")

    def pixels(socket):
        if not socket.links:
            return None
        img = socket.links[0].from_node.image
        w, h = img.size
        return np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[..., :3]

    colour, glow = pixels(bsdf.inputs["Base Color"]), pixels(bsdf.inputs["Emission Color"])
    h, w = colour.shape[:2]
    uv = obj.data.uv_layers.active.data
    rows = []
    for poly in obj.data.polygons:
        u = np.mean([uv[i].uv[:] for i in poly.loop_indices], 0)
        x, y = min(w - 1, int(u[0] % 1 * w)), min(h - 1, int(u[1] % 1 * h))
        lit = float(glow[y, x].max()) if glow is not None else 0.0
        rows.append((colour[y, x], poly.area, poly.normal[:], poly.center[:], lit))
    return rows


def mean_rgb(rows):
    if not rows:
        return "nil"
    c = np.array([r[0] for r in rows])
    a = np.array([r[1] for r in rows])
    r, g, b = np.round((c * a[:, None]).sum(0) / a.sum() * 255).astype(int)
    return f"Color3.fromRGB({r}, {g}, {b})"


if MODE == "colours":
    # PartFit.LOOKS (each fish model's back, belly and tail fin) and each part model's
    # `own` (its colour map's average, leaving out what its glow map lights)
    fbx_dir, part_dir = pathlib.Path(argv[1]), pathlib.Path(argv[2])
    for plan, name in MESHES.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        body, _, _ = import_fish(fbx_dir / f"{name}.fbx")
        rows = face_colours(body)
        # (Blender: head at -Y, up +Z; the fish is 1 long, so y + 0.5 runs nose to tail)
        middle = [r for r in rows if 0.15 < r[3][1] + 0.5 < 0.7]
        print(
            f"{plan}: back = {mean_rgb([r for r in middle if r[2][2] > 0.6])},"
            f" belly = {mean_rgb([r for r in middle if r[2][2] < -0.6])},"
            f" fin = {mean_rgb([r for r in rows if r[3][1] + 0.5 > 0.88])}"
        )
    for name in PARTS:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(part_dir / f"{name}.glb"))
        rows = [r for o in bpy.context.scene.objects if o.type == "MESH" for r in face_colours(o)]
        print(f"{name}: own = {mean_rgb([r for r in rows if r[4] < 0.15])}")
    sys.exit(0)

fits = json.loads(pathlib.Path(argv[1]).read_text())
FBX_DIR, PART_DIR, OUT = pathlib.Path(argv[2]), pathlib.Path(argv[3]), pathlib.Path(argv[4])
ONLY = argv[5] if len(argv) > 5 else ""
# PARTS_FOCUS=1 frames each shot on the part and where it meets the fish
FOCUS = os.environ.get("PARTS_FOCUS") == "1"

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 24 if not ONLY else 64
scene.cycles.use_denoising = True
scene.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("Water")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.10, 0.24, 0.30, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9


def sun(name, energy, rot, colour=(1, 1, 1)):
    data = bpy.data.lights.new(name, "SUN")
    data.energy = energy
    data.color = colour
    obj = bpy.data.objects.new(name, data)
    obj.rotation_euler = tuple(math.radians(a) for a in rot)
    scene.collection.objects.link(obj)


sun("Key", 3.2, (35, 10, 30))
sun("Fill", 1.0, (110, 0, -70), (0.7, 0.85, 1.0))
sun("Rim", 2.2, (-70, 0, 180), (0.55, 0.9, 1.0))

fish = {}
for plan, name in MESHES.items():
    obj, _, _ = import_fish(FBX_DIR / f"{name}.fbx")
    obj.name = plan
    obj.hide_render = True
    fish[plan] = obj


def sock(sockets, identifier: str):
    """A Mix node's socket by identifier (its float, vector and colour sockets share names)."""
    return next(x for x in sockets if x.identifier == identifier)


def import_part(name: str):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(PART_DIR / f"{name}.glb"))
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    for o in meshes:
        o.data.transform(o.matrix_world)
        o.parent = None
        o.matrix_world = Matrix.Identity(4)
    for o in new:
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    co = np.array([v.co[:] for v in obj.data.vertices])
    lo, hi = co.min(0), co.max(0)
    unit = float((hi - lo).max())
    mid = (lo + hi) / 2
    # Blender (x, y, z) -> parts.json (x, z, -y), in units of its longest side
    to_json = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))
    obj.data.transform(to_json @ Matrix.Scale(1 / unit, 4) @ Matrix.Translation(-Vector(mid.tolist())))
    # Its SurfaceAppearance.Color: the colour map multiplied by a tint
    for slot in obj.material_slots:
        tree = slot.material.node_tree
        bsdf = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")
        tint = tree.nodes.new("ShaderNodeMix")
        tint.data_type = "RGBA"
        tint.blend_type = "MULTIPLY"
        tint.inputs["Factor"].default_value = 1.0
        tint.name = "Tint"
        if bsdf.inputs["Base Color"].links:
            src = bsdf.inputs["Base Color"].links[0].from_socket
            tree.links.new(src, sock(tint.inputs, "A_Color"))
        tree.links.new(sock(tint.outputs, "Result_Color"), bsdf.inputs["Base Color"])
        glow = tree.nodes.new("ShaderNodeMix")
        glow.data_type = "RGBA"
        glow.blend_type = "MULTIPLY"
        glow.inputs["Factor"].default_value = 1.0
        glow.name = "GlowTint"
        # (only a model with a glow map glows: an unlinked Emission Color is white)
        if bsdf.inputs["Emission Color"].links:
            src = bsdf.inputs["Emission Color"].links[0].from_socket
            tree.links.new(src, sock(glow.inputs, "A_Color"))
            tree.links.new(sock(glow.outputs, "Result_Color"), bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = 1.0
    obj.name = name
    obj.hide_render = True
    return obj


parts = {name: import_part(name) for name in PARTS if (PART_DIR / f"{name}.glb").exists()}


def place(obj, rec):
    f = rec["frame"]  # 12 numbers: position, then the right, up and back columns
    p, r, u, b = f[0:3], f[3:6], f[6:9], f[9:12]
    frame = Matrix(
        (
            (r[0], u[0], b[0], p[0]),
            (r[1], u[1], b[1], p[1]),
            (r[2], u[2], b[2], p[2]),
            (0, 0, 0, 1),
        )
    )
    s = rec["scale"]
    scale = Matrix(((s[0], 0, 0, 0), (0, s[1], 0, 0), (0, 0, s[2], 0), (0, 0, 0, 1)))
    # (a `reversed` model hangs turned half round about its up axis, attach and all)
    turn = Matrix.Rotation(math.pi, 4, "Y") if rec.get("reversed") else Matrix.Identity(4)
    obj.matrix_world = G2R @ frame @ scale @ Matrix.Translation(-Vector(rec["attach"])) @ turn
    for slot in obj.material_slots:
        tree = slot.material.node_tree
        sock(tree.nodes["Tint"].inputs, "B_Color").default_value = (*rec["tint"], 1)
        glow = rec.get("glow") or [1, 1, 1]
        sock(tree.nodes["GlowTint"].inputs, "B_Color").default_value = (*glow, 1)
        bsdf = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Alpha"].default_value = 1 - rec.get("transparency", 0)


cam_data = bpy.data.cameras.new("Cam")
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam


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


ALL_VIEWS = {
    # the fish's right side, head on the left
    "side": Vector((1.0, 0.0, 0.0)),
    # from in front, above and to the side
    "three": Vector((0.9, -0.85, 0.55)),
    # from behind and above, where the game's camera follows the player's own fish
    "behind": Vector((0.35, 1.0, 0.45)),
    # straight down, head toward the bottom of the picture
    "top": Vector((0.0, 0.001, 1.0)),
}
# PARTS_VIEWS=side,behind picks the views (default: side and three-quarter)
VIEWS = {v: ALL_VIEWS[v] for v in os.environ.get("PARTS_VIEWS", "side,three").split(",")}


def shoot(objs, view: str, path: pathlib.Path, w: int, h: int, focus=None):
    lo, hi = bounds(objs)
    if focus is not None:
        # framed on the part and where it meets the fish
        flo, fhi = bounds([focus])
        middle, half = (flo + fhi) / 2, (fhi - flo) / 2 * 1.5 + 0.06
        lo, hi = np.maximum(lo, middle - half), np.minimum(hi, middle + half)
    mid = Vector(((lo + hi) / 2).tolist())
    direction = VIEWS[view].normalized()
    cam.location = mid + direction * 6
    cam.rotation_euler = (mid - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam_data.type = "ORTHO"
    bpy.context.view_layer.update()
    # fit the box seen from this direction
    inv = cam.matrix_world.inverted()
    corners = [Vector((x, y, z)) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]
    local = np.array([(inv @ c)[:2] for c in corners])
    span_x, span_y = np.ptp(local[:, 0]), np.ptp(local[:, 1])
    cam_data.ortho_scale = max(span_x, span_y * w / h) * 1.12
    scene.render.resolution_x, scene.render.resolution_y = w, h
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


cells = pathlib.Path(str(OUT) + "_cells")
cells.mkdir(parents=True, exist_ok=True)
want_plan, _, want_part = ONLY.partition(":")
plans = [p for p in MESHES if not want_plan or p == want_plan]
part_ids = [p for p in PARTS if p in parts and (not want_part or p == want_part)]
W, H = (360, 250) if not ONLY else (900, 620)
if os.environ.get("PARTS_CELL"):  # e.g. 600x420
    W, H = (int(v) for v in os.environ["PARTS_CELL"].split("x"))
for plan in plans:
    body = fish[plan]
    for pid in part_ids:
        rec = fits["plans"][plan].get(pid)
        if rec is None:
            continue
        obj = parts[pid]
        place(obj, rec)
        body.hide_render = False
        obj.hide_render = False
        for view in VIEWS:
            shoot([body, obj], view, cells / f"{plan}_{pid}_{view}.png", W, H, obj if FOCUS else None)
        obj.hide_render = True
        body.hide_render = True

# The sheet: a row per fish, its views side by side under each part
NV = len(VIEWS)
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

LABEL_W, HEAD_H = 120, 34
sheet = Image.new("RGB", (LABEL_W + W * NV * len(part_ids), HEAD_H + H * len(plans)), (16, 24, 32))
draw = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("DejaVuSans-Bold.ttf", 18)
except OSError:
    font = ImageFont.load_default()
title = fits.get("title", "")
for j, pid in enumerate(part_ids):
    draw.text((LABEL_W + j * W * NV + 10, 8), pid, fill=(240, 220, 140), font=font)
for i, plan in enumerate(plans):
    draw.text((10, HEAD_H + i * H + H // 2 - 10), plan, fill=(220, 236, 240), font=font)
    for j, pid in enumerate(part_ids):
        for k, view in enumerate(VIEWS):
            cell = cells / f"{plan}_{pid}_{view}.png"
            if cell.exists():
                sheet.paste(Image.open(cell).convert("RGB"), (LABEL_W + (j * NV + k) * W, HEAD_H + i * H))
if title:
    draw.text((sheet.width - 10 - draw.textlength(title, font=font), 8), title, fill=(160, 190, 200), font=font)
sheet.save(OUT)
print(f"[parts_preview] {len(plans)} fish x {len(part_ids)} parts -> {OUT}")
