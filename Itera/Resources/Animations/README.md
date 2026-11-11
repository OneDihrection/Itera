<!-- README.md — Created by dimaswisodewo on 2026-10-28. -->

# Animation sources

`HandRotation/hand_rotation_left.mov` and `hand_rotation_right.mov` are the forearm-rotation examples (640 × 640, 6.459 s, one full cycle: palm, turned at the midpoint, palm). `HandRotationExample` shows the movie for the exercised side as the mirrored camera preview displays it (the left hand uses `hand_rotation_right.mov` and the right hand `hand_rotation_left.mov`), so no reflection is applied. Demonstration and range loop the full cycle; the turn plays the first half and the return the second. Reduce Motion and pause hold the turned pose. Physical-device checks of playback and side choice remain pending.

The body-exercise demonstrations are the connected-joint renders of the light-brown rig in [`ArtSource/BodyDemonstrationsReview/BodyDemonstrations_ConnectedMotion.blend`](../../../ArtSource/BodyDemonstrationsReview/BodyDemonstrations_ConnectedMotion.blend), authored by [`Tools/author_body_demonstrations.py`](../../../Tools/author_body_demonstrations.py) and rendered to 768 × 768, 24 FPS silent H.264 MP4s following [`Documentation/AnimationRenderingStandard.md`](../../../Documentation/AnimationRenderingStandard.md). The app uses them for arm raise, elbow bend, directional reach, cross-midline reach, shoulder external and internal rotation, shoulder flexion, and sit-to-stand. Every arm clip shows the right arm; left-arm playback reflects it, and choosing both arms plays the right-arm clip beside its reflection. Fold towel and hand or finger exercises retain their separate demonstrations because they require different assets.

Physical-device verification of the new MP4s and the side-by-side both-arm layout remains pending.
