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
        case .fullFist: return .juice
        case .hookFist: return .well
        case .opposition: return .garland
        case .spreading: return .bloom
        case .extensionSequence: return .chimes
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
        case .fullFist:
            return activity.returning ? "kampung.juice.release" : "kampung.juice.squeeze"
        case .hookFist:
            return activity.returning ? "kampung.well.release" : "kampung.well.pull"
        case .opposition:
            return activity.returning ? "kampung.garland.release" : "kampung.garland.pick"
        case .spreading:
            return activity.returning ? "kampung.bloom.close" : "kampung.bloom.open"
        case .extensionSequence:
            return activity.returning ? "kampung.chimes.relax" : "kampung.chimes.lift"
        }
    }

    var gardenCompletedSteps: Int {
        let stepsPerRepetition = activity.kind.isSequential ? 4 : 1
        let completedFingers = activity.kind.isSequential && activity.phase == .active ? activity.finger : 0
        return activity.totalRepetitions * stepsPerRepetition + completedFingers
    }
}
