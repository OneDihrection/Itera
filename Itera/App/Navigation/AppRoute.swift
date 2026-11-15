//
//  AppRoute.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

enum AppRoute: Hashable {
    case therapySession
    case balanceSession(exercise: BalanceExercise, settings: BalancePracticeSettings)
    case reports
    /// One arm-practice session with its key-repetition replays.
    case sessionReport(UUID)
    case report(UUID)
    case fingerSession
    case sessionComplete
    case practicePreferences
    /// The page after the last daily-plan exercise.
    case planNext
    /// The intro page of one daily-plan item, by item id.
    case planIntro(String)
}

enum AppTab: Hashable {
    case home
    case reports
}

struct RoutePresentation: Identifiable {
    let id: UUID
    let route: AppRoute

    init(id: UUID = UUID(), route: AppRoute) {
        self.id = id
        self.route = route
    }
}
