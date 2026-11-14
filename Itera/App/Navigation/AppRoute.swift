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
    case balanceSession(exercise: BalanceExercise, settings: BalancePracticeSettings)
    case plan(ExerciseCategory)
    case reports
    case taskReports
    case report(UUID)
    case fingerSession
    case sessionComplete
    case practicePreferences
    case routineSettings(ExerciseCategory)
    case exercisePreview(FingerExercise)
    /// The page after the last daily-plan exercise.
    case planNext
    /// The intro page of one daily-plan item, by item id.
    case planIntro(String)
    /// Trial joint-angle measurement for comparing tracking backends.
    case angleMeasurement
    /// Doctor mode (ADR-008): one patient's prescription and progress.
    case doctorPatient(UUID)
    case doctorAddPatient
    case doctorPairing(UUID)
    case prescriptionItem(patient: UUID, item: UUID)
    /// Patient mode: pairing with the doctor and consent.
    case connectDoctor
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
