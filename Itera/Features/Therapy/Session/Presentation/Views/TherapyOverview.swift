//
//  TherapyOverview.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import SwiftUI

struct TherapyOverview: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PermissionManager.self) private var permissions

    var body: some View {
        HomeContent(model: HomeViewModel(
            permissions: permissions,
            audio: dependencies.audio,
            history: dependencies
        ))
    }
}

private struct HomeContent: View {
    @Environment(NavigationRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(PermissionManager.self) private var permissions
    @Environment(\.openURL) private var openURL
    @AppStorage("app.language") private var language = AppLanguage.selected.rawValue
    @State var model: HomeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("therapy.overview.title")
                    .typography(.homeHeading)
                    .accessibilityAddTraits(.isHeader)
                LanguageSelector(language: $language)
                    .disabled(model.busy)
                Text("home.positioning").typography(.homeLabel)
                exercises
                Label(
                    LocalizedStringKey(model.message),
                    systemImage: model.ready ? "checkmark.circle.fill" : "info.circle"
                )
                .typography(.title2)
                .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task {
                        if await model.performAction() {
                            router.push(.routineConfiguration)
                        }
                    }
                } label: {
                    Text(LocalizedStringKey(model.action))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(SessionButtonStyle())
                .disabled(model.busy)
                DisclosureGroup("home.permissions") {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(AppPermission.allCases, id: \.self) { permission in
                            LabeledContent(permission.title) {
                                Text(permissions.status(for: permission).title)
                            }
                        }
                        Button("home.recheck") { model.refresh() }
                        Button("home.openSettings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }.padding(.vertical)
                }
                .disabled(model.busy)
                if model.busy { ProgressView().accessibilityLabel(Text("home.working")) }
            }
            .padding(32)
        }
        .task { model.refresh() }
        .onChange(of: language) { _, _ in model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh() }
        }
    }

    private var exercises: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 24))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
        return layout {
            ExerciseIllustration(title: "therapy.armRaise", symbol: "figure.arms.open")
            ExerciseIllustration(title: "therapy.elbowBend", symbol: "figure.strengthtraining.traditional")
            ExerciseIllustration(title: "therapy.directionalReach", symbol: "hand.point.up.left")
        }
    }
}

private extension AppPermission {
    var title: LocalizedStringKey {
        switch self {
        case .camera: return "home.camera"
        case .microphone: return "home.microphone"
        case .speechRecognition: return "home.speech"
        }
    }
}

private extension PermissionStatus {
    var title: LocalizedStringKey {
        switch self {
        case .authorized: return "home.allowed"
        case .denied: return "home.denied"
        case .restricted: return "home.restrictedStatus"
        case .notDetermined: return "home.notRequested"
        case .unknown: return "home.unknown"
        }
    }
}
