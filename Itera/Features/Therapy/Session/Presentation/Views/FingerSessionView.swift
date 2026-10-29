//
//  FingerSessionView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct FingerSessionView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let model = dependencies.session {
                session(model)
                    .task { await model.start() }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active {
                            model.foreground()
                        }
                        else if phase == .background {
                            model.background()
                        }
                    }
                    .onChange(of: model.needsReflection) { _, finished in
                        if finished {
                            router.replaceFullScreenCover(with: .reflection)
                        }
                    }
            }
        }
        .interactiveDismissDisabled()
    }

    private func session(_ model: FingerSessionViewModel) -> some View {
        VStack(spacing: 18) {
            header(model)
            stage(model)
            if model.waitingForCamera && !model.paused {
                TherapyStatus(title: "camera.waiting", symbol: "video.slash")
            }
            instruction(model)
        }
        .padding(24)
        .background(TherapyPalette.cream)
        .accessibilityHidden(model.activity.phase == .countdown || model.paused)
        .overlay {
            if model.activity.phase == .countdown {
                TherapyCountdown(remaining: model.activity.remaining, total: 3,
                                 pause: model.pause, stop: { model.finish() })
                    .ignoresSafeArea()
            }
        }
        .overlay {
            if model.paused {
                pausePanel(model)
            }
        }
        .statusBarHidden(model.activity.phase == .countdown && !model.paused)
    }

    private func header(_ model: FingerSessionViewModel) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(model.stageKey)).typography(.footnote)
                    .foregroundStyle(TherapyPalette.primary)
                Text(LocalizedStringKey(model.activity.kind.title)).typography(.title)
            }
            Spacer(minLength: 8)
            if model.activity.phase == .active || model.activity.phase == .feedback || model.activity.phase == .rest {
                TherapyMetric(title: "session.time", value: model.timeText).frame(width: 100)
                TherapyMetric(title: "session.set", value: "\(model.activity.set)/\(model.routine.sets)").frame(width: 80)
                TherapyMetric(title: "session.repetitions", value: "\(model.activity.repetitions)/\(model.routine.repetitions)").frame(width: 115)
            }
            TherapyIconButton(title: "action.pause", symbol: "pause.fill", size: 92) {
                model.handleCommand(.pause)
            }
        }
        .foregroundStyle(TherapyPalette.ink)
    }

    private func stage(_ model: FingerSessionViewModel) -> some View {
        ZStack {
            // The single preview stays mounted beneath every phase-specific composition.
            camera(model)
                .accessibilityHidden([.demonstration, .feedback, .rest].contains(model.activity.phase))
            if model.activity.phase == .demonstration {
                demonstration(model)
            } else if model.activity.phase == .feedback {
                VStack(spacing: 20) {
                    TherapyCelebration().id(model.celebrationID).frame(height: 250)
                    Text("session.setComplete").typography(.largeTitle)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(TherapyPalette.cream)
            } else if model.activity.phase == .rest {
                rest(model)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rest(_ model: FingerSessionViewModel) -> some View {
        ZStack {
            TherapyRestBackdrop(paused: model.paused || model.waitingForCamera)
            VStack(spacing: 20) {
                Text("stage.rest").typography(.title)
                ZStack {
                    TherapyProgressRing(progress: model.activity.remaining / Double(model.routine.restSeconds))
                    Text(verbatim: String(model.countdown)).typography(size: 100, weight: .bold)
                        .monospacedDigit().contentTransition(.numericText(countsDown: true))
                }.frame(width: 250, height: 250)
                Text("rest.reassurance").typography(.body).foregroundStyle(TherapyPalette.muted)
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func camera(_ model: FingerSessionViewModel) -> some View {
        ZStack(alignment: .topTrailing) {
            TherapyPalette.cameraBackground
            HandCameraPreview(camera: model.camera, ready: model.previewReady)
                .accessibilityLabel("camera.preview")
            if let evidence = model.evidence {
                FingerLandmarkOverlay(evidence: evidence,
                                      progress: model.activity.progress,
                                      calibrating: model.activity.phase == .baseline || model.activity.phase == .target)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    TherapyStatus(title: LocalizedStringKey(model.cameraMessage),
                                  symbol: model.trackingReady ? "checkmark.circle.fill" : "viewfinder",
                                  color: TherapyPalette.primary)
                        .background(TherapyPalette.surface, in: Capsule())
                    Text(LocalizedStringKey(model.routine.side.title)).typography(.headline)
                        .padding(14).background(TherapyPalette.surface, in: Capsule())
                    Spacer()
                    if !model.trackingReady {
                        Text("camera.hint").typography(.title2)
                            .foregroundStyle(.white).padding(22)
                            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 20))
                    }
                }
                Spacer(minLength: 16)
                if [.baseline, .target, .active].contains(model.activity.phase) {
                    example(model)
                        .frame(width: 250, height: 265)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                }
            }.padding(20)
            if model.activity.phase == .active && model.trackingReady {
                VStack {
                    Spacer()
                    movementGuide(model)
                }.frame(maxWidth: .infinity).padding(20)
            }
        }
    }

    private func movementGuide(_ model: FingerSessionViewModel) -> some View {
        HStack(spacing: 18) {
            Label("guide.start", systemImage: "circle")
            ProgressView(value: model.activity.movementFraction)
                .tint(TherapyPalette.primary)
                .accessibilityLabel("guide.position")
            Label("guide.target", systemImage: "scope")
        }
        .typography(.headline)
        .foregroundStyle(TherapyPalette.primary)
        .padding(18)
        .background(TherapyPalette.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 22))
        .frame(maxWidth: 600)
    }

    private func example(_ model: FingerSessionViewModel) -> some View {
        FingerDemonstrationView(
            exercise: model.activity.kind, phase: model.activity.phase,
            returning: model.activity.returning || model.activity.needsStart,
            finger: model.activity.finger, side: model.routine.side, paused: model.paused || model.waitingForCamera
        )
        .background(TherapyPalette.mediaBackground)
        .accessibilityLabel("session.example")
    }

    private func demonstration(_ model: FingerSessionViewModel) -> some View {
        HStack(spacing: 30) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(LocalizedStringKey(model.instructionKey))
                        .typography(size: 42, weight: .bold, relativeTo: .title)
                    Text("demo.followComfortably").typography(.body)
                        .foregroundStyle(TherapyPalette.muted)
                    sessionControls(model)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity)
            example(model).frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottomLeading) {
                    TherapyMetric(title: "session.demoTime", value: model.demonstrationTimeText)
                        .frame(width: 160)
                        .padding(18)
                        .background(TherapyPalette.surface, in: RoundedRectangle(cornerRadius: 22))
                        .padding(18)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28))
        }
        .padding(28)
        .background(TherapyPalette.cream)
    }

    private func sessionControls(_ model: FingerSessionViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                TherapyButton(title: "action.repeat", symbol: "speaker.wave.2.fill", secondary: true, action: model.narrate)
                TherapyButton(title: model.voiceEnabled ? "voice.on" : "voice.off",
                              symbol: model.voiceEnabled ? "mic.fill" : "mic.slash", secondary: true) {
                    Task { await model.setVoice(!model.voiceEnabled) }
                }
            }
            if let key = model.errorKey {
                TherapyError(key: key)
                TherapyButton(title: "action.retry", secondary: true) {
                    Task {
                        await model.retryCamera()
                        await model.saveCheckpoint()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func instruction(_ model: FingerSessionViewModel) -> some View {
        if model.activity.phase != .demonstration {
            VStack(spacing: 14) {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey(model.instructionKey))
                            .typography(size: 36, weight: .bold, relativeTo: .title)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 14) {
                            if model.activity.kind.isSequential && [.baseline, .target, .active].contains(model.activity.phase) {
                                Text(LocalizedStringKey(model.fingerKey)).typography(.headline)
                            }
                            if [.baseline, .target, .active].contains(model.activity.phase) {
                                Text(LocalizedStringKey(model.liveFeedbackKey)).typography(.callout)
                                    .foregroundStyle(TherapyPalette.primary)
                            }
                        }
                    }
                    Spacer(minLength: 12)
                    Button(action: model.narrate) {
                        Image(systemName: "speaker.wave.2.fill").typography(.title2)
                            .frame(width: 68, height: 68)
                            .background(TherapyPalette.surface, in: Circle())
                    }
                    .buttonStyle(TherapySoundButtonStyle()).accessibilityLabel("action.repeat")
                    Button {
                        Task { await model.setVoice(!model.voiceEnabled) }
                    } label: {
                        Image(systemName: model.voiceEnabled ? "mic.fill" : "mic.slash")
                            .typography(.title2).frame(width: 68, height: 68)
                            .background(TherapyPalette.surface, in: Circle())
                    }
                    .buttonStyle(TherapySoundButtonStyle())
                    .accessibilityLabel(model.voiceEnabled ? "voice.on" : "voice.off")
                }
                if [.baseline, .target, .active].contains(model.activity.phase) {
                    ProgressView(value: model.activity.progress).tint(TherapyPalette.primary)
                        .accessibilityLabel("session.holdProgress")
                }
                if let key = model.errorKey {
                    HStack {
                        TherapyError(key: key)
                        TherapyButton(title: "action.retry", secondary: true) {
                            Task { await model.retryCamera() }
                        }.frame(width: 160)
                    }
                }
            }
            .foregroundStyle(TherapyPalette.ink)
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(TherapyPalette.secondary, in: RoundedRectangle(cornerRadius: 28))
        }
    }

    private func pausePanel(_ model: FingerSessionViewModel) -> some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            ScrollView {
                TherapyCard {
                    VStack(spacing: 22) {
                        Text("session.paused").typography(.largeTitle)
                        Text(LocalizedStringKey(model.activity.kind.title)).typography(.title2)
                        HStack {
                            TherapyMetric(title: "session.time", value: model.timeText)
                            TherapyMetric(title: "session.set", value: "\(model.activity.set)/\(model.routine.sets)")
                            TherapyMetric(title: "session.repetitions", value: "\(model.activity.repetitions)/\(model.routine.repetitions)")
                        }
                        if model.voiceEnabled {
                            TherapyStatus(title: "voice.pauseListening", symbol: "mic.fill")
                        }
                        if model.voiceNeedsAcknowledgment {
                            TherapyError(key: "voice.unavailable")
                            TherapyButton(title: "voice.useTouch", secondary: true) { model.acknowledgeTouch() }
                        }
                        if let key = model.errorKey {
                            TherapyError(key: key)
                            if key == "storage.error" {
                                TherapyButton(title: "action.retry", secondary: true) {
                                    Task { await model.saveCheckpoint() }
                                }
                            }
                        }
                        TherapyButton(title: "action.resume", symbol: "play.fill",
                                      disabled: !model.canResume) { model.handleCommand(.resume) }
                        TherapyButton(title: "action.later", symbol: "bookmark", secondary: true, disabled: model.saving) {
                            Task {
                                if await model.saveForLater() {
                                    router.dismissFullScreenCover()
                                    await dependencies.home.refresh()
                                }
                            }
                        }
                        TherapyButton(title: "action.recalibrate", secondary: true) { model.retryCalibration() }
                        TherapyButton(title: "action.skip", secondary: true) { model.skipCurrent() }
                        TherapyButton(title: "action.end", symbol: "stop.fill", destructive: true) { model.finish() }
                    }
                }
                .frame(maxWidth: 660).padding(32).frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(TherapyPalette.ink)
        .accessibilityAddTraits(.isModal)
    }
}

private struct FingerLandmarkOverlay: View {
    let evidence: HandEvidence
    let progress: Double
    let calibrating: Bool

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / evidence.width, geometry.size.height / evidence.height)
            let width = evidence.width * scale
            let height = evidence.height * scale
            let origin = CGPoint(x: (geometry.size.width - width) / 2, y: (geometry.size.height - height) / 2)
            if calibrating, evidence.points.count == 21, evidence.points[0].confidence >= 0.5 {
                TherapyProgressRing(progress: progress, lineWidth: 7)
                    .frame(width: 72, height: 72)
                    .background(TherapyPalette.surface.opacity(0.85), in: Circle())
                    .position(point(0, width: width, height: height, origin: origin))
            }
            Canvas { context, _ in
                for base in [1, 5, 9, 13, 17] {
                    let chain = [0, base, base + 1, base + 2, base + 3]
                    for pair in zip(chain, chain.dropFirst()) {
                        guard evidence.points[pair.0].confidence >= 0.5,
                              evidence.points[pair.1].confidence >= 0.5 else { continue }
                        var path = Path()
                        path.move(to: point(pair.0, width: width, height: height, origin: origin))
                        path.addLine(to: point(pair.1, width: width, height: height, origin: origin))
                        context.stroke(path, with: .color(TherapyPalette.secondary), lineWidth: 4)
                    }
                }
                for index in evidence.points.indices where evidence.points[index].confidence >= 0.5 {
                    let p = point(index, width: width, height: height, origin: origin)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.white))
                }
            }
            ForEach(Array([0, 4, 8, 12, 16, 20].enumerated()), id: \.offset) { number, joint in
                if evidence.points[joint].confidence >= 0.5 {
                    Text(verbatim: String(number)).typography(size: 20, weight: .bold)
                        .foregroundStyle(TherapyPalette.ink).frame(width: 34, height: 34)
                        .background(TherapyPalette.mint, in: Circle())
                        .position(point(joint, width: width, height: height, origin: origin))
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func point(_ index: Int, width: Double, height: Double, origin: CGPoint) -> CGPoint {
        let p = evidence.points[index]
        return CGPoint(x: origin.x + (1 - p.x) * width, y: origin.y + (1 - p.y) * height)
    }
}
