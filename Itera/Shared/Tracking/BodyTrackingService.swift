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
    private let deliveryLock = NSLock()
    private var pending: TrackingObservation?
    private var deliveryScheduled = false
    private var generation = UUID()
    private var position: AVCaptureDevice.Position = .front
    private var orientation: AVCaptureVideoOrientation = .landscapeLeft
    private var previousCenterStage: (mode: AVCaptureDevice.CenterStageControlMode, enabled: Bool)?
    private var configured = false
    private var hasInitialOrientation = false
    private var timestampOffset: Double?
    private var lastPublished = 0.0
    /// Keeps tracking the patient while bystanders are in view. Confined to `queue`.
    private var subjects = BodySubjectSelector()
    private var cupRequest: VNCoreMLRequest?
    private var cupEnabled = false

    func requireCup(_ enabled: Bool) {
        queue.async { [weak self] in
            guard let self, self.cupEnabled != enabled || (enabled && self.cupRequest == nil) else { return }
            self.cupEnabled = enabled
            self.cupRequest = nil
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
            ) { [weak self] _ in
                guard let self else {
                    return
                }
                self.queue.async {
                    self.generation = UUID()
                    self.availability.send(.discontinuity)
                }
            })
        notifications.append(
            center.addObserver(
                forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil
            ) { [weak self] _ in
                self?.start()
            })
        notifications.append(
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
            ) { [weak self] notification in
                guard let self else {
                    return
                }
                self.queue.async {
                    self.session.stopRunning()
                    self.restoreCenterStage()
                    self.availability.send(.discontinuity)
                }
                let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
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
                self.generation = UUID()
                self.timestampOffset =
                    ProcessInfo.processInfo.systemUptime
                    - CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
                self.session.startRunning()
                self.availability.send(.ready(self.generation))
                if self.cupEnabled, self.cupRequest == nil {
                    self.cupEnabled = false
                    self.requireCup(true)
                }
            } catch {
                self.restoreCenterStage()
                self.failures.send(error.localizedDescription)
                self.availability.send(.waiting)
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
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
            let orientation: AVCaptureVideoOrientation = landscapeRight ? .landscapeRight : .landscapeLeft
            let initialConfiguration = !self.hasInitialOrientation
            self.hasInitialOrientation = true
            guard initialConfiguration || self.position != position || self.orientation != orientation else {
                return
            }
            // Establishing preview orientation is setup, not lost capture evidence.
            if !initialConfiguration {
                self.availability.send(.discontinuity)
            }
            self.session.stopRunning()
            self.session.beginConfiguration()
            for input in self.session.inputs { self.session.removeInput(input) }
            for output in self.session.outputs { self.session.removeOutput(output) }
            self.session.commitConfiguration()
            self.configured = false
            self.position = position
            self.orientation = orientation
            self.start()
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
        guard
            let camera = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInUltraWideCamera], mediaType: .video, position: position
            ).devices.first ?? AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: position)
        else {
            throw TrackingError.cameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: camera)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw TrackingError.cameraUnavailable
        }
        session.addInput(input)
        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            // Semantic orientation accounts for the selected camera's sensor mounting.
            // A fixed raw angle can invert front-camera frames by 180 degrees.
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = orientation
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
        configured = true
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let image = CMSampleBufferGetImageBuffer(sampleBuffer) else {
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
        guard time - lastPublished >= 1.0 / 20 else {
            return
        }
        lastPublished = time
        do {
            try VNImageRequestHandler(cvPixelBuffer: image, orientation: .up).perform([request])
            let people = request.results ?? []
            let personPoints = people.map { (try? $0.recognizedPoints(.all)) ?? [:] }
            let imageAspect = Double(CVPixelBufferGetWidth(image)) / Double(CVPixelBufferGetHeight(image))
            let subject = subjects.select(
                personPoints.map { Self.candidate(for: $0, aspect: imageAspect) },
                at: time,
                generation: generation
            )

            var joints: [BodyJoint: TrackingObservation.Landmark] = [:]
            if let subject {
                let points = personPoints[subject]
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
                    try VNImageRequestHandler(cvPixelBuffer: image, orientation: .up).perform([cupRequest])
                } catch {
                    self.cupRequest = nil
                    cupFailures.send("cup.modelUnavailable")
                }
                let objects: [VNRecognizedObjectObservation] = self.cupRequest == nil
                    ? [] : (cupRequest.results as? [VNRecognizedObjectObservation] ?? [])
                let aspect = Double(CVPixelBufferGetWidth(image)) / Double(CVPixelBufferGetHeight(image))
                let centers = objects.compactMap { object -> TherapyPoint? in
                    guard let label = object.labels.first, label.identifier == "cup",
                        label.confidence >= 0.45 else { return nil }
                    return TherapyPoint(x: object.boundingBox.midX * aspect, y: object.boundingBox.midY)
                }
                let bounds = objects.compactMap { object -> TherapyRectangle? in
                    guard object.labels.first?.identifier == "cup", (object.labels.first?.confidence ?? 0) >= 0.45 else { return nil }
                    let box = object.boundingBox
                    return TherapyRectangle(minX: box.minX * aspect, minY: box.minY, width: box.width * aspect, height: box.height)
                }
                cup = CupEvidence(timestamp: time, generation: generation, centers: centers, bounds: bounds)
            }
            deliver(
                TrackingObservation(
                    timestamp: time, generation: generation, width: CVPixelBufferGetWidth(image),
                    height: CVPixelBufferGetHeight(image),
                    // Bystanders are excluded once the patient is selected; ambiguity reports everyone.
                    personCount: subject == nil ? people.count : 1,
                    joints: joints,
                    cup: cup
                ))
        } catch {
            failures.send(error.localizedDescription)
        }
    }

    private func deliver(_ frame: TrackingObservation) {
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

    private static let torsoJoints: [VNHumanBodyPoseObservation.JointName] = [
        .neck, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .root,
    ]

    private static func candidate(
        for points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint],
        aspect: Double
    ) -> BodySubjectSelector.Candidate {
        let confident = points.values
            .filter { $0.confidence >= 0.3 }
            .map { TherapyPoint(x: $0.location.x * aspect, y: $0.location.y) }
        let torso = torsoJoints
            .compactMap { points[$0] }
            .filter { $0.confidence >= 0.3 }
            .map { TherapyPoint(x: $0.location.x * aspect, y: $0.location.y) }

        guard !torso.isEmpty, confident.count >= 2 else {
            // Without a torso this person cannot be followed, so they can never win continuity.
            return BodySubjectSelector.Candidate(torso: TherapyPoint(x: .infinity, y: .infinity), size: 0)
        }

        let xs = confident.map(\.x)
        let ys = confident.map(\.y)
        let diagonal = TherapyPoint(
            x: (xs.max() ?? 0) - (xs.min() ?? 0),
            y: (ys.max() ?? 0) - (ys.min() ?? 0)
        )
        let center = torso.reduce(TherapyPoint(x: 0, y: 0), +).scaled(1 / Double(torso.count))

        return BodySubjectSelector.Candidate(torso: center, size: diagonal.length)
    }

    private static let jointMap: [(BodyJoint, VNHumanBodyPoseObservation.JointName)] = [
        (.nose, .nose), (.neck, .neck), (.root, .root),
        (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow), (.leftWrist, .leftWrist),
        (.rightWrist, .rightWrist), (.leftHip, .leftHip), (.rightHip, .rightHip),
    ]
    private enum TrackingError: Error { case cameraUnavailable }
}
