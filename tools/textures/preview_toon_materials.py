#!/usr/bin/env python3
"""Previews the toon material maps (make_toon_materials.py): each one on a small scene
in Blender (a displaced floor, a faceted boulder and a rough cave wall), tinted with the
game's colour for that material and softly lit, beside a flat 2x2 tiling swatch of the
grey map, all on one contact sheet. Needs bpy (python3.11, `pip install bpy`).

  python3.11 tools/textures/preview_toon_materials.py <out_dir>                # every material
  python3.11 tools/textures/preview_toon_materials.py <out_dir> Rock Sand      # only those

Writes <out_dir>/render_<Material>.png and <out_dir>/toon_materials_sheet.png.
"""

from __future__ import annotations

import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
TEX = ROOT / "assets" / "textures"

# The colour each material is multiplied by in game: Cave.COLORS and Shelf.COLORS for
# the Terrain, the den floors (Config/Dens) and WorldService's wood for parts.
# CrackedLava carries its own colour, so it's shown untinted (its MaterialColor
# should be white once the map is in).
TINTS = {
    "Rock": (96, 122, 130),
    "Slate": (70, 92, 104),
    "Basalt": (62, 74, 84),
    "Sandstone": (150, 138, 118),
    "Sand": (206, 194, 156),
    "Mud": (44, 60, 84),
    "CrackedLava": (255, 255, 255),
    "Pebble": (64, 156, 168),
    "Marble": (226, 228, 234),
    "WoodPlanks": (132, 104, 76),
    "Wood": (132, 96, 66),
}
TILE = 2.4  # Blender units per tile: the boulder is about one tile across
RES = 480


def render(name: str, out: pathlib.Path):
    import bpy

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = scene.render.resolution_y = RES
    scene.view_settings.view_transform = "Standard"
    scene.render.image_settings.file_format = "PNG"

    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.42, 0.5, 0.58, 1)
    bg.inputs["Strength"].default_value = 0.9

    # Material: the map, box-projected in world space, times the tint
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out_node = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.85
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1 / TILE, 1 / TILE, 1 / TILE)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(TEX / f"toon_{name}.png"))
    tex.projection = "BOX"
    tex.projection_blend = 0.25
    tint = nt.nodes.new("ShaderNodeRGB")
    tint.outputs[0].default_value = (*[(c / 255) ** 2.2 for c in TINTS[name]], 1)
    mul = nt.nodes.new("ShaderNodeVectorMath")
    mul.operation = "MULTIPLY"
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
    nt.links.new(tex.outputs["Color"], mul.inputs[0])
    nt.links.new(tint.outputs[0], mul.inputs[1])
    nt.links.new(mul.outputs[0], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs[0], out_node.inputs["Surface"])

    clouds = bpy.data.textures.new("Lumps", "CLOUDS")
    clouds.noise_scale = 0.9

    def finish(obj, strength, flat=True):
        obj.data.materials.append(mat)
        mod = obj.modifiers.new("Displace", "DISPLACE")
        mod.texture = clouds
        mod.strength = strength
        mod.texture_coords = "GLOBAL"
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier="Displace")
        for poly in obj.data.polygons:
            poly.use_smooth = not flat

    # Floor
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=40, y_subdivisions=40, size=9, location=(0, 0, 0))
    finish(bpy.context.object, 0.25)
    # Cave wall behind, leaning back a little
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=44, y_subdivisions=24, size=12, location=(0, 2.6, 2.6))
    wall = bpy.context.object
    wall.rotation_euler = (1.45, 0, 0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    finish(wall, 0.9)
    # A faceted boulder
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0, location=(0.35, 0.4, 0.55))
    rock = bpy.context.object
    rock.scale = (1.25, 1.0, 0.78)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    finish(rock, 0.45)

    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 3.8
    sun_data.angle = 0.35
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (0.85, -0.55, -0.5)
    scene.collection.objects.link(sun)

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 38
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (-0.6, -5.4, 2.7)
    target = bpy.data.objects.new("Target", None)
    target.location = (0.25, 0.7, 0.6)
    scene.collection.objects.link(target)
    track = cam.constraints.new("TRACK_TO")
    track.target = target
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"
    scene.camera = cam

    scene.render.filepath = str(out / f"render_{name}.png")
    bpy.ops.render.render(write_still=True)


def swatch(name: str, size: int) -> Image.Image:
    img = Image.open(TEX / f"toon_{name}.png").convert("RGB")
    tile = Image.new("RGB", (img.width * 2, img.height * 2))
    for i in range(2):
        for j in range(2):
            tile.paste(img, (i * img.width, j * img.height))
    return tile.resize((size, size), Image.LANCZOS)


def sheet(names: list[str], out: pathlib.Path):
    pad, cell, label = 16, RES, 34
    cols = 2
    card_w = cell * 2 + pad
    rows = (len(names) + cols - 1) // cols
    w = pad + cols * (card_w + pad)
    h = 64 + rows * (cell + label + pad) + pad
    canvas = Image.new("RGB", (w, h), (24, 28, 34))
    draw = ImageDraw.Draw(canvas)
    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    try:
        big = ImageFont.truetype(font_path.replace("Sans.ttf", "Sans-Bold.ttf"), 28)
        small = ImageFont.truetype(font_path, 20)
    except OSError:
        big = small = ImageFont.load_default()
    draw.text((pad, 16), "Toon materials: grey map (2x2 tiles) | tinted in game colour", fill=(235, 240, 245), font=big)
    for k, name in enumerate(names):
        x = pad + (k % cols) * (card_w + pad)
        y = 64 + (k // cols) * (cell + label + pad)
        tint = TINTS[name]
        draw.text((x, y + 4), f"{name}   tint {tint}", fill=(220, 226, 232), font=small)
        canvas.paste(swatch(name, cell), (x, y + label))
        r = out / f"render_{name}.png"
        if r.exists():
            canvas.paste(Image.open(r).convert("RGB").resize((cell, cell)), (x + cell + pad, y + label))
    canvas.save(out / "toon_materials_sheet.png")
    print(f"[preview] {out / 'toon_materials_sheet.png'}")


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        return 1
    out = pathlib.Path(argv[0])
    out.mkdir(parents=True, exist_ok=True)
    names = argv[1:] or list(TINTS)
    for name in names:
        render(name, out)
        print(f"[preview] render_{name}.png", flush=True)
    sheet(list(TINTS), out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
