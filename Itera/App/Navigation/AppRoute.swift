//
//  AppRoute.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

enum AppRoute: Hashable {
    case home
    case fingerHome
    case routineConfiguration
    case exercisePicker
    case therapySession
    case therapyOverview
    case plan
    case reports
    case achievements
    case achievementCelebration
    case achievement(String)
    case report(UUID)
    case fingerSession
    case reflection
    case routineSettings
    case exercisePreview(FingerExercise)
}

enum AppTab: Hashable {
    case home
    case reports
}

struct RoutePresentation: Identifiable {
    let id = UUID()
    let route: AppRoute
}
