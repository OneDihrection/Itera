//
//  ShoulderRotationMovieView.swift
//  Tuntun
//
//  Created by Fauzan Azima on 09/11/2026.
//

import AVFoundation
import SwiftUI

/// The bundled shoulder-rotation example for one arm, looping silently, or held on its target
/// pose when `holdsPeakAt` is set. It stands in for the native illustration when a recording
/// exists for the exercise and arm.
struct TMShoulderRotationMovieView: View {
    let resource: String
    let paused: Bool
    var mirrored: Bool = false
    /// Seconds into the clip to hold instead of looping, as during practice.
    var holdsPeakAt: Double?
    var accessibilityKey: LocalizedStringKey = "rotation.animationAccessibility"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let holdsPose = paused || reduceMotion

        ZStack {
            TMShoulderRotationPlayer(
                resource: resource,
                paused: holdsPose,
                peakSeconds: holdsPeakAt
            )
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)

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
    let peakSeconds: Double?

    func makeUIView(context: Context) -> TMLoopingMovieView {
        TMLoopingMovieView()
    }

    func updateUIView(_ view: TMLoopingMovieView, context: Context) {
        view.configure(
            resource: resource,
            paused: paused,
            peakSeconds: peakSeconds
        )
    }

    static func dismantleUIView(_ view: TMLoopingMovieView, coordinator: ()) {
        view.release()
    }
}

/// Plays one movie on a loop; a pause keeps the visible frame instead of rewinding, and a peak
/// time holds that frame until it is cleared.
private final class TMLoopingMovieView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var loadedResource: String?
    private var heldPeak: Double?

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

    func configure(resource: String, paused: Bool, peakSeconds: Double?) {
        if loadedResource != resource {
            load(resource)
        }

        if let peakSeconds {
            holdPeak(at: peakSeconds)
            return
        }

        heldPeak = nil

        if paused {
            player?.pause()
        } else {
            player?.play()
        }
    }

    /// Seeks once per peak time, so repeated SwiftUI updates do not restart the seek.
    private func holdPeak(at seconds: Double) {
        player?.pause()

        guard heldPeak != seconds else {
            return
        }

        heldPeak = seconds
        player?.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
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
        heldPeak = nil
    }
}
