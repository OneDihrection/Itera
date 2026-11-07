<!-- README.md — Created by dimaswisodewo on 2026-10-28. -->

# Animation sources

The two unmodified USDZ assets were copied from the local VisionPoc proof of concept's `VisionPoc/Resources/USDZ` directory. Names and authored transforms/materials are preserved. The arm-raise illustration is bilateral; reflecting its rendered picture does not make it unilateral.

`Shared/Animation/ExerciseAnimationRenderer.swift` adapts the local VisionPoc `Features/Therapy/TherapyAnimationRenderer.swift` implementation: recursive animation discovery, imported clip duration, parent-container framing, lighting, cancellation, and ten-second loading fallback. No external runtime assets are fetched.

Physical-device verification of static start/peak poses, playback, materials, and side reflection remains pending.

`HandRotation/hand_rotation_left.mov` and `hand_rotation_right.mov` are the forearm-rotation examples (640 × 640, 6.459 s, one full cycle: palm, turned at the midpoint, palm). `HandRotationExample` shows the movie for the exercised side as the mirrored camera preview displays it (the left hand uses `hand_rotation_right.mov` and the right hand `hand_rotation_left.mov`), so no reflection is applied. Demonstration and range loop the full cycle; the turn plays the first half and the return the second. Reduce Motion and pause hold the turned pose. Physical-device checks of playback and side choice remain pending.
