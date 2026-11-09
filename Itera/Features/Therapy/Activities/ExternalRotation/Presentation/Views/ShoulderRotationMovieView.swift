//
//  ShoulderRotationMovieView.swift
//  Itera
//
//  Created by Fauzan Azima on 09/11/2026.
//

import AVFoundation
import SwiftUI

/// The bundled shoulder-rotation example for one arm, looping silently. It stands in for the
/// native illustration when a recording exists for the exercise and arm.
struct ShoulderRotationMovieView: View {
    let resource: String
    let paused: Bool
    var accessibilityKey: LocalizedStringKey = "rotation.animationAccessibility"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether the movie for `resource` is bundled, so callers can fall back to the illustration.
    static func isAvailable(_ resource: String) -> Bool {
        Bundle.main.url(forResource: resource, withExtension: "mov") != nil
    }

    var body: some View {
        let holdsPose = paused || reduceMotion

        ZStack {
            ShoulderRotationPlayer(resource: resource, paused: holdsPose)

            TherapyDemoCaption(paused: holdsPose)
        }
        .background(TherapyPalette.mediaBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(TherapyPalette.green.opacity(0.18), lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityKey)
    }
}

private struct ShoulderRotationPlayer: UIViewRepresentable {
    let resource: String
    let paused: Bool

    func makeUIView(context: Context) -> LoopingMovieView {
        LoopingMovieView()
    }

    func updateUIView(_ view: LoopingMovieView, context: Context) {
        view.configure(resource: resource, paused: paused)
    }

    static func dismantleUIView(_ view: LoopingMovieView, coordinator: ()) {
        view.release()
    }
}

/// Plays one movie on a loop; a pause keeps the visible frame instead of rewinding.
private final class LoopingMovieView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var loadedResource: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(TherapyPalette.mediaBackground)
        // Fill the container edge to edge; the sides or top are cropped instead of letterboxed.
        playerLayer.videoGravity = .resizeAspectFill
        clipsToBounds = true
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    func configure(resource: String, paused: Bool) {
        if loadedResource != resource {
            load(resource)
        }

        if paused {
            player?.pause()
        } else {
            player?.play()
        }
    }

    private func load(_ resource: String) {
        release()

        guard let url = Bundle.main.url(forResource: resource, withExtension: "mov") else {
            return
        }

        let player = AVQueuePlayer()
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        playerLayer.player = player
        self.player = player
        loadedResource = resource
    }

    func release() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        playerLayer.player = nil
        player = nil
        loadedResource = nil
    }
}
