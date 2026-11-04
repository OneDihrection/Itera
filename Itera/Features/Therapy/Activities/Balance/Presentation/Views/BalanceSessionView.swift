//
//  BalanceSessionView.swift
//  Itera
//
//  Created by Gracia A on 02/11/2026.
//

import SwiftUI

struct BalanceSessionView: View {
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
                    metrics: model.snapshot.metrics,
                    goal: model.snapshot.goal,
                    collectedFruit: model.snapshot.deliveredFruit,
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
                    BalanceFruitOverlay(
                        snapshot: model.snapshot,
                        mirrored: model.frontCamera,
                        waiting: model.fruitWaiting
                    )
                }
                if model.cameraWaiting {
                    ProgressView("balance.cameraWaiting")
                        .tint(.white)
                        .typography(.headline)
                        .padding(24)
                        .foregroundStyle(.white)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 24))
                }
            }
            .background(TherapyPalette.cameraBackground)
            .clipShape(RoundedRectangle(cornerRadius: 32))
            .overlay {
                RoundedRectangle(cornerRadius: 32)
                    .strokeBorder(borderColor, lineWidth: 6)
            }
            .accessibilityLabel("balance.cameraAccessibility")
        }
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
                    TherapyIconButton(title: "session.camera", symbol: "arrow.triangle.2.circlepath.camera") {
                        model.switchCamera()
                    }
                }

                BalanceDemonstrationView(paused: model.paused || model.cameraWaiting)
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

                Text(LocalizedStringKey(model.fruitCue))
                    .typography(.headline)
                    .foregroundStyle(TherapyPalette.green)

                Text("balance.fruit.count \(Int64(model.snapshot.deliveredFruit))")
                    .typography(.footnote)
                    .foregroundStyle(TherapyPalette.ink)

                if model.snapshot.phase == .calibrating {
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
                        title: "balance.metric.touches",
                        value: "\(model.snapshot.metrics.completedTouches) / \(model.snapshot.goal)"
                    )
                    TherapyMetric(
                        title: "balance.metric.dwell",
                        value: model.snapshot.metrics.midlineDwellTime.formatted(.number.precision(.fractionLength(1))) + "s"
                    )
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

            var midline = Path()
            midline.move(to: point(state.midlineBase))
            midline.addLine(to: point(state.midlineTop))
            context.stroke(
                midline,
                with: .color(torsoColor),
                style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [12, 8])
            )

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
                context.stroke(Path(ellipseIn: rect), with: .color(targetColor), lineWidth: 6)
                if state.targetProgress > 0 {
                    var progress = Path()
                    progress.addArc(
                        center: point(target),
                        radius: radius + 9,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + 360 * state.targetProgress),
                        clockwise: false
                    )
                    context.stroke(progress, with: .color(.green), lineWidth: 8)
                }
                if let remaining = state.holdSecondsRemaining {
                    context.draw(
                        Text(verbatim: String(remaining))
                            .font(.system(size: min(42, radius * 0.72), weight: .bold))
                            .foregroundStyle(.white),
                        at: point(target)
                    )
                }
            }

            if let trackedWrist = state.wrist {
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
}
