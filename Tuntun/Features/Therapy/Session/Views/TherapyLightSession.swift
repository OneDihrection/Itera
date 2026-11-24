//
//  TherapyLightSession.swift
//  Tuntun
//
//  Created by dimaswisodewo on 07/11/2026.
//

import SwiftUI

// The light look for arm raise, elbow bend, directional reach and fold towel, built from the
// shared exercise screens. The camera stays in one place in the view tree: the practice layout is
// always mounted, and the stage pages and the pause dialog are overlays on top of it
// (SYSTEM_DESIGN.md section 5).

// MARK: - Practice layout

extension TMTherapySessionView {
    /// Heading, the camera with its cue bubble, the demonstration, counters, Pause and End.
    var lightLayout: some View {
        TMTherapyExerciseLiveLayout(
            heading: showsCalibrationHeading ? .calibration : lightHeading,
            cuePlacement: .video(videoBounds),
            repetitions: (model.snapshot.presentation?.count ?? 0, model.snapshot.activity?.goal ?? 0),
            sets: (model.snapshot.setNumber, model.snapshot.activity?.sets ?? 1),
            pauseTitle: "session.pauseAction",
            endTitle: "session.endAction",
            pauseDisabled: model.snapshot.paused,
            calibrating: isCalibrationLayout,
            demoRevision: model.demoRevision,
            demoAnnouncement: lightString(model.demoTitleKey),
            onPause: { model.command(.pause) },
            onEnd: requestEnd
        ) {
            lightCamera
        } demo: {
            demonstration
                .background(TherapyPalette.exerciseBackdrop)
        } accessories: {
            EmptyView()
        }
        .accessibilityHidden(hasFullScreenPresentation || model.snapshot.paused)
    }

    /// Debug builds only. Drawn over the header's trailing corner, above stage pages and the pause
    /// dialog, rather than in `accessories`, which would move the centred heading.
    @ViewBuilder
    var lightDebugFinishButton: some View {
        #if DEBUG
        if usesLightLayout, model.snapshot.summary == nil, !model.entryFailure {
            TMDebugActionButton(title: "debug.finishExercise", symbol: "forward.end.fill") {
                model.command(.debugFinish)
            }
            .padding(.top, 12)
            .padding(.trailing, 20)
        }
        #endif
    }

    /// Every light activity runs its opening and demonstration cues over the live camera.
    private var usesCameraOpening: Bool {
        switch model.snapshot.activity?.kind {
        case .armRaise, .elbowBend, .directionalReach, .foldTowel: return true
        default: return false
        }
    }

    /// Fold towel has no calibration, so its opening keeps the exercise heading.
    private var showsCalibrationHeading: Bool {
        isCalibrationLayout && model.snapshot.activity?.kind != .foldTowel
    }

    /// The opening and demonstration cues keep the calibration layout; they are spoken, not shown.
    private var showsCameraOpening: Bool {
        usesCameraOpening
            && (model.snapshot.stage == .instruction || model.snapshot.stage == .demonstration)
    }

    var isCalibrationLayout: Bool {
        if showsCameraOpening || (usesCameraOpening && model.snapshot.stage == .preparing) {
            return true
        }
        if model.snapshot.stage == .preparationWait || model.snapshot.speaksCalibrationComplete {
            return true
        }

        guard model.snapshot.stage == .activity else {
            return false
        }

        switch model.snapshot.presentation {
        case .movement(let movement):
            return movement.phase == .startCapture || movement.phase == .targetCapture
                || movement.phase == .returnToStart
        case .reach(let reach):
            return reach.phase == .setup || reach.phase == .assessment
        default:
            return false
        }
    }

    /// "Latihan N" while today's plan runs, over the exercise and side.
    var lightHeading: TMTherapyExerciseHeading {
        let eyebrow = plan.currentNumber.map { Text("plan.exerciseNumber \($0)") }
        return TMTherapyExerciseHeading(eyebrow: eyebrow, title: Text(verbatim: lightTitle))
    }

    private var lightTitle: String {
        guard let activity = model.snapshot.activity else {
            return ""
        }

        if model.snapshot.usesArmRaiseScript {
            return lightString(model.snapshot.armRaiseNarrationPrefix + "title")
        }

        var name = lightString(kindKeyName(activity.kind))

        if activity.hasSide {
            let side = model.snapshot.activeSide ?? activity.side
            name += " · " + lightString(side == .left ? "session.left" : "session.right")
        }

        return name
    }

    /// The shared preview with camera-wait and failure notices at its top edge. No instruction text
    /// is drawn over the camera; narration speaks the cue.
    private var lightCamera: some View {
        camera
            .overlay(alignment: .top) {
                VStack(spacing: 10) {
                    if model.snapshot.cameraWaiting {
                        TMTherapyFeedbackPill(text: "session.cameraWait")
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

    func requestEnd() {
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

extension TMTherapySessionView {
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
            recoveryPanel(cameraDeniedMessage)
        } else if !model.voiceReady {
            controlChoice
        } else if model.snapshot.stage == .preparing {
            preparingContent
        } else if model.snapshot.stage == .instruction {
            lightGuidance(demonstrating: false)
        } else if model.snapshot.stage == .demonstration {
            lightGuidance(demonstrating: true)
        } else {
            Spacer(minLength: 0)
        }
    }


    // MARK: Guidance

    private func lightGuidance(demonstrating: Bool) -> some View {
        VStack(spacing: 16) {
            lightGuidanceBody(demonstrating: demonstrating)

            if voiceOver, let id = model.snapshot.guidanceID {
                TMTherapyButton(title: "session.readingComplete", pill: true, brand: true) {
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
            TMMeasuredInstructionText(
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

            TMTherapySetSummary(
                heading: lightHeading,
                headline: lastSet && lastActivity
                    ? Text("session.allDoneTitle")
                    : Text("session.setDoneCheer \(model.snapshot.setNumber)"),
                total: lastSet
                    ? model.sessionLanguage.attributedString("session.total \(done)")
                    : model.sessionLanguage.attributedString(
                        "session.totalOfCheer \(done) \(activity.goal * activity.sets)"
                    ),
                message: lightSetMessage(lastSet: lastSet, lastActivity: lastActivity),
                results: results,
                footer: lightRestLine(lastSet: lastSet)
            ) {
                lightStageControls
            }
        }
    }

    /// The scripted arm-raise summary, or what comes after the last set. Between sets the total
    /// and the rest line say enough.
    private func lightSetMessage(lastSet: Bool, lastActivity: Bool) -> Text? {
        if model.snapshot.usesArmRaiseScript, let key = model.snapshot.armRaiseSummaryKey {
            return Text(LocalizedStringKey(key))
        }
        if lastSet, lastActivity {
            return Text("session.allDoneMessage")
        }

        if lastSet {
            return Text("session.nextSideRest")
        }

        return nil
    }

    /// The rest countdown, once the rest has begun.
    private func lightRestLine(lastSet: Bool) -> Text? {
        guard model.snapshot.stage == .rest else {
            return nil
        }

        if lastSet {
            return Text("session.restBeforeSide \(model.snapshot.seconds)")
        }

        return Text("session.restBeforeSet \(model.snapshot.seconds) \(model.snapshot.setNumber + 1)")
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

        return TMTherapySetSummary(
            heading: lightHeading,
            headline: finished
                ? Text("session.allDoneTitle")
                : Text(summary.interrupted ? "session.interrupted" : "session.stopped"),
            total: model.sessionLanguage.attributedString(
                "session.total \(results.reduce(0) { $0 + $1.done })"
            ),
            message: finished ? Text("session.allDoneMessage") : Text("session.stoppedMessage"),
            results: results
        ) {
            if automaticallyRests(after: summary) {
                if model.saving {
                    ProgressView("session.saving")
                }

                if let error = model.saveFailure {
                    saveError(error)
                }

                completionActions(summary)
            } else {
                TMTherapyFinishActions(
                    title: summaryExitTitle,
                    symbol: "play.fill",
                    disabled: model.saving || model.saveFailure != nil,
                    action: { leaveSummary(summary) }
                ) {
                    if model.saving {
                        ProgressView("session.saving")
                    }

                    if let error = model.saveFailure {
                        saveError(error)
                    }
                }
            }
        }
        .environment(\.colorScheme, .light)
    }

    // MARK: Pause

    /// "Latihan dijeda" over the current screen.
    var lightPauseDialog: some View {
        TMTherapyPauseDialog(
            setLabel: Text("session.setNumber \(model.snapshot.setNumber)"),
            title: Text(verbatim: lightTitle),
            elapsedSeconds: model.elapsedSeconds,
            resumeDisabled: !model.voiceReady,
            confirmingEndInitially: endRequested,
            onEnd: endSession,
            onResume: {
                endRequested = false
                model.command(.resume)
            }
        ) {
            if !model.voiceReady {
                Button("session.retryCamera") {
                    Task { await model.retryCamera(permissionService: permissionService) }
                }
                .buttonStyle(TMSessionButtonStyle())
            }
        }
        .environment(\.colorScheme, .light)
    }

    // MARK: Controls

    /// Pause and End stay reachable on every stage page: Pause as plain text over the red End pill.
    private var lightStageControls: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                TMTherapyButton(
                    title: "session.pauseAction",
                    symbol: "pause.fill",
                    disabled: model.snapshot.paused,
                    plain: true
                ) {
                    model.command(.pause)
                }

                TMTherapyButton(title: "session.endAction", symbol: "stop.fill", destructive: true, pill: true) {
                    requestEnd()
                }

                // The set page stays up through the rest that follows it, so it can end that rest.
                if model.snapshot.stage == .rest {
                    TMTherapyButton(
                        title: "rest.skip",
                        symbol: "forward.fill",
                        disabled: model.snapshot.paused,
                        plain: true
                    ) {
                        model.command(.skipRest)
                    }
                }
            }
            .frame(maxWidth: 460)

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
