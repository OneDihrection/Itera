//
//  FingerPauseDialog.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI
import UIKit

/// "Latihan dijeda" over the finger session: where the patient is, practice time, and resume
/// or end. It is a layer inside the session rather than a sheet, so the camera stays mounted.
///
/// Recovery messages and caregiver actions (save for later, recalibrate, skip) stay available
/// beneath the two main choices.
struct FingerPauseDialog: View {
    let model: FingerSessionViewModel
    /// Opens on the end confirmation when End was tapped on the live screen.
    var confirmingEndInitially = false
    let onResume: () -> Void

    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @Environment(\.openURL) private var openURL

    var body: some View {
        TherapyPauseDialog(
            setLabel: Text("session.setNumber \(model.activity.set)"),
            title: Text(verbatim: model.exerciseTitle),
            elapsedSeconds: Int(model.sessionElapsedSeconds),
            resumeDisabled: !model.canResume,
            confirmingEndInitially: confirmingEndInitially,
            onEnd: { model.finish() },
            onResume: {
                onResume()
                model.handleCommand(.resume)
            }
        ) {
            VStack(spacing: 14) {
                status
                caregiverActions
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - Status and recovery

    @ViewBuilder
    private var status: some View {
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

    private var caregiverActions: some View {
        ViewThatFits {
            HStack(spacing: 8) {
                caregiverButtons
            }
            VStack(spacing: 4) {
                caregiverButtons
            }
        }
    }

    @ViewBuilder
    private var caregiverButtons: some View {
        TherapyTextButton(title: "action.later", symbol: "bookmark", disabled: model.saving) {
            Task {
                if await model.saveForLater() {
                    router.dismissFullScreenCover()
                    // Saving for later also pauses today's plan; Beranda offers to continue.
                    if dependencies.dailyPlan.isRunning {
                        dependencies.dailyPlan.end(router: router)
                    }
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
