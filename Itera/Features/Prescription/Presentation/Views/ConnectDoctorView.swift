//
//  ConnectDoctorView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import SwiftUI

/// Patient mode: scanning the doctor's code in the clinic, then explicit consent.
struct TMConnectDoctorView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @State private var typedCode = ""
    @State private var confirmingLeave = false

    private var care: PatientCareViewModel { dependencies.patientCare }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                content
            }
            .multilineTextAlignment(.center)
            .padding(40)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(TherapyPalette.ink)
        .navigationTitle("care.connectTitle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("action.done") {
                    care.dismissConnection()
                    router.dismissSheet()
                }
            }
        }
        .confirmationDialog("care.leaveTitle", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("care.leave", role: .destructive) {
                Task {
                    await care.leaveDoctor()
                    dependencies.applyPrescription()
                }
            }
        } message: {
            Text("care.leaveMessage")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch care.connection {
        case .idle, .failed:
            if let link = care.link {
                currentDoctor(link)
                Divider()
            }
            scanner
        case .checking, .connecting:
            ProgressView()
                .controlSize(.large)
            Text(care.connection == .checking ? "care.checking" : "care.connecting")
                .typography(.headline)
        case .consent(let doctorName, let replacing):
            consent(doctorName: doctorName, replacing: replacing)
        case .connected:
            TMTherapyCompletionMark(tint: TherapyPalette.brand)
            Text("care.connected \(care.link?.doctorName ?? "")").typography(.title2)
        }
    }

    private func currentDoctor(_ link: PatientCareLink) -> some View {
        VStack(spacing: 12) {
            Text("care.currentDoctor \(link.doctorName)").typography(.headline)
            TMTherapyTextButton(title: "care.leave") { confirmingLeave = true }
        }
    }

    @ViewBuilder
    private var scanner: some View {
        Text("care.scanInstructions")
            .typography(.body)
            .foregroundStyle(TherapyPalette.muted)

        if case .failed(let key) = care.connection {
            TMTherapyError(key: key, detail: care.errorDetail)
        }

        if TMTherapyQRScanner.isAvailable {
            TMTherapyQRScanner { code in
                Task { await care.check(code: code) }
            }
            .frame(height: 360)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }

        VStack(spacing: 12) {
            Text("care.typeCode").typography(.subheadline)
            TextField("care.codePlaceholder", text: $typedCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .typography(size: 26, weight: .bold, relativeTo: .title)
                .monospaced()
                .padding(16)
                .background(TherapyPalette.panel, in: RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: 560)
            TMTherapyButton(title: "care.connect", symbol: "link", disabled: CareChannel(code: typedCode) == nil, pill: true) {
                Task { await care.check(code: typedCode) }
            }
            .frame(maxWidth: 320)
        }
    }

    /// The explicit consent required for sharing health data (ADR-008, step 4).
    private func consent(doctorName: String, replacing: String?) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "stethoscope")
                .typography(size: 56, weight: .regular, relativeTo: .largeTitle)
                .foregroundStyle(TherapyPalette.brand)
                .accessibilityHidden(true)

            Text("care.consentTitle \(doctorName)")
                .typography(size: 30, weight: .bold, relativeTo: .title)

            VStack(alignment: .leading, spacing: 14) {
                Label("care.consentSees", systemImage: "chart.bar.xaxis")
                Label("care.consentAssigns", systemImage: "list.bullet.clipboard")
                Label("care.consentNotShared", systemImage: "video.slash")
            }
            .typography(.body)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(TherapyPalette.planCard, in: RoundedRectangle(cornerRadius: 24))

            if let replacing {
                TMTherapyError(key: String(localized: "care.replacing \(replacing)", bundle: AppLanguage.selected.resourceBundle))
            }

            HStack(spacing: 16) {
                TMTherapyButton(title: "care.decline", secondary: true, pill: true) {
                    care.decline()
                }
                TMTherapyButton(title: "care.accept", symbol: "checkmark", pill: true, brand: true) {
                    Task {
                        await care.accept()
                        dependencies.applyPrescription()
                    }
                }
            }
        }
    }
}
