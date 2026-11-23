//
//  BalanceSessionView.swift
//  Tuntun
//
//  Created by Gracia A on 02/11/2026.
//

import SwiftUI

struct TMBalanceSessionView<ViewModel: BalanceSessionViewModelProtocol>: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: ViewModel
    private let plan: any DailyPlanSessionReporting
    private let permissionService: any PermissionServiceProtocol
    private let router: any SessionRouterProtocol

    init(
        model: ViewModel,
        plan: any DailyPlanSessionReporting,
        permissionService: any PermissionServiceProtocol,
        router: any SessionRouterProtocol
    ) {
        _model = State(initialValue: model)
        self.plan = plan
        self.permissionService = permissionService
        self.router = router
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
                    paused: model.paused,
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

            debugSkipRestButton
                .zIndex(4)

            loadingOverlay
                .zIndex(5)
        }
        .animation(.easeOut(duration: 0.28), value: model.allSetsDone)
        .background(TherapyPalette.canvas)
        .environment(\.colorScheme, .light)
        .statusBarHidden(false)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { await model.start(permissionService: permissionService) }
        .task(id: automaticallyRests && scenePhase == .active) {
            guard automaticallyRests, scenePhase == .active else { return }
            try? await Task.sleep(for: DailyPlanTiming.completionPreview)
            guard !Task.isCancelled, automaticallyRests else { return }
            leave()
        }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.foreground(permissionService: permissionService)
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
        guard let number = plan.currentNumber else {
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

    /// Debug builds only: ends the running rest between sets and starts the next set's countdown.
    @ViewBuilder
    private var debugSkipRestButton: some View {
        #if DEBUG
        if model.restBreath != nil, !model.paused, !model.allSetsDone {
            TMDebugSkipRestButton {
                model.skipRestForDebug()
            }
        }
        #endif
    }

    // MARK: - Live

    private var live: some View {
        TMTherapyExerciseLiveLayout(
            heading: model.calibrationMessage == nil
                ? heading
                : TMTherapyExerciseHeading(eyebrow: eyebrow, title: Text("stage.calibration")),
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
                selection: model.snapshot.armSelection,
                holdsPeak: model.demoHoldsPeak
            )
        } accessories: {
            EmptyView()
        }
    }

    private var camera: some View {
        ZStack(alignment: .top) {
            TMBodyCameraPreview(
                session: model.trackingService.session,
                front: true,
                onReady: model.previewReady,
                onOrientation: model.orientationChanged,
                onVideoBounds: { videoBounds = $0 }
            )

            if let overlay = model.snapshot.overlay {
                bubbleOverlay(overlay)
            }

            cameraStatus
        }
        .trackingStatusChip(model.trackingPositioned, videoBounds: videoBounds)
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
        .accessibilityLabel(LocalizedStringKey(model.exercise.key("cameraAccessibility")))
    }

    /// The countdown's seconds while it runs; the target is drawn quietly beneath it.
    private var countdownSeconds: Int? {
        guard !model.permissionDenied,
              !model.allSetsDone,
              model.restRemaining == nil,
              !model.cameraWaiting else {
            return nil
        }

        return model.countdownOverlaySeconds
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

    /// The target bubble, the wrist and the calibration cue, shared with the movement exercises;
    /// no skeleton.
    @ViewBuilder
    private func bubbleOverlay(_ overlay: BalanceOverlay) -> some View {
        let normalized = { (point: TherapyPoint) in
            CGPoint(x: point.x / overlay.aspect, y: point.y)
        }
        // While the comfortable end is shown, the cue runs from the wrist's resting position; the
        // wrist moves along it. Sit to stand moves its hip along its up or down arrow.
        let movementCue: SessionMovementCue? = {
            guard let joint = overlay.calibrationJoint ?? overlay.wrist,
                  let tip = overlay.calibrationTip else {
                return nil
            }

            return SessionMovementCue(
                tail: normalized(overlay.calibrationTail ?? joint),
                tip: normalized(tip),
                joint: normalized(joint)
            )
        }()

        if let target = overlay.target {
            if overlay.isCalibrationHold {
                // The patient's own joint is the marker: the wrist while the end pose is held
                // still, or sit to stand's hip, which pops on each held pose, stand and count.
                TMSessionBubbleOverlay(
                    imageAspect: overlay.aspect,
                    bubbleGuide: nil,
                    captureJoint: overlay.wrist.map(normalized),
                    holdProgress: overlay.targetProgress,
                    holdRadius: overlay.targetRadius,
                    captureCompletions: overlay.completions ?? model.snapshot.metrics.completedTouches,
                    captureActive: overlay.holdActive,
                    // Only sit to stand's step arrow is drawn with its marker; the arm exercises
                    // keep their wrist hold free of the range cue.
                    movementCue: overlay.calibrationJoint == nil ? nil : movementCue,
                    mirrored: true
                )
            } else {
                TMSessionBubbleOverlay(
                    imageAspect: overlay.aspect,
                    bubbleGuide: SessionBubbleGuide(
                        startCenter: normalized(target),
                        targetCenter: normalized(target),
                        trackedJoint: overlay.wrist.map(normalized),
                        radius: overlay.targetRadius,
                        activeZone: overlay.isReturnTarget ? .start : .target,
                        trackedJointInside: overlay.wrist.map { ($0 - target).length <= overlay.targetRadius } ?? false,
                        dwellProgress: overlay.targetProgress
                    ),
                    singleZone: overlay.isReturnTarget,
                    showsStart: false,
                    preview: countdownSeconds != nil,
                    mirrored: true
                )
            }
        } else {
            TMSessionBubbleOverlay(
                imageAspect: overlay.aspect,
                bubbleGuide: nil,
                movementCue: movementCue,
                mirrored: true
            )
        }
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
        model.allSetsDone && plan.hasAutomaticRest
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
                    title: plan.isRunning ? "plan.nextContinue" : "balance.completion.end",
                    symbol: plan.isRunning ? "play.fill" : nil,
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

        Task {
            await model.end()

            guard plan.isRunning else {
                router.closeSession()
                return
            }

            plan.finish(completed: completed)
        }
    }

    /// Covers starting and ending, which do synchronous main-actor work.
    @ViewBuilder
    private var loadingOverlay: some View {
        Group {
            if model.isPreparing, !model.permissionDenied {
                TMLoadingOverlay(message: "loading.preparingSession")
            } else if model.isFinishing {
                TMLoadingOverlay(message: "loading.finishingSession")
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: model.isPreparing || model.isFinishing
        )
    }

    /// Without camera access the session never started, so a running plan ends here.
    private func leaveWithoutResult() {
        guard plan.isRunning else {
            router.closeSession()
            return
        }

        plan.end()
    }
}
