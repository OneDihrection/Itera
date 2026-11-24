//
//  ScriptedRepetitions.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation

/// How the approved Indonesian scripts, recorded for two sets of five repetitions, follow any
/// prescription without new recordings.
///
/// A recorded sentence plays only when the numbers it speaks are true. Otherwise the caller
/// speaks the count with a Marizka number clip, or leaves the sentence out.
enum ScriptedRepetitions {
    /// The prescription the scripts' numbered sentences were recorded for.
    static let recordedSets = 2
    static let recordedRepetitions = 5

    /// Whether sentences naming the goals or totals ("dua set… lima repetisi") are true.
    static func matchesRecording(sets: Int, repetitions: Int) -> Bool {
        sets == recordedSets && repetitions == recordedRepetitions
    }

    /// The recorded repetition whose instructions guide `repetition` of `goal`.
    ///
    /// The first repetition keeps its opening wording and the last its "satu repetisi lagi";
    /// repetitions between them cycle through the recorded second to fourth. A goal of five
    /// therefore maps every repetition to itself.
    static func recordedRepetition(_ repetition: Int, goal: Int) -> Int {
        if repetition <= 1 {
            return 1
        }

        if repetition >= goal {
            return recordedRepetitions
        }

        return 2 + (repetition - 2) % 3
    }

    // MARK: - Scripts of 2026-11-23

    /// The 2026-11-23 scripts write later sets for three repetitions: an opening one, a middle
    /// one and a closing one.
    static let recordedLaterSetRepetitions = 3

    /// Repetition goals whose "dengan total … repetisi" and "… kali di setiap setnya" sentences
    /// are recorded: the scripts' three and the app's default five.
    static let recordedGoals: Set<Int> = [3, 5]

    /// Exercise totals recorded in "seluruh set, dengan total … repetisi": two sets of either goal.
    static let recordedTotals: Set<Int> = [6, 10]

    /// The recorded later-set repetition whose lines guide `repetition` of `goal`: the first
    /// keeps its opening, the last its closing wording, and every one between them the middle.
    static func recordedLaterSetRepetition(_ repetition: Int, goal: Int) -> Int {
        if repetition <= 1 {
            return 1
        }

        if repetition >= goal {
            return recordedLaterSetRepetitions
        }

        return 2
    }

    /// Whether "dua set, dengan … kali di setiap setnya" can be said with a recorded number.
    static func hasRecordedGoals(sets: Int, repetitions: Int) -> Bool {
        sets == 2 && recordedGoals.contains(repetitions)
    }
}
