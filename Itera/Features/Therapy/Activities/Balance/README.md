<!-- Balance — Created by Gracia A on 02/11/2026. -->

# Balancing: cross-midline movement

This feature uses the existing `BodyTrackingService` and `VNDetectHumanBodyPoseRequest` pipeline. Finger exercises continue to own `VNDetectHumanHandPoseRequest`; Balancing uses body-pose wrists so the hand, shoulders, hips, and spinal axis remain in one coordinate space.

## Coordinate system

Vision publishes normalized image coordinates. Before geometry, `TrackingObservation.point(_:)` converts each point to image-height units:

```text
p = (x · imageWidth / imageHeight, y)
```

This makes horizontal and vertical distances comparable for a landscape camera. Presentation alone applies front-camera mirroring.

The current torso axis is the line through the pelvis root `r` and neck `n`:

```text
u = normalize(n - r)
M(t) = r + t · u
signedSide(p) = cross(u, p - r)
```

A wrist has crossed when its signed side has the same sign as the opposite shoulder and its distance from the axis exceeds 5% of shoulder width.

## Baseline and compensation

Baseline posture is the mean of one contiguous second of stable neck, root, and shoulder observations. Movement beyond 30% of shoulder width or a shoulder-width change above 35% restarts calibration. These relaxed limits prevent ordinary posture adjustments and landmark jitter from repeatedly restarting setup.

Balancing accepts body joints at confidence 0.25. Torso landmarks use a 45% current / 55% previous temporal filter for stability, while elbows and wrists use 70% current / 30% previous so the target interaction remains responsive. The overlay retains each last-known joint for at most 1.25 seconds so brief occlusion from loose clothing or a hand touching the opposite shoulder does not make the guide flash. Cached joints may render the guide, but a touch is credited only while the active wrist and central posture anchors are fresh in the current frame.

The compensation index is the maximum of three normalized signals:

```text
lean = abs(atan2(cross(u₀, u), dot(u₀, u))) / 18°
shift = abs(dot(n - r, lateral₀) - baselineOffset) / shoulderWidth₀ / 0.40
rotation = max(0, 1 - normalizedShoulderWidth / baselineNormalizedShoulderWidth) / 0.40
index = max(lean, shift, rotation)
```

`normalizedShoulderWidth` divides shoulder span by torso length, reducing sensitivity to the patient moving uniformly closer to the camera. An index at or above 1 must remain present for 0.75 seconds before it flags compensation, clears target dwell, and prevents scoring. Brief Vision spikes are ignored. A confirmed warning clears after 0.5 seconds of safe posture, and each continuous warning is counted once.

## Target and movement metrics

The active wrist must cross the midline, enter a radius equal to 28% of current shoulder width around the opposite shoulder, and remain there for the configured 3–20 seconds. The patient hears a localized countdown, then returns the wrist to its anatomical side before the next arm begins. The completed shoulder target disappears until the next arm becomes active.

Across-midline time accumulates only from fresh, safe frames. Path smoothness uses finite differences of aspect-corrected wrist position:

```text
velocity = Δposition / Δt
acceleration = Δvelocity / Δt
jerk = Δacceleration / Δt / shoulderWidth
smoothness = 1 / (1 + RMS(jerk) · 0.002)
```

Frames with gaps above 300 ms clear transient evidence. The output is an exercise-aid metric, not a validated clinical balance or range-of-motion measurement.

## Presentation and completion

The setup screen stores the touch goal and hold duration. A bundled RealityKit demonstration loads `crossMidline.usdz`, with the editable Blender source retained under `ArtSource/BalanceCrossMidline.blend`. Touch and English voice commands can pause or resume the session.

After the final target, capture stops and a modal-style overlay presents target completion, across-midline time, compensation load, and the jerk-derived smoothness estimate. The chart explicitly identifies camera results as session estimates rather than clinical assessment. The patient can repeat with fresh calibration or end and return to the Balancing overview; the English on-device commands are `repeat` and `end`.
