<!-- README.md — Created by dimaswisodewo on 2026-10-28. -->

# Cup detector

The complete `yolo11n.mlpackage` was copied unchanged from `VisionPoc/VisionPoc/Features/Rehabilitation/Models/yolo11n.mlpackage` in the adjacent VisionPoc checkout. Xcode compiles it to `yolo11n.mlmodelc`. The model’s original metadata and weights are preserved.

The tracking owner loads the model only for cup activities, uses Vision’s `scaleFit` preprocessing, and accepts the highest-confidence `cup` classification at confidence 0.45 or greater. Vision bounding-box centers are mapped from lower-left normalized coordinates to aspect-correct unmirrored domain coordinates. Exactly one fresh cup near the selected wrist is required by cup-evidence stages. No camera images or detector streams are saved.

Simulator compilation verifies packaging only. Detection accuracy, inference age, sustained performance, orientation, mirroring, and wrist proximity still require physical M1-iPad verification.

# MediaPipe hand landmarker

`MediaPipe/hand_landmarker.task` (float16, 7,819,105 bytes, SHA-256 `fbc2a30080c3c557093b5ddfc334698132eb341044ccee322ccf8bcf3607cde1`) was downloaded unchanged on 2026-11-11 from `https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task`, the model linked from Google's MediaPipe Hand Landmarker guide, which distributes it under the Apache License 2.0. `MediaPipeHandDetector` loads it only when the finger camera uses the MediaPipe backend. No frames or landmarks are saved. Detection quality and handedness on unmirrored front-camera frames still require physical M1-iPad verification.
