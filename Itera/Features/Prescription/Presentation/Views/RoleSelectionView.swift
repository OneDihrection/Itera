//
//  RoleSelectionView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import SwiftUI

/// First launch: the iPad belongs to a doctor or to a patient (ADR-008).
struct TMRoleSelectionView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var choosingDoctor = false
    @State private var doctorName = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                VStack(spacing: 12) {
                    Text("role.title")
                        .typography(size: 44, weight: .bold, relativeTo: .largeTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text("role.subtitle")
                        .typography(.body)
                        .foregroundStyle(TherapyPalette.muted)
                }
                .multilineTextAlignment(.center)

                HStack(alignment: .top, spacing: 24) {
                    roleCard(
                        title: "role.patient",
                        detail: "role.patientDetail",
                        symbol: "figure.mind.and.body",
                        selected: !choosingDoctor
                    ) {
                        choosingDoctor = false
                    }
                    roleCard(
                        title: "role.doctor",
                        detail: "role.doctorDetail",
                        symbol: "stethoscope",
                        selected: choosingDoctor
                    ) {
                        choosingDoctor = true
                    }
                }

                if choosingDoctor {
                    TextField("role.doctorName", text: $doctorName)
                        .textContentType(.name)
                        .typography(.body)
                        .padding(18)
                        .background(TherapyPalette.panel, in: RoundedRectangle(cornerRadius: 18))
                        .frame(maxWidth: 520)
                }

                TMTherapyButton(
                    title: "role.continue",
                    symbol: "arrow.right",
                    disabled: choosingDoctor && trimmedName.isEmpty,
                    prominent: true,
                    action: confirm
                )
            }
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            .padding(48)
        }
        .foregroundStyle(TherapyPalette.ink)
        .background(TherapyPalette.canvas)
    }

    private var trimmedName: String {
        doctorName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func confirm() {
        if choosingDoctor {
            dependencies.doctor.doctorName = trimmedName
            dependencies.role = .doctor
        } else {
            dependencies.role = .patient
        }
    }

    private func roleCard(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: symbol)
                    .typography(size: 44, weight: .regular, relativeTo: .largeTitle)
                    .foregroundStyle(TherapyPalette.brand)
                Text(title)
                    .typography(size: 28, weight: .bold, relativeTo: .title2)
                Text(detail)
                    .typography(.body)
                    .foregroundStyle(TherapyPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
            .background(TherapyPalette.planCard, in: RoundedRectangle(cornerRadius: 28))
            .overlay {
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(selected ? TherapyPalette.brand : .clear, lineWidth: 4)
            }
            .contentShape(RoundedRectangle(cornerRadius: 28))
        }
        .buttonStyle(TMTherapySoundButtonStyle())
        .foregroundStyle(TherapyPalette.ink)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
