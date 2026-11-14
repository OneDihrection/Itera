//
//  Prescription.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import Foundation

// MARK: - Role

/// Who uses this iPad (ADR-008). Chosen once on first launch.
enum AppRole: String, CaseIterable, Identifiable {
    case doctor
    case patient

    static let storageKey = "app.role"

    var id: String { rawValue }

    static var saved: AppRole? {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppRole.init(rawValue:))
    }
}

// MARK: - Items

/// Sides travel in prescriptions and results by their raw value.
extension HandSide: Codable {}

/// The side a doctor assigns. Exercises without a side store `nil` instead.
enum PrescribedSide: String, Codable, CaseIterable, Identifiable {
    case left, right, both

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .left:
            return "session.left"
        case .right:
            return "session.right"
        case .both:
            return "prescription.side.both"
        }
    }
}

/// One exercise of a prescription, with every value the doctor chose. The patient app never
/// edits these; it reads them at launch.
struct PrescriptionItem: Identifiable, Codable, Hashable {
    var id = UUID()
    /// The catalog id: a `DailyPlanItem` id such as `fullFist` or `armRaise`.
    var exercise: String
    var side: PrescribedSide?
    /// Which side runs first when `side` is `.both`.
    var firstSide: HandSide = .left
    var sets: Int
    /// Repetitions, rounds or towels, by `ExerciseMeasures.unit`.
    var work: Int
    /// Seconds each position is held, for exercises with `ExerciseMeasures.hasHold`.
    var holdSeconds: Int?
    /// Rest between sets, and between the sides of a "both" item.
    var setRestSeconds: Int
    /// Breathing rest before the next exercise, in 12-second breaths; 0 skips it.
    var breathsBeforeNext: Int

    /// A new item with the exercise's defaults.
    init(exercise: DailyPlanItem) {
        let measures = ExerciseMeasures(exercise.exercise)
        self.exercise = exercise.id
        side = measures.sides.first.map { _ in .right }
        sets = 2
        work = measures.defaultWork
        holdSeconds = measures.hasHold ? 10 : nil
        setRestSeconds = 20
        breathsBeforeNext = 6
    }

    var catalogItem: DailyPlanItem? {
        PrescriptionCatalog.item(for: exercise)
    }
}

/// One published version. Versions never change after publishing, so results can name the
/// targets they ran against.
struct Prescription: Codable, Equatable {
    var version: Int
    var publishedAt: Date
    var items: [PrescriptionItem]
}

// MARK: - Measures

/// What each exercise lets the doctor set. The editor and the patient's session launch both
/// read this one table, so they cannot disagree.
struct ExerciseMeasures {
    enum Unit {
        case repetitions, rounds, towels

        var titleKey: String {
            switch self {
            case .repetitions:
                return "prescription.unit.repetitions"
            case .rounds:
                return "prescription.unit.rounds"
            case .towels:
                return "prescription.unit.towels"
            }
        }
    }

    let unit: Unit
    let workRange: ClosedRange<Int>
    let defaultWork: Int
    let hasHold: Bool
    /// The sides the doctor may choose; empty for exercises without a side.
    let sides: [PrescribedSide]

    static let setsRange = 1...5
    static let holdRange = 3...20
    static let setRestRange = 5...120
    static let breathsRange = 0...10

    init(_ exercise: DailyPlanItem.Exercise) {
        switch exercise {
        case .finger:
            // Finger sessions run one hand at a time.
            self.init(unit: .repetitions, workRange: 1...20, defaultWork: 5, hasHold: false, sides: [.left, .right])
        case .therapy(.armRaise), .therapy(.elbowBend):
            self.init(unit: .repetitions, workRange: 1...20, defaultWork: 5, hasHold: false, sides: PrescribedSide.allCases)
        case .therapy(.foldTowel):
            self.init(unit: .towels, workRange: 1...10, defaultWork: 1, hasHold: false, sides: PrescribedSide.allCases)
        case .therapy:
            // Directional reach and cup count rounds.
            self.init(unit: .rounds, workRange: 1...10, defaultWork: 1, hasHold: false, sides: PrescribedSide.allCases)
        case .balance(let balance) where balance.isSitToStand:
            self.init(unit: .repetitions, workRange: 1...20, defaultWork: 6, hasHold: false, sides: [])
        case .balance:
            self.init(unit: .repetitions, workRange: 1...20, defaultWork: 6, hasHold: true, sides: PrescribedSide.allCases)
        }
    }

    private init(unit: Unit, workRange: ClosedRange<Int>, defaultWork: Int, hasHold: Bool, sides: [PrescribedSide]) {
        self.unit = unit
        self.workRange = workRange
        self.defaultWork = defaultWork
        self.hasHold = hasHold
        self.sides = sides
    }

    /// Whether an item's values fit this exercise. Data from iCloud is validated with this
    /// before the patient app uses it.
    func accepts(_ item: PrescriptionItem) -> Bool {
        let sideFits = sides.isEmpty ? item.side == nil : item.side.map(sides.contains) ?? false
        let holdFits = hasHold
            ? item.holdSeconds.map(Self.holdRange.contains) ?? false
            : item.holdSeconds == nil

        return sideFits
            && holdFits
            && Self.setsRange.contains(item.sets)
            && workRange.contains(item.work)
            && Self.setRestRange.contains(item.setRestSeconds)
            && Self.breathsRange.contains(item.breathsBeforeNext)
    }
}

extension Prescription {
    /// A prescription the patient app may run: every item a known exercise with valid values.
    var isValid: Bool {
        version >= 1
            && !items.isEmpty
            && items.allSatisfy { item in
                item.catalogItem.map { ExerciseMeasures($0.exercise).accepts(item) } ?? false
            }
    }

    /// Seconds of practice-free time: rests between sets and breathing rests, for the editor's
    /// estimate. Exercise durations depend on the patient and are not estimated.
    var restSeconds: Int {
        items.indices.reduce(0) { total, index in
            let item = items[index]
            let sides = item.side == .both ? 2 : 1
            let setRests = (item.sets * sides - 1) * item.setRestSeconds
            let isLast = index == items.count - 1
            let breathing = isLast ? 0 : Int(Double(item.breathsBeforeNext) * LongRestBreath.cycleDuration)

            return total + setRests + breathing
        }
    }
}

// MARK: - Catalog

/// Every exercise a doctor can assign. Shown only in doctor mode.
enum PrescriptionCatalog {
    static let items = DailyPlan.standard

    static func item(for id: String) -> DailyPlanItem? {
        items.first { $0.id == id }
    }

    enum Group: String, CaseIterable, Identifiable {
        case fingers, arm, balance, task

        var id: String { rawValue }
        var titleKey: String { "prescription.group.\(rawValue)" }
    }

    static func group(of item: DailyPlanItem) -> Group {
        switch item.exercise {
        case .finger:
            return .fingers
        case .therapy(.foldTowel):
            return .task
        case .therapy:
            return .arm
        case .balance:
            return .balance
        }
    }
}
