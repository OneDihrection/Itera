//
//  PreparedAudioClip.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import AVFoundation

/// Playback mechanism only. SessionAudioService remains the sole audio-session owner.
@MainActor
final class PreparedAudioClip {
    private let player: AVAudioPlayer
    private var delegate: PlaybackDelegate?
    private var identity: UUID?

    init(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        guard player.prepareToPlay() else { throw Failure.unavailable }
    }

    func play(id: UUID, completion: @escaping (UUID, Bool) -> Void) -> Bool {
        stop()
        identity = id
        let delegate = PlaybackDelegate { [weak self] success in
            guard let self, self.identity == id else { return }
            self.identity = nil
            self.delegate = nil
            self.player.delegate = nil
            if success { _ = self.player.prepareToPlay() }
            completion(id, success)
        }
        self.delegate = delegate
        player.delegate = delegate
        player.currentTime = 0
        player.volume = 1
        return player.play()
    }

    func stop() {
        identity = nil
        delegate = nil
        player.delegate = nil
        player.pause()
        player.currentTime = 0
    }

    private enum Failure: Error { case unavailable }

    @MainActor
    private final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
        let completion: (Bool) -> Void

        init(completion: @escaping (Bool) -> Void) {
            self.completion = completion
        }

        nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            Task { @MainActor [weak self] in self?.completion(flag) }
        }

        nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
            Task { @MainActor [weak self] in self?.completion(false) }
        }
    }
}
