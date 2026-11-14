//
//  CareLink.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import Foundation

// MARK: - Shared results

/// One held angle range pair as the doctor sees it, from a finger or arm exercise.
struct SharedAngle: Codable, Equatable, Identifiable {
    /// A report title key such as `report.angle.knuckleFlexion` or `measurement.body.elbowFlexion`.
    let titleKey: String
    let before: AngleRange?
    let after: AngleRange?
    let threeD: Bool

    var id: String { titleKey }

    var spanChange: Double? {
        guard let before, let after else {
            return nil
        }

        return after.span - before.span
    }
}

/// One exercise of one patient session, as summary values only: what the patient's iPad sends
/// to the doctor. Never landmarks, video or audio (section 1).
struct SharedExerciseResult: Codable, Equatable, Identifiable {
    /// Stable across uploads: session id, exercise and side, so re-sending replaces it.
    let id: String
    let sessionID: UUID
    let date: Date
    /// Catalog id, as in `PrescriptionItem.exercise`.
    let exercise: String
    let side: HandSide?
    let completedSets: Int
    let plannedSets: Int
    /// Repetitions, rounds or towels done in all sets.
    let work: Int
    let completed: Bool
    let practiceSeconds: Double
    let angles: [SharedAngle]
    /// The prescription version in force when the session started, if one was.
    let prescriptionVersion: Int?
}

// MARK: - Doctor side

/// One patient as the doctor's iPad keeps them. The channel secret is in the Keychain under
/// this id, never in this record.
struct DoctorPatient: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    /// True once the patient consented on their iPad.
    var paired = false
    /// The unpublished edit; publishing copies it into `published`.
    var draft: [PrescriptionItem] = []
    var published: [Prescription] = []
    /// The patient's results, read from their shared zone.
    var results: [SharedExerciseResult] = []

    var latest: Prescription? { published.max { $0.version < $1.version } }

    /// True when the draft differs from what the patient has.
    var hasUnpublishedChanges: Bool { draft != (latest?.items ?? []) }
}

// MARK: - Patient side

/// The patient iPad's link to its one doctor and the last prescription it received. The channel
/// secret is in the Keychain (`PatientCareViewModel.keychainAccount`), never in this record.
struct PatientCareLink: Codable, Equatable {
    var doctorName: String
    var prescription: Prescription?
    /// Every version seen, with its publishing date, to tag results with the version in force.
    var versions: [Int: Date] = [:]
    /// Result ids already sent, so each upload sends only new ones.
    var uploaded: Set<String> = []

    func version(at date: Date) -> Int? {
        versions.filter { $0.value <= date }.max { $0.value < $1.value }?.key
    }
}

// MARK: - Repositories

protocol DoctorPatientRepository: Sendable {
    func load() async throws -> [DoctorPatient]
    func save(_ patients: [DoctorPatient]) async throws
}

protocol PatientCareLinkRepository: Sendable {
    func load() async throws -> PatientCareLink?
    func save(_ link: PatientCareLink?) async throws
}
