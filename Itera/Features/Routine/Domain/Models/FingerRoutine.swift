//
//  FingerRoutine.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

typealias TrainingSide = HandSide

extension HandSide {
    var title: String { "side." + rawValue }
}

enum FingerExercise: String, CaseIterable, Identifiable {
    case fullFist, hookFist, opposition, spreading, extensionSequence
    var id: String { rawValue }
    var title: String { "exercise." + rawValue }
    var detail: String { "detail." + rawValue }
    var symbol: String {
        switch self {
        case .fullFist: return "hand.raised.fill"
        case .hookFist: return "hand.point.up.left.fill"
        case .opposition: return "hand.pinch.fill"
        case .spreading: return "hand.raised.fingers.spread.fill"
        case .extensionSequence: return "hand.draw.fill"
        }
    }
    var isSequential: Bool { self == .opposition || self == .extensionSequence }
}

struct FingerRoutine: Equatable {
    var side: TrainingSide = .left
    var sets = 2
    var repetitions = 5
    var restSeconds = 20
    var voiceControl = false
    var ambientSound = false
    let exercises = FingerExercise.allCases
}
