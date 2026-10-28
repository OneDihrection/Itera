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
    var path: [AppRoute] = []
    var presentedSheets: [RoutePresentation] = []
    var presentedFullScreenCovers: [RoutePresentation] = []

    func push(_ route: AppRoute) {
        path.append(route)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path.removeAll()
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

    func dismissFullScreenCover() {
        guard !presentedFullScreenCovers.isEmpty else { return }
        presentedFullScreenCovers.removeLast()
    }

    func dismiss() {
        presentedSheets.removeAll()
        presentedFullScreenCovers.removeAll()
    }
}
