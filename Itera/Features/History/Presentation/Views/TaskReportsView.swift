//
//  TaskReportsView.swift
//  Itera
//
//  Created by dimaswisodewo on 05/11/2026.
//

import SwiftUI

struct TMTaskReportsView: View {
    @State var model: TaskReportsViewModel
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        List {
            if model.loading {
                ProgressView()
            }
            if let key = model.errorKey {
                Section {
                    Text(LocalizedStringKey(key))
                    TMTherapyButton(title: "action.retry") { Task { await model.load() } }
                }
            }
            if model.unreadableCount > 0 {
                Label("history.someUnreadable \(model.unreadableCount)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(TherapyPalette.muted)
            }
            if !model.loading, model.errorKey == nil, model.summaries.isEmpty {
                Text(model.category == .taskOriented ? "towel.historyEmpty" : "history.arm.empty")
            }
            ForEach(model.summaries) { summary in
                Section {
                    Text(summary.startedAt, format: .dateTime.day().month(.wide).year().hour().minute())
                        .typography(.headline)
                    Text(summary.interrupted ? "session.interrupted" : (summary.stopped ? "session.stopped" : "session.complete"))
                    ForEach(model.results(in: summary), id: \.executionID) { result in
                        resultRow(result)
                    }
                    TMTherapyButton(title: "history.report.open", symbol: "figure.arms.open") {
                        router.push(.sessionReport(summary.id))
                    }
                    TMTherapyButton(title: "towel.deleteHistory", secondary: true) {
                        Task { await model.delete(summary.id) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TherapyPalette.cream)
        .navigationTitle(model.category == .taskOriented ? "towel.history" : "history.arm.title")
        .task { await model.load() }
    }

    private func resultRow(_ result: SessionActivityResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(result.activity.kind.titleKey)).typography(.headline)
            Text(result.activity.side == .left ? "session.left" : "session.right")
            Text("session.setProgress \(result.setNumber ?? 1) \(result.activity.sets)")
            Text(verbatim: "\(result.completedWork) / \(result.activity.goal)")
                .typography(.title2)
            Text(LocalizedStringKey("session.outcome." + result.outcome.rawValue))
        }
    }

}
