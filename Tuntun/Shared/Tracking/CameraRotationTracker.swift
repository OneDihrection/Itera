//
//  CameraRotationTracker.swift
//  Tuntun
//
//  Created by dimaswisodewo on 19/11/2026.
//

import AVFoundation

/// Keeps camera connections upright with rotation angles, in place of the `videoOrientation`
/// deprecated in iOS 17.
///
/// The angles come from `AVCaptureDevice.RotationCoordinator`, which accounts for how each camera
/// is mounted: a fixed orientation-to-angle table is not safe, because the front camera's default
/// angle is 180° on iPads from spring 2024 and 0° on earlier ones. `videoRotationAngleRelativeToDeviceOrientation(_:)`
/// would map an interface orientation directly, but it needs iOS 27.
///
/// Use an instance on the main thread; the coordinator reports changes on the main queue.
/// `apply(_:to:)` may be called on a capture queue, as the camera services do.
final class CameraRotationTracker {
    /// The preview angle and the capture angle, in degrees.
    typealias Angles = (preview: CGFloat, capture: CGFloat)

    private var coordinator: AVCaptureDevice.RotationCoordinator?
    private var observations: [NSKeyValueObservation] = []
    private let onChange: (Angles) -> Void

    /// - Parameter onChange: called on the main queue when either angle changes after `track`.
    init(onChange: @escaping (Angles) -> Void) {
        self.onChange = onChange
    }

    /// Follows the camera feeding `connection`, starting over when it changes. Returns the current
    /// angles, or `nil` while the connection has no camera.
    @discardableResult
    func track(_ connection: AVCaptureConnection?, previewLayer: CALayer?) -> Angles? {
        guard let device = connection.flatMap(Self.device(of:)) else {
            stop()
            return nil
        }

        if coordinator?.device !== device || coordinator?.previewLayer !== previewLayer {
            start(device, previewLayer: previewLayer)
        }

        return coordinator.map(Self.angles(of:))
    }

    func stop() {
        observations = []
        coordinator = nil
    }

    /// Sets the connection's angle when it is supported and different. Returns whether it changed.
    @discardableResult
    static func apply(_ angle: CGFloat, to connection: AVCaptureConnection) -> Bool {
        guard connection.videoRotationAngle != angle,
              connection.isVideoRotationAngleSupported(angle) else {
            return false
        }

        connection.videoRotationAngle = angle
        return true
    }

    // MARK: - Private

    private func start(_ device: AVCaptureDevice, previewLayer: CALayer?) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        let report: (AVCaptureDevice.RotationCoordinator) -> Void = { [weak self] coordinator in
            self?.onChange(Self.angles(of: coordinator))
        }

        self.coordinator = coordinator
        observations = [
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { coordinator, _ in
                report(coordinator)
            },
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { coordinator, _ in
                report(coordinator)
            },
        ]
    }

    private static func angles(of coordinator: AVCaptureDevice.RotationCoordinator) -> Angles {
        (coordinator.videoRotationAngleForHorizonLevelPreview, coordinator.videoRotationAngleForHorizonLevelCapture)
    }

    private static func device(of connection: AVCaptureConnection) -> AVCaptureDevice? {
        connection.inputPorts.lazy
            .compactMap { ($0.input as? AVCaptureDeviceInput)?.device }
            .first
    }
}
