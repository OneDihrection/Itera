# refine_finger_demonstrations.py
# Created by Amelia Putri Aftiana on 29/10/2026.
# Deterministic skin weights and fingertip contact constraints for original demonstration assets.
import bpy
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
scene = bpy.data.scenes['IteraFingerDemonstrations']
rig = bpy.data.objects['Hand rig']
hand = bpy.data.objects['Original anatomical hand']
scene.frame_set(1)
# Constrain skinning to its own finger to prevent neighbouring fingers dragging each other.
for group in list(hand.vertex_groups):
    hand.vertex_groups.remove(group)
groups = {bone.name: hand.vertex_groups.new(name=bone.name) for bone in rig.data.bones}
names = ['index', 'middle', 'ring', 'little']
for vertex in hand.data.vertices:
    p = hand.matrix_world @ vertex.co
    if p.x > 0.044:
        name = 'thumb'
        joints = [rig.data.bones['thumb'+str(i)].head_local for i in range(3)]
        axis = (rig.data.bones['thumb2'].tail_local - joints[0]).normalized()
        value = (p - joints[0]).dot(axis)
        positions = [(j - joints[0]).dot(axis) for j in joints]
        base = -0.005
    else:
        name = min(names, key=lambda n: abs(p.x - rig.data.bones[n+'0'].head_local.x))
        joints = [rig.data.bones[name+str(i)].head_local for i in range(3)]
        value = p.z
        positions = [j.z for j in joints]
        base = positions[0] - 0.010
    if value < base:
        groups['palm'].add([vertex.index], 1, 'REPLACE')
        continue
    span = 0.010
    if value < positions[0] + 0.004:
        w = max(0, min(1, (value - base) / (positions[0] + 0.004 - base)))
        groups['palm'].add([vertex.index], 1 - w, 'REPLACE')
        groups[name+'0'].add([vertex.index], w, 'REPLACE')
        continue
    assigned = False
    for joint in [1, 2]:
        if value < positions[joint] + span/2:
            w = max(0, min(1, (value - positions[joint] + span/2) / span))
            groups[name+str(joint-1)].add([vertex.index], 1-w, 'REPLACE')
            groups[name+str(joint)].add([vertex.index], w, 'REPLACE')
            assigned = True
            break
    if not assigned:
        groups[name+'2'].add([vertex.index], 1, 'REPLACE')

constraints = []
for index, (name, goal) in enumerate(zip(names, [
    (0.030, -0.027, 0.117), (0.012, -0.030, 0.110),
    (-0.006, -0.028, 0.104), (-0.018, -0.025, 0.098),
])):
    target = bpy.data.objects.new('Contact ' + name, None)
    scene.collection.objects.link(target)
    target.location = goal
    for bone_name in [name+'2', 'thumb2']:
        ik = rig.pose.bones[bone_name].constraints.new('IK')
        ik.name = 'Opposition ' + name
        ik.target = target
        ik.chain_count = 3
        ik.iterations = 100
        ik.use_tail = True
        constraints.append((index, ik))
# Bake constraint influence into the existing four opposition subclips.
for frame in range(1, 529):
    scene.frame_set(frame)
    opposition = 97 <= frame <= 288
    finger = (frame - 97) // 48 if opposition else -1
    offset = (frame - 97) % 48 if opposition else 0
    if offset <= 17:
        amount = offset / 17
    elif offset <= 23:
        amount = 1
    elif offset <= 41:
        amount = (41-offset) / 18
    else:
        amount = 0
    amount = max(0, min(1, amount))
    for index, ik in constraints:
        ik.influence = amount if index == finger else 0
        ik.keyframe_insert('influence', frame=frame)

scene.render.image_settings.media_type = 'VIDEO'
scene.render.image_settings.file_format = 'FFMPEG'
scene.render.ffmpeg.format = 'QUICKTIME'
scene.render.ffmpeg.codec = 'H264'
scene.render.ffmpeg.constant_rate_factor = 'MEDIUM'
scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / 'ArtSource/FingerDemonstrations.blend'))
print('Refined weights and thumb-to-fingertip contact.')
