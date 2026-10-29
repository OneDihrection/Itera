import SwiftUI
import Playgrounds

struct ContentView: View {
    var body: some View {
        TherapyOverview()
    }
}

#Preview {
    ContentView()
        .environment(AppDependencies())
        .environment(NavigationRouter())
}

#Playground {
    _ = 1 + 2
}
