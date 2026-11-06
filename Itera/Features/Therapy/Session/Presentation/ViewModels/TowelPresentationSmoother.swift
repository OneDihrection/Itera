//
//  TowelPresentationSmoother.swift
//  Itera
//
//  Created by dimaswisodewo on 05/11/2026.
//

import Foundation

/// Selects short, interruptible display interpolation. Evidence remains authoritative;
/// SwiftUI interpolates only the cursor position and panel progress at the rendering leaves.
struct TowelPresentationSmoother {
    private var previous: TowelSnapshot?
    private var lastTime: Double?
    private var generation: UUID?
    private(set) var interpolates = false

    mutating func reset() {
        self = TowelPresentationSmoother()
    }

    mutating func consume(_ raw: TowelSnapshot, time: Double, generation: UUID) -> TowelSnapshot {
        interpolates = false
        if let previous, let lastTime {
            // The cursor eases between consecutive fresh frames of the same grab. Authoritative
            // resets (a new fold or repetition, lost or recovering evidence, a cancelled fold)
            // snap instead.
            interpolates = self.generation == generation
                && time > lastTime && time - lastTime <= 0.15
                && previous.phase == raw.phase && raw.phase == .practice
                && previous.foldIndex == raw.foldIndex && previous.count == raw.count
                && previous.grabID == raw.grabID
                && raw.interaction != .recovering && previous.interaction != .recovering
                && raw.trackingMessage == nil && previous.trackingMessage == nil
                && raw.handPosition != nil && previous.handPosition != nil
                && !(raw.foldProgress == 0 && previous.foldProgress > 0)
        }
        previous = raw
        lastTime = time
        self.generation = generation
        return raw
    }
}
