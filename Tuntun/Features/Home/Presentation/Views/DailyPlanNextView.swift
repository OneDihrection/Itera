//
//  DailyPlanNextView.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

import SwiftUI

/// The rest and countdown between exercises, or the page after the last exercise.
struct TMDailyPlanNextView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
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

    private static let countdownDuration = 10.0

    private var showingNextIntro: Bool {
        stage == .countdownIntro || stage == .countdown
    }

    private var usesNextScript: Bool {
        guard let itemID = dependencies.dailyPlan.nextSessionItemID else {
            return false
        }
        return dependencies.dailyPlan.usesOppositionScript(itemID: itemID, in: dependencies)
            || dependencies.dailyPlan.usesArmRaiseScript(itemID: itemID, in: dependencies)
    }

    private var countdownSeconds: Int {
        let countdownElapsed = stage == .countdown ? elapsed : 0
        return max(1, Int(ceil(Self.countdownDuration - countdownElapsed)))
    }

    private func remainingBreaths(afterStarting breath: LongRestBreath) -> Int {
        LongRestBreath.count - breath.number + 1
    }

    var body: some View {
        Group {
            if let itemID = dependencies.dailyPlan.nextSessionItemID {
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
                TMDailyPlanIntroView(
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
        .onReceive(dependencies.audio.events) { event in
            if case .completed(let id, _) = event, id == narrationID {
                narrationFinished = true
            }
        }
        .task(id: paused || scenePhase != .active) {
            if paused || scenePhase != .active {
                dependencies.audio.pauseMusic()
                dependencies.audio.cancelSpeech()
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
            dependencies.audio.prepareRestNarration()
            audioPrepared = true
        }

        if !showingNextIntro {
            dependencies.audio.startMusic()
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
            if stage == .breathing, dependencies.dailyPlan.usesScriptedLongRest,
               !narrationFinished {
                let boundary = LongRestBreath.narrationBoundary(at: elapsed)
                elapsed = min(proposedElapsed, boundary.nextDown)
                startedAt = now - elapsed
            } else {
                elapsed = proposedElapsed
            }

            if stage == .countdown, elapsed >= Self.countdownDuration {
                dependencies.audio.cancelSpeech()
                dependencies.dailyPlan.launchAfterRest(dependencies: dependencies, router: router)
                return
            }

            if stage == .countdown {
                let seconds = countdownSeconds
                if seconds != lastSpokenSecond {
                    dependencies.audio.play(id: UUID(), cue: .countdown(seconds))
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
                    dependencies.audio.stopMusic()
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
            return dependencies.dailyPlan.usesScriptedLongRest ? .breathing : .firstBreathCount
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
        guard let prefix = dependencies.dailyPlan.longRestNarrationPrefix,
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
            return dependencies.dailyPlan.nextSessionTitleKey.map { NarrationLine(key: $0) }
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
                return dependencies.dailyPlan.usesScriptedLongRest ? "rest.long.inhale" : "rest.long.inhaleFirst"
            case LongRestBreath.count:
                let lastBreathStart = Double(LongRestBreath.count - 1) * LongRestBreath.cycleDuration
                return elapsed - lastBreathStart < 1.4 ? "rest.long.inhaleLast" : "rest.long.inhale"
            default:
                return "rest.long.inhale"
            }
        case .hold:
            // The approved long-rest script has no spoken hold between inhale and exhale.
            return dependencies.dailyPlan.usesScriptedLongRest ? "" : "rest.long.hold"
        case .exhale:
            switch breath.number {
            case 1:
                return dependencies.dailyPlan.usesScriptedLongRest ? "rest.long.exhale" : "rest.long.exhaleSlow"
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
            return dependencies.dailyPlan.usesScriptedLongRest ? "" : "rest.long.settle"
        }
    }

    private static let remainingKey = "rest.long.remaining %lld"

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
        dependencies.audio.cancelSpeech()

        guard let line else {
            narrationID = nil
            narrationFinished = true
            return
        }

        // The breath count is spoken before the timed inhale so the longer cue has the full
        // phase. The two recordings play back to back; the stage waits for the second.
        if let breath, breath.phase == .inhale, announcesRemainingBreaths(before: breath, line: line) {
            dependencies.audio.speak(
                id: UUID(),
                key: dependencies.dailyPlan.longRestNarrationPrefix.map { $0 + "remaining %lld" }
                    ?? Self.remainingKey,
                argument: remainingBreaths(afterStarting: breath)
            )
        }

        let id = UUID()
        narrationID = id
        narrationFinished = false
        dependencies.audio.speak(id: id, key: line.key, argument: line.argument)
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

        return dependencies.dailyPlan.usesScriptedLongRest
            && line.key.hasSuffix("inhaleLast")
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        let language = AppLanguage.selected
        return String(localized: key, bundle: language.resourceBundle, locale: language.locale)
    }

    private func stop() {
        dependencies.audio.stopMusic()
        dependencies.audio.cancelSpeech()
        dependencies.dailyPlan.end(router: router)
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
                dependencies.dailyPlan.end(router: router)
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
