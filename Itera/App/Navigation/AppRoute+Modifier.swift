//
//  AppRoute+Modifier.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import SwiftUI

private struct RouterViewModifier: ViewModifier {
    @Environment(NavigationRouter.self) private var router

    func body(content: Content) -> some View {
        @Bindable var router = router

        NavigationStack(path: $router.path) {
            content
                .navigationDestination(for: AppRoute.self) {
                    AppRouterView.destination($0)
                }
                .modifier(ModalStackModifier(index: 0, isCover: false))
                .modifier(ModalStackModifier(index: 0, isCover: true))
        }
    }
}

private struct ModalStackModifier: ViewModifier {
    @Environment(NavigationRouter.self) private var router
    let index: Int
    let isCover: Bool

    private var presentations: [RoutePresentation] {
        isCover ? router.presentedFullScreenCovers : router.presentedSheets
    }

    private var presentation: Binding<RoutePresentation?> {
        Binding(
            get: {
                presentations.indices.contains(index) ? presentations[index] : nil
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
        AppRouterView.destination(item.route)
            .environment(router)
            .modifier(ModalStackModifier(index: index + 1, isCover: isCover))
    }
}

extension View {
    func withAppRouter() -> some View {
        modifier(RouterViewModifier())
    }
}
