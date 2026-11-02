//
//  FingerPauseView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct FingerPauseView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        Group {
            if let model = dependencies.session {
                pausePanel(model)
                    .onChange(of: model.paused) { _, paused in
                        if !paused, router.presentedSheets.last?.route == .fingerPause {
                            router.dismissSheet()
                        }
                    }
            }
        }
        .interactiveDismissDisabled()
        .presentationDetents([.large])
    }

    private func pausePanel(_ model: FingerSessionViewModel) -> some View {
        ZStack {
            TherapyPalette.cream.ignoresSafeArea()
            ScrollView {
                TherapyCard {
                    VStack(spacing: 22) {
                        Text("session.paused").typography(.largeTitle)
                        Text(LocalizedStringKey(model.activity.kind.title)).typography(.title2)
                        HStack {
                            TherapyMetric(title: "session.duration", value: model.timeText)
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
                                    router.dismissSheet()
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
