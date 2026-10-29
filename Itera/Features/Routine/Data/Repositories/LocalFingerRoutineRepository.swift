//
//  LocalFingerRoutineRepository.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

actor LocalFingerRoutineRepository: FingerRoutineRepository {
    private let url = URL.applicationSupportDirectory.appendingPathComponent("finger-routine.json")

    private struct Record: Codable {
        let version: Int
        let side: String
        let sets: Int
        let repetitions: Int
        let restSeconds: Int
        let voiceControl: Bool
        let ambientSound: Bool
    }

    func load() throws -> FingerRoutine? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let record = try AtomicJSONFiles.read(Record.self, from: url)
        guard record.version == 1, let side = TrainingSide(rawValue: record.side),
              (1...5).contains(record.sets), (1...20).contains(record.repetitions),
              (5...120).contains(record.restSeconds) else { throw StorageError.invalid }
        var routine = FingerRoutine()
        routine.side = side
        routine.sets = record.sets
        routine.repetitions = record.repetitions
        routine.restSeconds = record.restSeconds
        routine.voiceControl = record.voiceControl
        routine.ambientSound = record.ambientSound
        return routine
    }

    func save(_ routine: FingerRoutine) throws {
        // Never overwrite an unreadable or unsupported saved plan.
        _ = try load()
        let record = Record(version: 1, side: routine.side.rawValue, sets: routine.sets,
                            repetitions: routine.repetitions, restSeconds: routine.restSeconds,
                            voiceControl: routine.voiceControl, ambientSound: routine.ambientSound)
        try AtomicJSONFiles.write(record, to: url)
    }

    private enum StorageError: Error { case invalid }
}
