//
//  BodyCameraPreview.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import AVFoundation
import SwiftUI

struct TMBodyCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let front: Bool
    let onReady: (Bool) -> Void
    let onOrientation: (Bool) -> Void
    var onVideoBounds: ((CGRect?) -> Void)? = nil

    func makeUIView(context: Context) -> TMPreviewView {
        let view = TMPreviewView()
        TMPreviewView.active = view
        view.previewLayer.videoGravity = .resizeAspect
        view.previewLayer.session = session
        view.onReady = onReady
        view.onOrientation = onOrientation
        view.onVideoBounds = onVideoBounds
        view.observation = view.previewLayer.observe(\.isPreviewing, options: [.initial, .new]) {
            [weak view] layer, _ in
            DispatchQueue.main.async { [weak view] in
                view?.setNeedsLayout()
                view?.reportReadiness()
            }
        }
        return view
    }

    func updateUIView(_ view: TMPreviewView, context: Context) {
        view.front = front
        view.onVideoBounds = onVideoBounds
        view.setNeedsLayout()
    }

    static func dismantleUIView(_ view: TMPreviewView, coordinator: ()) {
        // A replaced view must not clear readiness that its successor already reported.
        if TMPreviewView.active === view || TMPreviewView.active == nil {
            view.onReady?(false)
        }
        view.observation = nil
        view.onReady = nil
        view.onOrientation = nil
        view.onVideoBounds = nil
        view.previewLayer.session = nil
    }

    final class TMPreviewView: UIView {
        /// The most recently created preview, the only one allowed to report "not ready" on teardown.
        static weak var active: TMPreviewView?

        var observation: NSKeyValueObservation?
        var onReady: ((Bool) -> Void)?
        var onOrientation: ((Bool) -> Void)?
        var onVideoBounds: ((CGRect?) -> Void)?
        private let videoMask = CAShapeLayer()
        private var videoBounds: CGRect?
        var front = true
        private var lastOrientation: UIInterfaceOrientation?
        private var reportedReady = false
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                lastOrientation = nil
            }
            setNeedsLayout()
            reportReadiness()
        }

        func reportReadiness() {
            let ready = window != nil
                && !isHidden
                && bounds.width > 0
                && bounds.height > 0
                && previewLayer.session != nil
                && previewLayer.isPreviewing
            guard ready != reportedReady else { return }
            reportedReady = ready
            NSLog("Body preview rendering=%@ attached=%@", ready.description, (window != nil).description)
            onReady?(ready)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            reportReadiness()
            #if targetEnvironment(macCatalyst)
            // Mac windows have no interface orientation and Mac cameras deliver upright frames, so use the unrotated (0°) landscapeRight path.
            let orientation = UIInterfaceOrientation.landscapeRight
            #else
            guard let orientation = window?.windowScene?.interfaceOrientation,
                  orientation == .landscapeLeft || orientation == .landscapeRight else { return }
            #endif
            let right = orientation == .landscapeRight
            let videoOrientation: AVCaptureVideoOrientation = right ? .landscapeRight : .landscapeLeft
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let connection = previewLayer.connection {
                #if targetEnvironment(macCatalyst)
                if connection.isVideoRotationAngleSupported(0) {
                    connection.videoRotationAngle = 0
                }
                #else
                if connection.isVideoOrientationSupported,
                   connection.videoOrientation != videoOrientation {
                    connection.videoOrientation = videoOrientation
                }
                #endif
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = front
                }
            }
            if onVideoBounds != nil {
                updateVideoBounds(previewLayer.applyRoundedVideoMask(videoMask))
            } else {
                previewLayer.mask = nil
                videoBounds = nil
            }
            CATransaction.commit()
            if orientation != lastOrientation {
                lastOrientation = orientation
                DispatchQueue.main.async { [weak self] in self?.onOrientation?(right) }
            }
        }

        private func updateVideoBounds(_ bounds: CGRect?) {
            guard videoBounds != bounds else {
                return
            }

            videoBounds = bounds
            DispatchQueue.main.async { [weak self] in
                guard let self, self.videoBounds == bounds else {
                    return
                }
                self.onVideoBounds?(bounds)
            }
        }
    }
}
