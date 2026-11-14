//
//  AngleMeasurementViewModel.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import Combine
import Foundation
import Observation

/// Live joint-angle measurement for trying the tracking backends against a goniometer.
/// It owns no exercise rules and saves nothing: readings live only while the page is open.
@MainActor
@Observable
final class AngleMeasurementViewModel {
    enum Subject: String, CaseIterable, Identifiable {
        case body, hand

        var id: String { rawValue }
        var titleKey: String { "measurement.subject.\(rawValue)" }
    }

    enum Status: Equatable {
        case startingCamera
        case notVisible
        case measuring
    }

    // MARK: - Choices

    private(set) var subject: Subject = .body
    var bodyAngle: BodyAngle = .elbowFlexion { didSet { resetRange() } }
    var side: HandSide = .right {
        didSet {
            camera.track(side: side)
            resetRange()
        }
    }
    var finger: MeasuredFinger = .index {
        didSet {
            // The thumb has no end joint.
            if finger == .thumb, fingerJoint == .end {
                fingerJoint = .middle
            }
            resetRange()
        }
    }
    var fingerJoint: FingerJointLevel = .middle { didSet { resetRange() } }
    var measuresSpread = false { didSet { resetRange() } }

    private(set) var bodyBackend = BodyPoseBackend.saved
    private(set) var handBackend = HandPoseBackend.saved

    // MARK: - Readings

    private(set) var status = Status.startingCamera
    private(set) var live: AngleSample?
    private(set) var estimator = AngleHoldEstimator()
    /// Width over height of the current camera image, for the overlay.
    private(set) var imageAspect = 16.0 / 9.0

    @ObservationIgnored let tracking: BodyTrackingService
    @ObservationIgnored let camera: HandCameraService
    @ObservationIgnored private var subscriptions = Set<AnyCancellable>()
    @ObservationIgnored private var running = false
    @ObservationIgnored private var switchTask: Task<Void, Never>?

    init(tracking: BodyTrackingService, camera: HandCameraService) {
        self.tracking = tracking
        self.camera = camera
    }

    var handAngle: HandAngle {
        measuresSpread ? .spread : .flexion(finger, fingerJoint)
    }

    /// Joint levels that exist for the selected finger.
    var availableJoints: [FingerJointLevel] {
        finger == .thumb ? [.knuckle, .middle] : FingerJointLevel.allCases
    }

    // MARK: - Lifecycle

    func start() {
        guard !running else {
            return
        }

        running = true
        subscribe()
        startCamera()
    }

    func stop() {
        running = false
        switchTask?.cancel()
        subscriptions.removeAll()
        tracking.stop()
        camera.stop()
    }

    func select(_ subject: Subject) {
        guard subject != self.subject else {
            return
        }

        stopCamera()
        self.subject = subject
        clearLive()
        estimator.reset()

        // Both services use the same front camera; let the stopped one release it first.
        switchTask?.cancel()
        switchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))

            guard let self, !Task.isCancelled, self.running else {
                return
            }

            self.startCamera()
        }
    }

    func select(_ backend: BodyPoseBackend) {
        bodyBackend = backend
        UserDefaults.standard.set(backend.rawValue, forKey: BodyPoseBackend.storageKey)
        tracking.usePoseBackend(backend)
        resetRange()
    }

    func select(_ backend: HandPoseBackend) {
        handBackend = backend
        UserDefaults.standard.set(backend.rawValue, forKey: HandPoseBackend.storageKey)
        camera.usePoseBackend(backend)
        resetRange()
    }

    func resetRange() {
        estimator.reset()
    }

    /// From the body preview, which knows the interface orientation.
    func orientationChanged(right: Bool) {
        tracking.configure(landscapeRight: right)
    }

    // MARK: - Camera

    private func startCamera() {
        status = .startingCamera

        switch subject {
        case .body:
            tracking.requireCup(false)
            tracking.requireHand(false)
            tracking.usePoseBackend(bodyBackend)
            tracking.start()
        case .hand:
            camera.usePoseBackend(handBackend)
            camera.track(side: side)
            camera.start()
        }
    }

    private func stopCamera() {
        switch subject {
        case .body:
            tracking.stop()
        case .hand:
            camera.stop()
        }
    }

    private func subscribe() {
        tracking.frames
            .sink { [weak self] frame in
                self?.receive(frame)
            }
            .store(in: &subscriptions)

        camera.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.receive(event)
            }
            .store(in: &subscriptions)
    }

    private func receive(_ frame: TrackingObservation) {
        guard subject == .body, fresh(frame.timestamp) else {
            return
        }

        imageAspect = frame.aspect
        record(JointAngleCalculator.sample(bodyAngle, side: side, in: frame))
    }

    private func receive(_ event: HandCameraEvent) {
        guard subject == .hand, case .sample(let sample) = event, fresh(sample.timestamp) else {
            return
        }

        guard let hand = sample.evidence else {
            record(nil)
            return
        }

        imageAspect = hand.width / max(hand.height, 1)
        record(JointAngleCalculator.sample(handAngle, in: hand))
    }

    private func record(_ sample: AngleSample?) {
        guard let sample else {
            status = .notVisible
            clearLive()
            return
        }

        status = .measuring
        live = sample
        estimator.consume(sample)
    }

    private func clearLive() {
        live = nil
        estimator.missing()
    }

    /// The 300 ms freshness rule used for scoring; older frames would lag the reading.
    private func fresh(_ timestamp: Double) -> Bool {
        ProcessInfo.processInfo.systemUptime - timestamp <= 0.3
    }
}
