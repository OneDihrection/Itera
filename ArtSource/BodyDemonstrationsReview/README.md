<!-- README.md — Created by dimaswisodewo on 2026-11-11. -->

# Body demonstrations: connected-joint review set

Review renders of the eight right-side body-exercise clips, authored for natural movement of connected joints. They are not bundled in the app and do not replace `Itera/Resources/Animations`.

- **Rig and scene:** the light-brown-skinned Male_Basemesh_Rig_01 (material `#C68E6D`) in `BodyDemonstrations_ConnectedMotion.blend`, which holds one action per clip. Arm clips show the right arm only so the app can reflect them for the left. Every clip starts and ends standing with both arms relaxed at the sides. No props are used; sit-to-stand is mimed without a chair.
- **Render:** 768 × 768, 24 FPS, silent H.264 `yuv420p` MP4 on a `#F5F5F5` background, following `Documentation/AnimationRenderingStandard.md`. Arm clips use the front camera; shoulder flexion and sit-to-stand use the side camera.
- **Authoring:** [`Tools/author_body_demonstrations.py`](../../Tools/author_body_demonstrations.py) solves each pose from a few parameters (arm elevation, plane, humeral roll, elbow angle, trunk lean and yaw). It couples shoulder blade lift and protraction, chest extension for overhead reach, head and neck follow-through, and ankle-pinned legs when the pelvis drops.
- **Encoding:** transparent PNG frames were composited over the background with FFmpeg, as in the standard.

Physical-device playback and light/dark surface checks remain pending.
