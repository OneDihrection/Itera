//
//  DebugPlanEditorView.swift
//  Tuntun
//
//  Created by dimaswisodewo on 15/11/2026.
//

#if DEBUG
import SwiftUI

/// Debug builds only: chooses which daily-plan exercises Beranda shows, their order, and
/// custom sets and repetitions per exercise. Edits a copy and applies it on Done.
struct TMDebugPlanEditorView: View {
    @Environment(NavigationRouter.self) private var router
    @Environment(AppDependencies.self) private var dependencies
    @State private var layout: DebugPlanLayout?

    var body: some View {
        List {
            noticeSection
            entriesSection
        }
        .environment(\.editMode, .constant(.active))
        .typography(.body)
        .tint(TherapyPalette.green)
        .navigationTitle("debug.planEditor.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            toolbarContent
        }
        .presentationDetents([.large])
        .onAppear {
            guard layout == nil else {
                return
            }

            layout = dependencies.dailyPlan.debugLayout
        }
    }

    // MARK: - Sections

    private var noticeSection: some View {
        Section {
            Text("debug.planEditor.help")
                .typography(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .debugOnly()
        }
    }

    @ViewBuilder
    private var entriesSection: some View {
        if let layout {
            Section {
                ForEach(layout.entries) { entry in
                    entryRow(entry)
                }
                .onMove { source, destination in
                    self.layout?.entries.move(fromOffsets: source, toOffset: destination)
                }
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: DebugPlanLayout.Entry) -> some View {
        let plan = dependencies.dailyPlan

        if let item = plan.standardItems.first(where: { $0.id == entry.itemID }),
           let binding = binding(for: entry.itemID) {
            let counts = plan.debugCounts(for: item, in: dependencies)

            TMDebugPlanEntryRow(
                entry: binding,
                titleKey: DailyPlanViewModel.titleKey(for: item.exercise),
                currentSets: counts.sets,
                currentRepetitions: counts.repetitions
            )
        }
    }

    private func binding(for itemID: String) -> Binding<DebugPlanLayout.Entry>? {
        guard let index = layout?.entries.firstIndex(where: { $0.itemID == itemID }) else {
            return nil
        }

        return Binding(
            get: { layout?.entries[index] ?? DebugPlanLayout.Entry(itemID: itemID) },
            set: { layout?.entries[index] = $0 }
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("debug.planEditor.reset") {
                layout = .standard(dependencies.dailyPlan.standardItems)
            }
            .typography(.body)
            .frame(minHeight: 44)
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("action.done") {
                if let layout {
                    dependencies.dailyPlan.applyDebugLayout(layout)
                }

                router.dismissSheet()
            }
            .typography(.headline)
            .frame(minHeight: 44)
        }
    }
}

// MARK: - Row

/// One exercise: shown on Beranda, and optional custom sets and repetitions.
private struct TMDebugPlanEntryRow: View {
    @Binding var entry: DebugPlanLayout.Entry
    let titleKey: String
    /// What the exercise runs with now; a newly customized entry starts from these.
    let currentSets: Int
    let currentRepetitions: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $entry.isShown) {
                Text(LocalizedStringKey(titleKey))
                    .typography(.headline)
            }
            .frame(minHeight: 44)

            Toggle("debug.planEditor.customCounts", isOn: customCounts)
                .frame(minHeight: 44)

            if entry.hasCustomCounts {
                countControls
            }
        }
        .padding(.vertical, 4)
        .opacity(entry.isShown ? 1 : 0.5)
    }

    @ViewBuilder
    private var countControls: some View {
        TMTherapyNumberControl(
            title: "plan.setsShort",
            value: sets,
            range: DebugPlanLayout.setsRange,
            showsBackground: false
        )

        TMTherapyNumberControl(
            title: "plan.repsShort",
            value: repetitions,
            range: DebugPlanLayout.repetitionsRange,
            showsBackground: false
        )
    }

    /// Turning custom counts on saves both values, so the entry stays customized.
    private var customCounts: Binding<Bool> {
        Binding(
            get: { entry.hasCustomCounts },
            set: { isOn in
                entry.sets = isOn ? clamped(currentSets, to: DebugPlanLayout.setsRange) : nil
                entry.repetitions = isOn
                    ? clamped(currentRepetitions, to: DebugPlanLayout.repetitionsRange)
                    : nil
            }
        )
    }

    private var sets: Binding<Int> {
        Binding(
            get: { entry.sets ?? currentSets },
            set: { entry.sets = $0 }
        )
    }

    private var repetitions: Binding<Int> {
        Binding(
            get: { entry.repetitions ?? currentRepetitions },
            set: { entry.repetitions = $0 }
        )
    }

    private func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }
}
#endif
