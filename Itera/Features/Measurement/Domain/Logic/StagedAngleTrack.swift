//
//  StagedAngleTrack.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import Foundation

/// When an angle was held during an exercise.
enum AngleStage {
    /// Calibration of the start and target positions, before the first repetition.
    case before
    /// Counted practice, through the last set.
    case after
}

/// One angle's held ranges before and during practice. Shared by finger and body exercises.
///
/// Only held readings count (`AngleHoldEstimator`), so moving between poses never sets a range.
/// It keeps two ranges, never a stream of samples.
struct StagedAngleTrack {
    private var estimator = AngleHoldEstimator()
    private var stage: AngleStage?
    private(set) var before: AngleRange?
    private(set) var after: AngleRange?
    /// True while every held reading came from metric 3D joints.
    private(set) var threeD = true
    private(set) var heldAny = false

    init(before: AngleRange? = nil, after: AngleRange? = nil, threeD: Bool = true) {
        self.before = before
        self.after = after
        self.threeD = threeD
        heldAny = before != nil || after != nil
    }

    /// - Parameter sample: this frame's angle, or nil when its joints are not usable.
    mutating func consume(_ sample: AngleSample?, stage: AngleStage) {
        if self.stage != stage {
            // A new stage starts a new hold so calibration and practice never mix.
            estimator.reset()
            self.stage = stage
        }

        guard let sample else {
            estimator.missing()
            return
        }

        estimator.consume(sample)

        guard let held = estimator.held else {
            return
        }

        let range = AngleRange(minimum: held, maximum: held)

        switch stage {
        case .before:
            before = range.including(before)
        case .after:
            after = range.including(after)
        }

        threeD = threeD && sample.source == .world3D
        heldAny = true
    }

    /// Lost evidence, a pause or a stage that is not measured ends the current hold.
    mutating func interrupt() {
        estimator.missing()
    }
}
