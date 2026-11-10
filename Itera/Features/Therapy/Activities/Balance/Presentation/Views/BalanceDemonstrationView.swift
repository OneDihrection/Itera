//
//  BalanceDemonstrationView.swift
//  Itera
//
//  Created by Gracia A on 02/11/2026.
//

import Combine
import RealityKit
import SwiftUI

struct TMBalanceDemonstrationView: View {
    let paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var state = LoadState.loading

    private enum LoadState {
        case loading, ready, failed
    }

    var body: some View {
        ZStack {
            TMBalanceAnimationViewport(
                paused: paused || reduceMotion,
                onStateChange: { state = $0 ? .ready : .failed }
            )

            if state == .loading {
                ProgressView()
                    .tint(TherapyPalette.green)
            } else if state == .failed {
                VStack(spacing: 10) {
                    Image(systemName: "figure.arms.open")
                        .typography(size: 52, weight: .bold)
                    Text("balance.animationUnavailable")
                        .typography(.footnote)
                }
                .foregroundStyle(TherapyPalette.muted)
            }

            TMTherapyDemoCaption(paused: paused)
        }
        .background(TherapyPalette.mediaBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(TherapyPalette.green.opacity(0.18), lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("balance.animationAccessibility")
    }
}

private struct TMBalanceAnimationViewport: UIViewRepresentable {
    let paused: Bool
    let onStateChange: (Bool) -> Void

    func makeCoordinator() -> BalanceAnimationRenderer {
        BalanceAnimationRenderer()
    }

    func makeUIView(context: Context) -> ARView {
        context.coordinator.load(paused: paused, onStateChange: onStateChange)
        return context.coordinator.view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.setPaused(paused)
    }

    static func dismantleUIView(_ view: ARView, coordinator: BalanceAnimationRenderer) {
        coordinator.stop()
    }
}

@MainActor
private final class BalanceAnimationRenderer {
    let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
    private var load: AnyCancellable?
    private var controllers: [AnimationPlaybackController] = []
    private var requestedPause = false

    init() {
        view.environment.background = .color(
            UIColor(red: 0.96, green: 0.95, blue: 0.89, alpha: 1)
        )
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
    }

    func load(paused: Bool, onStateChange: @escaping (Bool) -> Void) {
        requestedPause = paused
        guard let url = Bundle.main.url(forResource: "crossMidline", withExtension: "usdz") else {
            DispatchQueue.main.async { onStateChange(false) }
            return
        }

        load = Entity.loadAsync(contentsOf: url)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure = completion {
                    onStateChange(false)
                }
            } receiveValue: { [weak self] model in
                guard let self else { return }
                self.install(model)
                onStateChange(!self.controllers.isEmpty)
            }
    }

    private func install(_ model: Entity) {
        let bounds = model.visualBounds(relativeTo: nil)
        let largestExtent = max(bounds.extents.x, bounds.extents.y)
        guard largestExtent.isFinite, largestExtent > 0 else { return }

        let content = Entity()
        content.addChild(model)
        content.position = -bounds.center

        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(content)

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 38
        let distance = largestExtent * 1.9
        camera.look(at: .zero, from: [0, 0.1, distance], relativeTo: nil)
        anchor.addChild(camera)

        let keyLight = DirectionalLight()
        keyLight.light.intensity = 2_400
        keyLight.look(at: .zero, from: [distance, distance, distance], relativeTo: nil)
        anchor.addChild(keyLight)

        let fillLight = DirectionalLight()
        fillLight.light.intensity = 1_400
        fillLight.look(at: .zero, from: [-distance, 0, distance], relativeTo: nil)
        anchor.addChild(fillLight)

        view.scene.addAnchor(anchor)
        playAnimations(in: model)
        setPaused(requestedPause)
    }

    private func playAnimations(in entity: Entity) {
        if let animation = entity.availableAnimations.first,
            animation.definition.duration.isFinite,
            animation.definition.duration > 0
        {
            controllers.append(entity.playAnimation(
                animation.repeat(),
                transitionDuration: 0,
                startsPaused: requestedPause
            ))
        }
        for child in entity.children {
            playAnimations(in: child)
        }
    }

    func setPaused(_ paused: Bool) {
        requestedPause = paused
        for controller in controllers {
            paused ? controller.pause() : controller.resume()
        }
    }

    func stop() {
        load?.cancel()
        load = nil
        controllers.forEach { $0.stop() }
        controllers.removeAll()
        view.scene.anchors.removeAll()
    }
}
