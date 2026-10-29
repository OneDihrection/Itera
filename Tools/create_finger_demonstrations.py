# create_finger_demonstrations.py
# Created by Amelia Putri Aftiana on 29/10/2026.
# Original procedural hand and animations; no third-party mesh is copied.
import bpy
import math
from mathutils import Vector
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
scene = bpy.data.scenes.get('IteraFingerDemonstrations') or bpy.data.scenes.new('IteraFingerDemonstrations')
bpy.context.window.scene = scene
collection = bpy.data.collections.new('Itera Hand')
scene.collection.children.link(collection)

def move_to_collection(obj):
    for existing in list(obj.users_collection):
        existing.objects.unlink(obj)
    collection.objects.link(obj)
    return obj

def material(name, color, roughness):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = roughness
    if 'Subsurface Weight' in bsdf.inputs:
        bsdf.inputs['Subsurface Weight'].default_value = 0.12
    return mat

skin = material('Warm natural skin', (0.59, 0.32, 0.20), 0.47)
nail_material = material('Natural nail', (0.74, 0.47, 0.36), 0.35)
# Fine, low-amplitude surface detail, avoiding exaggerated plastic gloss.
nodes = skin.node_tree.nodes
noise = nodes.new('ShaderNodeTexNoise')
noise.inputs['Scale'].default_value = 650
bump = nodes.new('ShaderNodeBump')
bump.inputs['Strength'].default_value = 0.10
bump.inputs['Distance'].default_value = 0.00012
skin.node_tree.links.new(noise.outputs['Fac'], bump.inputs['Height'])
skin.node_tree.links.new(bump.outputs['Normal'], next(n for n in nodes if n.type == 'BSDF_PRINCIPLED').inputs['Normal'])

parts = []
def ellipsoid(name, center, scale):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=16, location=center)
    obj = move_to_collection(bpy.context.object)
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    parts.append(obj)
    return obj

def segment(name, start, end, radius, depth=0.87):
    middle = (Vector(start) + Vector(end)) / 2
    obj = ellipsoid(name, middle, (radius, radius * depth, (Vector(end)-Vector(start)).length / 2 + radius * 0.75))
    obj.rotation_euler = (Vector(end)-Vector(start)).to_track_quat('Z', 'Y').to_euler()
    return obj

ellipsoid('Palm', (0, 0, 0.079), (0.044, 0.018, 0.049))
ellipsoid('Thumb pad', (0.025, -0.009, 0.060), (0.023, 0.014, 0.030))
ellipsoid('Little finger pad', (-0.027, 0, 0.065), (0.018, 0.016, 0.035))
segment('Wrist and forearm', (0, 0.004, -0.060), (0, 0, 0.044), 0.024, 0.70)

fingers = []
for index, (name, x, z, lengths, radius) in enumerate([
    ('index', 0.027, 0.112, (0.032, 0.022, 0.018), 0.009),
    ('middle', 0.008, 0.120, (0.036, 0.025, 0.019), 0.0095),
    ('ring', -0.013, 0.116, (0.034, 0.023, 0.018), 0.009),
    ('little', -0.032, 0.105, (0.026, 0.019, 0.016), 0.0077),
]):
    joints = [Vector((x, 0, z))]
    for length in lengths:
        joints.append(joints[-1] + Vector((0, 0, length)))
    for i in range(3):
        segment(name + str(i), joints[i], joints[i+1], radius * (1 - i * 0.10))
    fingers.append((name, joints, radius))
thumb_joints = [Vector((0.029, 0, 0.052)), Vector((0.050, -0.001, 0.076)), Vector((0.066, -0.002, 0.098)), Vector((0.073, -0.003, 0.117))]
for i in range(3):
    segment('thumb' + str(i), thumb_joints[i], thumb_joints[i+1], 0.011 * (1 - i * 0.12))
fingers.append(('thumb', thumb_joints, 0.011))

bpy.ops.object.select_all(action='DESELECT')
for obj in parts:
    obj.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
hand = bpy.context.object
hand.name = 'Original anatomical hand'
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
remesh = hand.modifiers.new('Continuous skin surface', 'REMESH')
remesh.mode = 'VOXEL'
remesh.voxel_size = 0.0018
bpy.ops.object.modifier_apply(modifier=remesh.name)
smooth = hand.modifiers.new('Soft skin surface', 'SMOOTH')
smooth.factor = 0.6
smooth.iterations = 4
bpy.ops.object.modifier_apply(modifier=smooth.name)
for polygon in hand.data.polygons:
    polygon.use_smooth = True
hand.data.materials.append(skin)

armature = bpy.data.armatures.new('Hand articulation')
rig = bpy.data.objects.new('Hand rig', armature)
collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
hand.select_set(False)
bpy.ops.object.mode_set(mode='EDIT')
palm = armature.edit_bones.new('palm')
palm.head = (0, 0, 0)
palm.tail = (0, 0, 0.10)
for name, joints, radius in fingers:
    parent = palm
    for i in range(3):
        bone = armature.edit_bones.new(name + str(i))
        bone.head = joints[i]
        bone.tail = joints[i+1]
        bone.parent = parent
        parent = bone
bpy.ops.object.mode_set(mode='OBJECT')
# Automatic skin weights on the continuous mesh, followed by one subdivision pass.
bpy.ops.object.select_all(action='DESELECT')
hand.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
bpy.context.view_layer.objects.active = hand
relax = hand.modifiers.new('Gentle surface relaxation', 'SMOOTH')
relax.factor = 0.7
relax.iterations = 12
bpy.ops.object.modifier_move_up(modifier=relax.name)
sub = hand.modifiers.new('Fine surface', 'SUBSURF')
sub.levels = 1
sub.render_levels = 1
# Nails stay on the dorsal side and follow distal bones.
for name, joints, radius in fingers:
    middle = (joints[2] + joints[3]) / 2
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, location=(middle.x, middle.y + radius * 0.83, middle.z))
    nail = move_to_collection(bpy.context.object)
    nail.name = name + ' nail'
    nail.scale = (radius * 0.65, 0.0012, (joints[3] - joints[2]).length * 0.35)
    nail.rotation_euler = (joints[3] - joints[2]).to_track_quat('Z', 'Y').to_euler()
    nail.data.materials.append(nail_material)
    matrix = nail.matrix_world.copy()
    nail.parent = rig
    nail.parent_type = 'BONE'
    nail.parent_bone = name + '2'
    nail.matrix_world = matrix
    for p in nail.data.polygons:
        p.use_smooth = True

bpy.ops.object.camera_add(location=(0.015, -0.52, 0.105))
camera = move_to_collection(bpy.context.object)
camera.rotation_euler = (Vector((0.008, 0, 0.090)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 0.29
scene.camera = camera
for name, location, power, size in [
    ('Large soft key', (-0.2, -0.25, 0.35), 18, 0.28),
    ('Soft fill', (0.25, -0.10, 0.18), 9, 0.23),
    ('Rim', (0.05, 0.20, 0.28), 15, 0.20),
]:
    bpy.ops.object.light_add(type='AREA', location=location)
    light = move_to_collection(bpy.context.object)
    light.name = name
    light.data.energy = power * 0.12
    light.data.shape = 'DISK'
    light.data.size = size
    light.rotation_euler = (Vector((0, 0, 0.1)) - light.location).to_track_quat('-Z', 'Y').to_euler()
scene.world = bpy.data.worlds.new('Pale sage studio')
scene.world.use_nodes = True
background = next(n for n in scene.world.node_tree.nodes if n.type == 'BACKGROUND')
background.inputs['Color'].default_value = (0.60, 0.73, 0.65, 1)
background.inputs['Strength'].default_value = 0.5
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x = 480
scene.render.resolution_y = 480
scene.render.resolution_percentage = 100
scene.render.fps = 12
scene.render.image_settings.file_format = 'PNG'
scene.render.film_transparent = False
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'
scene.view_settings.exposure = -0.3
scene.render.image_settings.color_mode = 'RGB'

# Local bone axes: X bends toward the palm, Z splays the fingers in the image plane.
def pose(kind, finger, amount):
    for bone in rig.pose.bones:
        bone.rotation_mode = 'XYZ'
        bone.rotation_euler = (0, 0, 0)
    names = ['index', 'middle', 'ring', 'little']
    if kind == 'fullFist':
        for name in names:
            for i, degrees in enumerate([65, 85, 55]):
                rig.pose.bones[name + str(i)].rotation_euler.x = math.radians(degrees) * amount
        rig.pose.bones['thumb0'].rotation_euler.z = math.radians(-30) * amount
        rig.pose.bones['thumb1'].rotation_euler.x = math.radians(30) * amount
    elif kind == 'hookFist':
        for name in names:
            for i, degrees in enumerate([0, 95, 65]):
                rig.pose.bones[name + str(i)].rotation_euler.x = math.radians(degrees) * amount
    elif kind == 'spreading':
        for name, degrees in zip(names, [-17, -4, 10, 25]):
            rig.pose.bones[name + '0'].rotation_euler.z = math.radians(degrees) * amount
        rig.pose.bones['thumb0'].rotation_euler.z = math.radians(-12) * amount
    elif kind == 'extensionSequence':
        for i, name in enumerate(names):
            for segment_i, degrees in enumerate([20, 48, 22]):
                rig.pose.bones[name + str(segment_i)].rotation_euler.x = math.radians(degrees) * (1 - amount if i == finger else 1)
    elif kind == 'opposition':
        # Curl the named finger toward the thumb pad while the thumb moves across the palm.
        name = names[finger]
        for i, degrees in enumerate([35, 60, 35]):
            rig.pose.bones[name + str(i)].rotation_euler.x = math.radians(degrees) * amount
        rig.pose.bones[name + '0'].rotation_euler.z = math.radians(-8 - finger * 5) * amount
        rig.pose.bones['thumb0'].rotation_euler.x = math.radians(40 + finger * 6) * amount
        rig.pose.bones['thumb0'].rotation_euler.z = math.radians(24 + finger * 11) * amount
        rig.pose.bones['thumb1'].rotation_euler.x = math.radians(25) * amount
    for bone in rig.pose.bones:
        bone.keyframe_insert('rotation_euler')

starts = {}
frame = 1
for kind in ['fullFist', 'hookFist', 'opposition', 'spreading', 'extensionSequence']:
    starts[kind] = frame
    count = 4 if kind in ['opposition', 'extensionSequence'] else 1
    for finger in range(count):
        for offset, amount in [(0, 0), (17, 1), (23, 1), (41, 0), (47, 0)]:
            scene.frame_set(frame + offset)
            pose(kind, finger, amount)
        frame += 48
scene.frame_start = 1
scene.frame_end = frame - 1
scene['clip_starts'] = str(starts)
scene.frame_set(1)
ROOT.joinpath('ArtSource').mkdir(exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / 'ArtSource/FingerDemonstrations.blend'))
print('Created hand, rig and five movement animations.', starts, 'frames', frame - 1)

exec(compile((ROOT / 'Tools/refine_finger_demonstrations.py').read_text(), str(ROOT / 'Tools/refine_finger_demonstrations.py'), 'exec'))
