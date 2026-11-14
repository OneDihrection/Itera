//
//  DoctorHomeView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import SwiftUI

/// Doctor mode's root: every patient, their link state and latest activity.
struct TMDoctorHomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @State private var confirmingSignOut = false

    private var doctor: DoctorCareViewModel { dependencies.doctor }

    var body: some View {
        List {
            if let key = doctor.errorKey {
                Section {
                    TMTherapyError(key: key, detail: doctor.errorDetail)
                    TMTherapyTextButton(title: "action.retry") {
                        doctor.clearError()
                        Task { await refresh() }
                    }
                }
            }

            Section {
                if doctor.patients.isEmpty {
                    Text("doctor.noPatients")
                        .typography(.body)
                        .foregroundStyle(TherapyPalette.muted)
                }

                ForEach(doctor.patients) { patient in
                    Button {
                        router.push(.doctorPatient(patient.id))
                    } label: {
                        patientRow(patient)
                    }
                    .buttonStyle(TMTherapySoundButtonStyle())
                }
            } header: {
                Text("doctor.patients").typography(.headline)
            }
        }
        .navigationTitle(Text("doctor.title \(doctor.doctorName)"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.presentSheet(.doctorAddPatient)
                } label: {
                    Label("doctor.addPatient", systemImage: "person.badge.plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    confirmingSignOut = true
                } label: {
                    Label("role.signOut", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .modifier(TMSignOutConfirmation(isPresented: $confirmingSignOut))
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        await doctor.load()
        await doctor.refreshResults()
    }

    private func patientRow(_ patient: DoctorPatient) -> some View {
        HStack(spacing: 20) {
            Image(systemName: patient.paired ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.clock")
                .typography(size: 34, weight: .regular, relativeTo: .title2)
                .foregroundStyle(patient.paired ? TherapyPalette.brand : TherapyPalette.muted)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: patient.name)
                    .typography(size: 24, weight: .semiBold, relativeTo: .headline)
                Text(patient.paired ? "doctor.paired" : "doctor.notPaired")
                    .typography(.subheadline)
                    .foregroundStyle(TherapyPalette.muted)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                if let latest = patient.latest {
                    Text("doctor.version \(latest.version)").typography(.subheadline)
                } else {
                    Text("doctor.noPrescription").typography(.subheadline)
                }

                if let last = patient.results.first {
                    Text(last.date, format: .dateTime.day().month(.abbreviated))
                        .typography(.footnote)
                        .foregroundStyle(TherapyPalette.muted)
                }
            }
        }
        .foregroundStyle(TherapyPalette.ink)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Add patient

/// Names a new patient, then shows the pairing QR in the same sheet.
struct TMDoctorAddPatientView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @State private var name = ""
    @State private var createdID: UUID?

    var body: some View {
        Group {
            if let createdID {
                TMDoctorPairingView(patientID: createdID)
            } else {
                form
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("doctor.patientName", text: $name)
                    .textContentType(.name)
                    .frame(minHeight: 56)
            } footer: {
                Text("doctor.addPatientHelp").typography(.body)
            }

            if let key = dependencies.doctor.errorKey {
                Section { TMTherapyError(key: key, detail: dependencies.doctor.errorDetail) }
            }
        }
        .typography(.body)
        .navigationTitle("doctor.addPatient")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("action.cancel") { router.dismissSheet() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("doctor.createAndPair") {
                    Task {
                        createdID = await dependencies.doctor.addPatient(named: name)
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || dependencies.doctor.busy)
            }
        }
    }
}

// MARK: - Pairing

/// The clinic pairing screen: a single-use QR code and live progress of the patient's steps.
struct TMDoctorPairingView: View {
    let patientID: UUID
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router

    private var pairing: DoctorCareViewModel.Pairing? {
        dependencies.doctor.pairing.flatMap { $0.patientID == patientID ? $0 : nil }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Text(verbatim: dependencies.doctor.patient(patientID)?.name ?? "")
                    .typography(size: 32, weight: .bold, relativeTo: .title)

                if let pairing {
                    content(pairing)
                } else {
                    TMTherapyButton(title: "doctor.newCode", symbol: "qrcode", pill: true) {
                        dependencies.doctor.startPairing(for: patientID)
                    }
                }
            }
            .multilineTextAlignment(.center)
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(TherapyPalette.ink)
        .navigationTitle("doctor.pairingTitle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(pairing?.status == .paired ? "action.done" : "action.close") {
                    router.dismissSheet()
                }
            }
        }
        .onDisappear {
            if pairing?.status != .paired {
                dependencies.doctor.cancelPairing()
            }
        }
    }

    @ViewBuilder
    private func content(_ pairing: DoctorCareViewModel.Pairing) -> some View {
        switch pairing.status {
        case .waitingForPatient:
            Text("doctor.pairingInstructions")
                .typography(.body)
                .foregroundStyle(TherapyPalette.muted)

            TMTherapyQRCode(text: CareChannel.qrPrefix + pairing.channel.code)

            // The code is the patient's key: shown only here, in person.
            Text(verbatim: pairing.channel.groupedCode)
                .typography(size: 30, weight: .bold, relativeTo: .title)
                .monospaced()
                .textSelection(.enabled)
                .accessibilityLabel(Text("doctor.codeLabel \(pairing.channel.groupedCode)"))

            HStack(spacing: 12) {
                ProgressView()
                Text("doctor.pairingWaiting").typography(.headline)
            }
        case .paired:
            TMTherapyCompletionMark(tint: TherapyPalette.brand)
            Text("doctor.pairedNow").typography(.title2)
        case .expired:
            Text("doctor.codeExpired").typography(.headline)
            TMTherapyButton(title: "doctor.newCode", symbol: "arrow.clockwise", pill: true) {
                dependencies.doctor.startPairing(for: patientID)
            }
        case .failed(let key):
            TMTherapyError(key: key, detail: dependencies.doctor.errorDetail)
            TMTherapyButton(title: "doctor.newCode", symbol: "arrow.clockwise", pill: true) {
                dependencies.doctor.startPairing(for: patientID)
            }
        }
    }
}

// MARK: - Sign out

/// The confirmation shared by doctor and patient mode before returning to the role choice.
struct TMSignOutConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router

    func body(content: Content) -> some View {
        content.confirmationDialog("role.signOutTitle", isPresented: $isPresented, titleVisibility: .visible) {
            Button("role.signOut", role: .destructive) {
                dependencies.signOut(router: router)
            }
        } message: {
            Text("role.signOutMessage")
        }
    }
}
