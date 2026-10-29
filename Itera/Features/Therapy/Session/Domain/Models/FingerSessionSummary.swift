//
//  FingerSessionSummary.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

enum SessionOutcome: String { case completed, stopped, interrupted, savedForLater }
enum SessionFeeling: String, CaseIterable, Identifiable {
    // Retain historical values so older reports keep their original meaning.
    case comfortable, tired, painful, difficult, justRight, easy
    static let exerciseChoices: [Self] = [.difficult, .justRight, .easy]
    var id: String { rawValue }
    var title: String { "feeling." + rawValue }
    var symbol: String {
        switch self {
        case .comfortable: return "face.smiling"
        case .tired: return "moon.zzz"
        case .painful: return "heart.slash"
        case .difficult: return "face.dashed"
        case .justRight: return "face.smiling"
        case .easy: return "face.smiling.inverse"
        }
    }
}

struct FingerExerciseResult: Identifiable {
    var id: String { kind.rawValue }
    let kind: FingerExercise
    let completedSets: Int
    let repetitions: Int
    let activeSeconds: Double
    let observedGain: Double?
    let completed: Bool
    var skipped = false
}

struct FingerSessionSummary: Identifiable {
    let id: UUID
    let started: Date
    var ended: Date
    let routine: FingerRoutine
    var results: [FingerExerciseResult]
    var outcome: SessionOutcome
    var feeling: SessionFeeling?
    var exerciseIndex: Int
    var totalRepetitions: Int { results.reduce(0) { $0 + $1.repetitions } }
    var totalSets: Int { results.reduce(0) { $0 + $1.completedSets } }
    var duration: Double { results.reduce(0) { $0 + $1.activeSeconds } }
}
