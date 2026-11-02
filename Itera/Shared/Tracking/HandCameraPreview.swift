//
//  HandCameraPreview.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import AVFoundation
import SwiftUI

struct HandCameraPreview: UIViewRepresentable {
    let camera: HandCameraService
    let ready: (Bool) -> Void

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.preview.session = camera.session
        view.preview.videoGravity = .resizeAspect
        view.camera = camera
        view.ready = ready
        return view
    }

    func updateUIView(_ view: CameraPreviewView, context: Context) {
        view.ready = ready
    }

    static func dismantleUIView(_ view: CameraPreviewView, coordinator: ()) {
        view.ready?(false)
        view.preview.session = nil
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    weak var camera: HandCameraService?
    var ready: ((Bool) -> Void)?
    private var reportedReady = false
    private var appliedOrientation: AVCaptureVideoOrientation?
    private var previewObservation: NSKeyValueObservation?

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
        switch scene.interfaceOrientation {
        case .landscapeLeft: orientation = .landscapeLeft
        case .landscapeRight: orientation = .landscapeRight
        default:
            reportReadiness()
            return
        }
        if appliedOrientation != orientation {
            appliedOrientation = orientation
            camera?.orient(orientation)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let connection = preview.connection {
            if connection.videoOrientation != orientation {
                connection.videoOrientation = orientation
            }
            if connection.automaticallyAdjustsVideoMirroring {
                connection.automaticallyAdjustsVideoMirroring = false
            }
            if !connection.isVideoMirrored {
                connection.isVideoMirrored = true
            }
        }
        CATransaction.commit()
        reportReadiness()
    }

    private func reportReadiness() {
        let orientation = window?.windowScene?.interfaceOrientation
        let landscape = orientation == .landscapeLeft || orientation == .landscapeRight
        let attached = window != nil && preview.isPreviewing && landscape
        if attached != reportedReady {
            reportedReady = attached
            DispatchQueue.main.async { [weak self] in self?.ready?(attached) }
        }
    }
}
