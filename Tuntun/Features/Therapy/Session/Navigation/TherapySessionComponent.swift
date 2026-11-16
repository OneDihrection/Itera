//
//  TherapySessionComponent.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation

/// What the guided, Balancing and finger session pages need from their parent.
@MainActor
protocol TherapySessionDependency {
    var tracking: BodyTrackingService { get }
    var audio: SessionAudioService { get }
    var sessions: any SessionRepository { get }
    var permissions: PermissionManager { get }
    var fingers: FingerHomeViewModel { get }
    var fingerSessions: FingerSessionLauncher { get }
    /// Sessions report their finishing action to today's plan.
    var dailyPlan: DailyPlanViewModel { get }
    var sessionRouter: any SessionRouterProtocol { get }
    var tabRouter: any TabRouterProtocol { get }
}

@MainActor
final class TherapySessionComponent: Component<TherapySessionDependency> {
    let tracking: BodyTrackingService
    let audio: SessionAudioService
    let sessions: any SessionRepository
    let permissions: PermissionManager
    let fingers: FingerHomeViewModel
    let fingerSessions: FingerSessionLauncher
    let dailyPlan: DailyPlanViewModel
    let sessionRouter: any SessionRouterProtocol
    let tabRouter: any TabRouterProtocol

    init(dependency: TherapySessionDependency) {
        self.tracking = dependency.tracking
        self.audio = dependency.audio
        self.sessions = dependency.sessions
        self.permissions = dependency.permissions
        self.fingers = dependency.fingers
        self.fingerSessions = dependency.fingerSessions
        self.dailyPlan = dependency.dailyPlan
        self.sessionRouter = dependency.sessionRouter
        self.tabRouter = dependency.tabRouter
        super.init(with: dependency)
    }
}
