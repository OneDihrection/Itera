//
//  HandCameraPreview.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import AVFoundation
import SwiftUI

struct TMHandCameraPreview: UIViewRepresentable {
    let camera: HandCameraService
    let ready: (Bool) -> Void
    let videoBoundsChanged: (CGRect?) -> Void

    func makeUIView(context: Context) -> TMCameraPreviewView {
        let view = TMCameraPreviewView()
        view.preview.session = camera.session
        view.preview.videoGravity = .resizeAspect
        view.camera = camera
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
    weak var camera: HandCameraService?
    var ready: ((Bool) -> Void)?
    var videoBoundsChanged: ((CGRect?) -> Void)?
    private var videoBounds: CGRect?
    private var reportedReady = false
    private var appliedOrientation: AVCaptureVideoOrientation?
    private var previewObservation: NSKeyValueObservation?
    private let videoMask = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        preview.actions = ["bounds": NSNull(), "position": NSNull(), "transform": NSNull()]
        previewObservation = preview.observe(\.isPreviewing, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.appliedOrientation = nil
                self?.setNeedsLayout()
                self?.reportReadiness()
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            appliedOrientation = nil
        }
        setNeedsLayout()
        reportReadiness()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let scene = window?.windowScene else {
            return
        }
        let orientation: AVCaptureVideoOrientation
        #if targetEnvironment(macCatalyst)
        // Mac windows have no interface orientation, and Mac cameras already deliver landscape frames.
        orientation = .landscapeLeft
        #else
        switch scene.interfaceOrientation {
        case .landscapeLeft: orientation = .landscapeLeft
        case .landscapeRight: orientation = .landscapeRight
        default:
            reportReadiness()
            return
        }
        #endif
        if appliedOrientation != orientation {
            appliedOrientation = orientation
            camera?.orient(orientation)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let connection = preview.connection {
            #if !targetEnvironment(macCatalyst)
            if connection.isVideoOrientationSupported, connection.videoOrientation != orientation {
                connection.videoOrientation = orientation
            }
            #endif
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
    /// Masks the actual aspect-fit image and returns its bounds for the caption.
    func applyRoundedVideoMask(_ videoMask: CAShapeLayer) -> CGRect? {
        guard isPreviewing else {
            mask = nil
            return nil
        }

        // Convert the full image so the corners follow the video inside its letterbox margins.
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
