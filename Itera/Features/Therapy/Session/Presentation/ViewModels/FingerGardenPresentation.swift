//
//  FingerGardenPresentation.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 03/11/2026.
//

import Foundation

/// Maps accepted exercise state to artwork. No game action can advance the exercise.
extension FingerSessionViewModel {
    var gardenStyle: GardenActivityStyle {
        switch activity.kind {
        case .fullFist: return .light
        case .hookFist: return .butterfly
        case .opposition: return .seeds
        case .spreading: return .petals
        case .extensionSequence: return .firefly
        }
    }

    var gardenAvailable: Bool {
        activity.phase == .active && trackingReady && !waitingForCamera && !paused
    }

    var gardenPose: Double {
        guard activity.phase == .active, !activity.needsStart else {
            return 0
        }
        return min(1, max(0, activity.movementFraction))
    }

    var gardenSecured: Bool {
        activity.phase == .active && !activity.needsStart &&
            (activity.returning || activity.holdCompletionID != nil)
    }

    var gardenFeedbackKey: String {
        if let cue = gardenInteractionCue {
            return cue
        }
        return gardenSecured ? "garden.secured" : liveFeedbackKey
    }

    var gardenInteractionCue: String? {
        guard activity.phase == .active, !activity.needsStart else {
            return nil
        }
        switch activity.kind {
        case .hookFist:
            return activity.returning ? "garden.butterfly.open" : "garden.butterfly.curl"
        case .opposition:
            return activity.returning ? "garden.seed.release" : "garden.seed.pick"
        case .fullFist, .spreading, .extensionSequence:
            return nil
        }
    }

    var gardenCompletedSteps: Int {
        let stepsPerRepetition = activity.kind.isSequential ? 4 : 1
        let completedFingers = activity.kind.isSequential && activity.phase == .active ? activity.finger : 0
        return activity.totalRepetitions * stepsPerRepetition + completedFingers
    }
}
