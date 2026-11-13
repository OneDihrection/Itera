//
//  BalanceSessionView.swift
//  Itera
//
//  Created by Gracia A on 02/11/2026.
//

import SwiftUI

struct TMBalanceSessionView: View {
    @Environment(NavigationRouter.self) private var router
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PermissionManager.self) private var permissions
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: BalanceSessionViewModel

    init(model: BalanceSessionViewModel) {
        _model = State(initialValue: model)
    }

    /// Set when End was tapped on the live screen, so the pause dialog opens on its confirmation.
    @State private var endRequested = false
    @State private var videoBounds: CGRect?

    var body: some View {
        ZStack {
            if model.permissionDenied {
                permissionPanel
            } else {
                live
                    .accessibilityHidden(model.countdownOverlaySeconds != nil || model.paused)
            }

            if model.allSetsDone {
                allDonePage
                    .zIndex(2)
            } else if let breath = model.restBreath {
                TMTherapyBreathingRest(
                    cue: LocalizedStringKey(breath.phase.key),
                    intensity: breath.intensity,
                    animationDuration: 1,
                    pause: model.pause,
                    stop: requestEnd
                )
                .zIndex(2)
            }

            if let seconds = model.countdownOverlaySeconds, !model.permissionDenied,
               !model.allSetsDone, model.restRemaining == nil {
                TMPracticeCountdown(seconds: seconds, pause: model.pause, stop: requestEnd)
                    .ignoresSafeArea()
                    .zIndex(2)
            }

            if model.paused, !model.allSetsDone, !model.permissionDenied {
                pauseDialog
                    .zIndex(3)
            }

            debugFinishButton
                .zIndex(4)
        }
        .animation(.easeOut(duration: 0.28), value: model.allSetsDone)
        .background(TherapyPalette.canvas)
        .environment(\.colorScheme, .light)
        .statusBarHidden(false)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { await model.start(permissions: permissions) }
        .task(id: automaticallyRests && scenePhase == .active) {
            guard automaticallyRests, scenePhase == .active else { return }
            try? await Task.sleep(for: DailyPlanViewModel.completionPreviewDuration)
            guard !Task.isCancelled, automaticallyRests else { return }
            leave()
        }
        .onDisappear { model.stop() }
        .onChange(of: model.requestedExit) { _, requested in
            guard requested else { return }
            leave()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.foreground(permissions: permissions)
            case .background: model.background()
            case .inactive: break
            @unknown default: model.background()
            }
        }
    }

    // MARK: - Heading

    private var heading: TMTherapyExerciseHeading {
        TMTherapyExerciseHeading(eyebrow: eyebrow, title: title)
    }

    /// "Latihan N" while today's plan runs; a program started on its own has no number.
    private var eyebrow: Text? {
        guard let number = dependencies.dailyPlan.currentNumber else {
            return nil
        }

        return Text("plan.exerciseNumber \(number)")
    }

    private var title: Text {
        Text(LocalizedStringKey(model.exercise.key("title")))
    }

    // MARK: - Debug

    /// Debug builds only. Pinned to the header's trailing corner, above rest, countdown and the
    /// pause dialog, rather than in the live layout's `accessories`, which would move the heading.
    @ViewBuilder
    private var debugFinishButton: some View {
        #if DEBUG
        if !model.allSetsDone, !model.permissionDenied {
            TMDebugActionButton(title: "debug.finishExercise", symbol: "forward.end.fill") {
                model.finishExerciseForDebug()
            }
            .padding(.top, 12)
            .padding(.trailing, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        #endif
    }

    // MARK: - Live

    private var live: some View {
        TMTherapyExerciseLiveLayout(
            heading: model.calibrationMessage == nil
                ? heading
                : TMTherapyExerciseHeading(eyebrow: eyebrow, title: Text("stage.calibration")),
            cue: practiceCue,
            cuePlacement: .video(videoBounds),
            demoTitle: "session.followMovement",
            repetitions: (model.snapshot.metrics.completedTouches, model.snapshot.goal),
            sets: (model.setNumber, model.totalSets),
            pauseTitle: "session.pauseAction",
            endTitle: "session.endAction",
            pauseDisabled: model.paused,
            calibrating: model.calibrationMessage != nil,
            demoRevision: model.demoRevision,
            demoAnnouncement: String(localized: "demo.step.otherArm"),
            onPause: model.pause,
            onEnd: requestEnd
        ) {
            camera
        } demo: {
            TMBalanceExerciseDemonstrationView(
                exercise: model.exercise,
                paused: model.paused || model.cameraWaiting,
                arm: model.snapshot.activeArm,
                selection: model.snapshot.armSelection
            )
        } accessories: {
            EmptyView()
        }
    }

    private var practiceCue: Text {
        if let message = model.calibrationMessage, message != "calibration.try" {
            return Text(LocalizedStringKey(message))
        }
        return Text(LocalizedStringKey(cueKey))
    }

    /// The one cue line under the camera: a compensation warning first, then a rotation's
    /// calibration pose, otherwise the engine's own instruction.
    private var cueKey: String {
        if model.snapshot.compensation.isCompensating {
            return "balance.compensationWarning"
        }

        guard model.exercise.isRotation, model.exercise != .shoulderFlexion else {
            return model.snapshot.instructionKey
        }

        switch model.snapshot.phase {
        case .findingBody, .calibrating:
            return model.exercise.key("calibration.startHint")
        case .calibratingRange:
            return model.exercise.key("calibration.endHint")
        default:
            return model.snapshot.instructionKey
        }
    }

    private var camera: some View {
        ZStack(alignment: .top) {
            TMBodyCameraPreview(
                session: model.tracking.session,
                front: true,
                onReady: model.previewReady,
                onOrientation: model.orientationChanged,
                onVideoBounds: { videoBounds = $0 }
            )

            if let overlay = model.snapshot.overlay {
                targetOverlay(overlay)
            } else if !model.cameraWaiting {
                TMBalanceLiveSkeletonLayer(model: model)
            }

            cameraStatus
        }
        .background(TherapyPalette.canvas)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { model.viewport(proxy.size) }
                    .onChange(of: proxy.size) { _, size in
                        model.viewport(size)
                    }
            }
        }
        .accessibilityLabel(model.exercise.localized("cameraAccessibility"))
    }

    /// A camera failure offers a retry; otherwise waiting shows the calm camera message.
    @ViewBuilder
    private var cameraStatus: some View {
        if model.failure != nil {
            VStack(spacing: 12) {
                TMTherapyFeedbackPill(text: "session.captureError")

                TMTherapyTextButton(title: "action.retry", symbol: "arrow.clockwise") {
                    model.retryCamera()
                }
            }
            .padding(20)
        } else if model.cameraWaiting {
            TMTherapyFeedbackPill(text: "balance.cameraWaiting")
                .padding(20)
        }
    }

    /// The standard pose, target bubble, hold ring and countdown shared with the movement exercises.
    private func targetOverlay(_ overlay: BalanceOverlay) -> some View {
        func normalized(_ point: TherapyPoint) -> CGPoint {
            CGPoint(x: point.x / overlay.aspect, y: point.y)
        }

        let imageSize = CGSize(width: overlay.aspect, height: 1)
        let pose = SessionPoseGuide(chain: overlay.armChain.map(normalized))
        let countdown = overlay.target.flatMap { target in
            overlay.holdSecondsRemaining.map { seconds in
                SessionHoldCountdown(
                    seconds: seconds,
                    center: normalized(target),
                    radius: overlay.targetRadius
                )
            }
        }

        // While the comfortable end is shown, wind flows from the wrist's resting position; the
        // wrist moves through it.
        let movementCue: SessionMovementCue? = {
            guard let wrist = overlay.wrist,
                  let tip = overlay.calibrationTip else {
                return nil
            }

            return SessionMovementCue(
                tail: normalized(overlay.calibrationTail ?? wrist),
                tip: normalized(tip),
                joint: normalized(wrist)
            )
        }()

        guard let target = overlay.target else {
            return TMSessionTargetOverlay(
                imageSize: imageSize,
                bubbleGuide: nil,
                movementCue: movementCue,
                poseGuide: pose,
                mirrored: true
            )
        }

        guard !overlay.isCalibrationHold else {
            // The patient's own wrist is the marker while the end pose is held still.
            return TMSessionTargetOverlay(
                imageSize: imageSize,
                bubbleGuide: nil,
                captureJoint: overlay.wrist.map(normalized),
                holdProgress: overlay.targetProgress,
                holdRadius: overlay.targetRadius,
                poseGuide: pose,
                holdCountdown: countdown,
                mirrored: true
            )
        }

        let inside = overlay.wrist.map { ($0 - target).length <= overlay.targetRadius } ?? false
        let bubble = SessionBubbleGuide(
            startCenter: normalized(target),
            targetCenter: normalized(target),
            trackedJoint: overlay.wrist.map(normalized),
            radius: overlay.targetRadius,
            activeZone: overlay.isReturnTarget ? .start : .target,
            trackedJointInside: inside,
            dwellProgress: overlay.targetProgress
        )

        return TMSessionTargetOverlay(
            imageSize: imageSize,
            bubbleGuide: bubble,
            singleZone: overlay.isReturnTarget,
            showsStart: false,
            poseGuide: pose,
            holdCountdown: countdown,
            mirrored: true
        )
    }

    private func requestEnd() {
        endRequested = true
        model.pause()
    }

    // MARK: - Pause

    private var pauseDialog: some View {
        TMTherapyPauseDialog(
            setLabel: Text("session.setNumber \(model.setNumber)"),
            title: title,
            elapsedSeconds: model.elapsedSeconds,
            confirmingEndInitially: endRequested,
            onEnd: leave,
            onResume: {
                endRequested = false
                model.resume()
            }
        ) {
            EmptyView()
        }
    }

    // MARK: - Set summaries

    private var results: [TherapySetResult] {
        (1...max(1, model.totalSets)).map { number in
            let finished = number <= model.setResults.count

            return TherapySetResult(
                number: number,
                done: finished ? model.setResults[number - 1] : 0,
                goal: model.snapshot.goal,
                state: finished ? .done : .upcoming
            )
        }
    }

    private var repetitionsDone: Int {
        model.setResults.reduce(0, +)
    }

    private var automaticallyRests: Bool {
        model.allSetsDone && dependencies.dailyPlan.hasAutomaticRest
    }

    private var allDonePage: some View {
        TMTherapySetSummary(
            heading: heading,
            headline: Text("session.allDoneTitle"),
            message: Text("session.allDoneMessage"),
            results: results,
            total: Text("session.total \(repetitionsDone)")
        ) {
            if !automaticallyRests {
                TMTherapyFinishActions(
                    title: dependencies.dailyPlan.isRunning ? "plan.nextContinue" : "balance.completion.end",
                    symbol: dependencies.dailyPlan.isRunning ? "play.fill" : nil,
                    repeatTitle: "balance.completion.repeat",
                    onRepeat: model.restart,
                    action: endPractice
                ) {
                    if model.historySaveFailed {
                        TMTherapyError(key: "history.saveFailed")
                        TMTherapyTextButton(title: "action.retry", symbol: "arrow.clockwise") {
                            model.retryHistorySave()
                        }
                    }
                }
            }
        }
    }

    private var permissionPanel: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill")
                .typography(size: 64, weight: .bold)
                .foregroundStyle(TherapyPalette.warning)
            Text("balance.cameraRequired").typography(.title).multilineTextAlignment(.center)
            TMTherapyButton(title: "home.openSettings", symbol: "gear") { model.openSettings() }
            TMTherapyButton(title: "home.back", symbol: "chevron.left", secondary: true) { leaveWithoutResult() }
        }
        .padding(32)
        .frame(maxWidth: 700, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
    }

    private func endPractice() {
        leave()
    }

    /// Stops the session and goes back, or, while today's plan runs, on to the next exercise.
    /// Only a session that reached its goal counts as done in the plan.
    private func leave() {
        let completed = model.allSetsDone
        model.stop()

        guard dependencies.dailyPlan.isRunning else {
            router.pop()
            return
        }

        dependencies.dailyPlan.finish(completed: completed, router: router)
    }

    /// Without camera access the session never started, so a running plan ends here.
    private func leaveWithoutResult() {
        guard dependencies.dailyPlan.isRunning else {
            router.pop()
            return
        }

        dependencies.dailyPlan.end(router: router)
    }
}

/// The tracked skeleton alone, before the engine draws targets over it.
///
/// It is its own view so only this layer reads `livePose`, which changes every camera frame;
/// reading it in the session screen's body would rebuild the whole screen 30 times a second.
private struct TMBalanceLiveSkeletonLayer: View {
    let model: BalanceSessionViewModel

    var body: some View {
        if let skeleton = model.livePose {
            TMSessionTargetOverlay(
                imageSize: skeleton.imageSize,
                bubbleGuide: nil,
                poseGuide: skeleton.guide,
                mirrored: true
            )
        }
    }
}
