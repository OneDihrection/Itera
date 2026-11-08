//
//  BalanceSessionView.swift
//  Itera
//
//  Created by Gracia A on 02/11/2026.
//

import SwiftUI

struct BalanceSessionView: View {
    @AppStorage(ExerciseMusicTrack.storageKey) private var musicTrack = ExerciseMusicTrack.defaultValue
    @Environment(NavigationRouter.self) private var router
    @Environment(PermissionManager.self) private var permissions
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: BalanceSessionViewModel

    init(model: BalanceSessionViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack {
            Group {
                if model.permissionDenied {
                    permissionPanel
                } else {
                    sessionContent
                }
            }

            if model.snapshot.phase == .complete {
                BalanceCompletionOverlay(
                    exercise: model.exercise,
                    metrics: model.snapshot.metrics,
                    goal: model.snapshot.goal,
                    holdDuration: model.snapshot.holdDuration,
                    voiceListening: model.voiceListening,
                    repeatPractice: model.restart,
                    endPractice: endPractice
                )
                .zIndex(10)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.28), value: model.snapshot.phase == .complete)
        .background(TherapyPalette.cream)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .task { await model.start(permissions: permissions) }
        .onDisappear { model.stop() }
        .onChange(of: model.requestedExit) { _, requested in
            guard requested else { return }
            model.stop()
            router.pop()
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

    private var sessionContent: some View {
        GeometryReader { geometry in
            let stacked = geometry.size.width < 900
            let layout = stacked
                ? AnyLayout(VStackLayout(spacing: 20))
                : AnyLayout(HStackLayout(spacing: 20))
            layout {
                camera
                    .frame(
                        maxWidth: stacked ? .infinity : geometry.size.width * 0.66,
                        maxHeight: .infinity
                    )
                guidance
                    .frame(maxWidth: stacked ? .infinity : 430, maxHeight: .infinity)
            }
            .padding(20)
        }
    }

    private var camera: some View {
        GeometryReader { geometry in
            ZStack {
                BodyCameraPreview(
                    session: model.tracking.session,
                    front: model.frontCamera,
                    onReady: model.previewReady,
                    onOrientation: model.orientationChanged
                )
                if let overlay = model.snapshot.overlay {
                    BalancePoseOverlay(state: overlay, mirrored: model.frontCamera)
                }
                if model.cameraWaiting {
                    TherapyFeedbackPill(text: "balance.cameraWaiting")
                }
            }
            .background(TherapyPalette.cameraBackground)
            .clipShape(RoundedRectangle(cornerRadius: 32))
            .overlay {
                RoundedRectangle(cornerRadius: 32)
                    .strokeBorder(borderColor, lineWidth: 6)
            }
            .accessibilityLabel(model.exercise.localized("cameraAccessibility"))
        }
    }

    /// Spells out the two calibration poses of a rotation: where the arm starts, then where
    /// it ends. Shown only while that pose is being captured.
    private var calibrationGuide: AnyView? {
        guard model.exercise.isRotation, model.exercise != .shoulderFlexion else {
            return nil
        }

        let step: String
        let hint: String

        switch model.snapshot.phase {
        case .findingBody, .calibrating:
            // Shown from the very start, while the body is still being found, so the starting
            // pose is explained before the patient has to guess it.
            step = model.exercise.key("calibration.startStep")
            hint = model.exercise.key("calibration.startHint")
        case .calibratingRange:
            step = model.exercise.key("calibration.endStep")
            hint = model.exercise.key("calibration.endHint")
        default:
            return nil
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey(step))
                    .typography(.headline)
                    .foregroundStyle(TherapyPalette.green)

                Text(LocalizedStringKey(hint))
                    .typography(.footnote)
                    .foregroundStyle(TherapyPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TherapyPalette.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .combine)
        )
    }

    private var guidance: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    TherapyIconButton(title: "home.back", symbol: "xmark") {
                        model.stop()
                        router.pop()
                    }
                    Spacer()
                    TherapyIconButton(
                        title: model.paused ? "action.resume" : "action.pause",
                        symbol: model.paused ? "play.fill" : "pause.fill"
                    ) {
                        model.togglePause()
                    }
                    TherapyMusicMenu(
                        selection: $musicTrack,
                        options: ExerciseMusicTrack.allCases.map {
                            TherapyMusicOption(id: $0.rawValue, title: LocalizedStringKey($0.titleKey))
                        },
                        size: 44
                    )
                    TherapyIconButton(title: "session.camera", symbol: "arrow.triangle.2.circlepath.camera") {
                        model.switchCamera()
                    }
                }

                BalanceExerciseDemonstrationView(
                    exercise: model.exercise,
                    paused: model.paused || model.cameraWaiting,
                    arm: model.snapshot.activeArm,
                    selection: model.snapshot.armSelection
                )
                    .frame(height: 205)

                HStack(spacing: 12) {
                    Label(
                        model.voiceListening ? "balance.voiceListening" : "balance.voiceTouchFallback",
                        systemImage: model.voiceListening ? "waveform" : "hand.tap"
                    )
                    .typography(.footnote)
                    .foregroundStyle(model.voiceListening ? TherapyPalette.green : TherapyPalette.muted)
                    Spacer()
                    Text("balance.voiceCommands")
                        .typography(.footnote)
                        .foregroundStyle(TherapyPalette.muted)
                }
                .padding(14)
                .background(TherapyPalette.cream, in: RoundedRectangle(cornerRadius: 18))

                Label(
                    String(
                        format: String(localized: "balance.holdConfigured"),
                        model.holdSeconds
                    ),
                    systemImage: "timer"
                )
                .typography(.footnote)
                .foregroundStyle(TherapyPalette.green)

                if model.paused {
                    Label("balance.paused", systemImage: "pause.circle.fill")
                        .typography(.headline)
                        .foregroundStyle(TherapyPalette.warning)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(TherapyPalette.peach, in: RoundedRectangle(cornerRadius: 18))
                }

                HStack(spacing: 18) {
                    ZStack {
                        TherapyProgressRing(
                            progress: Double(model.snapshot.metrics.completedTouches)
                                / Double(max(1, model.snapshot.goal)),
                            lineWidth: 9
                        )
                        Text(verbatim: "\(model.snapshot.metrics.completedTouches)/\(model.snapshot.goal)")
                            .typography(.headline)
                    }
                    .frame(width: 82, height: 82)

                    Text(LocalizedStringKey(model.snapshot.instructionKey))
                        .typography(.therapyCue)
                        .foregroundStyle(instructionColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }

                if let guide = calibrationGuide {
                    guide
                }

                if model.snapshot.phase == .calibrating || model.snapshot.phase == .calibratingRange {
                    ProgressView(value: model.snapshot.calibrationProgress)
                        .tint(TherapyPalette.green)
                        .scaleEffect(y: 2)
                        .accessibilityLabel("balance.calibrationProgress")
                }

                if (model.snapshot.phase == .holding || model.snapshot.phase == .returning),
                    let remaining = model.snapshot.overlay?.holdSecondsRemaining
                {
                    HStack(spacing: 14) {
                        Image(systemName: "hand.raised.fill")
                            .typography(size: 28, weight: .bold)
                        Text(
                            String(
                                format: String(localized: "balance.holdCountdown"),
                                remaining
                            )
                        )
                        .typography(.title2)
                        .monospacedDigit()
                    }
                    .foregroundStyle(TherapyPalette.green)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TherapyPalette.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityAddTraits(.updatesFrequently)
                }

                if model.snapshot.compensation.isCompensating {
                    compensationPanel
                }

                HStack(spacing: 12) {
                    TherapyMetric(
                        title: model.exercise.localized("metric.touches"),
                        value: "\(model.snapshot.metrics.completedTouches) / \(model.snapshot.goal)"
                    )
                    if model.exercise.isRotation {
                        TherapyMetric(
                            title: model.exercise.localized("metric.angle"),
                            value: model.snapshot.targetAngle > 0
                                ? "\(Int(model.snapshot.rotationDegrees.rounded()))° / \(model.snapshot.targetAngle)°"
                                : "\(Int(model.snapshot.rotationDegrees.rounded()))°"
                        )
                    } else {
                        TherapyMetric(
                            title: "balance.metric.dwell",
                            value: model.snapshot.metrics.midlineDwellTime.formatted(.number.precision(.fractionLength(1))) + "s"
                        )
                    }
                }

                HStack(spacing: 12) {
                    TherapyMetric(
                        title: "balance.metric.compensation",
                        value: "\(model.snapshot.metrics.compensationEventsCount)"
                    )
                    TherapyMetric(
                        title: "balance.metric.smoothness",
                        value: model.snapshot.metrics.pathSmoothness.formatted(.percent.precision(.fractionLength(0)))
                    )
                }

                if let failure = model.failure, !failure.isEmpty {
                    Text(verbatim: failure)
                        .typography(.footnote)
                        .foregroundStyle(TherapyPalette.warning)
                }

            }
            .padding(24)
        }
        .background(TherapyPalette.surface, in: RoundedRectangle(cornerRadius: 32))
    }

    private var compensationPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("balance.compensationWarning", systemImage: "exclamationmark.triangle.fill")
                .typography(.headline)
            Text(
                String(
                    format: String(localized: "balance.compensation.detail"),
                    abs(model.snapshot.compensation.leanDegrees),
                    model.snapshot.compensation.shoulderRotationRatio * 100
                )
            )
            .typography(.footnote)
            if model.snapshot.compensation.reasons.contains(.elbowAway) {
                Text("rotation.compensation.elbow")
                    .typography(.footnote)
            }
        }
        .foregroundStyle(TherapyPalette.warning)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TherapyPalette.peach, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var permissionPanel: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill")
                .typography(size: 64, weight: .bold)
                .foregroundStyle(TherapyPalette.warning)
            Text("balance.cameraRequired").typography(.title).multilineTextAlignment(.center)
            TherapyButton(title: "home.openSettings", symbol: "gear") { model.openSettings() }
            TherapyButton(title: "home.back", symbol: "chevron.left", secondary: true) { router.pop() }
        }
        .padding(32)
        .frame(maxWidth: 700, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
    }

    private var borderColor: Color {
        model.snapshot.compensation.isCompensating ? TherapyPalette.warning : TherapyPalette.green
    }

    private var instructionColor: Color {
        model.snapshot.compensation.isCompensating ? TherapyPalette.warning : TherapyPalette.ink
    }

    private func endPractice() {
        model.stop()
        router.pop()
    }
}

private struct BalancePoseOverlay: View {
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
            let torsoColor = warning ? Color.orange : Color.cyan
            var torso = Path()
            torso.move(to: point(state.leftShoulder))
            torso.addLine(to: point(state.rightShoulder))
            torso.addLine(to: point(state.rightHip))
            torso.addLine(to: point(state.leftHip))
            torso.closeSubpath()
            context.fill(torso, with: .color(torsoColor.opacity(0.10)))
            context.stroke(torso, with: .color(torsoColor.opacity(0.75)), lineWidth: 3)

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
                context.stroke(arm, with: .color(.cyan), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                for joint in state.armChain {
                    let center = point(joint)
                    let rect = CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)
                    context.fill(Path(ellipseIn: rect), with: .color(.white))
                }
            }

            if let target = state.target {
                let radius = state.targetRadius * scale
                let targetColor: Color = state.isReturnTarget ? .cyan : .orange
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
                    color: state.isReturnTarget ? .cyan : .orange
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
                    with: .color(state.crossedMidline ? .green : .cyan)
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
