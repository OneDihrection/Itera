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
struct TMFingerPauseDialog: View {
    let model: FingerSessionViewModel
    /// Opens on the end confirmation when End was tapped on the live screen.
    var confirmingEndInitially = false
    let onResume: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        TMTherapyPauseDialog(
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
            recovery
        }
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder
    private var recovery: some View {
        if !model.canResume, let key = model.recoveryPanelKey {
            VStack(spacing: 12) {
                TMTherapyError(key: key)
                if model.needsPermissionSettings {
                    TMTherapyButton(title: "recovery.openSettings", symbol: "gearshape", pill: true) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
                TMTherapyButton(
                    title: model.needsPermissionSettings ? "recovery.checkAgain" : "action.retry",
                    secondary: true,
                    disabled: model.saving || model.recovering,
                    pill: true
                ) {
                    Task { await model.retryRecovery() }
                }
            }
        }
    }
}
