//
//  HistoryCellBuilder.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import SwiftUI

/// What a history row needs: the router it navigates with.
@MainActor
protocol HistoryCellDependency {
    var router: HistoryRouter { get }
}

@MainActor
final class HistoryCellComponent: Component<HistoryCellDependency> {
    let router: HistoryRouter

    init(dependency: HistoryCellDependency) {
        self.router = dependency.router
        super.init(with: dependency)
    }
}

protocol HistoryCellBuildable {
    associatedtype CellContent: View

    @ViewBuilder @MainActor func buildCell(entry: HistoryEntry) -> CellContent
}

/// No tap closure: the router is injected, so the row handles navigation itself.
@MainActor
final class HistoryCellBuilder: HistoryCellBuildable {
    private let component: HistoryCellComponent

    init(component: HistoryCellComponent) {
        self.component = component
    }

    @ViewBuilder func buildCell(entry: HistoryEntry) -> some View {
        let viewModel: some HistoryCellViewModelProtocol = HistoryCellViewModel(
            entry: entry,
            router: component.router
        )

        TMHistoryCellView(viewModel: viewModel)
    }
}
