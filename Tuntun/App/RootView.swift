//
//  RootView.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Observation
import SwiftUI

enum AppTab: Hashable {
    case home
    case reports
}

/// Switches the top-level tab from anywhere in the app, such as a session's closing page.
@MainActor
protocol TabRouterProtocol: AnyObject {
    func showProgress()
}

/// Owns the selected tab; the root view model forwards it to the tab bar.
@MainActor
@Observable
final class TabRouter: TabRouterProtocol {
    var selectedTab: AppTab = .home

    func showProgress() {
        selectedTab = .reports
    }
}

@MainActor
protocol RootViewModelProtocol: AnyObject, Observable {
    var selectedTab: AppTab { get set }
}

/// Owns the selected tab and plays the button click when the patient switches tabs.
@MainActor
@Observable
final class RootViewModel: RootViewModelProtocol {
    @ObservationIgnored private let router: TabRouter
    @ObservationIgnored private let playButtonClick: () -> Void

    /// Set by the tab bar, so a change is a tap; the router changes its own selection silently.
    var selectedTab: AppTab {
        get {
            router.selectedTab
        }
        set {
            guard newValue != router.selectedTab else {
                return
            }

            router.selectedTab = newValue
            playButtonClick()
        }
    }

    init(
        router: TabRouter,
        playButtonClick: @escaping () -> Void
    ) {
        self.router = router
        self.playButtonClick = playButtonClick
    }
}

/// The two top-level tabs. Each tab's root screen owns its own navigation stack.
struct RootView<ViewModel: RootViewModelProtocol, Home: View, Reports: View>: View {
    @State private var viewModel: ViewModel
    private let home: Home
    private let reports: Reports

    init(
        viewModel: ViewModel,
        home: Home,
        reports: Reports
    ) {
        _viewModel = State(initialValue: viewModel)
        self.home = home
        self.reports = reports
    }

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            home
                .tabItem { Label("tab.home", systemImage: "house") }
                .tag(AppTab.home)

            reports
                .tabItem { Label("tab.reports", systemImage: "chart.bar.xaxis") }
                .tag(AppTab.reports)
        }
        // The system tab bar sits at the top on iPadOS 18 and at the bottom on iPadOS 17.
        .tint(TherapyPalette.action)
    }
}
