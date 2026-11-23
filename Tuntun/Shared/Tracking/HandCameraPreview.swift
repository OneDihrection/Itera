//
//  HandCameraPreview.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import AVFoundation
import SwiftUI

struct TMHandCameraPreview: UIViewRepresentable {
    let cameraService: HandCameraService
    let ready: (Bool) -> Void
    let videoBoundsChanged: (CGRect?) -> Void

    func makeUIView(context: Context) -> TMCameraPreviewView {
        let view = TMCameraPreviewView()
        view.preview.session = cameraService.session
        view.preview.videoGravity = .resizeAspectFill
        view.cameraService = cameraService
        view.ready = ready
        view.videoBoundsChanged = videoBoundsChanged
        return view
    }

    func updateUIView(_ view: TMCameraPreviewView, context: Context) {
        view.ready = ready
        view.videoBoundsChanged = videoBoundsChanged
    }

    static func dismantleUIView(_ view: TMCameraPreviewView, coordinator: ()) {
        view.ready?(false)
        view.preview.session = nil
    }
}

final class TMCameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    weak var cameraService: HandCameraService?
    var ready: ((Bool) -> Void)?
    var videoBoundsChanged: ((CGRect?) -> Void)?
    private var videoBounds: CGRect?
    private var reportedReady = false
    /// The capture angle last sent to the camera service; cleared so the next layout sends it again.
    private var appliedCaptureAngle: CGFloat?
    private var previewObservation: NSKeyValueObservation?
    /// The camera's preview and capture angles; it reports changes on the main queue.
    private lazy var rotation = CameraRotationTracker { [weak self] angles in
        MainActor.assumeIsolated {
            self?.applyRotation(angles)
        }
    }
    private let videoMask = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        preview.actions = ["bounds": NSNull(), "position": NSNull(), "transform": NSNull()]
        previewObservation = preview.observe(\.isPreviewing, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.appliedCaptureAngle = nil
                self?.setNeedsLayout()
                self?.reportReadiness()
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            appliedCaptureAngle = nil
            rotation.stop()
        }
        setNeedsLayout()
        reportReadiness()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard window?.windowScene != nil else {
            return
        }
        #if !targetEnvironment(macCatalyst)
        // Mac windows have no interface orientation, and Mac cameras already deliver landscape
        // frames, so only iPad rotates.
        guard window?.windowScene?.interfaceOrientation.isLandscape == true else {
            reportReadiness()
            return
        }

        if let angles = rotation.track(preview.connection, previewLayer: preview) {
            applyRotation(angles)
        }
        #endif
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let connection = preview.connection {
            if connection.isVideoMirroringSupported {
                if connection.automaticallyAdjustsVideoMirroring {
                    connection.automaticallyAdjustsVideoMirroring = false
                }
                if !connection.isVideoMirrored {
                    connection.isVideoMirrored = true
                }
            }
        }
        updateVideoMask()
        CATransaction.commit()
        reportReadiness()
    }

    /// Keeps the preview upright and sends the capture angle to the camera service when it changes.
    private func applyRotation(_ angles: CameraRotationTracker.Angles) {
        if let connection = preview.connection {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CameraRotationTracker.apply(angles.preview, to: connection)
            CATransaction.commit()
        }

        guard appliedCaptureAngle != angles.capture else {
            return
        }

        appliedCaptureAngle = angles.capture
        cameraService?.rotateCapture(to: angles.capture)
    }

    private func updateVideoMask() {
        reportVideoBounds(preview.applyRoundedVideoMask(videoMask))
    }

    private func reportVideoBounds(_ bounds: CGRect?) {
        guard videoBounds != bounds else {
            return
        }

        videoBounds = bounds
        DispatchQueue.main.async { [weak self] in
            guard let self, self.videoBounds == bounds else {
                return
            }
            self.videoBoundsChanged?(bounds)
        }
    }

    private func reportReadiness() {
        #if targetEnvironment(macCatalyst)
        let landscape = true
        #else
        let orientation = window?.windowScene?.interfaceOrientation
        let landscape = orientation == .landscapeLeft || orientation == .landscapeRight
        #endif
        let attached = window != nil && preview.isPreviewing && landscape
        if attached != reportedReady {
            reportedReady = attached
            DispatchQueue.main.async { [weak self] in self?.ready?(attached) }
        }
    }
}

extension AVCaptureVideoPreviewLayer {
    /// Masks the visible image and returns its bounds. The preview fills its frame
    /// (aspect-fill), so these are the view's bounds.
    func applyRoundedVideoMask(_ videoMask: CAShapeLayer) -> CGRect? {
        guard isPreviewing else {
            mask = nil
            return nil
        }

        // Convert the full image and keep the part inside the view, so the corners follow it.
        let imageRect = layerRectConverted(
            fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1)
        ).intersection(bounds)
        guard !imageRect.isEmpty else {
            mask = nil
            return nil
        }

        videoMask.frame = bounds
        let localRect = imageRect.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        videoMask.path = UIBezierPath(roundedRect: localRect, cornerRadius: 28).cgPath
        mask = videoMask
        return localRect
    }
}
