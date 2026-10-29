//
//  MyApp.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

@main
struct MyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = NavigationRouter()
    @State private var dependencies: AppDependencies

    init() {
        _dependencies = State(initialValue: AppDependencies(permissions: PermissionManager()))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .typography(.body)
                .withAppRouter()
                .environment(router)
                .environment(dependencies)
                .environment(dependencies.permissions)
                .environment(\.buttonFeedback, dependencies.playButtonClick)
                .buttonStyle(TherapySoundButtonStyle())
                .task { await dependencies.recoverHistory() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { dependencies.permissions.refresh() }
                }
        }
    }

}
