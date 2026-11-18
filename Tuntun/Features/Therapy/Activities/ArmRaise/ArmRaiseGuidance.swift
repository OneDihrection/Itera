//
//  ArmRaiseGuidance.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 14/11/2026.
//

import Foundation

/// The approved arm-raise scripts share progression while keeping anatomical side in every
/// recording key. They follow any prescription: recordings that name a number play only when
/// it is true (see `ScriptedRepetitions`), and the session speaks other counts with Marizka
/// number clips.
enum ArmRaiseGuidance {
    static func prefix(for side: TherapySide) -> String {
        "armRaise." + side.rawValue + "."
    }

    /// The intro names its goals ("dua set… lima repetisi") only for the recorded prescription;
    /// otherwise the screen shows them.
    static func introduction(for side: TherapySide, sets: Int, repetitions: Int) -> [String] {
        let prefix = prefix(for: side)
        guard ScriptedRepetitions.matchesRecording(sets: sets, repetitions: repetitions) else {
            return [prefix + "intro.focus"]
        }

        return [prefix + "intro.focus", prefix + "intro.goals"]
    }

    /// The briefs name one arm, so an arm raise whose sides take turns keeps the general guidance.
    static func applies(to activity: SessionActivity) -> Bool {
        activity.kind == .armRaise && !activity.alternatesSides
    }

    /// Praise after `repetition`, or nil when no recording says it ("Satu repetisi selesai"
    /// exists for the first four); the session then speaks the Marizka number instead.
    static func praiseKey(after repetition: Int, side: TherapySide) -> String? {
        guard (1...4).contains(repetition) else {
            return nil
        }

        return prefix(for: side) + "rep.\(repetition).complete"
    }

    /// The recorded set summary when its numbers are true, otherwise nil. "summary.first"
    /// promises five repetitions and a second set; "summary.final" ten repetitions in two sets.
    static func summaryKey(setNumber: Int, sets: Int, goal: Int, side: TherapySide) -> String? {
        guard goal == ScriptedRepetitions.recordedRepetitions else {
            return nil
        }

        if setNumber == 1, sets >= 2 {
            return prefix(for: side) + "summary.first"
        }

        if setNumber == sets, sets == ScriptedRepetitions.recordedSets {
            return prefix(for: side) + "summary.final"
        }

        return nil
    }

    static func movementKey(_ movement: MovementSnapshot, set: Int, goal: Int, side: TherapySide) -> String {
        let prefix = prefix(for: side)
        switch movement.phase {
        case .startCapture:
            return prefix + "calibration.start"
        case .targetCapture:
            return prefix + "calibration.target"
        case .returnToStart:
            return prefix + "calibration.return"
        case .countdown:
            return prefix + (set == 1 ? "countdown.first" : "countdown.next")
        case .practice:
            let repetition = ScriptedRepetitions.recordedRepetition(movement.count + 1, goal: goal)
            let action = movement.instruction == "session.moveTarget" ? "raise" : "return"
            return prefix + "rep.\(repetition).\(action)"
        }
    }
}
