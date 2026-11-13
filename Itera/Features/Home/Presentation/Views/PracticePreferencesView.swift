//
//  PracticePreferencesView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct TMPracticePreferencesView: View {
    @AppStorage(ExerciseMusicTrack.storageKey) private var musicTrack = ExerciseMusicTrack.defaultValue
    @Environment(NavigationRouter.self) private var router
    @Environment(AppDependencies.self) private var dependencies
    @AppStorage(PracticePreferences.calmMode) private var calmMode = false
    @AppStorage(PracticePreferences.buttonSounds) private var buttonSounds = true

    @AppStorage(PracticePreferences.celebrationSounds) private var celebrationSounds = true
    @AppStorage(PracticePreferences.patientName) private var patientName = ""
    // Defaults carry over a choice made with the earlier settings.
    @AppStorage(PracticePreferences.replayRecording) private var replayRecording = PracticePreferences.replayRecordingLevel
    @AppStorage(PracticePreferences.videoCensoring) private var videoCensoring = PracticePreferences.videoCensoringChoice
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.selected.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @State private var voice: NarrationVoice.Summary?

    var body: some View {
        @Bindable var home = dependencies.home
        @Bindable var plan = dependencies.dailyPlan

        Form {
            // The same saved finger routine the plan page edits; a session in progress keeps
            // the snapshot it started with.
            Section {
                Picker("settings.trainingSide", selection: $plan.sidePreference) {
                    Text("settings.trainingSideDefault").tag("")
                    Text("session.left").tag(HandSide.left.rawValue)
                    Text("session.right").tag(HandSide.right.rawValue)
                }
                .frame(minHeight: 64)
                TMTherapyNumberControl(title: "plan.setsShort", value: $home.routine.sets, range: 1...5, showsBackground: false)
                TMTherapyNumberControl(title: "plan.repsShort", value: $home.routine.repetitions, range: 1...20, showsBackground: false)
                TMTherapyNumberControl(
                    title: "plan.restSeconds",
                    value: $home.routine.restSeconds,
                    range: 5...120,
                    step: 5,
                    showsBackground: false
                )
            } header: {
                Text("settings.exerciseTitle").typography(.headline)
            } footer: {
                Text("settings.exerciseHelp").typography(.body)
            }
            if let key = home.errorKey {
                Section { TMTherapyError(key: key) }
            }
            Section {
                TMLanguageSelector(language: $language)
                    .frame(minHeight: 64)
            } header: {
                Text("language.title").typography(.headline)
            }
            voiceSection
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
        }
        .typography(.body)
        .tint(TherapyPalette.green)
        .navigationTitle("cognitive.settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("action.done") {
                    Task {
                        if await dependencies.home.saveRoutine() {
                            router.dismissSheet()
                        }
                    }
                }
                    .typography(.headline)
                    .frame(minHeight: 64)
            }
        }
        .presentationDetents([.large])
        .onDisappear { Task { _ = await dependencies.home.saveRoutine() } }
        .onAppear(perform: refreshVoice)
        .onChange(of: language) { refreshVoice() }
        // A voice downloaded in the iPad's Settings app shows up on return.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshVoice()
            }
        }
    }

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

    // MARK: - Voice

    private var voiceSection: some View {
        Section {
            if let voice {
                LabeledContent {
                    Text(voice.isHighQuality ? "settings.voiceHigh" : "settings.voiceStandard")
                } label: {
                    Text(verbatim: voice.name)
                }
                .frame(minHeight: 64)
            }
        } header: {
            Text("settings.voiceTitle").typography(.headline)
        } footer: {
            Text(voice?.isHighQuality == true ? "settings.voiceGood" : "settings.voiceTip")
                .typography(.body)
        }
    }

    private func refreshVoice() {
        let selected = AppLanguage(rawValue: language) ?? .indonesian
        voice = NarrationVoice.summary(for: selected.speechIdentifier)
    }
}
