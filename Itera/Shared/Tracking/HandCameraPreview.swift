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
        view.setNeedsLayout()
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
    private var previewObservation: NSKeyValueObservation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewObservation = preview.observe(\.isPreviewing, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.reportReadiness() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
            ready?(false)
            return
        }
        camera?.orient(orientation)
        if let connection = preview.connection {
            connection.videoOrientation = orientation
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        reportReadiness()
    }

    private func reportReadiness() {
        let attached = window != nil && preview.isPreviewing
        if attached != reportedReady {
            reportedReady = attached
            DispatchQueue.main.async { [weak self] in self?.ready?(attached) }
        }
    }
}
