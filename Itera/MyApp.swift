import SwiftUI

@main struct MyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("app.language") private var language = Locale.preferredLanguages.first?.hasPrefix("id") == true ? "id" : "en"
    @State private var permissions = PermissionManager()
    @State private var router = NavigationRouter()
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .typography(.body)
                .withAppRouter()
                .environment(\.locale, Locale(identifier: language))
                .environment(router)
                .environment(permissions)
                .environment(dependencies)
                .task { await dependencies.recoverHistory() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        permissions.refresh()
                    }
                }
        }
    }
}
