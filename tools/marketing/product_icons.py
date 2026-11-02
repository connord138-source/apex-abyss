"""Store icons for the game passes and developer products, built from the game itself
like the Deep Pass icon (tools/marketing/pass_icon.py; owner, 2026-10-14: generated key
art is "clearly AI", so product art is real renders of the game's models on a card
drawn in code, and every word on it is set here).

    python tools/marketing/product_icons.py renders <dir> [name ...]   # Blender: fish and props into <dir> (~7 min, CPU)
    python tools/marketing/product_icons.py cards <dir>     # the cards from <dir>'s renders
    python tools/marketing/product_icons.py all <dir>       # both
    python tools/shades/screen_shades.py marketing/icon_*_512.png   # screen before uploading

`renders` runs Blender ($BLENDER, else blender on the PATH, else the default Windows
install) on half the CPU's threads. The fish go through render_fish.py in their own
textures (assets/fbx/species/<Fish>.fbx, skins `-`); everything else is a scene this
file builds when Blender runs it:

    blender -b -P tools/marketing/product_icons.py -- scene <name> <out.png> [size]

    ring        the Nibbler wearing the life ring the game draws for Second Chance
                (CardPhoto `lifeRing`: red and white bands)
    haul_small  the game's Haul photo (CardPhoto `haul`): three prey tied with a kelp
    haul_big    band (a Minnow, a Wrasse and a Sardine); two and three of those
    haul_huge   bundles for the bigger sizes
    garden      the den's Coral Garden bed (DenBuilder.garden): a ring of stones over
                its glow, the reef props growing in it
    den         den furniture: Sponge Sofa, Coral Lamp, Angler Lamp, Pearl Pedestal on a rug
    pouch       a diver's net pouch full of shells (no pouch model exists: rope along a
                bag's shape), drawn shut with a gold cord
    chest       the Treasure Chest heaped with shells

The shells are the game's conch (assets/glb/props/Shell.glb) tinted pearl blue, its
pink lip turned sea blue and its opening edge-on, and golden ones tinted the way
ShellController tints the Trench's golden shells. No normal map is ever used or written:
render_fish.py and this file unlink and drop any a model carries.

Moderation: every card must exit 0 on screen_shades.py. Its classifier is touchy at
icon size, and these scored 0.6-1.0 before they were changed: the Nibbler shot
three-quarter from the front (now from near the side), CardPhoto's Snapper and Grouper
in the haul (now a Minnow, a Wrasse and a Sardine), a conch's opening seen head-on, a
big round cloth pouch (now a net) and the Reef Globe in the den (now the Angler Lamp).
Even a moved subject changes the score (the Big Haul 1% left: 0.18 to 0.01), so screen
again after any change. 2026-11-02: all twelve under 0.13.

The cards are pass_icon.py's (navy glass, the gold frame and teal hairline, bubbles,
Luckiest Guy lettering in gold with a navy outline, Lilita One tags), each with its own
motif behind the subject in place of the Deep Pass's riptide. `cards` writes
marketing/icon_<id>_512.png for every pass and product, the ids read from
src/shared/Config/Monetization.luau: the three Double Haul sizes are a small, big and
huge haul, and the rewarded ad's product (a small Haul) shares the small one. A pass's
icon shows in a circle on the Store tab, so the four pass cards keep their title and
subject inside it (PASS_TITLE). Where each goes in Creator Hub: docs/STORE_PAGE.md,
"Pass and product icons".
"""

import math
import os
import pathlib
import random
import re
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
FBX = ROOT / "assets/fbx/species"
GLB = ROOT / "assets/glb"
OUT = pathlib.Path(os.environ.get("ICONS_OUT", ROOT / "marketing"))  # ICONS_OUT: a trial folder

try:
    import bpy  # Blender's Python: this file is building a scene
except ImportError:
    bpy = None

# --- Colours from the game (Ui.luau, CardPhoto, DenDoor, ShellController) ------------

LIFE_RED = (226, 64, 58)  # CardPhoto lifeRing
LIFE_WHITE = (236, 240, 243)  # its white, a touch cooler (240, 240, 236 reads warm under the key)
KELP_BAND = (70, 128, 52)  # CardPhoto haul
SHELL_GOLD = (255, 204, 84)  # ShellController GOLD
PEARL = (196, 212, 236)
GROTTO = [(84, 78, 104), (98, 90, 120), (74, 70, 94), (110, 100, 132)]  # DenDoor GROTTO_ROCK
GROTTO_MORTAR = (46, 42, 58)
DEN_TEAL = (86, 222, 255)  # Config/Dens glow Teal


# =====================================================================================
# Blender: the scenes
# =====================================================================================


def _lin(rgb):
    """sRGB 0-255 to Blender's linear 0-1, with alpha."""
    return tuple(((c / 255 + 0.055) / 1.055) ** 2.4 if c / 255 > 0.04045 else c / 255 / 12.92 for c in rgb) + (1.0,)


def _np():
    import numpy as np

    return np


def _verts(ob):
    np = _np()
    m = ob.matrix_world
    return np.array([(m @ v.co)[:] for v in ob.data.vertices])


def _clean(ob, rough=0.6):
    """Metal off, a set roughness, and no normal map: its links, its node, its image."""
    for slot in ob.material_slots:
        m = slot.material
        if m is None or not m.use_nodes:
            continue
        tree = m.node_tree
        bsdf = next((n for n in tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            continue
        for name in ("Metallic", "Roughness", "Normal"):
            for link in list(bsdf.inputs[name].links):
                tree.links.remove(link)
        for node in [n for n in tree.nodes if n.type in ("NORMAL_MAP", "BUMP")]:
            tree.nodes.remove(node)
        for node in [n for n in tree.nodes if n.type == "TEX_IMAGE" and not any(o.links for o in n.outputs)]:
            tree.nodes.remove(node)
        bsdf.inputs["Metallic"].default_value = 0.0
        bsdf.inputs["Roughness"].default_value = rough


def _import(path):
    """One model as a single mesh object at the world origin's frame, cleaned."""
    from mathutils import Matrix

    scene = bpy.context.scene
    before = set(scene.objects)
    if str(path).lower().endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=str(path))
    else:
        bpy.ops.import_scene.gltf(filepath=str(path))
    new = [o for o in scene.objects if o not in before]
    names = [o.name for o in new]
    meshes = [o for o in new if o.type == "MESH"]
    for o in meshes:  # a rigged fish: its rest pose
        for mod in [mod for mod in o.modifiers if mod.type == "ARMATURE"]:
            o.modifiers.remove(mod)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    if len(meshes) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    for name in names:
        o = bpy.data.objects.get(name)
        if o is not None and o is not body:
            bpy.data.objects.remove(o, do_unlink=True)
    body.data.transform(body.matrix_world)
    body.matrix_world = Matrix.Identity(4)
    _clean(body)
    return body


def _fit(ob, size, dim="max", anchor="bottom"):
    """Scales the mesh so `dim` (x, y, z or max) is `size` and moves it to the origin:
    its foot (anchor bottom) or its middle (centre)."""
    from mathutils import Matrix, Vector

    np = _np()
    co = _verts(ob)
    mn, mx = co.min(0), co.max(0)
    extent = (mx - mn) if dim == "max" else (mx - mn)["xyz".index(dim)]
    s = size / float(np.max(extent))
    mid = (mn + mx) / 2
    foot = Vector((mid[0], mid[1], mn[2] if anchor == "bottom" else mid[2]))
    ob.data.transform(Matrix.Scale(s, 4) @ Matrix.Translation(-foot))
    return ob


def _square(ob, flip=False):
    """A fish squared up as render_fish.py does it: centred, longest axis along Y,
    head (the fatter end) toward -Y."""
    from mathutils import Matrix, Vector

    np = _np()
    co = _verts(ob)
    ob.data.transform(Matrix.Translation(-Vector(((co.max(0) + co.min(0)) / 2).tolist())))
    co = _verts(ob)
    evals, evecs = np.linalg.eigh(np.cov(co[:, :2].T))
    axis = evecs[:, np.argmax(evals)]
    ob.data.transform(Matrix.Rotation(math.atan2(axis[0], axis[1]), 4, "Z"))
    co = _verts(ob)
    y0, length = co[:, 1].min(), np.ptp(co[:, 1])

    def girth(lo, hi):
        band = co[(co[:, 1] >= y0 + lo * length) & (co[:, 1] < y0 + hi * length)]
        return np.ptp(band[:, 0]) * np.ptp(band[:, 2]) if len(band) >= 8 else 0.0

    if (not girth(0.08, 0.3) > girth(0.7, 0.92)) != flip:
        ob.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
    return ob


def _place(ob, at=(0, 0, 0), yaw=0.0, pitch=0.0, roll=0.0):
    ob.rotation_mode = "XYZ"  # the glTF importer leaves objects in quaternions
    ob.rotation_euler = (math.radians(pitch), math.radians(roll), math.radians(yaw))
    ob.location = at
    bpy.context.view_layer.update()
    return ob


def _tint(ob, rgb, hue=None, sat=1.0, metal=None, rough=None):
    """Multiplies the colour map by `rgb` (as a SurfaceAppearance's Color does), after an
    optional hue turn (0.5 = none) and saturation."""
    for slot in ob.material_slots:
        m = slot.material
        if m is None or not m.use_nodes:
            continue
        tree = m.node_tree
        bsdf = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")
        socket = bsdf.inputs["Base Color"]
        source = socket.links[0].from_socket if socket.links else None
        if source is not None and (hue is not None or sat != 1.0):
            hsv = tree.nodes.new("ShaderNodeHueSaturation")
            hsv.inputs["Hue"].default_value = 0.5 if hue is None else hue
            hsv.inputs["Saturation"].default_value = sat
            tree.links.new(source, hsv.inputs["Color"])
            source = hsv.outputs["Color"]
        if source is None:
            c = socket.default_value
            socket.default_value = tuple(a * b for a, b in zip(c[:3], _lin(rgb)[:3])) + (1.0,)
        else:
            mix = tree.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            a = next(s for s in mix.inputs if s.name == "A" and s.type == "RGBA")
            b = next(s for s in mix.inputs if s.name == "B" and s.type == "RGBA")
            out = next(s for s in mix.outputs if s.type == "RGBA")
            tree.links.new(source, a)
            b.default_value = _lin(rgb)
            tree.links.new(out, socket)
        if metal is not None:
            bsdf.inputs["Metallic"].default_value = metal
        if rough is not None:
            bsdf.inputs["Roughness"].default_value = rough


def _mat(name, rgb, rough=0.5, emit=None, strength=0.0, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = _lin(rgb)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value = _lin(emit)
        bsdf.inputs["Emission Strength"].default_value = strength
    return m


def _smooth(ob):
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def _mesh(name, verts, faces, material):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(material)
    return _smooth(ob)


def _lathe(name, profile, material, segments=64, wobble=None):
    """A mesh turned round Z from (radius, height) points, bottom first, closed below."""
    verts, faces = [(0.0, 0.0, profile[0][1])], []
    for j, (r, z) in enumerate(profile):
        for i in range(segments):
            a = i / segments * 2 * math.pi
            rr = r * (1 + (wobble(a, j) if wobble else 0))
            verts.append((rr * math.cos(a), rr * math.sin(a), z))
    for i in range(segments):
        faces.append((0, 1 + (i + 1) % segments, 1 + i))
    for j in range(len(profile) - 1):
        for i in range(segments):
            a, b = 1 + j * segments + i, 1 + j * segments + (i + 1) % segments
            faces.append((a, b, b + segments, a + segments))
    return _mesh(name, verts, faces, material)


def _torus(name, major, minor, material, at=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(
        major_segments=96, minor_segments=24, major_radius=major, minor_radius=minor, location=at
    )
    ob = bpy.context.active_object
    ob.name = name
    ob.rotation_euler = tuple(math.radians(a) for a in rot)
    ob.scale = scale
    ob.data.materials.append(material)
    return _smooth(ob)


def _ball(name, radius, material, at, scale=(1, 1, 1), rot=(0, 0, 0), facets=0):
    """A sphere, or with `facets` (1-2) a flat-shaded low-poly rock like the game's."""
    if facets:
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=facets, radius=radius, location=at)
    else:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=radius, location=at)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = scale
    ob.rotation_euler = tuple(math.radians(a) for a in rot)
    ob.data.materials.append(material)
    return ob if facets else _smooth(ob)


def _rod(name, a, b, radius, material):
    from mathutils import Vector

    a, b = Vector(a), Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=radius, depth=(b - a).length, location=(a + b) / 2)
    ob = bpy.context.active_object
    ob.name = name
    ob.rotation_euler = (b - a).to_track_quat("Z", "Y").to_euler()
    ob.data.materials.append(material)
    return _smooth(ob)


SHELL_AWAY = 60  # the conch's turn that puts its opening edge-on to a camera at -Y


def _shell(at, size=0.62, gold=False, turn=0.0, pitch=0.0, roll=0.0):
    """The game's conch, pearl (its pink lip turned sea blue) or golden, its spire and
    whorls to the camera: `turn` is degrees off the turn that hides its opening (an
    opening seen head-on scored 1.0 on the moderation classifier)."""
    ob = _fit(_import(GLB / "props/Shell.glb"), size)
    if gold:
        _tint(ob, SHELL_GOLD, sat=0.4, metal=0.3, rough=0.32)
    else:
        _tint(ob, PEARL, hue=0.11, sat=0.8, rough=0.35)
    return _place(ob, at, SHELL_AWAY + turn, pitch, roll)


def _fish(name, length, flip=False, glb=False):
    path = GLB / f"prey/{name}.glb" if glb else FBX / f"{name}.fbx"
    ob = _square(_import(path), flip)
    return _fit(ob, length, "y", "centre")


def _setup(size, samples):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.04, 0.13, 0.22, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
    # render_fish.py's lights: a key from above front-right, a cool fill, a cyan rim
    for kind, energy, rot, colour in (
        ("Key", 3.4, (40, 0, 40), (1, 1, 1)),
        ("Fill", 0.9, (100, 0, -60), (0.7, 0.85, 1.0)),
        ("Rim", 4.0, (-60, 0, 200), (0.45, 0.95, 1.0)),
    ):
        data = bpy.data.lights.new(kind, "SUN")
        data.energy = energy
        data.color = colour
        obj = bpy.data.objects.new(kind, data)
        obj.rotation_euler = tuple(math.radians(a) for a in rot)
        scene.collection.objects.link(obj)


def _shoot(view, out, lens=70, margin=1.05):
    """Points a perspective camera along `view` (its direction from the subject) at
    every mesh in the scene, backed off until all of it is in frame, and renders."""
    from mathutils import Vector

    np = _np()
    scene = bpy.context.scene
    bpy.context.view_layer.update()
    pts = np.concatenate([_verts(o) for o in scene.objects if o.type == "MESH"])
    centre = Vector(((pts.max(0) + pts.min(0)) / 2).tolist())
    d = Vector(view).normalized()
    rot = (-d).to_track_quat("-Z", "Y")
    basis = rot.to_matrix()
    right, up = basis.col[0], basis.col[1]
    rel = pts - np.array(centre[:])
    x, y, z = rel @ np.array(right[:]), rel @ np.array(up[:]), rel @ np.array(d[:])
    t = math.tan(math.atan(36 / 2 / lens)) / margin
    distance = float(np.max(np.maximum(np.abs(x), np.abs(y)) / t + z))
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = lens
    span = float(np.ptp(pts, 0).max())
    cam_data.clip_start, cam_data.clip_end = span * 0.01, distance + span * 4
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.location = centre + d * distance
    cam.rotation_euler = rot.to_euler()
    pathlib.Path(out).parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(out)
    bpy.ops.render.render(write_still=True)


def scene_ring():
    """The Nibbler wearing the life ring round its middle."""
    np = _np()
    _fish("Nibbler", 2.0)
    fish = bpy.context.active_object
    co = _verts(fish)
    y0, length = co[:, 1].min(), np.ptp(co[:, 1])
    ring_y = y0 + 0.5 * length
    slab = co[np.abs(co[:, 1] - ring_y) < 0.08 * length]
    cx, cz = np.median(slab[:, 0]), np.median(slab[:, 2])
    r = float(np.percentile(np.hypot(slab[:, 0] - cx, slab[:, 2] - cz), 88))
    tube = 0.3 * r
    ring = _torus("LifeRing", r + tube * 0.55, tube, _mat("Red", LIFE_RED, 0.38), (cx, ring_y, cz), (90 - 10, 0, -8))
    ring.data.materials.append(_mat("White", LIFE_WHITE, 0.38))
    for p in ring.data.polygons:  # 8 bands, red and white, as a life ring has
        a = math.atan2(p.center.y, p.center.x) + math.pi
        p.material_index = int(a / (2 * math.pi / 8)) % 2
    return (1.0, -1.1, 0.16)


# A haul is laid out as CardPhoto's: three prey 3.2 studs long, ~0.55 apart up and 0.2
# back, turned 8 and tipped 6 degrees each, tied with a kelp band:
# (prey, height, depth, yaw, roll).
# CardPhoto's are a Snapper, a Grouper and a Wrasse; the icon's are a Minnow, a Wrasse
# and a Sardine, since the big-lipped Snapper and Grouper faces scored 0.86-0.99 on the
# moderation classifier at icon size (this trio 0.03)
BUNDLE = [("Minnow", -0.45, -0.2, -8, -6), ("Wrasse", 0.0, 0.0, 0, 0), ("Sardine", 0.5, 0.2, 8, 6)]
# The bigger sizes are more of them: (x, depth, height, yaw) per bundle
HAULS = {
    "haul_small": [(0.0, 0.0, 0.0, 0)],
    "haul_big": [(1.15, 1.1, 1.05, -10), (-0.75, 0.0, 0.0, 6)],
    "haul_huge": [(0.1, 2.2, 2.05, -4), (1.95, 0.9, 0.15, -12), (-1.6, 0.0, -0.05, 8)],
}


def _join(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


def _band(name, centre, ry, rz, width, thick, material, segments=96, sides=16):
    """A flat strap round the X axis: an ellipse of half-depth ry and half-height rz in
    the YZ plane, `width` across (along X) and `thick` deep."""
    cx, cy, cz = centre
    verts, faces = [], []
    for i in range(segments):
        u = i / segments * 2 * math.pi
        py, pz = cy + ry * math.cos(u), cz + rz * math.sin(u)
        ny, nz = math.cos(u) / ry, math.sin(u) / rz
        n = math.hypot(ny, nz)
        ny, nz = ny / n, nz / n
        for j in range(sides):
            v = j / sides * 2 * math.pi
            out = thick * math.cos(v)
            verts.append((cx + width * math.sin(v), py + out * ny, pz + out * nz))
    for i in range(segments):
        for j in range(sides):
            a, b = i * sides + j, i * sides + (j + 1) % sides
            c, d = ((i + 1) % segments) * sides + (j + 1) % sides, ((i + 1) % segments) * sides + j
            faces.append((a, b, c, d))
    return _mesh(name, verts, faces, material)


def _bundle(kelp):
    """One haul at the origin, heads toward -X, as one object."""
    np = _np()
    fish = []
    for prey, height, depth, yaw, roll in BUNDLE:
        fish.append(_place(_fish(prey, 3.2, glb=True), (0.0, depth, height), -90 + yaw, 0, roll))
    co = np.concatenate([_verts(o) for o in fish])
    xb = float(np.median(co[:, 0])) + 0.2
    slab = co[np.abs(co[:, 0] - xb) < 0.1]
    cy, cz = (slab[:, 1].max() + slab[:, 1].min()) / 2, (slab[:, 2].max() + slab[:, 2].min()) / 2
    ry, rz = np.ptp(slab[:, 1]) / 2 * 0.92, np.ptp(slab[:, 2]) / 2 * 0.9
    band = _band("Band", (xb, cy, cz), ry + 0.04, rz + 0.04, 0.22, 0.07, kelp)
    return _join(fish + [band])


def scene_haul(name):
    kelp = _mat("Kelp", KELP_BAND, 0.75)
    for x, depth, height, yaw in HAULS[name]:
        _place(_bundle(kelp), (x, depth, height), yaw)
    return (0.25, -1.0, 0.32)


# The Coral Garden's bed layout (DenBuilder LAYOUTS.bed: x across, z front + to back -,
# sizes in studs), each with the reef prop that plays it
GARDEN = [
    ("BranchFanViolet", 0.0, -0.05, 5.0, 90),
    ("BranchFanOrange", -0.35, -0.45, 4.6, 70),
    ("DomeCoralRed", 0.4, 0.2, 2.6, 20),
    ("PillarCoral", 0.52, -0.42, 4.2, 0),
    ("Anemone", -0.45, 0.35, 2.2, 40),
    ("TableCoralBlue", 0.28, -0.7, 3.4, 10),
    ("TubeSponge", -0.66, -0.08, 3.4, 30),
    ("DomeCoralYellow", -0.1, 0.55, 1.9, 60),
    ("Anemone", 0.72, 0.2, 1.8, 120),
    ("BranchFanRed", -0.22, -0.72, 3.6, 100),
    ("DomeCoralGreen", 0.16, 0.72, 1.5, 0),
]


def scene_garden():
    hw, hd = 2.6, 1.7
    sand = _ball("Sand", 1.0, _mat("Sand", (122, 126, 112), 0.9), (0, 0, -0.05), (hw, hd, 0.12))
    sand.name = "Sand"
    _torus("Glow", 1.0, 0.05, _mat("Glow", DEN_TEAL, 0.4, DEN_TEAL, 9.0), (0, 0, 0.04), (0, 0, 0), (hw + 0.25, hd + 0.25, 1))
    stone = [_mat(f"Stone{i}", c, 0.8) for i, c in enumerate(GROTTO)]
    stones = 22
    for i in range(stones):
        a = (i + 0.5) / stones * 2 * math.pi
        big = (1.4 + (i % 3) * 0.35) * 0.2
        _ball(
            "Stone",
            1.0,
            stone[i % 4],
            (math.cos(a) * (hw + 0.2), math.sin(a) * (hd + 0.2), big * 0.3),
            (big * 1.4, big, big * 0.75),
            (0, (i % 3 - 1) * 7, math.degrees(a) + 90 + (i % 2) * 20),
            facets=1,
        )
    for name, x, z, size, yaw in GARDEN:
        ob = _fit(_import(GLB / f"props/{name}.glb"), size * 0.6, "z")
        _place(ob, (x * hw * 0.85, -z * hd * 0.8, 0.0), yaw)  # front (+z) toward the camera
    return (0.0, -1.0, 0.55)


def scene_den():
    rug = _ball("Rug", 1.0, _mat("Rug", (36, 92, 112), 0.95), (0, 0.1, -0.03), (2.7, 1.5, 0.04))
    rug.name = "Rug"
    _torus("RugRim", 1.0, 0.035, _mat("RugRim", (255, 204, 92), 0.5), (0, 0.1, 0.0), (0, 0, 0), (2.7, 1.5, 0.6))
    _place(_fit(_import(GLB / "den_props2/SpongeSofa.glb"), 1.25, "z"), (0.0, 0.55, 0.0), 0)
    _place(_fit(_import(GLB / "den_props2/CoralLamp.glb"), 2.6, "z"), (-2.15, 0.65, 0.0), 15)
    _place(_fit(_import(GLB / "furniture/AnglerLamp.glb"), 2.2, "z"), (1.95, -0.3, 0.0), -25)
    _place(_fit(_import(GLB / "den_props2/PearlPedestal.glb"), 1.2, "z"), (-1.15, -0.55, 0.0), 0)
    return (0.35, -1.0, 0.3)


def _rope(name, pts, radius, material):
    """A rope along points: a bevelled curve, made a mesh so the camera frames it."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new("POLY")
    spline.points.add(len(pts) - 1)
    for point, (x, y, z) in zip(spline.points, pts):
        point.co = (x, y, z, 1.0)
    ob = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(material)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.convert(target="MESH")
    return bpy.context.view_layer.objects.active


def scene_pouch():
    """A diver's net pouch full of shells, drawn shut with a gold cord, a few spilled
    at its foot (no pouch model exists: the net is rope along a bag's shape)."""
    rng = random.Random(4)
    # The bag's radius by height, bottom to the cinched neck
    shape = [(0.0, 0.08), (0.12, 0.5), (0.32, 0.86), (0.6, 0.98), (0.9, 0.9), (1.18, 0.66), (1.38, 0.4), (1.48, 0.3)]

    def radius(z):
        for (z0, r0), (z1, r1) in zip(shape, shape[1:]):
            if z <= z1:
                return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
        return shape[-1][1]

    # Shells filling it, then a few spilled at its foot
    for i in range(16):
        z = 0.3 + 1.0 * (i / 15) ** 0.9
        a = rng.uniform(0, 2 * math.pi)
        r = radius(z) * rng.uniform(0.0, 0.62)
        _shell((math.cos(a) * r, math.sin(a) * r, z - 0.25), rng.uniform(0.48, 0.58), i % 4 == 1,
               rng.uniform(-40, 40), rng.uniform(-14, 14), rng.uniform(-24, 24))
    for at, size, gold_shell in (((-0.92, -0.8, 0.0), 0.52, False), ((0.62, -0.95, 0.0), 0.5, True), ((-0.12, -1.18, 0.0), 0.48, False)):
        _shell(at, size, gold_shell, rng.uniform(-30, 30), rng.uniform(-8, 8), rng.uniform(-15, 15))
    # The net: two ways round, a diamond mesh, gathered at the neck
    net = _mat("Net", (36, 120, 150), 0.7)
    strands, steps, twist = 16, 56, math.pi * 0.5
    for way in (-1, 1):
        for k in range(strands):
            pts = []
            for i in range(steps + 1):
                t = i / steps
                z = shape[0][0] + (shape[-1][0] - shape[0][0]) * t
                a = k * 2 * math.pi / strands + way * twist * t
                r = radius(z) * (1 + 0.04 * math.sin(5 * a))
                pts.append((math.cos(a) * r, math.sin(a) * r, z))
            _rope("Net", pts, 0.017, net)
    gold = _mat("Cord", (255, 204, 92), 0.35, metal=0.4)
    _torus("Cord", 0.32, 0.055, gold, (0, 0, 1.46), (0, 0, 0))
    # The net's mouth above the cord, flaring a little, and the cord's ends
    for k in range(strands):
        a = k * 2 * math.pi / strands
        _rope("Mouth", [(math.cos(a) * 0.3, math.sin(a) * 0.3, 1.46), (math.cos(a) * 0.42, math.sin(a) * 0.42, 1.66)], 0.016, net)
    _torus("Rim", 0.42, 0.03, net, (0, 0, 1.66), (0, 0, 0))
    _ball("Knot", 0.09, gold, (0.0, -0.33, 1.44))
    return (0.15, -1.0, 0.36)


def scene_chest():
    """The Treasure Chest with shells heaped on its lid and spilling round it."""
    chest = _fit(_import(GLB / "props/TreasureChest.glb"), 2.4, "x")
    co = _verts(chest)
    top, front = float(co[:, 2].max()), float(co[:, 1].min())
    rng = random.Random(9)
    spots = [  # on the lid
        (-0.55, 0.05, top - 0.08), (0.05, -0.1, top - 0.02), (0.6, 0.1, top - 0.1), (-0.2, 0.3, top + 0.05),
        (0.35, 0.35, top + 0.02), (0.0, 0.1, top + 0.3),
    ] + [  # and on the sand in front
        (-1.35, front - 0.25, 0.0), (-0.75, front - 0.55, 0.0), (0.0, front - 0.45, 0.0), (0.7, front - 0.6, 0.0),
        (1.35, front - 0.2, 0.0), (-1.55, front + 0.4, 0.0), (1.6, front + 0.45, 0.0), (0.35, front - 1.05, 0.0),
        (-0.4, front - 1.0, 0.0),
    ]
    for i, at in enumerate(spots):
        _shell(at, rng.uniform(0.5, 0.66), i % 3 == 1, rng.uniform(-35, 35), rng.uniform(-10, 10), rng.uniform(-18, 18))
    return (0.3, -1.0, 0.36)


SCENES = {
    "ring": scene_ring,
    "haul_small": lambda: scene_haul("haul_small"),
    "haul_big": lambda: scene_haul("haul_big"),
    "haul_huge": lambda: scene_haul("haul_huge"),
    "garden": scene_garden,
    "den": scene_den,
    "pouch": scene_pouch,
    "chest": scene_chest,
}


def blender_main(argv):
    kind, name, out = argv[0], argv[1], argv[2]
    size = int(argv[3]) if len(argv) > 3 else 1200
    if kind != "scene" or name not in SCENES:
        sys.exit(f"[product_icons] scene <{'|'.join(SCENES)}> <out.png> [size]")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _setup(size, 96)
    view = SCENES[name]()
    _shoot(view, out)
    print(f"[product_icons] {name} -> {out}")


# =====================================================================================
# Python: the renders and the cards
# =====================================================================================

# The fish through render_fish.py, own textures: (file, species, view). Every fish is
# shot from a little in front of side-on, head left; the VIP shark three-quarter. (The
# Nibbler shot three-quarter from the front, as render_fish.py does by default, scored
# 0.99 on the moderation classifier at ×2 Mass's size; from here 0.04.)
FISH = [("shark", "ReefShark", "1.0,-0.75,0.16")] + [
    (f"side_{f}", f, "1.0,-0.3,0.1") for f in ("Nibbler", "Cuda", "Puffer", "MorayEel", "Angler", "ReefShark")
]


def blender_exe():
    exe = os.environ.get("BLENDER") or shutil.which("blender")
    return exe or r"C:\Program Files\Blender Foundation\Blender 5.0\blender.exe"


def renders(folder: pathlib.Path, only=()):
    folder.mkdir(parents=True, exist_ok=True)
    threads = str(max(1, (os.cpu_count() or 2) // 2))
    base = [blender_exe(), "-b", "-t", threads, "--python-exit-code", "1", "-P"]
    jobs = [
        (name, base + [str(HERE / "render_fish.py"), "--", str(FBX / f"{species}.fbx"), "-", "-", str(folder / f"{name}.png"), "1100", view])
        for name, species, view in FISH
    ] + [(name, base + [str(HERE / "product_icons.py"), "--", "scene", name, str(folder / f"{name}.png"), "1200"]) for name in SCENES]
    for name, job in jobs:
        if only and name not in only:
            continue
        print(f"[product_icons] rendering {name}", flush=True)
        result = subprocess.run(job, cwd=ROOT, capture_output=True, text=True)
        if result.returncode != 0:
            print(result.stdout[-3000:], result.stderr[-3000:])
            sys.exit(f"[product_icons] Blender failed on {name}")


# --- The cards ------------------------------------------------------------------------


def card_kit():
    sys.path.insert(0, str(HERE))
    import pass_icon  # noqa: E402  (its palette, frame, lettering, tags)

    return pass_icon


def ids():
    """Monetization.luau's ids by key."""
    text = (ROOT / "src/shared/Config/Monetization.luau").read_text(encoding="utf-8")
    return {m.group(1): int(m.group(2)) for m in re.finditer(r'key\s*=\s*"(\w+)",\s*id\s*=\s*(\d+)', text)}


# Roblox shows a pass's icon in a circle on the experience's Store tab (developer
# products show square), so a pass's title and subject stay inside the inscribed circle:
# its title is at most this share of the card wide (the circle's chord at the title's
# height is ~0.8)
PASS_TITLE = 0.68


class Cards:
    def __init__(self, renders: pathlib.Path):
        from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

        self.Image, self.ImageChops, self.ImageDraw = Image, ImageChops, ImageDraw
        self.ImageFilter, self.ImageFont = ImageFilter, ImageFont
        self.k = card_kit()
        self.S = self.k.S
        self.renders = renders

    # The background: pass_icon's navy glass and glow, a motif, bubbles
    def background(self, glow=(24, 120, 150), glow_box=(0.14, 0.30, 0.86, 0.90)):
        Image, ImageDraw, ImageFilter = self.Image, self.ImageDraw, self.ImageFilter
        S, k = self.S, self.k
        card = Image.new("RGBA", (S, S))
        draw = ImageDraw.Draw(card)
        for y in range(S):
            t = y / (S - 1)
            colour = tuple(round(a + (b - a) * t**1.2) for a, b in zip(k.PANEL, k.FOOT))
            draw.line([(0, y), (S, y)], fill=colour + (255,))
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).ellipse(tuple(v * S for v in glow_box), fill=150)
        card.paste(glow, (0, 0), mask.filter(ImageFilter.GaussianBlur(110)))
        return card

    def bubbles(self, card, spots=((150, 330, 16), (118, 400, 9), (880, 310, 13), (905, 370, 8), (860, 640, 11), (170, 700, 12))):
        bd = self.ImageDraw.Draw(card)
        for x, y, r in spots:
            bd.ellipse((x - r, y - r, x + r, y + r), outline=self.k.AQUA + (130,), width=3)
            bd.ellipse((x - r * 0.45, y - r * 0.6, x - r * 0.05, y - r * 0.2), fill=(255, 255, 255, 110))

    def layer(self):
        return self.Image.new("RGBA", (self.S, self.S), (0, 0, 0, 0))

    def rays(self, card, cx, cy, colour, n=16, alpha=60, inner=40, outer=760, width=0.09, blur=6, turn=0.0):
        """Soft beams from a point (VIP's gold, Frenzy's burst)."""
        rays = self.layer()
        d = self.ImageDraw.Draw(rays)
        for i in range(n):
            a = turn + i * 2 * math.pi / n
            pts = [
                (cx + math.cos(a - width * 0.25) * inner, cy + math.sin(a - width * 0.25) * inner),
                (cx + math.cos(a - width) * outer, cy + math.sin(a - width) * outer),
                (cx + math.cos(a + width) * outer, cy + math.sin(a + width) * outer),
                (cx + math.cos(a + width * 0.25) * inner, cy + math.sin(a + width * 0.25) * inner),
            ]
            d.polygon(pts, fill=colour + (alpha,))
        fade = self.Image.new("L", (self.S, self.S), 0)
        self.ImageDraw.Draw(fade).ellipse((cx - outer * 0.8, cy - outer * 0.8, cx + outer * 0.8, cy + outer * 0.8), fill=255)
        fade = fade.filter(self.ImageFilter.GaussianBlur(outer * 0.25))
        rays.putalpha(self.ImageChops.multiply(rays.getchannel("A"), fade))
        card.alpha_composite(rays.filter(self.ImageFilter.GaussianBlur(blur)))

    def rings(self, card, cx, cy, colour, radii, squash=0.42, alpha=90, width=5):
        """Thin ellipses round a point, fading outward (×2 Mass's growth)."""
        layer = self.layer()
        d = self.ImageDraw.Draw(layer)
        for i, r in enumerate(radii):
            a = round(alpha * (1 - i / (len(radii) + 0.5)))
            d.ellipse((cx - r, cy - r * squash, cx + r, cy + r * squash), outline=colour + (a,), width=width)
        card.alpha_composite(layer.filter(self.ImageFilter.GaussianBlur(1.2)))

    def glint(self, card, x, y, r, colour=(255, 255, 255), alpha=230):
        """The game's four-point glint star, with a soft halo."""
        layer = self.layer()
        d = self.ImageDraw.Draw(layer)
        pts = []
        for i in range(8):
            a = i * math.pi / 4 - math.pi / 2
            rr = r if i % 2 == 0 else r * 0.22
            pts.append((x + math.cos(a) * rr, y + math.sin(a) * rr))
        halo = self.layer()
        self.ImageDraw.Draw(halo).ellipse((x - r * 0.7, y - r * 0.7, x + r * 0.7, y + r * 0.7), fill=colour + (alpha // 3,))
        card.alpha_composite(halo.filter(self.ImageFilter.GaussianBlur(r * 0.4)))
        d.polygon(pts, fill=colour + (alpha,))
        card.alpha_composite(layer.filter(self.ImageFilter.GaussianBlur(0.8)))

    def coin(self, label, d, font_size=None):
        """A gold badge: the game's gold button colours, a navy rim, navy lettering."""
        Image, ImageDraw, ImageFilter, k = self.Image, self.ImageDraw, self.ImageFilter, self.k
        pad = 30
        w = d + pad * 2
        out = Image.new("RGBA", (w, w), (0, 0, 0, 0))
        shadow = Image.new("L", (w, w), 0)
        ImageDraw.Draw(shadow).ellipse((pad, pad + 10, pad + d, pad + d + 10), fill=170)
        out.paste((0, 6, 16, 255), (0, 0), shadow.filter(ImageFilter.GaussianBlur(12)))
        disc = Image.new("RGBA", (w, w), (0, 0, 0, 0))
        dd = ImageDraw.Draw(disc)
        dd.ellipse((pad, pad, pad + d, pad + d), fill=k.NAVY + (255,))
        rim = max(8, d // 16)
        grad = Image.new("RGBA", (w, w))
        gd = ImageDraw.Draw(grad)
        for y in range(w):
            t = min(1, max(0, (y - pad) / d))
            gd.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(k.GOLD_TOP, k.GOLD_LOW)) + (255,))
        mask = Image.new("L", (w, w), 0)
        ImageDraw.Draw(mask).ellipse((pad + rim, pad + rim, pad + d - rim, pad + d - rim), fill=255)
        disc.paste(grad, (0, 0), mask)
        dd = ImageDraw.Draw(disc)
        inset = rim + max(6, d // 20)
        dd.ellipse((pad + inset, pad + inset, pad + d - inset, pad + d - inset), outline=(255, 246, 210, 170), width=3)
        dd.arc((pad + rim * 2, pad + rim * 1.6, pad + d - rim * 2, pad + d * 0.62), 200, 340, fill=(255, 255, 255, 150), width=4)
        out.alpha_composite(disc)
        f = self.ImageFont.truetype(str(k.FONTS / "LuckiestGuy-Regular.ttf"), font_size or round(d * 0.42))
        probe = ImageDraw.Draw(Image.new("L", (1, 1)))
        box = probe.textbbox((0, 0), label, font=f)
        tw, th = box[2] - box[0], box[3] - box[1]
        ImageDraw.Draw(out).text(((w - tw) / 2 - box[0], (w - th) / 2 - box[1] + d * 0.02), label, font=f, fill=k.NAVY + (255,))
        return out

    def title(self, card, label, y=0.19, size=150, max_w=0.82):
        """The gold title, shrunk to `max_w` of the card (PASS_TITLE for a pass)."""
        k, S = self.k, self.S
        f_size = size
        while True:
            layer = k.text(label, "LuckiestGuy-Regular.ttf", f_size, k.GOLD_TOP, k.GOLD_LOW, max(10, round(f_size * 0.093)))
            if layer.width - f_size * 0.56 <= S * max_w or f_size <= 70:
                break
            f_size -= 4
        k.place(card, layer, S * 0.5, S * y)

    def fish(self, name, width, flip=False, dim=1.0, rotate=0.0, shadow=(24, 150)):
        im = self.k.fish(self.renders / f"{name}.png", width, flip, dim)
        if rotate:
            im = im.rotate(rotate, resample=self.Image.BICUBIC, expand=True)
        return self.k.with_shadow(im, *shadow) if shadow else im

    def finish(self, card):
        return card.resize((512, 512), self.Image.LANCZOS)

    # --- One builder per icon ----------------------------------------------------------

    def double_mass(self, small="side_Nibbler", big="side_Nibbler", widths=(250, 560)):
        S, k = self.S, self.k
        card = self.background()
        self.rings(card, S * 0.6, S * 0.8, k.TEAL, [170, 250, 330, 410], alpha=80)
        self.bubbles(card)
        card = k.frame(card)
        k.place(card, self.fish(small, widths[0], dim=0.9, shadow=(18, 110)), S * 0.24, S * 0.52)
        k.place(card, self.fish(big, widths[1]), S * 0.6, S * 0.64)
        self.title(card, "×2 MASS", size=170, max_w=PASS_TITLE)
        return self.finish(card)

    def vip(self):
        S, k = self.S, self.k
        card = self.background(glow=(60, 96, 120))
        self.rays(card, S * 0.5, S * 0.62, k.GOLD, n=18, alpha=46, outer=720)
        self.bubbles(card)
        card = k.frame(card)
        k.place(card, self.fish("shark", 740), S * 0.5, S * 0.64)
        for x, y, r in ((0.2, 0.42, 34), (0.83, 0.47, 26), (0.74, 0.87, 22), (0.17, 0.80, 20)):
            self.glint(card, S * x, S * y, r, (255, 236, 170))
        self.title(card, "VIP", y=0.2, size=230)
        return self.finish(card)

    def den_arch(self, card, cx, base, half, height):
        """A den doorway: a rounded arch of Grotto stones on jambs, a dark glowing way in,
        brass lanterns either side (DenDoor's shape)."""
        Image, ImageDraw, ImageFilter, k = self.Image, self.ImageDraw, self.ImageFilter, self.k
        layer = self.layer()
        d = ImageDraw.Draw(layer)
        spring = base - height + half  # where the arch springs from the jambs
        inner = half - 70
        # The way in: dark, the den's glow low in it
        hole = Image.new("L", (self.S, self.S), 0)
        hd = ImageDraw.Draw(hole)
        hd.rectangle((cx - inner, spring, cx + inner, base), fill=255)
        hd.pieslice((cx - inner, spring - inner, cx + inner, spring + inner), 180, 360, fill=255)
        layer.paste((6, 16, 28, 255), (0, 0), hole)
        glow = Image.new("L", (self.S, self.S), 0)
        ImageDraw.Draw(glow).ellipse((cx - inner * 0.9, base - inner * 0.9, cx + inner * 0.9, base + inner * 0.5), fill=150)
        glow = self.ImageChops.multiply(glow.filter(ImageFilter.GaussianBlur(50)), hole)
        layer.paste(DEN_TEAL + (255,), (0, 0), glow)
        # Voussoirs round the arch, then jamb stones down each side
        n = 9
        for i in range(n):
            a0, a1 = math.pi + i * math.pi / n + 0.025, math.pi + (i + 1) * math.pi / n - 0.025
            pts = [(cx + math.cos(a) * r, spring + math.sin(a) * r) for r, a in ((inner, a0), (half, a0), (half, a1), (inner, a1))]
            d.polygon(pts, fill=GROTTO[i % 4] + (255,), outline=GROTTO_MORTAR + (255,), width=5)
        for side in (-1, 1):
            x0, x1 = (cx - half, cx - inner) if side < 0 else (cx + inner, cx + half)
            y = spring
            rows = 4
            step = (base - spring) / rows
            for j in range(rows):
                d.rectangle((x0, y + j * step + 3, x1, y + (j + 1) * step - 3), fill=GROTTO[(j + (side > 0)) % 4] + (255,), outline=GROTTO_MORTAR + (255,), width=5)
        # A threshold step
        d.rounded_rectangle((cx - half - 26, base - 6, cx + half + 26, base + 30), 10, fill=(64, 60, 82, 255), outline=GROTTO_MORTAR + (255,), width=5)
        # Top light on the stones
        light = self.layer()
        ImageDraw.Draw(light).arc((cx - half + 6, spring - half + 6, cx + half - 6, spring + half - 6), 190, 350, fill=(200, 220, 255, 70), width=8)
        layer.alpha_composite(light)
        card.alpha_composite(k.with_shadow(layer, 16, 120).crop((48, 48, 48 + self.S, 48 + self.S)))
        # Brass lanterns on the jambs, lit
        for side in (-1, 1):
            x, y = cx + side * (half + 6), spring + 40
            halo = self.layer()
            ImageDraw.Draw(halo).ellipse((x - 70, y - 60, x + 70, y + 80), fill=k.GOLD + (110,))
            card.alpha_composite(halo.filter(ImageFilter.GaussianBlur(26)))
            lamp = self.layer()
            ld = ImageDraw.Draw(lamp)
            ld.rounded_rectangle((x - 20, y - 10, x + 20, y + 50), 8, fill=(255, 226, 140, 255), outline=(120, 84, 30, 255), width=6)
            ld.polygon([(x - 28, y - 8), (x + 28, y - 8), (x, y - 34)], fill=(196, 140, 52, 255), outline=(120, 84, 30, 255))
            ld.rectangle((x - 24, y + 48, x + 24, y + 58), fill=(196, 140, 52, 255), outline=(120, 84, 30, 255), width=3)
            card.alpha_composite(lamp)

    def den(self):
        S, k = self.S, self.k
        card = self.background()
        self.bubbles(card, ((140, 360, 14), (112, 430, 8), (895, 640, 11), (150, 730, 10)))
        self.den_arch(card, S * 0.5, S * 0.84, S * 0.34, S * 0.52)
        card = k.frame(card)
        k.place(card, self.fish("den", 720), S * 0.5, S * 0.74)
        k.place(card, self.coin("+25", 210), S * 0.80, S * 0.40)
        self.title(card, "BIGGER DEN", size=150, max_w=PASS_TITLE)
        return self.finish(card)

    def garden(self):
        S, k = self.S, self.k
        card = self.background(glow=(20, 120, 140))
        self.bubbles(card)
        card = k.frame(card)
        k.place(card, self.fish("garden", 800), S * 0.5, S * 0.64)
        for x, y, r, c in ((0.2, 0.42, 30, k.AQUA), (0.8, 0.40, 26, (255, 236, 170)), (0.86, 0.66, 20, k.AQUA), (0.15, 0.68, 22, (255, 236, 170)), (0.55, 0.36, 18, k.AQUA)):
            self.glint(card, S * x, S * y, r, c)
        self.title(card, "DEEP GARDEN", size=150, max_w=PASS_TITLE)
        return self.finish(card)

    def second_chance(self):
        S, k = self.S, self.k
        card = self.background(glow=(30, 120, 150))
        self.rings(card, S * 0.5, S * 0.64, k.TEAL, [250, 330, 410], squash=0.9, alpha=55)
        self.bubbles(card)
        card = k.frame(card)
        k.place(card, self.fish("ring", 620), S * 0.5, S * 0.62)
        self.title(card, "SECOND CHANCE", size=150)
        return self.finish(card)

    def frenzy(self):
        S, k = self.S, self.k
        cx, cy = S * 0.5, S * 0.62
        card = self.background(glow=(40, 130, 150), glow_box=(0.1, 0.28, 0.9, 0.96))
        self.rays(card, cx, cy, k.TEAL, n=14, alpha=70, outer=700, width=0.1)
        self.rays(card, cx, cy, k.GOLD, n=14, alpha=50, outer=560, width=0.05, turn=math.pi / 14)
        self.bubbles(card)
        card = k.frame(card)
        # The six fish swimming out of the burst, heads outward: (render, width, the
        # spoke's angle clockwise from the right, its radius)
        spokes = [("side_ReefShark", 360, -150, 275), ("side_Puffer", 195, -90, 225), ("side_Cuda", 340, -30, 275),
                  ("side_Angler", 255, 30, 265), ("side_Nibbler", 210, 90, 232), ("side_MorayEel", 330, 150, 275)]
        for name, width, deg, r in spokes:
            a = math.radians(deg)
            right = math.cos(a) > 0.2  # the renders face left: right-going fish are mirrored
            tilt = -deg if right else 180 - deg
            k.place(card, self.fish(name, width, flip=right, rotate=tilt, shadow=(14, 110)), cx + math.cos(a) * r, cy + math.sin(a) * r * 0.86)
        k.place(card, self.coin("×2", 180), cx, cy)
        self.title(card, "FRENZY", size=180)
        return self.finish(card)

    def double_haul(self, size, label, width=None, at=(0.47, 0.62)):
        S, k = self.S, self.k
        card = self.background(glow=(40, 110, 130))
        self.rays(card, S * 0.5, S * 0.64, k.GOLD, n=16, alpha=34, outer=640)
        self.bubbles(card)
        card = k.frame(card)
        width = width or {"haul_big": 690, "haul_huge": 760}.get(size, 600)
        k.place(card, self.fish(size, width), S * at[0], S * at[1])
        k.place(card, self.coin("×2", 200), S * 0.80, S * 0.43)
        k.place(card, k.pill(label, 46), S * 0.5, S * 0.885)
        self.title(card, "DOUBLE HAUL", size=150)
        return self.finish(card)

    def shells(self, scene, label, width):
        S, k = self.S, self.k
        card = self.background(glow=(30, 110, 140))
        self.rings(card, S * 0.5, S * 0.86, k.TEAL, [200, 290, 380], alpha=60)
        self.bubbles(card)
        card = k.frame(card)
        k.place(card, self.fish(scene, width), S * 0.5, S * 0.63)
        for x, y, r, c in ((0.18, 0.44, 30, (255, 255, 255)), (0.83, 0.42, 26, (255, 236, 170)), (0.86, 0.72, 20, (255, 255, 255)), (0.14, 0.74, 18, (255, 236, 170))):
            self.glint(card, S * x, S * y, r, c)
        self.title(card, label, size=160)
        return self.finish(card)


def cards(folder: pathlib.Path):
    c = Cards(folder)
    known = ids()
    make = [
        ("DoubleMass", c.double_mass),
        ("VIP", c.vip),
        ("DenExpansion", c.den),
        ("DeepGarden", c.garden),
        ("SecondChance", c.second_chance),
        ("ServerFrenzy", c.frenzy),
        ("DoubleHaulSmall", lambda: c.double_haul("haul_small", "SMALL HAUL")),
        ("DoubleHaulBig", lambda: c.double_haul("haul_big", "BIG HAUL", at=(0.46, 0.63))),
        ("DoubleHaulHuge", lambda: c.double_haul("haul_huge", "HUGE HAUL")),
        ("ShellPouch", lambda: c.shells("pouch", "100 SHELLS", 560)),
        ("ShellChest", lambda: c.shells("chest", "600 SHELLS", 700)),
    ]
    OUT.mkdir(exist_ok=True)
    written = {}
    for key, build in make:
        path = OUT / f"icon_{known[key]}_512.png"
        image = build()
        image.save(path)
        written[key] = image
        print(f"[product_icons] {key} -> {path}")
    # The rewarded ad doubles a small Haul: the small icon
    path = OUT / f"icon_{known['AdDoubleHaul']}_512.png"
    written["DoubleHaulSmall"].save(path)
    print(f"[product_icons] AdDoubleHaul -> {path}")


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("renders", "cards", "all"):
        sys.exit(__doc__.split("\n\n")[1])
    folder = pathlib.Path(sys.argv[2]).resolve()
    if sys.argv[1] in ("renders", "all"):
        renders(folder, sys.argv[3:])  # optionally just the named renders
    if sys.argv[1] in ("cards", "all"):
        cards(folder)


if __name__ == "__main__":
    if bpy is not None and "--" in sys.argv:
        blender_main(sys.argv[sys.argv.index("--") + 1 :])
    else:
        main()
