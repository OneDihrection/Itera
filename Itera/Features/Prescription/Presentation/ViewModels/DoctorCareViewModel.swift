//
//  DoctorCareViewModel.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import Foundation
import Observation

/// The doctor's patients: adding and pairing them, editing and publishing prescriptions, and
/// reading their results. Each patient has its own encrypted `CareChannel`, kept in the Keychain.
/// Local state is saved after every change, so the doctor's edits survive without a connection.
@MainActor
@Observable
final class DoctorCareViewModel {
    /// The in-person pairing in progress for one patient (ADR-008, "Pairing in the clinic").
    struct Pairing: Equatable {
        enum Status: Equatable {
            case waitingForPatient
            case paired
            case expired
            case failed(String)
        }

        let patientID: UUID
        let channel: CareChannel
        var status: Status
    }

    static let doctorNameKey = "doctor.name"
    /// How long a shown code accepts a patient's consent.
    static let pairingLifetime: TimeInterval = 10 * 60

    private(set) var patients: [DoctorPatient] = []
    private(set) var pairing: Pairing?
    private(set) var errorKey: String?
    /// The CloudKit code and system text behind `errorKey`, for diagnosis.
    private(set) var errorDetail: String?
    private(set) var busy = false
    var doctorName = UserDefaults.standard.string(forKey: DoctorCareViewModel.doctorNameKey) ?? "" {
        didSet { UserDefaults.standard.set(doctorName, forKey: Self.doctorNameKey) }
    }

    @ObservationIgnored private let repository: any DoctorPatientRepository
    @ObservationIgnored private let cloud: CareCloudService
    @ObservationIgnored private var pairingTask: Task<Void, Never>?
    @ObservationIgnored private var loadFailed = false

    init(repository: any DoctorPatientRepository, cloud: CareCloudService) {
        self.repository = repository
        self.cloud = cloud
    }

    func patient(_ id: UUID) -> DoctorPatient? {
        patients.first { $0.id == id }
    }

    private func channel(for id: UUID) -> CareChannel? {
        CareKeychain.channel(account: id.uuidString)
    }

    // MARK: - Local state

    func load() async {
        do {
            patients = try await repository.load()
            loadFailed = false
        } catch {
            // Never overwrite an unreadable file with an empty list.
            loadFailed = true
            errorKey = "care.error.storage"
        }
    }

    private func persist() async {
        guard !loadFailed else {
            return
        }

        do {
            try await repository.save(patients)
        } catch {
            errorKey = "care.error.storage"
        }
    }

    private func update(_ id: UUID, _ change: (inout DoctorPatient) -> Void) {
        guard let index = patients.firstIndex(where: { $0.id == id }) else {
            return
        }

        change(&patients[index])
    }

    // MARK: - Patients

    /// Adds a patient with a new secret, then shows the code. Nothing reaches iCloud until the
    /// code is shown, and nothing readable ever does.
    func addPatient(named name: String) async -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return nil
        }

        let id = UUID()
        CareKeychain.save(.random(), account: id.uuidString)
        patients.append(DoctorPatient(id: id, name: trimmed))
        await persist()
        startPairing(for: id)
        return id
    }

    func removePatient(_ id: UUID) async {
        busy = true
        defer { busy = false }

        if let channel = channel(for: id) {
            do {
                try await cloud.removeDoctorRecords(on: channel)
            } catch {
                fail(error, during: "remove patient")
                return
            }
        }

        if pairing?.patientID == id {
            cancelPairing()
        }

        CareKeychain.delete(account: id.uuidString)
        patients.removeAll { $0.id == id }
        await persist()
    }

    // MARK: - Prescriptions

    func setDraft(_ items: [PrescriptionItem], for id: UUID) {
        update(id) { $0.draft = items }
        Task { await persist() }
    }

    /// Publishes the draft as the next immutable version. Drafts never reach the patient.
    func publish(_ id: UUID) async {
        guard let patient = patient(id), let channel = channel(for: id) else {
            return
        }

        let prescription = Prescription(
            version: (patient.latest?.version ?? 0) + 1,
            publishedAt: Date(),
            items: patient.draft
        )

        guard prescription.isValid else {
            errorKey = "care.error.invalidPrescription"
            return
        }

        busy = true
        defer { busy = false }

        do {
            try await cloud.publishPrescriptions(patient.published + [prescription], on: channel)
        } catch {
            fail(error, during: "publish")
            return
        }

        update(id) { $0.published.append(prescription) }
        await persist()
    }

    // MARK: - Results

    func refreshResults() async {
        for patient in patients where patient.paired {
            guard let channel = channel(for: patient.id) else {
                continue
            }

            do {
                let results = try await cloud.results(on: channel)
                update(patient.id) { $0.results = results }
            } catch {
                fail(error, during: "results")
            }
        }

        await persist()
    }

    func clearError() {
        errorKey = nil
        errorDetail = nil
    }

    private func fail(_ error: Error, during step: String) {
        CareCloudService.log(error, during: step)
        errorKey = Self.key(for: error)
        errorDetail = CareCloudService.errorDetail(for: error)
    }

    // MARK: - Pairing

    /// Publishes a fresh invitation on the patient's channel and waits for their consent.
    func startPairing(for id: UUID) {
        cancelPairing()

        guard let channel = channel(for: id) else {
            errorKey = "care.error.storage"
            return
        }

        pairing = Pairing(patientID: id, channel: channel, status: .waitingForPatient)

        pairingTask = Task { [weak self] in
            await self?.runPairing(patientID: id, channel: channel)
        }
    }

    func cancelPairing() {
        pairingTask?.cancel()
        pairingTask = nil
        pairing = nil
    }

    private func runPairing(patientID: UUID, channel: CareChannel) async {
        do {
            let shownAt = Date()
            try await cloud.publishOffer(CareCloudService.Offer(doctorName: doctorName, createdAt: shownAt), on: channel)

            let deadline = shownAt.addingTimeInterval(Self.pairingLifetime)

            while Date() < deadline {
                try Task.checkCancellation()

                // A reply from before this code was shown belongs to an earlier pairing.
                if let reply = try await cloud.reply(on: channel), reply.acceptedAt >= shownAt.addingTimeInterval(-5) {
                    update(patientID) { $0.paired = true }
                    pairing?.status = .paired
                    await persist()
                    return
                }

                try await Task.sleep(for: .seconds(2))
            }

            pairing?.status = .expired
        } catch is CancellationError {
            return
        } catch {
            CareCloudService.log(error, during: "pairing")
            errorDetail = CareCloudService.errorDetail(for: error)
            pairing?.status = .failed(Self.key(for: error))
        }
    }

    static func key(for error: Error) -> String {
        CareCloudService.errorKey(for: error)
    }
}
