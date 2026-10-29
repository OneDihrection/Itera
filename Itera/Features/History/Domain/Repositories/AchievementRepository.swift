//
//  AchievementRepository.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import Foundation

protocol AchievementRepository: Sendable {
    func merge(_ candidates: [AchievementAward]) async throws -> [AchievementAward]
    func acknowledge(_ ids: Set<String>) async throws -> [AchievementAward]
}
