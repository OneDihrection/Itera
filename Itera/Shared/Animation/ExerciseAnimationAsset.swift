//
//  ExerciseAnimationAsset.swift
//  Itera
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
}

/// How a demonstration video plays: looping, or held on its first or middle frame.
enum TherapyAnimationPlayback: String {
    case looping, staticStart, staticPeak
}

/// Outcome of loading a demonstration video.
enum ExerciseVideoEvent {
    case ready, failed
}
