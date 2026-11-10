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
        }
        .animation(.easeOut(duration: 0.28), value: model.allSetsDone)
        .background(TherapyPalette.canvas)
        .environment(\.colorScheme, .light)
        .statusBarHidden(false)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { await model.start(permissions: permissions) }
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
            }

            if model.cameraWaiting {
                TMTherapyFeedbackPill(text: "balance.cameraWaiting")
                    .padding(20)
            }
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

    /// The standard pose, target bubble, hold ring and countdown shared with the movement exercises.
    private func targetOverlay(_ overlay: BalanceOverlay) -> some View {
        func normalized(_ point: TherapyPoint) -> CGPoint {
            CGPoint(x: point.x / overlay.aspect, y: point.y)
        }

        let imageSize = CGSize(width: overlay.aspect, height: 1)
        let pose = SessionPoseGuide(
            torso: overlay.showsTorso
                ? [overlay.leftShoulder, overlay.rightShoulder, overlay.rightHip, overlay.leftHip]
                    .map(normalized)
                : [],
            midline: overlay.showsMidline
                ? (normalized(overlay.midlineBase), normalized(overlay.midlineTop))
                : nil,
            chain: overlay.armChain.map(normalized),
            warning: overlay.compensationWarning
        )
        let countdown = overlay.target.flatMap { target in
            overlay.holdSecondsRemaining.map { seconds in
                SessionHoldCountdown(
                    seconds: seconds,
                    center: normalized(target),
                    radius: overlay.targetRadius
                )
            }
        }

        guard let target = overlay.target else {
            return TMSessionTargetOverlay(
                imageSize: imageSize,
                bubbleGuide: nil,
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

    private var allDonePage: some View {
        TMTherapySetSummary(
            heading: heading,
            headline: Text("session.allDoneTitle"),
            message: Text("session.allDoneMessage"),
            results: results,
            total: Text("session.total \(repetitionsDone)")
        ) {
            TMTherapyFinishActions(
                title: dependencies.dailyPlan.isRunning ? "plan.nextContinue" : "balance.completion.end",
                symbol: dependencies.dailyPlan.isRunning ? "play.fill" : nil,
                repeatTitle: "balance.completion.repeat",
                onRepeat: model.restart,
                action: endPractice
            )
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
