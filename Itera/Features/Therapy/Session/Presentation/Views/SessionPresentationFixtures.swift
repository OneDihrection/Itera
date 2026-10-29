//
//  SessionPresentationFixtures.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

#if DEBUG
import SwiftUI

/// Detached presentation snapshots. No route, permission grant, capture, audio, or persistence.
/// Select a preview, language, text size, and landscape dimensions in Xcode's canvas.
enum SessionPresentationFixtures {
    struct Fixture: Identifiable {
        let id: String
        let snapshot: SessionSnapshot
    }

    static var all: [Fixture] {
        var fixtures: [Fixture] = []
        for kind in TherapyKind.allCases {
            for side in [TherapySide.left, .right] {
                let activity = SessionActivity(kind: kind, side: side, goal: 5)
                let plans = kind == .armRaise || kind == .elbowBend
                    ? [SessionGuidance.opening(activity, includePositioning: true)]
                    : [SessionGuidance.opening(activity, includePositioning: false)]
                for (index, card) in plans.flatMap(\.cards).enumerated() {
                    var value = base(activity)
                    value.stage = card.demonstration ? .demonstration : .instruction
                    value.instruction = card.key
                    fixtures.append(Fixture(id: "\(kind.rawValue)-\(side.rawValue)-card-\(index)", snapshot: value))
                }
            }
        }
        let movement = SessionActivity(kind: .armRaise, side: .left, goal: 5)
        for phase in [MovementPhase.startCapture, .targetCapture, .returnToStart, .countdown, .practice] {
            for progress in [0.0, 0.5, 1.0] {
                var value = base(movement)
                var state = MovementSnapshot()
                state.phase = phase
                state.progress = progress
                state.seconds = 3
                state.guide = guide(progress: progress, capturing: phase == .startCapture || phase == .targetCapture)
                state.pose = phase == .targetCapture ? .peak : (phase == .practice ? .looping : .start)
                state.instruction = phase == .practice ? "session.moveTarget" : "session.holdStart"
                value.presentation = .movement(state)
                value.instruction = state.instruction
                fixtures.append(Fixture(id: "movement-\(phase)-\(progress)", snapshot: value))
            }
        }
        var movementLoss = base(movement)
        var lostMovementState = MovementSnapshot()
        lostMovementState.phase = .returnToStart
        lostMovementState.trackingMessage = "session.movementTrackingLost"
        movementLoss.presentation = .movement(lostMovementState)
        movementLoss.instruction = lostMovementState.instruction
        fixtures.append(Fixture(id: "movement-tracking-loss", snapshot: movementLoss))

        let directions = ["right", "left", "up"]
        for direction in 0..<directions.count {
            for phase in [ReachPhase.setup, .assessment, .countdown, .rehearsal, .practice, .finished] {
                var value = base(SessionActivity(kind: .directionalReach, side: .left, goal: 3))
                var state = ReachSnapshot()
                state.phase = phase
                state.seconds = 3
                state.direction = direction
                state.count = phase == .practice || phase == .finished ? 1 : 0
                state.round = state.count + 1
                state.step = phase == .assessment ? 1 : 3
                state.rehearsal = phase == .rehearsal
                state.instruction = "session.reach\(directions[direction].capitalized)"
                var target = guide(progress: 0.5)
                target.directionOnly = phase == .assessment
                target.farthest = TherapyPoint(x: 0.8, y: 0.6)
                state.guide = target
                value.presentation = .reach(state)
                value.instruction = state.instruction
                fixtures.append(Fixture(id: "reach-\(directions[direction])-\(phase)", snapshot: value))
            }
        }
        var reachLoss = base(SessionActivity(kind: .directionalReach, side: .left, goal: 3))
        var lostReachState = ReachSnapshot()
        lostReachState.phase = .practice
        lostReachState.count = 1
        lostReachState.round = 2
        lostReachState.direction = 1
        lostReachState.trackingMessage = "session.reachTrackingLost"
        lostReachState.caregiverSkippedSteps = [
            ReachSkippedStep(round: 1, direction: 0, phase: .practice)
        ]
        lostReachState.guide = guide(progress: 0.1)
        reachLoss.presentation = .reach(lostReachState)
        reachLoss.instruction = lostReachState.instruction
        fixtures.append(Fixture(id: "reach-tracking-loss-and-skipped-step", snapshot: reachLoss))

        for phase in [CupPhase.rehearsal, .countdown, .practice, .finished] {
            for step in [CupStep.start, .nearFace, .handReturn, .transfer, .cupReturn] {
                var value = base(SessionActivity(kind: .cup, side: .left, goal: 1))
                var state = CupSnapshot()
                state.phase = phase
                state.step = step
                state.guide = guide(progress: 0.5, capturing: phase == .rehearsal)
                value.presentation = .cup(state)
                value.instruction = ["cup.start", "cup.nearFace", "cup.handReturn", "cup.transfer", "cup.cupReturn"][step.rawValue]
                fixtures.append(Fixture(id: "cup-\(phase)-\(step)", snapshot: value))
            }
        }
        var cupEvidenceLoss = base(SessionActivity(kind: .cup, side: .left, goal: 3))
        var lostCupState = CupSnapshot()
        lostCupState.phase = .practice
        lostCupState.step = .transfer
        lostCupState.count = 1
        lostCupState.evidenceMessage = "cup.evidenceMissing"
        lostCupState.guide = guide(progress: 0.25)
        cupEvidenceLoss.presentation = .cup(lostCupState)
        cupEvidenceLoss.instruction = lostCupState.instruction
        fixtures.append(Fixture(id: "cup-evidence-loss", snapshot: cupEvidenceLoss))

        for stage in [SessionSnapshot.Stage.preparationWait, .feedback, .rest, .preparing, .summary] {
            var value = base(movement)
            value.stage = stage
            value.seconds = 5
            value.instruction = stage == .rest ? "session.rest" : "session.feedback"
            value.cameraWaiting = stage == .preparing
            if stage == .summary {
                value.summary = SessionSummary(id: UUID(), routine: .demo(), startedAt: Date(), endedAt: Date(), stopped: false, results: [])
            }
            fixtures.append(Fixture(id: "session-\(stage)", snapshot: value))
        }
        for kind in TherapyKind.allCases {
            var paused = base(SessionActivity(kind: kind, side: .left, goal: 3))
            paused.paused = true
            paused.assistanceKey = assistanceKey(for: kind)
            fixtures.append(Fixture(id: "paused-recovery-\(kind)", snapshot: paused))
        }
        fixtures.append(Fixture(id: "camera-wait", snapshot: cameraWait(movement)))
        fixtures.append(Fixture(id: "summary-stopped-partial", snapshot: summary(stopped: true)))
        fixtures.append(Fixture(id: "summary-interrupted", snapshot: summary(interrupted: true)))
        fixtures.append(Fixture(id: "summary-completed", snapshot: summary(stopped: false)))
        return fixtures
    }

    private static func assistanceKey(for kind: TherapyKind) -> String {
        switch kind {
        case .armRaise: return "session.assistance.armRaise"
        case .elbowBend: return "session.assistance.elbowBend"
        case .directionalReach: return "session.assistance.reach"
        case .cup: return "session.assistance.cup"
        }
    }

    private static func cameraWait(_ activity: SessionActivity) -> SessionSnapshot {
        var value = base(activity)
        value.stage = .preparing
        value.cameraWaiting = true
        value.instruction = "session.cameraWait"
        return value
    }

    private static func summary(stopped: Bool = false, interrupted: Bool = false) -> SessionSnapshot {
        let now = Date()
        let reach = SessionActivity(kind: .directionalReach, side: .left, goal: 3)
        let cup = SessionActivity(kind: .cup, side: .right, goal: 3)
        let reachResult = SessionActivityResult(
            executionID: UUID(),
            activity: reach,
            outcome: .completed,
            completedWork: 2,
            reachOutcomes: [
                ReachOutcome(direction: 0, evidence: .reached),
                ReachOutcome(direction: 1, evidence: .notReached),
            ],
            skippedReachSteps: [ReachSkippedStep(round: 3, direction: 2, phase: .practice)]
        )
        let cupResult = SessionActivityResult(
            executionID: UUID(),
            activity: cup,
            outcome: stopped ? .interrupted : .completed,
            completedWork: 1,
            cupOutcomes: [CupMilestone(round: 1, step: CupStep.start.rawValue)]
        )
        var value = base(reach)
        value.stage = .summary
        value.summary = SessionSummary(
            id: UUID(),
            routine: .demo(),
            startedAt: now.addingTimeInterval(-120),
            endedAt: now,
            stopped: stopped,
            interrupted: interrupted,
            results: stopped ? [reachResult, cupResult] : [reachResult]
        )
        return value
    }

    private static func base(_ activity: SessionActivity) -> SessionSnapshot {
        var value = SessionSnapshot()
        value.stage = .activity
        value.activity = activity
        value.activityCount = 6
        value.cameraWaiting = false
        value.guidanceID = UUID()
        return value
    }

    private static func guide(progress: Double, capturing: Bool = false) -> TargetGuide {
        TargetGuide(
            start: TherapyPoint(x: 0.5, y: 0.3),
            target: TherapyPoint(x: 0.9, y: 0.6),
            tracked: TherapyPoint(x: 0.88, y: 0.59),
            radius: 0.08,
            targetActive: true,
            progress: progress,
            aspect: 4 / 3,
            capturing: capturing,
            savedStart: true
        )
    }
}

struct SessionPresentationFixturePreviews: PreviewProvider {
    static var previews: some View {
        ForEach(SessionPresentationFixtures.all) { fixture in
            TherapySessionView(fixture: fixture.snapshot)
                .environment(PermissionManager())
                .environment(NavigationRouter())
                .preferredColorScheme(.dark)
                .previewLayout(.fixed(width: 1366, height: 1024))
                .previewDisplayName(fixture.id)
        }
    }
}
#endif
