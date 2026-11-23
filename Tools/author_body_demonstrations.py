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
pelvis drops. Rigify's drivers stay untouched; only FK controls are keyed. `author_grip` then keys
a natural finger grip that follows the arm's movement, and the clip is rendered from the scene's
`Cam_<clip>` camera.
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


# MARK: - Hand grip

# Reaching clips open the hand as the arm elevates; the others close it into a loose hold at
# the peak of the movement. Sit to stand keeps the relaxed hand. Angles are degrees of finger
# curl about each bone's local X axis (positive curls toward the palm), as knuckle, middle and
# end joint.
GRIP_REACH_CLIPS = {
    "arm_raise_demonstration",
    "shoulder_flexion_right_demonstration",
    "directional_reach_demonstration",
}
GRIP_HOLD_CLIPS = {
    "cross_midline_right_demonstration",
    "elbow_bend_demonstration",
    "shoulder_external_rotation_right_demonstration",
    "shoulder_internal_rotation_right_demonstration",
}
GRIP_RELAXED = {
    "f_index": (14, 24, 14),
    "f_middle": (18, 28, 17),
    "f_ring": (22, 32, 19),
    "f_pinky": (27, 36, 22),
}

# Frames each finger trails the index finger, so the fingers curl in a small cascade.
GRIP_LAG = {"f_index": 0, "f_middle": 1, "f_ring": 2, "f_pinky": 3}
GRIP_THUMB_RELAXED = (3, 5, 4)
GRIP_OPEN_FRACTION = 0.65
GRIP_CLOSE_GAIN = 1.3
GRIP_THUMB_OPEN_FRACTION = 0.5
GRIP_THUMB_CLOSE_GAIN = 1.6
GRIP_KEY_STEP = 3
GRIP_SMOOTHING = 7


def grip_effort(rig, start, end):
    """How far the right hand has travelled from its first position, 0 to 1, smoothed per frame."""
    scene = bpy.context.scene
    positions = []

    for frame in range(start, end + 1):
        scene.frame_set(frame)
        positions.append(rig.matrix_world @ rig.pose.bones["DEF-hand.R"].head)

    distances = [(position - positions[0]).length for position in positions]
    largest = max(max(distances), 1e-6)
    normalized = [distance / largest for distance in distances]
    half = GRIP_SMOOTHING // 2
    padded = [normalized[0]] * half + normalized + [normalized[-1]] * half

    return [
        sum(padded[index:index + GRIP_SMOOTHING]) / GRIP_SMOOTHING
        for index in range(len(normalized))
    ]


def key_curl(rig, bone, frame, degrees):
    pose_bone = rig.pose.bones[bone]
    pose_bone.rotation_mode = "QUATERNION"
    pose_bone.rotation_quaternion = Quaternion((1, 0, 0), math.radians(degrees))
    pose_bone.keyframe_insert("rotation_quaternion", frame=frame, group=bone)


def author_grip(rig, clip_name, start, end):
    """Keys a natural grip on the finger controls of the clip's action.

    The right hand follows the arm's movement: it opens as a reaching arm elevates and closes
    into a loose hold at the peak of the other clips, each finger a frame behind the last. The
    left hand stays relaxed. Must run after the arm motion is keyed, since the effort comes from it.
    """
    effort = grip_effort(rig, start, end)

    def at(frame):
        position = min(max(frame - start, 0), len(effort) - 1)
        return effort[position]

    reaching = clip_name in GRIP_REACH_CLIPS
    holding = clip_name in GRIP_HOLD_CLIPS
    frames = sorted(set(range(start, end + 1, GRIP_KEY_STEP)) | {end})

    def curl(base, amount, open_fraction, close_gain):
        if reaching:
            return base * (1 - open_fraction * amount)

        if holding:
            return base * (1 + close_gain * amount)

        return base

    for finger, joints in GRIP_RELAXED.items():
        for index, base in enumerate(joints):
            right = f"{finger}.0{index + 1}.R"

            for frame in frames:
                lagged = frame - GRIP_LAG[finger] - index
                key_curl(rig, right, frame, curl(base, at(lagged), GRIP_OPEN_FRACTION, GRIP_CLOSE_GAIN))

            for frame in (start, end):
                key_curl(rig, f"{finger}.0{index + 1}.L", frame, base)

    for index, base in enumerate(GRIP_THUMB_RELAXED):
        for frame in frames:
            key_curl(
                rig,
                f"thumb.0{index + 1}.R",
                frame,
                curl(base, at(frame - index), GRIP_THUMB_OPEN_FRACTION, GRIP_THUMB_CLOSE_GAIN),
            )

        for frame in (start, end):
            key_curl(rig, f"thumb.0{index + 1}.L", frame, base)


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
    author_grip(rig, clip_name, start, end)
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


# Seated exercises are framed from just below the hips to above the highest reach, so a
# standing figure no longer suggests standing practice. Sit-to-stand keeps the full body.
TORSO_CLIPS = {
    "arm_raise_demonstration",
    "elbow_bend_demonstration",
    "directional_reach_demonstration",
    "cross_midline_right_demonstration",
    "shoulder_external_rotation_right_demonstration",
    "shoulder_internal_rotation_right_demonstration",
    "shoulder_flexion_right_demonstration",
}

# Camera-space units. The pelvis sits near y = 0.06 and the head top near 0.80; overhead reach
# (directional reach, shoulder flexion) rises to about 1.22. Each clip is framed to its own
# motion: the bottom edge stays at the waist, the top clears the highest point with headroom,
# and the sides keep a margin, so the moving arm never touches the edge.
TORSO_BOTTOM = 0.08
TORSO_HEADROOM = 0.10
TORSO_SIDE_MARGIN = 0.10


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


def motion_extent(camera, start, end, step=3, stride=7):
    """The figure's left, right and top edges in camera space across the clip's motion."""
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH" and obj.visible_get()]
    to_camera = camera.matrix_world.inverted()
    scene = bpy.context.scene
    low, high, top = math.inf, -math.inf, -math.inf

    for frame in range(int(start), int(end) + 1, step):
        scene.frame_set(frame)
        depsgraph = bpy.context.evaluated_depsgraph_get()

        for obj in meshes:
            evaluated = obj.evaluated_get(depsgraph)
            mesh = evaluated.to_mesh()
            matrix = to_camera @ evaluated.matrix_world

            for index in range(0, len(mesh.vertices), stride):
                point = matrix @ mesh.vertices[index].co
                low = min(low, point.x)
                high = max(high, point.x)
                top = max(top, point.y)

            evaluated.to_mesh_clear()

    return low, high, top


def frame_torso(start, end):
    """Zooms the current camera from the waist to just above the clip's highest point.

    The square frame takes whichever is larger, the height or the margined width, and keeps
    the bottom edge at the waist; any spare height goes above the head.
    """
    camera = bpy.data.objects["Exercise camera"]
    low, high, top = motion_extent(camera, start, end)

    height = top + TORSO_HEADROOM - TORSO_BOTTOM
    width = (high - low) + 2 * TORSO_SIDE_MARGIN
    scale = max(height, width)

    camera.data.ortho_scale = scale
    camera.data.shift_x = ((low + high) / 2) / scale
    camera.data.shift_y = (TORSO_BOTTOM + scale / 2) / scale


def clip_camera_name(clip_name):
    """The camera the scene stores for a clip, `Cam_arm_raise` for `arm_raise_demonstration`.

    Those cameras hold each clip's final framing (waist-up for the seated clips, a turned
    full-body view for sit to stand). A scene without one is framed by `frame_camera`.
    """
    return "Cam_" + clip_name.removesuffix("_demonstration")


def render_frames(clip_name, directory):
    """Authors the clip, then renders transparent 768 x 768 PNG frames at 24 FPS."""
    config = CLIPS[clip_name]
    action = author(clip_name)
    clip_camera = bpy.data.objects.get(clip_camera_name(clip_name))

    if clip_camera is not None:
        bpy.context.scene.camera = clip_camera
    else:
        frame_camera(config.get("camera", "front"))

        if clip_name in TORSO_CLIPS:
            frame_torso(*action.frame_range)

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


def export_clip(clip_name, ffmpeg="ffmpeg"):
    """Renders one clip and encodes it into the app's animation folder.

    Encoding follows Documentation/AnimationRenderingStandard.md: the transparent frames are
    composited over the app's #F5F5F5 surface as a silent 24 FPS H.264 yuv420p MP4.
    """
    import pathlib
    import subprocess
    import tempfile

    output = pathlib.Path(__file__).resolve().parents[1] / "Tuntun/Resources/Animations" / f"{clip_name}.mp4"

    with tempfile.TemporaryDirectory(prefix=f"tuntun-{clip_name}-") as directory:
        start, end = render_frames(clip_name, directory)
        subprocess.run(
            [
                ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                "-framerate", str(FPS), "-start_number", str(int(start)),
                "-i", f"{directory}/frame_%04d.png",
                "-f", "lavfi", "-i", f"color=c=0xF5F5F5:s=768x768:r={FPS}",
                "-filter_complex", "[1:v][0:v]overlay=shortest=1:format=auto,format=yuv420p[v]",
                "-map", "[v]", "-frames:v", str(int(end - start) + 1),
                "-c:v", "libx264", "-crf", "18", "-movflags", "+faststart",
                str(output),
            ],
            check=True,
        )

    return output


if __name__ == "__main__" and bpy.app.background:
    # blender -b ArtSource/BodyDemonstrationsReview/BodyDemonstrations_ConnectedMotion.blend \
    #   -P Tools/author_body_demonstrations.py -- --ffmpeg /opt/homebrew/bin/ffmpeg [clip ...]
    import argparse
    import sys

    parser = argparse.ArgumentParser()
    parser.add_argument("clips", nargs="*")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])

    for name in arguments.clips or sorted(TORSO_CLIPS):
        print("Exported", export_clip(name, arguments.ffmpeg))
