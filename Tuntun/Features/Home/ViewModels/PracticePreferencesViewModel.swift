//
//  PracticePreferencesViewModel.swift
//  Tuntun
//
//  Created by dimaswisodewo on 16/11/2026.
//

import Foundation
import Observation
import UIKit

/// What Settings offers when voice control lacks access: ask for it, send the caregiver to the
/// system Settings, or only explain that a device manager restricts it.
enum VoicePermissionFallback: Equatable {
    case request
    case openSettings(messageKey: String)
    case restricted

    var messageKey: String {
        switch self {
        case .request:
            return "settings.voiceNeedsAccess"
        case .openSettings(let messageKey):
            return messageKey
        case .restricted:
            return "home.restricted"
        }
    }

    /// The fallback button's title, or nil when nothing in the app can grant access.
    var actionKey: String? {
        switch self {
        case .request:
            return "home.enablePermissions"
        case .openSettings:
            return "home.openSettings"
        case .restricted:
            return nil
        }
    }
}


@MainActor
protocol PracticePreferencesViewModelProtocol: AnyObject, Observable {
    /// Every plan exercise in the plan's order, with whether Beranda shows it.
    var layoutEntries: [DailyPlanLayout.Entry] { get }
    /// The plan item an entry stands for.
    func item(for entry: DailyPlanLayout.Entry) -> DailyPlanItem?
    func titleKey(for item: DailyPlanItem) -> String
    func setShown(_ shown: Bool, for entry: DailyPlanLayout.Entry)
    func moveEntries(fromOffsets source: IndexSet, toOffset destination: Int)
    /// Every exercise shown, in the standard order.
    func resetLayout()

    func hasSide(_ item: DailyPlanItem) -> Bool
    /// Right only, left only, or both sides.
    func side(for item: DailyPlanItem) -> RoutineSides
    func setSide(_ side: RoutineSides, for item: DailyPlanItem)
    /// What the exercise runs with now: Settings' choice, otherwise its program's own.
    func counts(for item: DailyPlanItem) -> (sets: Int, repetitions: Int)
    func setSets(_ sets: Int, for item: DailyPlanItem)
    func setRepetitions(_ repetitions: Int, for item: DailyPlanItem)

    /// The rest between every set of every exercise, in seconds.
    var shortRestSeconds: Int { get }
    func setShortRestSeconds(_ seconds: Int)
    /// Narrated breaths of the long rest between exercises and between sides.
    var longRestBreaths: Int { get }
    func setLongRestBreaths(_ breaths: Int)

    /// Voice control is always on; this mirrors whether microphone and speech access allow it.
    var voiceEnabled: Bool { get }
    var voiceFallback: VoicePermissionFallback? { get }

    func done()
    func refreshPermissions()
    /// Requests the missing voice permissions, or opens the system Settings when they were denied.
    func resolveVoiceAccess() async
}

/// The settings sheet. Order, visibility, side, sets and repetitions are per plan exercise; the
/// short and long rests are plan-wide. Every preference is saved as it changes. A session in
/// progress keeps the snapshot it started with.
@MainActor
@Observable
final class PracticePreferencesViewModel: PracticePreferencesViewModelProtocol {
    private let plan: DailyPlanViewModel
    @ObservationIgnored private let router: any HomeRouterProtocol
    /// Not ignored: its statuses are observable, so the voice row follows permission changes.
    private let permissionService: any PermissionServiceProtocol

    /// The permissions voice commands need; the camera is checked when a session starts.
    private static let voicePermissions: [AppPermission] = [.microphone, .speechRecognition]

    init(
        plan: DailyPlanViewModel,
        router: any HomeRouterProtocol,
        permissionService: any PermissionServiceProtocol
    ) {
        self.plan = plan
        self.router = router
        self.permissionService = permissionService
    }

    // MARK: - Layout

    var layoutEntries: [DailyPlanLayout.Entry] {
        plan.layout.entries
    }

    func item(for entry: DailyPlanLayout.Entry) -> DailyPlanItem? {
        plan.standardItems.first { $0.id == entry.itemID }
    }

    func titleKey(for item: DailyPlanItem) -> String {
        DailyPlanViewModel.titleKey(for: item.exercise)
    }

    func setShown(_ shown: Bool, for entry: DailyPlanLayout.Entry) {
        var layout = plan.layout

        guard let index = layout.entries.firstIndex(where: { $0.itemID == entry.itemID }) else {
            return
        }

        layout.entries[index].isShown = shown
        plan.applyLayout(layout)
    }

    func moveEntries(fromOffsets source: IndexSet, toOffset destination: Int) {
        var layout = plan.layout
        layout.moveEntries(fromOffsets: source, toOffset: destination)
        plan.applyLayout(layout)
    }

    func resetLayout() {
        plan.resetLayout()
    }

    // MARK: - Exercise settings

    func hasSide(_ item: DailyPlanItem) -> Bool {
        plan.hasSide(item)
    }

    func side(for item: DailyPlanItem) -> RoutineSides {
        plan.side(for: item)
    }

    func setSide(_ side: RoutineSides, for item: DailyPlanItem) {
        plan.setSide(side, for: item)
    }

    func counts(for item: DailyPlanItem) -> (sets: Int, repetitions: Int) {
        plan.counts(for: item)
    }

    func setSets(_ sets: Int, for item: DailyPlanItem) {
        plan.setSets(sets, for: item)
    }

    func setRepetitions(_ repetitions: Int, for item: DailyPlanItem) {
        plan.setRepetitions(repetitions, for: item)
    }

    // MARK: - Rest

    var shortRestSeconds: Int {
        plan.shortRestSeconds
    }

    func setShortRestSeconds(_ seconds: Int) {
        plan.setShortRestSeconds(seconds)
    }

    var longRestBreaths: Int {
        plan.longRestBreaths
    }

    func setLongRestBreaths(_ breaths: Int) {
        plan.setLongRestBreaths(breaths)
    }

    func done() {
        router.dismissSheet()
    }

    // MARK: - Voice control

    var voiceEnabled: Bool {
        Self.voicePermissions.allSatisfy { permission in
            permissionService.status(for: permission) == .authorized
        }
    }

    var voiceFallback: VoicePermissionFallback? {
        guard let missing = Self.voicePermissions.first(where: { permission in
            permissionService.status(for: permission) != .authorized
        }) else {
            return nil
        }

        switch permissionService.status(for: missing) {
        case .denied:
            let messageKey = missing == .microphone
                ? "home.microphoneDenied"
                : "home.speechDenied"
            return .openSettings(messageKey: messageKey)
        case .restricted:
            return .restricted
        case .notDetermined, .unknown, .authorized:
            return .request
        }
    }

    func refreshPermissions() {
        permissionService.refresh()
    }

    func resolveVoiceAccess() async {
        refreshPermissions()

        switch voiceFallback {
        case .request:
            for permission in Self.voicePermissions {
                guard await permissionService.request(permission) == .authorized else {
                    break
                }
            }
        case .openSettings:
            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                return
            }
            await UIApplication.shared.open(url)
        case .restricted, nil:
            break
        }
    }
}
