//
//  ScriptedSummary.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 23/11/2026.
//

import Foundation

/// The 2026-11-23 scripts' set summary, shared by the hand scripts and the Balancing scripts.
enum ScriptedSummary {
    /// The first set's summary, with its total when a recording states it, then the rest before
    /// set two; the last set's, with the exercise total when recorded, then the thanks. A set
    /// between them keeps the general ending after the Marizka number.
    static func lines(completedSets: Int, sets: Int, goal: Int) -> [NarrationLine] {
        if completedSets >= sets {
            let total = goal * sets
            let summary = ScriptedRepetitions.recordedTotals.contains(total)
                ? NarrationLine(key: "scripted.summary.finalTotal %lld", argument: total)
                : NarrationLine(key: "scripted.summary.final")
            return [summary, NarrationLine(key: "scripted.summary.thanks")]
        }

        if completedSets == 1 {
            let summary = ScriptedRepetitions.recordedGoals.contains(goal)
                ? NarrationLine(key: "scripted.summary.firstTotal %lld", argument: goal)
                : NarrationLine(key: "scripted.summary.first")
            return [summary, NarrationLine(key: "scripted.summary.restBeforeSecondSet")]
        }

        return [.number(goal), NarrationLine(key: "session.good")]
    }
}
