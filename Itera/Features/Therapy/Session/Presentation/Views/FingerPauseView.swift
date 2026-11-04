//
//  FingerPauseView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI
import UIKit

struct FingerPauseView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let model = dependencies.session {
                pausePanel(model)
                    .environment(\.locale, model.sessionLanguage.locale)
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
                        if model.trackingRecoveryPaused && model.canResume {
                            TherapyStatus(title: "recovery.ready", symbol: "checkmark.circle.fill")
                        } else if let key = model.recoveryPanelKey {
                            TherapyError(key: key)
                            if model.needsPermissionSettings {
                                TherapyButton(title: "recovery.openSettings", symbol: "gearshape") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        openURL(url)
                                    }
                                }
                            }
                            TherapyButton(
                                title: model.needsPermissionSettings ? "recovery.checkAgain" : "action.retry",
                                symbol: "arrow.clockwise", secondary: true,
                                disabled: model.saving || model.recovering
                            ) {
                                Task { await model.retryRecovery() }
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
