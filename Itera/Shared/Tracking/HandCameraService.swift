//
//  HandCameraService.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import AVFoundation
import Combine
import Vision

struct CameraSample {
    let evidence: HandEvidence?
    let timestamp: Double
    let generation: UUID
}

enum HandCameraEvent {
    case sample(CameraSample)
    case failure(String)
}

/// One serial capture/inference owner. Late frames are dropped by the capture output.
final class HandCameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let events = PassthroughSubject<HandCameraEvent, Never>()
    private let queue = DispatchQueue(label: "dev.itera.hand-camera", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private let request = VNDetectHumanHandPoseRequest()
    private var generation = UUID()
    private var configured = false
    private var lastInference = 0.0
    private var notifications: [NSObjectProtocol] = []

    override init() {
        super.init()
        request.maximumHandCount = 2
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                self?.events.send(.failure("camera.interrupted"))
            })
        }
    }

    deinit {
        notifications.forEach(NotificationCenter.default.removeObserver)
    }

    func start() {
        queue.async { [self] in
            do {
                if !configured {
                    try configure()
                }
                if !session.isRunning {
                    generation = UUID()
                    lastInference = 0
                    session.startRunning()
                }
            } catch {
                events.send(.failure("camera.unavailable"))
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
            generation = UUID()
        }
    }

    func orient(_ orientation: AVCaptureVideoOrientation) {
        queue.async { [self] in
            if let connection = output.connection(with: .video), connection.videoOrientation != orientation {
                connection.videoOrientation = orientation
                generation = UUID()
            }
        }
    }

    private func configure() throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw CameraError.unavailable
        }
        let input = try AVCaptureDeviceInput(device: camera)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw CameraError.unavailable
        }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            connection.videoOrientation = .landscapeLeft
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        configured = true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        guard timestamp - lastInference >= 1.0 / 15,
              let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        lastInference = timestamp
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up).perform([request])
            let hands = request.results ?? []
            // Multiple hands are ambiguous: do not choose a patient by screen position.
            guard hands.count == 1, let hand = hands.first else {
                events.send(.sample(CameraSample(evidence: nil, timestamp: timestamp, generation: generation)))
                return
            }
            let names: [VNHumanHandPoseObservation.JointName] = [
                .wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
                .indexMCP, .indexPIP, .indexDIP, .indexTip,
                .middleMCP, .middlePIP, .middleDIP, .middleTip,
                .ringMCP, .ringPIP, .ringDIP, .ringTip,
                .littleMCP, .littlePIP, .littleDIP, .littleTip
            ]
            let points = try names.map { name in
                let p = try hand.recognizedPoint(name)
                return HandPoint(x: p.location.x, y: p.location.y, confidence: p.confidence)
            }
            let side: HandSide?
            switch hand.chirality {
            case .left: side = .left
            case .right: side = .right
            default: side = nil
            }
            let evidence = HandEvidence(
                timestamp: timestamp, generation: generation,
                width: Double(CVPixelBufferGetWidth(pixelBuffer)),
                height: Double(CVPixelBufferGetHeight(pixelBuffer)), side: side, points: points
            )
            events.send(.sample(CameraSample(evidence: evidence, timestamp: timestamp, generation: generation)))
        } catch {
            events.send(.sample(CameraSample(evidence: nil, timestamp: timestamp, generation: generation)))
        }
    }

    private enum CameraError: Error { case unavailable }
}
