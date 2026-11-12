//
//  RepClipWriter.swift
//  Itera
//
//  Created by dimaswisodewo on 12/11/2026.
//

import AVFoundation
import CoreImage

/// Encodes already-filtered key-repetition frames as a small silent MP4.
///
/// HEVC keeps a clip at roughly half the size of H.264 at the same look; H.264 is used only
/// where the encoder rejects HEVC.
///
/// The file is written beside its destination and moved into place only when complete, so a
/// failed or interrupted write never leaves a partial clip behind.
enum RepClipWriter {
    private static let hevcBitRate = 120_000
    private static let h264BitRate = 150_000
    /// One keyframe every three seconds at 10 fps; clips are short, so seeking stays quick.
    private static let keyFrameInterval = 30
    /// The last frame stays on screen for one capture interval.
    private static let lastFrameDuration = RepClipFrameSource.frameInterval

    enum WriteError: Error {
        case noFrames
        case unreadableFrame
        case writerFailed(String)
    }

    static func write(_ frames: [RepClipFrame], to url: URL) async throws {
        let frames = increasingFrames(frames)

        guard let first = frames.first,
              let firstImage = CIImage(data: first.jpeg)
        else {
            throw WriteError.noFrames
        }

        let width = Int(firstImage.extent.width)
        let height = Int(firstImage.extent.height)
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: temporary) }

        let writer = try AVAssetWriter(outputURL: temporary, fileType: .mp4)
        let hevc = settings(codec: .hevc, bitRate: hevcBitRate, width: width, height: height)
        let outputSettings = writer.canApply(outputSettings: hevc, forMediaType: .video)
            ? hevc
            : settings(codec: .h264, bitRate: h264BitRate, width: width, height: height)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )

        guard writer.canAdd(input) else {
            throw WriteError.writerFailed("input rejected")
        }

        writer.add(input)

        guard writer.startWriting() else {
            throw WriteError.writerFailed(writer.error?.localizedDescription ?? "start")
        }

        writer.startSession(atSourceTime: .zero)

        let context = CIContext(options: [.priorityRequestLow: true, .cacheIntermediates: false])
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        for frame in frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }

            guard let image = CIImage(data: frame.jpeg),
                  let pool = adaptor.pixelBufferPool
            else {
                writer.cancelWriting()
                throw WriteError.unreadableFrame
            }

            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)

            guard let buffer else {
                writer.cancelWriting()
                throw WriteError.writerFailed("pixel buffer")
            }

            context.render(image, to: buffer, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: colorSpace)

            let time = CMTime(seconds: frame.time - first.time, preferredTimescale: 600)

            guard adaptor.append(buffer, withPresentationTime: time) else {
                writer.cancelWriting()
                throw WriteError.writerFailed(writer.error?.localizedDescription ?? "append")
            }
        }

        let end = (frames.last?.time ?? first.time) - first.time + lastFrameDuration
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: end, preferredTimescale: 600))
        await writer.finishWriting()

        guard writer.status == .completed else {
            throw WriteError.writerFailed(writer.error?.localizedDescription ?? "finish")
        }

        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }

    private static func settings(
        codec: AVVideoCodecType,
        bitRate: Int,
        width: Int,
        height: Int
    ) -> [String: Any] {
        [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoMaxKeyFrameIntervalKey: keyFrameInterval,
            ],
        ]
    }

    /// Presentation times must strictly increase at the 600 timescale.
    private static func increasingFrames(_ frames: [RepClipFrame]) -> [RepClipFrame] {
        var result: [RepClipFrame] = []

        for frame in frames.sorted(by: { $0.time < $1.time }) {
            if let last = result.last, frame.time - last.time < 1.0 / 600 {
                continue
            }

            result.append(frame)
        }

        return result
    }
}
