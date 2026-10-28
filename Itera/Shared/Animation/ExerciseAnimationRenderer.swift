//
//  ExerciseAnimationRenderer.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import Combine
import RealityKit
import UIKit

enum ExerciseAnimationAsset: String {
    case armRaise
    case elbowBend
}

/// Pose selection follows the bundled asset convention in USDZ_ANIMATION_STANDARD.md.
enum TherapyAnimationPlayback: String {
    case looping, staticStart, staticPeak
}

/// Owns the virtual scene and cancels every outstanding operation when its owner changes.
@MainActor final class ExerciseAnimationRenderer {
    enum Event { case ready, failed }

    let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
    private var configuration: String?
    private var generation: UUID?
    private var load: AnyCancellable?
    private var loadingTimeout: Task<Void, Never>?
    private var playback: AnimationPlaybackController?
    private var onEvent: ((Event) -> Void)?

    init() {
        view.environment.background = .color(.init(white: 0.08, alpha: 1))
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
    }

    func configure(
        exercise: ExerciseAnimationAsset,
        reducedMotion: Bool,
        mode: TherapyAnimationPlayback,
        requestID: UUID?,
        onEvent: @escaping (Event) -> Void
    ) {
        self.onEvent = onEvent
        let key =
            "\(exercise.rawValue)-\(mode.rawValue)-\(reducedMotion)-\(requestID?.uuidString ?? "active")"
        guard configuration != key else {
            return
        }
        stop()
        self.onEvent = onEvent
        configuration = key
        let token = UUID()
        generation = token

        let name: String
        switch exercise {
        case .armRaise: name = "side_arm_raise_male_v1"
        case .elbowBend: name = "bicep_curl_right_male_v1"
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz") else {
            report(.failed, token: token)
            return
        }

        loadingTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.generation == token else {
                return
            }
            self.load?.cancel()
            self.load = nil
            self.report(.failed, token: token)
        }
        load = Entity.loadAsync(contentsOf: url)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self, self.generation == token else {
                    return
                }
                if case .failure = completion {
                    self.loadingTimeout?.cancel()
                    self.report(.failed, token: token)
                }
            } receiveValue: { [weak self] entity in
                guard let self, self.generation == token else {
                    return
                }
                self.loadingTimeout?.cancel()
                self.install(
                    entity,
                    exercise: exercise,
                    reducedMotion: reducedMotion,
                    mode: mode,
                    token: token
                )
            }
    }

    private func install(
        _ model: Entity,
        exercise: ExerciseAnimationAsset,
        reducedMotion: Bool,
        mode: TherapyAnimationPlayback,
        token: UUID
    ) {
        guard let (owner, animation) = animatedEntity(in: model),
            animation.definition.duration.isFinite, animation.definition.duration > 0
        else {
            report(.failed, token: token)
            return
        }

        let bounds = model.visualBounds(relativeTo: nil)
        let height = bounds.extents.y
        guard height.isFinite, height > 0 else {
            report(.failed, token: token)
            return
        }

        // Center the model without replacing transforms authored into the USDZ.
        let content = Entity()
        content.addChild(model)
        content.position = -bounds.center
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(content)

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 42
        let distance = max(height, bounds.extents.x) * 2
        // Orbit toward the rig's anatomical right (negative X), retaining framing distance.
        let azimuth: Float = (exercise == .armRaise ? -20 : -70) * .pi / 180
        let elevation: Float = 10 * .pi / 180
        let position: SIMD3<Float> = [
            distance * cos(elevation) * sin(azimuth),
            distance * sin(elevation),
            distance * cos(elevation) * cos(azimuth),
        ]
        camera.look(at: .zero, from: position, relativeTo: nil)
        anchor.addChild(camera)

        // Keep the visible joints evenly lit as exercise camera angles change.
        let lightingTarget: SIMD3<Float> = [0, 0, -distance]
        let mainLight = DirectionalLight()
        mainLight.light.color = .white
        mainLight.light.intensity = 2_500
        camera.addChild(mainLight)
        mainLight.look(
            at: lightingTarget,
            from: [0.5 * distance, 0.8 * distance, 0],
            relativeTo: camera
        )

        let fillLight = DirectionalLight()
        fillLight.light.color = .white
        fillLight.light.intensity = 1_800
        camera.addChild(fillLight)
        fillLight.look(
            at: lightingTarget,
            from: [-0.7 * distance, 0.2 * distance, 0],
            relativeTo: camera
        )
        view.scene.addAnchor(anchor)

        let isStatic = reducedMotion || mode != .looping
        let resource = isStatic ? animation : animation.repeat()
        playback = owner.playAnimation(resource, transitionDuration: 0, startsPaused: isStatic)
        if isStatic {
            // Both assets hold their peak joint pose around the clip midpoint.
            // Select from the imported duration rather than assuming USD seconds survive import.
            playback?.time = mode == .staticStart ? 0 : animation.definition.duration / 2
        }
        report(.ready, token: token)
    }

    private func animatedEntity(in entity: Entity) -> (Entity, AnimationResource)? {
        if let animation = entity.availableAnimations.first {
            return (entity, animation)
        }
        for child in entity.children {
            if let result = animatedEntity(in: child) {
                return result
            }
        }
        return nil
    }

    private func report(_ event: Event, token: UUID) {
        // Avoid publishing SwiftUI state during a representable update.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token else {
                return
            }
            self.onEvent?(event)
        }
    }

    func stop() {
        generation = nil
        configuration = nil
        load?.cancel()
        load = nil
        loadingTimeout?.cancel()
        loadingTimeout = nil
        playback?.stop()
        playback = nil
        view.scene.anchors.removeAll()
        onEvent = nil
    }
}
