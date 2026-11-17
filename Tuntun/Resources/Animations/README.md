<!-- README.md — Created by dimaswisodewo on 2026-10-28. -->

# Animation sources

`HandRotation/hand_rotation_left.mov` and `hand_rotation_right.mov` are the forearm-rotation examples (640 × 640, 6.459 s, one full cycle: palm, turned at the midpoint, palm). `HandRotationExample` shows the movie for the exercised side as the mirrored camera preview displays it (the left hand uses `hand_rotation_right.mov` and the right hand `hand_rotation_left.mov`), so no reflection is applied. Demonstration and range loop the full cycle; the turn plays the first half and the return the second. Reduce Motion and pause hold the turned pose. Physical-device checks of playback and side choice remain pending.

The body-exercise demonstrations are the connected-joint renders of the light-brown rig in [`ArtSource/BodyDemonstrationsReview/BodyDemonstrations_ConnectedMotion.blend`](../../../ArtSource/BodyDemonstrationsReview/BodyDemonstrations_ConnectedMotion.blend), authored by [`Tools/author_body_demonstrations.py`](../../../Tools/author_body_demonstrations.py) and rendered to 768 × 768, 24 FPS silent H.264 MP4s following [`Documentation/AnimationRenderingStandard.md`](../../../Documentation/AnimationRenderingStandard.md). The app uses them for arm raise, elbow bend, directional reach, cross-midline reach, shoulder external and internal rotation, shoulder flexion, and sit-to-stand. Every arm clip shows the right arm; left-arm playback reflects it, and with both arms chosen the demonstration follows the active arm. Fold towel and hand or finger exercises retain their separate demonstrations because they require different assets.

Since 2026-11-17 the seven seated-exercise clips (arm raise, elbow bend, directional reach, cross midline, external and internal rotation, shoulder flexion) are framed from the waist up by `frame_torso` in the same tool, so the standing rig does not suggest standing practice; `sit_to_stand_demonstration.mp4` keeps the full body. Re-export with `export_clip` (see the tool's run comment).

During practice the app holds each body clip on its target pose instead of looping. The held times are the middle of each keyframed hold in the authoring tool (`ExerciseAnimationAsset.peakSeconds(reachPose:)` and `TMBalanceExerciseDemonstrationView.peakSeconds`); a re-export that changes timing must update them.

Physical-device verification of the new MP4s remains pending.
