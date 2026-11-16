//
//  HistoryRecoveryService.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation
import Observation

/// What readiness needs from interrupted-session recovery.
@MainActor
protocol HistoryRecoveryServiceProtocol: AnyObject {
    var recovering: Bool { get }
    var recoveryFailure: String? { get }
    func recoverHistory() async
}

/// Finalizes a session interrupted by termination, once per launch, before therapy starts.
@MainActor
@Observable
final class HistoryRecoveryService: HistoryRecoveryServiceProtocol {
    private(set) var recoveryFailure: String?
    private(set) var recovering = true

    @ObservationIgnored private let sessions: any SessionRepository
    @ObservationIgnored private var didRecover = false

    init(sessions: any SessionRepository) {
        self.sessions = sessions
    }

    func recoverHistory() async {
        guard !didRecover else {
            return
        }

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
}
