//
//  DebugScreenLauncher.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

#if DEBUG
import SwiftUI

/// Debug-only launch argument for checking screens on the Simulator without touch:
///
///     -IteraScreen intro:<plan item id>     opens that plan item's intro through the plan
///     -IteraScreen gallery:<screen>         shows live, pause, setDone or allDone with sample values
///
/// Release builds never compile this file.
enum DebugScreenLauncher {
    static var argument: String? {
        let arguments = ProcessInfo.processInfo.arguments

        guard let index = arguments.firstIndex(of: "-IteraScreen"),
              arguments.indices.contains(index + 1) else {
            return nil
        }

        return arguments[index + 1]
    }

    static var galleryScreen: String? {
        guard let argument, argument.hasPrefix("gallery:") else {
            return nil
        }

        return String(argument.dropFirst("gallery:".count))
    }

    @MainActor
    static func openIntroIfRequested(dependencies: AppDependencies, router: NavigationRouter) {
        guard let argument, argument.hasPrefix("intro:") else {
            return
        }

        dependencies.dailyPlan.begin(from: String(argument.dropFirst("intro:".count)), router: router)
    }
}

/// The shared exercise screens filled with sample values from the design.
struct TMDebugScreenGallery: View {
    let screen: String

    private let results = [
        TherapySetResult(number: 1, done: 8, goal: 8, state: .done),
        TherapySetResult(number: 2, done: 8, goal: 8, state: .done),
        TherapySetResult(number: 3, done: 0, goal: 8, state: .upcoming),
    ]

    var body: some View {
        switch screen {
        case "pause":
            ZStack {
                live
                TMTherapyPauseDialog(
                    setLabel: Text("session.setNumber \(2)"),
                    title: Text("balance.title"),
                    elapsedSeconds: 173,
                    onEnd: {},
                    onResume: {}
                ) {
                    EmptyView()
                }
            }
        case "setDone":
            TMTherapySetSummary(
                heading: heading,
                headline: Text("session.setDone \(2)"),
                message: Text("session.setRest \(3)"),
                results: results,
                total: Text("session.totalOf \(16) \(24)"),
                footer: Text("session.nextSetIn \(3) \(12)")
            ) {
                EmptyView()
            }
        case "allDone":
            TMTherapySetSummary(
                heading: heading,
                headline: Text("session.allDoneTitle"),
                message: Text("session.allDoneMessage"),
                results: results.map { TherapySetResult(number: $0.number, done: 8, goal: 8, state: .done) },
                total: Text("session.total \(24)")
            ) {
                TMTherapyButton(title: "plan.nextContinue", symbol: "play.fill", prominent: true) {}
            }
        default:
            live
        }
    }

    private var heading: TMTherapyExerciseHeading {
        TMTherapyExerciseHeading(eyebrow: Text("plan.exerciseNumber \(1)"), title: Text("balance.title"))
    }

    private var live: some View {
        TMTherapyExerciseLiveLayout(
            heading: heading,
            cue: Text("plan.purpose.crossMidline"),
            demoTitle: "session.followMovement",
            repetitions: (3, 8),
            sets: (1, 3),
            pauseTitle: "session.pauseAction",
            endTitle: "session.endAction",
            onPause: {},
            onEnd: {}
        ) {
            Color.gray.opacity(0.4)
        } demo: {
            TMBalanceExerciseDemonstrationView(exercise: .crossMidline, paused: false)
        } accessories: {
            EmptyView()
        }
    }
}
#endif
