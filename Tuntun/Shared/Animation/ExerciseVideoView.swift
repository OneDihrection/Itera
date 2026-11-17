//
//  ExerciseVideoView.swift
//  Tuntun
//
//  Created by dimaswisodewo on 09/11/2026.
//

import AVFoundation
import SwiftUI

struct TMExerciseVideoView: UIViewRepresentable {
    let resource: String
    let mode: TherapyAnimationPlayback
    /// Where `staticPeak` (and Reduce Motion while looping) holds the clip.
    let peakSeconds: Double
    let reducedMotion: Bool
    let onEvent: (ExerciseVideoEvent) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> TMPlayerView {
        let view = TMPlayerView()
        context.coordinator.configure(
            view: view,
            resource: resource,
            mode: mode,
            peakSeconds: peakSeconds,
            reducedMotion: reducedMotion,
            onEvent: onEvent
        )
        return view
    }

    func updateUIView(_ view: TMPlayerView, context: Context) {
        context.coordinator.configure(
            view: view,
            resource: resource,
            mode: mode,
            peakSeconds: peakSeconds,
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
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var currentMode: TherapyAnimationPlayback?
        private var currentPeakSeconds: Double?
        private var currentReducedMotion: Bool?
        private var currentResource: String?

        func configure(
            view: TMPlayerView,
            resource: String,
            mode: TherapyAnimationPlayback,
            peakSeconds: Double,
            reducedMotion: Bool,
            onEvent: @escaping (ExerciseVideoEvent) -> Void
        ) {
            if currentResource != resource {
                stop(view: view)
                guard let url = Bundle.main.url(forResource: resource, withExtension: "mp4") else {
                    onEvent(.failed)
                    return
                }
                let queue = AVQueuePlayer()
                queue.isMuted = true
                view.playerLayer.videoGravity = .resizeAspectFill
                view.playerLayer.player = queue
                player = queue
                looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
                currentResource = resource
                onEvent(.ready)
            }

            guard currentMode != mode
                || currentPeakSeconds != peakSeconds
                || currentReducedMotion != reducedMotion
            else {
                return
            }

            currentMode = mode
            currentPeakSeconds = peakSeconds
            currentReducedMotion = reducedMotion

            if reducedMotion || mode != .looping {
                player?.pause()
                let time = mode == .staticStart
                    ? CMTime.zero
                    : CMTime(seconds: peakSeconds, preferredTimescale: 600)
                player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            } else {
                player?.play()
            }
        }

        func stop(view: TMPlayerView) {
            player?.pause()
            looper = nil
            player?.removeAllItems()
            view.playerLayer.player = nil
            player = nil
            currentResource = nil
            currentMode = nil
            currentPeakSeconds = nil
            currentReducedMotion = nil
        }
    }
}
