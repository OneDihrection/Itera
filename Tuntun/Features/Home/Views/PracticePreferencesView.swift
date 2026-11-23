//
//  PracticePreferencesView.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

struct TMPracticePreferencesView<ViewModel: PracticePreferencesViewModelProtocol>: View {
    @AppStorage(ExerciseMusicTrack.storageKey) private var musicTrack = ExerciseMusicTrack.defaultValue
    @State private var viewModel: ViewModel
    @Environment(\.scenePhase) private var scenePhase
    /// Arrange mode: drag handles and show/hide toggles instead of each exercise's settings.
    @State private var arranging = false
    @AppStorage(PracticePreferences.calmMode) private var calmMode = false
    @AppStorage(PracticePreferences.buttonSounds) private var buttonSounds = true

    @AppStorage(PracticePreferences.celebrationSounds) private var celebrationSounds = true
    @AppStorage(PracticePreferences.patientName) private var patientName = ""
    // Defaults carry over a choice made with the earlier settings.
    @AppStorage(PracticePreferences.replayRecording) private var replayRecording = PracticePreferences.replayRecordingLevel
    @AppStorage(PracticePreferences.videoCensoring) private var videoCensoring = PracticePreferences.videoCensoringChoice
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.selected.rawValue

    init(viewModel: ViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            exercisesSection
            restSection
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
        .environment(\.editMode, .constant(arranging ? .active : .inactive))
        .typography(.body)
        .tint(TherapyPalette.green)
        .navigationTitle("cognitive.settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("action.done") {
                    viewModel.done()
                }
                    .typography(.headline)
                    .frame(minHeight: 64)
            }
        }
        .presentationDetents([.large])
        .onAppear { viewModel.refreshPermissions() }
        // Returning from the system Settings updates the voice row.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                return
            }

            viewModel.refreshPermissions()
        }
    }

    // MARK: - Exercises

    /// The one place for exercise preferences, in the plan's order. Normally each exercise folds
    /// its side, sets and repetitions under its name; Arrange shows drag handles and
    /// show/hide switches instead. Every change is saved at once.
    private var exercisesSection: some View {
        Section {
            ForEach(viewModel.layoutEntries) { entry in
                if let item = viewModel.item(for: entry) {
                    if arranging {
                        arrangeRow(entry, item: item)
                    } else {
                        exerciseRow(entry, item: item)
                    }
                }
            }
            .onMove { source, destination in
                viewModel.moveEntries(fromOffsets: source, toOffset: destination)
            }

            if arranging {
                TMTherapyTextButton(title: "settings.resetOrder", symbol: "arrow.counterclockwise") {
                    viewModel.resetLayout()
                }
                .frame(minHeight: 64)
            }
        } header: {
            exercisesHeader
        } footer: {
            Text(arranging ? "settings.arrangeHelp" : "settings.planExercisesHelp")
                .typography(.body)
        }
    }

    private var exercisesHeader: some View {
        HStack {
            Text("settings.planExercisesTitle")
                .typography(.headline)

            Spacer()

            Button(arranging ? "action.done" : "settings.arrange") {
                withAnimation {
                    arranging.toggle()
                }
            }
            .typography(.headline)
            .textCase(nil)
            // Section headers draw text in the secondary style; keep the action visibly tappable.
            .foregroundStyle(TherapyPalette.green)
            .frame(minHeight: 44)
        }
    }

    private func arrangeRow(_ entry: DailyPlanLayout.Entry, item: DailyPlanItem) -> some View {
        Toggle(isOn: shownBinding(for: entry)) {
            Text(LocalizedStringKey(viewModel.titleKey(for: item)))
                .typography(.headline)
        }
        .frame(minHeight: 64)
    }

    private func exerciseRow(_ entry: DailyPlanLayout.Entry, item: DailyPlanItem) -> some View {
        DisclosureGroup {
            exerciseControls(item)
        } label: {
            exerciseLabel(entry, item: item)
        }
        .frame(minHeight: 64)
    }

    private func exerciseLabel(_ entry: DailyPlanLayout.Entry, item: DailyPlanItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(viewModel.titleKey(for: item)))
                .typography(.headline)

            exerciseSummary(entry, item: item)
                .typography(.body)
                .foregroundStyle(.secondary)
        }
        .opacity(isShown(entry, item: item) ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }

    /// Hidden in Arrange, or with 0 sets or repetitions, which also hides the exercise. Its
    /// controls stay open, so raising the count to 1 shows it again.
    private func isShown(_ entry: DailyPlanLayout.Entry, item: DailyPlanItem) -> Bool {
        let counts = viewModel.counts(for: item)

        return entry.isShown
            && counts.sets > 0
            && counts.repetitions > 0
    }

    @ViewBuilder
    private func exerciseSummary(_ entry: DailyPlanLayout.Entry, item: DailyPlanItem) -> some View {
        if isShown(entry, item: item) {
            let counts = viewModel.counts(for: item)

            HStack(spacing: 6) {
                if viewModel.hasSide(item) {
                    Text(sideKey(viewModel.side(for: item)))
                    Text(verbatim: "·")
                }

                Text("plan.sets \(counts.sets)")
                Text(verbatim: "·")
                Text("plan.repetitions \(counts.repetitions)")
            }
        } else {
            Text("settings.hidden")
        }
    }

    @ViewBuilder
    private func exerciseControls(_ item: DailyPlanItem) -> some View {
        if viewModel.hasSide(item) {
            Picker("settings.side", selection: sideBinding(for: item)) {
                Text("session.right").tag(RoutineSides.right)
                Text("session.left").tag(RoutineSides.left)
                Text("settings.side.both").tag(RoutineSides.both)
            }
            .frame(minHeight: 64)
        }

        TMTherapyNumberControl(
            title: "plan.setsShort",
            value: setsBinding(for: item),
            range: DailyPlanOverrides.setsRange,
            showsBackground: false
        )

        TMTherapyNumberControl(
            title: "plan.repsShort",
            value: repetitionsBinding(for: item),
            range: DailyPlanOverrides.repetitionsRange,
            showsBackground: false
        )
    }

    private func sideKey(_ side: RoutineSides) -> LocalizedStringKey {
        switch side {
        case .right:
            return "session.right"
        case .left:
            return "session.left"
        case .both:
            return "settings.side.both"
        }
    }

    private func shownBinding(for entry: DailyPlanLayout.Entry) -> Binding<Bool> {
        Binding(
            get: { entry.isShown },
            set: { viewModel.setShown($0, for: entry) }
        )
    }

    private func sideBinding(for item: DailyPlanItem) -> Binding<RoutineSides> {
        Binding(
            get: { viewModel.side(for: item) },
            set: { viewModel.setSide($0, for: item) }
        )
    }

    private func setsBinding(for item: DailyPlanItem) -> Binding<Int> {
        Binding(
            get: { viewModel.counts(for: item).sets },
            set: { viewModel.setSets($0, for: item) }
        )
    }

    private func repetitionsBinding(for item: DailyPlanItem) -> Binding<Int> {
        Binding(
            get: { viewModel.counts(for: item).repetitions },
            set: { viewModel.setRepetitions($0, for: item) }
        )
    }

    // MARK: - Rest

    /// One short rest between every set of every exercise and one long rest between exercises,
    /// for the whole plan.
    private var restSection: some View {
        Section {
            TMTherapyNumberControl(
                title: "settings.shortRest",
                value: shortRestBinding,
                range: DailyPlanRest.shortRange,
                step: 5,
                showsBackground: false
            )

            TMTherapyNumberControl(
                title: "settings.longRest",
                value: longRestBinding,
                range: DailyPlanRest.longBreathsRange,
                showsBackground: false
            )
        } header: {
            Text("settings.restTitle").typography(.headline)
        } footer: {
            Text("settings.restHelp \(viewModel.longRestBreaths * Int(LongRestBreath.cycleDuration))")
                .typography(.body)
        }
    }

    private var shortRestBinding: Binding<Int> {
        Binding(
            get: { viewModel.shortRestSeconds },
            set: { viewModel.setShortRestSeconds($0) }
        )
    }

    private var longRestBinding: Binding<Int> {
        Binding(
            get: { viewModel.longRestBreaths },
            set: { viewModel.setLongRestBreaths($0) }
        )
    }

    // MARK: - Voice control

    /// Voice control cannot be switched off: the toggle shows whether permissions allow it, and
    /// switching it on while access is missing asks for access or opens the system Settings.
    private var voiceSection: some View {
        Section {
            Toggle("plan.voice", isOn: voiceBinding)
                .frame(minHeight: 64)

            if let actionKey = viewModel.voiceFallback?.actionKey {
                Button(LocalizedStringKey(actionKey)) {
                    Task {
                        await viewModel.resolveVoiceAccess()
                    }
                }
                .frame(minHeight: 64)
            }
        } header: {
            Text("plan.voice").typography(.headline)
        } footer: {
            voiceFooter
        }
    }

    private var voiceBinding: Binding<Bool> {
        Binding {
            viewModel.voiceEnabled
        } set: { enabled in
            guard enabled, !viewModel.voiceEnabled else {
                return
            }

            Task {
                await viewModel.resolveVoiceAccess()
            }
        }
    }

    @ViewBuilder
    private var voiceFooter: some View {
        if let fallback = viewModel.voiceFallback {
            visibilityWarning(LocalizedStringKey(fallback.messageKey))
        } else {
            Text("settings.voiceHelp").typography(.body)
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
}

// MARK: - Previews

#if DEBUG
@MainActor
@Observable
private final class MockPracticePreferencesViewModel: PracticePreferencesViewModelProtocol {
    private let items = Array(DailyPlan.standard.prefix(4))
    private(set) var layoutEntries: [DailyPlanLayout.Entry]
    private var sides: [String: RoutineSides] = [:]
    private var setCounts: [String: Int] = [:]
    private var repetitionCounts: [String: Int] = [:]
    private(set) var shortRestSeconds = 15
    private(set) var longRestBreaths = 6
    let voiceEnabled = false
    let voiceFallback: VoicePermissionFallback? = .openSettings(messageKey: "home.microphoneDenied")

    init() {
        layoutEntries = DailyPlanLayout.standard(Array(DailyPlan.standard.prefix(4))).entries
    }

    func item(for entry: DailyPlanLayout.Entry) -> DailyPlanItem? {
        items.first { $0.id == entry.itemID }
    }

    func titleKey(for item: DailyPlanItem) -> String {
        DailyPlanViewModel.titleKey(for: item.exercise)
    }

    func setShown(_ shown: Bool, for entry: DailyPlanLayout.Entry) {
        guard let index = layoutEntries.firstIndex(where: { $0.itemID == entry.itemID }) else {
            return
        }

        layoutEntries[index].isShown = shown
    }

    func moveEntries(fromOffsets source: IndexSet, toOffset destination: Int) {
        layoutEntries.move(fromOffsets: source, toOffset: destination)
    }

    func resetLayout() {
        layoutEntries = DailyPlanLayout.standard(items).entries
    }

    func hasSide(_ item: DailyPlanItem) -> Bool {
        true
    }

    func side(for item: DailyPlanItem) -> RoutineSides {
        sides[item.id] ?? .both
    }

    func setSide(_ side: RoutineSides, for item: DailyPlanItem) {
        sides[item.id] = side
    }

    func counts(for item: DailyPlanItem) -> (sets: Int, repetitions: Int) {
        (setCounts[item.id] ?? 2, repetitionCounts[item.id] ?? 5)
    }

    func setSets(_ sets: Int, for item: DailyPlanItem) {
        setCounts[item.id] = sets
    }

    func setRepetitions(_ repetitions: Int, for item: DailyPlanItem) {
        repetitionCounts[item.id] = repetitions
    }

    func setShortRestSeconds(_ seconds: Int) {
        shortRestSeconds = seconds
    }

    func setLongRestBreaths(_ breaths: Int) {
        longRestBreaths = breaths
    }

    func done() {}
    func refreshPermissions() {}
    func resolveVoiceAccess() async {}
}

#Preview("Settings") {
    NavigationStack {
        TMPracticePreferencesView(viewModel: MockPracticePreferencesViewModel())
    }
}
#endif
