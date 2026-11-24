//
//  CameraDisplayGeometry.swift
//  Tuntun
//
//  Created by dimaswisodewo on 05/11/2026.
//

import Foundation
import CoreGraphics

/// The image rectangle of an aspect-fill camera preview: the whole image scaled to cover the
/// viewport, centred, so it overflows on the cropped sides. Overlays map normalized points
/// through it, so they stay on the joints the preview shows.
struct CameraDisplayGeometry {
    let imageRect: CGRect

    /// The part of the image the preview shows, in normalized image coordinates. It is centred,
    /// so it is the same with a top or bottom origin and under mirroring. Overlays that must stay
    /// whole on screen (the fold towel) lay out inside it.
    let visibleRect: CGRect

    init(aspect: Double, viewport: CGSize) {
        let aspect = aspect.isFinite && aspect > 0 ? aspect : 1
        let height = max(viewport.height, viewport.width / aspect)
        let size = CGSize(width: height * aspect, height: height)
        imageRect = CGRect(
            x: (viewport.width - size.width) / 2,
            y: (viewport.height - size.height) / 2,
            width: size.width,
            height: size.height
        )

        guard size.width > 0, size.height > 0 else {
            visibleRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            return
        }

        visibleRect = CGRect(
            x: -imageRect.minX / size.width,
            y: -imageRect.minY / size.height,
            width: viewport.width / size.width,
            height: viewport.height / size.height
        )
    }

    func point(_ normalized: CGPoint, mirrored: Bool = false) -> CGPoint {
        CGPoint(
            x: imageRect.minX + (mirrored ? 1 - normalized.x : normalized.x) * imageRect.width,
            y: imageRect.minY + (1 - normalized.y) * imageRect.height
        )
    }
}
