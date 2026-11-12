//
//  RepClipPlayer.swift
//  Itera
//
//  Created by dimaswisodewo on 12/11/2026.
//

import AVFoundation
import SwiftUI

/// Plays a short silent clip with the same play/pause circle and scrubber as `TMSkeletonReplay`.
///
/// It loops while playing, mirrors by default to match the front-camera preview, and starts
/// paused at the midpoint under Reduce Motion. It knows nothing about exercises or how the
/// clip was made.
struct TMRepClipPlayer: View {
    let url: URL
    /// Mirrors the picture to match the front-camera preview the patient saw.
    var mirrored = true
    var emphasisColor: Color = TherapyPalette.brand
    var height: CGFloat = 320
    let accessibilityLabel: Text

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var player = AVPlayer()
    @State private var playing = false
    @State private var duration = 0.0
    @State private var scrubbedTime = 0.0

    var body: some View {
        TimelineView(.animation(paused: !playing)) { _ in
            VStack(spacing: 8) {
                video
                controls(at: playing ? player.currentTime().seconds : scrubbedTime)
            }
        }
        .task(id: url) {
            await load()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { note in
            loopIfCurrent(note.object as? AVPlayerItem)
        }
        .onDisappear {
            player.pause()
            playing = false
        }
    }

    // MARK: - Sections

    private var video: some View {
        TMRepClipVideoLayer(player: player)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(TherapyPalette.progressPanel)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isImage)
    }

    private func controls(at time: Double) -> some View {
        HStack(spacing: 12) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .typography(.title3, weight: .semiBold)
                    .foregroundStyle(TherapyPalette.onBrand)
                    .frame(width: 52, height: 52)
                    .background(emphasisColor, in: Circle())
            }
            .accessibilityLabel(Text(playing ? "replay.pause" : "replay.play"))

            Slider(
                value: Binding(
                    get: { min(max(time.isFinite ? time : 0, 0), max(duration, 0.01)) },
                    set: { scrub(to: $0) }
                ),
                in: 0...max(duration, 0.01)
            )
            .tint(emphasisColor)
            .accessibilityLabel(Text("replay.position"))
        }
    }

    // MARK: - Playback

    private func load() async {
        let item = AVPlayerItem(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.replaceCurrentItem(with: item)

        let loaded = (try? await item.asset.load(.duration))?.seconds ?? 0
        duration = loaded.isFinite ? loaded : 0

        if reduceMotion {
            scrub(to: duration / 2)
        } else {
            scrubbedTime = 0
            player.play()
            playing = true
        }
    }

    private func loopIfCurrent(_ item: AVPlayerItem?) {
        guard let item, item === player.currentItem else {
            return
        }

        player.seek(to: .zero)

        if playing {
            player.play()
        }
    }

    private func togglePlayback() {
        if playing {
            scrubbedTime = player.currentTime().seconds
            player.pause()
            playing = false
        } else {
            player.play()
            playing = true
        }
    }

    private func scrub(to time: Double) {
        player.pause()
        playing = false
        scrubbedTime = min(max(0, time), duration)
        player.seek(
            to: CMTime(seconds: scrubbedTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }
}

/// Hosts the player's layer, fitted without cropping so the whole recorded frame is visible.
private struct TMRepClipVideoLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }

    final class LayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
