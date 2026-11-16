//
//  LocalRoutineRepository.swift
//  Tuntun
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Foundation

actor LocalRoutineRepository: RoutineRepository {
    private struct Record: Codable {
        let version: Int
        let routine: RoutineConfiguration
    }
    private let storage = AtomicFileStorage()
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func load() throws -> RoutineConfiguration? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let record = try storage.read(Record.self, from: url)
        guard record.version == 1 else {
            throw CocoaError(.coderReadCorrupt)
        }
        return record.routine
    }
}
