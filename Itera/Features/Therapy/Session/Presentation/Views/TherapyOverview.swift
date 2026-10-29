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
            VStack(alignment: .leading, spacing: 28) {
                Text("therapy.overview.title")
                    .typography(.largeTitle)
                    .accessibilityAddTraits(.isHeader)
                LanguageSelector(language: $language)
                    .disabled(model.busy)
                Text("home.positioning").typography(.body)
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
            .padding(28)
        .background(TherapyPalette.cream)
        }
        .environment(\.locale, Locale(identifier: language))
        .task { model.refresh() }
        .onChange(of: language) { _, _ in model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh() }
        }
    }

    private var exercises: some View {
        VStack(spacing: 12) {
            TherapyArtworkPanel(
                title: "home.armPractice",
                subtitle: "",
                artwork: "symbol:figure.arms.open"
            )
            .clipShape(RoundedRectangle(cornerRadius: 30))
            TherapyButton(title: "home.viewShort", symbol: "slider.horizontal.3") {
                router.push(.routineConfiguration)
            }
            ForEach(Array(TherapyKind.allCases.enumerated()), id: \.element) { index, kind in
                TherapyExerciseRow(
                    title: LocalizedStringKey("session." + kind.rawValue),
                    subtitle: "",
                    artwork: "symbol:" + symbol(for: kind),
                    color: TherapyPalette.illustrationBackground(at: index)
                ) {
                    router.push(.routineConfiguration)
                }
                .accessibilityHint("routine.configureHint")
            }
        }
    }

    private func symbol(for kind: TherapyKind) -> String {
        switch kind {
        case .armRaise: return "figure.arms.open"
        case .elbowBend: return "figure.strengthtraining.traditional"
        case .directionalReach: return "hand.point.up.left"
        case .cup: return "cup.and.saucer.fill"
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
