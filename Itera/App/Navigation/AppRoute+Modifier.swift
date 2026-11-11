//
//  AppRoute+Modifier.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import SwiftUI

private struct TMRouterViewModifier: ViewModifier {
    @Environment(NavigationRouter.self) private var router
    @Environment(\.buttonFeedback) private var buttonFeedback

    func body(content: Content) -> some View {
        @Bindable var router = router

        TabView(selection: Binding(
            get: { router.selectedTab },
            set: { tab in
                if router.selectedTab != tab {
                    buttonFeedback()
                }
                router.selectedTab = tab
            }
        )) {
            NavigationStack(path: $router.homePath) {
                content
                    .navigationDestination(for: AppRoute.self) {
                        AppRouterView.destination($0)
                    }
            }
            .tabItem { Label("tab.home", systemImage: "house") }
            .tag(AppTab.home)

            NavigationStack(path: $router.reportsPath) {
                TMFingerReportsView()
                    .navigationDestination(for: AppRoute.self) {
                        AppRouterView.destination($0)
                    }
            }
            .tabItem { Label("tab.reports", systemImage: "chart.bar.xaxis") }
            .tag(AppTab.reports)
        }
        // The system tab bar sits at the top on iPadOS 18 and at the bottom on iPadOS 17.
        .tint(TherapyPalette.action)
        .modifier(TMModalStackModifier(index: 0, isCover: false))
        .modifier(TMModalStackModifier(index: 0, isCover: true))
    }
}

private struct TMModalStackModifier: ViewModifier {
    @Environment(NavigationRouter.self) private var router
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PermissionManager.self) private var permissions
    @Environment(\.buttonFeedback) private var buttonFeedback
    let index: Int
    let isCover: Bool
    var sheetHostCoverID: UUID? = nil

    private var presentations: [RoutePresentation] {
        isCover ? router.presentedFullScreenCovers : router.presentedSheets
    }

    private var presentation: Binding<RoutePresentation?> {
        Binding(
            get: {
                // Sheets belong to the visible cover, or the root when no cover is open.
                if !isCover, router.presentedFullScreenCovers.last?.id != sheetHostCoverID {
                    return nil
                }
                return presentations.indices.contains(index) ? presentations[index] : nil
            },
            set: { value in
                guard value == nil, presentations.indices.contains(index) else { return }

                // Dismissing a parent also clears its nested presentations.
                if isCover {
                    router.presentedFullScreenCovers.removeSubrange(index...)
                } else {
                    router.presentedSheets.removeSubrange(index...)
                }
            }
        )
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if isCover {
            content.fullScreenCover(item: presentation) { item in
                modalContent(item)
            }
        } else {
            content.sheet(item: presentation) { item in
                modalContent(item)
            }
        }
    }

    private func modalContent(_ item: RoutePresentation) -> some View {
        Group {
            if isCover {
                TMFullScreenRouteContent(presentation: item)
                    .modifier(TMModalStackModifier(index: 0, isCover: false, sheetHostCoverID: item.id))
            } else {
                NavigationStack {
                    AppRouterView.destination(item.route)
                }
            }
        }
        .modifier(TMModalStackModifier(index: index + 1, isCover: isCover, sheetHostCoverID: sheetHostCoverID))
        // Applied last so nested presentations see them too; Mac Catalyst does not
        // reliably forward the presenter's environment into sheet and cover content.
        .environment(router)
        .environment(dependencies)
        .environment(permissions)
        .environment(\.buttonFeedback, buttonFeedback)
        .typography(.body)
        .buttonStyle(TMTherapySoundButtonStyle())
    }
}

/// A full-screen presentation stays mounted while its destination changes.
private struct TMFullScreenRouteContent: View {
    @Environment(NavigationRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let presentation: RoutePresentation
    @State private var displayedRoute: AppRoute?

    private var currentRoute: AppRoute? {
        router.presentedFullScreenCovers.first { $0.id == presentation.id }?.route
    }

    var body: some View {
        let route = displayedRoute ?? presentation.route

        ZStack {
            TherapyPalette.canvas.ignoresSafeArea()
            AppRouterView.destination(route)
                .id(route)
                .transition(.opacity)
        }
        .onChange(of: currentRoute, initial: true) { _, route in
            guard let route else {
                return
            }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                displayedRoute = route
            }
        }
    }
}

extension View {
    func withAppRouter() -> some View {
        modifier(TMRouterViewModifier())
    }
}
