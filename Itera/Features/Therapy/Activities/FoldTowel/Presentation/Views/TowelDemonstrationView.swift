//
//  TowelDemonstrationView.swift
//  Itera
//
//  Created by dimaswisodewo on 07/11/2026.
//

import SwiftUI

/// A looping demonstration of the real gesture: a hand pinches the handle, slides the towel to
/// the goal, then opens. It renders the same workspace the patient sees, driven by a scripted
/// snapshot, so the example and the exercise never drift apart.
struct TowelDemonstrationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(start))

            TowelWorkspaceView(
                snapshot: TowelDemoScript.snapshot(at: elapsed, staticPose: reduceMotion),
                showsHeader: false
            )
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
        }
    }
}

// MARK: - Script

/// The demonstration timeline. Each fold takes `foldDuration` seconds and the four folds repeat.
enum TowelDemoScript {
    static let foldDuration = 5.0

    static func snapshot(at elapsed: Double, staticPose: Bool) -> TowelSnapshot {
        let foldIndex = staticPose ? 0 : Int(elapsed / foldDuration) % TowelBoard.foldCount
        let time = staticPose ? 2.0 : elapsed.truncatingRemainder(dividingBy: foldDuration)
        let path = TowelFoldSequence.path(forFold: foldIndex)

        var snapshot = TowelSnapshot()
        snapshot.phase = .practice
        snapshot.foldIndex = foldIndex
        snapshot.grabPoint = path.grab
        snapshot.destination = path.destination

        switch time {
        case ..<0.8:
            // The hand drifts in from beside the handle, still open.
            let t = ease(time / 0.8)
            let offset = TherapyPoint(x: 0.12, y: 0.14).scaled(1 - t)
            snapshot.handPosition = path.grab + offset
            snapshot.grip = .open
            snapshot.interaction = .approach
        case ..<3.0:
            // Pinching on the handle grabs at once, then the towel follows the hand to the goal.
            let progress = ease((time - 0.8) / 2.2)
            snapshot.handPosition = lerp(path.grab, path.destination, progress)
            snapshot.grip = .closed
            snapshot.interaction = .folding
            snapshot.foldProgress = progress
        default:
            // Open at the goal to let go; the folded towel stays until the next fold begins.
            snapshot.handPosition = path.destination
            snapshot.grip = time < 3.9 ? .closed : .open
            snapshot.interaction = .readyToRelease
            snapshot.foldProgress = 1
        }

        return snapshot
    }

    private static func ease(_ value: Double) -> Double {
        let t = min(1, max(0, value))

        return t * t * (3 - 2 * t)
    }

    private static func lerp(_ a: TherapyPoint, _ b: TherapyPoint, _ t: Double) -> TherapyPoint {
        a + (b - a).scaled(t)
    }
}

#if DEBUG
#Preview("Towel demonstration") {
    TowelDemonstrationView()
        .frame(width: 420, height: 360)
        .background(TherapyPalette.exerciseBackdrop)
}
#endif
