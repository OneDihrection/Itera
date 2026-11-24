//
//  ExerciseAnimationAsset.swift
//  Tuntun
//
//  Created by dimaswisodewo on 28/10/2026.
//

enum ExerciseAnimationAsset: String {
    case armRaise
    case elbowBend
    case directionalReach

    var demonstrationResource: String {
        switch self {
        case .armRaise: return "arm_raise_demonstration"
        case .elbowBend: return "elbow_bend_demonstration"
        case .directionalReach: return "directional_reach_demonstration"
        }
    }

    /// The rise and return segments of the clip; `reachPose` picks the reach clip's pose:
    /// 0 outward, 1 across the body, 2 up.
    ///
    /// The frames come from `Tools/author_body_demonstrations.py` and must be updated whenever a
    /// clip is re-exported with different timing.
    func timeline(reachPose: Int = 0) -> DemonstrationTimeline {
        switch self {
        case .armRaise, .elbowBend:
            return DemonstrationTimeline(riseFrames: 13...55, returnFrames: 61...97)
        case .directionalReach:
            let reachTimelines = [
                DemonstrationTimeline(riseFrames: 13...40, returnFrames: 43...67),
                DemonstrationTimeline(riseFrames: 67...100, returnFrames: 103...133),
                DemonstrationTimeline(riseFrames: 133...166, returnFrames: 169...199)
            ]
            return reachTimelines[min(max(reachPose, 0), reachTimelines.count - 1)]
        }
    }
}

/// Where a body demonstration moves from its start pose to its target pose and back.
///
/// The rise ends at the middle of the clip's keyframed target hold and the return ends on the
/// start pose, so each segment's last frame is the pose to hold. Frames are the authoring tool's
/// (24 FPS, frame 1 at zero).
struct DemonstrationTimeline: Equatable {
    let rise: ClosedRange<Double>
    let returning: ClosedRange<Double>

    init(riseFrames: ClosedRange<Double>, returnFrames: ClosedRange<Double>) {
        rise = Self.seconds(riseFrames.lowerBound)...Self.seconds(riseFrames.upperBound)
        returning = Self.seconds(returnFrames.lowerBound)...Self.seconds(returnFrames.upperBound)
    }

    /// The target pose, held at the end of the rise.
    var peakSeconds: Double {
        rise.upperBound
    }

    /// The start pose, held at the end of the return.
    var neutralSeconds: Double {
        returning.upperBound
    }

    private static func seconds(_ frame: Double) -> Double {
        (frame - 1) / 24
    }
}

/// How a demonstration video plays: looping, or moving to and holding its start or target pose,
/// as the finger examples play the half-cycle matching the current instruction.
enum TherapyAnimationPlayback: Equatable {
    case looping, neutral, peak
}

/// Outcome of loading a demonstration video.
enum ExerciseVideoEvent {
    case ready, failed
}
