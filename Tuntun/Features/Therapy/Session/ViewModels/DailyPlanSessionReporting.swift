//
//  DailyPlanSessionReporting.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation

/// What a session page reads from, and reports to, today's plan while the plan runs it.
/// `DailyPlanViewModel` conforms; sessions never depend on the plan's concrete type.
@MainActor
protocol DailyPlanSessionReporting: AnyObject {
    var isRunning: Bool { get }
    /// The running item's position in today's plan.
    var currentNumber: Int? { get }
    var hasAutomaticRest: Bool { get }

    /// Called by a session's finishing action. Only a session that reached its goal counts.
    func finish(completed: Bool)
    /// Leaving before a session could start ends the run.
    func end()
    func markFingerScriptRest(_ side: HandSide?)
    func markArmRaiseRest(_ side: TherapySide?)
    /// A Balancing session that a 2026-11-23 script narrated finished; the long rest follows suit.
    func markBalanceScriptRest(_ scripted: Bool)
}

enum DailyPlanTiming {
    /// How long a finished session's summary stays visible before a running plan moves on.
    static let completionPreview: Duration = .seconds(4)
}
