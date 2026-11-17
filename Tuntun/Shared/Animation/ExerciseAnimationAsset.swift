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

    /// Seconds into the clip where the target pose is held, at the middle of its keyframed hold.
    ///
    /// The frames come from `Tools/author_body_demonstrations.py` (24 FPS, frame 1 at zero) and
    /// must be updated whenever a clip is re-exported with different timing. `reachPose` picks
    /// the reach clip's pose: 0 outward, 1 across the body, 2 up.
    func peakSeconds(reachPose: Int = 0) -> Double {
        let frame: Double

        switch self {
        case .armRaise, .elbowBend:
            frame = 55
        case .directionalReach:
            let reachFrames: [Double] = [40, 100, 166]
            frame = reachFrames[min(max(reachPose, 0), reachFrames.count - 1)]
        }

        return (frame - 1) / 24
    }
}

/// How a demonstration video plays: looping, or held on its first frame or its target pose.
enum TherapyAnimationPlayback: String {
    case looping, staticStart, staticPeak
}

/// Outcome of loading a demonstration video.
enum ExerciseVideoEvent {
    case ready, failed
}
