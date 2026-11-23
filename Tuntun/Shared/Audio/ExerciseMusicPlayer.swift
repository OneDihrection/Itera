//
//  ExerciseMusicPlayer.swift
//  Tuntun
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
///
/// Main-actor state decides what should play; every `AVAudioPlayer` call runs on `MusicWorker`'s
/// serial queue, because loading, preparing and playing call into the audio session, which
/// warns about and can stall the UI on the main thread.
@MainActor
final class ExerciseMusicPlayer {
    private let defaults: UserDefaults
    private let resource: (String) -> URL?
    private let worker = MusicWorker()
    private var subscription: AnyCancellable?
    private var startupCheck: Task<Void, Never>?
    /// The track loaded or loading; cleared when a load fails, so the next refresh retries.
    private var track: ExerciseMusicTrack?
    /// Changes on every load, so a late failure or startup check from an earlier track is ignored.
    private var loadGeneration = 0
    private var hasPlayer = false
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
        cancelStartupCheck()
        worker.pause()
    }

    func resume() {
        start()
    }

    /// Stops and rewinds, keeping the loaded track. Releasing the player at a session's end and
    /// loading it again for the long rest both ran on the main thread and stalled that move.
    func stop() {
        active = false
        paused = true
        cancelStartupCheck()
        ducked = false
        worker.rewind(volume: volume)
    }

    func setDucked(_ value: Bool) {
        guard ducked != value else {
            return
        }
        ducked = value
        worker.setVolume(volume, fade: 0.3)
    }

    func refresh() {
        guard active else {
            return
        }
        let selected = defaults.string(forKey: ExerciseMusicTrack.storageKey)
            .flatMap(ExerciseMusicTrack.init(rawValue:)) ?? .floats
        if track != selected {
            load(selected)
        }
        if !paused, hasPlayer, startupCheck == nil {
            worker.playIfStopped()
            // Capture and speech recognition can change the audio route during session entry.
            // Check once after startup settles, without restarting a playing track.
            let generation = loadGeneration
            startupCheck = Task { [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else {
                    return
                }
                self.startupCheck = nil
                if self.loadGeneration == generation, self.hasPlayer, !self.paused {
                    self.worker.playIfStopped()
                }
            }
        }
    }

    /// Replaces the player on the worker. The load is queued before any play, so a play
    /// requested right after it starts the new track.
    private func load(_ selected: ExerciseMusicTrack) {
        cancelStartupCheck()
        loadGeneration &+= 1
        track = selected

        guard let name = selected.resourceName, let url = resource(name) else {
            hasPlayer = false
            worker.unload()
            return
        }

        hasPlayer = true
        let generation = loadGeneration
        worker.load(url, volume: volume) { [weak self] loaded in
            Task { @MainActor in
                guard let self, self.loadGeneration == generation, !loaded else {
                    return
                }
                // Optional music failure must never prevent readable/spoken exercise guidance.
                self.cancelStartupCheck()
                self.hasPlayer = false
                self.track = nil
            }
        }
    }

    private func cancelStartupCheck() {
        startupCheck?.cancel()
        startupCheck = nil
    }

    // Music stays audible but well under narration, so speech stays clear and loud.
    private var volume: Float { ducked ? 0.10 : 0.50 }

    // MARK: - Worker

    /// Owns the `AVAudioPlayer` and runs every call on one serial queue, in the order requested.
    private final class MusicWorker: @unchecked Sendable {
        private let queue = DispatchQueue(label: "Tuntun.music", qos: .userInitiated)
        private var player: AVAudioPlayer?

        func load(_ url: URL, volume: Float, completion: @escaping @Sendable (Bool) -> Void) {
            queue.async {
                self.player?.stop()
                self.player = nil

                guard let replacement = try? AVAudioPlayer(contentsOf: url), replacement.prepareToPlay() else {
                    completion(false)
                    return
                }

                replacement.numberOfLoops = -1
                replacement.volume = volume
                self.player = replacement
                completion(true)
            }
        }

        func unload() {
            queue.async {
                self.player?.stop()
                self.player = nil
            }
        }

        /// Never restarts a playing track.
        func playIfStopped() {
            queue.async {
                guard let player = self.player, !player.isPlaying else {
                    return
                }
                player.play()
            }
        }

        func pause() {
            queue.async {
                self.player?.pause()
            }
        }

        func rewind(volume: Float) {
            queue.async {
                self.player?.pause()
                self.player?.currentTime = 0
                self.player?.volume = volume
            }
        }

        func setVolume(_ volume: Float, fade: TimeInterval) {
            queue.async {
                self.player?.setVolume(volume, fadeDuration: fade)
            }
        }
    }
}
