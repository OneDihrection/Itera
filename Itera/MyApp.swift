import SwiftUI

@main struct MyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var permissions = PermissionManager()
    @State private var router = NavigationRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .typography(.body)
                .withAppRouter()
                .environment(router)
                .environment(permissions)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        permissions.refresh()
                    }
                }
        }
    }
}
