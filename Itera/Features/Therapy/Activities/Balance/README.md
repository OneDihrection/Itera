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

Balancing accepts body joints at confidence 0.20, then applies a confidence-aware adaptive filter. Slow landmark motion uses stronger smoothing to remove stationary jitter, while fast intentional motion raises the current-frame weight so the wrist guide remains responsive. Single-frame jumps beyond a joint-specific fraction of shoulder width are rejected. When a joint is temporarily occluded, its cached point follows the observed torso translation for at most 1.25 seconds instead of remaining frozen while the rest of the skeleton moves. Hip orientation, hip width, shoulder orientation, and spine direction are checked before rendering; an incoherent frame keeps the last stable overlay instead of drawing a folded torso. Cached joints may render the guide, but a touch is credited only while the active wrist and central posture anchors are fresh in the current frame.

The compensation index is the maximum of three normalized signals:

```text
lean = abs(atan2(cross(u₀, u), dot(u₀, u))) / 18°
shift = abs(dot(n - r, lateral₀) - baselineOffset) / shoulderWidth₀ / 0.40
rotation = max(0, 1 - normalizedShoulderWidth / baselineNormalizedShoulderWidth) / 0.40
index = max(lean, shift, rotation)
```

`normalizedShoulderWidth` divides shoulder span by torso length, reducing sensitivity to the patient moving uniformly closer to the camera. An index at or above 1 must remain present for 0.75 seconds before it flags compensation, clears target dwell, and prevents scoring. Brief Vision spikes are ignored. A confirmed warning clears after 0.5 seconds of safe posture, and each continuous warning is counted once.

## Target and movement metrics

The active wrist reaches toward an orange target centered on the opposite shoulder, with a radius equal to 34% of current shoulder width, and remains there for the configured 3–20 seconds. Circle contact is authoritative for scoring so a wrist visibly inside the target is not rejected by a momentary torso-axis jitter; actual crossed-midline time continues to be captured separately as a metric. Once a hold begins, a 40% exit radius and a 0.4-second tracking grace prevent boundary jitter or a single missing wrist frame from restarting the countdown; compensation still resets the hold immediately. The engine captures each visible wrist's neutral position at baseline. After every successful touch, the orange shoulder target disappears and a generous blue return target appears at that neutral position. The wrist must return to its anatomical side, enter the return target, and remain stable for 5 seconds before another repetition can begin. The blue target displays its own progress ring and countdown in both the camera overlay and instruction panel. This return gate is mandatory for Right, Left, and Both modes, and remains active through temporary compensation warnings so a posture warning cannot bypass it.

Across-midline time accumulates only from fresh, safe frames. Path smoothness uses finite differences of aspect-corrected wrist position:

```text
velocity = Δposition / Δt
acceleration = Δvelocity / Δt
jerk = Δacceleration / Δt / shoulderWidth
smoothness = 1 / (1 + RMS(jerk) · 0.002)
```

Frames with gaps above 300 ms clear transient evidence. The output is an exercise-aid metric, not a validated clinical balance or range-of-motion measurement.

## Presentation and completion

The setup screen stores the touch goal, hold duration, and active-arm choice. Right and Left repeat only the selected arm after every return-to-start phase; Both begins on the right and alternates arms. A bundled RealityKit demonstration loads `crossMidline.usdz`, with the editable Blender source retained under `ArtSource/BalanceCrossMidline.blend`. The mannequin includes a clear face, hands, clothing, legs, target ring, and midline so the cross-body movement remains legible at the setup-card size.

After the final target, capture stops and a modal-style overlay presents target completion, across-midline time, compensation load, and the jerk-derived smoothness estimate. The chart explicitly identifies camera results as session estimates rather than clinical assessment. The patient can repeat with fresh calibration or end and return to the Balancing overview.

On-device voice recognition continuously restarts after a command, a final transcription, or a transient recognition error. It accepts the English commands `pause`, `start`, `end`, and `repeat`, plus the Indonesian equivalents `jeda`, `mulai`, `akhiri`, and `ulangi`. The selected app language determines the preferred recognition locale, with the other supported locale used as an availability fallback. Touch controls remain available whenever recognition is unavailable or a command is missed.
