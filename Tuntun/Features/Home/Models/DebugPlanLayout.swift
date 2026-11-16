//
//  DebugPlanLayout.swift
//  Tuntun
//
//  Created by dimaswisodewo on 15/11/2026.
//

#if DEBUG
import Foundation

/// A debug-build arrangement of today's plan: which exercises Beranda shows, in what order,
/// and optional per-exercise set and repetition counts that replace the program's own.
///
/// Stores stable item ids only. Release builds always run `DailyPlan.standard`.
struct DebugPlanLayout: Codable, Equatable {
    struct Entry: Codable, Equatable, Identifiable {
        let itemID: String
        var isShown = true
        /// `nil` keeps the program's own setting.
        var sets: Int?
        var repetitions: Int?

        var id: String {
            itemID
        }

        var hasCustomCounts: Bool {
            sets != nil || repetitions != nil
        }
    }

    static let storageKey = "debug.dailyPlanLayout"
    static let setsRange = 1...5
    static let repetitionsRange = 1...20

    var entries: [Entry]

    /// Every standard item shown in its standard order, with no custom counts.
    static func standard(_ items: [DailyPlanItem]) -> DebugPlanLayout {
        DebugPlanLayout(entries: items.map { Entry(itemID: $0.id) })
    }

    /// Entries for every standard item: saved ones in their saved order, ids that no longer
    /// exist dropped, and exercises added to the plan later appended as shown.
    func reconciled(with standard: [DailyPlanItem]) -> DebugPlanLayout {
        let known = Set(standard.map(\.id))
        let kept = entries.filter { known.contains($0.itemID) }
        let keptIDs = Set(kept.map(\.itemID))

        let added = standard
            .filter { !keptIDs.contains($0.id) }
            .map { Entry(itemID: $0.id) }

        return DebugPlanLayout(entries: kept + added)
    }

    /// The shown items, in the layout's order.
    func items(from standard: [DailyPlanItem]) -> [DailyPlanItem] {
        let byID = Dictionary(uniqueKeysWithValues: standard.map { ($0.id, $0) })

        return reconciled(with: standard).entries
            .filter(\.isShown)
            .compactMap { byID[$0.itemID] }
    }

    /// The entry of `itemID` when it carries custom counts.
    func override(for itemID: String) -> Entry? {
        guard let entry = entries.first(where: { $0.itemID == itemID }),
              entry.hasCustomCounts else {
            return nil
        }

        return entry
    }

    // MARK: - Storage

    /// The saved layout, or the standard one when nothing (or nothing readable) was saved.
    static func load(
        for standard: [DailyPlanItem],
        defaults: UserDefaults = .standard
    ) -> DebugPlanLayout {
        guard let data = defaults.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode(DebugPlanLayout.self, from: data) else {
            return .standard(standard)
        }

        return saved.reconciled(with: standard)
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else {
            return
        }

        defaults.set(data, forKey: Self.storageKey)
    }
}
#endif
