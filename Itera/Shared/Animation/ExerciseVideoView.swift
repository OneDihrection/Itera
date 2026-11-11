//
//  ExerciseVideoView.swift
//  Itera
//
//  Created by dimaswisodewo on 09/11/2026.
//

import AVFoundation
import SwiftUI

struct TMExerciseVideoView: UIViewRepresentable {
    let resource: String
    let mode: TherapyAnimationPlayback
    let reducedMotion: Bool
    let onEvent: (ExerciseVideoEvent) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> TMPlayerView {
        let view = TMPlayerView()
        context.coordinator.configure(view: view, resource: resource, mode: mode, reducedMotion: reducedMotion, onEvent: onEvent)
        return view
    }

    func updateUIView(_ view: TMPlayerView, context: Context) {
        context.coordinator.configure(view: view, resource: resource, mode: mode, reducedMotion: reducedMotion, onEvent: onEvent)
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
        private var currentReducedMotion: Bool?
        private var currentResource: String?

        func configure(
            view: TMPlayerView,
            resource: String,
            mode: TherapyAnimationPlayback,
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

            guard currentMode != mode || currentReducedMotion != reducedMotion else { return }
            currentMode = mode
            currentReducedMotion = reducedMotion
            if reducedMotion || mode != .looping {
                player?.pause()
                let duration = player?.currentItem?.duration ?? .zero
                let time = mode == .staticStart ? CMTime.zero : CMTimeMultiplyByFloat64(duration, multiplier: 0.5)
                if time.isValid && time.isNumeric {
                    player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                }
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
            currentReducedMotion = nil
        }
    }
}
