"""Renders the hub (run_hub.sh): the cavern's Terrain voxelized from cave_ops.jsonl
plus the part dump in hub_parts.txt (parts, lights, particle stand-ins, imported
models from assets/tripo/, and every SurfaceGui's text drawn with Pillow).

    EGL_PLATFORM=surfaceless <bpy python> render_hub.py -- <dir>   (VIEWS=a,b,...)

A rough look, for shapes, colours, layout and whether text fits: Terrain and the
toon-material parts get a plate pattern like the toon maps (big plates, dark seams
at the material's studsPerTile), Roblox's flat Ambient is added as a dim unshadowed
fill, and the water's haze is laid over by depth (a second, flat render).
Cycles on the CPU, since this sandbox has no EGL for EEVEE.
"""
import math
import os
import re
import sys

import bpy
import mathutils
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cave_render  # noqa: E402  (rasterize, build_mesh, grid_axes)

argv = sys.argv[sys.argv.index("--") + 1 :]
DIR = os.path.abspath(argv[0])
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "../.."))
VIEWS = [v for v in os.environ.get("VIEWS", "").split(",") if v]
RES = [int(v) for v in os.environ.get("RES", "1280,720").split(",")]
SAMPLES = int(os.environ.get("SAMPLES", "24"))
FOG = float(os.environ.get("FOG", "150"))  # studs to 63% haze
NO_TERRAIN = os.environ.get("NO_TERRAIN") == "1"

M = mathutils.Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # Roblox (x, y, z) -> Blender (x, -z, y)

# Cave.COLORS (sRGB)
TERRAIN = {
    1: (96, 122, 130),  # Rock
    2: (70, 92, 104),  # Slate
    3: (150, 138, 118),  # Sandstone
    4: (206, 194, 156),  # Sand
    5: (88, 98, 110),  # Basalt
    6: (60, 80, 100),  # Mud
    7: (255, 110, 40),  # CrackedLava
    8: (38, 92, 184),  # Glacier (the Blue Hole's walls)
}
# Config/Materials toon overrides: studs per tile, and plank (Regular) or plate (Organic)
TOON = {
    "Rock": (14, "plates"),
    "Slate": (14, "plates"),
    "Basalt": (12, "plates"),
    "Sandstone": (14, "bands"),
    "Sand": (16, "plates"),
    "Mud": (16, "plates"),
    "CrackedLava": (12, "plates"),
    "Pebble": (8, "plates"),
    "Marble": (14, "plates"),
    "WoodPlanks": (8, "planks"),
    "Wood": (8, "planks"),
    "Limestone": (12, "plates"),
    "Glacier": (14, "plates"),
}
AMBIENT = (0.085, 0.12, 0.15)  # Lighting.Ambient's flat fill (linear), lifted to read
FOG_COLOR = (34, 104, 128)
# Another biome's water (run_vents.sh): FOG_COLOR=r,g,b (sRGB 0-255), AMBIENT=r,g,b
# (linear) and SUN=<energy> (default 3)
if os.environ.get("FOG_COLOR"):
    FOG_COLOR = tuple(int(v) for v in os.environ["FOG_COLOR"].split(","))
if os.environ.get("AMBIENT"):
    AMBIENT = tuple(float(v) for v in os.environ["AMBIENT"].split(","))
SUN = float(os.environ.get("SUN", "3.0"))
EMIT = float(os.environ.get("EMIT", "1"))  # imported glow maps' strength
# ...per model (EMIT_BY=LeviathanRib=0.3,GlowEggs=1.8)
EMIT_BY = {k: float(v) for k, v in (kv.split("=") for kv in os.environ.get("EMIT_BY", "").split(",") if "=" in kv)}
# A model's own Glow attribute (TrenchDress `shine`, BlueDress) wins over both, times this
GLOW_SCALE = float(os.environ.get("GLOW_SCALE", "1"))
# HDR=1: the picture is rendered in linear light (EXR), hazed there, bloomed as the
# game's OceanBloom blooms (what passes BLOOM_THRESHOLD, at BLOOM_INTENSITY: the dark
# biomes' 1.1 and 0.9), then rolled off and encoded. Without it, glow over 1 clips flat.
HDR = os.environ.get("HDR") == "1"
BLOOM_THRESHOLD = float(os.environ.get("BLOOM_THRESHOLD", "1.1"))
BLOOM_INTENSITY = float(os.environ.get("BLOOM_INTENSITY", "0.9"))
FONTS = {
    "lucky": os.path.join(REPO, "tools/marketing/fonts/LuckiestGuy-Regular.ttf"),
    "black": "/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf",
    "bold": "/usr/share/fonts/opentype/inter/Inter-Bold.otf",
    "semi": "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf",
    "medium": "/usr/share/fonts/opentype/inter/Inter-Medium.otf",
}


def lin(c):
    return tuple((v / 255 if v > 1.001 else v) ** 2.2 for v in c)


def vec(s):
    return mathutils.Vector([float(v) for v in s.split(",")])


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

def node_mat(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    return mat, mat.node_tree.nodes, mat.node_tree.links


def world_pos(nodes):
    geo = nodes.new("ShaderNodeNewGeometry")
    return geo.outputs["Position"]


def add_ambient(nodes, links, bsdf, color_socket):
    """Roblox's Ambient: a flat, unshadowed fill of the surface's own colour."""
    mix = nodes.new("ShaderNodeVectorMath")
    mix.operation = "MULTIPLY"
    links.new(color_socket, mix.inputs[0])
    mix.inputs[1].default_value = AMBIENT
    links.new(mix.outputs[0], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.0


def toon_pattern(nodes, links, color_socket, studs, kind):
    """Multiplies `color_socket` by a plate (or plank) pattern in world space: big
    flat plates with dark seams, each a little lighter or darker, ~0.8 on average
    like the toon maps (Config/Materials)."""
    pos = world_pos(nodes)
    # Roblox studs -> Blender units are 1:1; scale so one tile is `studs`
    scale = nodes.new("ShaderNodeVectorMath")
    scale.operation = "SCALE"
    links.new(pos, scale.inputs[0])
    scale.inputs["Scale"].default_value = 1.0 / studs
    if kind == "planks":
        stretch = nodes.new("ShaderNodeVectorMath")
        stretch.operation = "MULTIPLY"
        links.new(scale.outputs[0], stretch.inputs[0])
        stretch.inputs[1].default_value = (0.35, 0.35, 2.6)  # long boards
        src = stretch.outputs[0]
    elif kind == "bands":
        stretch = nodes.new("ShaderNodeVectorMath")
        stretch.operation = "MULTIPLY"
        links.new(scale.outputs[0], stretch.inputs[0])
        stretch.inputs[1].default_value = (0.5, 0.5, 2.2)
        src = stretch.outputs[0]
    else:
        src = scale.outputs[0]
    vor = nodes.new("ShaderNodeTexVoronoi")
    vor.voronoi_dimensions = "3D"
    vor.feature = "DISTANCE_TO_EDGE"
    links.new(src, vor.inputs["Vector"])
    vor2 = nodes.new("ShaderNodeTexVoronoi")
    vor2.voronoi_dimensions = "3D"
    links.new(src, vor2.inputs["Vector"])
    # seam: dark where the distance to the edge is small
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.025
    ramp.color_ramp.elements[0].color = (0.42, 0.42, 0.42, 1)
    ramp.color_ramp.elements[1].position = 0.06
    ramp.color_ramp.elements[1].color = (0.86, 0.86, 0.86, 1)
    links.new(vor.outputs["Distance"], ramp.inputs["Fac"])
    # per-plate shade
    sep = nodes.new("ShaderNodeSeparateColor")
    links.new(vor2.outputs["Color"], sep.inputs["Color"])
    shade = nodes.new("ShaderNodeMapRange")
    shade.inputs["To Min"].default_value = 0.88
    shade.inputs["To Max"].default_value = 1.08
    links.new(sep.outputs["Red"], shade.inputs["Value"])
    m1 = nodes.new("ShaderNodeMix")
    m1.data_type = "RGBA"
    m1.blend_type = "MULTIPLY"
    m1.inputs["Factor"].default_value = 1.0
    links.new(color_socket, m1.inputs["A"])
    links.new(ramp.outputs["Color"], m1.inputs["B"])
    m2 = nodes.new("ShaderNodeVectorMath")
    m2.operation = "SCALE"
    links.new(m1.outputs["Result"], m2.inputs[0])
    links.new(shade.outputs["Result"], m2.inputs["Scale"])
    return m2.outputs[0]


MAT_CACHE = {}


def part_material(color, mat_name, transparency, reflectance):
    key = (tuple(round(c, 3) for c in color), mat_name, round(transparency, 2), round(reflectance, 2))
    if key in MAT_CACHE:
        return MAT_CACHE[key]
    mat, nodes, links = node_mat(str(key))
    bsdf = nodes["Principled BSDF"]
    base = lin(color)
    rgb = nodes.new("ShaderNodeRGB")
    rgb.outputs[0].default_value = (*base, 1)
    color_socket = rgb.outputs[0]
    bsdf.inputs["Roughness"].default_value = 0.55
    bsdf.inputs["Specular IOR Level"].default_value = 0.35
    if mat_name in TOON:
        studs, kind = TOON[mat_name]
        color_socket = toon_pattern(nodes, links, color_socket, studs, kind)
        bsdf.inputs["Roughness"].default_value = 0.9
    elif mat_name == "SmoothPlastic":
        bsdf.inputs["Roughness"].default_value = 0.42
    elif mat_name in ("Foil", "Metal", "DiamondPlate"):
        bsdf.inputs["Metallic"].default_value = 0.85
        bsdf.inputs["Roughness"].default_value = 0.32 if mat_name == "Foil" else 0.42
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 3.0 if mat_name == "Foil" else 9.0
        links.new(world_pos(nodes), noise.inputs["Vector"])
        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.35 if mat_name == "Foil" else 0.12
        links.new(noise.outputs["Fac"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    elif mat_name == "Fabric":
        bsdf.inputs["Roughness"].default_value = 1.0
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 40.0
        links.new(world_pos(nodes), noise.inputs["Vector"])
        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.15
        links.new(noise.outputs["Fac"], bump.inputs["Height"])
        links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    elif mat_name == "Glass":
        bsdf.inputs["Roughness"].default_value = 0.05
        bsdf.inputs["Coat Weight"].default_value = 1.0
    if reflectance > 0:
        bsdf.inputs["Roughness"].default_value = min(bsdf.inputs["Roughness"].default_value, 0.25)
        bsdf.inputs["Specular IOR Level"].default_value = 0.5 + reflectance
    links.new(color_socket, bsdf.inputs["Base Color"])
    if mat_name == "Neon":
        links.new(color_socket, bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 3.5
    elif mat_name == "ForceField":
        # an animated shimmer in game: faint, additive, mostly see-through
        links.new(color_socket, bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 0.8 * (1 - transparency)
    else:
        add_ambient(nodes, links, bsdf, color_socket)
    alpha = 1 - transparency
    if mat_name == "ForceField":
        alpha = alpha * 0.5
    if alpha < 1:
        bsdf.inputs["Alpha"].default_value = alpha
        try:
            mat.surface_render_method = "BLENDED"
        except AttributeError:
            pass
    MAT_CACHE[key] = mat
    return mat


def sand_pattern(nodes, links, color_socket):
    """Multiplies `color_socket` by the real toon Sand map (assets/textures/toon_Sand.png:
    soft ripple bands), laid flat in world space at its studsPerTile (Config/Materials
    Sand 16), as the game's Terrain wears it."""
    path = os.path.join(REPO, "assets/textures/toon_Sand.png")
    if not os.path.exists(path):
        return toon_pattern(nodes, links, color_socket, 16, "plates")
    pos = world_pos(nodes)
    scale = nodes.new("ShaderNodeVectorMath")
    scale.operation = "SCALE"
    links.new(pos, scale.inputs[0])
    scale.inputs["Scale"].default_value = 1.0 / 16
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(path, check_existing=True)
    tex.image.colorspace_settings.name = "Non-Color"
    tex.extension = "REPEAT"
    links.new(scale.outputs[0], tex.inputs["Vector"])
    mul = nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    links.new(color_socket, mul.inputs["A"])
    links.new(tex.outputs["Color"], mul.inputs["B"])
    # (the game lifts a Terrain colour x1.22 while its toon map is on: Cave.paint
    # `terrainLift`, since the grey map darkens it)
    lift = nodes.new("ShaderNodeMix")
    lift.data_type = "RGBA"
    lift.blend_type = "MULTIPLY"
    lift.inputs["Factor"].default_value = 1.0
    links.new(mul.outputs["Result"], lift.inputs["A"])
    lift.inputs["B"].default_value = (1.22, 1.22, 1.22, 1)
    return lift.outputs["Result"]


def terrain_material(obj):
    mat, nodes, links = node_mat("TerrainToon")
    bsdf = nodes["Principled BSDF"]
    attr = nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    plates = toon_pattern(nodes, links, attr.outputs["Color"], 14, "plates")
    # Sand (material 4) wears its own ripple map; the rest the plate pattern
    ids = nodes.new("ShaderNodeAttribute")
    ids.attribute_name = "MatId"
    is_sand = nodes.new("ShaderNodeMath")
    is_sand.operation = "COMPARE"
    is_sand.inputs[1].default_value = 4
    is_sand.inputs[2].default_value = 0.5
    links.new(ids.outputs["Fac"], is_sand.inputs[0])
    pick = nodes.new("ShaderNodeMix")
    pick.data_type = "RGBA"
    links.new(is_sand.outputs[0], pick.inputs["Factor"])
    links.new(plates, pick.inputs["A"])
    links.new(sand_pattern(nodes, links, attr.outputs["Color"]), pick.inputs["B"])
    color = pick.outputs["Result"]
    links.new(color, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.92
    add_ambient(nodes, links, bsdf, color)
    obj.data.materials.clear()
    obj.data.materials.append(mat)


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

def base_meshes():
    made = []
    bpy.ops.mesh.primitive_cube_add(size=2)
    made.append(bpy.context.active_object)
    bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=1, depth=2)
    made.append(bpy.context.active_object)
    made[1].data.transform(mathutils.Matrix.Rotation(math.pi / 2, 4, "Y"))  # axis along X like Roblox
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1, segments=32, ring_count=16)
    made.append(bpy.context.active_object)
    for poly in made[2].data.polygons:
        poly.use_smooth = True
    for poly in made[1].data.polygons:
        poly.use_smooth = abs(poly.normal.x) < 0.5
    wedge = bpy.data.meshes.new("Wedge")
    verts = [(x, y, z) for x in (-1, 1) for (y, z) in ((-1, -1), (-1, 1), (1, 1))]
    wedge.from_pydata(verts, [], [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (0, 3, 5, 2)])
    wedge.update()
    corner = bpy.data.meshes.new("CornerWedge")
    # Roblox CornerWedge: the peak over the (+X, +Y, -Z)... approximated as a tetra-ish block
    cverts = [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1), (1, 1, -1)]
    corner.from_pydata(cverts, [], [(0, 3, 2, 1), (0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)])
    corner.update()
    meshes = {"Block": made[0].data, "Cylinder": made[1].data, "Ball": made[2].data, "Wedge": wedge, "CornerWedge": corner}
    placeholder = bpy.data.materials.new("slot")
    for mesh in meshes.values():
        mesh.materials.append(placeholder)
    for o in made:
        bpy.data.objects.remove(o, do_unlink=True)
    return meshes


def frame_matrix(f, i):
    """Four '|' fields from index i: position, right, up, back -> (pos, rot3x3)."""
    pos = vec(f[i])
    right, up, back = vec(f[i + 1]), vec(f[i + 2]), vec(f[i + 3])
    rot = mathutils.Matrix((right, up, back)).transposed()
    return pos, rot


def place(obj, pos, rot, scale):
    mw = (M @ rot).to_4x4()
    mw.translation = M @ pos
    obj.matrix_world = mw @ mathutils.Matrix.Diagonal((*scale, 1))


def add_part(f, meshes):
    name, shape = f[1], f[2]
    size = vec(f[3])
    pos, rot = frame_matrix(f, 4)
    color = [float(v) for v in f[8].split(",")]
    mat_name, transparency, reflectance = f[9], float(f[10]), float(f[11])
    if shape == "Ball":
        d = min(size)
        size = mathutils.Vector((d, d, d))
    elif shape == "Cylinder":
        d = min(size.y, size.z)
        size = mathutils.Vector((size.x, d, d))
    mesh = meshes["Ball"] if shape == "Ellipsoid" else meshes.get(shape, meshes["Block"])
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    place(obj, pos, rot, (size.x / 2, size.y / 2, size.z / 2))
    obj.material_slots[0].link = "OBJECT"
    obj.material_slots[0].material = part_material(color, mat_name, transparency, reflectance)
    if mat_name in ("Neon", "ForceField") or transparency > 0.5:
        obj.visible_shadow = False


LIGHTS = []


def add_light(f):
    pos = vec(f[1])
    color = [float(v) for v in f[2].split(",")]
    rng, brightness = float(f[3]), float(f[4])
    LIGHTS.append((pos, color, rng, brightness))


def make_lights():
    for i, (pos, color, rng, brightness) in enumerate(LIGHTS[:160]):
        ld = bpy.data.lights.new(f"PL{i}", "POINT")
        ld.energy = brightness * rng * rng * 1.6
        ld.color = color
        ld.shadow_soft_size = 0.6
        ld.use_shadow = False
        try:
            ld.use_custom_distance = True
            ld.cutoff_distance = rng * 1.2
        except AttributeError:
            pass
        lo = bpy.data.objects.new(f"PL{i}", ld)
        bpy.context.scene.collection.objects.link(lo)
        lo.location = M @ pos


def add_particles(f, meshes):
    import random

    name = f[1]
    pos, rot = frame_matrix(f, 2)
    box = vec(f[6])
    color = [float(v) for v in f[7].split(",")]
    rate, life, speed, rise, size = (float(v) for v in f[8:13])
    # (an emitter's transparency at birth, when the dump has it: see-through ones
    # are drawn fainter)
    fade = float(f[13]) if len(f) > 13 and f[13] else 0.35
    alpha = 0.45 * max(0.15, min(1.0, (1 - fade) / 0.65))
    rnd = random.Random(hash(f[2]) & 0xFFFF)
    count = int(max(4, min(90, rate * life * 0.8)))
    key = ("particle", tuple(round(c, 2) for c in color), round(alpha, 2))
    mat = bpy.data.materials.get(str(key))
    if mat is None:
        mat, nodes, links = node_mat(str(key))
        bsdf = nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*lin(color), 1)
        bsdf.inputs["Emission Color"].default_value = (*lin(color), 1)
        bsdf.inputs["Emission Strength"].default_value = 1.2
        bsdf.inputs["Alpha"].default_value = alpha
        bsdf.inputs["Roughness"].default_value = 0.1
    for _ in range(count):
        age = rnd.random()
        local = mathutils.Vector(
            (rnd.uniform(-box.x / 2, box.x / 2), rnd.uniform(-box.y / 2, box.y / 2), rnd.uniform(-box.z / 2, box.z / 2))
        )
        world = pos + rot @ local + mathutils.Vector((0, age * life * (speed * 0.6 + max(rise, 0) * 0.4), 0))
        d = max(size * (0.5 + 0.5 * rnd.random()), 0.12)
        obj = bpy.data.objects.new("Particle", meshes["Ball"])
        bpy.context.scene.collection.objects.link(obj)
        obj.matrix_world = mathutils.Matrix.Translation(M @ world) @ mathutils.Matrix.Scale(d / 2, 4)
        obj.material_slots[0].link = "OBJECT"
        obj.material_slots[0].material = mat
        obj.visible_shadow = False


# ---------------------------------------------------------------------------
# Imported models (Props.dress placements)
# ---------------------------------------------------------------------------
GLB_CACHE = {}
# The shipped bundles first (fetch_assets.py unpacks them into assets/glb/props), then
# the raw Tripo outputs (the same geometry)
PROP_DIRS = [os.path.join(REPO, "assets/glb/props")] + [
    os.path.join(REPO, "assets/tripo", d) for d in ("props", "vendors", "furniture", "whalefall", "ruins", "cliff", "biome_wreck", "biome_trench", "biome_kelp", "biome_reef", "biome_blue")
]


def glb(name):
    if name in GLB_CACHE:
        return GLB_CACHE[name]
    path = None
    for d in PROP_DIRS:
        p = os.path.join(d, name + ".glb")
        if os.path.exists(p):
            path = p
            break
    if path is None:
        GLB_CACHE[name] = None
        return None
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = mathutils.Matrix.Identity(4)
    vs = [v.co for v in obj.data.vertices]
    mn = mathutils.Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = mathutils.Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    obj.data.transform(mathutils.Matrix.Translation(-(mn + mx) / 2))
    obj.data.transform(mathutils.Matrix.Rotation(math.pi, 4, "Z"))  # Studio turns a GLB half round
    ext = mx - mn
    data = obj.data
    for mat in data.materials:  # no normal maps in game (stripped), no metal
        if mat and mat.use_nodes:
            for node in mat.node_tree.nodes:
                if node.type == "BSDF_PRINCIPLED":
                    for link in list(node.inputs["Normal"].links):
                        mat.node_tree.links.remove(link)
                    for link in list(node.inputs["Metallic"].links):
                        mat.node_tree.links.remove(link)
                    node.inputs["Metallic"].default_value = 0.0
                    # a glow map's strength as the game sets it (EMIT=, TrenchDress `shine`)
                    if node.inputs["Emission Strength"].default_value > 0:
                        node.inputs["Emission Strength"].default_value *= EMIT_BY.get(name, EMIT)
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    GLB_CACHE[name] = (data, (ext.x, ext.z, ext.y))
    return GLB_CACHE[name]


def add_prop(f):
    name, mode = f[1], f[2]
    got = glb(name)
    if got is None:
        return
    data, ext = got
    pos, rot = frame_matrix(f, 3)
    size = vec(f[7])
    if mode == "height":
        scale = size.y / max(ext[1], 1e-4)
        centre = pos
    else:
        scale = min(size.x / max(ext[0], 1e-4), size.y / max(ext[1], 1e-4), size.z / max(ext[2], 1e-4))
        centre = pos + rot @ mathutils.Vector((0, -size.y / 2 + ext[1] * scale / 2, 0))
    world = (M @ rot @ M.inverted()).to_4x4()
    world.translation = M @ centre
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.matrix_world = world @ mathutils.Matrix.Scale(scale, 4)
    tint = lin([float(v) for v in f[8].split(",")]) if len(f) > 8 and f[8] else None
    # the model's own glow as the builder set it (the Glow / GlowTint attributes beside
    # EmissiveStrength / EmissiveTint): replaces the EMIT / EMIT_BY guess for this one
    glow = float(f[9]) if len(f) > 9 and f[9] else None
    glow_tint = lin([float(v) for v in f[10].split(",")]) if len(f) > 10 and f[10] else None
    if tint is None and glow is None and glow_tint is None:
        return
    for slot in obj.material_slots:
        src = slot.material
        if src is None:
            continue
        copy = src.copy()
        tree = copy.node_tree
        for node in list(tree.nodes):
            if node.type != "BSDF_PRINCIPLED":
                continue
            basec = node.inputs["Base Color"]
            if tint is not None and basec.links:
                source = basec.links[0].from_socket
                mult = tree.nodes.new("ShaderNodeVectorMath")
                mult.operation = "MULTIPLY"
                mult.inputs[1].default_value = tint
                tree.links.new(source, mult.inputs[0])
                tree.links.new(mult.outputs[0], basec)
            strength = node.inputs["Emission Strength"]
            if glow is not None and strength.default_value > 0:
                strength.default_value *= glow * GLOW_SCALE / EMIT_BY.get(name, EMIT)
            ecol = node.inputs["Emission Color"]
            if glow_tint is not None and ecol.links:
                source = ecol.links[0].from_socket
                mult = tree.nodes.new("ShaderNodeVectorMath")
                mult.operation = "MULTIPLY"
                mult.inputs[1].default_value = glow_tint
                tree.links.new(source, mult.inputs[0])
                tree.links.new(mult.outputs[0], ecol)
        slot.link = "OBJECT"
        slot.material = copy


# ---------------------------------------------------------------------------
# Beams (light shafts): camera-facing ribbons that add their light, drawn in a pass
# of their own (everything else held out) and added over the hazed picture
# ---------------------------------------------------------------------------

BEAMS = []


def add_beam(f):
    BEAMS.append(
        {
            "a": vec(f[1]),
            "b": vec(f[2]),
            "w0": float(f[3]),
            "w1": float(f[4]),
            "color": lin([float(v) for v in f[5].split(",")]),
            "alpha": [1 - float(f[6]), 1 - float(f[7]), 1 - float(f[8])],
        }
    )


def beam_material(beam):
    mat, nodes, links = node_mat("Beam")
    out = nodes["Material Output"]
    for n in list(nodes):
        if n.type == "BSDF_PRINCIPLED":
            nodes.remove(n)
    uv = nodes.new("ShaderNodeUVMap")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(uv.outputs["UV"], sep.inputs[0])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "LINEAR"
    els = ramp.color_ramp.elements
    els[0].position, els[1].position = 0.0, 1.0
    els[0].color = (beam["alpha"][0],) * 3 + (1,)
    els[1].color = (beam["alpha"][2],) * 3 + (1,)
    mid = els.new(0.6)
    mid.color = (beam["alpha"][1],) * 3 + (1,)
    links.new(sep.outputs["X"], ramp.inputs["Fac"])
    # the water between the camera and the shaft takes its light away
    cam = nodes.new("ShaderNodeCameraData")
    neg = nodes.new("ShaderNodeMath")
    neg.operation = "MULTIPLY"
    neg.inputs[1].default_value = -1.0 / FOG
    links.new(cam.outputs["View Distance"], neg.inputs[0])
    att = nodes.new("ShaderNodeMath")
    att.operation = "EXPONENT"
    links.new(neg.outputs[0], att.inputs[0])
    mul = nodes.new("ShaderNodeMixRGB")
    mul.blend_type = "MULTIPLY"
    mul.inputs["Fac"].default_value = 1.0
    links.new(ramp.outputs["Color"], mul.inputs[1])
    links.new(att.outputs[0], mul.inputs[2])
    tint = nodes.new("ShaderNodeMixRGB")
    tint.blend_type = "MULTIPLY"
    tint.inputs["Fac"].default_value = 1.0
    links.new(mul.outputs[0], tint.inputs[1])
    tint.inputs[2].default_value = (*beam["color"], 1)
    em = nodes.new("ShaderNodeEmission")
    links.new(tint.outputs[0], em.inputs["Color"])
    tr = nodes.new("ShaderNodeBsdfTransparent")
    add = nodes.new("ShaderNodeAddShader")
    links.new(tr.outputs[0], add.inputs[0])
    links.new(em.outputs[0], add.inputs[1])
    links.new(add.outputs[0], out.inputs["Surface"])
    return mat


def build_beams(cam_pos):
    """Ribbons turned to face `cam_pos` (Roblox axes), as a FaceCamera Beam is."""
    objs = []
    for i, beam in enumerate(BEAMS):
        a, b = beam["a"], beam["b"]
        axis = b - a
        mid = (a + b) / 2
        side = axis.cross(mathutils.Vector(cam_pos) - mid)
        if side.length < 1e-6:
            continue
        side.normalize()
        steps = 10
        verts, faces, uvs = [], [], []
        for s in range(steps + 1):
            t = s / steps
            p = a + axis * t
            half = (beam["w0"] + (beam["w1"] - beam["w0"]) * t) / 2
            verts.append(M @ (p - side * half))
            verts.append(M @ (p + side * half))
        for s in range(steps):
            faces.append((2 * s, 2 * s + 1, 2 * s + 3, 2 * s + 2))
        mesh = bpy.data.meshes.new(f"Beam{i}")
        mesh.from_pydata([tuple(v) for v in verts], [], faces)
        layer = mesh.uv_layers.new(name="UVMap")
        for poly in mesh.polygons:
            for li in poly.loop_indices:
                vi = mesh.loops[li].vertex_index
                layer.data[li].uv = ((vi // 2) / steps, vi % 2)
        mesh.materials.append(beam_material(beam))
        obj = bpy.data.objects.new(f"Beam{i}", mesh)
        bpy.context.scene.collection.objects.link(obj)
        objs.append(obj)
    return objs


def render_beams(scene, name, cam_pos):
    """The shafts alone, everything else held out; returns the image path or None."""
    if not BEAMS:
        return None
    others = [o for o in scene.objects if o.type in ("MESH", "CURVE", "FONT")]
    beams = build_beams(cam_pos)
    for o in others:
        o.is_holdout = True
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs["Strength"].default_value = 0.0
    scene.render.film_transparent = True
    scene.view_layers[0].material_override = None
    scene.cycles.samples = 8
    scene.cycles.use_denoising = False
    path = os.path.join(DIR, f"_beams_{name}.{'exr' if HDR else 'png'}")
    scene.render.filepath = path
    if HDR:
        scene.render.image_settings.file_format = "OPEN_EXR"
        scene.render.image_settings.color_depth = "16"
    else:
        scene.render.image_settings.color_depth = "8"
    bpy.ops.render.render(write_still=True)
    scene.render.image_settings.file_format = "PNG"
    for o in others:
        o.is_holdout = False
    for o in beams:
        bpy.data.objects.remove(o, do_unlink=True)
    scene.render.film_transparent = False
    bg.inputs["Strength"].default_value = 0.6
    return path


def read_exr(path):
    """An EXR's linear RGB as a (height, width, 3) array, top row first."""
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1, :, :3]
    bpy.data.images.remove(img)
    return px


def finish_hdr(beauty_exr, depth_path, beam_path, out_png):
    """Haze, the shafts and bloom in linear light, as the game composes them, then a
    soft shoulder and sRGB."""
    from scipy.ndimage import gaussian_filter

    im = read_exr(beauty_exr)
    d = np.asarray(Image.open(depth_path).convert("F")).astype(np.float32) / 65535.0 * 1000.0
    d[d <= 0.01] = 1000.0
    f = 1 - np.exp(-d / FOG)
    fog = np.array(lin(FOG_COLOR), dtype=np.float32)
    out = im * (1 - f[..., None]) + fog * f[..., None]
    if beam_path:
        out = out + read_exr(beam_path)
    # OceanBloom: what passes the threshold spreads (Size 28 at 1280 wide)
    bright = np.maximum(out - BLOOM_THRESHOLD, 0)
    scale = out.shape[1] / 1280
    glow = np.zeros_like(out)
    for sigma, weight in ((4, 0.45), (12, 0.35), (28, 0.2)):
        for c in range(3):
            glow[..., c] += gaussian_filter(bright[..., c], sigma * scale) * weight
    out = out + glow * BLOOM_INTENSITY * 2.5
    knee = 0.8
    out = np.where(out < knee, out, knee + (1 - knee) * (1 - np.exp(-(out - knee) / (1 - knee))))
    out = np.clip(out, 0, 1)
    srgb = np.where(out <= 0.0031308, out * 12.92, 1.055 * out ** (1 / 2.4) - 0.055)
    Image.fromarray((srgb * 255).astype(np.uint8)).save(out_png)


def add_beam_image(beauty_path, beam_path):
    """Adds the shafts' light (in linear light) over the hazed picture."""
    def to_lin(x):
        return np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4)

    def to_srgb(x):
        x = np.clip(x, 0, 1)
        return np.where(x <= 0.0031308, x * 12.92, 1.055 * x ** (1 / 2.4) - 0.055)

    im = np.asarray(Image.open(beauty_path).convert("RGB")).astype(np.float32) / 255
    bm = np.asarray(Image.open(beam_path).convert("RGB")).astype(np.float32) / 255
    out = to_srgb(to_lin(im) + to_lin(bm))
    Image.fromarray((out * 255).astype(np.uint8)).save(beauty_path)


# ---------------------------------------------------------------------------
# SurfaceGui text
# ---------------------------------------------------------------------------

def font_for(weight, size):
    w = weight.lower()
    if "lucky" in w:
        path = FONTS["lucky"]
    elif "black" in w or "heavy" in w or "extrabold" in w:
        path = FONTS["black"]
    elif "semibold" in w:
        path = FONTS["semi"]
    elif "medium" in w or "regular" in w:
        path = FONTS["medium"]
    else:
        path = FONTS["bold"]
    return ImageFont.truetype(path, max(int(size), 1))


def wrap(text, font, width):
    lines = []
    for para in text.split("\n"):
        words = para.split(" ")
        line = ""
        for word in words:
            trial = word if not line else line + " " + word
            if font.getlength(trial) <= width or not line:
                line = trial
            else:
                lines.append(line)
                line = word
        lines.append(line)
    return lines


def fit(text, weight, w, h, maxsize, scaled, textsize):
    if not scaled:
        font = font_for(weight, textsize)
        return font, [text], textsize
    size = int(min(100, maxsize))
    while size > 2:
        font = font_for(weight, size)
        lines = wrap(text, font, w)
        if len(lines) * size * 1.0 <= h + 0.5 and all(font.getlength(line) <= w + 0.5 for line in lines):
            return font, lines, size
        size -= 1
    font = font_for(weight, 2)
    return font, [text], 2


def udim(s):
    xs, xo, ys, yo = (float(v) for v in s.split(","))
    return xs, xo, ys, yo


def draw_gui(gui, items):
    """Draws a SurfaceGui's frames and labels into an RGBA image."""
    W, H = gui["canvas"]
    scale = min(1.0, 2048 / max(W, H))
    img = Image.new("RGBA", (max(1, int(W * scale)), max(1, int(H * scale))), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rects = {-1: (0.0, 0.0, W, H)}
    for it in items:
        depth = it["depth"]
        px, py, pw, ph = rects.get(depth - 1, rects[-1])
        xs, xo, ys, yo = it["pos"]
        sxs, sxo, sys_, syo = it["size"]
        w = sxs * pw + sxo
        h = sys_ * ph + syo
        ax, ay = it["anchor"]
        x = px + xs * pw + xo - ax * w
        y = py + ys * ph + yo - ay * h
        rects[depth] = (x, y, w, h)
        if not it["visible"]:
            continue
        box = [x * scale, y * scale, (x + w) * scale, (y + h) * scale]
        if it["bgT"] < 0.999:
            a = int(255 * (1 - it["bgT"]))
            fill = tuple(int(c * 255) for c in it["bg"]) + (a,)
            radius = 0
            if it["corner"]:
                cs, co = it["corner"]
                radius = (cs * min(w, h) + co) * scale
            stroke = None
            if it["stroke"] is not None and it["kind"] == "Frame":
                stroke = tuple(int(c * 255) for c in it["stroke"]) + (255,)
            draw.rounded_rectangle(box, radius=radius, fill=fill, outline=stroke, width=max(1, int(it["strokeW"] * scale)) if stroke else 0)
        elif it["stroke"] is not None and it["kind"] == "Frame":
            radius = 0
            if it["corner"]:
                cs, co = it["corner"]
                radius = (cs * min(w, h) + co) * scale
            stroke = tuple(int(c * 255) for c in it["stroke"]) + (255,)
            draw.rounded_rectangle(box, radius=radius, outline=stroke, width=max(1, int(it["strokeW"] * scale)))
        text = re.sub(r"<[^>]+>", "", it["text"])
        if it["kind"] == "TextLabel" and text.strip():
            font, lines, size = fit(text, it["weight"], w, h, it["max"], it["scaled"], it["textsize"])
            font = font_for(it["weight"], max(1, size * scale))
            color = tuple(int(c * 255) for c in it["fg"]) + (int(255 * (1 - it["fgT"])),)
            stroke = tuple(int(c * 255) for c in it["stroke"]) + (255,) if it["stroke"] is not None else None
            total = len(lines) * size * scale
            ty = box[1] + (box[3] - box[1] - total) / 2
            for line in lines:
                lw = font.getlength(line)
                if it["xalign"] == "Left":
                    tx = box[0]
                elif it["xalign"] == "Right":
                    tx = box[2] - lw
                else:
                    tx = box[0] + (box[2] - box[0] - lw) / 2
                kwargs = {}
                if stroke:
                    kwargs = {"stroke_width": max(1, int(round(it["strokeW"] * scale))), "stroke_fill": stroke}
                # Pillow's text box starts at the ascender; nudge to centre caps like Roblox
                draw.text((tx, ty + size * scale * 0.06), line, font=font, fill=color, **kwargs)
                ty += size * scale
    return img


GUI_COUNT = [0]


def add_gui(gui, items):
    if not items:
        return
    img = draw_gui(gui, items)
    GUI_COUNT[0] += 1
    path = os.path.join(DIR, "_gui", f"gui{GUI_COUNT[0]}.png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    pos, rot = gui["pos"], gui["rot"]
    size = gui["size"]
    face = gui["face"]
    rx, ry, rz = rot.col[0], rot.col[1], rot.col[2]
    if face == "Front":
        n, right, down, fw, fh, half = -rz, -rx, -ry, size.x, size.y, size.z / 2
    elif face == "Back":
        n, right, down, fw, fh, half = rz, rx, -ry, size.x, size.y, size.z / 2
    elif face == "Right":
        n, right, down, fw, fh, half = rx, -rz, -ry, size.z, size.y, size.x / 2
    elif face == "Left":
        n, right, down, fw, fh, half = -rx, rz, -ry, size.z, size.y, size.x / 2
    elif face == "Top":
        n, right, down, fw, fh, half = ry, rx, rz, size.x, size.z, size.y / 2
    else:
        n, right, down, fw, fh, half = -ry, rx, -rz, size.x, size.z, size.y / 2
    c = pos + n * (half + 0.03)
    corners = [
        c - right * fw / 2 - down * fh / 2,
        c + right * fw / 2 - down * fh / 2,
        c + right * fw / 2 + down * fh / 2,
        c - right * fw / 2 + down * fh / 2,
    ]
    mesh = bpy.data.meshes.new(f"Gui{GUI_COUNT[0]}")
    mesh.from_pydata([tuple(M @ p) for p in corners], [], [(0, 1, 2, 3)])
    uv = mesh.uv_layers.new()
    for i, (u, v) in enumerate(((0, 1), (1, 1), (1, 0), (0, 0))):
        uv.data[i].uv = (u, v)
    obj = bpy.data.objects.new(f"Gui{GUI_COUNT[0]}", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.visible_shadow = False
    mat, nodes, links = node_mat(f"GuiMat{GUI_COUNT[0]}")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(path)
    tex.interpolation = "Cubic"
    bsdf = nodes["Principled BSDF"]
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    if gui["light"] < 0.5:  # LightInfluence 0: drawn at full brightness
        links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
        bsdf.inputs["Base Color"].default_value = (0, 0, 0, 1)
        links.remove(bsdf.inputs["Base Color"].links[0])
    else:
        add_ambient(nodes, links, bsdf, tex.outputs["Color"])
    try:
        mat.surface_render_method = "BLENDED"
    except AttributeError:
        pass
    mesh.materials.append(mat)


def parse_u(f):
    def col(s):
        return [float(v) for v in s.split(",")]

    return {
        "depth": int(f[1]),
        "kind": f[2],
        "pos": udim(f[3]),
        "size": udim(f[4]),
        "anchor": [float(v) for v in f[5].split(",")],
        "bg": col(f[6]),
        "bgT": float(f[7]),
        "fg": col(f[8]),
        "fgT": float(f[9]),
        "text": f[10],
        "scaled": f[11] == "1",
        "weight": f[12],
        "textsize": float(f[13]),
        "stroke": col(f[14]) if f[14] else None,
        "strokeW": float(f[15]),
        "max": float(f[17]) if f[17] else 100,
        "corner": [float(v) for v in f[18].split(",")] if f[18] else None,
        "xalign": f[19],
        "visible": f[20] == "1",
    }


EXTRA_VIEWS = {}


def load_parts(meshes):
    gui, items = None, []
    path = os.path.join(DIR, "hub_parts.txt")
    for line in open(path):
        f = line.rstrip("\n").split("|")
        tag = f[0]
        if tag != "U" and gui is not None:
            add_gui(gui, items)
            gui, items = None, []
        if tag == "P":
            add_part(f, meshes)
        elif tag == "L":
            add_light(f)
        elif tag == "B" and f[1].count(",") == 2:  # (a builder's view box B|name|... isn't a Beam)
            add_beam(f)
        elif tag == "E":
            add_particles(f, meshes)
        elif tag == "R":
            add_prop(f)
        elif tag == "G":
            pos, rot = frame_matrix(f, 2)
            w, h = (float(v) for v in f[7].split(","))
            gui = {"pos": pos, "rot": rot, "size": vec(f[6]), "canvas": (w, h), "light": float(f[8]), "face": f[9]}
        elif tag == "U":
            items.append(parse_u(f))
        elif tag == "V":  # a camera the builder asks for: V|name|position|target|fov
            EXTRA_VIEWS[f[1]] = (tuple(vec(f[2])), tuple(vec(f[3])), float(f[4]))
    if gui is not None:
        add_gui(gui, items)


# ---------------------------------------------------------------------------
# Scene, cameras, haze
# ---------------------------------------------------------------------------

def camera(name, position, target, fov_deg=70):
    cam = bpy.data.cameras.new(name)
    cam.sensor_fit = "VERTICAL"
    cam.angle_y = math.radians(fov_deg)
    cam.clip_start = 0.3
    cam.clip_end = 3000
    obj = bpy.data.objects.new(name, cam)
    bpy.context.scene.collection.objects.link(obj)
    pos = M @ mathutils.Vector(position)
    tgt = M @ mathutils.Vector(target)
    obj.location = pos
    obj.rotation_euler = (tgt - pos).to_track_quat("-Z", "Y").to_euler()
    return obj


def polar(angle_deg, r, y):
    a = math.radians(angle_deg)
    return (math.cos(a) * r, y, math.sin(a) * r)


def views():
    """Named cameras: (position, target, fov)."""
    v = {}
    # Over the plaza from a fish's height near den 12's doorway, looking across
    v["plaza"] = (polar(205, 70, 14), polar(30, 40, 6), 70)
    v["plaza2"] = (polar(110, 78, 16), polar(-60, 30, 4), 70)
    # High under the dome, the whole floor
    v["overview"] = (polar(250, 60, 78), polar(60, 20, 0), 74)
    # Den 1 (15 deg, owned, a 20-character name) and den 2 (45 deg, empty) up close
    v["door"] = (polar(15, 58, 13), polar(15, 104, 18), 70)
    v["door2"] = (polar(30, 52, 12), polar(45, 104, 17), 70)
    v["doors"] = (polar(30, 20, 14), polar(30, 95, 20), 76)
    # The Shade Dyer's stall (315 deg) and the Tidecharm Trader (225) and the wheel (240)
    v["stall"] = (polar(318, 12, 8), polar(315, 34, 5), 70)
    v["stall2"] = (polar(150, 14, 9), polar(135, 34, 5), 70)
    v["stall3"] = (polar(62, 13, 8), polar(45, 34, 5), 70)
    v["wheel"] = (polar(262, 30, 16), polar(240, 62, 14), 70)
    # Den 1's nameplate from the beacon's side of the plaza (readability)
    v["doorfar"] = (polar(330, 24, 12), polar(15, 95, 27), 50)
    v["top"] = ((0, 260, 0.01), (0, 0, 0), 46)
    # The tunnel at 0 deg from the plaza (den doorways either side), and out along it
    v["tunnel"] = (polar(-6, 42, 16), polar(0, 104, 22), 72)
    v["tunnelout"] = (polar(0, 100, 18), polar(0, 220, 22), 72)
    return v


def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 3
    scene.cycles.transparent_max_bounces = 16
    scene.render.resolution_x, scene.render.resolution_y = RES
    try:
        scene.view_settings.view_transform = "Standard"
    except TypeError:
        pass
    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*lin(FOG_COLOR), 1)
    bg.inputs["Strength"].default_value = 0.6
    sun = bpy.data.lights.new("Sun", "SUN")  # straight down through the oculus (ClockTime 12)
    sun.energy = SUN
    sun.color = (0.85, 0.96, 1.0)
    sun.angle = math.radians(3)
    so = bpy.data.objects.new("Sun", sun)
    so.rotation_euler = (math.radians(4), math.radians(3), 0)
    if os.environ.get("SUN_DIR"):  # the way the light travels, in Roblox axes (run_cliff.sh: in from the open water)
        travel = M @ vec(os.environ["SUN_DIR"])
        so.rotation_euler = travel.to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(so)
    return scene


def depth_material():
    mat, nodes, links = node_mat("Depth")
    out = nodes["Material Output"]
    for n in list(nodes):
        if n.type == "BSDF_PRINCIPLED":
            nodes.remove(n)
    lp = nodes.new("ShaderNodeLightPath")
    div = nodes.new("ShaderNodeMath")
    div.operation = "DIVIDE"
    links.new(lp.outputs["Ray Length"], div.inputs[0])
    div.inputs[1].default_value = 1000.0
    em = nodes.new("ShaderNodeEmission")
    links.new(div.outputs[0], em.inputs["Color"])
    links.new(em.outputs[0], out.inputs["Surface"])
    return mat


def haze(beauty_path, depth_path):
    im = np.asarray(Image.open(beauty_path).convert("RGB")).astype(np.float32) / 255
    d = np.asarray(Image.open(depth_path).convert("F")).astype(np.float32)
    # 16-bit depth: value/65535 * 1000 studs
    d = d / 65535.0 * 1000.0
    d[d <= 0.01] = 1000.0
    f = 1 - np.exp(-d / FOG)
    fog = np.array(FOG_COLOR, dtype=np.float32) / 255
    out = im * (1 - f[..., None]) + fog * f[..., None]
    # a soft bloom round the brightest bits (Neon, lit text)
    lum = out.max(axis=2, keepdims=True)
    bright = np.clip((lum - 0.7) / 0.3, 0, 1) * out
    src = Image.fromarray((bright * 255).astype(np.uint8))
    glow = np.zeros_like(out)
    for radius, weight in ((3, 0.4), (10, 0.35), (28, 0.3)):
        glow += np.asarray(src.filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255 * weight
    out = 1 - (1 - out) * (1 - np.clip(glow, 0, 1))
    Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(beauty_path)


def main():
    scene = setup_scene()
    meshes = base_meshes()
    if not NO_TERRAIN:
        import json

        ops = [json.loads(line) for line in open(os.path.join(DIR, "cave_ops.jsonl")) if line.strip()]
        # the builders' repaints (T|replace|min|max|from|to), after every fill
        for line in open(os.path.join(DIR, "hub_parts.txt")):
            f = line.rstrip("\n").split("|")
            if f[0] == "T" and f[1] == "replace":
                ops.append({"kind": "replace", "min": list(vec(f[2])), "max": list(vec(f[3])), "from": f[4], "to": f[5]})
        grid = cave_render.rasterize(ops)
        cave_render.COLORS.update({k: lin(v) for k, v in TERRAIN.items()})
        terrain = cave_render.build_mesh(grid, "Cave")
        terrain_material(terrain)
        cut = grid.copy()
        xs, ys, zs = cave_render.grid_axes()
        cut[:, ys > 70, :] = 0
        cutaway = cave_render.build_mesh(cut, "CaveCut")
        terrain_material(cutaway)
        cutaway.hide_render = True
    load_parts(meshes)
    make_lights()
    depth = depth_material()
    chosen = views()
    chosen.update(EXTRA_VIEWS)
    names = VIEWS or (list(EXTRA_VIEWS) if EXTRA_VIEWS else [n for n in chosen if n not in ("plaza2", "door2", "stall2", "stall3", "doorfar")])
    for name in names:
        position, target, fov = chosen[name]
        cam = camera(name, position, target, fov)
        scene.camera = cam
        if not NO_TERRAIN:
            top = name in ("top", "overview")
            terrain.hide_render, cutaway.hide_render = top, not top
        out = os.path.join(DIR, f"hub_{name}.png")
        scene.render.filepath = out
        scene.view_layers[0].material_override = None
        scene.cycles.samples = SAMPLES
        scene.cycles.use_denoising = True
        beauty = out
        if HDR:
            beauty = os.path.join(DIR, f"_beauty_{name}.exr")
            scene.render.filepath = beauty
            scene.render.image_settings.file_format = "OPEN_EXR"
            scene.render.image_settings.color_depth = "16"
        else:
            scene.render.image_settings.color_depth = "8"
        bpy.ops.render.render(write_still=True)
        scene.render.image_settings.file_format = "PNG"
        # depth pass: every surface emits its distance
        dpath = os.path.join(DIR, f"_depth_{name}.png")
        scene.view_layers[0].material_override = depth
        bg = scene.world.node_tree.nodes["Background"]
        bg.inputs["Strength"].default_value = 0.0
        scene.cycles.samples = 1
        scene.cycles.use_denoising = False
        scene.render.image_settings.color_mode = "BW"
        scene.render.image_settings.color_depth = "16"
        try:
            scene.view_settings.view_transform = "Raw"
        except TypeError:
            pass
        scene.render.filepath = dpath
        bpy.ops.render.render(write_still=True)
        scene.render.image_settings.color_mode = "RGB"
        bg.inputs["Strength"].default_value = 0.6
        try:
            scene.view_settings.view_transform = "Standard"
        except TypeError:
            pass
        if HDR:
            finish_hdr(beauty, dpath, render_beams(scene, name, position), out)
        elif name != "top":
            haze(out, dpath)
            bpath = render_beams(scene, name, position)
            if bpath:
                add_beam_image(out, bpath)
        print("wrote", out)


main()
