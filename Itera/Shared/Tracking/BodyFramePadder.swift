//
//  BodyFramePadder.swift
//  Itera
//
//  Created by dimaswisodewo on 10/11/2026.
//

import CoreImage
import CoreVideo

/// Extends each camera frame downward with a neutral strip before body pose inference.
///
/// Vision's body pose model expects a mostly full-body subject. A seated patient close to the
/// camera shows only head and torso, and the person or key joints then drop out. Padding below
/// the subject gives the model room for the lower body it expects. Results come back in padded
/// coordinates, so callers must map `y` through `originalY(_:)`.
///
/// Not thread-safe: owned and used by the inference queue only.
final class BodyFramePadder {
    /// Extra height below the frame, as a fraction of the original height.
    static let bottomPadding = 0.5

    private let context = CIContext()
    private let background = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
    private var pool: CVPixelBufferPool?
    private var poolWidth = 0
    private var poolHeight = 0

    /// Maps a normalized Vision `y` (bottom-left origin) from the padded frame back to the
    /// original frame. Points inside the padding strip come out negative.
    static func originalY(_ paddedY: Double) -> Double {
        paddedY * (1 + bottomPadding) - bottomPadding
    }

    /// Returns the padded copy of `image`, or nil when a buffer could not be produced, in which
    /// case the caller should run inference on the original frame without remapping.
    func padded(_ image: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(image)
        let height = CVPixelBufferGetHeight(image)
        let paddedHeight = Int((Double(height) * (1 + Self.bottomPadding)).rounded())

        guard let pool = pool(width: width, height: paddedHeight) else {
            return nil
        }

        var output: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output)

        guard let output else {
            return nil
        }

        let bounds = CGRect(x: 0, y: 0, width: width, height: paddedHeight)

        // Core Image's origin is bottom-left, so lifting the frame by the strip height keeps it on top.
        let frame = CIImage(cvPixelBuffer: image)
            .transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(paddedHeight - height)))
        let composite = frame.composited(over: background.cropped(to: bounds))

        context.render(composite, to: output, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())

        return output
    }

    private func pool(width: Int, height: Int) -> CVPixelBufferPool? {
        if let pool, poolWidth == width, poolHeight == height {
            return pool
        }

        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
        ]

        var created: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &created)

        pool = created
        poolWidth = width
        poolHeight = height

        return created
    }
}
