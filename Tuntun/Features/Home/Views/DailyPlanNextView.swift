//
//  DailyPlanNextView.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

import Combine
import SwiftUI

/// The rest and countdown between exercises, or the page after the last exercise.
struct TMDailyPlanNextView<
    ViewModel: DailyPlanNextViewModelProtocol,
    Builder: DailyPlanNextContentBuildable
>: View {
    @State private var viewModel: ViewModel
    /// Builds the next exercise's intro shown after the rest, with its own dependencies.
    private let builder: Builder

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum Stage: Equatable {
        case opening, restInvitation, instructions, posture, firstBreathCount, breathing
        case closing, nextExercise, exerciseName
        case countdownIntro, countdown
    }

    @State private var stage = Stage.opening
    @State private var elapsed = 0.0
    @State private var audioPrepared = false
    @State private var narrationID: UUID?
    @State private var narrationFinished = false
    @State private var paused = false

    private static var countdownDuration: Double { 10.0 }

    private var showingNextIntro: Bool {
        stage == .countdownIntro || stage == .countdown
    }

    private var usesNextScript: Bool {
        viewModel.usesNextScript
    }

    private var countdownSeconds: Int {
        let countdownElapsed = stage == .countdown ? elapsed : 0
        return max(1, Int(ceil(Self.countdownDuration - countdownElapsed)))
    }

    private func remainingBreaths(afterStarting breath: LongRestBreath) -> Int {
        LongRestBreath.count - breath.number + 1
    }

    init(viewModel: ViewModel, builder: Builder) {
        _viewModel = State(initialValue: viewModel)
        self.builder = builder
    }

    var body: some View {
        Group {
            if let itemID = viewModel.nextSessionItemID {
                transitionPage(itemID: itemID)
            } else {
                completionPage
            }
        }
        .interactiveDismissDisabled()
    }

    private func transitionPage(itemID: String) -> some View {
        ZStack {
            if showingNextIntro {
                builder.buildDailyPlanIntro(
                    itemID: itemID,
                    countdownSeconds: usesNextScript ? nil : countdownSeconds,
                    automatic: usesNextScript
                )
                    .environment(\.colorScheme, .light)
                    .transition(.opacity)
            } else {
                let breath = stage == .breathing ? LongRestBreath(elapsed: elapsed) : nil
                let cue = text(for: restLine(breath: breath))
                TMTherapyLongRest(
                    cue: Text(verbatim: cue),
                    cueID: cue,
                    counter: breath.map { Text("rest.long.remaining \(remainingBreaths(afterStarting: $0))") },
                    intensity: breath?.intensity ?? 0.25,
                    paused: paused,
                    togglePause: { paused.toggle() },
                    stop: stop
                )
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: showingNextIntro)
        .onReceive(viewModel.audioEvents) { event in
            if case .completed(let id, _) = event, id == narrationID {
                narrationFinished = true
            }
        }
        .task(id: paused || scenePhase != .active) {
            if paused || scenePhase != .active {
                viewModel.pauseMusic()
                viewModel.cancelSpeech()
            } else {
                await runTransition()
            }
        }
    }

    private func runTransition() async {
        if !audioPrepared {
            // Let the previous exercise release its shared camera and audio.
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            viewModel.prepareRestNarration()
            audioPrepared = true
        }

        if !showingNextIntro {
            viewModel.startMusic()
        }

        var startedAt = ProcessInfo.processInfo.systemUptime - elapsed
        var lastCueID: String?
        var lastSpokenSecond: Int?
        while !Task.isCancelled, !paused, scenePhase == .active {
            if stage == .countdownIntro, usesNextScript {
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            let proposedElapsed = now - startedAt
            if stage == .breathing, viewModel.usesScriptedLongRest,
               !narrationFinished {
                let boundary = LongRestBreath.narrationBoundary(at: elapsed)
                elapsed = min(proposedElapsed, boundary.nextDown)
                startedAt = now - elapsed
            } else {
                elapsed = proposedElapsed
            }

            if stage == .countdown, elapsed >= Self.countdownDuration {
                viewModel.cancelSpeech()
                viewModel.launchAfterRest()
                return
            }

            if stage == .countdown {
                let seconds = countdownSeconds
                if seconds != lastSpokenSecond {
                    viewModel.playCountdown(seconds)
                    lastSpokenSecond = seconds
                }
            } else {
                let breath = stage == .breathing ? LongRestBreath(elapsed: elapsed) : nil
                let line = restLine(breath: breath)
                let cue = text(for: line)
                let cueID = breath.map { "\($0.number)-\($0.phase)-\(cue)" } ?? cue
                if lastCueID != cueID {
                    speak(line, breath: breath)
                    lastCueID = cueID
                }
            }

            if let next = nextStage {
                if next == .countdownIntro {
                    viewModel.stopMusic()
                }
                stage = next
                elapsed = 0
                startedAt = now
                lastCueID = nil
                continue
            }

            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }
        }
    }

    private var nextStage: Stage? {
        if stage == .breathing {
            return elapsed >= LongRestBreath.duration ? .closing : nil
        }
        guard (elapsed >= 2 && narrationFinished) || elapsed >= 12 else {
            return nil
        }
        switch stage {
        case .opening: return .restInvitation
        case .restInvitation: return .instructions
        case .instructions: return .posture
        case .posture:
            return viewModel.usesScriptedLongRest ? .breathing : .firstBreathCount
        case .firstBreathCount: return .breathing
        case .closing: return .nextExercise
        case .nextExercise: return .exerciseName
        case .exerciseName: return .countdownIntro
        case .countdownIntro: return .countdown
        case .breathing, .countdown: return nil
        }
    }

    /// The catalog line for the current stage. Each line is spoken by its key, so the recorded
    /// Marizka clip plays (the system voice is only the fallback), and shown as its text.
    private func restLine(breath: LongRestBreath?) -> NarrationLine? {
        guard let line = baseRestLine(breath: breath) else {
            return nil
        }
        guard let prefix = viewModel.longRestNarrationPrefix,
              line.key.hasPrefix("rest.long.") else {
            return line
        }
        return NarrationLine(
            key: prefix + line.key.dropFirst("rest.long.".count),
            argument: line.argument
        )
    }

    private func baseRestLine(breath: LongRestBreath?) -> NarrationLine? {
        switch stage {
        case .opening:
            return NarrationLine(key: "rest.long.opening")
        case .restInvitation:
            return NarrationLine(key: "rest.long.restInvitation")
        case .instructions:
            return NarrationLine(key: "rest.long.instructions")
        case .posture:
            return NarrationLine(key: "rest.long.posture")
        case .firstBreathCount:
            return NarrationLine(key: Self.remainingKey, argument: LongRestBreath.count)
        case .closing:
            return NarrationLine(key: "rest.long.closing")
        case .nextExercise:
            return NarrationLine(key: "rest.long.nextExercise")
        case .exerciseName:
            return viewModel.nextSessionTitleKey.map { NarrationLine(key: $0) }
        case .countdownIntro, .countdown:
            return NarrationLine(key: "calibration.countdown")
        case .breathing:
            guard let breath else {
                return nil
            }

            let key = breathingKey(for: breath)
            return key.isEmpty ? nil : NarrationLine(key: key)
        }
    }

    private func breathingKey(for breath: LongRestBreath) -> String {
        switch breath.phase {
        case .inhale:
            switch breath.number {
            case 1:
                return viewModel.usesScriptedLongRest ? "rest.long.inhale" : "rest.long.inhaleFirst"
            case LongRestBreath.count:
                let lastBreathStart = Double(LongRestBreath.count - 1) * LongRestBreath.cycleDuration
                return elapsed - lastBreathStart < 1.4 ? "rest.long.inhaleLast" : "rest.long.inhale"
            default:
                return "rest.long.inhale"
            }
        case .hold:
            // The approved long-rest script has no spoken hold between inhale and exhale.
            return viewModel.usesScriptedLongRest ? "" : "rest.long.hold"
        case .exhale:
            switch breath.number {
            case 1:
                return viewModel.usesScriptedLongRest ? "rest.long.exhale" : "rest.long.exhaleSlow"
            case 5:
                return "rest.long.exhaleSlow"
            case 3:
                return "rest.long.exhaleShoulders"
            case LongRestBreath.count:
                return "rest.long.exhaleLast"
            default:
                return "rest.long.exhale"
            }
        case .settle:
            return viewModel.usesScriptedLongRest ? "" : "rest.long.settle"
        }
    }

    private static var remainingKey: String { "rest.long.remaining %lld" }

    /// The displayed text of a line, with a format key's number filled in.
    private func text(for line: NarrationLine?) -> String {
        guard let line else {
            return ""
        }

        let language = AppLanguage.selected

        guard let argument = line.argument else {
            return localized(String.LocalizationValue(line.key))
        }

        let format = language.resourceBundle.localizedString(forKey: line.key, value: nil, table: nil)

        return String(format: format, locale: language.locale, argument)
    }

    private func speak(_ line: NarrationLine?, breath: LongRestBreath?) {
        viewModel.cancelSpeech()

        guard let line else {
            narrationID = nil
            narrationFinished = true
            return
        }

        // The breath count is spoken before the timed inhale so the longer cue has the full
        // phase. The two recordings play back to back; the stage waits for the second.
        if let breath, breath.phase == .inhale, announcesRemainingBreaths(before: breath, line: line) {
            viewModel.speak(
                id: UUID(),
                key: viewModel.longRestNarrationPrefix.map { $0 + "remaining %lld" }
                    ?? Self.remainingKey,
                argument: remainingBreaths(afterStarting: breath)
            )
        }

        let id = UUID()
        narrationID = id
        narrationFinished = false
        viewModel.speak(id: id, key: line.key, argument: line.argument)
    }

    /// Whether "N napas lagi" precedes this inhale cue.
    ///
    /// The first breath never announces six. The approved script also says "1 napas lagi"
    /// before "Sekali lagi"; the last breath speaks two inhale cues, so only the first one
    /// carries the count. The older generic rest keeps its original 5…2 counts.
    private func announcesRemainingBreaths(before breath: LongRestBreath, line: NarrationLine) -> Bool {
        guard breath.number > 1 else {
            return false
        }

        guard breath.number == LongRestBreath.count else {
            return true
        }

        return viewModel.usesScriptedLongRest
            && line.key.hasSuffix("inhaleLast")
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        let language = AppLanguage.selected
        return String(localized: key, bundle: language.resourceBundle, locale: language.locale)
    }

    private func stop() {
        viewModel.stopMusic()
        viewModel.cancelSpeech()
        viewModel.end()
    }

    private var completionPage: some View {
        VStack(spacing: 40) {
            Spacer(minLength: 24)

            VStack(spacing: 20) {
                TMTherapyCompletionMark(tint: TherapyPalette.brand)

                Text("plan.dayComplete")
                    .typography(size: 52, weight: .bold, relativeTo: .largeTitle)
                    .accessibilityAddTraits(.isHeader)

                Text("plan.dayCompleteMessage")
                    .typography(size: 26, weight: .regular, relativeTo: .title3)
            }
            .multilineTextAlignment(.center)

            Spacer(minLength: 24)

            TMTherapyButton(title: "plan.backHome", symbol: "house.fill", prominent: true) {
                viewModel.end()
            }

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 48)
        .foregroundStyle(TherapyPalette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TherapyPalette.canvas)
        .environment(\.colorScheme, .light)
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
@Observable
private final class MockDailyPlanNextViewModel: DailyPlanNextViewModelProtocol {
    let nextSessionItemID: String? = nil
    let nextSessionTitleKey: String? = nil
    let usesNextScript = false
    let usesScriptedLongRest = false
    let longRestNarrationPrefix: String? = nil
    let audioEvents = Empty<AudioEvent, Never>().eraseToAnyPublisher()

    func prepareRestNarration() {}
    func startMusic() {}
    func pauseMusic() {}
    func stopMusic() {}
    func cancelSpeech() {}
    func playCountdown(_ seconds: Int) {}
    func speak(id: UUID, key: String, argument: Int?) {}
    func launchAfterRest() {}
    func end() {}
}

@MainActor
private struct MockNextBuilder: DailyPlanNextContentBuildable {
    @ViewBuilder func buildDailyPlanIntro(
        itemID: String,
        countdownSeconds: Int?,
        automatic: Bool
    ) -> some View {
        Text(verbatim: "Intro \(itemID)")
    }
}

#Preview("Day complete") {
    TMDailyPlanNextView(viewModel: MockDailyPlanNextViewModel(), builder: MockNextBuilder())
}
#endif
