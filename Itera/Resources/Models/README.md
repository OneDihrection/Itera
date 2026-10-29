<!-- README.md — Created by dimaswisodewo on 2026-10-28. -->

# Cup detector

The complete `yolo11n.mlpackage` was copied unchanged from `VisionPoc/VisionPoc/Features/Rehabilitation/Models/yolo11n.mlpackage` in the adjacent VisionPoc checkout. Xcode compiles it to `yolo11n.mlmodelc`. The model’s original metadata and weights are preserved.

The tracking owner loads the model only for cup activities, uses Vision’s `scaleFit` preprocessing, and accepts the highest-confidence `cup` classification at confidence 0.45 or greater. Vision bounding-box centers are mapped from lower-left normalized coordinates to aspect-correct unmirrored domain coordinates. Exactly one fresh cup near the selected wrist is required by cup-evidence stages. No camera images or detector streams are saved.

Simulator compilation verifies packaging only. Detection accuracy, inference age, sustained performance, orientation, mirroring, and wrist proximity still require physical M1-iPad verification.
