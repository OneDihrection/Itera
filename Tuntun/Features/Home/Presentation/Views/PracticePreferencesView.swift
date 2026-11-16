//
//  PracticePreferencesView.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct TMPracticePreferencesView<
    ViewModel: PracticePreferencesViewModelProtocol,
    Builder: PracticePreferencesContentBuildable
>: View {
    @AppStorage(ExerciseMusicTrack.storageKey) private var musicTrack = ExerciseMusicTrack.defaultValue
    @State private var viewModel: ViewModel
    private let builder: Builder
    @Environment(\.buttonFeedback) private var buttonFeedback
    /// The nested Debug plan editor sheet.
    @State private var editingPlan = false
    @AppStorage(PracticePreferences.calmMode) private var calmMode = false
    @AppStorage(PracticePreferences.buttonSounds) private var buttonSounds = true

    @AppStorage(PracticePreferences.celebrationSounds) private var celebrationSounds = true
    @AppStorage(PracticePreferences.patientName) private var patientName = ""
    // Defaults carry over a choice made with the earlier settings.
    @AppStorage(PracticePreferences.replayRecording) private var replayRecording = PracticePreferences.replayRecordingLevel
    @AppStorage(PracticePreferences.videoCensoring) private var videoCensoring = PracticePreferences.videoCensoringChoice
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.selected.rawValue

    init(viewModel: ViewModel, builder: Builder) {
        _viewModel = State(initialValue: viewModel)
        self.builder = builder
    }

    var body: some View {
        Form {
            // The same saved finger routine the plan page edits; a session in progress keeps
            // the snapshot it started with.
            Section {
                Picker("settings.trainingSide", selection: $viewModel.sidePreference) {
                    Text("settings.trainingSideDefault").tag("")
                    Text("session.left").tag(HandSide.left.rawValue)
                    Text("session.right").tag(HandSide.right.rawValue)
                }
                .frame(minHeight: 64)
                TMTherapyNumberControl(title: "plan.setsShort", value: $viewModel.sets, range: 1...5, showsBackground: false)
                TMTherapyNumberControl(title: "plan.repsShort", value: $viewModel.repetitions, range: 1...20, showsBackground: false)
                TMTherapyNumberControl(
                    title: "plan.restSeconds",
                    value: $viewModel.restSeconds,
                    range: 5...120,
                    step: 5,
                    showsBackground: false
                )
            } header: {
                Text("settings.exerciseTitle").typography(.headline)
            } footer: {
                Text("settings.exerciseHelp").typography(.body)
            }
            if let key = viewModel.errorKey {
                Section { TMTherapyError(key: key) }
            }
            Section {
                TMLanguageSelector(language: $language)
                    .frame(minHeight: 64)
            } header: {
                Text("language.title").typography(.headline)
            }
            Section {
                TextField("settings.patientName", text: $patientName)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .frame(minHeight: 64)
            } header: {
                Text("settings.patientNameTitle").typography(.headline)
            } footer: {
                Text("settings.patientNameHelp").typography(.body)
            }
            recordingSection
            Section {
                Toggle("cognitive.calm", isOn: $calmMode)
                    .frame(minHeight: 64)
            } footer: {
                Text("cognitive.calmHelp").typography(.body)
            }
            Section {
                Picker("music.title", selection: $musicTrack) {
                    ForEach(ExerciseMusicTrack.allCases) { track in
                        Text(LocalizedStringKey(track.titleKey)).tag(track.rawValue)
                    }
                }
                .frame(minHeight: 64)
                Toggle("cognitive.clicks", isOn: $buttonSounds)
                    .frame(minHeight: 64)
                Toggle("cognitive.celebrationSounds", isOn: $celebrationSounds)
                    .frame(minHeight: 64)
            } footer: {
                Text("cognitive.soundHelp").typography(.body)
            }
            #if DEBUG
            debugSection
            #endif
        }
        .typography(.body)
        .tint(TherapyPalette.green)
        .navigationTitle("cognitive.settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("action.done") {
                    Task {
                        await viewModel.done()
                    }
                }
                    .typography(.headline)
                    .frame(minHeight: 64)
            }
        }
        .presentationDetents([.large])
        .onDisappear { Task { await viewModel.save() } }
        #if DEBUG
        .sheet(isPresented: $editingPlan) {
            NavigationStack {
                builder.buildDebugPlanEditor()
            }
            .modalEnvironment(buttonFeedback: buttonFeedback)
        }
        #endif
    }

    #if DEBUG
    // MARK: - Debug

    private var debugSection: some View {
        Section {
            TMDebugActionButton(title: "debug.planEditor.open", symbol: "list.bullet") {
                editingPlan = true
            }
        }
    }
    #endif

    // MARK: - Recording

    /// A privacy ladder: no replay, skeleton only, or video with the skeleton. Video hides the
    /// face, the room, both, or (with a warning) nothing. Repetition numbers are kept at every
    /// level.
    private var recordingSection: some View {
        Section {
            Picker("settings.recordingMode", selection: $replayRecording) {
                Text("settings.recordingOff").tag(ReplayRecording.off)
                Text("settings.recordingSkeleton").tag(ReplayRecording.skeleton)
                Text("settings.recordingVideo").tag(ReplayRecording.video)
            }
            .pickerStyle(.inline)

            if replayRecording == .video {
                Picker("settings.videoCensoring", selection: $videoCensoring) {
                    Text("settings.censorFaceOnly").tag(VideoCensoring.face)
                    Text("settings.censorBackgroundOnly").tag(VideoCensoring.background)
                    Text("settings.censorBoth").tag(VideoCensoring.both)
                    Text("settings.censorNone").tag(VideoCensoring.none)
                }
                .frame(minHeight: 64)
            }
        } header: {
            Text("settings.recordingTitle").typography(.headline)
        } footer: {
            recordingFooter
        }
    }

    @ViewBuilder
    private var recordingFooter: some View {
        switch (replayRecording, videoCensoring) {
        case (.off, _):
            Text("settings.recordingOffHelp").typography(.body)
        case (.skeleton, _):
            Text("settings.recordingSkeletonHelp").typography(.body)
        case (.video, .both):
            Text("settings.recordingVideoHelp").typography(.body)
        case (.video, .face):
            visibilityWarning("settings.recordingWarningBackground")
        case (.video, .background):
            visibilityWarning("settings.recordingWarningFace")
        case (.video, .none):
            visibilityWarning("settings.recordingWarningNone")
        }
    }

    private func visibilityWarning(_ key: LocalizedStringKey) -> some View {
        Label(key, systemImage: "exclamationmark.triangle")
            .typography(.body)
            .foregroundStyle(TherapyPalette.warning)
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
@Observable
private final class MockPracticePreferencesViewModel: PracticePreferencesViewModelProtocol {
    var sidePreference = ""
    var sets = 2
    var repetitions = 5
    var restSeconds = 20
    let errorKey: String? = nil

    func done() async {}
    func save() async {}
}

@MainActor
private struct MockPreferencesBuilder: PracticePreferencesContentBuildable {
    @ViewBuilder func buildDebugPlanEditor() -> some View {
        Text(verbatim: "Plan editor")
    }
}

#Preview("Settings") {
    NavigationStack {
        TMPracticePreferencesView(
            viewModel: MockPracticePreferencesViewModel(),
            builder: MockPreferencesBuilder()
        )
    }
}
#endif
