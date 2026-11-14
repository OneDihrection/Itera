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
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.selected.rawValue
    @AppStorage(BodyPoseBackend.storageKey) private var bodyBackend = BodyPoseBackend.vision2D.rawValue
    @AppStorage(HandPoseBackend.storageKey) private var handBackend = HandPoseBackend.vision.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @State private var voice: NarrationVoice.Summary?
    @State private var confirmingSignOut = false

    var body: some View {
        @Bindable var home = dependencies.home
        @Bindable var plan = dependencies.dailyPlan

        Form {
            exerciseSection
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
            trackingSection
            Section {
                Button("role.signOut", role: .destructive) {
                    confirmingSignOut = true
                }
                .frame(minHeight: 64)
            } footer: {
                Text("role.signOutMessage").typography(.body)
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
        .modifier(TMSignOutConfirmation(isPresented: $confirmingSignOut))
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

    // MARK: - Exercise

    /// The saved finger routine the plan page edits. Only the doctor sets sides, sets, repetitions
    /// and rest in patient mode (ADR-008), so the section is hidden there.
    @ViewBuilder
    private var exerciseSection: some View {
        @Bindable var home = dependencies.home
        @Bindable var plan = dependencies.dailyPlan

        if dependencies.role != .patient {
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
        }
    }

    // MARK: - Tracking

    /// Trial switches for the detectors; every exercise keeps its rules with either choice.
    private var trackingSection: some View {
        Section {
            Picker("tracking.bodyBackend", selection: $bodyBackend) {
                ForEach(BodyPoseBackend.allCases) { backend in
                    Text(LocalizedStringKey(backend.titleKey)).tag(backend.rawValue)
                }
            }
            .frame(minHeight: 64)
            Picker("tracking.handBackend", selection: $handBackend) {
                ForEach(HandPoseBackend.allCases.filter(\.isAvailable)) { backend in
                    Text(LocalizedStringKey(backend.titleKey)).tag(backend.rawValue)
                }
            }
            .frame(minHeight: 64)
        } header: {
            Text("tracking.title").typography(.headline)
        } footer: {
            Text("tracking.help").typography(.body)
        }
        .onChange(of: bodyBackend) { dependencies.applyTrackingBackends() }
        .onChange(of: handBackend) { dependencies.applyTrackingBackends() }
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
