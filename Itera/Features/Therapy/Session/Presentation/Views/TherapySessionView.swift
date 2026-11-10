//
//  TherapySessionView.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import SwiftUI

struct TMTherapySessionView: View {
    @AppStorage(ExerciseMusicTrack.storageKey) var musicTrack = ExerciseMusicTrack.defaultValue
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    /// Read from UIAccessibility instead of the environment key, which traps on Mac Catalyst.
    @State var voiceOver = UIAccessibility.isVoiceOverRunning
    @ScaledMetric(relativeTo: .largeTitle) var instructionSize = 96.0
    @ScaledMetric(relativeTo: .title3) var calibrationCaptionSize = TMTherapyInstructionBubble.baseFontSize
    @Environment(PermissionManager.self) var permissions
    @Environment(NavigationRouter.self) var router
    @Environment(AppDependencies.self) var dependencies
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PracticePreferences.calmMode) private var calmMode = false
    @State private var celebrationStart: Date?
    @State private var showsCameraRecovery = false
    /// Rest length as first shown, so the light rest ring has a total to count down from.
    @State var restTotal = 0.0
    /// Set when End was tapped on the live screen, so the pause dialog opens on its confirmation.
    @State var endRequested = false
    @State var videoBounds: CGRect?
    @State var model: TherapySessionViewModel

    private var presentationOnly = false

    init(model: TherapySessionViewModel) { _model = State(initialValue: model) }

    #if DEBUG
    init(fixture: SessionSnapshot) {
        _model = State(initialValue: .presentationFixture(fixture))
        presentationOnly = true
    }
    #endif

    var body: some View {
        sessionContent
            .onReceive(
                NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)
            ) { _ in
                voiceOver = UIAccessibility.isVoiceOverRunning
            }
    }

    private var sessionContent: some View {
        GeometryReader { geometry in
            if model.entryFailure {
                VStack(spacing: 24) {
                    Text(LocalizedStringKey(model.entryMessage)).typography(.title)
                    Button("home.retry") {
                        Task { await model.start(permissions: permissions) }
                    }
                    .disabled(model.validating)
                    .buttonStyle(TMSessionButtonStyle())
                    Button("home.openSettings") { model.openSettings() }
                        .buttonStyle(TMSessionButtonStyle())
                    Button("home.back") { leaveWithoutResult() }
                        .buttonStyle(TMSessionButtonStyle())
                }
                .padding(32)
            } else if let summary = model.snapshot.summary, usesLightTheme {
                lightAllDone(summary)
            } else if let summary = model.snapshot.summary {
                VStack(spacing: 12) {
                    header
                    summaryContent(summary)
                    if let error = model.saveFailure { saveError(error) }
                }
                .padding(12)
            } else {
                activityLayout(in: geometry.size)
            }
        }
        .overlay {
            if model.snapshot.summary == nil, !model.entryFailure, hasFullScreenPresentation {
                fullScreenPresentation
            }
        }
        .overlay {
            // Light sessions pause over the screen they were on, which stays mounted beneath.
            if usesLightLayout, model.snapshot.paused, model.snapshot.summary == nil, !model.entryFailure {
                lightPauseDialog
            }
        }
        .overlay {
            if let celebrationStart, !reduceMotion, !calmMode {
                TMSessionCelebration(start: celebrationStart).ignoresSafeArea()
            }
        }
        .onChange(of: model.snapshot.stage) { _, stage in
            if stage == .rest {
                restTotal = Double(model.snapshot.seconds)
            }
        }
        .onChange(of: model.snapshot.summary?.id) { _, id in
            if id != nil, let summary = model.snapshot.summary,
                !summary.stopped, !summary.interrupted {
                celebrationStart = Date()
            }
        }
        .overlay {
            if model.snapshot.summary == nil, !hasFullScreenPresentation {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .strokeBorder(
                        usesLightLayout ? Color.clear : phaseColor,
                        lineWidth: 8
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .environment(\.locale, model.sessionLocale)
        .background(usesLightTheme ? TherapyPalette.canvas : Color.black)
        .foregroundStyle(usesLightTheme ? TherapyPalette.ink : Color.white)
        .toolbar(model.snapshot.summary == nil || usesLightTheme ? .hidden : .visible, for: .navigationBar)
        .navigationTitle(model.snapshot.summary == nil ? "" : "session.summaryTitle")
        .statusBarHidden(!usesLightLayout && model.snapshot.summary == nil)
        .navigationBarBackButtonHidden(model.snapshot.summary == nil || usesLightTheme)
        .task {
            if !presentationOnly { await model.start(permissions: permissions) }
        }
        .task(id: model.snapshot.stage == .preparing) {
            await revealCameraRecoveryAfterDelay()
        }
        .onDisappear { if !presentationOnly { model.exit() } }
        .onChange(of: scenePhase) { _, phase in
            guard !presentationOnly else { return }
            switch phase {
            case .active: model.foreground()
            case .background: model.background()
            case .inactive: break
            @unknown default: model.background()
            }
        }
    }

    /// Arm raise, elbow bend, directional reach and fold towel use the light, finger-exercise
    /// look: the camera beside a side column, with light stage pages.
    ///
    /// This depends on the activity alone, never on the stage: full-screen stages such as the
    /// countdown cover the layout with an overlay, and the camera preview must stay mounted
    /// beneath them (SYSTEM_DESIGN.md section 5).
    var usesLightLayout: Bool {
        guard let kind = model.snapshot.activity?.kind else {
            return false
        }

        return Self.lightKinds.contains(kind)
    }

    private static let lightKinds: Set<TherapyKind> = [.armRaise, .elbowBend, .directionalReach, .foldTowel]

    /// The whole screen is light while a light activity runs. The summary is light only when every
    /// result is, so a routine mixing in cup or sit-to-stand does not flip themes at the end.
    var usesLightTheme: Bool {
        guard let summary = model.snapshot.summary else {
            return usesLightLayout
        }

        return summary.results.allSatisfy { Self.lightKinds.contains($0.activity.kind) }
    }

    var hasFullScreenPresentation: Bool {
        if model.cameraDenied || (model.snapshot.paused && !usesLightLayout) {
            return true
        }
        if model.isStarting {
            return false
        }
        if !model.voiceReady {
            return true
        }
        if model.snapshot.stage == .preparing {
            return model.failure != nil || showsCameraRecovery
        }
        if usesLightLayout, isCalibrationLayout {
            return false
        }
        return model.snapshot.stage == .instruction
            || model.snapshot.stage == .demonstration || model.snapshot.stage == .preparationWait || model.snapshot.stage == .rest
            || model.snapshot.stage == .feedback
            || model.snapshot.presentation?.countdownSeconds != nil
    }

    @ViewBuilder
    private var fullScreenPresentation: some View {
        if model.snapshot.stage == .rest, let breath = model.snapshot.restBreath,
           !model.cameraDenied, model.voiceReady, !model.snapshot.paused || usesLightLayout {
            TMTherapyBreathingRest(
                cue: LocalizedStringKey(breath.phase.key),
                intensity: breath.intensity,
                pause: { model.command(.pause) },
                stop: {
                    if usesLightLayout {
                        requestEnd()
                    } else {
                        model.command(.stop)
                    }
                }
            )
        } else if model.snapshot.stage == .activity,
           let seconds = model.snapshot.presentation?.countdownSeconds,
           model.snapshot.instruction != "calibration.complete",
           !model.cameraDenied, model.voiceReady, !model.snapshot.paused || usesLightLayout {
            TMPracticeCountdown(
                seconds: seconds,
                pause: { model.command(.pause) },
                stop: {
                    if usesLightLayout {
                        requestEnd()
                    } else {
                        model.command(.stop)
                    }
                }
            )
            .ignoresSafeArea()
        } else if usesLightLayout {
            lightStagePage
        } else {
            darkStagePage
        }
    }

    private var darkStagePage: some View {
        TMSessionStageSurface(background: presentationBackground, border: phaseColor) {
            sessionContext
            presentationContent
            trackingStatus
        } controls: {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 16))
                : AnyLayout(HStackLayout(spacing: 24))
            layout {
                Button("session.help") { model.command(.help) }
                Button(model.snapshot.paused ? "session.resume" : "session.pause") {
                    model.command(model.snapshot.paused ? .resume : .pause)
                }
                .disabled(model.snapshot.paused && !model.voiceReady)
                Button("therapy.session.stop") { model.command(.stop) }
            }
            .buttonStyle(TMSessionButtonStyle())
            if let failure = model.failure {
                Text(verbatim: failure).typography(.caption).foregroundStyle(.orange)
            }
            if let error = model.saveFailure { saveError(error) }
        }
    }

    private var sessionContext: some View {
        VStack(spacing: 6) {
            if let activity = model.snapshot.activity {
                HStack(spacing: 16) {
                    Text(kindKey(activity.kind))
                    if activity.hasSide {
                        Text(LocalizedStringKey("side." + activity.side.rawValue))
                    }
                }
                .typography(.title2)
            }
            if model.snapshot.activityCount > 0 {
                Text("cognitive.step \(min(model.snapshot.index + 1, model.snapshot.activityCount)) \(model.snapshot.activityCount)")
                    .typography(.body)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Activity layout

    /// Seconds the camera may take to become ready before recovery buttons are offered.
    private static let cameraRecoveryDelay = 3.0

    private func revealCameraRecoveryAfterDelay() async {
        showsCameraRecovery = false

        guard model.snapshot.stage == .preparing else {
            return
        }

        try? await Task.sleep(for: .seconds(Self.cameraRecoveryDelay))

        guard !Task.isCancelled else {
            return
        }

        showsCameraRecovery = true
    }

    /// One layout for every activity stage. The camera keeps the same position in the view tree
    /// whichever bars surround it, so SwiftUI never rebuilds the preview when the layout mode or
    /// a full-screen stage changes.
    @ViewBuilder
    private func activityLayout(in size: CGSize) -> some View {
        if usesLightLayout {
            lightLayout
        } else {
            darkLayout(in: size)
        }
    }

    private func darkLayout(in size: CGSize) -> some View {
        let cameraHeight = size.height * (dynamicTypeSize.isAccessibilitySize ? 0.45 : 0.6)
        let barsHeight = max(0, size.height - cameraHeight - 40)

        return VStack(spacing: 8) {
            ScrollView { header.frame(maxWidth: .infinity) }
                .frame(height: barsHeight * 0.4)

            camera
                .frame(height: cameraHeight)

            ScrollView {
                trackingStatus
                if model.snapshot.stage != .preparing {
                    footer
                }
                if let error = model.saveFailure { saveError(error) }
            }
            .frame(height: barsHeight * 0.6)
        }
        .padding(12)
        .accessibilityHidden(hasFullScreenPresentation)
    }

    var trackingStatus: some View {
        Text("session.cameraWait")
            .typography(.body)
            .frame(maxWidth: .infinity)
            .opacity(model.snapshot.cameraWaiting ? 1 : 0)
            .accessibilityHidden(!model.snapshot.cameraWaiting)
    }

    private var presentationBackground: Color {
        // Keep a steady surface across stages and temporary tracking interruptions.
        Color(white: 0.08)
    }

    @ViewBuilder
    private var presentationContent: some View {
        if model.cameraDenied {
            recoveryPanel("therapy.session.cameraDenied")
        } else if model.snapshot.paused {
            ScrollView {
                TMSessionPanel(light: usesLightTheme) {
                    VStack(spacing: 16) {
                        Text("session.paused").typography(.therapyPause)
                        Text("session.resumeHelp")
                        if let failure = model.failure {
                            Text(verbatim: failure).typography(.caption).foregroundStyle(.orange)
                        }
                        if let assistanceKey = model.snapshot.assistanceKey {
                            Text(LocalizedStringKey(assistanceKey))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        DisclosureGroup("session.assistance") {
                            Text("session.resumeHelp")
                            Button("session.repeat") { model.command(.repeatInstruction) }
                                .buttonStyle(TMSessionButtonStyle())
                            recoveryControls

                        }
                    }
                }
            }
        } else if !model.voiceReady {
            controlChoice
        } else if model.snapshot.stage == .preparing {
            preparingContent
        } else if model.snapshot.stage == .preparationWait {
            VStack(spacing: 24) {
                Text("parity.getReady").typography(.therapyPhase)
                Text(verbatim: "\(model.snapshot.seconds)").typography(.therapyCountdown)
            }
        } else if model.snapshot.stage == .instruction {
            instructionPanel
        } else if model.snapshot.stage == .rest {
            VStack(spacing: 16) {
                Text(LocalizedStringKey(model.snapshot.instruction)).typography(.therapyPhase)
                Text(verbatim: "\(model.snapshot.seconds)")
                    .typography(.therapyCountdown)
                    .minimumScaleFactor(0.25)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.snapshot.stage == .feedback {
            TMSessionPanel(light: usesLightTheme) {
                Text(LocalizedStringKey(model.snapshot.instruction)).typography(.therapyPhase)
            }
        } else if model.snapshot.stage == .demonstration {
            guidancePanel(demonstrating: true)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                if let activity = model.snapshot.activity {
                    HStack(spacing: 8) {
                        Text(kindKey(activity.kind))
                        if activity.hasSide {
                            Text(activity.side == .left ? "session.left" : "session.right")
                        }
                    }
                    .typography(.title2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.snapshot.summary == nil {
                    TMTherapyMusicMenu(
                        selection: $musicTrack,
                        options: ExerciseMusicTrack.allCases.map {
                            TherapyMusicOption(id: $0.rawValue, title: LocalizedStringKey($0.titleKey))
                        },
                        size: 44
                    )

                    Button("session.help") { model.command(.help) }
                        .buttonStyle(TMSessionButtonStyle(compact: true))
                    Button("session.pause") { model.command(.pause) }
                        .buttonStyle(TMSessionButtonStyle(compact: true))
                    Button("therapy.session.stop") { model.command(.stop) }
                        .buttonStyle(TMSessionButtonStyle(compact: true))
                }
            }
            HStack(spacing: 12) {
                Text(phaseLabel).foregroundStyle(phaseColor)
                Spacer(minLength: 0)
                if let activity = model.snapshot.activity {
                    if activity.kind != .sitToStand {
                        Text("session.setProgress \(model.snapshot.setNumber) \(activity.sets)")
                    }
                    Text(verbatim: "\(model.snapshot.presentation?.count ?? 0) / \(activity.goal)")
                        .monospacedDigit()
                }
                Text(model.listening ? "session.listening" : "home.voiceUnavailable")
            }
            .typography(.title3)
        }
        .padding(4)
    }

    private var phaseLabel: LocalizedStringKey {
        if model.snapshot.paused { return "session.paused" }
        switch model.snapshot.stage {
        case .instruction, .demonstration: return "session.guidanceHeading"
        case .rest: return "session.rest"
        case .feedback: return "session.feedback"
        case .preparing: return "session.cameraWait"
        case .preparationWait: return "parity.getReady"
        case .summary: return "session.complete"
        case .activity:
            switch model.snapshot.presentation {
            case .towel: return "session.practice"
            case .movement(let value):
                return value.phase == .practice ? "session.practice" : "session.calibration"
            case .reach(let value):
                switch value.phase {
                case .setup, .assessment: return "session.reachAssessment"
                case .rehearsal: return "session.rehearsal"
                case .practice: return "session.practice"
                case .countdown: return "session.countdown"
                case .finished: return "session.complete"
                }
            case .cup(let value):
                return value.phase == .practice ? "session.practice" : "session.rehearsal"
            case .timed: return "session.timedPractice"
            case nil: return "session.cameraWait"
            }
        }
    }

    private var cornerExampleActive: Bool? {
        switch model.snapshot.presentation {
        case .movement(let value): return value.phase == .practice
        case .timed: return true
        default: return nil
        }
    }

    var camera: some View {
        GeometryReader { geometry in
            ZStack {
                TMBodyCameraPreview(
                    session: model.tracking.session, front: true,
                    onReady: model.previewReady,
                    onOrientation: model.orientationChanged,
                    onVideoBounds: usesLightLayout ? { videoBounds = $0 } : nil
                )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                if !model.snapshot.paused, !model.snapshot.cameraWaiting,
                    model.snapshot.stage == .activity,
                    let guide = model.snapshot.presentation?.guide
                {
                    targetOverlay(guide, size: geometry.size)
                }
                if !model.snapshot.paused, !model.snapshot.cameraWaiting,
                   model.snapshot.stage == .activity,
                   case .towel(let towel) = model.snapshot.presentation {
                    TMTowelWorkspaceView(snapshot: model.towelDisplay ?? towel, interpolates: model.towelInterpolates)
                }
                if !usesLightLayout, !hasFullScreenPresentation, model.snapshot.stage == .activity,
                    let active = cornerExampleActive
                {
                    let availableWidth = max(0, geometry.size.width - 24)
                    let availableHeight = max(0, geometry.size.height - 24)
                    let width = active
                        ? min(440, availableWidth * 0.55)
                        : min(320, availableWidth * 0.45, availableHeight * 0.9 * 5 / 6)
                    VStack {
                        HStack {
                            Spacer()
                            demonstration.frame(width: width, height: active ? availableHeight : width * 6 / 5)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .allowsHitTesting(false)
                }
            }
            .background(usesLightLayout ? TherapyPalette.canvas : Color.black)
            .clipShape(RoundedRectangle(cornerRadius: usesLightLayout ? 28 : 36))
            .onAppear { model.viewport(width: geometry.size.width, height: geometry.size.height) }
            .onChange(of: geometry.size) { _, size in
                model.viewport(width: size.width, height: size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var phaseColor: Color {
        if model.snapshot.paused {
            return .gray
        }
        switch model.snapshot.stage {
        case .preparing, .rest, .summary: return .gray
        case .instruction, .demonstration: return .blue
        case .preparationWait: return .blue
        case .feedback: return .green
        case .activity:
            switch model.snapshot.presentation {
            case .towel: return .green
            case .movement(let value):
                return value.phase == .startCapture || value.phase == .targetCapture ? .yellow : .green
            case .reach(let value):
                switch value.phase {
                case .setup, .assessment, .rehearsal: return .blue
                case .countdown, .practice: return .green
                case .finished: return .gray
                }
            case .cup(let value):
                return value.phase == .practice || value.phase == .countdown ? .green : .blue
            case .timed: return .green
            case nil: return .gray
            }
        }
    }

    private var instructionPanel: some View {
        guidancePanel(demonstrating: false)
    }

    private func guidancePanel(demonstrating: Bool) -> some View {
        Group {
            VStack(spacing: 12) {
                Text(demonstrating ? "session.example" : "session.guidanceHeading")
                    .typography(.therapyPhase)
                GeometryReader { geometry in
                    if demonstrating, model.snapshot.activity?.kind == .armRaise || model.snapshot.activity?.kind == .elbowBend {
                        if geometry.size.width > 850 {
                            HStack(spacing: 24) {
                                guidanceText(demonstrating: true)
                                demonstration
                            }
                        } else {
                            VStack(spacing: 12) {
                                guidanceText(demonstrating: true)
                                demonstration
                            }
                        }
                    } else {
                        guidanceText(demonstrating: demonstrating)
                    }
                }
                if voiceOver, let id = model.snapshot.guidanceID {
                    Button("session.readingComplete") { model.readingChanged(id, complete: true) }
                        .buttonStyle(TMSessionButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func guidanceText(demonstrating: Bool) -> some View {
        if let id = model.snapshot.guidanceID {
            TMMeasuredInstructionText(
                phrase: guidancePhrase,
                instructionID: id,
                fontSize: demonstrating ? instructionSize * 2 / 3 : instructionSize,
                reduceMotion: reduceMotion,
                voiceOver: voiceOver,
                onReadingChanged: { id, complete in model.readingChanged(id, complete: complete) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    var guidancePhrase: String {
        String(localized: String.LocalizationValue(model.snapshot.instruction), bundle: model.sessionLanguage.resourceBundle, locale: model.sessionLocale)
    }

    @ViewBuilder var demonstration: some View {
        if model.snapshot.activity?.kind == .foldTowel {
            TMTowelDemonstrationView()
        }

        if let activity = model.snapshot.activity, activity.kind == .armRaise || activity.kind == .elbowBend {
            let mode: TherapyAnimationPlayback = {
                if model.snapshot.stage == .demonstration {
                    return .looping
                }
                if case .movement(let value) = model.snapshot.presentation {
                    switch value.pose {
                    case .start: return .staticStart
                    case .peak: return .staticPeak
                    case .looping: return .looping
                    }
                }
                return .looping
            }()
            TMExerciseExample(
                asset: activity.kind == .armRaise ? .armRaise : .elbowBend,
                mirrored: activity.side == .left,
                mode: mode
            )
                .id(activity.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    var primaryMovementCue: String {
        switch model.snapshot.presentation {
        case .towel(let value): return value.trackingMessage ?? value.instruction
        case .movement(let value): return value.trackingMessage ?? model.snapshot.instruction
        case .reach(let value): return value.trackingMessage ?? model.snapshot.instruction
        case .cup(let value): return value.evidenceMessage ?? model.snapshot.instruction
        default: return model.snapshot.instruction
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Text(verbatim: SessionGuidanceCopy(phrase: String(localized: String.LocalizationValue(primaryMovementCue), bundle: model.sessionLanguage.resourceBundle, locale: model.sessionLocale)).main)
                .typography(.therapyCue)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            if let support = SessionGuidanceCopy(phrase: String(localized: String.LocalizationValue(primaryMovementCue), bundle: model.sessionLanguage.resourceBundle, locale: model.sessionLocale)).support {
                Text(verbatim: support).typography(.title2)
            }
            switch model.snapshot.presentation {
            case .towel(let towel):
                if towel.phase == .practice {
                    Text("towel.foldNumber \(towel.foldIndex + 1)")
                }
            case .movement(let movement):
                if movement.phase == .startCapture || movement.phase == .targetCapture {
                    HStack(spacing: 16) {
                        Text("session.remaining \(movement.seconds)").monospacedDigit()
                        ProgressView(value: movement.progress)
                            .tint(.yellow)
                            .accessibilityLabel(Text("session.holdProgress"))
                    }
                }
            case .reach(let reach):
                HStack(spacing: 12) {
                    Text("session.reachRound \(reach.round)").monospacedDigit()
                    Text(LocalizedStringKey([
                        "session.reachRight", "session.reachLeft", "session.reachUp",
                    ][reach.direction]))
                    if reach.rehearsal { Text("session.rehearsal") }
                    if reach.seconds > 0 { Text("session.remaining \(reach.seconds)").monospacedDigit() }
                }
            case .cup(let cup):
                Text(cup.phase == .rehearsal ? "session.rehearsal" : "cup.safety")
                if cup.phase == .rehearsal {
                    Text(LocalizedStringKey(cupSupportCue(cup.step)))
                }
            case .timed(let practice):
                Text("session.practiceSeconds \(Int(practice.seconds)) \(Int(practice.goal))")
            case nil: EmptyView()
            }
            if let failure = model.failure {
                Text(verbatim: failure).typography(.caption).foregroundStyle(.orange)
            }
        }
        .typography(.title2)
        .padding(8)
        .background(.black, in: RoundedRectangle(cornerRadius: 12))
    }

    private func cupSupportCue(_ step: CupStep) -> String {
        switch step {
        case .start, .nearFace: return "session.cupHoldSupport"
        case .transfer: return "session.cupTransferSupport"
        case .handReturn, .cupReturn: return "session.cupReturnSupport"
        }
    }

    var preparingContent: some View {
        recoveryPanel("session.cameraWait")
    }

    var controlChoice: some View {
        ScrollView {
            TMSessionPanel(light: usesLightTheme) {
                VStack(spacing: 16) {
                    Text("home.entryBlocked").typography(.title2)
                    Button("home.openSettings") {
                        model.openSettings()
                    }.buttonStyle(TMSessionButtonStyle())
                    Button("home.retry") {
                        Task { await model.enableVoice(permissions: permissions) }
                    }.buttonStyle(TMSessionButtonStyle())
                }
            }
        }
    }

    var recoveryControls: some View {
        VStack(spacing: 12) {
            Button(model.snapshot.activity?.kind == .foldTowel ? "towel.restart" : "session.recalibrate") { model.command(.retryCalibration) }
                .buttonStyle(TMSessionButtonStyle())
            if model.snapshot.stage == .activity {
                HStack {
                    Button("session.redo") { model.command(.redo) }
                        .buttonStyle(TMSessionButtonStyle())
                    let reachActivity = model.snapshot.activity?.kind == .directionalReach
                    let cupRehearsal: Bool = {
                        guard case .cup(let cup) = model.snapshot.presentation else { return false }
                        return cup.phase == .rehearsal
                    }()
                    if reachActivity || cupRehearsal {
                        Button("session.adjustTarget") { model.command(.adjustTarget) }
                            .buttonStyle(TMSessionButtonStyle())
                    }
                }
                if model.snapshot.activity?.kind == .directionalReach {
                    HStack {
                        Button("session.retryStep") { model.command(.retryStep) }
                            .buttonStyle(TMSessionButtonStyle())
                        Button("session.skipStep") { model.command(.skipStep) }
                            .buttonStyle(TMSessionButtonStyle())
                    }
                }
                if model.snapshot.activity?.kind == .armRaise || model.snapshot.activity?.kind == .elbowBend {
                    HStack {
                        Button("session.retryStep") { model.command(.retryStep) }
                            .buttonStyle(TMSessionButtonStyle())
                        Button("session.timedPractice") { model.command(.timedPractice) }
                            .buttonStyle(TMSessionButtonStyle())
                    }
                }
            }
            Button("session.skip") { model.command(.skip) }
                .buttonStyle(TMSessionButtonStyle())
        }
    }

    func recoveryPanel(_ key: LocalizedStringKey) -> some View {
        ScrollView {
            TMSessionPanel(light: usesLightTheme) {
                VStack(spacing: 16) {
                    Text(key).typography(.therapyPhase)
                    if model.cameraDenied {
                        Button("home.openSettings") { model.openSettings() }
                            .buttonStyle(TMSessionButtonStyle())
                    }
                    Button("session.retryCamera") {
                        Task { await model.retryCamera(permissions: permissions) }
                    }.buttonStyle(TMSessionButtonStyle())

                    recoveryControls
                }
            }
        }
    }

    func saveError(_ message: String) -> some View {
        TMSessionPanel(light: usesLightTheme) {
            HStack {
                VStack(alignment: .leading) {
                    Text("session.saveError")
                    Text(verbatim: message).typography(.caption)
                }
                Button("session.retrySave") { model.retrySave() }.buttonStyle(TMSessionButtonStyle())
                Button("session.continueUnsaved") { model.acknowledgeSaveFailure() }.buttonStyle(
                    TMSessionButtonStyle())
            }
        }
    }

    func summaryContent(_ summary: SessionSummary) -> some View {
        List {
            Section {
                Text(
                    summary.interrupted
                        ? "session.interrupted"
                        : (summary.stopped ? "session.stopped" : "session.complete")
                ).typography(.largeTitle)
                if reduceMotion, !summary.stopped, !summary.interrupted {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
            }
            if summary.routine.activities.contains(where: { $0.kind != .sitToStand }) {
                Text("session.completedSets \(summary.completedSets)")
            }
            Section("session.results") {
                ForEach(summary.results, id: \.executionID) { result in
                    summaryRow(result)
                }
            }
            Section {
                if summary.results.contains(where: { $0.activity.kind == .cup }) {
                    Text("session.cupCaution")
                }
                Text("session.summaryCaution")
                if model.saving { ProgressView("session.saving") }
                Button(summaryExitTitle) { leaveSummary(summary) }
                    .buttonStyle(TMSessionButtonStyle())
                    .disabled(model.saving || model.saveFailure != nil)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(usesLightTheme ? TherapyPalette.canvas : Color.black)
    }

    // MARK: - Leaving

    /// While today's plan runs, the summary leads on to the next exercise.
    var summaryExitTitle: LocalizedStringKey {
        dependencies.dailyPlan.isRunning ? "plan.nextContinue" : "session.restart"
    }

    func leaveSummary(_ summary: SessionSummary) {
        guard dependencies.dailyPlan.isRunning else {
            router.pop()
            return
        }

        dependencies.dailyPlan.finish(completed: !summary.stopped, router: router)
    }

    /// Leaving before the session could start ends a running plan instead of skipping ahead.
    private func leaveWithoutResult() {
        guard dependencies.dailyPlan.isRunning else {
            router.popToRoot()
            return
        }

        dependencies.dailyPlan.end(router: router)
    }

    private func summaryRow(_ result: SessionActivityResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(kindKey(result.activity.kind))
                if result.activity.hasSide {
                    Text(result.activity.side == .left ? "session.left" : "session.right")
                }
                Spacer()
                if result.activity.kind != .sitToStand {
                    Text("session.setProgress \(result.setNumber ?? 1) \(result.activity.sets)")
                }
                Text(LocalizedStringKey("session.outcome." + result.outcome.rawValue))
                if result.practiceSeconds > 0, result.completedWork == 0 {
                    Text("session.elapsed \(Int(result.practiceSeconds))")
                } else {
                    Text(verbatim: "\(result.completedWork) / \(result.activity.goal)")
                }
            }
            if let outcomes = result.cupOutcomes {
                ForEach(Array(outcomes.enumerated()), id: \.offset) { _, milestone in
                    HStack {
                        Text("cup.round \(milestone.round)")
                        Text(LocalizedStringKey("cup.step.\(milestone.step)"))
                    }
                    .typography(.caption)
                }
            }
            if !result.reachOutcomes.isEmpty {
                ForEach(Array(result.reachOutcomes.enumerated()), id: \.offset) { _, outcome in
                    HStack {
                        Text(LocalizedStringKey([
                            "session.reachRight", "session.reachLeft", "session.reachUp",
                        ][outcome.direction]))
                        Text(LocalizedStringKey("session.reachOutcome.\(outcome.evidence.rawValue)"))
                    }
                    .typography(.caption)
                }
            }
            if let skipped = result.skippedReachSteps, !skipped.isEmpty {
                ForEach(Array(skipped.enumerated()), id: \.offset) { _, step in
                    HStack {
                        Text("session.caregiverSkippedStep")
                        if step.round > 0 {
                            Text("session.reachRound \(step.round)")
                        }
                        Text(LocalizedStringKey([
                            "session.reachRight", "session.reachLeft", "session.reachUp",
                        ][step.direction]))
                        Text(LocalizedStringKey("session.reachPhase.\(step.phase.rawValue)"))
                    }
                    .typography(.caption)
                }
            }
        }
    }

    func kindKey(_ kind: TherapyKind) -> LocalizedStringKey {
        LocalizedStringKey(kindKeyName(kind))
    }

    func kindKeyName(_ kind: TherapyKind) -> String {
        switch kind {
        case .armRaise: return "session.armRaise"
        case .elbowBend: return "session.elbowBend"
        case .directionalReach: return "session.directionalReach"
        case .cup: return "session.cup"
        case .foldTowel: return "session.foldTowel"
        case .sitToStand: return "session.sitToStand"
        }
    }

    private func targetOverlay(_ guide: TargetGuide, size: CGSize) -> some View {
        func normalized(_ point: TherapyPoint) -> CGPoint {
            CGPoint(x: point.x / guide.aspect, y: point.y)
        }
        let active = guide.targetActive ? guide.target : guide.start
        let inside = guide.acceptedInside ?? ((guide.tracked - active).length <= guide.radius)
        let bubble = SessionBubbleGuide(
            startCenter: normalized(guide.start),
            targetCenter: normalized(guide.target),
            trackedJoint: normalized(guide.tracked),
            radius: guide.radius,
            activeZone: guide.targetActive ? .target : .start,
            trackedJointInside: inside,
            dwellProgress: guide.jointHold ? 0 : guide.progress
        )
        let direction = (guide.directionOnly || guide.directionTip != nil) ? SessionDirectionGuide(
            origin: normalized(guide.start),
            tip: normalized(guide.directionTip ?? guide.target),
            trackedJoint: normalized(guide.tracked),
            showsArrow: guide.showsDirectionArrow,
            farthestPosition: guide.farthest.map(normalized)
        ) : nil
        return TMSessionTargetOverlay(
            imageSize: CGSize(width: guide.aspect, height: 1),
            bubbleGuide: guide.capturing ? (guide.savedStart ? bubble : nil) : (guide.directionOnly ? nil : bubble),
            singleZone: guide.start == guide.target,
            settingUp: guide.capturing,
            captureJoint: (guide.capturing || guide.jointHold) ? normalized(guide.tracked) : nil,
            holdProgress: guide.progress,
            holdRadius: guide.matchesHoldRing ? guide.radius : nil,
            directionGuide: direction,
            mirrored: true
        )
    }
}
