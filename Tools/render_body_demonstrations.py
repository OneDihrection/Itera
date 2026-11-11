# render_body_demonstrations.py — Created by dimaswisodewo on 2026-11-11.

"""Render the body-exercise demonstrations from ArtSource/BodyDemonstrations.blend.

Run from the repository root:
    blender -b ArtSource/BodyDemonstrations.blend -t 4 \
      -P Tools/render_body_demonstrations.py -- --clip arm_raise_demonstration

Omit --clip to render every clip. The source scene has one bright yellow rig, camera,
and lights; this script authors each motion on its FK controls and exports a silent MP4.
"""

import argparse
from math import radians
from pathlib import Path
import shutil
import subprocess
import tempfile

import bpy
from mathutils import Quaternion, Vector


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Itera/Resources/Animations"
RIG = "Male_Basemesh_Rig_01"


def arm(side, *rotations):
    return {f"upper_arm_fk.{side}": rotations}


def elbow(side, angle):
    return {f"forearm_fk.{side}": (("Y", angle),)}


def combine(*parts):
    result = {}
    for part in parts:
        result.update(part)
    return result


def cross(side):
    direction = 1 if side == "R" else -1
    return arm(side, ("Y", 45 * direction), ("Z", 140 * direction))


def rotation(side, inward):
    direction = 1 if side == "R" else -1
    return combine(
        arm(side, ("Y", -40 * direction), ("Z", -65 * direction if inward else 0)),
        {f"forearm_fk.{side}": (("X", -105),)},
    )


def flexion(side):
    return arm(side, ("X", -145))


NEUTRAL_ARMS = combine(
    arm("R", ("Y", -30)),
    arm("L", ("Y", 30)),
)


def rotation_cycle(start, peak):
    return [
        (1, {}), (13, {}),
        (25, start), (37, start),
        (61, peak), (73, peak),
        (85, start), (97, {}), (108, {}),
    ]


# Each tuple is (frame, pose). The first and last poses match for clean looping.
CLIPS = {
    "arm_raise_demonstration": {
        "poses": [
            (1, {}), (13, {}),
            (49, combine(arm("R", ("Y", 80)), arm("L", ("Y", -80)))),
            (61, combine(arm("R", ("Y", 80)), arm("L", ("Y", -80)))),
            (96, {}),
        ],
    },
    "elbow_bend_demonstration": {
        "poses": [
            (1, {}), (13, {}),
            (49, combine(elbow("R", 120), elbow("L", -120))),
            (61, combine(elbow("R", 120), elbow("L", -120))),
            (96, {}),
        ],
    },
    "directional_reach_demonstration": {
        "poses": [
            (1, {}), (13, {}),
            (37, arm("R", ("Y", 45))), (49, {}),
            (73, cross("R")), (85, {}),
            (109, arm("R", ("Y", 115))), (121, {}),
            (132, {}),
        ],
    },
    "cross_midline_right_demonstration": {
        "poses": [(1, {}), (13, {}), (49, cross("R")), (61, cross("R")), (96, {})],
    },
    "cross_midline_both_demonstration": {
        "poses": [
            (1, {}), (13, {}), (43, cross("R")), (55, {}),
            (85, cross("L")), (97, {}), (108, {}),
        ],
    },
    "shoulder_external_rotation_right_demonstration": {
        "poses": rotation_cycle(rotation("R", True), rotation("R", False)),
    },
    "shoulder_external_rotation_both_demonstration": {
        "poses": rotation_cycle(
            combine(rotation("R", True), rotation("L", True)),
            combine(rotation("R", False), rotation("L", False)),
        ),
    },
    "shoulder_internal_rotation_right_demonstration": {
        "poses": rotation_cycle(rotation("R", False), rotation("R", True)),
    },
    "shoulder_internal_rotation_both_demonstration": {
        "poses": rotation_cycle(
            combine(rotation("R", False), rotation("L", False)),
            combine(rotation("R", True), rotation("L", True)),
        ),
    },
    "shoulder_flexion_right_demonstration": {
        "camera": "side",
        "poses": [(1, {}), (13, {}), (61, flexion("R")), (73, flexion("R")), (120, {})],
    },
    "shoulder_flexion_both_demonstration": {
        "camera": "side",
        "poses": [
            (1, {}), (13, {}),
            (61, combine(flexion("R"), flexion("L"))),
            (73, combine(flexion("R"), flexion("L"))),
            (120, {}),
        ],
    },
    "sit_to_stand_demonstration": {
        "camera": "side",
        "chair": True,
        "poses": [
            (1, {}), (13, {}),
            (45, {"sit": 1}), (61, {"sit": 1}),
            (115, {}), (132, {}),
        ],
    },
}


def add_chair(scene):
    material = bpy.data.materials.new("Muted chair")
    material.diffuse_color = (0.42, 0.39, 0.36, 1)
    material.use_nodes = True
    shader = next(node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = (0.42, 0.39, 0.36, 1)

    pieces = [
        ((0, 0.24, 0.48), (0.83, 0.62, 0.08)),
        ((0, 0.53, 0.84), (0.83, 0.08, 0.73)),
        ((-0.34, -0.01, 0.23), (0.07, 0.07, 0.46)),
        ((0.34, -0.01, 0.23), (0.07, 0.07, 0.46)),
        ((-0.34, 0.48, 0.23), (0.07, 0.07, 0.46)),
        ((0.34, 0.48, 0.23), (0.07, 0.07, 0.46)),
    ]
    for location, dimensions in pieces:
        bpy.ops.mesh.primitive_cube_add(size=1, location=location)
        obj = bpy.context.object
        obj.dimensions = dimensions
        obj.data.materials.append(material)


def set_camera(scene, kind):
    camera = scene.camera
    camera.location = (5.5, -3.5, 1.5) if kind == "side" else (0.75, -6.0, 1.55)
    target = Vector((0, 0, 0.9))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.3


def local_rotation(bone, rotations):
    rest = bone.bone.matrix_local.to_quaternion()
    result = Quaternion()
    axes = {"X": (1, 0, 0), "Y": (0, 1, 0), "Z": (0, 0, 1)}
    for axis, degrees in rotations:
        rotation = rest.inverted() @ Quaternion(axes[axis], radians(degrees)) @ rest
        result = rotation @ result
    return result


def animate(scene, config):
    rig = bpy.data.objects[RIG]
    # Keep Rigify's drivers: clearing animation data would disconnect FK controls
    # from the deform bones and produce a still render.
    if rig.animation_data:
        rig.animation_data.action = None
    controls = {
        name
        for _, pose in config["poses"]
        for name in pose
        if name != "sit"
    }
    controls.update(NEUTRAL_ARMS)
    if config.get("chair"):
        controls.update(
            f"{part}.{side}"
            for side in ("L", "R")
            for part in ("thigh_fk", "shin_fk")
        )

    for side in ("L", "R"):
        rig.pose.bones[f"upper_arm_parent.{side}"]["IK_FK"] = 1.0
        rig.pose.bones[f"thigh_parent.{side}"]["IK_FK"] = 1.0

    for frame, pose in config["poses"]:
        pose = combine(NEUTRAL_ARMS, pose)
        scene.frame_set(frame)
        seated = bool(pose.get("sit"))
        rig.location = (0, 0, -0.38 if seated else 0)
        if config.get("chair"):
            rig.keyframe_insert(data_path="location", frame=frame)
        for name in controls:
            rotations = pose.get(name, ())
            if config.get("chair") and name.startswith("thigh_fk") and seated:
                rotations = (("X", -80),)
            if config.get("chair") and name.startswith("shin_fk") and seated:
                rotations = (("X", 80),)
            bone = rig.pose.bones[name]
            bone.rotation_quaternion = local_rotation(bone, rotations)
            bone.keyframe_insert(data_path="rotation_quaternion", frame=frame)

    scene.frame_start = 1
    scene.frame_end = config["poses"][-1][0]


def ffmpeg_path():
    executable = shutil.which("ffmpeg")
    if executable:
        return executable
    brew = shutil.which("brew")
    if not brew:
        raise RuntimeError("FFmpeg is missing, and Homebrew is unavailable")
    subprocess.run([brew, "install", "ffmpeg"], check=True)
    executable = shutil.which("ffmpeg")
    if not executable:
        raise RuntimeError("Homebrew installed FFmpeg but it is not on PATH")
    return executable


def render_clip(name, encoder):
    config = CLIPS[name]
    scene = bpy.context.scene
    set_camera(scene, config.get("camera", "front"))
    if config.get("chair"):
        add_chair(scene)
    animate(scene, config)

    scene.render.fps = 24
    scene.render.fps_base = 1
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.use_freestyle = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    OUTPUT.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix=f"itera-{name}-") as temporary:
        scene.render.filepath = str(Path(temporary) / "frame_")
        bpy.ops.render.render(animation=True)
        output = OUTPUT / f"{name}.mp4"
        subprocess.run(
            [
                encoder, "-hide_banner", "-loglevel", "error", "-y",
                "-framerate", "24", "-start_number", "1",
                "-i", str(Path(temporary) / "frame_%04d.png"),
                "-f", "lavfi", "-i", "color=c=0xF5F5F5:s=768x768:r=24",
                "-filter_complex", "[1:v][0:v]overlay=shortest=1:format=auto,format=yuv420p[v]",
                "-map", "[v]", "-frames:v", str(scene.frame_end),
                "-c:v", "libx264", "-crf", "18", "-movflags", "+faststart",
                str(output),
            ],
            check=True,
        )
        print(f"Rendered {name}: {output}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--clip", choices=sorted(CLIPS))
    arguments = parser.parse_args(__import__("sys").argv[__import__("sys").argv.index("--") + 1:] if "--" in __import__("sys").argv else [])
    encoder = ffmpeg_path()
    for name in [arguments.clip] if arguments.clip else CLIPS:
        render_clip(name, encoder)


if __name__ == "__main__":
    main()
