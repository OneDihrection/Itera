//
//  RepClipFrameSource.swift
//  Itera
//
//  Created by dimaswisodewo on 12/11/2026.
//

import CoreImage
import CoreVideo
import Foundation
import Vision

/// Turns camera frames into small filtered frames and keeps the ones that belong to key
/// repetitions, so a session report can show a short clip beside the skeleton replay.
///
/// Every stored frame is filtered as `RepClipPrivacy` asks before it is encoded: the background
/// is blurred through Vision person segmentation, and each head (from the body pose and from
/// face detection) is pixelated. Only the Vision requests a chosen filter needs are run. When a
/// chosen filter cannot be applied, the frame fails closed: a missing head reuses head regions
/// seen within `headMemory`, and otherwise the whole picture is blurred. A frame is never kept
/// with less censoring than was chosen.
///
/// Hand cameras have no body pose and usually look at the hands, so their frames are offered
/// without head evidence: only faces the detector finds are pixelated, and a frame with no
/// detected face is kept sharp. This is the caregiver-accepted exception to failing closed.
///
/// Work is bounded and never delays inference: frames are taken at most every `frameInterval`,
/// only one is processed at a time on a utility queue (later offers are dropped), the ring
/// holds `ringSeconds`, and kept clips are limited to the key repetitions of two sets.
final class RepClipFrameSource: @unchecked Sendable {
    static let frameInterval = 0.1
    static let outputWidth = 320
    /// Longer than the longest recorded repetition (`KeyRepRecorder.maximumRepSeconds`).
    private static let ringSeconds = 65.0
    private static let headMemory = 0.3
    /// Sets whose clips are held; the older one is still waiting to be taken for saving.
    private static let maximumGroups = 2

    private let queue = DispatchQueue(label: "Itera.repClips", qos: .utility)
    private let context = CIContext(options: [.priorityRequestLow: true, .cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private let segmentation: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .fast
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()
    private let faces = VNDetectFaceRectanglesRequest()

    /// Guards the flags read from the inference queue.
    private let lock = NSLock()
    private var enabled = false
    private var privacy = RepClipPrivacy()
    private var busy = false
    private var lastOffer = -Double.infinity

    // Confined to `queue`.
    private var ring: [RepClipFrame] = []
    private var groups: [UUID: [Int: [RepClipFrame]]] = [:]
    private var groupOrder: [UUID] = []
    private var lastHeads: (time: Double, regions: [CGRect])?
    private var lastFailureLog = -Double.infinity

    // MARK: - Control

    /// Starts or stops taking frames. Stopping keeps the ring: the transition that ends a set
    /// also credits its last repetition, whose `keep` may arrive just after recording stops. The
    /// ring is bounded by time and `keep` copies by time range, so older frames never join a
    /// later repetition.
    func setEnabled(_ value: Bool) {
        lock.withLock {
            enabled = value
        }
    }

    /// Drops the ring at the end of a session, keeping clips already kept so pending saves can
    /// still take them. Runs after any `keep` sent before it.
    func releaseFrames() {
        queue.async { [weak self] in
            self?.ring.removeAll()
            self?.lastHeads = nil
        }
    }

    /// Chooses what clips hide. Sessions set it once when they start, after `reset()`, so one
    /// session never mixes filters.
    func configure(privacy: RepClipPrivacy) {
        lock.withLock {
            self.privacy = privacy
        }
    }

    /// Whether offers need head evidence; building it is skipped when faces are not censored.
    var needsHeads: Bool {
        lock.withLock {
            privacy.blursFace
        }
    }

    /// Drops every frame and clip, for the end of a session.
    func reset() {
        setEnabled(false)

        queue.async { [weak self] in
            guard let self else {
                return
            }

            self.ring.removeAll()
            self.groups.removeAll()
            self.groupOrder.removeAll()
            self.lastHeads = nil
        }
    }

    // MARK: - Input

    /// Whether a frame captured at `time` should be offered. Claims the single processing slot,
    /// so a true answer must be followed by `offer`.
    func claimFrame(at time: Double) -> Bool {
        lock.withLock {
            // The slack lets every third 30 fps frame through despite timestamp jitter;
            // otherwise only every fourth would qualify.
            guard enabled,
                  !busy,
                  time - lastOffer >= Self.frameInterval - 0.01
            else {
                return false
            }

            busy = true
            lastOffer = time
            return true
        }
    }

    /// Filters and stores `image` after `claimFrame(at:)` returned true.
    /// - Parameter heads: Head evidence for every detected person, bystanders included, or nil
    ///   from a hand camera, which has no body pose; face censoring then relies on face
    ///   detection alone.
    func offer(_ image: CVPixelBuffer, time: Double, heads: [RepClipHead]?) {
        let privacy = lock.withLock { self.privacy }

        queue.async { [weak self] in
            guard let self else {
                return
            }

            if let jpeg = self.filteredJPEG(from: image, time: time, heads: heads, privacy: privacy) {
                self.append(RepClipFrame(time: time, jpeg: jpeg))
            }

            self.lock.withLock {
                self.busy = false
            }
        }
    }

    // MARK: - Key repetitions

    /// Copies the frames from `start` to `end` into `group` as `repNumber`, and releases clips of
    /// that group whose repetitions are no longer in `retaining`.
    func keep(group: UUID, repNumber: Int, from start: Double, to end: Double, retaining: Set<Int>) {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            let frames = self.ring.filter { $0.time >= start && $0.time <= end }

            if self.groups[group] == nil {
                self.groupOrder.append(group)
                self.dropOldGroups()
            }

            var clips = self.groups[group] ?? [:]
            clips[repNumber] = frames.isEmpty ? nil : frames
            clips = clips.filter { retaining.contains($0.key) }
            self.groups[group] = clips
        }
    }

    /// Removes and returns the clips kept for `group`, by repetition number.
    func take(group: UUID) async -> [Int: [RepClipFrame]] {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: [:])
                    return
                }

                let clips = self.groups.removeValue(forKey: group) ?? [:]
                self.groupOrder.removeAll { $0 == group }
                continuation.resume(returning: clips)
            }
        }
    }

    // MARK: - Storage

    private func append(_ frame: RepClipFrame) {
        ring.append(frame)

        let oldest = frame.time - Self.ringSeconds
        if let first = ring.first, first.time < oldest {
            ring.removeAll { $0.time < oldest }
        }
    }

    /// A set that is never saved (skipped, or nothing credited) must not hold memory forever.
    private func dropOldGroups() {
        while groupOrder.count > Self.maximumGroups {
            let oldest = groupOrder.removeFirst()
            groups[oldest] = nil
        }
    }

    // MARK: - Filtering

    private func filteredJPEG(
        from image: CVPixelBuffer,
        time: Double,
        heads: [RepClipHead]?,
        privacy: RepClipPrivacy
    ) -> Data? {
        let source = CIImage(cvPixelBuffer: image)
        let size = Self.outputSize(for: source.extent.size)
        let small = Self.scaled(source, to: size)
        let bounds = CGRect(origin: .zero, size: size)

        let output = filtered(small, time: time, heads: heads, privacy: privacy)
            ?? Self.blurred(small, sigma: 16, bounds: bounds)

        return context.jpegRepresentation(
            of: output,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.6]
        )
    }

    /// Applies the chosen filters, or returns nil when one of them cannot be applied, so the
    /// caller blurs the whole frame.
    private func filtered(
        _ image: CIImage,
        time: Double,
        heads: [RepClipHead]?,
        privacy: RepClipPrivacy
    ) -> CIImage? {
        var requests: [VNRequest] = []

        if privacy.blursBackground {
            requests.append(segmentation)
        }

        if privacy.blursFace {
            requests.append(faces)
        }

        guard !requests.isEmpty else {
            return image
        }

        do {
            try VNImageRequestHandler(ciImage: image, orientation: .up).perform(requests)
        } catch {
            logFailure("Rep clip filtering failed: \(error.localizedDescription)", at: time)
            return nil
        }

        let size = image.extent.size
        let bounds = CGRect(origin: .zero, size: size)
        var output = image

        if privacy.blursBackground {
            guard let result = segmentation.results?.first else {
                return nil
            }

            let mask = Self.scaled(CIImage(cvPixelBuffer: result.pixelBuffer), to: size)
            output = Self.blurringBackground(output, mask: mask, bounds: bounds)
        }

        if privacy.blursFace {
            guard let regions = headRegions(heads: heads, faces: faces.results ?? [], size: size, time: time) else {
                return nil
            }

            output = Self.pixelatingHeads(output, source: image, regions: regions, bounds: bounds)
        }

        return output
    }

    /// Pixel rectangles to pixelate, or nil when the frame must be blurred whole.
    private func headRegions(
        heads: [RepClipHead]?,
        faces: [VNFaceObservation],
        size: CGSize,
        time: Double
    ) -> [CGRect]? {
        let faceRegions = faces.map { face in
            let box = VNImageRectForNormalizedRect(face.boundingBox, Int(size.width), Int(size.height))
            return box.insetBy(dx: -box.width * 0.3, dy: -box.height * 0.3)
        }

        // Without body pose there is no way to know whether a person is in view, so the face
        // detector alone decides (see the type's documentation).
        guard let heads else {
            return faceRegions
        }

        let poseRegions = heads.map { Self.region(for: $0, size: size) }
        let located = poseRegions.compactMap { $0 } + faceRegions
        // A person whose head was not located is covered only when face detection found one.
        let everyHeadCovered = !poseRegions.contains(nil) || !faceRegions.isEmpty

        if !located.isEmpty, everyHeadCovered {
            lastHeads = (time, located)
            return located
        }

        if let lastHeads, time - lastHeads.time <= Self.headMemory {
            return lastHeads.regions
        }

        // No one in view is not a privacy risk only if nobody is there; without a located head we
        // cannot tell, so the whole frame is blurred.
        return nil
    }

    /// A square around the face points, large enough for hair and a turned head.
    private static func region(for head: RepClipHead, size: CGSize) -> CGRect? {
        guard !head.face.isEmpty else {
            return nil
        }

        let points = head.face.map { pixel($0, size: size) }
        let count = CGFloat(points.count)
        let sumX = points.reduce(CGFloat(0)) { $0 + $1.x }
        let sumY = points.reduce(CGFloat(0)) { $0 + $1.y }
        let center = CGPoint(x: sumX / count, y: sumY / count)
        let spread = points.map { distance($0, center) }.max() ?? 0
        let neckDistance = head.neck.map { distance(pixel($0, size: size), center) } ?? 0
        let half = max(spread * 1.8, neckDistance * 0.9, size.height * 0.08)

        return CGRect(x: center.x - half, y: center.y - half, width: half * 2, height: half * 2)
    }

    private static func pixel(_ normalized: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: normalized.x * size.width, y: normalized.y * size.height)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func logFailure(_ message: String, at time: Double) {
        guard time - lastFailureLog >= 5 else {
            return
        }

        lastFailureLog = time
        NSLog("%@", message)
    }

    // MARK: - Image operations

    /// `outputWidth` wide with the source aspect, rounded to even sizes for the video encoder.
    static func outputSize(for source: CGSize) -> CGSize {
        let width = CGFloat(outputWidth)
        let height = (width * source.height / max(source.width, 1) / 2).rounded() * 2
        return CGSize(width: width, height: max(height, 2))
    }

    private static func scaled(_ image: CIImage, to size: CGSize) -> CIImage {
        let extent = image.extent

        guard extent.width > 0, extent.height > 0 else {
            return image
        }

        return image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: size.width / extent.width, y: size.height / extent.height))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    private static func blurred(_ image: CIImage, sigma: Double, bounds: CGRect) -> CIImage {
        image
            .clampedToExtent()
            .applyingGaussianBlur(sigma: sigma)
            .cropped(to: bounds)
    }

    /// People kept sharp through the segmentation mask over a blurred room.
    private static func blurringBackground(_ image: CIImage, mask: CIImage, bounds: CGRect) -> CIImage {
        image
            .applyingFilter(
                "CIBlendWithMask",
                parameters: [
                    kCIInputBackgroundImageKey: blurred(image, sigma: 10, bounds: bounds),
                    kCIInputMaskImageKey: mask,
                ]
            )
            .cropped(to: bounds)
    }

    /// Every head region pixelated from the unfiltered `source`, over `image`.
    private static func pixelatingHeads(
        _ image: CIImage,
        source: CIImage,
        regions: [CGRect],
        bounds: CGRect
    ) -> CIImage {
        var output = image

        // Blurring before pixelating removes edges that coarse blocks would otherwise keep.
        let softened = source.clampedToExtent().applyingGaussianBlur(sigma: 3)

        for head in regions {
            let block = max(head.width / 3, 6)
            let pixelated = softened
                .applyingFilter(
                    "CIPixellate",
                    parameters: [
                        kCIInputCenterKey: CIVector(x: head.midX, y: head.midY),
                        kCIInputScaleKey: block,
                    ]
                )
                .cropped(to: head)

            output = pixelated.composited(over: output)
        }

        return output.cropped(to: bounds)
    }
}
