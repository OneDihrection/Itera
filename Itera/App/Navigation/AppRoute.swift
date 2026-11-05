//
//  AppRoute.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

enum AppRoute: Hashable {
    case home
    case fingerHome(ExerciseCategory)
    case routineConfiguration(TherapyCategory)
    case exercisePicker(TherapyCategory)
    case therapySession
    case therapyOverview(TherapyCategory)
    case balanceOverview(BalanceExercise)
    case armRotationHome
    case balanceSession(
        exercise: BalanceExercise,
        repetitions: Int,
        holdSeconds: Int,
        armSelection: BalanceArmSelection
    )
    case plan(ExerciseCategory)
    case reports
    case taskReports
    case achievements
    case achievementCelebration
    case achievement(String)
    case achievementShare(String)
    case report(UUID)
    case fingerPause
    case fingerSession
    case reflection
    case sessionComplete
    case practicePreferences
    case routineSettings(ExerciseCategory)
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
