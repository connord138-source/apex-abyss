"""Renders the ambient sea life's poses (ambient_dump.luau's JSON) in Blender: each
rigged model (assets/fbx/ambient/<Name>.fbx) posed bone by bone the way
AmbientLifeController turns its bones, beside its part-built stand-in built from the
same pose's parts. Run by run_ambient.sh.

    python3.11 ambient_render.py <poses.json> <out_dir> <fbx_dir> [Name ...]

One sheet per creature, <out_dir>/<Name>.png: a row per moment (labelled), the top,
side (head left) and three-quarter views, model left, stand-in right in each. Roblox
axes (X right, Y up, -Z ahead) become Blender's the way rig_ambient.py's export does:
(x, y, z) -> (-x, z, y), head at -Y, up +Z.
"""

from __future__ import annotations

import json
import math
import os
import sys

import bpy  # (first: bmesh comes with it)
import bmesh  # noqa: E402
from mathutils import Matrix, Vector

POSES, OUT, FBX = sys.argv[1], sys.argv[2], sys.argv[3]
ONLY = set(sys.argv[4:])
M = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))
W, H = 520, 340

data = json.load(open(POSES))


def rot(cols) -> Matrix:
    """A Roblox rotation (right, up, back columns) in Blender's axes."""
    r = Matrix((cols[0], cols[1], cols[2])).transposed()
    return M @ r @ M.transposed()


def pos(p) -> Vector:
    return M @ Vector(p)


def to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def material(name: str, colour) -> bpy.types.Material:
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*[to_linear(c) for c in colour], 1)
    bsdf.inputs["Roughness"].default_value = 0.65
    return mat


# Unit shapes in Roblox's own local axes (a part's size scales them)
BOX = [(x, y, z) for x in (-0.5, 0.5) for y in (-0.5, 0.5) for z in (-0.5, 0.5)]
BOX_FACES = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
# A WedgePart: full bottom and back (+Z), the slope from the back's top edge down to the
# front's bottom edge
WEDGE = [(-0.5, -0.5, -0.5), (0.5, -0.5, -0.5), (-0.5, -0.5, 0.5), (0.5, -0.5, 0.5), (-0.5, 0.5, 0.5), (0.5, 0.5, 0.5)]
WEDGE_FACES = [(0, 1, 3, 2), (2, 3, 5, 4), (0, 2, 4), (1, 5, 3), (0, 4, 5, 1)]


def shape(kind: str):
    if kind == "block":
        return BOX, BOX_FACES
    if kind == "wedge":
        return WEDGE, WEDGE_FACES
    # ball and cylinder (along X): rings
    verts, faces = [], []
    n, rings = 12, 7
    if kind == "cyl":
        for x in (-0.5, 0.5):
            for k in range(n):
                a = 2 * math.pi * k / n
                verts.append((x, 0.5 * math.cos(a), 0.5 * math.sin(a)))
        faces = [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
        faces += [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
        return verts, faces
    for i in range(rings + 1):
        th = math.pi * i / rings
        for k in range(n):
            a = 2 * math.pi * k / n
            verts.append((0.5 * math.sin(th) * math.cos(a), 0.5 * math.cos(th), 0.5 * math.sin(th) * math.sin(a)))
    for i in range(rings):
        for k in range(n):
            faces.append((i * n + k, i * n + (k + 1) % n, (i + 1) * n + (k + 1) % n, (i + 1) * n + k))
    return verts, faces


def build_stand_in(parts, look, scale: float, name: str) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    roles = sorted({p["role"] for p in parts})
    mats = [material(f"{name}_{r}", look.get(r, (0.8, 0.0, 0.8))) for r in roles]
    for p in parts:
        verts, faces = shape(p["shape"])
        cf = p["cf"]
        origin = Vector(cf[0])
        r, u, b = Vector(cf[1]), Vector(cf[2]), Vector(cf[3])
        size = p["size"]
        made = []
        for v in verts:
            local = r * (v[0] * size[0]) + u * (v[1] * size[1]) + b * (v[2] * size[2])
            made.append(bm.verts.new(pos(origin + local) * scale))
        for f in faces:
            try:
                face = bm.faces.new([made[i] for i in f])
                face.material_index = roles.index(p["role"])
            except ValueError:
                pass
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    for m in mats:
        obj.data.materials.append(m)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def look_at(cam, eye: Vector, target: Vector, up: Vector):
    f = (target - eye).normalized()
    r = f.cross(up).normalized()
    u = r.cross(f)
    cam.matrix_world = Matrix.Translation(eye) @ Matrix(((r.x, u.x, -f.x), (r.y, u.y, -f.y), (r.z, u.z, -f.z))).to_4x4()
    return r, u


def render(creature: dict):
    name = creature["name"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 10
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = W, H
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.32, 0.5, 0.55, 1)
    bg.inputs["Strength"].default_value = 0.9
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 3.2
    so = bpy.data.objects.new("Sun", sun)
    so.rotation_euler = (math.radians(35), math.radians(-20), math.radians(25))
    scene.collection.objects.link(so)
    look = {k: tuple(v) for k, v in creature["look"].items()}

    # The model, if it's been rigged
    arm = body = None
    path = os.path.join(FBX, f"{name}.fbx")
    extent = 1.0
    if os.path.exists(path):
        bpy.ops.import_scene.fbx(filepath=path)
        arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
        body = next((o for o in bpy.data.objects if o.type == "MESH"), None)
    if body is not None:
        corners = [body.matrix_world @ Vector(c) for c in body.bound_box]
        lo = Vector([min(c[i] for c in corners) for i in range(3)])
        hi = Vector([max(c[i] for c in corners) for i in range(3)])
        dims = hi - lo
        # The measure: Roblox X is Blender X, Roblox Z is Blender Y
        extent = dims.x if creature["measure"] == "X" else dims.y
        arm_base = arm.matrix_world.copy()
    size = max(extent * 1.25, 0.5)
    cam_data = bpy.data.cameras.new("C")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("C", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    tiles = []
    for si, sample in enumerate(creature["samples"]):
        lift = sample["lift"]
        lift_m = Matrix.Translation(pos(lift[0]) * extent) @ rot(lift[1:]).to_4x4()
        if arm is not None:
            bpy.context.view_layer.objects.active = arm
            for pb in arm.pose.bones:
                q = sample["pose"].get(pb.name)
                if q is None:
                    pb.matrix_basis = Matrix.Identity(4)
                    continue
                qb = rot(q[1:])
                rest = (arm_base.to_3x3().normalized() @ pb.bone.matrix_local.to_3x3()).normalized()
                pb.matrix_basis = (rest.inverted() @ qb @ rest).to_4x4()
        stand = build_stand_in(sample["parts"], look, extent, f"{name}_stand_{si}")
        for vi, (eye_dir, up) in enumerate(
            (
                (Vector((0, 0, 1)), Vector((0, -1, 0))),  # top, head up the picture
                (Vector((1, 0, 0)), Vector((0, 0, 1))),  # side, from its left: head on the left
                (Vector((0.55, -0.7, 0.5)).normalized(), Vector((0, 0, 1))),  # three-quarter, front left
            )
        ):
            right, _ = look_at(cam, eye_dir * size * 6, Vector((0, 0, 0)), up)
            spread = right * extent * 0.62
            if arm is not None:
                arm.matrix_world = Matrix.Translation(-spread) @ lift_m @ arm_base
                stand.matrix_world = Matrix.Translation(spread) @ lift_m
            else:
                stand.matrix_world = lift_m
            cam_data.ortho_scale = extent * 2.45
            path_png = os.path.join(OUT, f"_{name}_{si}_{vi}.png")
            scene.render.filepath = path_png
            bpy.ops.render.render(write_still=True)
            tiles.append((si, vi, path_png))
        bpy.data.objects.remove(stand)
    # The sheet
    from PIL import Image, ImageDraw

    rows = len(creature["samples"])
    sheet = Image.new("RGB", (W * 3, (H + 22) * rows + 30), (24, 28, 32))
    draw = ImageDraw.Draw(sheet)
    draw.text((8, 8), f"{name}: model (left) and part-built stand-in (right); top, side (head left), three-quarter", fill=(230, 230, 230))
    for si, vi, p in tiles:
        y = 30 + si * (H + 22)
        sheet.paste(Image.open(p).convert("RGB"), (vi * W, y + 22))
        if vi == 0:
            draw.text((8, y + 4), creature["samples"][si]["label"], fill=(240, 220, 120))
        os.remove(p)
    sheet.save(os.path.join(OUT, f"{name}.png"))
    print("[ambient_render] wrote", os.path.join(OUT, f"{name}.png"), "model" if arm else "stand-in only")


for creature in data:
    if ONLY and creature["name"] not in ONLY:
        continue
    render(creature)
