<!-- README.md — Created by dimaswisodewo on 2026-10-28. -->

# Animation sources

The two unmodified USDZ assets were copied from the local VisionPoc proof of concept's `VisionPoc/Resources/USDZ` directory. Names and authored transforms/materials are preserved. The arm-raise illustration is bilateral; reflecting its rendered picture does not make it unilateral.

`Shared/Animation/ExerciseAnimationRenderer.swift` adapts the local VisionPoc `Features/Therapy/TherapyAnimationRenderer.swift` implementation: recursive animation discovery, imported clip duration, parent-container framing, lighting, cancellation, and ten-second loading fallback. No external runtime assets are fetched.

Physical-device verification of static start/peak poses, playback, materials, and side reflection remains pending.
