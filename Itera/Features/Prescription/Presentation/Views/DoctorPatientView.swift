//
//  DoctorPatientView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import SwiftUI
import UniformTypeIdentifiers

/// One patient in doctor mode: the prescription editor and the patient's progress.
struct TMDoctorPatientView: View {
    let patientID: UUID
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router
    @State private var tab = Tab.prescription
    @State private var confirmingRemoval = false

    enum Tab: Hashable {
        case prescription, progress
    }

    private var doctor: DoctorCareViewModel { dependencies.doctor }

    var body: some View {
        Group {
            if let patient = doctor.patient(patientID) {
                VStack(spacing: 20) {
                    Picker("doctor.section", selection: $tab) {
                        Text("doctor.prescription").tag(Tab.prescription)
                        Text("doctor.progress").tag(Tab.progress)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 520)

                    if let key = doctor.errorKey {
                        TMTherapyError(key: key, detail: doctor.errorDetail)
                    }

                    switch tab {
                    case .prescription:
                        TMPrescriptionEditorView(patient: patient)
                    case .progress:
                        TMDoctorPatientProgressView(patient: patient)
                    }
                }
                .padding(24)
                .navigationTitle(Text(verbatim: patient.name))
                .toolbar { toolbar(patient) }
            } else {
                Text("doctor.patientMissing").typography(.body)
            }
        }
        .foregroundStyle(TherapyPalette.ink)
        .background(TherapyPalette.canvas)
        .confirmationDialog("doctor.removeTitle", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("doctor.remove", role: .destructive) {
                Task {
                    await doctor.removePatient(patientID)
                    router.pop()
                }
            }
        } message: {
            Text("doctor.removeMessage")
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ patient: DoctorPatient) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    doctor.startPairing(for: patient.id)
                    router.presentSheet(.doctorPairing(patient.id))
                } label: {
                    Label(patient.paired ? "doctor.pairAgain" : "doctor.pair", systemImage: "qrcode")
                }
                Button(role: .destructive) {
                    confirmingRemoval = true
                } label: {
                    Label("doctor.remove", systemImage: "person.badge.minus")
                }
            } label: {
                Label("doctor.more", systemImage: "ellipsis.circle")
            }
        }
    }
}

// MARK: - Prescription editor

/// Two panes: the catalog (only here, in doctor mode) and the patient's ordered prescription.
/// Exercises are added by tapping or dragging, reordered by dragging and removed by swiping.
struct TMPrescriptionEditorView: View {
    let patient: DoctorPatient
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router

    private var draft: [PrescriptionItem] { patient.draft }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            catalog
                .frame(width: 340)
            VStack(spacing: 16) {
                prescriptionList
                publishBar
            }
        }
    }

    // MARK: Catalog

    private var catalog: some View {
        List {
            ForEach(PrescriptionCatalog.Group.allCases) { group in
                Section {
                    ForEach(PrescriptionCatalog.items.filter { PrescriptionCatalog.group(of: $0) == group }) { item in
                        catalogRow(item)
                    }
                } header: {
                    Text(LocalizedStringKey(group.titleKey)).typography(.headline)
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay(alignment: .top) {
            Text("doctor.catalog")
                .typography(.footnote)
                .foregroundStyle(TherapyPalette.muted)
                .padding(.top, 4)
        }
    }

    private func catalogRow(_ item: DailyPlanItem) -> some View {
        let added = draft.contains { $0.exercise == item.id }

        return HStack {
            Text(LocalizedStringKey(DailyPlanViewModel.titleKey(for: item.exercise)))
                .typography(.body)
            Spacer()
            Button {
                add(item, at: draft.count)
            } label: {
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .typography(size: 26, weight: .regular, relativeTo: .title3)
            }
            .disabled(added)
            .accessibilityLabel(Text("doctor.addExercise"))
        }
        .frame(minHeight: 44)
        .draggable(item.id)
    }

    // MARK: Prescription

    private var prescriptionList: some View {
        List {
            Section {
                if draft.isEmpty {
                    Text("doctor.emptyPrescription")
                        .typography(.body)
                        .foregroundStyle(TherapyPalette.muted)
                        .frame(minHeight: 120)
                        .dropDestination(for: String.self) { ids, _ in
                            insert(ids, at: 0)
                        }
                }

                ForEach(Array(draft.enumerated()), id: \.element.id) { index, item in
                    Button {
                        router.presentSheet(.prescriptionItem(patient: patient.id, item: item.id))
                    } label: {
                        prescriptionRow(item, number: index + 1)
                    }
                    .buttonStyle(TMTherapySoundButtonStyle())
                }
                .onMove { from, to in
                    var items = draft
                    items.move(fromOffsets: from, toOffset: to)
                    dependencies.doctor.setDraft(items, for: patient.id)
                }
                .onDelete { offsets in
                    var items = draft
                    items.remove(atOffsets: offsets)
                    dependencies.doctor.setDraft(items, for: patient.id)
                }
                .dropDestination(for: String.self) { ids, index in
                    insert(ids, at: index)
                }
            } header: {
                HStack {
                    Text("doctor.prescriptionFor \(patient.name)").typography(.headline)
                    Spacer()
                    EditButton().typography(.subheadline)
                }
            } footer: {
                Text("doctor.editorHelp").typography(.footnote)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func prescriptionRow(_ item: PrescriptionItem, number: Int) -> some View {
        let catalogItem = item.catalogItem
        let measures = catalogItem.map { ExerciseMeasures($0.exercise) }

        return HStack(spacing: 16) {
            Text(verbatim: "\(number)")
                .typography(size: 22, weight: .bold, relativeTo: .headline)
                .foregroundStyle(TherapyPalette.brand)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 6) {
                if let catalogItem {
                    Text(LocalizedStringKey(DailyPlanViewModel.titleKey(for: catalogItem.exercise)))
                        .typography(size: 22, weight: .semiBold, relativeTo: .headline)
                }

                Text(TMPrescriptionText.summary(item, measures: measures))
                    .typography(.subheadline)
                    .foregroundStyle(TherapyPalette.muted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(TherapyPalette.muted)
                .accessibilityHidden(true)
        }
        .foregroundStyle(TherapyPalette.ink)
        .frame(minHeight: 64)
        .accessibilityElement(children: .combine)
    }

    // MARK: Publish

    private var publishBar: some View {
        let prescription = Prescription(version: 1, publishedAt: .now, items: draft)

        return HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(patient.hasUnpublishedChanges ? "doctor.unpublished" : "doctor.published")
                    .typography(.headline)
                Text("doctor.restTotal \(prescription.restSeconds / 60) \(prescription.restSeconds % 60)")
                    .typography(.footnote)
                    .foregroundStyle(TherapyPalette.muted)
            }

            Spacer()

            TMTherapyButton(
                title: "doctor.publish",
                symbol: "paperplane.fill",
                disabled: !patient.hasUnpublishedChanges || !prescription.isValid || dependencies.doctor.busy,
                pill: true,
                brand: true
            ) {
                Task { await dependencies.doctor.publish(patient.id) }
            }
            .frame(maxWidth: 320)
        }
        .padding(.horizontal, 8)
    }

    // MARK: Editing

    private func add(_ item: DailyPlanItem, at index: Int) {
        guard !draft.contains(where: { $0.exercise == item.id }) else {
            return
        }

        var items = draft
        items.insert(PrescriptionItem(exercise: item), at: min(index, items.count))
        dependencies.doctor.setDraft(items, for: patient.id)
    }

    /// Dropped catalog ids, each exercise at most once.
    @discardableResult
    private func insert(_ ids: [String], at index: Int) -> Bool {
        let new = ids.compactMap(PrescriptionCatalog.item(for:))

        guard !new.isEmpty else {
            return false
        }

        for (offset, item) in new.enumerated() {
            add(item, at: index + offset)
        }

        return true
    }
}

// MARK: - Item editor

/// Every value of one prescription item, limited to what its exercise uses.
struct TMPrescriptionItemEditor: View {
    let patientID: UUID
    let itemID: UUID
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router

    private var item: PrescriptionItem? {
        dependencies.doctor.patient(patientID)?.draft.first { $0.id == itemID }
    }

    var body: some View {
        Group {
            if let item, let catalogItem = item.catalogItem {
                form(item, measures: ExerciseMeasures(catalogItem.exercise))
                    .navigationTitle(LocalizedStringKey(DailyPlanViewModel.titleKey(for: catalogItem.exercise)))
            } else {
                Text("doctor.patientMissing").typography(.body)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("action.done") { router.dismissSheet() }
            }
        }
    }

    private func form(_ item: PrescriptionItem, measures: ExerciseMeasures) -> some View {
        Form {
            if !measures.sides.isEmpty {
                Section {
                    Picker("doctor.side", selection: binding(\.side, item)) {
                        ForEach(measures.sides) { side in
                            Text(LocalizedStringKey(side.titleKey)).tag(Optional(side))
                        }
                    }
                    .frame(minHeight: 56)

                    if item.side == .both {
                        Picker("doctor.firstSide", selection: binding(\.firstSide, item)) {
                            Text("session.left").tag(HandSide.left)
                            Text("session.right").tag(HandSide.right)
                        }
                        .frame(minHeight: 56)
                    }
                }
            }

            Section {
                TMTherapyNumberControl(title: "plan.setsShort", value: binding(\.sets, item), range: ExerciseMeasures.setsRange, showsBackground: false)
                TMTherapyNumberControl(title: LocalizedStringKey(measures.unit.titleKey), value: binding(\.work, item), range: measures.workRange, showsBackground: false)

                if measures.hasHold {
                    TMTherapyNumberControl(
                        title: "doctor.holdSeconds",
                        value: Binding(
                            get: { item.holdSeconds ?? 10 },
                            set: { value in change(item) { $0.holdSeconds = value } }
                        ),
                        range: ExerciseMeasures.holdRange,
                        showsBackground: false
                    )
                }
            } header: {
                Text("doctor.workTitle").typography(.headline)
            }

            Section {
                TMTherapyNumberControl(
                    title: "doctor.setRest",
                    value: binding(\.setRestSeconds, item),
                    range: ExerciseMeasures.setRestRange,
                    step: 5,
                    showsBackground: false
                )
                TMTherapyNumberControl(
                    title: "doctor.breaths",
                    value: binding(\.breathsBeforeNext, item),
                    range: ExerciseMeasures.breathsRange,
                    showsBackground: false
                )
            } header: {
                Text("doctor.restTitle").typography(.headline)
            } footer: {
                Text("doctor.restHelp \(Int(Double(item.breathsBeforeNext) * LongRestBreath.cycleDuration))")
                    .typography(.footnote)
            }
        }
        .typography(.body)
    }

    private func binding<Value>(_ path: WritableKeyPath<PrescriptionItem, Value>, _ item: PrescriptionItem) -> Binding<Value> {
        Binding(
            get: { item[keyPath: path] },
            set: { value in change(item) { $0[keyPath: path] = value } }
        )
    }

    private func change(_ item: PrescriptionItem, _ edit: (inout PrescriptionItem) -> Void) {
        guard var items = dependencies.doctor.patient(patientID)?.draft,
              let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        edit(&items[index])
        dependencies.doctor.setDraft(items, for: patientID)
    }
}

enum TMPrescriptionText {
    /// "3 set · 8 repetisi · istirahat 20 dtk · 6 napas" for a row.
    static func summary(_ item: PrescriptionItem, measures: ExerciseMeasures?) -> LocalizedStringKey {
        let side = item.side.map { String(localized: String.LocalizationValue($0.titleKey), bundle: AppLanguage.selected.resourceBundle) } ?? "–"
        let unit = String(localized: String.LocalizationValue(measures?.unit.titleKey ?? "prescription.unit.repetitions"), bundle: AppLanguage.selected.resourceBundle)

        return "doctor.itemSummary \(item.sets) \(item.work) \(unit) \(item.setRestSeconds) \(item.breathsBeforeNext) \(side)"
    }
}

// MARK: - Progress

/// The patient's sent results, newest first, against the prescription version in force.
struct TMDoctorPatientProgressView: View {
    let patient: DoctorPatient
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if !patient.paired {
                    Text("doctor.progressNotPaired").typography(.body).foregroundStyle(TherapyPalette.muted)
                } else if patient.results.isEmpty {
                    Text("doctor.progressEmpty").typography(.body).foregroundStyle(TherapyPalette.muted)
                }

                ForEach(patient.results) { result in
                    resultCard(result)
                }

                if !patient.results.isEmpty {
                    Text("report.angleNote")
                        .typography(.footnote)
                        .foregroundStyle(TherapyPalette.muted)
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await dependencies.doctor.refreshResults() }
        .task { await dependencies.doctor.refreshResults() }
    }

    private func resultCard(_ result: SharedExerciseResult) -> some View {
        TMTherapyCard(color: TherapyPalette.canvas, outlined: true, padding: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    if let item = PrescriptionCatalog.item(for: result.exercise) {
                        Text(LocalizedStringKey(DailyPlanViewModel.titleKey(for: item.exercise)))
                            .typography(size: 22, weight: .semiBold, relativeTo: .headline)
                    }
                    if let side = result.side {
                        Text(side == .left ? "session.left" : "session.right")
                            .typography(.subheadline)
                            .foregroundStyle(TherapyPalette.muted)
                    }
                    Spacer()
                    Text(result.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                        .typography(.subheadline)
                }

                HStack(spacing: 24) {
                    Label(result.completed ? "progress.outcome.completed" : "progress.partial",
                          systemImage: result.completed ? "checkmark" : "checkmark.square")
                    Text("doctor.resultSets \(result.completedSets) \(result.plannedSets)")
                    Text("doctor.resultWork \(result.work)")
                    if let version = result.prescriptionVersion {
                        Text("doctor.version \(version)")
                    }
                }
                .typography(.subheadline)

                ForEach(result.angles) { angle in
                    TMTherapyAngleReportCard(
                        title: LocalizedStringKey(angle.titleKey),
                        badge: angle.threeD ? "report.angle.source3D" : "report.angle.source2D",
                        lines: TMFingerAngleList.lines(before: angle.before, after: angle.after, change: angle.spanChange)
                    )
                }
            }
            .foregroundStyle(TherapyPalette.ink)
        }
    }
}
