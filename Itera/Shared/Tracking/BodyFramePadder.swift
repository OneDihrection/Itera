//
//  BodyFramePadder.swift
//  Itera
//
//  Created by dimaswisodewo on 10/11/2026.
//

import CoreVideo
import Foundation

/// Extends each camera frame downward with a neutral strip before body pose inference.
///
/// Vision's body pose model expects a mostly full-body subject. A seated patient close to the
/// camera shows only head and torso, and the person or key joints then drop out. Padding below
/// the subject gives the model room for the lower body it expects. Results come back in padded
/// coordinates, so callers must map `y` through `originalY(_:)`.
///
/// Frames are padded in the camera's own 8-bit bi-planar YUV format by copying plane rows on the
/// CPU: about 2 MB of copying per 720p frame, with no GPU work or colour conversion, so padding
/// adds a small fixed cost to every frame's age. Other formats are not padded.
///
/// Not thread-safe: owned and used by the inference queue only.
final class BodyFramePadder {
    /// Extra height below the frame, as a fraction of the original height.
    static let bottomPadding = 0.5

    /// Neutral grey in video and full range alike: mid luma, zero chroma.
    private static let neutral: UInt8 = 128

    private static let supportedFormats: Set<OSType> = [
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    ]

    private var pool: CVPixelBufferPool?
    private var poolWidth = 0
    private var poolHeight = 0
    private var poolFormat: OSType = 0
    private var reportedUnsupportedFormat: OSType?

    /// Maps a normalized Vision `y` (bottom-left origin) from the padded frame back to the
    /// original frame. Points inside the padding strip come out negative.
    static func originalY(_ paddedY: Double) -> Double {
        paddedY * (1 + bottomPadding) - bottomPadding
    }

    /// Returns the padded copy of `image`, or nil when it cannot be padded (an unsupported pixel
    /// format or no buffer), in which case the caller runs inference on the original frame
    /// without remapping.
    func padded(_ image: CVPixelBuffer) -> CVPixelBuffer? {
        let format = CVPixelBufferGetPixelFormatType(image)

        guard Self.supportedFormats.contains(format) else {
            reportUnsupported(format)
            return nil
        }

        let width = CVPixelBufferGetWidth(image)
        let height = CVPixelBufferGetHeight(image)

        // Chroma is subsampled vertically, so the padded height stays even.
        let paddedHeight = Int((Double(height) * (1 + Self.bottomPadding) / 2).rounded()) * 2

        guard let pool = pool(width: width, height: paddedHeight, format: format) else {
            return nil
        }

        var created: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created)

        guard let output = created else {
            return nil
        }

        CVPixelBufferLockBaseAddress(image, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(output, [])
            CVPixelBufferUnlockBaseAddress(image, .readOnly)
        }

        // Plane 0 is luma, plane 1 interleaved CbCr; both copy the same way.
        for plane in 0..<2 {
            copyPlane(plane, from: image, to: output)
        }

        CVBufferPropagateAttachments(image, output)
        return output
    }

    /// Copies one plane's rows to the top of the output plane and fills the rows below with grey.
    /// Pool buffers are recycled, so the strip is filled on every frame.
    private func copyPlane(_ plane: Int, from source: CVPixelBuffer, to output: CVPixelBuffer) {
        guard let sourceBase = CVPixelBufferGetBaseAddressOfPlane(source, plane),
              let outputBase = CVPixelBufferGetBaseAddressOfPlane(output, plane) else {
            return
        }

        let sourceRows = CVPixelBufferGetHeightOfPlane(source, plane)
        let outputRows = CVPixelBufferGetHeightOfPlane(output, plane)
        let sourceStride = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
        let outputStride = CVPixelBufferGetBytesPerRowOfPlane(output, plane)
        let rowBytes = min(sourceStride, outputStride)

        if sourceStride == outputStride {
            memcpy(outputBase, sourceBase, sourceStride * sourceRows)
        } else {
            for row in 0..<sourceRows {
                memcpy(outputBase + row * outputStride, sourceBase + row * sourceStride, rowBytes)
            }
        }

        let stripRows = outputRows - sourceRows

        guard stripRows > 0 else {
            return
        }

        memset(outputBase + sourceRows * outputStride, Int32(Self.neutral), stripRows * outputStride)
    }

    private func pool(width: Int, height: Int, format: OSType) -> CVPixelBufferPool? {
        if let pool, poolWidth == width, poolHeight == height, poolFormat == format {
            return pool
        }

        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: format,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
        ]

        var created: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &created)

        pool = created
        poolWidth = width
        poolHeight = height
        poolFormat = format

        return created
    }

    private func reportUnsupported(_ format: OSType) {
        guard reportedUnsupportedFormat != format else {
            return
        }

        reportedUnsupportedFormat = format
        NSLog("Body frame padding skipped for pixel format %u", format)
    }
}
