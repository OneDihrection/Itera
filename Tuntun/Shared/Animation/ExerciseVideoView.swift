//
//  ExerciseVideoView.swift
//  Tuntun
//
//  Created by dimaswisodewo on 09/11/2026.
//

import AVFoundation
import SwiftUI

/// Plays a body demonstration: looping, or the half-cycle into the pose the patient is asked for,
/// held on its last frame, as the finger examples do.
struct TMExerciseVideoView: UIViewRepresentable {
    let resource: String
    let mode: TherapyAnimationPlayback
    /// The clip's rise and return; Reduce Motion while looping holds its peak.
    let timeline: DemonstrationTimeline
    var paused = false
    let reducedMotion: Bool
    let onEvent: (ExerciseVideoEvent) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> TMPlayerView {
        let view = TMPlayerView()
        update(view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: TMPlayerView, context: Context) {
        update(view, coordinator: context.coordinator)
    }

    private func update(_ view: TMPlayerView, coordinator: Coordinator) {
        coordinator.configure(
            view: view,
            resource: resource,
            mode: mode,
            timeline: timeline,
            paused: paused,
            reducedMotion: reducedMotion,
            onEvent: onEvent
        )
    }

    static func dismantleUIView(_ view: TMPlayerView, coordinator: Coordinator) {
        coordinator.stop(view: view)
    }

    final class TMPlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Coordinator {
        private var player: AVPlayer?
        private var endObserver: NSObjectProtocol?
        private var currentResource: String?
        private var currentMode: TherapyAnimationPlayback?
        private var currentTimeline: DemonstrationTimeline?
        private var currentReducedMotion: Bool?
        private var currentPaused: Bool?
        /// True while a loop or a half-cycle still has frames to play.
        private var playing = false

        func configure(
            view: TMPlayerView,
            resource: String,
            mode: TherapyAnimationPlayback,
            timeline: DemonstrationTimeline,
            paused: Bool,
            reducedMotion: Bool,
            onEvent: @escaping (ExerciseVideoEvent) -> Void
        ) {
            if currentResource != resource {
                stop(view: view)

                guard load(resource, into: view) else {
                    onEvent(.failed)
                    return
                }

                onEvent(.ready)
            }

            let previousMode = currentMode
            let poseChanged = currentMode != mode
                || currentTimeline != timeline
                || currentReducedMotion != reducedMotion

            // The other endpoint of the same clip segment, so the move between them can play.
            let continuesMovement = previousMode != nil
                && previousMode != mode
                && previousMode != .looping
                && currentTimeline == timeline

            currentMode = mode
            currentTimeline = timeline
            currentReducedMotion = reducedMotion

            if poseChanged {
                show(
                    mode,
                    timeline: timeline,
                    animated: continuesMovement && !reducedMotion,
                    reducedMotion: reducedMotion
                )
            }

            guard poseChanged || currentPaused != paused else {
                return
            }

            currentPaused = paused

            // A pause holds the visible frame; resuming continues an unfinished loop or move.
            if paused || !playing {
                player?.pause()
            } else {
                player?.play()
            }
        }

        func stop(view: TMPlayerView) {
            player?.pause()

            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }

            endObserver = nil
            view.playerLayer.player = nil
            player = nil
            currentResource = nil
            currentMode = nil
            currentTimeline = nil
            currentReducedMotion = nil
            currentPaused = nil
            playing = false
        }

        // MARK: - Playback

        private func load(_ resource: String, into view: TMPlayerView) -> Bool {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "mp4") else {
                return false
            }

            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.actionAtItemEnd = .pause
            view.playerLayer.videoGravity = .resizeAspectFill
            view.playerLayer.player = player
            self.player = player
            currentResource = resource

            // Fires at the clip's end while looping and at `forwardPlaybackEndTime` after a move.
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.reachedEnd()
            }

            return true
        }

        private func show(
            _ mode: TherapyAnimationPlayback,
            timeline: DemonstrationTimeline,
            animated: Bool,
            reducedMotion: Bool
        ) {
            switch mode {
            case .looping:
                if reducedMotion {
                    hold(at: timeline.peakSeconds)
                } else {
                    play(from: 0, until: nil)
                }
            case .peak:
                if animated {
                    play(from: timeline.rise.lowerBound, until: timeline.rise.upperBound)
                } else {
                    hold(at: timeline.peakSeconds)
                }
            case .neutral:
                if animated {
                    play(from: timeline.returning.lowerBound, until: timeline.returning.upperBound)
                } else {
                    hold(at: timeline.neutralSeconds)
                }
            }
        }

        private func hold(at seconds: Double) {
            playing = false
            player?.pause()
            player?.currentItem?.forwardPlaybackEndTime = .invalid
            seek(to: seconds)
        }

        /// Plays from `start` to `end`, or to the clip's end and around again when `end` is nil.
        private func play(from start: Double, until end: Double?) {
            playing = true
            player?.pause()
            player?.currentItem?.forwardPlaybackEndTime = end.map(Self.time) ?? .invalid
            seek(to: start)
        }

        private func reachedEnd() {
            guard currentMode == .looping, playing else {
                // A finished move stays on its last frame.
                playing = false
                return
            }

            seek(to: 0)

            if currentPaused != true {
                player?.play()
            }
        }

        private func seek(to seconds: Double) {
            player?.seek(
                to: Self.time(seconds),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }

        private static func time(_ seconds: Double) -> CMTime {
            CMTime(seconds: seconds, preferredTimescale: 600)
        }
    }
}
