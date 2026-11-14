//
//  AppDependencies.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppDependencies: HistoryRecovering {
    let home: FingerHomeViewModel
    let forearm: FingerHomeViewModel
    private(set) var session: FingerSessionViewModel?
    let permissions: PermissionManager
    @ObservationIgnored private let camera = HandCameraService(poseBackend: .saved)
    @ObservationIgnored private let fingerAudio = GuidanceAudioService()
    @ObservationIgnored private let repository: any FingerSessionRepository
    @ObservationIgnored private let forearmRepository: any FingerSessionRepository

    let tracking = BodyTrackingService(poseBackend: .saved)
    let audio = SessionAudioService()
    let routine: RoutineViewModel
    let taskRoutine: RoutineViewModel
    /// Today's plan across programs; Beranda shows it and finishing sessions report to it.
    let dailyPlan = DailyPlanViewModel(repository: LocalDailyPlanProgressRepository())
    /// Who uses this iPad (ADR-008); nil until chosen on first launch.
    var role = AppRole.saved {
        didSet { UserDefaults.standard.set(role?.rawValue, forKey: AppRole.storageKey) }
    }
    @ObservationIgnored let cloud = CareCloudService()
    let doctor: DoctorCareViewModel
    let patientCare: PatientCareViewModel
    var selectedRoutine = Routine.demo()
    let sessions: any SessionRepository
    private(set) var recoveryFailure: String?
    private(set) var recovering = true
    private var didRecover = false

    init(permissions: PermissionManager) {
        self.permissions = permissions
        let directory = URL.applicationSupportDirectory.appendingPathComponent(
            "Sessions", isDirectory: true)
        sessions = LocalSessionRepository(directory: directory)
        routine = RoutineViewModel(repository: LocalRoutineRepository(
            url: URL.applicationSupportDirectory.appendingPathComponent("routines.json")
        ))

        taskRoutine = RoutineViewModel(repository: LocalRoutineRepository(
            url: URL.applicationSupportDirectory.appendingPathComponent("routines-task-oriented.json")
        ))

        let repository = LocalFingerSessionRepository()
        self.repository = repository
        home = FingerHomeViewModel(repository: repository, routineRepository: LocalFingerRoutineRepository())
        let forearmRepository = LocalFingerSessionRepository(category: .forearm)
        self.forearmRepository = forearmRepository
        forearm = FingerHomeViewModel(
            category: .forearm, repository: forearmRepository,
            routineRepository: LocalFingerRoutineRepository(category: .forearm)
        )
        doctor = DoctorCareViewModel(repository: LocalDoctorPatientRepository(), cloud: cloud)
        patientCare = PatientCareViewModel(repository: LocalPatientCareLinkRepository(), cloud: cloud)
    }

    // MARK: - Care (ADR-008)

    /// Returns to the role choice. Local and iCloud data stay, so choosing the same role again
    /// restores the patients or the doctor link.
    func signOut(router: NavigationRouter) {
        doctor.cancelPairing()
        dailyPlan.end(router: router)
        router.dismiss()
        router.popToRoot()
        role = nil
    }

    /// Debug builds launched with `-IteraStandardPlan` run the fixed plan without a doctor, so
    /// sessions can be tried on a device or Simulator that is not paired.
    private var usesStandardPlan: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-IteraStandardPlan")
        #else
        return false
        #endif
    }

    /// Patient mode: shows the stored prescription at once, then receives a newer one and sends
    /// new results when iCloud is reachable. Failures keep the stored prescription.
    func refreshCare() async {
        guard role == .patient else {
            return
        }

        await patientCare.load()
        applyPrescription()

        await patientCare.refreshPrescription()
        applyPrescription()

        await patientCare.upload(
            fingerHistory: home.history + forearm.history,
            therapyHistory: (try? await sessions.history()) ?? []
        )
    }

    func applyPrescription() {
        guard !usesStandardPlan else {
            return
        }

        dailyPlan.apply(patientCare.prescription)
    }

    func playButtonClick() {
        guard UserDefaults.standard.object(forKey: PracticePreferences.buttonSounds) as? Bool ?? true else {
            return
        }
        // A tap sound never lands on top of narration from a running session.
        guard !audio.isNarrating else {
            return
        }

        fingerAudio.playButtonClick()
    }

    func routineModel(for category: TherapyCategory) -> RoutineViewModel {
        switch category {
        case .arm: return routine
        case .taskOriented: return taskRoutine
        }
    }

    func homeModel(for category: ExerciseCategory) -> FingerHomeViewModel {
        category == .fingers ? home : forearm
    }

    func refreshHomes() async {
        await home.refresh()
        await forearm.refresh()
    }

    /// - Parameter only: one exercise of the category to run alone, as a daily-plan item does.
    func prepareSession(
        category: ExerciseCategory = .fingers,
        continuing: Bool = false,
        only: FingerExercise? = nil,
        side: HandSide? = nil,
        prescribed: PrescriptionItem? = nil
    ) {
        let model = homeModel(for: category)
        let checkpoint = continuing ? model.checkpoint : nil
        var routine = checkpoint?.routine ?? model.routine

        if checkpoint == nil {
            routine.only = only
            routine.side = side ?? routine.side

            // A doctor's values replace the saved finger settings for this session only.
            if let prescribed {
                routine.sets = prescribed.sets
                routine.repetitions = prescribed.work
                routine.restSeconds = prescribed.setRestSeconds
            }
        }

        session = FingerSessionViewModel(
            routine: routine, checkpoint: checkpoint,
            camera: camera, audio: fingerAudio, permissions: permissions,
            repository: category == .fingers ? repository : forearmRepository
        )
    }

    func recoverHistory() async {
        guard !didRecover else { return }
        recovering = true
        do {
            try await sessions.recoverInterrupted()
            recoveryFailure = nil
            didRecover = true
        } catch {
            recoveryFailure = error.localizedDescription
        }
        recovering = false
    }

    /// Applies the saved tracking backends to both camera services, after Settings changes them.
    func applyTrackingBackends() {
        tracking.usePoseBackend(.saved)
        camera.usePoseBackend(.saved)
    }

    func makeAngleMeasurement() -> AngleMeasurementViewModel {
        AngleMeasurementViewModel(tracking: tracking, camera: camera)
    }

    func makeSession() -> TherapySessionViewModel {
        TherapySessionViewModel(tracking: tracking, audio: audio, repository: sessions, routine: selectedRoutine)
    }
}
