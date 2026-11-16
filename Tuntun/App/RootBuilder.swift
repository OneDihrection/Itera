//
//  RootBuilder.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import SwiftUI

/// Builds the app's root: the two tabs, each from its feature's builder.
@MainActor
final class RootBuilder {
    private let component: AppComponent

    init(component: AppComponent) {
        self.component = component
    }

    /// Each tab's root screen owns its own navigation stack.
    @ViewBuilder func buildRoot() -> some View {
        let viewModel: some RootViewModelProtocol = component.rootViewModel

        RootView(
            viewModel: viewModel,
            home: component.homeBuilder.buildHome(),
            reports: component.historyBuilder.buildReports()
        )
    }
}
