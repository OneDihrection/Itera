//
//  AppRouterView.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import SwiftUI

@MainActor
enum AppRouterView {
    @ViewBuilder
    static func destination(_ route: AppRoute) -> some View {
        switch route {
        case .home:
            ContentView()
        }
    }
}

#if DEBUG
private struct RouterPreview: View {
    @State private var router: NavigationRouter

    init(route: AppRoute? = nil, sheet: Bool = false) {
        let router = NavigationRouter()

        if let route {
            if sheet {
                router.presentSheet(route)
            } else {
                router.push(route)
            }
        }

        _router = State(initialValue: router)
    }

    var body: some View {
        ContentView()
            .typography(.body)
            .withAppRouter()
            .environment(router)
    }
}

#Preview("Root") {
    RouterPreview()
}

#Preview("Pushed route") {
    RouterPreview(route: .home)
}

#Preview("Sheet") {
    RouterPreview(route: .home, sheet: true)
}
#endif
