"""Bakes a fish GLB's texture-space maps for the shade skins (make_shades.py).

    <blender python> tools/shades/bake_maps.py -- <fish.glb> <out.npz> [flip] [size]

For every texel of the fish's color texture this records where it sits on the body:
its 3D position and surface normal in a squared-up body frame (head toward -Y, back
up +Z, the fish's sides along X), so the skins can lay stripes, spots, bands and
sheens on the body in 3D and nothing breaks at the texture's UV seams. The color
texture comes along, plus flat face renders (front, three-quarter and side) with a
UV pass, for finding the eyes. Ported from Hatch & Snatch's tools/mutations; the
head is found the way rig_fish.py finds it (the deep, wide end; a tail is a thin
blade), and `flip` swaps that guess.
"""

import math
import pathlib
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :]
SRC, OUT = argv[0], argv[1]
FLIP = len(argv) > 2 and argv[2] == "flip"
SIZE = int(argv[3]) if len(argv) > 3 else 1024

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
if len(meshes) > 1:
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.data.transform(body.matrix_world)
body.matrix_world = Matrix.Identity(4)

# The color texture (Tripo: one material, one base-color image)
color_image = None
for slot in body.material_slots:
    bsdf = next((n for n in slot.material.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        continue
    link = bsdf.inputs["Base Color"].links
    if link and link[0].from_node.type == "TEX_IMAGE":
        color_image = link[0].from_node.image
assert color_image is not None, "no color texture"

# Square up like rig_fish.py: the long horizontal axis onto Y, head toward -Y
co = np.array([v.co[:] for v in body.data.vertices])
centre = (co.max(0) + co.min(0)) / 2
body.data.transform(Matrix.Translation(-Vector(centre)))
co -= centre
evals, evecs = np.linalg.eigh(np.cov(co[:, :2].T))
axis = evecs[:, np.argmax(evals)]
body.data.transform(Matrix.Rotation(math.atan2(axis[0], axis[1]), 4, "Z"))
co = np.array([v.co[:] for v in body.data.vertices])
y0, length = co[:, 1].min(), np.ptp(co[:, 1])


def girth(lo, hi):
    band = co[(co[:, 1] >= y0 + lo * length) & (co[:, 1] < y0 + hi * length)]
    if len(band) < 8:
        return 0.0
    return np.ptp(band[:, 0]) * np.ptp(band[:, 2])


head_low = girth(0.08, 0.3) > girth(0.7, 0.92)
if FLIP:
    head_low = not head_low
if not head_low:
    body.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
vs = np.array([v.co[:] for v in body.data.vertices])
mn, mx = vs.min(0), vs.max(0)
length = float(mx[1] - mn[1])

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 1
scene.cycles.device = "CPU"
scene.render.bake.margin = 6

mat = body.material_slots[0].material
nodes, links = mat.node_tree.nodes, mat.node_tree.links
out_node = next(n for n in nodes if n.type == "OUTPUT_MATERIAL")
orig_surface = out_node.inputs["Surface"].links[0].from_socket
geo = nodes.new("ShaderNodeNewGeometry")
emit = nodes.new("ShaderNodeEmission")
target = nodes.new("ShaderNodeTexImage")
mapping = nodes.new("ShaderNodeVectorMath")  # (p - mn) / extent
mapping.operation = "MULTIPLY_ADD"
extent = np.maximum(mx - mn, 1e-6)
mapping.inputs[1].default_value = tuple(1.0 / extent)
mapping.inputs[2].default_value = tuple(-mn / extent)


def bake(name, socket, transform=True):
    img = bpy.data.images.new(name, SIZE, SIZE, alpha=True, float_buffer=True)
    img.generated_color = (0, 0, 0, 0)
    target.image = img
    nodes.active = target
    for link in list(emit.inputs["Color"].links):
        links.remove(link)
    if transform:
        links.new(socket, mapping.inputs[0])
        links.new(mapping.outputs[0], emit.inputs["Color"])
    else:
        links.new(socket, emit.inputs["Color"])
    links.new(emit.outputs[0], out_node.inputs["Surface"])
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.bake(type="EMIT")
    arr = np.array(img.pixels[:], dtype=np.float32).reshape(SIZE, SIZE, 4)
    return arr[::-1]  # top row first, like the PNG


position = bake("pos", geo.outputs["Position"])
normal = bake("nrm", geo.outputs["Normal"], transform=False)

# Face views for finding the eyes: a fish's eyes sit on the sides of its head, so
# the head from the front, the three-quarters and both sides, flat and as a UV pass
FACE = 512
scene.render.resolution_x = FACE
scene.render.resolution_y = FACE
scene.render.image_settings.file_format = "OPEN_EXR"
scene.render.image_settings.color_depth = "32"
scene.view_settings.view_transform = "Raw"
scene.cycles.samples = 4
scene.cycles.use_denoising = False
scene.render.film_transparent = True
uvmap = nodes.new("ShaderNodeUVMap")
tex_color = next(n for n in nodes if n.type == "TEX_IMAGE" and n.image == color_image)
head = vs[vs[:, 1] < mn[1] + 0.3 * length]
face_c = Vector(head.mean(0))
face_r = float(max(np.ptp(head[:, 0]), np.ptp(head[:, 2]), 0.3 * length))
cam_data = bpy.data.cameras.new("FaceCam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = face_r * 1.3
cam = bpy.data.objects.new("FaceCam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
tmp = pathlib.Path(OUT).with_suffix(".face.exr")


def render_pass(socket):
    for link in list(emit.inputs["Color"].links):
        links.remove(link)
    links.new(socket, emit.inputs["Color"])
    links.new(emit.outputs[0], out_node.inputs["Surface"])
    scene.render.filepath = str(tmp)
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(str(tmp))
    arr = np.array(img.pixels[:], dtype=np.float32).reshape(FACE, FACE, 4)[::-1]
    bpy.data.images.remove(img)
    return arr


faces = []
for yaw in (0.0, 40.0, -40.0, 90.0, -90.0):
    direction = Vector((math.sin(math.radians(yaw)), -math.cos(math.radians(yaw)), 0.12)).normalized()
    cam.location = face_c + direction * (length * 2)
    cam.rotation_euler = (face_c - cam.location).to_track_quat("-Z", "Y").to_euler()
    flat = render_pass(tex_color.outputs["Color"])
    uv = render_pass(uvmap.outputs["UV"])
    faces.append(np.concatenate([flat[..., :3], uv[..., :2], flat[..., 3:4]], -1))
tmp.unlink(missing_ok=True)
links.new(orig_surface, out_node.inputs["Surface"])

w, h = color_image.size
color = np.array(color_image.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1, :, :3]

np.savez_compressed(
    OUT,
    color=(np.clip(color, 0, 1) * 255).astype(np.uint8),
    position=(position[:, :, :3] * extent + mn).astype(np.float16),  # body frame, model units
    normal=normal[:, :, :3].astype(np.float16),
    covered=position[:, :, 3] > 0.5,  # baked texels (unbaked stay transparent)
    bounds=np.stack([mn, mx]),
    length=length,
    faces=np.stack(faces).astype(np.float32),  # (view, y, x, [r, g, b, u, v, alpha])
)
print(f"[bake] {SRC}: texture {w}x{h}, maps {SIZE}, length {length:.3f}")
