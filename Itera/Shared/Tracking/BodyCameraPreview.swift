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
            DispatchQueue.main.async { [weak view] in
                view?.setNeedsLayout()
                view?.onReady?(layer.isPreviewing)
            }
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

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                lastOrientation = nil
            }
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let orientation = window?.windowScene?.interfaceOrientation,
                  orientation == .landscapeLeft || orientation == .landscapeRight else {
                return
            }
            let right = orientation == .landscapeRight
            let videoOrientation: AVCaptureVideoOrientation = right ? .landscapeRight : .landscapeLeft
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let connection = previewLayer.connection {
                if connection.isVideoOrientationSupported,
                   connection.videoOrientation != videoOrientation {
                    connection.videoOrientation = videoOrientation
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = front
                }
            }
            CATransaction.commit()
            if orientation != lastOrientation {
                lastOrientation = orientation
                DispatchQueue.main.async { [weak self] in self?.onOrientation?(right) }
            }
        }
    }
}
