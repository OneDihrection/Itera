//
//  MediaPipeHandDetector.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

#if canImport(MediaPipeTasksVision)
import AVFoundation
import MediaPipeTasksVision

/// MediaPipe Hand Landmarker for the finger camera, producing the same `HandEvidence` as Vision.
///
/// MediaPipe's 21 landmarks use Vision's joint order (wrist, then four joints per finger from
/// the thumb), so only coordinates are converted. Runs synchronously in `.video` mode on the
/// caller's capture queue, so work stays bounded by the capture output dropping late frames.
final class MediaPipeHandDetector {
    /// MediaPipe reports only hands that passed its 0.5 presence threshold and gives no per-joint
    /// confidence, so every joint of a reported hand gets this value (above Itera's 0.5 gates).
    private static let jointConfidence: Float = 0.9

    private let landmarker: HandLandmarker
    private var lastMilliseconds = -1

    init(maximumHands: Int) throws {
        guard let path = Bundle.main.path(forResource: "hand_landmarker", ofType: "task") else {
            throw CocoaError(.fileNoSuchFile)
        }

        let options = HandLandmarkerOptions()
        options.baseOptions.modelAssetPath = path
        options.runningMode = .video
        options.numHands = maximumHands
        landmarker = try HandLandmarker(options: options)
    }

    /// - Parameter buffer: a 32BGRA camera frame, already rotated upright by the capture connection.
    func hands(
        in buffer: CMSampleBuffer,
        timestamp: Double,
        generation: UUID,
        width: Double,
        height: Double
    ) throws -> [HandEvidence] {
        // Video mode rejects timestamps that do not increase.
        let milliseconds = max(Int((timestamp * 1000).rounded()), lastMilliseconds + 1)
        lastMilliseconds = milliseconds

        let image = try MPImage(sampleBuffer: buffer, orientation: .up)
        let result = try landmarker.detect(videoFrame: image, timestampInMilliseconds: milliseconds)

        return result.landmarks.indices.map { index in
            // MediaPipe's origin is the top-left corner; Vision's (and Itera's) is bottom-left.
            let points = result.landmarks[index].map { landmark in
                HandPoint(
                    x: Double(landmark.x),
                    y: 1 - Double(landmark.y),
                    confidence: Self.jointConfidence
                )
            }

            return HandEvidence(
                timestamp: timestamp,
                generation: generation,
                width: width,
                height: height,
                side: side(at: index, in: result),
                points: points,
                world: world(at: index, in: result)
            )
        }
    }

    /// World landmarks are meters around the hand's centre with Y down; flipping Y and Z is a
    /// rotation, so angles are unchanged and Y points up like the rest of Itera.
    private func world(at index: Int, in result: HandLandmarkerResult) -> [TherapyVector3]? {
        guard result.worldLandmarks.indices.contains(index) else {
            return nil
        }

        return result.worldLandmarks[index].map { landmark in
            TherapyVector3(x: Double(landmark.x), y: -Double(landmark.y), z: -Double(landmark.z))
        }
    }

    /// MediaPipe labels handedness as if the image were mirrored like a selfie. Itera's frames are
    /// unmirrored, so the label is swapped to name the anatomical hand.
    private func side(at index: Int, in result: HandLandmarkerResult) -> HandSide? {
        guard result.handedness.indices.contains(index),
              let label = result.handedness[index].first?.categoryName?.lowercased() else {
            return nil
        }

        switch label {
        case "left":
            return .right
        case "right":
            return .left
        default:
            return nil
        }
    }
}
#endif
