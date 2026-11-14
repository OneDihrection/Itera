//
//  FingerAngleRecorder.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import Foundation

/// Records one finger exercise's held angles from calibration to the end of practice.
struct FingerAngleRecorder {
    typealias Stage = AngleStage

    let metrics: [FingerAngleMetric]
    private var tracks: [StagedAngleTrack]

    /// - Parameter prior: ranges already recorded for this exercise in a session resumed later;
    ///   new readings widen them.
    init(exercise: FingerExercise, prior: [FingerAngleResult] = []) {
        metrics = FingerAngleMetric.metrics(for: exercise)
        tracks = metrics.map { metric in
            guard let result = prior.first(where: { $0.metric == metric }) else {
                return StagedAngleTrack()
            }

            return StagedAngleTrack(before: result.before, after: result.after, threeD: result.threeD)
        }
    }

    mutating func observe(_ hand: HandEvidence, stage: Stage) {
        for index in tracks.indices {
            tracks[index].consume(Self.sample(metrics[index], in: hand), stage: stage)
        }
    }

    mutating func interrupt() {
        for index in tracks.indices {
            tracks[index].interrupt()
        }
    }

    var results: [FingerAngleResult] {
        zip(metrics, tracks).compactMap { metric, track in
            guard track.heldAny else {
                return nil
            }

            return FingerAngleResult(metric: metric, before: track.before, after: track.after, threeD: track.threeD)
        }
    }

    /// The mean of a metric's parts, or nil unless every part is measurable this frame.
    static func sample(_ metric: FingerAngleMetric, in hand: HandEvidence) -> AngleSample? {
        let parts = metric.parts.compactMap { JointAngleCalculator.sample($0, in: hand) }

        guard parts.count == metric.parts.count, let first = parts.first else {
            return nil
        }

        let mean = parts.reduce(0) { $0 + $1.degrees } / Double(parts.count)
        let threeD = parts.allSatisfy { $0.source == .world3D }

        return AngleSample(
            degrees: mean,
            source: threeD ? .world3D : .image2D,
            timestamp: first.timestamp,
            points: first.points
        )
    }
}
