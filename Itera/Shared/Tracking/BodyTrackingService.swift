//
//  BodyTrackingService.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import AVFoundation
import Combine
import CoreML
import Vision

/// One serial capture/inference owner, with one replaceable pending delivery on the main queue.
final class BodyTrackingService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let frames = PassthroughSubject<TrackingObservation, Never>()
    let failures = PassthroughSubject<String, Never>()
    let cupFailures = PassthroughSubject<String, Never>()
    let availability = PassthroughSubject<TrackingAvailability, Never>()

    private let queue = DispatchQueue(label: "Itera.bodyTracking", qos: .userInitiated)
    private let inferenceQueue = DispatchQueue(label: "Itera.bodyInference", qos: .userInitiated)
    private var inferenceBusy = false
    private let deliveryLock = NSLock()
    private var pending: TrackingObservation?
    private var deliveryScheduled = false
    private var generation = UUID()
    private var position: AVCaptureDevice.Position = .front
    private var angle: CGFloat = 180
    private var previousCenterStage: (mode: AVCaptureDevice.CenterStageControlMode, enabled: Bool)?
    private var wantsCapture = false
    private var configured = false
    private var hasInitialOrientation = false
    private var timestampOffset: Double?
    private var lastPublished = 0.0
    private var lastInferenceFailure = 0.0
    private var cupRequest: VNCoreMLRequest?
    private var cupEnabled = false
    private let cupTracker = CupObjectTracker()
    private var watchdogIdentity = UUID()
    private var frameWatchdog: DispatchWorkItem?
    private var awaitingFirstFrame = false
    private var captureStartedAt = 0.0

    func requireCup(_ enabled: Bool) {
        inferenceQueue.async { [weak self] in
            guard let self, self.cupEnabled != enabled || (enabled && self.cupRequest == nil) else { return }
            self.cupEnabled = enabled
            self.cupRequest = nil
            self.cupTracker.reset()
            guard enabled else { return }
            do {
                guard let url = Bundle.main.url(forResource: "yolo11n", withExtension: "mlmodelc") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let model = try MLModel(contentsOf: url)
                self.cupRequest = VNCoreMLRequest(model: try VNCoreMLModel(for: model))
                self.cupRequest?.imageCropAndScaleOption = .scaleFit
            } catch {
                self.cupFailures.send("cup.modelUnavailable")
            }
        }
    }

    private let request = VNDetectHumanBodyPoseRequest()
    private var notifications: [NSObjectProtocol] = []

    override init() {
        super.init()
        let center = NotificationCenter.default
        notifications.append(
            center.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil
            ) { [weak self] notification in
                NSLog("Body capture interrupted reason=%@", String(describing: notification.userInfo?[AVCaptureSessionInterruptionReasonKey]))
                guard let self else {
                    return
                }
                self.queue.async {
                    self.cancelFrameWatchdog()
                    self.invalidateGeneration()
                    self.availability.send(.discontinuity)
                }
            })
        notifications.append(
            center.addObserver(
                forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    guard self.wantsCapture else { return }
                    self.awaitingFirstFrame = true
                    self.startIfRequested()
                    self.scheduleFrameWatchdog(for: self.generation)
                }
            })
        notifications.append(
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
            ) { [weak self] notification in
                guard let self else {
                    return
                }
                self.queue.async {
                    self.cancelFrameWatchdog()
                    self.invalidateGeneration()
                    self.session.stopRunning()
                    self.restoreCenterStage()
                    self.availability.send(.discontinuity)
                }
                let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
                NSLog("Body capture runtime error domain=%@ code=%ld", error?.domain ?? "unknown", error?.code ?? 0)
                self.failures.send(
                    error?.localizedDescription ?? "")
            })
    }

    deinit {
        restoreCenterStage()
        for notification in notifications {
            NotificationCenter.default.removeObserver(notification)
        }
    }

    func start() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.wantsCapture = true
            self.startIfRequested()
        }
    }

    private func startIfRequested() {
        guard wantsCapture else { return }
        do {
            if self.previousCenterStage == nil {
                self.previousCenterStage = (
                    AVCaptureDevice.centerStageControlMode,
                    AVCaptureDevice.isCenterStageEnabled
                )
            }
            AVCaptureDevice.centerStageControlMode = .app
            AVCaptureDevice.isCenterStageEnabled = false
            guard self.hasInitialOrientation, !self.session.isRunning else { return }
            try self.configureIfNeeded()
            self.invalidateGeneration()
            self.timestampOffset =
                ProcessInfo.processInfo.systemUptime
                - CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
            NSLog("Body capture start requested")
            self.session.startRunning()
            self.captureStartedAt = ProcessInfo.processInfo.systemUptime
            NSLog("Body capture running=%@ generation=%@", self.session.isRunning.description, self.generation.uuidString)
            guard self.session.isRunning else {
                throw TrackingError.cameraUnavailable
            }
            self.awaitingFirstFrame = true
            self.scheduleFrameWatchdog(for: self.generation)
        } catch {
            self.cancelFrameWatchdog()
            self.restoreCenterStage()
            self.failures.send(error.localizedDescription)
            self.availability.send(.waiting)
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.wantsCapture = false
            self?.invalidateGeneration()
            self?.cancelFrameWatchdog()
            self?.session.stopRunning()
            self?.restoreCenterStage()
            self?.availability.send(.waiting)
        }
    }

    func configure(front: Bool, landscapeRight: Bool) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            let position: AVCaptureDevice.Position = front ? .front : .back
            let angle: CGFloat = landscapeRight ? 0 : 180
            let initialConfiguration = !self.hasInitialOrientation
            self.hasInitialOrientation = true
            guard initialConfiguration || self.position != position || self.angle != angle else {
                return
            }
            // Establishing preview orientation is setup, not lost capture evidence.
            if !initialConfiguration {
                self.availability.send(.discontinuity)
            }
            self.session.stopRunning()
            self.cancelFrameWatchdog()
            self.session.beginConfiguration()
            for input in self.session.inputs { self.session.removeInput(input) }
            for output in self.session.outputs { self.session.removeOutput(output) }
            self.session.commitConfiguration()
            self.configured = false
            self.position = position
            self.angle = angle
            self.invalidateGeneration()
            self.startIfRequested()
        }
    }

    private func restoreCenterStage() {
        guard let previous = previousCenterStage else {
            return
        }
        AVCaptureDevice.centerStageControlMode = .app
        AVCaptureDevice.isCenterStageEnabled = previous.enabled
        AVCaptureDevice.centerStageControlMode = previous.mode
        previousCenterStage = nil
    }

    private func configureIfNeeded() throws {
        guard !configured else {
            return
        }
        let selectedCamera = AVCaptureDevice.default(
            .builtInUltraWideCamera, for: .video, position: position
        ) ?? AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: position
        ) ?? AVCaptureDevice.default(for: .video)
        guard let camera = selectedCamera else {
            throw TrackingError.cameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: camera)
        NSLog("Body capture selected device=%@ type=%@ position=%ld", camera.localizedName, camera.deviceType.rawValue, position.rawValue)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        session.automaticallyConfiguresApplicationAudioSession = false
        defer { session.commitConfiguration() }
        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw TrackingError.cameraUnavailable
        }
        session.addInput(input)
        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
        if camera.activeFormat.videoSupportedFrameRateRanges.contains(where: {
            $0.minFrameRate <= 30 && $0.maxFrameRate >= 30
        }) {
            try camera.lockForConfiguration()
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            camera.unlockForConfiguration()
        }
        configured = true
        NSLog("Body capture configuration complete")
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard wantsCapture, session.outputs.contains(where: { $0 === output }),
              let image = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let rawTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard rawTime.isFinite else {
            return
        }
        guard let timestampOffset else {
            return
        }
        let time = rawTime + timestampOffset
        if awaitingFirstFrame {
            awaitingFirstFrame = false
            NSLog("Body capture first frame delay=%.3f seconds generation=%@", ProcessInfo.processInfo.systemUptime - captureStartedAt, generation.uuidString)
            availability.send(.ready(generation))
        }
        scheduleFrameWatchdog(for: generation)
        guard wantsCapture, !inferenceBusy else { return }
        inferenceBusy = true
        let expectedGeneration = generation
        inferenceQueue.async { [weak self] in
            guard let self else { return }
            self.process(image, time: time, generation: expectedGeneration)
            self.queue.async { self.inferenceBusy = false }
        }
    }

    private func process(_ image: CVPixelBuffer, time: Double, generation: UUID) {
        guard !cupEnabled || time - lastPublished >= 1.0 / 20 else { return }
        lastPublished = time
        do {
            if !cupEnabled {
                try VNImageRequestHandler(cvPixelBuffer: image, orientation: .up).perform([request])
            }
            let people = cupEnabled ? [] : (request.results ?? [])
            var joints: [BodyJoint: TrackingObservation.Landmark] = [:]
            if people.count == 1, let person = people.first {
                let points = try person.recognizedPoints(.all)
                for (joint, visionJoint) in Self.jointMap {
                    if let point = points[visionJoint] {
                        joints[joint] = .init(
                            position: TherapyPoint(x: point.location.x, y: point.location.y),
                            confidence: point.confidence)
                    }
                }
            }
            var cup: CupEvidence?
            if cupEnabled, let cupRequest {
                do {
                    cup = try cupTracker.process(
                        image, timestamp: time, generation: generation, detector: cupRequest)
                } catch {
                    cupTracker.reset()
                    self.cupRequest = nil
                    cupFailures.send("cup.modelUnavailable")
                }
            }

            deliver(
                TrackingObservation(
                    timestamp: time, generation: generation, width: CVPixelBufferGetWidth(image),
                    height: CVPixelBufferGetHeight(image), personCount: people.count, joints: joints, cup: cup
                ))
        } catch {
            if time - lastInferenceFailure >= 5 {
                lastInferenceFailure = time
                NSLog("Body inference failed: %@", error.localizedDescription)
            }
            // Missing evidence clears holds without taking down healthy video.
            deliver(TrackingObservation(
                timestamp: time, generation: generation,
                width: CVPixelBufferGetWidth(image), height: CVPixelBufferGetHeight(image),
                personCount: 0, joints: [:], cup: nil
            ))
        }
    }

    private func deliver(_ frame: TrackingObservation) {
        queue.async { [weak self] in
            guard let self, self.wantsCapture, self.generation == frame.generation,
                  ProcessInfo.processInfo.systemUptime - frame.timestamp <= 0.3 else { return }
            self.enqueueDelivery(frame)
        }
    }

    private func enqueueDelivery(_ frame: TrackingObservation) {
        deliveryLock.lock()
        pending = frame
        let schedule = !deliveryScheduled
        deliveryScheduled = true
        deliveryLock.unlock()
        guard schedule else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.deliveryLock.lock()
            let frame = self.pending
            self.pending = nil
            self.deliveryScheduled = false
            self.deliveryLock.unlock()
            if let frame { self.frames.send(frame) }
        }
    }

    private func invalidateGeneration() {
        generation = UUID()
        deliveryLock.lock()
        pending = nil
        deliveryLock.unlock()
    }

    private func cancelFrameWatchdog() {
        watchdogIdentity = UUID()
        frameWatchdog?.cancel()
        frameWatchdog = nil
        awaitingFirstFrame = false
    }

    private func scheduleFrameWatchdog(for expectedGeneration: UUID) {
        frameWatchdog?.cancel()
        let firstFrame = awaitingFirstFrame
        let identity = UUID()
        watchdogIdentity = identity
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.watchdogIdentity == identity, self.wantsCapture,
                  self.generation == expectedGeneration, self.session.isRunning else {
                return
            }
            self.cancelFrameWatchdog()
            self.invalidateGeneration()
            self.session.stopRunning()
            self.restoreCenterStage()
            NSLog("Body capture frame timeout firstFrame=%@ generation=%@", firstFrame.description, expectedGeneration.uuidString)
            self.availability.send(.discontinuity)
            self.failures.send(firstFrame ? "Camera did not deliver a startup frame." : "Camera frames stopped arriving.")
        }
        frameWatchdog = work
        queue.asyncAfter(deadline: .now() + (firstFrame ? 3.0 : 1.0), execute: work)
    }

    private static let jointMap: [(BodyJoint, VNHumanBodyPoseObservation.JointName)] = [
        (.nose, .nose), (.neck, .neck), (.root, .root),
        (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow), (.leftWrist, .leftWrist),
        (.rightWrist, .rightWrist), (.leftHip, .leftHip), (.rightHip, .rightHip),
        (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
        (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
    ]
    private enum TrackingError: Error { case cameraUnavailable }
}
