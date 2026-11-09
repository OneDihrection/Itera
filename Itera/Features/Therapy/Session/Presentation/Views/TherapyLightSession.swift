//
//  TherapyLightSession.swift
//  Itera
//
//  Created by dimaswisodewo on 07/11/2026.
//

import SwiftUI

// The light look for arm raise, elbow bend, directional reach and fold towel, built from the
// shared exercise screens. The camera stays in one place in the view tree: the practice layout is
// always mounted, and the stage pages and the pause dialog are overlays on top of it
// (SYSTEM_DESIGN.md section 5).

// MARK: - Practice layout

extension TherapySessionView {
    /// Heading, the camera with its cue bubble, the demonstration, counters, Pause and End.
    var lightLayout: some View {
        TherapyExerciseLiveLayout(
            heading: lightHeading,
            cue: lightCue,
            demoTitle: "session.followMovement",
            repetitions: (model.snapshot.presentation?.count ?? 0, model.snapshot.activity?.goal ?? 0),
            sets: (model.snapshot.setNumber, model.snapshot.activity?.sets ?? 1),
            pauseTitle: "session.pauseAction",
            endTitle: "session.endAction",
            pauseDisabled: model.snapshot.paused,
            onPause: { model.command(.pause) },
            onEnd: requestEnd
        ) {
            lightCamera
        } demo: {
            demonstration
                .background(TherapyPalette.exerciseBackdrop)
        } accessories: {
            lightAccessories
        }
        .accessibilityHidden(hasFullScreenPresentation || model.snapshot.paused)
    }

    /// "Latihan N" while today's plan runs, over the exercise and side.
    var lightHeading: TherapyExerciseHeading {
        let eyebrow = dependencies.dailyPlan.currentNumber.map { Text("plan.exerciseNumber \($0)") }
        return TherapyExerciseHeading(eyebrow: eyebrow, title: Text(verbatim: lightTitle))
    }

    private var lightTitle: String {
        guard let activity = model.snapshot.activity else {
            return ""
        }

        var name = lightString(kindKeyName(activity.kind))

        if activity.hasSide {
            name += " · " + lightString(activity.side == .left ? "session.left" : "session.right")
        }

        return name
    }

    /// The live cue, with the towel fold, reach round or timed seconds after it when relevant.
    private var lightCue: Text {
        let copy = SessionGuidanceCopy(phrase: lightString(primaryMovementCue))
        var lines = [copy.main]

        if let support = copy.support {
            lines.append(support)
        }

        if let status = lightStatus {
            lines.append(status)
        }

        return Text(verbatim: lines.joined(separator: "\n"))
    }

    private var lightStatus: String? {
        switch model.snapshot.presentation {
        case .reach(let reach) where reach.phase == .rehearsal:
            return lightString("session.rehearsal")
        case .towel(let towel) where towel.phase == .practice:
            return String(format: lightString("towel.foldNumber %lld"), towel.foldIndex + 1)
        case .timed(let practice):
            return String(
                format: lightString("session.practiceSeconds %lld %lld"),
                Int(practice.seconds),
                Int(practice.goal)
            )
        default:
            return nil
        }
    }

    /// The shared preview with camera-wait and failure notices at its top edge, clear of the cue.
    private var lightCamera: some View {
        camera
            .overlay(alignment: .top) {
                VStack(spacing: 10) {
                    if model.snapshot.cameraWaiting {
                        TherapyFeedbackPill(text: "session.cameraWait")
                    }

                    if let failure = model.failure {
                        Text(verbatim: failure)
                            .typography(.caption)
                            .foregroundStyle(TherapyPalette.warning)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }

                    if let error = model.saveFailure {
                        saveError(error)
                    }
                }
                .padding(22)
            }
    }

    @ViewBuilder
    private var lightAccessories: some View {
        TherapyMusicMenu(
            selection: $musicTrack,
            options: ExerciseMusicTrack.allCases.map {
                TherapyMusicOption(id: $0.rawValue, title: LocalizedStringKey($0.titleKey))
            },
            size: 44
        )
        TherapyIconButton(title: "session.repeat", symbol: "speaker.wave.2.fill", size: 44, circle: true) {
            model.command(.repeatInstruction)
        }
        Image(systemName: model.listening ? "mic.fill" : "mic.slash")
            .typography(size: 20, weight: .semiBold)
            .frame(width: 44, height: 44)
            .accessibilityLabel(Text(model.listening ? "session.listening" : "home.voiceUnavailable"))
    }

    private func requestEnd() {
        endRequested = true
        model.command(.pause)
    }

    func lightString(_ key: String) -> String {
        String(
            localized: String.LocalizationValue(key),
            bundle: model.sessionLanguage.resourceBundle,
            locale: model.sessionLocale
        )
    }
}

// MARK: - Stage pages

extension TherapySessionView {
    /// Instruction, demonstration, countdowns, set summaries and recovery, light.
    @ViewBuilder
    var lightStagePage: some View {
        Group {
            if lightShowsSetSummary {
                lightSetSummary
            } else {
                VStack(spacing: 24) {
                    lightHeading
                    lightStageContent
                    lightStageControls
                }
                .padding(40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(TherapyPalette.ink)
        .background(TherapyPalette.canvas.ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }

    /// Feedback and rest after a set are one page: what was done and what comes next.
    private var lightShowsSetSummary: Bool {
        let stage = model.snapshot.stage
        return (stage == .feedback || stage == .rest)
            && !model.cameraDenied
            && model.voiceReady
            && !model.isStarting
    }

    @ViewBuilder
    private var lightStageContent: some View {
        if model.cameraDenied {
            recoveryPanel("therapy.session.cameraDenied")
        } else if model.isStarting {
            startupWaiting
        } else if !model.voiceReady {
            controlChoice
        } else if model.snapshot.stage == .preparing {
            preparingContent
        } else if model.snapshot.stage == .preparationWait {
            lightCountdown(
                "parity.getReady",
                seconds: model.snapshot.seconds,
                total: 5,
                running: model.snapshot.countdownRunning
            )
        } else if model.snapshot.stage == .activity,
            let seconds = model.snapshot.presentation?.countdownSeconds
        {
            lightCountdown(
                "stage.countdown",
                seconds: seconds,
                total: 3,
                running: model.snapshot.countdownRunning
            )
        } else if model.snapshot.stage == .instruction {
            lightGuidance(demonstrating: false)
        } else if model.snapshot.stage == .demonstration {
            lightGuidance(demonstrating: true)
        } else {
            Spacer(minLength: 0)
        }
    }

    /// A title over a dial that fills the free height: the number is the page.
    private func lightCountdown(
        _ title: LocalizedStringKey,
        seconds: Int,
        total: Int,
        running: Bool
    ) -> some View {
        VStack(spacing: 20) {
            Text(title)
                .typography(size: 52, weight: .bold, relativeTo: .largeTitle)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            TherapyCountdownDial(
                secondsLeft: seconds,
                total: total,
                running: running,
                tint: TherapyPalette.brand,
                track: TherapyPalette.planPanel
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Guidance

    private func lightGuidance(demonstrating: Bool) -> some View {
        VStack(spacing: 16) {
            lightGuidanceBody(demonstrating: demonstrating)

            if voiceOver, let id = model.snapshot.guidanceID {
                TherapyButton(title: "session.readingComplete", pill: true, brand: true) {
                    model.readingChanged(id, complete: true)
                }
                .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Text beside the exercise's own demonstration, as on the intro.
    @ViewBuilder
    private func lightGuidanceBody(demonstrating: Bool) -> some View {
        if demonstrating {
            HStack(spacing: 40) {
                lightGuidanceText(demonstrating: true)

                demonstration
                    .background(TherapyPalette.exerciseBackdrop)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .environment(\.therapyDemoCaptionHidden, true)
                    .frame(maxWidth: .infinity)
            }
        } else {
            lightGuidanceText(demonstrating: false)
        }
    }

    /// Measured reading stays the advancement gate for every instruction and demonstration card.
    @ViewBuilder
    private func lightGuidanceText(demonstrating: Bool) -> some View {
        if let id = model.snapshot.guidanceID {
            MeasuredInstructionText(
                phrase: guidancePhrase,
                instructionID: id,
                fontSize: demonstrating ? instructionSize / 2 : instructionSize * 2 / 3,
                reduceMotion: reduceMotion,
                voiceOver: voiceOver,
                textColor: .label,
                onReadingChanged: { id, complete in model.readingChanged(id, complete: complete) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Spacer(minLength: 0)
        }
    }

    // MARK: Set summaries

    /// Sets of the current activity recorded so far, with the rest still to come.
    private func setResults(for activity: SessionActivity) -> [TherapySetResult] {
        let recorded = model.snapshot.results.filter { $0.activity.id == activity.id }

        return (1...max(1, activity.sets)).map { number in
            let result = recorded.first { ($0.setNumber ?? 1) == number }

            return TherapySetResult(
                number: number,
                done: result?.completedWork ?? 0,
                goal: activity.goal,
                state: result?.outcome == .completed ? .done : .upcoming
            )
        }
    }

    /// The set page after each set: "Set N selesai!" with the rest, or the all-done wording when
    /// the last set of the last side is finished.
    @ViewBuilder
    private var lightSetSummary: some View {
        if let activity = model.snapshot.activity {
            let results = setResults(for: activity)
            let finishedSets = results.filter { $0.state == .done }.count
            let lastSet = finishedSets >= activity.sets
            let lastActivity = model.snapshot.index >= model.snapshot.activityCount - 1
            let done = results.reduce(0) { $0 + $1.done }

            TherapySetSummary(
                heading: lightHeading,
                headline: lastSet && lastActivity
                    ? Text("session.allDoneTitle")
                    : Text("session.setDone \(model.snapshot.setNumber)"),
                message: lightSetMessage(lastSet: lastSet, lastActivity: lastActivity),
                results: results,
                total: lastSet
                    ? Text("session.total \(done)")
                    : Text("session.totalOf \(done) \(activity.goal * activity.sets)"),
                footer: lightRestLine(lastSet: lastSet)
            ) {
                lightStageControls
            }
        }
    }

    private func lightSetMessage(lastSet: Bool, lastActivity: Bool) -> Text {
        if lastSet, lastActivity {
            return Text("session.allDoneMessage")
        }

        if lastSet {
            return Text("session.nextSideRest")
        }

        return Text("session.setRest \(model.snapshot.setNumber + 1)")
    }

    /// The rest countdown, once the rest has begun.
    private func lightRestLine(lastSet: Bool) -> Text? {
        guard model.snapshot.stage == .rest else {
            return nil
        }

        if lastSet {
            return Text("session.nextSideIn \(model.snapshot.seconds)")
        }

        return Text("session.nextSetIn \(model.snapshot.setNumber + 1) \(model.snapshot.seconds)")
    }

    /// After the session: every set of every side, and the way on.
    func lightAllDone(_ summary: SessionSummary) -> some View {
        let results = summary.results.enumerated().map { index, result in
            TherapySetResult(
                number: index + 1,
                done: result.completedWork,
                goal: result.activity.goal,
                state: result.outcome == .completed ? .done : .upcoming
            )
        }
        let finished = !summary.stopped && !summary.interrupted

        return TherapySetSummary(
            heading: lightHeading,
            headline: finished
                ? Text("session.allDoneTitle")
                : Text(summary.interrupted ? "session.interrupted" : "session.stopped"),
            message: finished ? Text("session.allDoneMessage") : Text("session.stoppedMessage"),
            results: results,
            total: Text("session.total \(results.reduce(0) { $0 + $1.done })")
        ) {
            VStack(spacing: 12) {
                if model.saving {
                    ProgressView("session.saving")
                }

                if let error = model.saveFailure {
                    saveError(error)
                }

                TherapyButton(
                    title: summaryExitTitle,
                    symbol: "play.fill",
                    disabled: model.saving || model.saveFailure != nil,
                    prominent: true
                ) {
                    leaveSummary(summary)
                }
            }
        }
        .environment(\.colorScheme, .light)
    }

    // MARK: Pause

    /// "Latihan dijeda" over the current screen.
    var lightPauseDialog: some View {
        TherapyPauseDialog(
            setLabel: Text("session.setNumber \(model.snapshot.setNumber)"),
            title: Text(verbatim: lightTitle),
            elapsedSeconds: model.elapsedSeconds,
            resumeDisabled: !model.voiceReady,
            confirmingEndInitially: endRequested,
            onEnd: { model.command(.stop) },
            onResume: {
                endRequested = false
                model.command(.resume)
            }
        ) {
            if !model.voiceReady {
                Button("session.retryCamera") {
                    Task { await model.retryCamera(permissions: permissions) }
                }
                .buttonStyle(SessionButtonStyle())
            }
        }
        .environment(\.colorScheme, .light)
    }

    // MARK: Controls

    /// Pause and End stay reachable on every stage page.
    private var lightStageControls: some View {
        VStack(spacing: 12) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 12))
                : AnyLayout(HStackLayout(spacing: 16))

            layout {
                TherapyButton(
                    title: "session.pauseAction",
                    symbol: "pause.fill",
                    disabled: model.snapshot.paused,
                    pill: true,
                    brand: true
                ) {
                    model.command(.pause)
                }

                TherapyButton(title: "session.endAction", symbol: "stop.fill", secondary: true, pill: true) {
                    requestEnd()
                }
            }
            .frame(maxWidth: 760)

            if let failure = model.failure, !model.snapshot.paused {
                Text(verbatim: failure)
                    .typography(.caption)
                    .foregroundStyle(TherapyPalette.warning)
            }

            if let error = model.saveFailure {
                saveError(error)
            }
        }
    }
}
