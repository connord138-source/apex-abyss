"""Renders the hub cavern's Terrain fill ops (from run_cave.sh) in Blender.

    EGL_PLATFORM=surfaceless <bpy python> cave_render.py -- <dir with cave_ops.jsonl>

The ops are rasterized into a voxel grid the way Roblox Terrain fills do (later ops
overwrite earlier ones), turned into a mesh with marching cubes, colored by material,
and rendered from inside (plaza, a den doorway, a tunnel mouth), as a cutaway from
above, and from outside. A rough look only: Roblox's terrain textures become flat
colors. Needs numpy and scikit-image in Blender's Python.
"""
import json
import math
import os
import sys

import bpy
import mathutils
import numpy as np
from skimage import measure

argv = sys.argv[sys.argv.index("--") + 1 :]
DIR = os.path.abspath(argv[0])
# --world: the whole seafloor (run_world.sh) at a coarse cell, from above and the sides
WORLD = "--world" in argv
CELL = 8.0 if WORLD else 2.0  # studs per voxel (Roblox uses 4; finer shows the shape better)
BOUNDS = ((-1600, 1600), (-960, 130), (-1600, 1600)) if WORLD else ((-190, 190), (-34, 150), (-190, 190))

MATERIALS = {"Air": 0, "Rock": 1, "Slate": 2, "Sandstone": 3, "Sand": 4, "Basalt": 5, "Mud": 6, "CrackedLava": 7}
# Roughly Cave.COLORS and Shelf.COLORS, in linear-ish RGB
COLORS = {
    1: (0.33, 0.44, 0.47),
    2: (0.23, 0.32, 0.37),
    3: (0.56, 0.50, 0.42),
    4: (0.78, 0.72, 0.56),
    5: (0.20, 0.25, 0.29),
    6: (0.17, 0.24, 0.33),
    7: (1.0, 0.42, 0.12),
}

M = mathutils.Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # Roblox (x, y, z) -> Blender (x, -z, y)


def grid_axes():
    axes = []
    for lo, hi in BOUNDS:
        axes.append(np.arange(lo + CELL / 2, hi, CELL))
    return axes


def rasterize(ops):
    xs, ys, zs = grid_axes()
    grid = np.zeros((len(xs), len(ys), len(zs)), dtype=np.uint8)
    for op in ops:
        material = MATERIALS[op["material"]]
        cx, cy, cz = op["center"]
        # Only the cells the op can touch (a big world has hundreds of ops)
        if op["kind"] == "ball":
            ext = op["radius"]
        elif op["kind"] == "block":
            ext = math.sqrt(sum(s * s for s in op["size"])) / 2
        else:
            ext = math.sqrt(op["radius"] ** 2 + (op["height"] / 2) ** 2)
        i0, i1 = np.searchsorted(xs, cx - ext), np.searchsorted(xs, cx + ext, side="right")
        j0, j1 = np.searchsorted(ys, cy - ext), np.searchsorted(ys, cy + ext, side="right")
        k0, k1 = np.searchsorted(zs, cz - ext), np.searchsorted(zs, cz + ext, side="right")
        if i0 >= i1 or j0 >= j1 or k0 >= k1:
            continue
        X, Y, Z = np.meshgrid(xs[i0:i1], ys[j0:j1], zs[k0:k1], indexing="ij")
        if op["kind"] == "ball":
            r = op["radius"]
            mask = (X - cx) ** 2 + (Y - cy) ** 2 + (Z - cz) ** 2 <= r * r
        else:
            right, up, look = (np.array(a, dtype=float) for a in op["axes"])
            dx, dy, dz = X - cx, Y - cy, Z - cz
            lr = dx * right[0] + dy * right[1] + dz * right[2]
            lu = dx * up[0] + dy * up[1] + dz * up[2]
            ll = dx * look[0] + dy * look[1] + dz * look[2]
            if op["kind"] == "block":
                sx, sy, sz = op["size"]
                mask = (np.abs(lr) <= sx / 2) & (np.abs(lu) <= sy / 2) & (np.abs(ll) <= sz / 2)
            else:  # cylinder along the CFrame's up axis
                r, h = op["radius"], op["height"]
                mask = (np.abs(lu) <= h / 2) & (lr * lr + ll * ll <= r * r)
        sub = grid[i0:i1, j0:j1, k0:k1]
        sub[mask] = material
    return grid


def build_mesh(grid, name):
    xs, ys, zs = grid_axes()
    solid = (grid > 0).astype(np.float32)
    # Pad so the surface closes at the grid's edges
    padded = np.pad(solid, 1, mode="constant", constant_values=0)
    verts, faces, _, _ = measure.marching_cubes(padded, level=0.5)
    verts = (verts - 1) * CELL + np.array([xs[0], ys[0], zs[0]])
    # Material per vertex: the solid voxel nearest to it
    idx = np.clip(np.round((verts - np.array([xs[0], ys[0], zs[0]])) / CELL).astype(int), 0, np.array(grid.shape) - 1)
    mats = grid[idx[:, 0], idx[:, 1], idx[:, 2]]
    # A vertex on the surface sits next to air: look one cell inward along a few offsets
    for off in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
        missing = mats == 0
        if not missing.any():
            break
        j = np.clip(idx[missing] + np.array(off), 0, np.array(grid.shape) - 1)
        mats[missing] = grid[j[:, 0], j[:, 1], j[:, 2]]
    mats[mats == 0] = 1
    mesh = bpy.data.meshes.new(name)
    blender_verts = [tuple(M @ mathutils.Vector(v)) for v in verts]
    mesh.from_pydata(blender_verts, [], [tuple(int(i) for i in f) for f in faces])
    mesh.update()
    colors = mesh.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    flat = np.zeros((len(verts), 4), dtype=np.float32)
    for mat_id, color in COLORS.items():
        flat[mats == mat_id] = (*color, 1.0)
    colors.data.foreach_set("color", flat.ravel())
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for poly in mesh.polygons:
        poly.use_smooth = True
    mat = bpy.data.materials.new(name + "Mat")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    attr = nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    bsdf = nodes["Principled BSDF"]
    mat.node_tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    obj.data.materials.append(mat)
    return obj


def add_glow(name, position, size, color, strength):
    bpy.ops.mesh.primitive_cube_add(size=1)
    obj = bpy.context.active_object
    obj.name = name
    obj.location = M @ mathutils.Vector(position)
    obj.scale = tuple(s / 2 for s in size)
    mat = bpy.data.materials.new(name + "Mat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Emission Color"].default_value = (*color, 1)
    bsdf.inputs["Emission Strength"].default_value = strength
    obj.data.materials.append(mat)
    return obj


def point_light(position, color, energy, radius=3.0):
    light = bpy.data.lights.new("L", "POINT")
    light.color = color
    light.energy = energy
    light.shadow_soft_size = radius
    obj = bpy.data.objects.new("L", light)
    obj.location = M @ mathutils.Vector(position)
    bpy.context.scene.collection.objects.link(obj)


def dress(hub):
    """Stand-ins for what stays as parts: the plaza, beacon, pools, den lamps."""
    import colorsys

    add_glow("Beacon", (0, 16, 0), (6, 26, 6), (0.43, 0.9, 1.0), 6)
    point_light((0, 22, 0), (0.45, 0.9, 1.0), 40000, 6)
    # Plaza disc
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=45, depth=2)
    plaza = bpy.context.active_object
    plaza.location = M @ mathutils.Vector((0, 0.5, 0))
    mat = bpy.data.materials.new("PlazaMat")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.2, 0.22, 0.24, 1)
    plaza.data.materials.append(mat)
    for den in hub["dens"]:
        px, py, pz = den["pool"]
        add_glow("Pool", (px, py, pz), (14, 0.6, 14), (0.31, 0.9, 1.0), 2.5)
        point_light((px, py + 6, pz), (0.31, 0.9, 1.0), 6000, 4)
        lx, ly, lz = den["lamp"]
        point_light((lx, ly, lz), (1.0, 0.77, 0.55), 5000, 3)
    for s in hub["sconces"]:
        add_glow("Sconce", s, (2, 2, 1), (1.0, 0.75, 0.47), 8)
        point_light((s[0], s[1], s[2]), (1.0, 0.75, 0.47), 2500, 2)


def camera(name, position, target, fov_deg):
    cam = bpy.data.cameras.new(name)
    cam.angle = math.radians(fov_deg)
    cam.clip_start = 0.5
    cam.clip_end = 8000
    obj = bpy.data.objects.new(name, cam)
    bpy.context.scene.collection.objects.link(obj)
    pos = M @ mathutils.Vector(position)
    tgt = M @ mathutils.Vector(target)
    obj.location = pos
    direction = tgt - pos
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return obj


def render_world():
    """The whole seafloor (run_world.sh): from above and from three sides."""
    ops = [json.loads(line) for line in open(os.path.join(DIR, "world_ops.jsonl")) if line.strip()]
    grid = rasterize(ops)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 3
    scene.render.resolution_x, scene.render.resolution_y = 1280, 1280
    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.08, 0.3, 0.4, 1)
    bg.inputs["Strength"].default_value = 0.5
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 4.0
    sun.color = (0.85, 0.95, 1.0)
    sun.angle = math.radians(6)
    so = bpy.data.objects.new("Sun", sun)
    so.rotation_euler = (math.radians(35), math.radians(20), 0)
    scene.collection.objects.link(so)
    build_mesh(grid, "World")
    views = {
        "aerial": camera("Aerial", (0, 3400, 1000), (0, -200, 0), 58),
        "north": camera("North", (0, 1000, -2900), (0, -250, 0), 60),
        "south": camera("South", (0, 1000, 2900), (0, -350, 150), 60),
        "east": camera("East", (2900, 950, 0), (0, -250, 0), 60),
    }
    for name, cam in views.items():
        scene.camera = cam
        if name != "aerial":
            scene.render.resolution_x, scene.render.resolution_y = 1400, 800
        out = os.path.join(DIR, f"world_{name}.png")
        scene.render.filepath = out
        bpy.ops.render.render(write_still=True)
        print("wrote", out)


def main():
    if WORLD:
        render_world()
        return
    ops = [json.loads(line) for line in open(os.path.join(DIR, "cave_ops.jsonl")) if line.strip()]
    grid = rasterize(ops)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    # Cycles on the CPU: this sandbox has no EGL for EEVEE
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 4
    scene.render.resolution_x, scene.render.resolution_y = 1120, 700
    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.05, 0.22, 0.30, 1)
    bg.inputs["Strength"].default_value = 0.35
    # The sun through the oculus
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 5.0
    sun.color = (0.8, 0.95, 1.0)
    sun.angle = math.radians(4)
    so = bpy.data.objects.new("Sun", sun)
    so.rotation_euler = (math.radians(12), math.radians(8), 0)
    scene.collection.objects.link(so)

    full = build_mesh(grid, "Cave")
    # Cutaway: everything above the dome's shoulder removed, for the aerial view
    cut = grid.copy()
    xs, ys, zs = grid_axes()
    cut[:, ys > 64, :] = 0
    cutaway = build_mesh(cut, "CaveCut")
    cutaway.hide_render = True

    hub = json.load(open(os.path.join(DIR, "cave_layout.json")))
    dress(hub)

    views = {
        "plaza": camera("Plaza", (-30, 9, 52), (40, 30, -40), 85),
        "den": camera("Den", (84, 12, 46), (-20, 40, -30), 90),
        "tunnel": camera("Tunnel", (0, 16, -120), (0, 24, 60), 80),
        "oculus": camera("Oculus", (20, 6, 20), (0, 110, 0), 95),
        "aerial": camera("Aerial", (160, 230, 170), (0, 20, 0), 60),
        "outside": camera("Outside", (0, 70, -330), (0, 60, 0), 70),
    }
    for name, cam in views.items():
        scene.camera = cam
        if name == "aerial":
            full.hide_render, cutaway.hide_render = True, False
        else:
            full.hide_render, cutaway.hide_render = False, True
        out = os.path.join(DIR, f"cave_{name}.png")
        scene.render.filepath = out
        bpy.ops.render.render(write_still=True)
        print("wrote", out)


main()
