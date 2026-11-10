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
                TMBalancePoseOverlay(state: overlay, mirrored: true)
            }

            if model.cameraWaiting {
                TMTherapyFeedbackPill(text: "balance.cameraWaiting")
                    .padding(20)
            }
        }
        .background(TherapyPalette.canvas)
        .accessibilityLabel(model.exercise.localized("cameraAccessibility"))
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
            VStack(spacing: 12) {
                TMTherapyButton(
                    title: dependencies.dailyPlan.isRunning ? "plan.nextContinue" : "balance.completion.end",
                    symbol: dependencies.dailyPlan.isRunning ? "play.fill" : nil,
                    prominent: true,
                    action: endPractice
                )
                TMTherapyTextButton(title: "balance.completion.repeat", symbol: "arrow.clockwise") {
                    model.restart()
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

private struct TMBalancePoseOverlay: View {
    let state: BalanceOverlay
    let mirrored: Bool

    var body: some View {
        Canvas { context, size in
            let image = CGSize(width: state.aspect, height: 1)
            let scale = min(size.width / image.width, size.height / image.height)
            let offset = CGPoint(
                x: (size.width - image.width * scale) / 2,
                y: (size.height - image.height * scale) / 2
            )
            func point(_ source: TherapyPoint) -> CGPoint {
                CGPoint(
                    x: offset.x + (mirrored ? state.aspect - source.x : source.x) * scale,
                    y: offset.y + (1 - source.y) * scale
                )
            }

            let warning = state.compensationWarning
            let torsoColor = warning ? Color.orange : TherapyPalette.guidanceYellow

            if state.showsTorso {
                var torso = Path()
                torso.move(to: point(state.leftShoulder))
                torso.addLine(to: point(state.rightShoulder))
                torso.addLine(to: point(state.rightHip))
                torso.addLine(to: point(state.leftHip))
                torso.closeSubpath()
                context.fill(torso, with: .color(torsoColor.opacity(0.10)))
                context.stroke(torso, with: .color(torsoColor.opacity(0.75)), lineWidth: 3)
            }

            if state.showsMidline {
                var midline = Path()
                midline.move(to: point(state.midlineBase))
                midline.addLine(to: point(state.midlineTop))
                context.stroke(
                    midline,
                    with: .color(torsoColor),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [12, 8])
                )
            }

            if state.armChain.count > 1 {
                var arm = Path()
                arm.move(to: point(state.armChain[0]))
                state.armChain.dropFirst().forEach { arm.addLine(to: point($0)) }
                context.stroke(arm, with: .color(.black), style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                context.stroke(arm, with: .color(.white), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                for joint in state.armChain {
                    let center = point(joint)
                    let rect = CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)
                    context.fill(Path(ellipseIn: rect), with: .color(TherapyPalette.guidanceYellow))
                }
            }

            if let target = state.target {
                let radius = state.targetRadius * scale
                let targetColor: Color = TherapyPalette.guidanceBlue
                let rect = CGRect(
                    x: point(target).x - radius,
                    y: point(target).y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(targetColor.opacity(0.28)))
                // The outline is the progress bar: a dim track that fills clockwise.
                context.stroke(Path(ellipseIn: rect), with: .color(targetColor.opacity(0.45)), lineWidth: 8)
                if state.targetProgress > 0 {
                    var progress = Path()
                    progress.addArc(
                        center: point(target),
                        radius: radius,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + 360 * min(1, state.targetProgress)),
                        clockwise: false
                    )
                    context.stroke(
                        progress,
                        with: .color(targetColor),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                }
                if let remaining = state.holdSecondsRemaining {
                    // The count sits just outside the marker so it never hides the wrist, above
                    // it unless that would leave the picture.
                    let badge = 54.0
                    let gap = 14.0
                    let center = point(target)
                    let above = center.y - radius - gap - badge / 2
                    let badgeCenter = CGPoint(
                        x: center.x,
                        y: above - badge / 2 >= offset.y
                            ? above
                            : center.y + radius + gap + badge / 2
                    )
                    let badgeRect = CGRect(
                        x: badgeCenter.x - badge / 2,
                        y: badgeCenter.y - badge / 2,
                        width: badge,
                        height: badge
                    )

                    context.fill(Path(ellipseIn: badgeRect), with: .color(.black.opacity(0.6)))
                    context.stroke(Path(ellipseIn: badgeRect), with: .color(targetColor), lineWidth: 3)
                    context.draw(
                        Text(verbatim: String(remaining))
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white),
                        at: badgeCenter
                    )
                }
            }

            if let target = state.target, let trackedWrist = state.wrist {
                drawGuideArrow(
                    in: &context,
                    from: point(trackedWrist),
                    to: point(target),
                    targetRadius: state.targetRadius * scale,
                    color: .white
                )
            }

            // During the end-pose hold the marker itself sits on the wrist, with the countdown inside.
            if let trackedWrist = state.wrist, !state.isCalibrationHold {
                let wrist = point(trackedWrist)
                let wristRadius = 14.0
                let wristRect = CGRect(
                    x: wrist.x - wristRadius,
                    y: wrist.y - wristRadius,
                    width: wristRadius * 2,
                    height: wristRadius * 2
                )
                context.fill(
                    Path(ellipseIn: wristRect),
                    with: .color(TherapyPalette.guidanceYellow)
                )
                context.stroke(Path(ellipseIn: wristRect), with: .color(.white), lineWidth: 4)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// An arrow from the patient's wrist to the edge of the target, so it is clear where to
    /// move. It disappears once the wrist is inside the target.
    private func drawGuideArrow(
        in context: inout GraphicsContext,
        from start: CGPoint,
        to end: CGPoint,
        targetRadius: Double,
        color: Color
    ) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        let wristGap = 22.0
        let tipGap = targetRadius + 8

        guard distance > tipGap + wristGap + 30 else {
            return
        }

        let unit = CGPoint(x: dx / distance, y: dy / distance)
        let tail = CGPoint(x: start.x + unit.x * wristGap, y: start.y + unit.y * wristGap)
        let tip = CGPoint(x: end.x - unit.x * tipGap, y: end.y - unit.y * tipGap)

        let headLength = 26.0
        let spread = Angle.degrees(28).radians
        let angle = atan2(unit.y, unit.x)
        let shaftEnd = CGPoint(
            x: tip.x - unit.x * headLength * 0.6,
            y: tip.y - unit.y * headLength * 0.6
        )

        var shaft = Path()
        shaft.move(to: tail)
        shaft.addLine(to: shaftEnd)

        var head = Path()
        head.move(to: tip)
        head.addLine(to: CGPoint(
            x: tip.x - headLength * cos(angle - spread),
            y: tip.y - headLength * sin(angle - spread)
        ))
        head.addLine(to: CGPoint(
            x: tip.x - headLength * cos(angle + spread),
            y: tip.y - headLength * sin(angle + spread)
        ))
        head.closeSubpath()

        let dashed = StrokeStyle(lineWidth: 7, lineCap: .round, dash: [14, 10])

        context.stroke(shaft, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: 11, lineCap: .round, dash: [14, 10]))
        context.stroke(shaft, with: .color(color), style: dashed)
        context.fill(head, with: .color(.black.opacity(0.55)))
        context.fill(head, with: .color(color))
    }
}
