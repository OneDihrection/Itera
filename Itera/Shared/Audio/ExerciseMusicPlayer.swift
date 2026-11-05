//
//  ExerciseMusicPlayer.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import AVFoundation
import Combine

/// Bundled tracks and a device-local preference, independent of saved therapy routines.
enum ExerciseMusicTrack: String, CaseIterable, Identifiable {
    case off
    case floats
    case homecoming

    static let storageKey = "practice.exerciseMusic"
    static let defaultValue = Self.floats.rawValue
    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .off: return "music.off"
        case .floats: return "music.floats"
        case .homecoming: return "music.homecoming"
        }
    }

    var resourceName: String? {
        switch self {
        case .off: return nil
        case .floats: return "Floats"
        case .homecoming: return "Homecoming"
        }
    }
}

/// Playback only: the containing audio service remains the sole AVAudioSession owner.
/// Preference changes replace the player only when the track changes; pauses retain position.
@MainActor
final class ExerciseMusicPlayer {
    private let defaults: UserDefaults
    private let resource: (String) -> URL?
    private var subscription: AnyCancellable?
    private var player: AVAudioPlayer?
    private var track: ExerciseMusicTrack?
    private var active = false
    private var paused = true
    private var ducked = false

    init(
        defaults: UserDefaults = .standard,
        resource: @escaping (String) -> URL? = { Bundle.main.url(forResource: $0, withExtension: "mp3") }
    ) {
        self.defaults = defaults
        self.resource = resource
        subscription = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    func start() {
        active = true
        paused = false
        refresh()
    }

    func pause() {
        paused = true
        player?.pause()
    }

    func resume() {
        start()
    }

    func stop() {
        active = false
        paused = true
        player?.stop()
        player = nil
        track = nil
        ducked = false
    }

    func setDucked(_ value: Bool) {
        guard ducked != value else {
            return
        }
        ducked = value
        player?.setVolume(volume, fadeDuration: 0.2)
    }

    func refresh() {
        guard active else {
            return
        }
        let selected = defaults.string(forKey: ExerciseMusicTrack.storageKey)
            .flatMap(ExerciseMusicTrack.init(rawValue:)) ?? .floats
        if track != selected || (player == nil && selected != .off) {
            player?.stop()
            player = nil
            track = selected
            if let name = selected.resourceName, let url = resource(name) {
                // Optional music failure must never prevent readable/spoken exercise guidance.
                if let replacement = try? AVAudioPlayer(contentsOf: url), replacement.prepareToPlay() {
                    replacement.numberOfLoops = -1
                    replacement.volume = volume
                    player = replacement
                }
            }
        }
        if !paused, player?.isPlaying == false {
            player?.play()
        }
    }

    // Both supplied recordings begin softly. Retain audible music during narration,
    // rather than attenuating their opening by another 32 dB.
    private var volume: Float { ducked ? 0.18 : 0.50 }
}
