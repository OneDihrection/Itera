//
//  PreparedAudioClip.swift
//  Tuntun
//
//  Created by dimaswisodewo on 28/10/2026.
//

import AVFoundation

/// Main-actor identities guard completions; all player work is serialized off the UI thread.
@MainActor
final class PreparedAudioClip {
    private let worker: PlayerWorker
    private var identity: UUID?
    /// The clip's length, reported by the player once its first play starts off the main thread.
    private var duration: TimeInterval?
    /// System uptime of the current play, cleared when it stops.
    private var startedAt: TimeInterval?

    init(url: URL) throws {
        worker = PlayerWorker(url: url)
    }

    /// Seconds left in the current play, or nil when nothing plays or the length is not yet known.
    func remaining(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval? {
        guard identity != nil, let duration, let startedAt else {
            return nil
        }

        return max(0, duration - (now - startedAt))
    }

    func play(id: UUID, volume: Float = 1, completion: @escaping (UUID, Bool) -> Void) -> Bool {
        identity = id
        startedAt = ProcessInfo.processInfo.systemUptime
        worker.play(volume: volume, started: { [weak self] duration in
            Task { @MainActor in
                self?.duration = duration
            }
        }) { [weak self] success in
            Task { @MainActor in
                guard let self, self.identity == id else { return }
                self.identity = nil
                completion(id, success)
            }
        }
        return true
    }

    /// Fades out before pausing, so a cut never clicks. A later `play` takes over immediately.
    func stop(fade: TimeInterval = 0.04) {
        identity = nil
        startedAt = nil
        worker.stop(fade: fade)
    }

    private final class PlayerWorker: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
        private let queue = DispatchQueue(label: "Tuntun.audioClip", qos: .userInitiated)
        private let url: URL
        private var player: AVAudioPlayer?

        private var completion: ((Bool) -> Void)?
        /// Changes on every play and stop, so late callbacks from an earlier play are ignored.
        private var token = 0

        init(url: URL) {
            self.url = url
            super.init()
            queue.async {
                self.player = try? AVAudioPlayer(contentsOf: url)
                _ = self.player?.prepareToPlay()
            }
        }

        func play(volume: Float, started: @escaping (TimeInterval) -> Void, completion: @escaping (Bool) -> Void) {
            queue.async {
                self.token &+= 1
                self.player?.pause()
                self.completion = completion
                do {
                    let player = try self.player ?? AVAudioPlayer(contentsOf: self.url)
                    self.player = player
                    player.delegate = self
                    player.setVolume(volume, fadeDuration: 0)
                    player.currentTime = 0
                    guard player.play() else {
                        self.finish(false)
                        return
                    }

                    started(player.duration)
                } catch {
                    self.finish(false)
                }
            }
        }

        func stop(fade: TimeInterval) {
            queue.async {
                self.token &+= 1
                self.completion = nil

                guard let player = self.player, player.isPlaying else {
                    return
                }

                let stopToken = self.token
                player.setVolume(0, fadeDuration: fade)
                self.queue.asyncAfter(deadline: .now() + fade) {
                    // A new play in the meantime owns the player now.
                    guard self.token == stopToken else {
                        return
                    }

                    player.pause()
                    player.currentTime = 0
                }
            }
        }

        private func finish(_ success: Bool) {
            let completion = completion
            self.completion = nil
            completion?(success)
        }

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            queue.async {
                // A finish queued from an earlier play must not complete a newer one that is
                // already playing on the same cached player.
                guard self.player === player, !player.isPlaying else { return }
                self.finish(flag)
            }
        }

        func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
            queue.async {
                guard self.player === player else { return }
                self.finish(false)
            }
        }
    }
}
