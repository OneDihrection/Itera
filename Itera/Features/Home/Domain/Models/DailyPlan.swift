//
//  DailyPlan.swift
//  Itera
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
        case .therapy(.cup):
            return "symbol:cup.and.saucer.fill"
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

enum DailyPlan {
    /// Every exercise the app offers, in practice order: hand and forearm first, then arm,
    /// shoulder, trunk and the task. The plan is fixed for now; change this list to change it.
    static let standard: [DailyPlanItem] = {
        let fingers = FingerExercise.allCases.map { DailyPlanItem(exercise: .finger($0)) }

        let arm: [DailyPlanItem] = [
            DailyPlanItem(exercise: .therapy(.armRaise)),
            DailyPlanItem(exercise: .therapy(.elbowBend)),
            DailyPlanItem(exercise: .therapy(.directionalReach)),
            DailyPlanItem(exercise: .therapy(.cup)),
        ]

        let shoulderAndTrunk: [DailyPlanItem] = [
            DailyPlanItem(exercise: .balance(.crossMidline)),
            DailyPlanItem(exercise: .balance(.externalRotation)),
            DailyPlanItem(exercise: .balance(.internalRotation)),
            DailyPlanItem(exercise: .balance(.shoulderFlexion)),
            DailyPlanItem(exercise: .balance(.sitToStand)),
        ]

        return fingers + arm + shoulderAndTrunk + [DailyPlanItem(exercise: .therapy(.foldTowel))]
    }()
}

/// Which plan items were completed on one calendar day.
struct DailyPlanProgress: Equatable {
    /// Start of the day this progress belongs to.
    var day: Date
    var completed: Set<String>

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
