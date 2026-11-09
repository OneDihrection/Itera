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
        /// A whole finger program: finger sessions always run every exercise in their category.
        case finger(ExerciseCategory)
        /// One guided-session activity kind, run alone.
        case therapy(TherapyKind)
        case balance(BalanceExercise)
    }

    /// Stable identifier persisted in plan progress. Never a display string.
    let id: String
    let exercise: Exercise

    /// Asset name of the plan illustration, `plan-<id>`.
    var artwork: String {
        "plan-" + id
    }

    /// Existing artwork of the same program, shown until the plan illustration is bundled.
    var fallbackArtwork: String {
        switch exercise {
        case .finger(let category):
            return category.artwork
        case .therapy(.foldTowel):
            return "symbol:square.stack.3d.up"
        case .therapy:
            return "symbol:figure.arms.open"
        case .balance(.sitToStand):
            return "symbol:figure.seated.side"
        case .balance(.crossMidline):
            return "symbol:figure.stand"
        case .balance:
            return "symbol:arrow.triangle.2.circlepath"
        }
    }
}

enum DailyPlan {
    /// Today's practice, in order. The plan is fixed for now; change this list to change it.
    static let standard: [DailyPlanItem] = [
        DailyPlanItem(id: "fingers", exercise: .finger(.fingers)),
        DailyPlanItem(id: "armRaise", exercise: .therapy(.armRaise)),
        DailyPlanItem(id: "crossMidline", exercise: .balance(.crossMidline)),
        DailyPlanItem(id: "externalRotation", exercise: .balance(.externalRotation)),
        DailyPlanItem(id: "sitToStand", exercise: .balance(.sitToStand)),
        DailyPlanItem(id: "foldTowel", exercise: .therapy(.foldTowel)),
    ]
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
