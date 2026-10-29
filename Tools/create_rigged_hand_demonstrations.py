# create_rigged_hand_demonstrations.py
# Created by Amelia Putri Aftiana on 29/10/2026.
# Adapts the user-supplied rig without altering its original .blend file.
import bpy
import math
import numpy as np
from pathlib import Path
from mathutils import Vector, Quaternion

ROOT = Path(__file__).resolve().parents[1]
scene = bpy.data.scenes.get('IteraRiggedHand')
if scene is None:
    scene = bpy.data.scenes.new('IteraRiggedHand')
    bpy.context.window.scene = scene
    with bpy.data.libraries.load(str(ROOT / 'ArtSource/Reference/rigged_hand.blend'), link=False) as (source, target):
        target.objects = ['hand', 'Armature.001']
        target.actions = list(source.actions)
    for obj in target.objects:
        if obj is not None:
            scene.collection.objects.link(obj)
bpy.context.window.scene = scene
rig = next(obj for obj in scene.objects if obj.type == 'ARMATURE')
hand = next(obj for obj in scene.objects if obj.type == 'MESH')
names = ['index', 'middle', 'ring', 'pinky']
controls = names + ['thumb']

# Read each authored pose independently, so unkeyed channels cannot leak between actions.
def read_pose(action_name):
    rig.animation_data_clear()
    for bone in rig.pose.bones:
        bone.rotation_mode = 'XYZ'
        bone.location = (0, 0, 0)
        bone.rotation_euler = (0, 0, 0)
        bone.scale = (1, 1, 1)
    action = bpy.data.actions[action_name]
    rig.animation_data_create()
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]
    frame = int(action.frame_range.x)
    scene.frame_set(frame + 1)
    scene.frame_set(frame)
    bpy.context.view_layer.update()
    return {bone.name: (list(bone.location), list(bone.rotation_euler), list(bone.scale)) for bone in rig.pose.bones}

poses = {name: read_pose('Armature.' + name) for name in ['open', 'fist', 'touch', 'pinch']}
rig.animation_data_clear()

def clone(pose):
    return {name: tuple(list(values) for values in channels) for name, channels in pose.items()}

def blend(a, b, amount):
    return {name: tuple([x + (y-x)*amount for x,y in zip(ca,cb)] for ca,cb in zip(a[name],b[name])) for name in a}

def apply(pose):
    for name, (location, rotation, scale) in pose.items():
        bone = rig.pose.bones[name]
        bone.location = location
        bone.rotation_euler = rotation
        bone.scale = scale
    bpy.context.view_layer.update()

open_pose = poses['open']
fist = poses['fist']
hook = clone(open_pose)
for name in names:
    # The authored controller scale curls PIP/DIP; leaving its rotation open preserves MCP.
    hook[name] = (hook[name][0], hook[name][1], list(fist[name][2]))

together = clone(open_pose)
for name in names:
    bone = rig.data.bones[name]
    direction = bone.tail_local - bone.head_local
    angle = -math.atan2(direction.x, direction.z)
    rest = bone.matrix_local.to_quaternion()
    local = rest.inverted() @ Quaternion(Vector((0, 1, 0)), angle) @ rest
    together[name] = (together[name][0], list(local.to_euler('XYZ')), together[name][2])
together['thumb'] = blend(open_pose, fist, 0.25)['thumb']

# Fit thumb/finger pads together while regularizing toward comfortable authored poses.
# Only controller channels are changed; original weights and rig constraints remain intact.
def fit_opposition(index):
    pose = clone(open_pose)
    name = names[index]
    pose[name] = blend(open_pose, fist, 0.48)[name]
    pose['thumb'] = poses['touch']['thumb']
    pose['thumb.000'] = poses['touch']['thumb.000']
    apply(pose)
    initial = np.array(list(pose[name][1]) + [pose[name][2][0]] + list(pose['thumb'][1]) + [pose['thumb'][2][0]] + list(pose['thumb.000'][1]), dtype=float)
    target = np.array([(0.043,0.032,0.112),(0.025,0.034,0.104),(0.012,0.030,0.095),(0.001,0.025,0.087)][index])
    def update(values):
        rig.pose.bones[name].rotation_euler = values[:3]
        rig.pose.bones[name].scale = (values[3],)*3
        rig.pose.bones['thumb'].rotation_euler = values[4:7]
        rig.pose.bones['thumb'].scale = (values[7],)*3
        rig.pose.bones['thumb.000'].rotation_euler = values[8:11]
        bpy.context.view_layer.update()
    def residual(values):
        update(values)
        finger = np.array(rig.matrix_world @ rig.pose.bones[name+'.003'].tail)
        thumb = np.array(rig.matrix_world @ rig.pose.bones['thumb.002'].tail)
        finger_goal = target + np.array([-0.002,0,0])
        thumb_goal = target + np.array([0.002,0,0])
        return np.concatenate(((finger-finger_goal)/0.1,(thumb-thumb_goal)/0.1,0.012*(values-initial)))
    values = initial.copy()
    damping = 0.015
    for _ in range(45):
        current = residual(values)
        jacobian = np.column_stack([(residual(values + np.eye(len(values))[i]*0.002)-current)/0.002 for i in range(len(values))])
        delta = np.linalg.solve(jacobian.T@jacobian + damping*np.eye(len(values)), -jacobian.T@current)
        candidate = values + np.clip(delta,-0.18,0.18)
        candidate[:3] = np.clip(candidate[:3],-2,2)
        candidate[4:7] = np.clip(candidate[4:7],-2,2)
        candidate[8:11] = np.clip(candidate[8:11],-1.6,1.6)
        candidate[3] = np.clip(candidate[3],0.34,1.05)
        candidate[7] = np.clip(candidate[7],0.34,1.05)
        if np.linalg.norm(residual(candidate)) < np.linalg.norm(current):
            values = candidate
            damping = max(0.0002,damping*0.8)
        else:
            damping *= 2
    update(values)
    for control in [name,'thumb','thumb.000']:
        bone = rig.pose.bones[control]
        pose[control] = (list(bone.location),list(bone.rotation_euler),list(bone.scale))
    finger_tip = rig.matrix_world @ rig.pose.bones[name+'.003'].tail
    thumb_tip = rig.matrix_world @ rig.pose.bones['thumb.002'].tail
    print('PAD FIT',name,round((finger_tip-thumb_tip).length,4),flush=True)
    return pose

opposition = [fit_opposition(i) for i in range(4)]
relaxed = blend(open_pose,fist,0.35)
extensions = []
for name in names:
    pose = clone(relaxed)
    pose[name] = open_pose[name]
    extensions.append(pose)

# Author one contiguous action; runtime preserves the established 4-second subclip contract.
rig.animation_data_clear()
rig.animation_data_create()
rig.animation_data.action = bpy.data.actions.new('Itera rigged hand guidance')
frame = 1
starts = {}
for kind, pairs in [
    ('fullFist',[(open_pose,fist)]),
    ('hookFist',[(open_pose,hook)]),
    ('opposition',[(open_pose,pose) for pose in opposition]),
    ('spreading',[(together,open_pose)]),
    ('extensionSequence',[(relaxed,pose) for pose in extensions]),
]:
    starts[kind] = frame
    for baseline,target in pairs:
        for offset,amount in [(0,0),(36,1),(47,1),(84,0),(95,0)]:
            scene.frame_set(frame+offset)
            apply(blend(baseline,target,amount))
            for bone in rig.pose.bones:
                bone.keyframe_insert('location')
                bone.keyframe_insert('rotation_euler')
                bone.keyframe_insert('scale')
        frame += 96

# Soft studio lighting, palm toward the viewer; no tabletop or hidden support.
for obj in list(scene.objects):
    if obj.type in {'LIGHT','CAMERA'}:
        scene.collection.objects.unlink(obj)

def attach(obj):
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    scene.collection.objects.link(obj)
    return obj

bpy.ops.object.camera_add(location=(0.018,0.58,0.115))
camera = attach(bpy.context.object)
camera.name = 'Rigged hand front camera'
camera.rotation_euler = (Vector((0.018,0,0.080))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 0.34
scene.camera = camera
for name,position,power,size in [
    ('Soft key',(-0.20,0.28,0.32),6,0.35),
    ('Soft fill',(0.24,0.18,0.13),3,0.28),
    ('Rim',(-0.06,-0.15,0.25),4,0.28),
]:
    bpy.ops.object.light_add(type='AREA',location=position)
    light = attach(bpy.context.object)
    light.name = 'Rigged '+name
    light.data.energy = power * 0.55
    light.data.shape = 'DISK'
    light.data.size = size
    light.rotation_euler = (Vector((0.02,0,0.07))-light.location).to_track_quat('-Z','Y').to_euler()
scene.world = bpy.data.worlds.new('Rigged hand soft studio')
scene.world.use_nodes = True
background = next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND')
background.inputs['Color'].default_value = (0.80,0.86,0.85,1)
background.inputs['Strength'].default_value = 0.4
# A fixed sage backdrop shared by all instruction clips, without tinting the hand lighting.
nodes = scene.world.node_tree.nodes
links = scene.world.node_tree.links
camera_background = nodes.new('ShaderNodeBackground')
camera_background.inputs['Color'].default_value = (0.70, 0.92, 0.78, 1)
camera_background.inputs['Strength'].default_value = 1
light_path = nodes.new('ShaderNodeLightPath')
mix = nodes.new('ShaderNodeMixShader')
output = next(node for node in nodes if node.type == 'OUTPUT_WORLD')
links.new(light_path.outputs['Is Camera Ray'], mix.inputs[0])
links.new(background.outputs[0], mix.inputs[1])
links.new(camera_background.outputs[0], mix.inputs[2])
links.new(mix.outputs[0], output.inputs['Surface'])
material = hand.data.materials[0]
if material.use_nodes:
    bsdf = next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    bsdf.inputs['Roughness'].default_value = 0.48
    if 'Subsurface Weight' in bsdf.inputs:
        bsdf.inputs['Subsurface Weight'].default_value = 0.07
for polygon in hand.data.polygons:
    polygon.use_smooth = True
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x = 640
scene.render.resolution_y = 640
scene.render.resolution_percentage = 100
scene.render.fps = 24
scene.render.film_transparent = False
scene.render.image_settings.media_type = 'VIDEO'
scene.render.image_settings.file_format = 'FFMPEG'
scene.render.ffmpeg.format = 'QUICKTIME'
scene.render.ffmpeg.codec = 'H264'
scene.render.ffmpeg.constant_rate_factor = 'MEDIUM'
scene.view_settings.view_transform = 'AgX'
scene.view_settings.exposure = -0.3
scene.frame_start = 1
scene.frame_end = 1056
scene.frame_set(1)
bpy.context.view_layer.update()
scene['source'] = 'User supplied Downloads/rigged_hand.blend; original preserved in ArtSource/Reference.'
scene['clip_starts'] = str(starts)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / 'ArtSource/RiggedFingerDemonstrations.blend'))
print('Saved rigged guidance scene',starts)
