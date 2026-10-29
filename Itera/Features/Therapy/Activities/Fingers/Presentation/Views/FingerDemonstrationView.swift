//
//  FingerDemonstrationView.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import AVFoundation
import SwiftUI

/// Plays only the half-cycle matching the current instruction; calibration uses held poses.
struct FingerDemonstrationView: UIViewRepresentable {
    let exercise: FingerExercise
    let phase: FingerPhase
    let returning: Bool
    let finger: Int
    let side: TrainingSide
    let paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> HandMovieView { HandMovieView() }

    func updateUIView(_ view: HandMovieView, context: Context) {
        let displayedPhase: FingerPhase
        if reduceMotion && (phase == .active || phase == .demonstration) {
            displayedPhase = returning ? .baseline : .target
        } else {
            displayedPhase = phase
        }
        view.configure(asset: exercise.rawValue, phase: displayedPhase,
                       returning: returning, finger: exercise.isSequential ? finger : 0,
                       mirrored: side == .left, paused: paused || reduceMotion)
    }

    static func dismantleUIView(_ view: HandMovieView, coordinator: ()) { view.releasePlayer() }
}

final class HandMovieView: UIView {
    private let playerLayer = AVPlayerLayer()
    private let fallback = UILabel()
    private var player: AVPlayer?
    private var observer: Any?
    private var key = ""
    private var cueKey = ""
    private var end = 4.0
    private var start = 0.0
    private var looping = false
    private var assetName = ""
    private var playbackRevision = 0
    private var seeking = false
    private var reachedEndpoint = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(TherapyPalette.mediaBackground)
        layer.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspectFill
        fallback.text = String(localized: "demo.unavailable")
        AppFont.applyBodyStyle(to: fallback)
        fallback.textColor = UIColor(TherapyPalette.ink)
        fallback.numberOfLines = 0
        fallback.textAlignment = .center
        addSubview(fallback)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep layer geometry stable when the selected side applies a reflection.
        playerLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        playerLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        fallback.frame = bounds.insetBy(dx: 18, dy: 18)
    }

    func configure(asset: String, phase: FingerPhase, returning: Bool, finger: Int, mirrored: Bool, paused: Bool) {
        let newKey = "\(asset)-\(phase)-\(returning)-\(finger)-\(paused)"
        playerLayer.setAffineTransform(CGAffineTransform(scaleX: mirrored ? -1 : 1, y: 1))
        guard newKey != key else {
            return
        }
        key = newKey
        let nextCue = "\(asset)-\(phase)-\(returning)-\(finger)"
        let sameCue = cueKey == nextCue
        cueKey = nextCue
        let resumeCurrentPosition = sameCue && player != nil && !paused
        playbackRevision += 1
        if sameCue, paused, let player {
            // A preview pause holds the visible pose rather than returning to frame zero.
            looping = false
            seeking = false
            player.pause()
            return
        }
        if assetName != asset {
            releasePlayer()
            assetName = asset
            guard let url = Bundle.main.url(forResource: asset, withExtension: "mov") else {
                fallback.isHidden = false
                return
            }
            let player = AVPlayer(url: url)
            player.isMuted = true
            player.actionAtItemEnd = .pause
            self.player = player
            playerLayer.player = player
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.04, preferredTimescale: 600), queue: .main) { [weak self] time in
                guard let self, !self.seeking, !self.reachedEndpoint,
                      time.seconds >= self.end - 0.08 else {
                    return
                }
                if self.looping {
                    self.seek(to: self.start, play: true)
                } else {
                    // Pausing also notifies time observers. Hold each endpoint only once.
                    self.reachedEndpoint = true
                    self.player?.pause()
                }
            }
            fallback.isHidden = true
        }
        let offset = Double(finger) * 4
        looping = phase == .demonstration && !paused
        start = offset
        end = offset + 4
        var position = offset
        var shouldPlay = false
        switch phase {
        case .target:
            position = offset + 1.9
        case .demonstration:
            start = 0
            position = 0
            end = (asset == "opposition" || asset == "extensionSequence") ? 16 : 4
            shouldPlay = !paused
        case .active:
            position = offset + (returning ? 2 : 0)
            end = offset + (returning ? 4 : 2)
            shouldPlay = !paused
        default:
            break
        }
        if resumeCurrentPosition, let currentTime = player?.currentTime().seconds, currentTime.isFinite {
            position = currentTime
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
                guard let self, let currentPlayer,
                      self.playbackRevision == revision else {
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
    }
}
