//
//  MyApp.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

@main
struct MyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = NavigationRouter()
    @State private var dependencies: AppDependencies
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.selected.rawValue

    init() {
        _dependencies = State(initialValue: AppDependencies(permissions: PermissionManager()))
        AppFont.configureNavigationBars()
    }

    var body: some Scene {
        WindowGroup {
            root
                .typography(.body)
                .withAppRouter(dependencies: dependencies)
                // Applied outside the router so tab stacks, sheets and covers share the language.
                .environment(\.locale, (AppLanguage(rawValue: language) ?? .indonesian).locale)
                .environment(router)
                .environment(\.buttonFeedback, dependencies.playButtonClick)
                .buttonStyle(TMTherapySoundButtonStyle())
                .task {
                    #if DEBUG
                    dependencies.openDebugIntroIfRequested(router: router)
                    #endif
                    await dependencies.recoverHistory()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        dependencies.refreshPermissions()
                    }
                }
        }
    }

    @ViewBuilder
    private var root: some View {
        #if DEBUG
        if let screen = DebugScreenLauncher.galleryScreen {
            TMDebugScreenGallery(screen: screen)
        } else {
            dependencies.makeHomeView()
        }
        #else
        dependencies.makeHomeView()
        #endif
    }
}
