"""Renders the start screen's documentary shots (run_start.sh) at their key frames.

    EGL_PLATFORM=surfaceless <bpy python> start_render.py -- <dir with start.txt>

For each shot's chosen plan (SHOT|, CAM|, FISH|, MARK| lines from start_shots.luau)
the Terrain's fill ops (OP| lines) are voxelized round the camera's path and turned
into a mesh, the school's fish are drawn as simple bodies at each key frame, and the
water's haze is laid over by depth in the biome's own colour. What only exists as
parts at run time gets rough stand-ins so the composition can be judged: kelp stalks
in the Kelp Shallows, coral heads on the reef, the great temple's platform and
columns in the Ruins, chimney throats in the Vents (Shelf's own chimneys are Terrain).
Then the start screen's layout is drawn over it as the player sees it: the letterbox
bars, the lower third, the title, the how-to cards and the prompt.
Writes start_<shot>_<k>.png and start_sheet.png. SHOTS=a,b limits the shots;
RES=w,h (960,540), SAMPLES (16), CELL (studs per voxel, 2.5).
"""
import json
import math
import os
import random
import sys

import bpy
import mathutils
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cave_render  # noqa: E402  (rasterize, build_mesh, grid_axes)

argv = sys.argv[sys.argv.index("--") + 1 :]
DIR = os.path.abspath(argv[0])
SHOTS = [s for s in os.environ.get("SHOTS", "").split(",") if s]
RES = [int(v) for v in os.environ.get("RES", "960,540").split(",")]
SAMPLES = int(os.environ.get("SAMPLES", "16"))
CELL = float(os.environ.get("CELL", "2.5"))
M = cave_render.M

FONT_HEAVY = "/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf"
FONT_BOLD = "/usr/share/fonts/opentype/inter/Inter-Bold.otf"
FONT_SEMI = "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf"

# Cave.COLORS and Shelf.COLORS (sRGB), the toon-lifted look
TERRAIN = {
    1: (96, 122, 130),
    2: (70, 92, 104),
    3: (150, 138, 118),
    4: (206, 194, 156),
    5: (88, 98, 110),
    6: (54, 72, 98),
    7: (255, 120, 40),
}
# How bright the light from above is by biome, and how far the haze lets you see
LIGHT = {
    "KelpShallows": (3.6, 150),
    "CoralReef": (3.6, 170),
    "ShipwreckGraveyard": (3.0, 135),
    "OpenBlue": (2.2, 230),
    "SunkenRuins": (1.8, 190),
    "HydrothermalVents": (1.0, 150),
    "AbyssalTrench": (0.35, 120),
}
GLOWS = {"Lanternfish": (0.35, 0.92, 1.0), "Viperfish": (0.38, 0.9, 0.95), "Hatchetfish": (0.33, 0.95, 0.9)}


def lin(c):
    return tuple((v / 255 if v > 1.001 else v) ** 2.2 for v in c)


def vec(s):
    return mathutils.Vector([float(v) for v in s.split(",")])


def read():
    ops, shots, cams, fish, marks = [], {}, {}, {}, {}
    for line in open(os.path.join(DIR, "start.txt")):
        f = line.rstrip("\n").split("|")
        tag = f[0]
        if tag == "OP":
            op = json.loads(line[3:])
            if op["material"] not in cave_render.MATERIALS:
                op["material"] = "Rock"
            ops.append(op)
        elif tag == "SHOT":
            b = [float(v) for v in f[5].split(",")]
            shots[f[1]] = {
                "biome": f[2],
                "haze": [float(v) for v in f[3].split(",")],
                "bounds": ((b[0], b[1]), (b[2], b[3]), (b[4], b[5])),
                "name": f[6],
                "place": f[7],
            }
        elif tag == "CAM":
            cams.setdefault(f[1], []).append((int(f[2]), vec(f[3]), vec(f[4]), float(f[5]), float(f[6])))
        elif tag == "FISH":
            fish.setdefault((f[1], int(f[2])), []).append(
                (vec(f[3]), vec(f[4]), float(f[5]), float(f[6]), [float(v) for v in f[7].split(",")])
            )
        elif tag == "MARK":
            marks[f[1]] = vec(f[2])
    return ops, shots, cams, fish, marks


def material(name, color, emit=0.0, rough=0.6):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    if emit > 0:
        bsdf.inputs["Emission Color"].default_value = (*color, 1)
        bsdf.inputs["Emission Strength"].default_value = emit
    return mat


def shape(kind, name, position, size, rotation, mat):
    """A cube or sphere `size` (studs, Roblox axes) at `position`, turned by `rotation`
    (a 3x3 in Roblox space), with material `mat`."""
    if kind == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.5, segments=20, ring_count=10)
    elif kind == "cylinder":
        bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=0.5, depth=1)
        # Blender's cylinder runs along its Z: Roblox's Y in our frame
        bpy.context.active_object.data.transform(mathutils.Matrix.Rotation(-math.pi / 2, 4, "X"))
    else:
        bpy.ops.mesh.primitive_cube_add(size=1)
    obj = bpy.context.active_object
    obj.name = name
    rot = rotation if rotation is not None else mathutils.Matrix.Identity(3)
    world = (M @ rot).to_4x4()
    world.translation = M @ mathutils.Vector(position)
    obj.matrix_world = world @ mathutils.Matrix.Diagonal((size[0], size[1], size[2], 1))
    # (a Roblox-space size: our M maps y to z and z to -y, so scale before the turn)
    obj.data.materials.append(mat)
    if kind == "sphere":
        for poly in obj.data.polygons:
            poly.use_smooth = True
    return obj


def frame_of(look):
    """A Roblox-space rotation whose -Z is `look` (its right and up columns)."""
    back = -look.normalized()
    up = mathutils.Vector((0, 1, 0))
    right = up.cross(back)
    if right.length < 1e-4:
        right = mathutils.Vector((1, 0, 0))
    right.normalize()
    up = back.cross(right)
    return mathutils.Matrix((right, up, back)).transposed()


def ground_top(grid, x, z):
    xs, ys, zs = cave_render.grid_axes()
    i = int(np.clip(np.searchsorted(xs, x), 0, len(xs) - 1))
    k = int(np.clip(np.searchsorted(zs, z), 0, len(zs) - 1))
    column = np.nonzero(grid[i, :, k])[0]
    if len(column) == 0:
        return None
    return ys[column.max()] + cave_render.CELL / 2


def stand_ins(shot_id, shot, grid, marks, path_center):
    """Rough stand-ins for the run-time dressing round the shot."""
    rng = random.Random(hash(shot_id) & 0xFFFF)
    biome = shot["biome"]
    (x0, x1), _, (z0, z1) = shot["bounds"]
    cx, cz = path_center
    if biome in ("KelpShallows", "ShipwreckGraveyard"):
        kelp = material("Kelp", lin((78, 116, 52)), rough=0.8)
        for _ in range(16 if biome == "KelpShallows" else 6):
            kx, kz = cx + rng.uniform(-160, 160), cz + rng.uniform(-160, 160)
            for _ in range(rng.randint(8, 16)):
                x, z = kx + rng.uniform(-34, 34), kz + rng.uniform(-34, 34)
                top = ground_top(grid, x, z)
                if top is None:
                    continue
                height = rng.uniform(50, 190) * (1 if biome == "KelpShallows" else 0.8)
                shape("cylinder", "Kelp", (x, top + height / 2, z), (1.2, height, 1.2), None, kelp)
                for b in range(3):
                    y = top + height * (b + 1) / 4
                    blade = frame_of(mathutils.Vector((math.cos(b * 2.1), -0.4, math.sin(b * 2.1))))
                    shape("cube", "Blade", (x, y, z), (3.2, 0.2, 12), blade, kelp)
    if biome == "CoralReef":
        colors = [(240, 110, 120), (255, 160, 80), (170, 110, 220), (250, 220, 110), (90, 200, 190)]
        mats = [material(f"Coral{i}", lin(c)) for i, c in enumerate(colors)]
        for _ in range(90):
            x, z = cx + rng.uniform(-110, 110), cz + rng.uniform(-110, 110)
            top = ground_top(grid, x, z)
            if top is None:
                continue
            size = rng.uniform(2, 8) * 1.6
            shape("sphere", "Coral", (x, top + size * 0.35, z), (size, size * 0.8, size), None, rng.choice(mats))
    if biome == "ShipwreckGraveyard" and shot_id in marks:
        # A stand-in wreck at the shot's landmark (WorldService wreck: a listing keel,
        # two hull sides, ribs and a broken mast)
        keel = marks[shot_id]
        floor = keel.y - 8
        wood = material("Wood", lin((96, 74, 52)), rough=0.9)
        light_wood = material("WoodLight", lin((128, 102, 74)))
        length, beam = 88, 88 * 0.28
        turn = mathutils.Matrix.Rotation(0.7, 3, "Y") @ mathutils.Matrix.Rotation(math.radians(18), 3, "Z")
        def at(x, y, z):
            return mathutils.Vector((keel.x, floor, keel.z)) + turn @ mathutils.Vector((x, y, z))
        shape("cube", "Keel", at(0, 2.5, 0), (length, 5, beam * 0.55), turn, wood)
        for side in (-1, 1):
            tilt = turn @ mathutils.Matrix.Rotation(math.radians(side * -30), 3, "X")
            shape("cube", "Hull", at(0, beam * 0.24, side * beam * 0.34), (length * 0.92, beam * 0.55, 2.5), tilt, wood)
            for i in range(7):
                x = -length * 0.42 + i * (length * 0.84 / 6)
                rib = turn @ mathutils.Matrix.Rotation(math.radians(side * -22), 3, "X")
                shape("cube", "Rib", at(x, beam * 0.4, side * beam * 0.46), (2, beam * 0.7, 2), rib, light_wood)
        shape("cylinder", "Mast", at(10, beam * 0.9, 0), (2.6, beam * 1.5, 2.6), turn, light_wood)
    if biome == "SunkenRuins" and shot_id in marks:
        # The great temple (Ruins.luau greatTemple, its frame T0) and the avenue's columns
        temple = marks[shot_id]
        floor = temple.y - 24
        out = mathutils.Vector((temple.x, 0, temple.z)).normalized()
        across = mathutils.Vector((out.z, 0, -out.x))  # T0's right (-(out x up))
        rot = mathutils.Matrix((across, mathutils.Vector((0, 1, 0)), out)).transposed()
        stone = material("Marble", lin((196, 212, 206)))
        shade = material("Shade", lin((150, 172, 172)))
        for k, (w, d) in enumerate(((104, 130), (90, 116), (76, 102))):
            centre = mathutils.Vector((temple.x, floor + k * 6 + 3, temple.z))
            shape("cube", "Tier", centre, (w, 6, d), rot, shade)
        for x in (-32, -14, 14, 32):
            for z in (-45, -27, -9, 9, 27, 45):
                if abs(x) < 20 and abs(z) < 40:
                    continue
                p = mathutils.Vector((temple.x, floor + 18 + 15, temple.z)) + across * x + out * z
                shape("cylinder", "Column", p, (5.2, 30, 5.2), None, stone)
        roof = mathutils.Vector((temple.x, floor + 18 + 33, temple.z))
        shape("cube", "Entablature", roof, (76, 5, 102), rot, stone)
        for side in (-1, 1):
            for z in range(-230, -110, 22):
                p = mathutils.Vector((temple.x, floor + 15, temple.z)) + across * (side * 25) + out * z
                shape("cylinder", "AvenueColumn", p, (5.2, 30, 5.2), None, stone)
    if biome == "HydrothermalVents":
        glow = material("Throat", lin((255, 150, 54)), emit=6)
        for _ in range(6):
            x, z = cx + rng.uniform(-90, 90), cz + rng.uniform(-90, 90)
            top = ground_top(grid, x, z)
            if top is None:
                continue
            shape("sphere", "Fissure", (x, top + 0.3, z), (rng.uniform(6, 16), 0.6, rng.uniform(1.2, 2.5)), None, glow)
            light = bpy.data.lights.new("Ember", "POINT")
            light.color = (1.0, 0.55, 0.25)
            light.energy = 6000
            light.shadow_soft_size = 3
            lo = bpy.data.objects.new("Ember", light)
            lo.location = M @ mathutils.Vector((x, top + 4, z))
            bpy.context.scene.collection.objects.link(lo)


def fish_objects(entries, glow):
    made = []
    for i, (pos, look_at, length, height, color) in enumerate(entries):
        look = (look_at - pos).normalized()
        rot = frame_of(look)
        mat = material(f"Fish{i}", lin(color) if max(color) > 1 else tuple(c ** 2.2 for c in color), emit=1.5 if glow else 0, rough=0.4)
        if glow:
            mat.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (*glow, 1)
        height = max(height, length * 0.18)
        body = shape("sphere", "Fish", pos, (height * 0.55, height, length), rot, mat)
        tail = shape("cube", "Tail", pos - look * (length * 0.55), (0.08 * length, height * 0.75, length * 0.28), rot, mat)
        made += [body, tail]
    return made


def depth_material():
    mat = bpy.data.materials.new("Depth")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
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


def haze(beauty, depth, fog_color, fog):
    im = np.asarray(Image.open(beauty).convert("RGB")).astype(np.float32) / 255
    d = np.asarray(Image.open(depth).convert("F")).astype(np.float32) / 65535.0 * 1000.0
    d[d <= 0.01] = 1000.0
    f = 1 - np.exp(-d / fog)
    out = im * (1 - f[..., None]) + np.array(fog_color, dtype=np.float32) * f[..., None]
    # gentle bloom round the brightest bits (glowing fish, the vents' throats)
    lum = out.max(axis=2, keepdims=True)
    bright = np.clip((lum - 0.7) / 0.3, 0, 1) * out
    src = Image.fromarray((bright * 255).astype(np.uint8))
    glow = np.zeros_like(out)
    for radius, weight in ((3, 0.4), (10, 0.35), (24, 0.3)):
        glow += np.asarray(src.filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255 * weight
    out = 1 - (1 - out) * (1 - np.clip(glow, 0, 1))
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))


def font(path, size):
    try:
        return ImageFont.truetype(path, int(size))
    except OSError:
        return ImageFont.load_default()


def overlay(img, shot, k, seconds):
    """The start screen's layout over a frame (StartController, design units 1280x720)."""
    W, H = img.size
    s = min(W / 1280, H / 720)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    bar = int(H * 0.085)
    draw.rectangle((0, 0, W, bar), fill=(0, 0, 0, 240))
    draw.rectangle((0, H - bar, W, H), fill=(0, 0, 0, 240))
    # Title (top): the APEX TIDE logo (marketing/logo.png, once Config/Textures `logo`
    # is set) or the lettering, and its line; the group rests at UIScale 0.86
    sub = font(FONT_BOLD, 17 * s)
    line = "EAT   ·   GROW   ·   BECOME THE APEX"
    logo_path = os.path.join(HERE, "..", "..", "marketing", "logo.png")
    if os.path.exists(logo_path):
        k = 0.86 * s
        cy = H * 0.32
        logo = Image.open(logo_path).convert("RGBA")
        lh = round(200 * k)
        logo = logo.resize((round(lh * logo.width / logo.height), lh), Image.LANCZOS)
        bottom = cy + (110 - 85) * k
        layer.alpha_composite(logo, (int((W - logo.width) / 2), int(bottom - lh)))
        ty = cy + (128 - 85) * k
        draw.text(((W - draw.textlength(line, font=sub)) / 2, ty), line, font=sub, fill=(86, 222, 255, 255))
    else:
        title = font(FONT_HEAVY, 72 * s)
        tw = draw.textlength("APEX TIDE", font=title)
        ty = int(H * 0.2 - 40 * s)
        draw.text(((W - tw) / 2 + 3 * s, ty + 3 * s), "APEX TIDE", font=title, fill=(4, 26, 44, 150))
        draw.text(((W - tw) / 2, ty), "APEX TIDE", font=title, fill=(232, 250, 255, 255))
        draw.text(((W - draw.textlength(line, font=sub)) / 2, ty + 84 * s), line, font=sub, fill=(86, 222, 255, 255))
    # How-to cards above the bottom bar
    card_w, card_h, gap = 236 * s, 64 * s, 12 * s
    left = (W - (3 * card_w + 2 * gap)) / 2
    top = H - bar - 14 * s - card_h
    for i, (head, color) in enumerate((("EAT", (112, 236, 164)), ("BITE", (255, 96, 96)), ("BANK", (255, 204, 92)))):
        x = left + i * (card_w + gap)
        draw.rounded_rectangle((x, top, x + card_w, top + card_h), radius=12 * s, fill=(12, 34, 54, 150), outline=(*color, 120))
        draw.text((x + 12 * s, top + 8 * s), head, font=font(FONT_HEAVY, 15 * s), fill=(*color, 255))
        draw.text((x + 12 * s, top + 30 * s), "how to play, one line", font=font(FONT_SEMI, 12 * s), fill=(234, 247, 252, 200))
    # Lower third (left, above the cards)
    name = font(FONT_HEAVY, 30 * s)
    place = font(FONT_BOLD, 15 * s)
    lx, ly = 52 * s, top - 20 * s - 56 * s
    draw.rectangle((lx - 14 * s, ly + 4 * s, lx - 10 * s, ly + 54 * s), fill=(86, 222, 255, 255))
    draw.text((lx + 2 * s, ly + 2 * s), shot["name"], font=name, fill=(0, 0, 0, 120))
    draw.text((lx, ly), shot["name"], font=name, fill=(240, 250, 255, 255))
    draw.text((lx, ly + 38 * s), shot["place"].upper(), font=place, fill=(170, 230, 245, 255))
    # Prompt in the bottom bar
    prompt = font(FONT_HEAVY, 18 * s)
    text = "PRESS ANY KEY"
    draw.text(((W - draw.textlength(text, font=prompt)) / 2, H - bar / 2 - 11 * s), text, font=prompt, fill=(255, 255, 255, 220))
    # What frame this is (for the preview only)
    draw.text((8 * s, 6 * s), f"{shot['id']}  key {k}  t={seconds:.1f}s", font=font(FONT_SEMI, 12 * s), fill=(255, 255, 255, 160))
    return Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")


def render_shot(shot_id, shot, ops, cams, fish, marks):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.max_bounces = 3
    scene.render.resolution_x, scene.render.resolution_y = RES
    try:
        scene.view_settings.view_transform = "Standard"
    except TypeError:
        pass
    sun_energy, fog = LIGHT.get(shot["biome"], (2.0, 160))
    fog_color = [min(c * 1.1, 1) for c in shot["haze"]]
    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*lin(fog_color), 1)
    bg.inputs["Strength"].default_value = 0.5 + sun_energy * 0.12
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = sun_energy
    sun.color = (0.85, 0.96, 1.0)
    sun.angle = math.radians(8)
    so = bpy.data.objects.new("Sun", sun)
    so.rotation_euler = (math.radians(18), math.radians(10), 0)
    scene.collection.objects.link(so)

    cave_render.BOUNDS = shot["bounds"]
    cave_render.CELL = CELL
    cave_render.COLORS.update({k: lin(v) for k, v in TERRAIN.items()})
    grid = cave_render.rasterize(ops)
    if grid.any():
        cave_render.build_mesh(grid, "Terrain")
    path = [c[1] for c in cams[shot_id]]
    centre = (sum(p.x for p in path) / len(path), sum(p.z for p in path) / len(path))
    stand_ins(shot_id, shot, grid, marks, centre)

    depth = depth_material()
    keys = sorted(cams[shot_id], key=lambda c: c[0])
    outs = []
    for k, position, target, fov, seconds in keys:
        glow = GLOWS.get(shot["name"].replace(" ", ""))
        made = fish_objects(fish.get((shot_id, k), []), glow)
        cam = bpy.data.cameras.new(f"Cam{k}")
        cam.sensor_fit = "VERTICAL"
        cam.angle_y = math.radians(fov)
        cam.clip_start = 0.3
        cam.clip_end = 3000
        co = bpy.data.objects.new(f"Cam{k}", cam)
        scene.collection.objects.link(co)
        p, t = M @ position, M @ target
        co.location = p
        co.rotation_euler = (t - p).to_track_quat("-Z", "Y").to_euler()
        scene.camera = co
        beauty = os.path.join(DIR, f"_beauty_{shot_id}_{k}.png")
        scene.view_layers[0].material_override = None
        scene.cycles.samples = SAMPLES
        scene.cycles.use_denoising = True
        scene.render.image_settings.color_mode = "RGB"
        scene.render.image_settings.color_depth = "8"
        try:
            scene.view_settings.view_transform = "Standard"
        except TypeError:
            pass
        scene.render.filepath = beauty
        bpy.ops.render.render(write_still=True)
        dpath = os.path.join(DIR, f"_depth_{shot_id}_{k}.png")
        scene.view_layers[0].material_override = depth
        strength = bg.inputs["Strength"].default_value
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
        bg.inputs["Strength"].default_value = strength
        img = haze(beauty, dpath, fog_color, fog)
        img = overlay(img, {**shot, "id": shot_id}, k, seconds)
        out = os.path.join(DIR, f"start_{shot_id}_{k}.png")
        img.save(out)
        os.remove(beauty)
        os.remove(dpath)
        outs.append(out)
        print("wrote", out)
        for obj in made:
            bpy.data.objects.remove(obj, do_unlink=True)
    return outs


def sheet(paths):
    rows = {}
    for p in paths:
        shot, k = os.path.basename(p)[6:-4].rsplit("_", 1)
        rows.setdefault(shot, {})[int(k)] = p
    tw, th = RES[0] // 2, RES[1] // 2
    cols = max(len(r) for r in rows.values())
    out = Image.new("RGB", (cols * tw, len(rows) * th), (0, 0, 0))
    for r, shot in enumerate(rows):
        for k, p in rows[shot].items():
            out.paste(Image.open(p).resize((tw, th)), (k * tw, r * th))
    path = os.path.join(DIR, "start_sheet.png")
    out.save(path)
    print("wrote", path)


def main():
    ops, shots, cams, fish, marks = read()
    made = []
    for shot_id, shot in shots.items():
        if SHOTS and shot_id not in SHOTS:
            continue
        made += render_shot(shot_id, shot, ops, cams, fish, marks)
    if made:
        existing = sorted(
            os.path.join(DIR, f) for f in os.listdir(DIR) if f.startswith("start_") and f.endswith(".png") and f != "start_sheet.png"
        )
        sheet(existing)


main()
