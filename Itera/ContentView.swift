//
//  ContentView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct TMContentView: View {
    @Environment(AppDependencies.self) private var dependencies

    /// The role chosen on first launch decides the whole app (ADR-008).
    var body: some View {
        switch dependencies.role {
        case nil:
            TMRoleSelectionView()
        case .doctor:
            TMDoctorHomeView()
        case .patient:
            TMHomeView()
        }
    }
}
