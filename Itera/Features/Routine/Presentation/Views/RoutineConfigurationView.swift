//
//  RoutineConfigurationView.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import SwiftUI

struct TMRoutineConfigurationView: View {
    let category: TherapyCategory
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PermissionManager.self) private var permissions
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        TMRoutineEditor(
            category: category,
            model: dependencies.routineModel(for: category),
            readiness: HomeViewModel(permissions: permissions, audio: dependencies.audio, history: dependencies)
        )
    }
}

private struct TMRoutineEditor: View {
    @Environment(NavigationRouter.self) private var router
    @Environment(AppDependencies.self) private var dependencies
    let category: TherapyCategory
    @Bindable var model: RoutineViewModel
    @State var readiness: HomeViewModel

    var body: some View {
        List {
            Section {
                Text("routine.heading").typography(.largeTitle)
                Text("routine.detail")
                Text("routine.phases")
                Text(LocalizedStringKey(category.positioningKey))
            }
            Section("routine.exercises") {
                ForEach($model.configuration.exercises) { $exercise in
                    TMRoutineExerciseRow(exercise: $exercise)
                        .listRowBackground(TherapyPalette.surface)
                }
                .onMove { model.configuration.exercises.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { model.configuration.exercises.remove(atOffsets: $0) }
                Button("routine.add", systemImage: "plus.circle") {
                    router.presentSheet(.exercisePicker(category))
                }
            }
            Section {
                DisclosureGroup("routine.options") {
                    Stepper(value: $model.configuration.restSeconds, in: 0...120, step: 5) {
                        Text("routine.rest \(model.configuration.restSeconds)")
                    }
                    Stepper(value: $model.configuration.practiceSeconds, in: 10...600, step: 10) {
                        Text("routine.duration \(model.configuration.practiceSeconds)")
                    }
                    Text("routine.voiceRequired")
                    Button("routine.delete", role: .destructive) {
                        Task { await model.deleteSaved() }
                    }
                }
            }
            Section("routine.voiceCommands") {
                Text("routine.distanceDetail")
                Text("routine.englishCommandsDetail")
                ForEach([
                    "routine.voicePhrase.pause",
                    "routine.voicePhrase.resume",
                ], id: \.self) { phrase in
                    Label(LocalizedStringKey(phrase), systemImage: "waveform")
                }
            }
            Section {
                Text(LocalizedStringKey(readiness.message))
                if let failure = model.failure {
                    Text(verbatim: failure).foregroundStyle(.red)
                    Button("home.retry") { Task { await model.load() } }
                }
                TMTherapyButton(title: "therapy.session.start", symbol: "play.fill") {
                    Task {
                        guard await model.save(), await readiness.performAction() else { return }
                        dependencies.selectedRoutine = model.configuration.snapshot
                        router.push(.therapySession)
                    }
                }
                .disabled(model.loadFailed || model.loading || model.saving || model.configuration.exercises.isEmpty)
                Text("routine.comfort").typography(.footnote)
            }
        }
        .scrollContentBackground(.hidden)
        .background(TherapyPalette.cream)
        .listStyle(.insetGrouped)
        .navigationTitle("therapy.session.title")
        .toolbar { EditButton() }
        .task {
            await model.load()
            readiness.refresh()
        }
    }
}

private struct TMRoutineExerciseRow: View {
    @Binding var exercise: RoutineExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey("session." + exercise.kind.rawValue)).typography(.headline)
            Picker("routine.side", selection: $exercise.sides) {
                Text("session.left").tag(RoutineSides.left)
                Text("session.right").tag(RoutineSides.right)
                if exercise.kind == .armRaise || exercise.kind == .elbowBend || exercise.kind == .foldTowel {
                    Text("routine.both").tag(RoutineSides.both)
                }
            }
            .pickerStyle(.segmented)
            if exercise.sides == .both {
                Picker("routine.first", selection: $exercise.firstSide) {
                    Text("session.left").tag(TherapySide.left)
                    Text("session.right").tag(TherapySide.right)
                }
                .pickerStyle(.segmented)
            }
            Stepper(value: $exercise.sets, in: 1...5) {
                Text("routine.sets \(exercise.sets)")
            }
            Text("routine.perSet")
            if exercise.kind == .foldTowel {
                Text("towel.routineDetail")
            }
            if exercise.kind == .armRaise || exercise.kind == .elbowBend || exercise.kind == .foldTowel {
                if exercise.sides != .right {
                    Stepper(value: $exercise.leftGoal, in: 1...100) {
                        Text("routine.leftGoal \(exercise.leftGoal)")
                    }
                }
                if exercise.sides != .left {
                    Stepper(value: $exercise.rightGoal, in: 1...100) {
                        Text("routine.rightGoal \(exercise.rightGoal)")
                    }
                }
            } else {
                Stepper(value: $exercise.rounds, in: 1...10) {
                    Text("routine.rounds \(exercise.rounds)")
                }
                Text("routine.reachDetail")
            }
        }
        .padding(.vertical, 8)
    }
}

struct TMRoutineExercisePicker: View {
    let category: TherapyCategory
    @Environment(AppDependencies.self) private var dependencies
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("routine.add").typography(.title2)
                Spacer()
                Button("routine.close") { router.dismissSheet() }
            }
            .padding()
            List(category.kinds, id: \.self) { kind in
                let added = dependencies.routineModel(for: category).configuration.exercises.contains { $0.kind == kind }
                Button {
                    dependencies.routineModel(for: category).add(kind)
                    router.dismissSheet()
                } label: {
                    HStack {
                        Text(LocalizedStringKey("session." + kind.rawValue))
                        Spacer()
                        Image(systemName: added ? "checkmark" : "plus.circle")
                    }
                }
                .disabled(added)
            }
        }
    }
}
