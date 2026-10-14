"""Close-up views of a fish's mouth with a UV pass, for finding small teeth
(make_shades.py `_teeth`, teeth.json `mouth`).

    <blender python> tools/shades/bake_mouth.py -- <fish.glb> <out.npz> <x,y,z> <radius> [flip]

bake_maps.py's head views are 512 px of the whole head, where the Reef Shark's teeth
are a pixel or two each. This squares the fish up exactly as bake_maps.py does (the
same body frame its `position` map is in), then renders the mouth at <x,y,z> (body
frame, model units: read it off the fish's `position` map) from the front, the
three-quarters and the sides, a little from below, 1024 px across 2 x <radius>. Saves
`faces` in bake_maps.py's layout: (view, y, x, [r, g, b, u, v, alpha]).
"""

import math
import pathlib
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :]
SRC, OUT = argv[0], argv[1]
CENTRE = Vector(tuple(float(v) for v in argv[2].split(",")))
RADIUS = float(argv[3])
FLIP = len(argv) > 4 and argv[4] == "flip"
VIEW = 1024

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

# The body frame, as bake_maps.py squares it up
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
print(f"[mouth] bounds {vs.min(0)} {vs.max(0)}")

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 4
scene.cycles.use_denoising = False
scene.render.resolution_x = scene.render.resolution_y = VIEW
scene.render.image_settings.file_format = "OPEN_EXR"
scene.render.image_settings.color_depth = "32"
scene.view_settings.view_transform = "Raw"
scene.render.film_transparent = True

mat = body.material_slots[0].material
nodes, links = mat.node_tree.nodes, mat.node_tree.links
out_node = next(n for n in nodes if n.type == "OUTPUT_MATERIAL")
bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
tex_color = bsdf.inputs["Base Color"].links[0].from_node
emit = nodes.new("ShaderNodeEmission")
uvmap = nodes.new("ShaderNodeUVMap")
cam_data = bpy.data.cameras.new("MouthCam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = RADIUS * 2
cam = bpy.data.objects.new("MouthCam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
tmp = pathlib.Path(OUT).with_suffix(".mouth.exr")


def render_pass(socket):
    for link in list(emit.inputs["Color"].links):
        links.remove(link)
    links.new(socket, emit.inputs["Color"])
    links.new(emit.outputs[0], out_node.inputs["Surface"])
    scene.render.filepath = str(tmp)
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(str(tmp))
    arr = np.array(img.pixels[:], dtype=np.float32).reshape(VIEW, VIEW, 4)[::-1]
    bpy.data.images.remove(img)
    return arr


faces = []
for yaw in (0.0, 35.0, -35.0, 70.0, -70.0):
    direction = Vector((math.sin(math.radians(yaw)), -math.cos(math.radians(yaw)), -0.2)).normalized()
    cam.location = CENTRE + direction * (length * 2)
    cam.rotation_euler = (CENTRE - cam.location).to_track_quat("-Z", "Y").to_euler()
    flat = render_pass(tex_color.outputs["Color"])
    uv = render_pass(uvmap.outputs["UV"])
    faces.append(np.concatenate([flat[..., :3], uv[..., :2], flat[..., 3:4]], -1))
tmp.unlink(missing_ok=True)
np.savez_compressed(OUT, faces=np.stack(faces).astype(np.float16))
print(f"[mouth] {SRC} -> {OUT}")
