//
//  DailyPlan.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

import Foundation

/// One exercise in today's plan. The plan only names what to run; its settings (sets,
/// repetitions, hold, side) stay owned by that program's own settings page.
struct DailyPlanItem: Identifiable, Hashable {
    enum Exercise: Hashable {
        /// One finger or forearm exercise, run alone with its category's settings.
        case finger(FingerExercise)
        /// One guided-session activity kind, run alone.
        case therapy(TherapyKind)
        case balance(BalanceExercise)
    }

    let exercise: Exercise

    /// Stable identifier persisted in plan progress: the exercise's own raw value, never a
    /// display string.
    var id: String {
        switch exercise {
        case .finger(let exercise):
            return exercise.rawValue
        case .therapy(let kind):
            return kind.rawValue
        case .balance(let exercise):
            return exercise.rawValue
        }
    }

    /// Asset name of the plan illustration, `plan-<id>`.
    var artwork: String {
        "plan-" + id
    }

    /// Existing artwork of the same exercise, shown when no plan illustration is bundled.
    var fallbackArtwork: String {
        switch exercise {
        case .finger(let exercise):
            return exercise.artwork
        case .therapy(.elbowBend):
            return "symbol:figure.strengthtraining.traditional"
        case .therapy(.directionalReach):
            return "symbol:hand.point.up.left"
        case .therapy(.foldTowel):
            return "symbol:square.stack.3d.up"
        case .therapy:
            return "symbol:figure.arms.open"
        case .balance(.sitToStand):
            return "symbol:figure.seated.side"
        case .balance(.crossMidline):
            return "symbol:figure.stand"
        case .balance(.shoulderFlexion):
            return "symbol:figure.wave"
        case .balance:
            return "symbol:arrow.triangle.2.circlepath"
        }
    }
}

/// Sets and repetitions chosen for one exercise in Settings; `nil` keeps the program's own.
/// Zero sets or repetitions hides the exercise from the plan.
struct DailyPlanOverrides: Equatable {
    /// What Settings offers; 0 hides the exercise.
    static let setsRange = 0...3
    static let repetitionsRange = 0...12

    /// What a plan session runs with, so the live set list never exceeds three rows of twelve.
    static let playableSets = 1...3
    static let playableRepetitions = 1...12

    var sets: Int?
    var repetitions: Int?

    static func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }

    /// True when Settings set the sets or repetitions to 0, which hides the exercise.
    var hidesExercise: Bool {
        sets == 0 || repetitions == 0
    }
}

/// The plan-wide rests chosen in Settings: one short rest between every set of every exercise,
/// and one long rest between exercises (and between the sides of a one-side-per-session item).
enum DailyPlanRest {
    /// Rest before each later set, in seconds; Settings steps by 5.
    static let shortRange = 5...120
    static let defaultShortSeconds = 15

    /// Narrated long-rest breaths. Recorded "N napas lagi" clips exist only up to six.
    static let longBreathsRange = 2...6
    static let defaultLongBreaths = 6
}

enum DailyPlan {
    /// The daily exercises in practice order: the two scripted exercises first, then the other
    /// hand and forearm exercises, arm, shoulder, trunk and the task. This is the default order;
    /// Settings can reorder and hide items (`DailyPlanLayout`) and set each one's side and counts.
    static let standard: [DailyPlanItem] = {
        // The approved scripts open with Sentuh Jempol ke Jari ("Hari ini kita akan mulai…")
        // and continue with Angkat Lengan ("Selanjutnya…"), so both lead the plan.
        let scripted: [DailyPlanItem] = [
            DailyPlanItem(exercise: .finger(.opposition)),
            DailyPlanItem(exercise: .therapy(.armRaise)),
        ]

        let fingers = FingerExercise.allCases
            .filter { $0 != .opposition }
            .map { DailyPlanItem(exercise: .finger($0)) }

        let arm: [DailyPlanItem] = [
            DailyPlanItem(exercise: .therapy(.elbowBend)),
            DailyPlanItem(exercise: .therapy(.directionalReach)),
        ]

        let shoulderAndTrunk: [DailyPlanItem] = [
            DailyPlanItem(exercise: .balance(.crossMidline)),
            DailyPlanItem(exercise: .balance(.externalRotation)),
            DailyPlanItem(exercise: .balance(.internalRotation)),
            DailyPlanItem(exercise: .balance(.shoulderFlexion)),
            DailyPlanItem(exercise: .balance(.sitToStand)),
        ]

        return scripted + fingers + arm + shoulderAndTrunk + [DailyPlanItem(exercise: .therapy(.foldTowel))]
    }()
}

/// Which plan items were completed on one calendar day.
struct DailyPlanProgress: Equatable {
    /// Start of the day this progress belongs to.
    var day: Date
    var completed: Set<String>
    /// The items the plan showed that day, so the Progress calendar can tell a fully completed
    /// day from a partial one after the layout changes. Empty in progress saved before 21/11/2026.
    var planned: [String] = []

    static func empty(on date: Date, calendar: Calendar = .current) -> DailyPlanProgress {
        DailyPlanProgress(day: calendar.startOfDay(for: date), completed: [])
    }

    /// Progress from an earlier day no longer counts: each day starts a fresh plan.
    func current(on date: Date, calendar: Calendar = .current) -> DailyPlanProgress {
        guard calendar.isDate(day, inSameDayAs: date) else {
            return .empty(on: date, calendar: calendar)
        }

        return self
    }
}
