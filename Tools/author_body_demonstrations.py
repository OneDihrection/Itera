# author_body_demonstrations.py — Created by dimaswisodewo on 2026-11-11.

"""Author connected-joint body-exercise motion on the yellow Rigify rig.

Run inside Blender, for example through the Blender MCP:

    exec(open("<repo>/Tools/author_body_demonstrations.py").read())
    author("arm_raise_demonstration")

Each clip is a short list of key poses written as a few readable parameters
(arm elevation, elevation plane, humeral roll, elbow angle, trunk lean, yaw and so on).
`solve` turns every sampled frame into absolute bone orientations, and couples the joints
that move with the arm: shoulder blade lift and protraction, chest extension for overhead
reach, a smaller follow-through in the neck and head, and an ankle-pinned leg solve when the
pelvis drops. Rigify's drivers stay untouched; only FK controls are keyed.
"""

import math

import bpy
from mathutils import Matrix, Quaternion, Vector


RIG = "Male_Basemesh_Rig_01"
FPS = 24

ARM_SIDES = ("R", "L")
BODY_CONTROLS = ("torso", "chest", "neck", "head")
SIDE_CONTROLS = ("shoulder", "upper_arm_fk", "forearm_fk", "hand_fk", "thigh_fk", "shin_fk", "foot_fk")
CONTROLS = BODY_CONTROLS + tuple(f"{name}.{side}" for name in SIDE_CONTROLS for side in ARM_SIDES)

# Order matters: a bone is placed only after the bones it hangs from have been evaluated.
LEVELS = (
    ("torso",),
    ("chest", "thigh_fk.R", "thigh_fk.L"),
    ("shoulder.R", "shoulder.L", "neck", "shin_fk.R", "shin_fk.L"),
    ("upper_arm_fk.R", "upper_arm_fk.L", "head", "foot_fk.R", "foot_fk.L"),
    ("forearm_fk.R", "forearm_fk.L"),
    ("hand_fk.R", "hand_fk.L"),
)

NEUTRAL = {"lean": 0.0, "bend": 0.0, "yaw": 0.0, "drop": 0.0, "back": 0.0}
for _side in ARM_SIDES:
    NEUTRAL.update({
        f"{_side}_e": 9.0,         # arm elevation from hanging straight down (0) to overhead (180)
        f"{_side}_p": 0.0,         # elevation plane: 0 out to the side, 90 forward, 130 across the body
        f"{_side}_roll": 0.0,      # humeral rotation about the arm: positive turns outward
        f"{_side}_elbow": 10.0,    # angle between upper arm and forearm (0 = straight)
        f"{_side}_froll": 0.0,     # forearm rotation: positive turns the palm up
    })

ROLL_SIGN = 1.0


def _rig():
    return bpy.data.objects[RIG]


def rest_data(rig):
    data = {}
    for name in CONTROLS:
        bone = rig.pose.bones[name].bone
        head, tail = bone.head_local.copy(), bone.tail_local.copy()
        data[name] = {
            "rot": bone.matrix_local.to_quaternion(),
            "head": head,
            "tail": tail,
            "dir": (tail - head).normalized(),
            "length": (tail - head).length,
        }
    return data


def rotation(axis, degrees):
    return Quaternion(axis, math.radians(degrees))


def swing(a, b):
    return a.normalized().rotation_difference(b.normalized())


def arm_solution(rest, side, e, p, roll, elbow, froll):
    """Returns absolute (armature-space) rotations for upper arm, forearm and hand."""
    mirror = 1 if side == "R" else -1
    u0 = rest[f"upper_arm_fk.{side}"]["dir"]
    f0 = rest[f"forearm_fk.{side}"]["dir"]

    er, pr = math.radians(e), math.radians(p)
    u = Vector((
        mirror * -math.sin(er) * math.cos(pr),
        -math.sin(er) * math.sin(pr),
        -math.cos(er),
    ))
    upper = Quaternion(u, math.radians(roll) * ROLL_SIGN * mirror) @ swing(u0, u)

    hinge = u0.cross(f0).normalized()
    rest_elbow = math.degrees(u0.angle(f0))
    bent = upper @ rotation(hinge, elbow - rest_elbow)

    f_dir = bent @ f0
    fore = Quaternion(f_dir, math.radians(froll) * mirror) @ bent
    return upper, fore, fore


def calibrate_roll_sign(rest):
    """Makes positive humeral roll turn the forearm outward (away from the body)."""
    global ROLL_SIGN
    ROLL_SIGN = 1.0
    _, fore_zero, _ = arm_solution(rest, "R", 12, 0, 0, 90, 0)
    _, fore_roll, _ = arm_solution(rest, "R", 12, 0, 20, 90, 0)
    outward = (fore_roll @ rest["forearm_fk.R"]["dir"]).x < (fore_zero @ rest["forearm_fk.R"]["dir"]).x
    ROLL_SIGN = 1.0 if outward else -1.0


def smooth(t):
    return t * t * (3 - 2 * t)


def merged(pose):
    return {**NEUTRAL, **pose}


def sample(keys, frame):
    if frame <= keys[0][0]:
        return merged(keys[0][1])
    for (f0, a), (f1, b) in zip(keys, keys[1:]):
        if frame <= f1:
            t = smooth((frame - f0) / (f1 - f0)) if f1 > f0 else 1.0
            pa, pb = merged(a), merged(b)
            return {k: pa[k] + (pb[k] - pa[k]) * t for k in pa}
    return merged(keys[-1][1])


def trunk_rotation(params):
    elevated = max(params["R_e"], params["L_e"])
    extension = 0.12 * max(0.0, elevated - 100.0)
    return (
        rotation((0, 0, 1), params["yaw"])
        @ rotation((0, 1, 0), params["bend"])
        @ rotation((1, 0, 0), params["lean"] - extension)
    )


def girdle_rotation(side, e, p):
    mirror = 1 if side == "R" else -1
    lift = 0.24 * min(max(e - 25.0, 0.0), 140.0)
    reach = 0.15 * e * max(math.sin(math.radians(p)), 0.0)
    return rotation((0, 0, 1), reach * mirror) @ rotation((0, 1, 0), lift * mirror)


def solve_leg(rest, side, hip, ankle):
    thigh = rest[f"thigh_fk.{side}"]
    shin = rest[f"shin_fk.{side}"]
    l1, l2 = thigh["length"], shin["length"]
    reach = ankle - hip
    d = min(reach.length, (l1 + l2) * 0.999)
    forward = reach.normalized()
    a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    away = Vector((0, -1, 0))
    pole = (away - forward * away.dot(forward)).normalized()
    knee = hip + forward * a + pole * h
    return swing(thigh["dir"], knee - hip), swing(shin["dir"], ankle - knee)


def place(rig, rest, name, orientation, offset=None):
    pose_bone = rig.pose.bones[name]
    basis = (orientation @ rest[name]["rot"]).to_matrix().to_4x4()
    head = pose_bone.head.copy()
    if offset is not None:
        # The pelvis offset is absolute, so start from the rest head instead of the last solved frame.
        head = rest[name]["head"] + offset
    pose_bone.matrix = Matrix.Translation(head) @ basis


def pose_frame(rig, rest, params, lagged, legs):
    chest = trunk_rotation(params)
    chest_lagged = trunk_rotation(lagged)
    identity = Quaternion()
    targets = {
        "torso": identity,
        "chest": chest,
        "neck": identity.slerp(chest_lagged, 0.45),
        "head": identity.slerp(chest_lagged, 0.12),
    }
    for side in ARM_SIDES:
        upper, fore, hand = arm_solution(
            rest, side,
            params[f"{side}_e"], params[f"{side}_p"], params[f"{side}_roll"],
            params[f"{side}_elbow"], params[f"{side}_froll"],
        )
        targets[f"shoulder.{side}"] = girdle_rotation(side, params[f"{side}_e"], params[f"{side}_p"])
        targets[f"upper_arm_fk.{side}"] = upper
        targets[f"forearm_fk.{side}"] = fore
        targets[f"hand_fk.{side}"] = hand
        targets[f"foot_fk.{side}"] = identity

    pelvis = Vector((0, params["back"], -params["drop"]))
    for level in LEVELS:
        for name in level:
            if name.startswith(("thigh_fk", "shin_fk", "foot_fk")) and not legs:
                continue
            if name.startswith("thigh_fk"):
                side = name[-1]
                hip = rig.pose.bones[name].head.copy()
                ankle = rest[f"shin_fk.{side}"]["tail"].copy()
                targets[name], targets[f"shin_fk.{side}"] = solve_leg(rest, side, hip, ankle)
            place(rig, rest, name, targets[name], pelvis if name == "torso" else None)
        bpy.context.view_layer.update()


def record(rig):
    values = {}
    for name in CONTROLS:
        pose_bone = rig.pose.bones[name]
        values[name] = (
            pose_bone.rotation_mode,
            tuple(pose_bone.rotation_quaternion),
            tuple(pose_bone.rotation_euler),
            tuple(pose_bone.location),
        )
    return values


def reset(rig):
    for name in CONTROLS:
        pose_bone = rig.pose.bones[name]
        pose_bone.location = (0, 0, 0)
        pose_bone.rotation_quaternion = (1, 0, 0, 0)
        pose_bone.rotation_euler = (0, 0, 0)


def author(clip_name, clips=None):
    clips = clips or CLIPS
    config = clips[clip_name]
    keys = config["poses"]
    legs = config.get("legs", False)
    start, end = keys[0][0], keys[-1][0]

    rig = _rig()
    for side in ARM_SIDES:
        rig.pose.bones[f"upper_arm_parent.{side}"]["IK_FK"] = 1.0
        rig.pose.bones[f"thigh_parent.{side}"]["IK_FK"] = 1.0
    if rig.animation_data:
        rig.animation_data.action = None
    reset(rig)
    bpy.context.view_layer.update()

    rest = rest_data(rig)
    calibrate_roll_sign(rest)

    frames = {}
    for frame in range(start, end + 1):
        params = sample(keys, frame)
        lagged = sample(keys, max(start, frame - 4))
        pose_frame(rig, rest, params, lagged, legs)
        frames[frame] = record(rig)

    reset(rig)
    bpy.context.view_layer.update()
    scene = bpy.context.scene
    for frame, values in frames.items():
        for name, (mode, quaternion, euler, location) in values.items():
            pose_bone = rig.pose.bones[name]
            if mode == "QUATERNION":
                pose_bone.rotation_quaternion = quaternion
                pose_bone.keyframe_insert("rotation_quaternion", frame=frame, group=name)
            else:
                pose_bone.rotation_euler = euler
                pose_bone.keyframe_insert("rotation_euler", frame=frame, group=name)
            if name == "torso":
                pose_bone.location = location
                pose_bone.keyframe_insert("location", frame=frame, group=name)
    for side in ARM_SIDES:
        for name in (f"upper_arm_parent.{side}", f"thigh_parent.{side}"):
            rig.pose.bones[name].keyframe_insert('["IK_FK"]', frame=start)

    action = rig.animation_data.action
    stale = bpy.data.actions.get(clip_name)
    if stale is not None and stale is not action:
        bpy.data.actions.remove(stale)
    action.name = clip_name
    action.use_fake_user = True
    scene.frame_start, scene.frame_end = start, end
    scene.frame_set(start)
    return action


def both(**kw):
    """Applies one set of arm values to both arms, then returns the combined pose."""
    pose = {}
    for side in ARM_SIDES:
        for key, value in kw.items():
            pose[f"{side}_{key}"] = value
    return pose


def one(side, **kw):
    return {f"{side}_{key}": value for key, value in kw.items()}


def cycle(*poses, rise=36, hold=12, lead=12, tail=12):
    """neutral hold, then each pose reached in `rise` frames with a `hold` at the peak, then back."""
    keys = [(1, {}), (1 + lead, {})]
    frame = 1 + lead
    for pose in poses:
        frame += rise
        keys.append((frame, pose))
        frame += hold
        keys.append((frame, pose))
        frame += rise
        keys.append((frame, {}))
    keys.append((frame + tail, {}))
    return keys


CLIPS = {}


def cross_reach(side, yaw):
    """Arm swung straight across the body toward the far side, without touching it."""
    return {**one(side, e=90, p=145, elbow=5), "yaw": yaw}


def shoulder_touch(side, yaw):
    """Hand resting on the opposite shoulder, elbow lifted in front of the chest.

    Solved numerically so the palm lands on the shoulder without the forearm passing
    through the chest; the humerus turns inward to bring the elbow forward.
    """
    return {**one(side, e=93, p=111, elbow=112, roll=-40, froll=-14), "yaw": yaw}


def rotation_pose(side, roll):
    return one(side, e=14, p=0, elbow=90, roll=roll)


def rotation_cycle(side, roll_peak):
    ready = rotation_pose(side, 0)
    peak = rotation_pose(side, roll_peak)
    return [
        (1, {}), (13, {}),
        (37, ready), (49, ready),
        (73, peak), (85, peak),
        (109, ready), (117, ready),
        (141, {}), (153, {}),
    ]


def forward_raise(side):
    return one(side, e=165, p=90, elbow=5)


def seated_pose(lean):
    pose = {"drop": 0.40, "back": 0.27, "lean": lean}
    pose.update(both(e=52, p=90, elbow=22))
    return pose


# Arm clips show the right arm only; the app reflects the video for the left arm.
CLIPS.update({
    "arm_raise_demonstration": {
        "poses": cycle(one("R", e=90, p=0, elbow=5, roll=8)),
    },
    "elbow_bend_demonstration": {
        "poses": cycle(one("R", e=9, p=0, elbow=140, froll=25)),
    },
    "directional_reach_demonstration": {
        "poses": [
            (1, {}), (13, {}),
            (37, one("R", e=90, p=0, elbow=5)), (43, one("R", e=90, p=0, elbow=5)), (67, {}),
            (97, cross_reach("R", 22)), (103, cross_reach("R", 22)), (133, {}),
            (163, {**one("R", e=165, p=15, elbow=6), "bend": 6}),
            (169, {**one("R", e=165, p=15, elbow=6), "bend": 6}),
            (199, {}), (211, {}),
        ],
    },
    "cross_midline_right_demonstration": {
        "poses": cycle(shoulder_touch("R", 18), rise=42),
    },
    "shoulder_external_rotation_right_demonstration": {"poses": rotation_cycle("R", 55)},
    "shoulder_internal_rotation_right_demonstration": {"poses": rotation_cycle("R", -45)},
    "shoulder_flexion_right_demonstration": {
        "camera": "side",
        "poses": cycle(forward_raise("R"), rise=48),
    },
    "sit_to_stand_demonstration": {
        "camera": "side",
        "legs": True,
        "poses": [
            (1, {}), (13, {}),
            (37, seated_pose(24)), (49, seated_pose(24)), (73, seated_pose(24)),
            (91, {"lean": 22, **both(e=40, p=90, elbow=20), "drop": 0.2, "back": 0.2}),
            (115, {}), (127, {}),
        ],
    },
})


CAMERAS = {
    "front": {"location": (0.75, -6.0, 1.55), "rotation": (1.4637110233306885, 0.0, 0.1243550181388855)},
    "side": {"location": (5.5, -3.5, 1.5), "target": (0.0, 0.0, 0.9)},
}


def frame_camera(kind):
    """Square orthographic framing shared by every clip, with room for overhead reach."""
    camera = bpy.data.objects["Exercise camera"]
    preset = CAMERAS[kind]
    camera.location = preset["location"]
    if "rotation" in preset:
        camera.rotation_euler = preset["rotation"]
    else:
        direction = Vector(preset["target"]) - Vector(preset["location"])
        camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.5
    camera.data.shift_x = 0.0
    camera.data.shift_y = 0.07


def render_frames(clip_name, directory):
    """Authors the clip, then renders transparent 768 x 768 PNG frames at 24 FPS."""
    config = CLIPS[clip_name]
    action = author(clip_name)
    frame_camera(config.get("camera", "front"))

    scene = bpy.context.scene
    render = scene.render
    render.resolution_x = 768
    render.resolution_y = 768
    render.resolution_percentage = 100
    render.fps = FPS
    render.fps_base = 1
    render.film_transparent = True
    render.use_freestyle = False
    render.image_settings.file_format = "PNG"
    render.image_settings.color_mode = "RGBA"
    render.filepath = f"{directory}/frame_"
    bpy.ops.render.render(animation=True)
    return action.frame_range[0], action.frame_range[1]
