//
//  PatientCareViewModel.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import Foundation
import Observation

/// The patient's link to their one doctor: consent and pairing, receiving prescriptions and
/// sending results over the encrypted `CareChannel`. The patient never edits a prescription.
@MainActor
@Observable
final class PatientCareViewModel {
    enum Connection: Equatable {
        case idle
        case checking
        /// Waiting for the patient's consent; `replacing` names the current doctor.
        case consent(doctorName: String, replacing: String?)
        case connecting
        case connected
        case failed(String)
    }

    /// The patient iPad keeps one channel: one patient, one doctor.
    static let keychainAccount = "care.patient"

    private(set) var link: PatientCareLink?
    private(set) var connection = Connection.idle
    private(set) var errorKey: String?
    /// The CloudKit code and system text behind the last failure, for diagnosis.
    private(set) var errorDetail: String?

    @ObservationIgnored private let repository: any PatientCareLinkRepository
    @ObservationIgnored private let cloud: CareCloudService
    @ObservationIgnored private var pendingChannel: CareChannel?
    @ObservationIgnored private var pendingOffer: CareCloudService.Offer?
    @ObservationIgnored private var loadFailed = false

    init(repository: any PatientCareLinkRepository, cloud: CareCloudService) {
        self.repository = repository
        self.cloud = cloud
    }

    private var channel: CareChannel? {
        CareKeychain.channel(account: Self.keychainAccount)
    }

    /// The prescription Beranda runs, or nil when no valid one has arrived.
    var prescription: Prescription? {
        link?.prescription.flatMap { $0.isValid ? $0 : nil }
    }

    func load() async {
        do {
            link = try await repository.load()
            loadFailed = false
        } catch {
            loadFailed = true
            errorKey = "care.error.storage"
        }
    }

    private func persist() async {
        guard !loadFailed else {
            return
        }

        do {
            try await repository.save(link)
        } catch {
            errorKey = "care.error.storage"
        }
    }

    private func fail(_ error: Error, during step: String) -> String {
        CareCloudService.log(error, during: step)
        errorDetail = CareCloudService.errorDetail(for: error)
        return DoctorCareViewModel.key(for: error)
    }

    // MARK: - Pairing

    /// From the scanned QR or the typed 26-character code.
    func check(code: String) async {
        guard let channel = CareChannel(code: code) else {
            connection = .failed("care.error.code")
            return
        }

        connection = .checking

        do {
            try await cloud.requireAccount()

            guard let offer = try await cloud.offer(on: channel),
                  Date().timeIntervalSince(offer.createdAt) < DoctorCareViewModel.pairingLifetime else {
                connection = .failed("care.error.code")
                return
            }

            pendingChannel = channel
            pendingOffer = offer
            let replacing = self.channel == channel ? nil : link?.doctorName
            connection = .consent(doctorName: offer.doctorName, replacing: replacing)
        } catch {
            connection = .failed(fail(error, during: "connect"))
        }
    }

    func decline() {
        pendingChannel = nil
        pendingOffer = nil
        connection = .idle
    }

    /// The patient's explicit consent: replaces any previous doctor, then tells this one.
    func accept() async {
        guard let channel = pendingChannel, let offer = pendingOffer else {
            return
        }

        connection = .connecting

        do {
            if let previous = self.channel, previous != channel {
                // One patient, one doctor: the previous doctor loses the results first.
                try await cloud.removePatientRecords(on: previous)
            }

            try await cloud.publishReply(on: channel)
            CareKeychain.save(channel, account: Self.keychainAccount)
            link = PatientCareLink(doctorName: offer.doctorName)
            await persist()
            await refreshPrescription()
            connection = .connected
        } catch {
            connection = .failed(fail(error, during: "accept"))
        }

        pendingChannel = nil
        pendingOffer = nil
    }

    func dismissConnection() {
        connection = .idle
    }

    // MARK: - Sync

    /// Keeps the newest valid version. An invalid version is ignored and the previous one stays.
    func refreshPrescription() async {
        guard link != nil, let channel else {
            return
        }

        do {
            let versions = try await cloud.prescriptions(on: channel)

            for version in versions {
                link?.versions[version.version] = version.publishedAt
            }

            if let newest = versions.filter(\.isValid).max(by: { $0.version < $1.version }),
               newest.version > (link?.prescription?.version ?? 0) {
                link?.prescription = newest
            }

            await persist()
        } catch {
            errorKey = fail(error, during: "prescriptions")
        }
    }

    /// Sends results not sent yet, tagged with the version in force when each session started.
    func upload(fingerHistory: [FingerSessionSummary], therapyHistory: [SessionSummary]) async {
        guard let link, let channel else {
            return
        }

        let results = fingerHistory.flatMap {
            SharedResultBuilder.results(from: $0, version: link.version(at: $0.started))
        } + therapyHistory.flatMap {
            SharedResultBuilder.results(from: $0, version: link.version(at: $0.startedAt))
        }

        let new = results.filter { !link.uploaded.contains($0.id) }

        guard !new.isEmpty else {
            return
        }

        do {
            try await cloud.upload(new, on: channel)
            self.link?.uploaded.formUnion(new.map(\.id))
            await persist()
        } catch {
            errorKey = fail(error, during: "upload")
        }
    }

    func leaveDoctor() async {
        do {
            if let channel {
                try await cloud.removePatientRecords(on: channel)
            }

            CareKeychain.delete(account: Self.keychainAccount)
            link = nil
            await persist()
        } catch {
            errorKey = fail(error, during: "leave")
        }
    }
}
