//
//  TherapyOverview.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import SwiftUI

struct TherapyOverview: View {
    let category: TherapyCategory
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PermissionManager.self) private var permissions

    var body: some View {
        HomeContent(category: category, model: HomeViewModel(
            permissions: permissions,
            audio: dependencies.audio,
            history: dependencies
        ))
    }
}

private struct HomeContent: View {
    let category: TherapyCategory
    @Environment(NavigationRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(PermissionManager.self) private var permissions
    @Environment(\.openURL) private var openURL
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.selected.rawValue
    @State var model: HomeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(LocalizedStringKey(category == .taskOriented ? "task.category" : "therapy.overview.title"))
                    .typography(.largeTitle)
                    .accessibilityAddTraits(.isHeader)
                LanguageSelector(language: $language)
                    .disabled(model.busy)
                Text(LocalizedStringKey(category.positioningKey)).typography(.body)
                exercises
                if category == .taskOriented {
                    TherapyButton(title: "towel.history", symbol: "chart.bar") { router.push(.taskReports) }
                }
                Label(
                    LocalizedStringKey(model.message),
                    systemImage: model.ready ? "checkmark.circle.fill" : "info.circle"
                )
                .typography(.title2)
                .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task {
                        if await model.performAction() {
                            router.push(.routineConfiguration(category))
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
                title: LocalizedStringKey(category.title),
                subtitle: "",
                artwork: category.artwork
            )
            .clipShape(RoundedRectangle(cornerRadius: 30))
            TherapyButton(title: "home.viewShort", symbol: "slider.horizontal.3") {
                router.push(.routineConfiguration(category))
            }
            ForEach(Array(category.kinds.enumerated()), id: \.element) { index, kind in
                TherapyExerciseRow(
                    title: LocalizedStringKey("session." + kind.rawValue),
                    subtitle: "",
                    artwork: "symbol:" + symbol(for: kind),
                    color: TherapyPalette.illustrationBackground(at: index)
                ) {
                    router.push(.routineConfiguration(category))
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
        case .foldTowel: return "square.stack.3d.up"
        case .cup: return "cup.and.saucer.fill"
        case .sitToStand: return "figure.stand"
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
