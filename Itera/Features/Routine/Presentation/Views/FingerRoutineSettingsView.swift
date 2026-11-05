//
//  FingerRoutineSettingsView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct FingerRoutineSettingsView: View {
    @AppStorage(ExerciseMusicTrack.storageKey) private var musicTrack = ExerciseMusicTrack.defaultValue
    let category: ExerciseCategory
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        @Bindable var home = dependencies.homeModel(for: category)
        Form {
            Section("plan.side") {
                Picker("plan.side", selection: $home.routine.side) {
                    ForEach(TrainingSide.allCases) { side in
                        Text(LocalizedStringKey(side.title))
                            .typography(.body)
                            .frame(minHeight: 64)
                            .tag(side)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("plan.amountShort") {
                TherapyNumberControl(title: "plan.setsShort", value: $home.routine.sets, range: 1...5, showsBackground: false)
                TherapyNumberControl(title: "plan.repsShort", value: $home.routine.repetitions, range: 1...20, showsBackground: false)
                TherapyNumberControl(title: "plan.restSeconds", value: $home.routine.restSeconds, range: 5...120, step: 5, showsBackground: false)
            }
            Section("plan.audioShort") {
                Toggle("plan.voice", isOn: $home.routine.voiceControl)
                Picker("music.title", selection: $musicTrack) {
                    ForEach(ExerciseMusicTrack.allCases) { track in
                        Text(LocalizedStringKey(track.titleKey)).tag(track.rawValue)
                    }
                }
                .frame(minHeight: 64)
            }
            Section {
                DisclosureGroup("plan.caregiverShort") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("plan.guidance")
                        Text("plan.voiceNote")
                        Text("home.position")
                    }
                    .typography(.body).foregroundStyle(TherapyPalette.muted)
                    .padding(.vertical, 12)
                }
            }
            if let key = home.errorKey {
                Section { TherapyError(key: key) }
            }
        }
        .typography(.body)
        .tint(TherapyPalette.green)
        .navigationTitle("plan.edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("action.done") {
                    Task {
                        if await home.saveRoutine() {
                            router.dismissSheet()
                        }
                    }
                }
                .typography(.headline).frame(minHeight: 44)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onDisappear { Task { _ = await home.saveRoutine() } }
    }
}
