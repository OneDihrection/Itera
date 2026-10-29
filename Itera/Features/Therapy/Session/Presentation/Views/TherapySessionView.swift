//
//  TherapySessionView.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import SwiftUI

struct TherapySessionView: View {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @ScaledMetric(relativeTo: .largeTitle) private var instructionSize = 96.0
    @Environment(PermissionManager.self) private var permissions
    @Environment(NavigationRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var celebrationStart: Date?
    @State private var model: TherapySessionViewModel

    private var presentationOnly = false

    init(model: TherapySessionViewModel) { _model = State(initialValue: model) }

    #if DEBUG
    init(fixture: SessionSnapshot) {
        _model = State(initialValue: .presentationFixture(fixture))
        presentationOnly = true
    }
    #endif

    var body: some View {
        GeometryReader { geometry in
            if model.entryFailure {
                VStack(spacing: 24) {
                    Text(LocalizedStringKey(model.entryMessage)).typography(.title)
                    Button("home.retry") {
                        Task { await model.start(permissions: permissions) }
                    }
                    .disabled(model.validating)
                    .buttonStyle(SessionButtonStyle())
                    Button("home.openSettings") { model.openSettings() }
                        .buttonStyle(SessionButtonStyle())
                    Button("home.back") { router.popToRoot() }
                        .buttonStyle(SessionButtonStyle())
                }
                .padding(32)
            } else if let summary = model.snapshot.summary {
                VStack(spacing: 12) {
                    header
                    summaryContent(summary)
                    if let error = model.saveFailure { saveError(error) }
                }
                .padding(12)
            } else {
                let cameraHeight = geometry.size.height * (dynamicTypeSize.isAccessibilitySize ? 0.45 : 0.6)
                let barsHeight = max(0, geometry.size.height - cameraHeight - 40)
                VStack(spacing: 8) {
                    ScrollView { header.frame(maxWidth: .infinity) }
                        .frame(height: barsHeight * 0.4)
                    camera.frame(height: cameraHeight)
                    ScrollView {
                        footer
                        if let error = model.saveFailure { saveError(error) }
                    }
                    .frame(height: barsHeight * 0.6)
                }
                .padding(12)
                .accessibilityHidden(hasFullScreenPresentation)
            }
        }
        .overlay {
            if model.snapshot.summary == nil, !model.entryFailure, hasFullScreenPresentation {
                fullScreenPresentation
            }
        }
        .overlay {
            if let celebrationStart, !reduceMotion {
                SessionCelebration(start: celebrationStart).ignoresSafeArea()
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
                    .strokeBorder(phaseColor, lineWidth: 8)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .environment(\.locale, model.sessionLocale)
        .background(.black)
        .foregroundStyle(.white)
        .toolbar(model.snapshot.summary == nil ? .hidden : .visible, for: .navigationBar)
        .navigationTitle(model.snapshot.summary == nil ? "" : "session.summaryTitle")
        .statusBarHidden(model.snapshot.summary == nil)
        .navigationBarBackButtonHidden(model.snapshot.summary == nil)
        .task {
            if !presentationOnly { await model.start(permissions: permissions) }
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

    private var hasFullScreenPresentation: Bool {
        model.cameraDenied || !model.voiceReady || model.snapshot.paused
            || model.snapshot.cameraWaiting || model.snapshot.stage == .instruction
            || model.snapshot.stage == .demonstration || model.snapshot.stage == .preparationWait || model.snapshot.stage == .rest
            || model.snapshot.stage == .feedback
            || model.snapshot.presentation?.countdownSeconds != nil
    }

    private var fullScreenPresentation: some View {
        SessionStageSurface(background: presentationBackground, border: phaseColor) {
            presentationContent
        } controls: {
            HStack(spacing: 24) {
                Button("session.help") { model.command(.help) }
                Button(model.snapshot.paused ? "session.resume" : "session.pause") {
                    model.command(model.snapshot.paused ? .resume : .pause)
                }
                .disabled(model.snapshot.paused && !model.voiceReady)
                Button("therapy.session.stop") { model.command(.stop) }
            }
            .buttonStyle(SessionButtonStyle())
            if let failure = model.failure {
                Text(verbatim: failure).typography(.caption).foregroundStyle(.orange)
            }
            if let error = model.saveFailure { saveError(error) }
        }
    }

    private var presentationBackground: Color {
        switch model.snapshot.stage {
        case .instruction, .demonstration:
            return Color(red: 0.03, green: 0.14, blue: 0.34)
        default:
            if model.snapshot.paused || model.snapshot.cameraWaiting { return .black }
            if model.snapshot.presentation?.countdownSeconds != nil {
                return Color(red: 0.04, green: 0.24, blue: 0.14)
            }
            return Color(white: 0.12)
        }
    }

    @ViewBuilder
    private var presentationContent: some View {
        if model.cameraDenied {
            recoveryPanel("therapy.session.cameraDenied")
        } else if !model.voiceReady {
            controlChoice
        } else if model.snapshot.paused {
            ScrollView {
                SessionPanel {
                    VStack(spacing: 16) {
                        Text("session.paused").typography(.therapyPause)
                        Text("session.resumeHelp")
                        if let assistanceKey = model.snapshot.assistanceKey {
                            Text(LocalizedStringKey(assistanceKey))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        DisclosureGroup("session.assistance") {
                            Text("session.resumeHelp")
                            Button("session.repeat") { model.command(.repeatInstruction) }
                                .buttonStyle(SessionButtonStyle())
                            recoveryControls
                            Button("session.camera") { model.switchCamera() }
                                .buttonStyle(SessionButtonStyle())
                        }
                    }
                }
            }
        } else if model.snapshot.cameraWaiting {
            recoveryPanel("session.cameraWait")
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
            SessionPanel {
                Text(LocalizedStringKey(model.snapshot.instruction)).typography(.therapyPhase)
            }
        } else if model.snapshot.stage == .demonstration {
            guidancePanel(demonstrating: true)
        } else if model.snapshot.stage == .activity,
            let seconds = model.snapshot.presentation?.countdownSeconds
        {
            countdownPanel(seconds)
                .frame(maxHeight: .infinity)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                if let activity = model.snapshot.activity {
                    HStack(spacing: 8) {
                        Text(kindKey(activity.kind))
                        Text(activity.side == .left ? "session.left" : "session.right")
                    }
                    .typography(.title2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.snapshot.summary == nil {
                    Button("session.help") { model.command(.help) }
                        .buttonStyle(SessionButtonStyle(compact: true))
                    Button("session.pause") { model.command(.pause) }
                        .buttonStyle(SessionButtonStyle(compact: true))
                    Button("therapy.session.stop") { model.command(.stop) }
                        .buttonStyle(SessionButtonStyle(compact: true))
                }
            }
            HStack(spacing: 12) {
                Text(phaseLabel).foregroundStyle(phaseColor)
                Spacer(minLength: 0)
                if let activity = model.snapshot.activity {
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

    private var camera: some View {
        GeometryReader { geometry in
            ZStack {
                BodyCameraPreview(
                    session: model.tracking.session, front: model.frontCamera,
                    onReady: model.previewReady, onOrientation: model.orientationChanged)
                if !model.snapshot.paused, !model.snapshot.cameraWaiting,
                    model.snapshot.stage == .activity,
                    let guide = model.snapshot.presentation?.guide
                {
                    targetOverlay(guide, size: geometry.size)
                }
                if !hasFullScreenPresentation, model.snapshot.stage == .activity,
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
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 36))
            .onAppear { model.viewport(width: geometry.size.width, height: geometry.size.height) }
            .onChange(of: geometry.size) { _, size in
                model.viewport(width: size.width, height: size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var phaseColor: Color {
        if model.snapshot.paused || model.snapshot.cameraWaiting {
            return .gray
        }
        switch model.snapshot.stage {
        case .preparing, .rest, .summary: return .gray
        case .instruction, .demonstration: return .blue
        case .preparationWait: return .blue
        case .feedback: return .green
        case .activity:
            switch model.snapshot.presentation {
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
                        .buttonStyle(SessionButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func guidanceText(demonstrating: Bool) -> some View {
        if let id = model.snapshot.guidanceID {
            MeasuredInstructionText(
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

    private var guidancePhrase: String {
        String(localized: String.LocalizationValue(model.snapshot.instruction), bundle: model.sessionLanguage.resourceBundle, locale: model.sessionLocale)
    }

    private func countdownPanel(_ seconds: Int) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("session.countdown").typography(.therapyPhase)
                Text(verbatim: "\(seconds)")
                    .typography(.therapyCountdown)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
        }
        .background(.black.opacity(0.9))
    }

    @ViewBuilder private var demonstration: some View {
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
            ExerciseExample(
                asset: activity.kind == .armRaise ? .armRaise : .elbowBend,
                mirrored: activity.side == .left,
                mode: mode
            )
                .id(activity.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var primaryMovementCue: String {
        switch model.snapshot.presentation {
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

    private var controlChoice: some View {
        ScrollView {
            SessionPanel {
                VStack(spacing: 16) {
                    Text("home.entryBlocked").typography(.title2)
                    Button("home.openSettings") {
                        model.openSettings()
                    }.buttonStyle(SessionButtonStyle())
                    Button("home.retry") {
                        Task { await model.enableVoice(permissions: permissions) }
                    }.buttonStyle(SessionButtonStyle())
                }
            }
        }
    }

    private var recoveryControls: some View {
        VStack(spacing: 12) {
            Button("session.recalibrate") { model.command(.retryCalibration) }
                .buttonStyle(SessionButtonStyle())
            if model.snapshot.stage == .activity {
                HStack {
                    Button("session.redo") { model.command(.redo) }
                        .buttonStyle(SessionButtonStyle())
                    let reachActivity = model.snapshot.activity?.kind == .directionalReach
                    let cupRehearsal: Bool = {
                        guard case .cup(let cup) = model.snapshot.presentation else { return false }
                        return cup.phase == .rehearsal
                    }()
                    if reachActivity || cupRehearsal {
                        Button("session.adjustTarget") { model.command(.adjustTarget) }
                            .buttonStyle(SessionButtonStyle())
                    }
                }
                if model.snapshot.activity?.kind == .directionalReach {
                    HStack {
                        Button("session.retryStep") { model.command(.retryStep) }
                            .buttonStyle(SessionButtonStyle())
                        Button("session.skipStep") { model.command(.skipStep) }
                            .buttonStyle(SessionButtonStyle())
                    }
                }
                if model.snapshot.activity?.kind == .armRaise || model.snapshot.activity?.kind == .elbowBend {
                    HStack {
                        Button("session.retryStep") { model.command(.retryStep) }
                            .buttonStyle(SessionButtonStyle())
                        Button("session.timedPractice") { model.command(.timedPractice) }
                            .buttonStyle(SessionButtonStyle())
                    }
                }
            }
            Button("session.skip") { model.command(.skip) }
                .buttonStyle(SessionButtonStyle())
        }
    }

    private func recoveryPanel(_ key: LocalizedStringKey) -> some View {
        ScrollView {
            SessionPanel {
                VStack(spacing: 16) {
                    Text(key).typography(.therapyPhase)
                    if model.cameraDenied {
                        Button("home.openSettings") { model.openSettings() }
                            .buttonStyle(SessionButtonStyle())
                    }
                    Button("session.retryCamera") {
                        Task { await model.retryCamera(permissions: permissions) }
                    }.buttonStyle(SessionButtonStyle())
                    recoveryControls
                }
            }
        }
    }

    private func saveError(_ message: String) -> some View {
        SessionPanel {
            HStack {
                VStack(alignment: .leading) {
                    Text("session.saveError")
                    Text(verbatim: message).typography(.caption)
                }
                Button("session.retrySave") { model.retrySave() }.buttonStyle(SessionButtonStyle())
                Button("session.continueUnsaved") { model.acknowledgeSaveFailure() }.buttonStyle(
                    SessionButtonStyle())
            }
        }
    }

    private func summaryContent(_ summary: SessionSummary) -> some View {
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
                Button("session.restart") { router.pop() }
                    .buttonStyle(SessionButtonStyle())
                    .disabled(model.saving || model.saveFailure != nil)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(.black)
    }

    private func summaryRow(_ result: SessionActivityResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(kindKey(result.activity.kind))
                Text(result.activity.side == .left ? "session.left" : "session.right")
                Spacer()
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

    private func kindKey(_ kind: TherapyKind) -> LocalizedStringKey {
        switch kind {
        case .armRaise: return "session.armRaise"
        case .elbowBend: return "session.elbowBend"
        case .directionalReach: return "session.directionalReach"
        case .cup: return "session.cup"
        }
    }

    private func targetOverlay(_ guide: TargetGuide, size: CGSize) -> some View {
        func normalized(_ point: TherapyPoint) -> CGPoint {
            CGPoint(x: point.x / guide.aspect, y: point.y)
        }
        let active = guide.targetActive ? guide.target : guide.start
        let inside = (guide.tracked - active).length <= guide.radius
        let bubble = SessionBubbleGuide(
            startCenter: normalized(guide.start),
            targetCenter: normalized(guide.target),
            trackedJoint: normalized(guide.tracked),
            radius: guide.radius,
            activeZone: guide.targetActive ? .target : .start,
            trackedJointInside: inside,
            dwellProgress: guide.progress
        )
        let direction = (guide.directionOnly || guide.directionTip != nil) ? SessionDirectionGuide(
            origin: normalized(guide.start),
            tip: normalized(guide.directionTip ?? guide.target),
            trackedJoint: normalized(guide.tracked),
            showsArrow: guide.showsDirectionArrow,
            farthestPosition: guide.farthest.map(normalized)
        ) : nil
        return SessionTargetOverlay(
            imageSize: CGSize(width: guide.aspect, height: 1),
            bubbleGuide: guide.capturing ? (guide.savedStart ? bubble : nil) : (guide.directionOnly ? nil : bubble),
            singleZone: guide.start == guide.target,
            settingUp: guide.capturing,
            captureJoint: guide.capturing ? normalized(guide.tracked) : nil,
            holdProgress: guide.progress,
            directionGuide: direction,
            mirrored: model.frontCamera
        )
    }
}
