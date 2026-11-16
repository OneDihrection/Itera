//
//  HistoryCellView.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import SwiftUI

/// One tappable session in "Riwayat latihan"; the row handles its own navigation.
struct TMHistoryCellView<ViewModel: HistoryCellViewModelProtocol>: View {
    /// Not owned: the list rebuilds rows from fresh entries, as the reference's
    /// `@ObservedObject` cell does.
    private let viewModel: ViewModel

    init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Button {
            viewModel.onTap()
        } label: {
            card
        }
        .buttonStyle(TMTherapySoundButtonStyle())
    }

    @ViewBuilder
    private var card: some View {
        switch viewModel.entry {
        case .finger(let summary):
            TMFingerHistoryCard(summary: summary)
        case .arm(let summary):
            TMMovementHistoryCard(summary: summary)
        }
    }
}

#if DEBUG
@MainActor
@Observable
private final class MockHistoryCellViewModel: HistoryCellViewModelProtocol {
    let entry = HistoryEntry.finger(
        FingerSessionSummary(
            id: UUID(),
            started: .now,
            ended: .now,
            routine: FingerRoutine(),
            results: [],
            outcome: .completed,
            feeling: nil,
            exerciseIndex: 0
        )
    )

    func onTap() {}
}

#Preview("History cell") {
    TMHistoryCellView(viewModel: MockHistoryCellViewModel())
        .padding()
}
#endif
