//
//  DebugPlanEditorViewModel.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

#if DEBUG
import Foundation
import Observation

/// What the editor shows for one exercise beside its toggle.
struct DebugPlanEntryInfo {
    let titleKey: String
    /// What the exercise runs with now; a newly customized entry starts from these.
    let currentSets: Int
    let currentRepetitions: Int
}

@MainActor
protocol DebugPlanEditorViewModelProtocol: AnyObject, Observable {
    /// The edited copy; nothing changes on Beranda until `apply()`.
    var layout: DebugPlanLayout { get set }

    func info(for itemID: String) -> DebugPlanEntryInfo?
    func reset()
    func apply()
}

/// Debug builds only: edits a copy of the plan's layout and applies it on Done.
@MainActor
@Observable
final class DebugPlanEditorViewModel: DebugPlanEditorViewModelProtocol {
    var layout: DebugPlanLayout

    @ObservationIgnored private let plan: DailyPlanViewModel

    init(plan: DailyPlanViewModel) {
        self.plan = plan
        self.layout = plan.debugLayout
    }

    func info(for itemID: String) -> DebugPlanEntryInfo? {
        guard let item = plan.standardItems.first(where: { $0.id == itemID }) else {
            return nil
        }

        let counts = plan.debugCounts(for: item)

        return DebugPlanEntryInfo(
            titleKey: DailyPlanViewModel.titleKey(for: item.exercise),
            currentSets: counts.sets,
            currentRepetitions: counts.repetitions
        )
    }

    func reset() {
        layout = .standard(plan.standardItems)
    }

    func apply() {
        plan.applyDebugLayout(layout)
    }
}
#endif
