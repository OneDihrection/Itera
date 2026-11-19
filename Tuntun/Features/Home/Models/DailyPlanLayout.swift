//
//  DailyPlanLayout.swift
//  Tuntun
//
//  Created by dimaswisodewo on 15/11/2026.
//

import Foundation

/// The caregiver's arrangement of today's plan, chosen in Settings: which exercises Beranda
/// shows, and in what order. Counts saved by the former debug editor are ignored when decoding.
///
/// Stores stable item ids only.
struct DailyPlanLayout: Codable, Equatable {
    struct Entry: Codable, Equatable, Identifiable {
        let itemID: String
        var isShown = true

        var id: String {
            itemID
        }
    }

    static let storageKey = "practice.planLayout"
    /// Where the debug-only plan editor saved its layout; read once to carry it over.
    private static let legacyStorageKey = "debug.dailyPlanLayout"

    var entries: [Entry]

    /// Every standard item shown in its standard order.
    static func standard(_ items: [DailyPlanItem]) -> DailyPlanLayout {
        DailyPlanLayout(entries: items.map { Entry(itemID: $0.id) })
    }

    /// Entries for every standard item: saved ones in their saved order, ids that no longer
    /// exist dropped, and exercises added to the plan later appended as shown.
    func reconciled(with standard: [DailyPlanItem]) -> DailyPlanLayout {
        let known = Set(standard.map(\.id))
        let kept = entries.filter { known.contains($0.itemID) }
        let keptIDs = Set(kept.map(\.itemID))

        let added = standard
            .filter { !keptIDs.contains($0.id) }
            .map { Entry(itemID: $0.id) }

        return DailyPlanLayout(entries: kept + added)
    }

    /// Moves the entries at `source` so they land before the entry now at `destination`, the way
    /// a list drag reports it.
    mutating func moveEntries(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moved = source.map { entries[$0] }
        let movedAbove = source.filter { $0 < destination }.count

        entries = entries.enumerated()
            .filter { !source.contains($0.offset) }
            .map(\.element)
        entries.insert(contentsOf: moved, at: destination - movedAbove)
    }

    /// The shown items, in the layout's order.
    func items(from standard: [DailyPlanItem]) -> [DailyPlanItem] {
        let byID = Dictionary(uniqueKeysWithValues: standard.map { ($0.id, $0) })

        return reconciled(with: standard).entries
            .filter(\.isShown)
            .compactMap { byID[$0.itemID] }
    }

    // MARK: - Storage

    /// The saved layout, or the standard one when nothing (or nothing readable) was saved.
    static func load(
        for standard: [DailyPlanItem],
        defaults: UserDefaults = .standard
    ) -> DailyPlanLayout {
        guard let data = defaults.data(forKey: storageKey) ?? defaults.data(forKey: legacyStorageKey),
              let saved = try? JSONDecoder().decode(DailyPlanLayout.self, from: data) else {
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
