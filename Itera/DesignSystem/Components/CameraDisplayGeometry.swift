//
//  CameraDisplayGeometry.swift
//  Itera
//
//  Created by dimaswisodewo on 05/11/2026.
//

import Foundation
import CoreGraphics

/// The image rectangle used by an aspect-fit camera preview, excluding letterbox margins.
struct CameraDisplayGeometry {
    let imageRect: CGRect

    init(aspect: Double, viewport: CGSize) {
        let aspect = aspect.isFinite && aspect > 0 ? aspect : 1
        let height = min(viewport.height, viewport.width / aspect)
        let size = CGSize(width: height * aspect, height: height)
        imageRect = CGRect(
            x: (viewport.width - size.width) / 2,
            y: (viewport.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    func point(_ normalized: CGPoint, mirrored: Bool = false) -> CGPoint {
        CGPoint(
            x: imageRect.minX + (mirrored ? 1 - normalized.x : normalized.x) * imageRect.width,
            y: imageRect.minY + (1 - normalized.y) * imageRect.height
        )
    }
}
