//
//  CareCloudService.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import CloudKit
import Foundation

/// Every CloudKit call of ADR-008 (revised 2026-11-11), with no UI or local state.
///
/// All data lives in the container's public database, which counts against the developer's
/// quota, so a full personal iCloud never blocks the app. Every payload is AES-GCM encrypted
/// with the doctor–patient `CareChannel`, and record names are derived from it, so the public
/// database holds only unreadable, unlinkable blobs.
///
/// Write rights come from CloudKit's default public-database roles: anyone signed in may create
/// records, and only a record's creator may change or delete it. The doctor therefore writes the
/// prescriptions and the patient writes the results; neither can alter the other's records.
///
/// The container is created on first use, so a build without the iCloud entitlement still
/// launches until a CloudKit action is taken.
final class CareCloudService: @unchecked Sendable {
    /// One generic record type, so the schema reveals nothing about what a record holds.
    private static let recordType = "CareRecord"
    private static let boxKey = "box"
    /// How many months of results the doctor reads back.
    private static let resultMonths = 12

    /// The entitlements' container, `iCloud.<bundle identifier>`: no identifier in code to keep in
    /// step with project.yml.
    private lazy var container = CKContainer.default()
    private var database: CKDatabase { container.publicCloudDatabase }

    enum CareError: LocalizedError {
        case noAccount
        case malformedRecord

        var errorDescription: String? {
            switch self {
            case .noAccount:
                return "care.error.noAccount"
            case .malformedRecord:
                return "care.error.cloud"
            }
        }
    }

    /// The doctor's invitation, read by the patient before consent.
    struct Offer: Codable {
        let doctorName: String
        let createdAt: Date
    }

    /// The patient's consent, which tells the doctor the link is complete.
    struct Reply: Codable {
        let acceptedAt: Date
    }

    private enum Logical {
        static let offer = "offer"
        static let reply = "reply"
        static let prescriptions = "prescriptions"

        static func results(_ month: String) -> String { "results-" + month }
    }

    // MARK: - Errors

    /// A message key for what actually went wrong. Only network problems say "check the
    /// connection"; setup, account and schema problems each get their own message.
    static func errorKey(for error: Error) -> String {
        if let care = error as? CareError, let key = care.errorDescription {
            return key
        }

        guard let code = cloudError(error)?.code else {
            return "care.error.cloud"
        }

        switch code {
        case .notAuthenticated:
            return "care.error.noAccount"
        case .accountTemporarilyUnavailable:
            return "care.error.accountUnavailable"
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return "care.error.cloud"
        case .badContainer, .missingEntitlement, .permissionFailure, .managedAccountRestricted:
            return "care.error.setup"
        case .serverRejectedRequest, .invalidArguments, .incompatibleVersion:
            return "care.error.schema"
        case .quotaExceeded:
            return "care.error.quota"
        default:
            return "care.error.unknown"
        }
    }

    /// "CKError 10 · <system text>", shown small under the message so a screenshot is enough to
    /// diagnose it.
    static func errorDetail(for error: Error) -> String? {
        guard let cloud = cloudError(error) else {
            return error is CareError ? nil : error.localizedDescription
        }

        return "CKError \(cloud.code.rawValue) · \(cloud.localizedDescription)"
    }

    /// The first real error inside a partial failure, which batch saves report.
    private static func cloudError(_ error: Error) -> CKError? {
        guard let error = error as? CKError else {
            return nil
        }

        if error.code == .partialFailure,
           let inner = error.partialErrorsByItemID?.values.first as? CKError {
            return inner
        }

        return error
    }

    static func log(_ error: Error, during step: String) {
        NSLog("CloudKit %@ failed: %@", step, String(describing: error))
    }

    // MARK: - Account

    /// Writing to the public database needs a signed-in iCloud account, but no free space in it.
    func requireAccount() async throws {
        guard try await container.accountStatus() == .available else {
            throw CareError.noAccount
        }
    }

    // MARK: - Doctor

    func publishOffer(_ offer: Offer, on channel: CareChannel) async throws {
        try await requireAccount()
        try await put(offer, as: Logical.offer, on: channel)
    }

    func reply(on channel: CareChannel) async throws -> Reply? {
        try await get(Reply.self, as: Logical.reply, on: channel)
    }

    /// Every version in one record, so the patient reads them in one request.
    func publishPrescriptions(_ versions: [Prescription], on channel: CareChannel) async throws {
        try await requireAccount()
        try await put(versions, as: Logical.prescriptions, on: channel)
    }

    /// The patient's results from the last twelve months, newest first.
    func results(on channel: CareChannel, now: Date = .now) async throws -> [SharedExerciseResult] {
        let months = Self.months(endingAt: now, count: Self.resultMonths)
        let chunks = try await getMany([SharedExerciseResult].self, as: months.map(Logical.results), on: channel)

        return chunks.flatMap { $0 }.sorted { $0.date > $1.date }
    }

    /// Ends the link from the doctor's side: the patient no longer receives a prescription.
    func removeDoctorRecords(on channel: CareChannel) async throws {
        try await delete([Logical.offer, Logical.prescriptions], on: channel)
    }

    // MARK: - Patient

    func offer(on channel: CareChannel) async throws -> Offer? {
        try await get(Offer.self, as: Logical.offer, on: channel)
    }

    func publishReply(on channel: CareChannel) async throws {
        try await requireAccount()
        try await put(Reply(acceptedAt: .now), as: Logical.reply, on: channel)
    }

    func prescriptions(on channel: CareChannel) async throws -> [Prescription] {
        try await get([Prescription].self, as: Logical.prescriptions, on: channel) ?? []
    }

    /// Adds results to their month's record, replacing any with the same id.
    func upload(_ results: [SharedExerciseResult], on channel: CareChannel) async throws {
        guard !results.isEmpty else {
            return
        }

        try await requireAccount()

        let byMonth = Dictionary(grouping: results) { Self.month(of: $0.date) }

        for (month, new) in byMonth {
            let logical = Logical.results(month)
            let existing = try await get([SharedExerciseResult].self, as: logical, on: channel) ?? []
            let ids = Set(new.map(\.id))
            try await put(existing.filter { !ids.contains($0.id) } + new, as: logical, on: channel)
        }
    }

    /// Ends the link from the patient's side: the reply and every sent result are deleted.
    func removePatientRecords(on channel: CareChannel, now: Date = .now) async throws {
        let months = Self.months(endingAt: now, count: 24).map(Logical.results)
        try await delete([Logical.reply] + months, on: channel)
    }

    // MARK: - Records

    private func recordID(_ logical: String, on channel: CareChannel) -> CKRecord.ID {
        CKRecord.ID(recordName: channel.recordName(logical))
    }

    /// Creates or replaces this account's record. Changing a record created by someone else is
    /// refused by the server.
    private func put<Value: Encodable>(_ value: Value, as logical: String, on channel: CareChannel) async throws {
        let id = recordID(logical, on: channel)
        let record = CKRecord(recordType: Self.recordType, recordID: id)
        record[Self.boxKey] = try channel.seal(value, as: logical)

        let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)

        if case .failure(let error) = result.saveResults[id] {
            throw error
        }
    }

    private func get<Value: Decodable>(_ type: Value.Type, as logical: String, on channel: CareChannel) async throws -> Value? {
        try await getMany(type, as: [logical], on: channel).first
    }

    /// Missing records are skipped; any other failure is thrown.
    private func getMany<Value: Decodable>(
        _ type: Value.Type,
        as logicals: [String],
        on channel: CareChannel
    ) async throws -> [Value] {
        let ids = logicals.map { recordID($0, on: channel) }
        let found = try await database.records(for: ids)
        var values: [Value] = []

        for (logical, id) in zip(logicals, ids) {
            switch found[id] {
            case .success(let record):
                guard let box = record[Self.boxKey] as? Data else {
                    throw CareError.malformedRecord
                }

                values.append(try channel.open(type, from: box, as: logical))
            case .failure(let error as CKError) where error.code == .unknownItem:
                continue
            case .failure(let error):
                throw error
            case nil:
                continue
            }
        }

        return values
    }

    private func delete(_ logicals: [String], on channel: CareChannel) async throws {
        let ids = logicals.map { recordID($0, on: channel) }
        let result = try await database.modifyRecords(saving: [], deleting: ids)

        for (_, outcome) in result.deleteResults {
            if case .failure(let error as CKError) = outcome, error.code != .unknownItem {
                throw error
            }
        }
    }

    // MARK: - Months

    private static func month(of date: Date) -> String {
        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    static func months(endingAt date: Date, count: Int) -> [String] {
        let calendar = Calendar(identifier: .gregorian)

        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: date).map(month(of:))
        }
    }
}
