//
//  LocalPrescriptionRepositories.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import Foundation

/// Versioned local files for the doctor's patients and the patient's link. Like every local
/// repository, an unreadable or unsupported file is never overwritten.
private struct VersionedRecord<Value: Codable>: Codable {
    let version: Int
    let value: Value
}

private enum LocalRecordError: Error {
    case unsupported
}

private func readRecord<Value: Codable>(_ type: Value.Type, at url: URL) throws -> Value? {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return nil
    }

    let record = try AtomicJSONFiles.read(VersionedRecord<Value>.self, from: url)

    guard record.version == 1 else {
        throw LocalRecordError.unsupported
    }

    return record.value
}

actor LocalDoctorPatientRepository: DoctorPatientRepository {
    private let url: URL

    init(url: URL = URL.applicationSupportDirectory.appendingPathComponent("doctor-patients.json")) {
        self.url = url
    }

    func load() throws -> [DoctorPatient] {
        try readRecord([DoctorPatient].self, at: url) ?? []
    }

    func save(_ patients: [DoctorPatient]) throws {
        _ = try load()
        try AtomicJSONFiles.write(VersionedRecord(version: 1, value: patients), to: url)
    }
}

actor LocalPatientCareLinkRepository: PatientCareLinkRepository {
    private let url: URL

    init(url: URL = URL.applicationSupportDirectory.appendingPathComponent("patient-care-link.json")) {
        self.url = url
    }

    func load() throws -> PatientCareLink? {
        try readRecord(PatientCareLink?.self, at: url) ?? nil
    }

    func save(_ link: PatientCareLink?) throws {
        _ = try load()
        try AtomicJSONFiles.write(VersionedRecord(version: 1, value: link), to: url)
    }
}
