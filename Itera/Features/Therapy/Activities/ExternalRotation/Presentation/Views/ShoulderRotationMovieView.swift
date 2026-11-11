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
struct TMShoulderRotationMovieView: View {
    let resource: String
    let paused: Bool
    var mirrored: Bool = false
    /// Shows the right-arm recording beside its reflection, depicting both arms.
    var bothArms: Bool = false
    var accessibilityKey: LocalizedStringKey = "rotation.animationAccessibility"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let holdsPose = paused || reduceMotion

        ZStack {
            if bothArms {
                HStack(spacing: 0) {
                    TMShoulderRotationPlayer(resource: resource, paused: holdsPose, fitsFigure: true)

                    TMShoulderRotationPlayer(resource: resource, paused: holdsPose, fitsFigure: true)
                        .scaleEffect(x: -1, y: 1)
                }
            } else {
                TMShoulderRotationPlayer(resource: resource, paused: holdsPose)
                    .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            }

            TMTherapyDemoCaption(paused: holdsPose)
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

private struct TMShoulderRotationPlayer: UIViewRepresentable {
    let resource: String
    let paused: Bool
    /// Letterboxes instead of cropping, so a half-width figure stays whole.
    var fitsFigure = false

    func makeUIView(context: Context) -> TMLoopingMovieView {
        TMLoopingMovieView()
    }

    func updateUIView(_ view: TMLoopingMovieView, context: Context) {
        view.fitsFigure = fitsFigure
        view.configure(resource: resource, paused: paused)
    }

    static func dismantleUIView(_ view: TMLoopingMovieView, coordinator: ()) {
        view.release()
    }
}

/// Plays one movie on a loop; a pause keeps the visible frame instead of rewinding.
private final class TMLoopingMovieView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var loadedResource: String?

    var fitsFigure = false {
        didSet {
            playerLayer.videoGravity = fitsFigure ? .resizeAspect : .resizeAspectFill
        }
    }

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

        guard let url = Bundle.main.url(forResource: resource, withExtension: "mp4") else {
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
