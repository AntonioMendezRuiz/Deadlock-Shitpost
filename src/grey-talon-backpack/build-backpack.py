import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parent
BLEND = ROOT / "grey-talon-backpack.blend"
GLB = ROOT / "grey-talon-backpack.glb"
LOGO = ROOT.parent / "logoglovo.png"

def srgb_to_linear(value):
    value = value / 255.0
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


YELLOW = (1.0, srgb_to_linear(205), srgb_to_linear(27), 1.0)
BLACK = (0.006, 0.006, 0.006, 1.0)
DARK = (0.018, 0.018, 0.018, 1.0)
FLOOR = (0.16, 0.16, 0.16, 1.0)


def material(name, color, roughness=0.5, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def image_material(name, image_path, roughness=0.4):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    image = bpy.data.images.load(str(image_path), check_existing=True)
    image.pack()
    tex.image = image
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def rounded_box(name, size, location, bevel_width, mat, segments=4, smooth=False):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel_width > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel_width
        mod.segments = segments
        mod.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if smooth:
        for poly in obj.data.polygons:
            poly.use_smooth = True
    obj.data.materials.append(mat)
    return obj


def text_mesh(name, body, size, location, mat, extrude=0.004, bevel=0.0015):
    bpy.ops.object.text_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.data.body = body
    obj.data.font = bpy.data.fonts.load(r"C:\Windows\Fonts\arialbd.ttf")
    obj.data.size = size
    obj.data.align_x = "CENTER"
    obj.data.align_y = "CENTER"
    obj.data.extrude = extrude
    obj.data.bevel_depth = bevel
    obj.data.bevel_resolution = 3
    obj.rotation_euler = (math.radians(90), 0, 0)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


bpy.ops.wm.read_factory_settings(use_empty=True)

yellow = material("Glovo Yellow", YELLOW, roughness=0.55)
black = material("Bag Black", BLACK, roughness=0.48)
dark = material("Logo Black", DARK, roughness=0.38)
logo_mat = image_material("Glovo Logo Image", LOGO, roughness=0.55)
floor_mat = material("Floor", FLOOR, roughness=0.85)

body = rounded_box("Body", (0.78, 0.78, 0.78), (0, 0, 0), 0.03, yellow, 4, True)
bottom = rounded_box("Bottom Trim", (0.80, 0.80, 0.08), (0, 0, -0.39), 0.02, black, 4, True)
lid = rounded_box("Top Lid", (0.80, 0.80, 0.08), (0, 0, 0.39), 0.02, black, 4, True)

frame = rounded_box("Front Frame", (0.68, 0.024, 0.68), (0, -0.40, 0), 0.02, black, 4, True)
panel = rounded_box("Front Panel", (0.60, 0.028, 0.60), (0, -0.416, 0), 0.015, yellow, 4, True)

bpy.ops.mesh.primitive_plane_add(size=0.52, location=(0, -0.4325, 0))
logo = bpy.context.object
logo.name = "Glovo Logo Image"
logo.rotation_euler = (math.radians(90), 0, 0)
logo.data.materials.append(logo_mat)

side_logos = (
    (
        "Glovo Logo Left",
        Matrix(
            (
                (0, 0, -1, -0.3925),
                (-1, 0, 0, 0),
                (0, 1, 0, 0),
                (0, 0, 0, 1),
            )
        ),
    ),
    (
        "Glovo Logo Right",
        Matrix(
            (
                (0, 0, 1, 0.3925),
                (1, 0, 0, 0),
                (0, 1, 0, 0),
                (0, 0, 0, 1),
            )
        ),
    ),
)
for name, matrix in side_logos:
    bpy.ops.mesh.primitive_plane_add(size=0.52)
    side_logo = bpy.context.object
    side_logo.name = name
    side_logo.matrix_world = matrix
    side_logo.data.materials.append(logo_mat)

for x in (-0.20, 0.20):
    rounded_box(f"Shoulder Strap {x:+.3f}", (0.075, 0.025, 0.60), (x, 0.40, 0), 0.010, black, 3, True)
    rounded_box(f"Strap Buckle {x:+.3f}", (0.090, 0.030, 0.050), (x, 0.415, 0.27), 0.008, dark, 3, True)

bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, -0.44))
plane = bpy.context.object
plane.name = "Floor"
plane.data.materials.append(floor_mat)

bpy.ops.object.light_add(type="AREA", location=(1.6, -1.9, 2.2))
key = bpy.context.object
key.name = "Key Light"
key.data.energy = 240
key.data.shape = "DISK"
key.data.size = 1.5
key.rotation_euler = (math.radians(35), 0, math.radians(35))

bpy.ops.object.light_add(type="AREA", location=(-1.8, -0.8, 1.1))
fill = bpy.context.object
fill.name = "Fill Light"
fill.data.energy = 90
fill.data.size = 1.8
fill.rotation_euler = (math.radians(65), 0, math.radians(-60))

bpy.ops.object.light_add(type="AREA", location=(0.2, 1.8, 1.7))
rim = bpy.context.object
rim.name = "Rim Light"
rim.data.energy = 140
rim.data.size = 1.2
rim.rotation_euler = (math.radians(55), 0, math.radians(180))

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1200
scene.render.resolution_y = 1200
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"
scene.view_settings.exposure = -1.0
if scene.world is None:
    scene.world = bpy.data.worlds.new("World")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.035, 0.035, 0.04, 1)
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.45

bpy.ops.object.camera_add(location=(1.05, -1.55, 1.05))
cam = bpy.context.object
cam.name = "Preview Camera"
cam.data.lens = 62
scene.camera = cam
target = Vector((0, 0, 0.0))
cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()

bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))

scene.render.filepath = str(ROOT / "preview.png")
bpy.ops.render.render(write_still=True)

cam.location = (0, -2.2, 0.55)
cam.rotation_euler = (Vector((0, 0, 0.0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
scene.render.filepath = str(ROOT / "front.png")
bpy.ops.render.render(write_still=True)

cam.location = (0, 2.2, 0.60)
cam.rotation_euler = (Vector((0, 0, 0.0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
scene.render.filepath = str(ROOT / "back.png")
bpy.ops.render.render(write_still=True)

bpy.ops.object.select_all(action="DESELECT")
for obj in bpy.context.scene.objects:
    if obj.type == "MESH" and obj.name != "Floor":
        obj.select_set(True)
bpy.ops.export_scene.gltf(
    filepath=str(GLB),
    export_format="GLB",
    use_selection=True,
    export_apply=True,
)
print("BLEND", BLEND)
print("GLB", GLB)

