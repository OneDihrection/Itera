//
//  HandRotationExample.swift
//  Itera
//
//  Created by Fauzan Azima on 07/11/2026.
//

import AVFoundation
import SwiftUI

/// The forearm-rotation example: the bundled `hand_rotation_left` / `hand_rotation_right` movie
/// for the exercised side. Each movie is one full cycle, palm to turned and back.
struct TMHandRotationExample: UIViewRepresentable {
    let phase: FingerPhase
    let returning: Bool
    let side: TrainingSide
    let paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> TMHandRotationMovieView {
        TMHandRotationMovieView()
    }

    func updateUIView(_ view: TMHandRotationMovieView, context: Context) {
        view.configure(
            side: side,
            phase: phase,
            returning: returning,
            paused: paused,
            reduceMotion: reduceMotion
        )
    }

    static func dismantleUIView(_ view: TMHandRotationMovieView, coordinator: ()) {
        view.releasePlayer()
    }
}

/// Plays the half of the cycle that matches the current instruction and holds its end pose.
final class TMHandRotationMovieView: UIView {
    /// Length of both bundled movies; the turned pose is at the midpoint.
    private static let clipDuration = 6.459
    private static let turnedPose = clipDuration / 2

    private let playerLayer = AVPlayerLayer()
    private let fallback = UILabel()
    private var player: AVPlayer?
    private var observer: Any?
    private var loadedSide: TrainingSide?
    private var key = ""
    private var cueKey = ""
    private var start = 0.0
    private var end = clipDuration
    private var looping = false
    private var seeking = false
    private var reachedEndpoint = false
    private var playbackRevision = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(TherapyPalette.mediaBackground)
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)
        fallback.text = String(localized: "demo.unavailable")
        AppFont.applyBodyStyle(to: fallback)
        fallback.textColor = UIColor(TherapyPalette.ink)
        fallback.numberOfLines = 0
        fallback.textAlignment = .center
        fallback.isHidden = true
        addSubview(fallback)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        fallback.frame = bounds.insetBy(dx: 18, dy: 18)
    }

    func configure(side: TrainingSide, phase: FingerPhase, returning: Bool, paused: Bool, reduceMotion: Bool) {
        let holdsPose = paused || reduceMotion
        let newKey = "\(side)-\(phase)-\(returning)-\(holdsPose)"

        guard newKey != key else {
            return
        }

        key = newKey
        let nextCue = "\(side)-\(phase)-\(returning)"
        let sameCue = cueKey == nextCue
        cueKey = nextCue
        playbackRevision += 1

        if loadedSide != side {
            loadMovie(for: side)
        }

        guard let player else {
            return
        }

        // A pause holds the visible pose instead of rewinding.
        if sameCue, paused {
            looping = false
            seeking = false
            player.pause()
            return
        }

        let plan = playbackPlan(phase: phase, returning: returning, holdsPose: holdsPose)
        looping = plan.looping
        start = plan.start
        end = plan.end

        var position = plan.position
        var shouldPlay = plan.play

        // Resuming the same cue continues from where it stopped.
        if sameCue, !paused, let current = player.currentTime().seconds as Double?, current.isFinite {
            position = current

            if position >= end - 0.08 {
                if looping {
                    position = start
                } else {
                    shouldPlay = false
                }
            }
        }

        seek(to: position, play: shouldPlay)
    }

    private func playbackPlan(
        phase: FingerPhase,
        returning: Bool,
        holdsPose: Bool
    ) -> (start: Double, end: Double, position: Double, play: Bool, looping: Bool) {
        let full = Self.clipDuration
        let turned = Self.turnedPose

        switch phase {
        case .target:
            return (0, full, turned, false, false)
        case .demonstration, .range:
            guard !holdsPose else {
                return (0, full, turned, false, false)
            }
            return (0, full, 0, true, true)
        case .active:
            let from = returning ? turned : 0
            let to = returning ? full : turned
            guard !holdsPose else {
                return (from, to, returning ? 0 : turned, false, false)
            }
            return (from, to, from, true, false)
        default:
            return (0, full, 0, false, false)
        }
    }

    private func loadMovie(for side: TrainingSide) {
        releasePlayer()
        loadedSide = side
        // Each movie shows its anatomical hand seen from the front, but the camera preview is a
        // mirror: a left hand's thumb appears on the right of the screen. The patient copies
        // what they see, so the example for their left hand is the right-hand movie and back.
        let name = side == .left ? "hand_rotation_right" : "hand_rotation_left"

        guard let url = Bundle.main.url(forResource: name, withExtension: "mov") else {
            fallback.isHidden = false
            return
        }

        let player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        self.player = player
        playerLayer.player = player
        fallback.isHidden = true

        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.04, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.handleTick(time.seconds)
        }
    }

    private func handleTick(_ seconds: Double) {
        guard !seeking, !reachedEndpoint, seconds >= end - 0.08 else {
            return
        }

        if looping {
            seek(to: start, play: true)
        } else {
            // Pausing also notifies observers; hold each endpoint only once.
            reachedEndpoint = true
            player?.pause()
        }
    }

    private func seek(to seconds: Double, play: Bool) {
        guard let currentPlayer = player else {
            return
        }

        let revision = playbackRevision
        reachedEndpoint = false
        seeking = true
        currentPlayer.pause()
        currentPlayer.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self, weak currentPlayer] completed in
            Task { @MainActor in
                guard let self, let currentPlayer, self.playbackRevision == revision else {
                    return
                }

                self.seeking = false

                guard completed, play else {
                    return
                }

                currentPlayer.play()
            }
        }
    }

    func releasePlayer() {
        playbackRevision += 1
        seeking = false
        reachedEndpoint = false

        if let observer {
            player?.removeTimeObserver(observer)
        }

        observer = nil
        player?.pause()
        playerLayer.player = nil
        player = nil
        loadedSide = nil
        key = ""
        cueKey = ""
    }
}
