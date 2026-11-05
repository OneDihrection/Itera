//
//  PracticePreferencesView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct PracticePreferencesView: View {
    @Environment(NavigationRouter.self) private var router
    @AppStorage(PracticePreferences.gardenActivities) private var gardenActivities = true
    @AppStorage(PracticePreferences.calmMode) private var calmMode = false
    @AppStorage(PracticePreferences.buttonSounds) private var buttonSounds = true

    @AppStorage(PracticePreferences.celebrationSounds) private var celebrationSounds = true

    var body: some View {
        Form {
            Section {
                Toggle("garden.enabled", isOn: $gardenActivities)
                    .frame(minHeight: 64)
            } footer: {
                Text("garden.settingsHelp").typography(.body)
            }
            Section {
                Toggle("cognitive.calm", isOn: $calmMode)
                    .frame(minHeight: 64)
            } footer: {
                Text("cognitive.calmHelp").typography(.body)
            }
            Section {
                Toggle("cognitive.clicks", isOn: $buttonSounds)
                    .frame(minHeight: 64)
                Toggle("cognitive.celebrationSounds", isOn: $celebrationSounds)
                    .frame(minHeight: 64)
            } footer: {
                Text("cognitive.soundHelp").typography(.body)
            }
            Section {
                DisclosureGroup("garden.assetCredits") {
                    Text("garden.assetAttribution")
                        .typography(.body)
                }
            }
        }
        .typography(.body)
        .tint(TherapyPalette.green)
        .navigationTitle("cognitive.settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("action.done") { router.dismissSheet() }
                    .typography(.headline)
                    .frame(minHeight: 64)
            }
        }
        .presentationDetents([.large])
    }
}
