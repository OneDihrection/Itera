//
//  FingerPauseView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI
import UIKit

/// The paused card: where the patient is, elapsed time, and resume or end.
///
/// Recovery messages and caregiver actions (save for later, recalibrate, skip) stay
/// available here, beneath the two main choices.
struct FingerPauseView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @Environment(\.openURL) private var openURL
    /// Ending is destructive, so it takes a second, explicit tap (in place, not a new modal).
    @State private var confirmingEnd = false

    var body: some View {
        Group {
            if let model = dependencies.session {
                pauseCard(model)
                    .environment(\.locale, model.sessionLanguage.locale)
                    .onChange(of: model.paused) { _, paused in
                        if !paused, router.presentedSheets.last?.route == .fingerPause {
                            router.dismissSheet()
                        }
                    }
            }
        }
        .interactiveDismissDisabled()
        .presentationBackground(TherapyPalette.canvas)
        .presentationCornerRadius(40)
        .modifier(FittedSheetSizing())
    }

    // MARK: - Card

    private func pauseCard(_ model: FingerSessionViewModel) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                title
                Text("session.setTitle \(model.activity.set) \(model.exerciseTitle)")
                    .typography(size: 22, weight: .medium, relativeTo: .title3)
                Text(verbatim: model.timeText)
                    .typography(size: 64, weight: .bold, relativeTo: .largeTitle)
                    .monospacedDigit()
                    .accessibilityLabel(Text("session.duration"))
                    .accessibilityValue(Text(verbatim: model.timeText))

                mainActions(model)
                status(model)
                caregiverActions(model)
            }
            .multilineTextAlignment(.center)
            .padding(36)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(TherapyPalette.ink)
        .accessibilityAddTraits(.isModal)
    }

    private var title: some View {
        HStack(spacing: 16) {
            Image(systemName: "pause.fill")
                .typography(size: 22, weight: .bold)
                .frame(width: 52, height: 52)
                .background(TherapyPalette.panel, in: Circle())
                .accessibilityHidden(true)
            Text("session.pausedTitle")
                .typography(size: 36, weight: .bold, relativeTo: .largeTitle)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private func mainActions(_ model: FingerSessionViewModel) -> some View {
        if confirmingEnd {
            VStack(spacing: 14) {
                Text("session.endConfirmMessage")
                    .typography(size: 20, weight: .regular, relativeTo: .body)
                    .foregroundStyle(TherapyPalette.muted)
                HStack(spacing: 16) {
                    TherapyButton(title: "session.endCancel", secondary: true, pill: true) {
                        confirmingEnd = false
                    }
                    TherapyButton(title: "session.endConfirm", destructive: true, pill: true) {
                        model.finish()
                    }
                }
            }
            .padding(.top, 8)
        } else {
            HStack(spacing: 16) {
                TherapyButton(title: "session.endSession", secondary: true, pill: true) {
                    confirmingEnd = true
                }
                TherapyButton(
                    title: "session.resumeExercise",
                    symbol: "play.fill",
                    disabled: !model.canResume,
                    pill: true
                ) {
                    model.handleCommand(.resume)
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Status and recovery

    @ViewBuilder
    private func status(_ model: FingerSessionViewModel) -> some View {
        if model.voiceEnabled {
            TherapyStatus(title: "voice.pauseListening", symbol: "mic.fill")
        }

        if model.trackingRecoveryPaused && model.canResume {
            TherapyStatus(title: "recovery.ready", symbol: "checkmark.circle.fill")
        } else if let key = model.recoveryPanelKey {
            VStack(spacing: 12) {
                TherapyError(key: key)
                if model.needsPermissionSettings {
                    TherapyButton(title: "recovery.openSettings", symbol: "gearshape", pill: true) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
                TherapyButton(
                    title: model.needsPermissionSettings ? "recovery.checkAgain" : "action.retry",
                    symbol: "arrow.clockwise",
                    secondary: true,
                    disabled: model.saving || model.recovering,
                    pill: true
                ) {
                    Task { await model.retryRecovery() }
                }
            }
        }
    }

    private func caregiverActions(_ model: FingerSessionViewModel) -> some View {
        ViewThatFits {
            HStack(spacing: 8) {
                caregiverButtons(model)
            }
            VStack(spacing: 4) {
                caregiverButtons(model)
            }
        }
    }

    @ViewBuilder
    private func caregiverButtons(_ model: FingerSessionViewModel) -> some View {
        TherapyTextButton(title: "action.later", symbol: "bookmark", disabled: model.saving) {
            Task {
                if await model.saveForLater() {
                    router.dismissSheet()
                    router.dismissFullScreenCover()
                    await dependencies.refreshHomes()
                }
            }
        }
        TherapyTextButton(title: "action.recalibrate", symbol: "scope") {
            model.retryCalibration()
        }
        TherapyTextButton(title: "action.skip", symbol: "forward.end") {
            model.skipCurrent()
        }
    }
}

/// Sizes the pause sheet to its card on iPadOS 18 and later; earlier systems keep the
/// standard centered form sheet, whose content scrolls if it does not fit.
private struct FittedSheetSizing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.fitted)
        } else {
            content
        }
    }
}
