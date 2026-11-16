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
    @State private var component: AppComponent
    @State private var builder: RootBuilder
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.selected.rawValue

    init() {
        let component = AppComponent(permissions: PermissionManager())
        _component = State(initialValue: component)
        _builder = State(initialValue: RootBuilder(component: component))
        AppFont.configureNavigationBars()
    }

    var body: some Scene {
        WindowGroup {
            root
                .typography(.body)
                // Applied at the root so tab stacks, sheets and covers share the language.
                .environment(\.locale, (AppLanguage(rawValue: language) ?? .indonesian).locale)
                .environment(\.buttonFeedback, component.buttonClick.play)
                .buttonStyle(TMTherapySoundButtonStyle())
                .task {
                    #if DEBUG
                    component.openDebugIntroIfRequested()
                    #endif
                    await component.recoverHistory()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        component.refreshPermissions()
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
            builder.buildRoot()
        }
        #else
        builder.buildRoot()
        #endif
    }
}
