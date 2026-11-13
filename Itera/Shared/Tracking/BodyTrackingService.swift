//
//  BodyTrackingService.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import AVFoundation
import Combine
import Vision

/// One serial capture/inference owner, with one replaceable pending delivery on the main queue.
final class BodyTrackingService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let frames = PassthroughSubject<TrackingObservation, Never>()
    let failures = PassthroughSubject<String, Never>()
    let availability = PassthroughSubject<TrackingAvailability, Never>()
    /// Privacy-filtered key-repetition video, fed from body inference while sessions enable it.
    let clips = RepClipFrameSource()

    private let queue = DispatchQueue(label: "Itera.bodyTracking", qos: .userInitiated)
    private let inferenceQueue = DispatchQueue(label: "Itera.bodyInference", qos: .userInitiated)
    private var inferenceBusy = false
    private let deliveryLock = NSLock()
    private var pending: TrackingObservation?
    private var deliveryScheduled = false
    private var generation = UUID()
    private var orientation: AVCaptureVideoOrientation = .landscapeLeft
    private var previousCenterStage: (mode: AVCaptureDevice.CenterStageControlMode, enabled: Bool)?
    private var wantsCapture = false
    private var configured = false
    private var hasInitialOrientation = false
    private var timestampOffset: Double?
    private var lastStaleLog = 0.0
    /// Per-stage inference timing, logged every 10 s. Confined to `queue`.
    private var timing = BodyInferenceTiming()
    /// Oldest inference result still worth showing, in seconds.
    private static let maximumFrameAge = 0.8
    /// Keeps tracking the patient while bystanders are in view. Confined to `inferenceQueue`.
    private var subjects = BodySubjectSelector()
    private var lastInferenceFailure = 0.0
    private var watchdogIdentity = UUID()
    private var frameWatchdog: DispatchWorkItem?
    private var awaitingFirstFrame = false
    /// Automatic restarts since the last delivered frame; bounded so a dead camera is reported, not looped.
    private var watchdogRestarts = 0
    private var captureStartedAt = 0.0

    private let handRequest = VNDetectHumanHandPoseRequest()
    private var handEnabled = false
    private var normalLens = false
    /// Chooses the patient's hand among several. Confined to `inferenceQueue`.
    private var handSubjects = HandSubjectSelector()

    /// Hand inference shares the capture session and bounded delivery with body inference.
    /// - Parameter side: the exercised hand, used to pick the patient's hand when several are visible.
    func requireHand(_ enabled: Bool, side: HandSide? = nil) {
        inferenceQueue.async { [weak self] in
            guard let self else { return }
            self.handEnabled = enabled
            self.handSubjects.preferredSide = side
            self.handSubjects.reset()
        }
        queue.async { [weak self] in
            guard let self, self.normalLens != enabled else { return }
            self.normalLens = enabled
            guard self.configured else { return }
            // The lens changes only when a new activity starts, before it has any calibration, so
            // this is a camera wait rather than a discontinuity that pauses the session.
            self.availability.send(.waiting)
            self.session.stopRunning()
            self.cancelFrameWatchdog()
            self.session.beginConfiguration()
            for input in self.session.inputs { self.session.removeInput(input) }
            for output in self.session.outputs { self.session.removeOutput(output) }
            self.session.commitConfiguration()
            self.configured = false
            self.invalidateGeneration()
            self.startIfRequested()
        }
    }

    private let request = VNDetectHumanBodyPoseRequest()
    /// Confined to `inferenceQueue`.
    private let framePadder = BodyFramePadder()
    /// Pads frames for upper-body stability. Set `Itera.bodyFramePadding` to false in
    /// `UserDefaults` to compare against unpadded inference on a device.
    private static let padsFrames = UserDefaults.standard.object(forKey: "Itera.bodyFramePadding") as? Bool ?? true
    private var notifications: [NSObjectProtocol] = []

    override init() {
        super.init()
        handRequest.maximumHandCount = 4
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

                    // Frames can resume without an interruption-ended notification; the first one
                    // must still announce the new generation, or every later frame is rejected.
                    self.awaitingFirstFrame = true
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
                let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
                NSLog("Body capture runtime error domain=%@ code=%ld", error?.domain ?? "unknown", error?.code ?? 0)
                self.queue.async {
                    self.cancelFrameWatchdog()
                    self.invalidateGeneration()
                    self.session.stopRunning()
                    self.restoreCenterStage()
                    self.availability.send(.discontinuity)
                    // Sent from `queue` so it always follows the discontinuity.
                    self.failures.send(error?.localizedDescription ?? "")
                    self.restartOnceAfterFailure()
                }
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
            // The service outlives sessions, so each explicit start earns a fresh automatic restart.
            self.watchdogRestarts = 0
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

    func configure(landscapeRight: Bool) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            let orientation: AVCaptureVideoOrientation = landscapeRight ? .landscapeRight : .landscapeLeft
            let initialConfiguration = !self.hasInitialOrientation
            self.hasInitialOrientation = true
            guard initialConfiguration || self.orientation != orientation else {
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
            self.orientation = orientation
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
        var selectedCamera = (normalLens ? nil : AVCaptureDevice.default(
            .builtInUltraWideCamera, for: .video, position: .front
        )) ?? AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .front
        )
        #if targetEnvironment(macCatalyst)
        // A Mac’s user-facing webcam can report an unspecified position.
        selectedCamera = selectedCamera ?? AVCaptureDevice.default(for: .video)
        #endif
        guard let camera = selectedCamera, camera.position != .back else {
            throw TrackingError.cameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: camera)
        NSLog("Body capture selected device=%@ type=%@ position=%ld", camera.localizedName, camera.deviceType.rawValue, camera.position.rawValue)
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
            // Semantic orientation accounts for the selected camera's sensor mounting.
            // A fixed raw angle can invert front-camera frames by 180 degrees.
            #if targetEnvironment(macCatalyst)
            if connection.isVideoRotationAngleSupported(0) {
                connection.videoRotationAngle = 0
            }
            #else
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = orientation
            }
            #endif
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
        // The capture session's clock is not always the host clock on Mac, so a fixed offset
        // measured at start skews every frame's age. Convert each timestamp to the host clock,
        // as the hand pipeline does, so the freshness check below reflects real latency.
        let time = CMSyncConvertTime(
            CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            from: session.synchronizationClock ?? CMClockGetHostTimeClock(),
            to: CMClockGetHostTimeClock()
        ).seconds
        guard time.isFinite else {
            return
        }
        if awaitingFirstFrame {
            awaitingFirstFrame = false
            NSLog("Body capture first frame delay=%.3f seconds generation=%@", ProcessInfo.processInfo.systemUptime - captureStartedAt, generation.uuidString)
            watchdogRestarts = 0
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
        // Hand inference runs at the full capture rate: a lower rate makes the cursor visibly steppy.
        do {
            // Vision reports in the padded frame when padding is used; `originalY` maps back.
            var paddedImage: CVPixelBuffer?
            var paddingTime: Double?
            if !handEnabled, Self.padsFrames {
                let paddingStart = ProcessInfo.processInfo.systemUptime
                paddedImage = framePadder.padded(image)

                if paddedImage != nil {
                    paddingTime = ProcessInfo.processInfo.systemUptime - paddingStart
                }
            }

            let inferenceStart = ProcessInfo.processInfo.systemUptime
            if !handEnabled {
                try VNImageRequestHandler(cvPixelBuffer: paddedImage ?? image, orientation: .up).perform([request])
            }
            let originalY: (Double) -> Double = paddedImage == nil ? { $0 } : BodyFramePadder.originalY
            let people = handEnabled ? [] : (request.results ?? [])
            let personPoints = people.map { (try? $0.recognizedPoints(.all)) ?? [:] }
            let imageAspect = Double(CVPixelBufferGetWidth(image)) / Double(CVPixelBufferGetHeight(image))
            let subject = subjects.select(
                personPoints.map { Self.candidate(for: $0, aspect: imageAspect, originalY: originalY) },
                at: time,
                generation: generation
            )

            if clips.claimFrame(at: time) {
                clips.offer(image, time: time, heads: clipHeads(personPoints, originalY: originalY))
            }

            var joints: [BodyJoint: TrackingObservation.Landmark] = [:]
            if let subject {
                let points = personPoints[subject]
                for (joint, visionJoint) in Self.jointMap {
                    if let point = points[visionJoint] {
                        let y = originalY(point.location.y)

                        // Inside the padding strip is below the frame: a guess, never a sighting.
                        guard y >= 0 else {
                            continue
                        }

                        joints[joint] = .init(
                            position: TherapyPoint(x: point.location.x, y: y),
                            confidence: point.confidence)
                    }
                }
            }
            var hand: HandEvidence?
            if handEnabled {
                try VNImageRequestHandler(cvPixelBuffer: image, orientation: .up).perform([handRequest])
                let hands = handRequest.results ?? []
                // Never choose by screen position alone; ambiguous scenes report no hand.
                if let index = handSubjects.select(
                    hands.map { HandPoseExtractor.candidate(for: $0, aspect: imageAspect) },
                    at: time,
                    generation: generation
                ) {
                    hand = try HandPoseExtractor.evidence(
                        from: hands[index], timestamp: time, generation: generation,
                        width: Double(CVPixelBufferGetWidth(image)),
                        height: Double(CVPixelBufferGetHeight(image))
                    )
                }
            }
            deliver(
                TrackingObservation(
                    timestamp: time, generation: generation, width: CVPixelBufferGetWidth(image),
                    height: CVPixelBufferGetHeight(image),
                    // Bystanders are excluded once the patient is selected; ambiguity reports everyone.
                    personCount: subject == nil ? people.count : 1,
                    joints: joints,
                    hand: hand,
                    subjectEpoch: subjects.epoch
                ),
                padding: paddingTime,
                inference: ProcessInfo.processInfo.systemUptime - inferenceStart
            )
        } catch {
            if time - lastInferenceFailure >= 5 {
                lastInferenceFailure = time
                NSLog("Body inference failed: %@", error.localizedDescription)
            }
            // Missing evidence clears holds without taking down healthy video.
            deliver(TrackingObservation(
                timestamp: time, generation: generation,
                width: CVPixelBufferGetWidth(image), height: CVPixelBufferGetHeight(image),
                personCount: 0, joints: [:]
            ))
        }
    }

    /// - Parameters:
    ///   - padding: seconds spent padding the frame, nil when it was not padded.
    ///   - inference: seconds spent in Vision and selection, nil when inference failed.
    private func deliver(_ frame: TrackingObservation, padding: Double? = nil, inference: Double? = nil) {
        queue.async { [weak self] in
            guard let self, self.wantsCapture, self.generation == frame.generation else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let age = now - frame.timestamp

            // Inference takes noticeable time on Mac; a frame slightly late is still far better
            // than none, since a dropped frame looks to the patient like lost tracking.
            guard age <= Self.maximumFrameAge else {
                self.timing.recordDropped(now: now)

                if ProcessInfo.processInfo.systemUptime - self.lastStaleLog >= 3 {
                    self.lastStaleLog = ProcessInfo.processInfo.systemUptime
                    NSLog("Body frame dropped as stale age=%.3f", age)
                }
                return
            }

            if let inference {
                self.timing.record(padding: padding, vision: inference, age: age, now: now)
            }

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

    /// Joints that identify a person across frames. Hips and root are left out on purpose: a
    /// seated patient close to the camera often has them out of frame or flickering, and each
    /// appearance or loss shifted the identity point enough to drop the lock onto the patient,
    /// so the skeleton vanished whenever someone else was in view.
    private static let torsoJoints: [VNHumanBodyPoseObservation.JointName] = [
        .neck, .nose, .leftShoulder, .rightShoulder,
    ]

    private static func candidate(
        for points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint],
        aspect: Double,
        originalY: (Double) -> Double
    ) -> BodySubjectSelector.Candidate {
        let confident = points.values
            .filter { $0.confidence >= 0.3 }
            .map { TherapyPoint(x: $0.location.x * aspect, y: originalY($0.location.y)) }
        let torso = torsoJoints
            .compactMap { points[$0] }
            .filter { $0.confidence >= 0.3 }
            .map { TherapyPoint(x: $0.location.x * aspect, y: originalY($0.location.y)) }

        guard !torso.isEmpty, confident.count >= 2 else {
            // Without a torso this person cannot be followed, so they can never win continuity.
            return BodySubjectSelector.Candidate(torso: TherapyPoint(x: .infinity, y: .infinity), size: 0)
        }

        let center = torso.reduce(TherapyPoint(x: 0, y: 0), +).scaled(1 / Double(torso.count))

        return BodySubjectSelector.Candidate(
            torso: center,
            size: shoulderWidth(points, aspect: aspect, originalY: originalY),
            centerOffset: abs(center.x / max(aspect, 0.0001) - 0.5)
        )
    }

    /// Shoulder width: visible for every upper-body exercise, unchanged by arm movement, and
    /// steadier than a box that grows when hips appear or disappear behind a table. Returns 0
    /// (unknown) when a shoulder is not confidently visible. A fallback measure such as the torso
    /// box differs from shoulder width by far more than the selector's size tolerance, so a raised
    /// arm hiding one shoulder used to make the patient look like a different person.
    private static func shoulderWidth(
        _ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint],
        aspect: Double,
        originalY: (Double) -> Double
    ) -> Double {
        guard let left = points[.leftShoulder],
              let right = points[.rightShoulder],
              left.confidence >= 0.3,
              right.confidence >= 0.3 else {
            return 0
        }

        let width = TherapyPoint(
            x: (left.location.x - right.location.x) * aspect,
            y: originalY(left.location.y) - originalY(right.location.y)
        )
        return width.length
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
            self.restartOnceAfterFailure()
        }
        frameWatchdog = work
        queue.asyncAfter(deadline: .now() + (firstFrame ? 3.0 : 1.0), execute: work)
    }

    /// Tries once to bring the camera back without waiting for a manual retry; the session still
    /// pauses on the discontinuity and resumes only on explicit request. The count resets when a
    /// frame arrives or capture is started explicitly, so a dead camera is reported, not looped.
    private func restartOnceAfterFailure() {
        guard watchdogRestarts < 1 else {
            return
        }

        watchdogRestarts += 1
        queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startIfRequested()
        }
    }

    private static let jointMap: [(BodyJoint, VNHumanBodyPoseObservation.JointName)] = [
        (.nose, .nose), (.neck, .neck), (.root, .root),
        (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow), (.leftWrist, .leftWrist),
        (.rightWrist, .rightWrist), (.leftHip, .leftHip), (.rightHip, .rightHip),
        (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
        (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
    ]
    private static let faceJoints: [VNHumanBodyPoseObservation.JointName] = [
        .nose, .leftEye, .rightEye, .leftEar, .rightEar,
    ]
    /// Every person's head, bystanders included, so no face is left unfiltered. Hand mode runs no
    /// body pose, so it reports nil and face detection alone censors faces. Confined to
    /// `inferenceQueue`.
    private func clipHeads(
        _ people: [[VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]],
        originalY: (Double) -> Double
    ) -> [RepClipHead]? {
        guard !handEnabled else {
            return nil
        }

        guard clips.needsHeads else {
            return []
        }

        return people.map { Self.clipHead(from: $0, originalY: originalY) }
    }

    /// Head points count from this confidence: a weakly seen face is still worth hiding.
    private static let clipHeadConfidence: Float = 0.1

    private static func clipHead(
        from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint],
        originalY: (Double) -> Double
    ) -> RepClipHead {
        func located(_ name: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let point = points[name], point.confidence >= clipHeadConfidence else {
                return nil
            }

            let y = originalY(point.location.y)

            guard y >= 0 else {
                return nil
            }

            return CGPoint(x: point.location.x, y: y)
        }

        return RepClipHead(face: faceJoints.compactMap(located), neck: located(.neck))
    }

    private enum TrackingError: Error { case cameraUnavailable }
}
