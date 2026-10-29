//
//  NavigationRouter.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Observation

@MainActor
@Observable
final class NavigationRouter {
    var selectedTab: AppTab = .home
    var homePath: [AppRoute] = []
    var reportsPath: [AppRoute] = []

    var path: [AppRoute] {
        get { selectedTab == .home ? homePath : reportsPath }
        set {
            if selectedTab == .home {
                homePath = newValue
            } else {
                reportsPath = newValue
            }
        }
    }
    var presentedSheets: [RoutePresentation] = []
    var presentedFullScreenCovers: [RoutePresentation] = []

    func push(_ route: AppRoute) {
        switch route {
        case .home:
            popToRoot()
        case .reports:
            selectedTab = .reports
            reportsPath.removeAll()
        case .report:
            selectedTab = .reports
            reportsPath.append(route)
        case .plan:
            selectedTab = .home
            homePath.append(route)
        default:
            path.append(route)
        }
    }

    func presentAchievementCelebration() {
        guard presentedSheets.isEmpty, presentedFullScreenCovers.isEmpty else {
            return
        }
        presentSheet(.achievementCelebration)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        homePath.removeAll()
        reportsPath.removeAll()
        selectedTab = .home
    }

    func replace(_ route: AppRoute, with replacement: AppRoute) {
        guard let index = path.firstIndex(of: route) else {
            push(replacement)
            return
        }

        path[index] = replacement
    }

    func presentSheet(_ route: AppRoute) {
        presentedSheets.append(RoutePresentation(route: route))
    }

    func presentFullScreenCover(_ route: AppRoute) {
        presentedFullScreenCovers.append(RoutePresentation(route: route))
    }

    func dismissSheet() {
        guard !presentedSheets.isEmpty else { return }
        presentedSheets.removeLast()
    }

    func replaceFullScreenCover(with route: AppRoute) {
        guard !presentedFullScreenCovers.isEmpty else { return }
        presentedFullScreenCovers[presentedFullScreenCovers.count - 1] = RoutePresentation(route: route)
    }

    func dismissFullScreenCover() {
        guard !presentedFullScreenCovers.isEmpty else { return }
        presentedFullScreenCovers.removeLast()
    }

    func dismiss() {
        presentedSheets.removeAll()
        presentedFullScreenCovers.removeAll()
    }
}
