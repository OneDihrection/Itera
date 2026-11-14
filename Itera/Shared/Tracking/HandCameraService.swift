//
//  HandCameraService.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import AVFoundation
import Combine
import Vision

enum HandDetectionIssue: Equatable { case missingHand, multipleHands, unreadable }

struct CameraSample {
    let evidence: HandEvidence?
    let timestamp: Double
    let generation: UUID
    var issue: HandDetectionIssue? = nil
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
    private var device: AVCaptureDevice?
    private var previousCenterStage: (mode: AVCaptureDevice.CenterStageControlMode, enabled: Bool)?
    private var lastInference = 0.0
    private var notifications: [NSObjectProtocol] = []
    /// Keeps scoring on the patient's hand when bystanders' or the other hand appear. Queue-confined.
    private var subjects = HandSubjectSelector()
    /// One hand-pose inference per camera frame at 30 fps. At 15 Hz the drawn hand and its ring
    /// moved in visible steps and every filter lagged twice as long. Work stays bounded: inference
    /// runs on the capture queue and late frames are dropped by the output, never queued.
    private static let inferenceInterval = 1.0 / 30
    /// Confined to `queue`.
    private var poseBackend: HandPoseBackend
    #if canImport(MediaPipeTasksVision)
    /// Loaded on first use; queue-confined.
    private var mediaPipe: MediaPipeHandDetector?
    /// Set when MediaPipe cannot load or run; Vision is used until the backend is chosen again.
    private var mediaPipeFailed = false
    #endif

    init(poseBackend: HandPoseBackend = .vision) {
        self.poseBackend = poseBackend
        super.init()
        // Room for both of the patient's hands plus a bystander's, so the exercised hand
        // is not crowded out of the results; the subject selector picks among them.
        request.maximumHandCount = 4
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
                    try beginFixedFraming()
                    generation = UUID()
                    lastInference = 0
                    session.startRunning()
                }
            } catch {
                restoreCenterStage()
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
            restoreCenterStage()
        }
    }

    /// Chooses the hand detector for the next frames. Every finger rule reads the same joints,
    /// so this can change between sessions without other changes.
    func usePoseBackend(_ backend: HandPoseBackend) {
        queue.async { [self] in
            let backend = backend.isAvailable ? backend : .vision
            poseBackend = backend
            subjects.reset()
            #if canImport(MediaPipeTasksVision)
            mediaPipeFailed = false
            #endif
            NSLog("Hand pose backend=%@", backend.rawValue)
        }
    }

    /// Sets the exercised side, used only to choose between several newly visible hands.
    func track(side: HandSide) {
        queue.async { [self] in
            subjects.preferredSide = side
            subjects.reset()
        }
    }

    func orient(_ orientation: AVCaptureVideoOrientation) {
        #if targetEnvironment(macCatalyst)
        // Mac cameras already deliver upright landscape frames; forcing an orientation rotates them.
        return
        #else
        queue.async { [self] in
            if let connection = output.connection(with: .video), connection.videoOrientation != orientation {
                connection.videoOrientation = orientation
                generation = UUID()
            }
        }
        #endif
    }

    private func configure() throws {
        var selectedCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        #if targetEnvironment(macCatalyst)
        // A Mac’s user-facing webcam can report an unspecified position.
        selectedCamera = selectedCamera ?? AVCaptureDevice.default(for: .video)
        #endif
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let camera = selectedCamera, camera.position != .back else {
            throw CameraError.unavailable
        }
        let input = try AVCaptureDeviceInput(device: camera)
        device = camera
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw CameraError.unavailable
        }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        // MediaPipe reads only 32BGRA frames; Vision accepts them too, so one format serves both.
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            #if !targetEnvironment(macCatalyst)
            connection.videoOrientation = .landscapeLeft
            #endif
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .off
            }
        }
        configured = true
    }

    private func beginFixedFraming() throws {
        if previousCenterStage == nil {
            previousCenterStage = (AVCaptureDevice.centerStageControlMode, AVCaptureDevice.isCenterStageEnabled)
        }
        AVCaptureDevice.centerStageControlMode = .app
        AVCaptureDevice.isCenterStageEnabled = false
        guard let device else {
            return
        }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.cancelVideoZoomRamp()
        device.videoZoomFactor = max(1, device.minAvailableVideoZoomFactor)
    }

    private func restoreCenterStage() {
        guard let previousCenterStage else {
            return
        }
        AVCaptureDevice.centerStageControlMode = .app
        AVCaptureDevice.isCenterStageEnabled = previousCenterStage.enabled
        AVCaptureDevice.centerStageControlMode = previousCenterStage.mode
        self.previousCenterStage = nil
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // The session clock is not always the host clock on Mac, which the view model's freshness check assumes.
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(buffer)
        let timestamp = CMSyncConvertTime(
            presentationTime,
            from: session.synchronizationClock ?? CMClockGetHostTimeClock(),
            to: CMClockGetHostTimeClock()
        ).seconds
        guard timestamp - lastInference >= Self.inferenceInterval - 0.001,
              let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        lastInference = timestamp
        let width = Double(CVPixelBufferGetWidth(pixelBuffer))
        let height = Double(CVPixelBufferGetHeight(pixelBuffer))

        do {
            let hands = try detectHands(
                in: buffer,
                pixelBuffer: pixelBuffer,
                timestamp: timestamp,
                width: width,
                height: height
            )

            // Never choose by screen position alone; ambiguous scenes report no hand.
            guard let index = subjects.select(
                hands.map(HandPoseExtractor.candidate(for:)),
                at: timestamp,
                generation: generation
            ) else {
                events.send(.sample(CameraSample(
                    evidence: nil, timestamp: timestamp, generation: generation,
                    issue: hands.count > 1 ? .multipleHands : .missingHand
                )))
                return
            }

            events.send(.sample(CameraSample(evidence: hands[index], timestamp: timestamp, generation: generation)))
        } catch {
            events.send(.sample(CameraSample(evidence: nil, timestamp: timestamp, generation: generation, issue: .unreadable)))
        }
    }

    // MARK: - Detectors

    private func detectHands(
        in buffer: CMSampleBuffer,
        pixelBuffer: CVPixelBuffer,
        timestamp: Double,
        width: Double,
        height: Double
    ) throws -> [HandEvidence] {
        #if canImport(MediaPipeTasksVision)
        if poseBackend == .mediaPipe, let detector = loadMediaPipe() {
            do {
                return try detector.hands(
                    in: buffer,
                    timestamp: timestamp,
                    generation: generation,
                    width: width,
                    height: height
                )
            } catch {
                mediaPipeFailed = true
                NSLog("MediaPipe hand detection failed, using Vision: %@", error.localizedDescription)
            }
        }
        #endif

        try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up).perform([request])

        return try (request.results ?? []).map { hand in
            try HandPoseExtractor.evidence(
                from: hand,
                timestamp: timestamp,
                generation: generation,
                width: width,
                height: height
            )
        }
    }

    #if canImport(MediaPipeTasksVision)
    private func loadMediaPipe() -> MediaPipeHandDetector? {
        guard !mediaPipeFailed else {
            return nil
        }

        if let mediaPipe {
            return mediaPipe
        }

        do {
            mediaPipe = try MediaPipeHandDetector(maximumHands: request.maximumHandCount)
        } catch {
            mediaPipeFailed = true
            NSLog("MediaPipe hand model unavailable, using Vision: %@", error.localizedDescription)
        }

        return mediaPipe
    }
    #endif

    private enum CameraError: Error { case unavailable }
}
