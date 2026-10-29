//
//  BodyCameraPreview.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import AVFoundation
import SwiftUI

struct BodyCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let front: Bool
    let onReady: (Bool) -> Void
    let onOrientation: (Bool) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspect
        view.previewLayer.session = session
        view.onReady = onReady
        view.onOrientation = onOrientation
        view.observation = view.previewLayer.observe(\.isPreviewing, options: [.initial, .new]) {
            [weak view] layer, _ in
            DispatchQueue.main.async { [weak view] in view?.onReady?(layer.isPreviewing) }
        }
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.front = front
        view.setNeedsLayout()
    }

    static func dismantleUIView(_ view: PreviewView, coordinator: ()) {
        view.observation = nil
        view.onReady = nil
        view.onOrientation = nil
        view.previewLayer.session = nil
    }

    final class PreviewView: UIView {
        var observation: NSKeyValueObservation?
        var onReady: ((Bool) -> Void)?
        var onOrientation: ((Bool) -> Void)?
        var front = true
        private var lastOrientation: UIInterfaceOrientation?
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            let orientation = window?.windowScene?.interfaceOrientation ?? .landscapeLeft
            let right = orientation == .landscapeRight
            if let connection = previewLayer.connection {
                let angle: CGFloat = right ? 0 : 180
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = front
                }
            }
            if orientation != lastOrientation {
                lastOrientation = orientation
                DispatchQueue.main.async { [weak self] in self?.onOrientation?(right) }
            }
        }
    }
}
