//
//  LocalAchievementRepository.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

actor LocalAchievementRepository: AchievementRepository {
    private let url: URL

    init(url: URL = URL.applicationSupportDirectory.appendingPathComponent("practice-achievements.json")) {
        self.url = url
    }

    func merge(_ candidates: [AchievementAward]) throws -> [AchievementAward] {
        var awards = try read()
        var existing = Set(awards.map(\.id))
        let additions = candidates.filter { existing.insert($0.id).inserted }
        if !additions.isEmpty {
            awards += additions
            try save(awards)
        }
        return awards
    }

    func acknowledge(_ ids: Set<String>) throws -> [AchievementAward] {
        var awards = try read()
        for index in awards.indices where ids.contains(awards[index].id) {
            awards[index].acknowledged = true
        }
        try save(awards)
        return awards
    }

    private func read() throws -> [AchievementAward] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let record = try AtomicJSONFiles.read(Ledger.self, from: url)
        let known = Set(PracticeAchievement.catalog.map(\.id))
        guard record.version == 1,
              Set(record.awards.map(\.id)).count == record.awards.count,
              record.awards.allSatisfy({ known.contains($0.id) && $0.earned.timeIntervalSince1970.isFinite }) else {
            throw LedgerError.invalid
        }
        return record.awards.map { AchievementAward(id: $0.id, earned: $0.earned, acknowledged: $0.acknowledged) }
    }

    private func save(_ awards: [AchievementAward]) throws {
        let record = Ledger(version: 1, awards: awards.map {
            AwardRecord(id: $0.id, earned: $0.earned, acknowledged: $0.acknowledged)
        })
        try AtomicJSONFiles.write(record, to: url)
    }

    private struct Ledger: Codable {
        let version: Int
        let awards: [AwardRecord]
    }

    private struct AwardRecord: Codable {
        let id: String
        let earned: Date
        let acknowledged: Bool
    }

    private enum LedgerError: Error { case invalid }
}
