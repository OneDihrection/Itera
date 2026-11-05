//
//  CupObjectTracker.swift
//  Itera
//
//  Created by dimaswisodewo on 05/11/2026.
//

import Vision

/// Inference-queue confined. Detection confirms identity; tracking fills the intervening frames.
final class CupObjectTracker {
    private var sequence = VNSequenceRequestHandler()
    private var request: VNTrackObjectRequest?
    private var generation: UUID?
    private var trackID: UUID?
    private var candidate: CGRect?
    private var candidateCount = 0
    private var lastDetection = -Double.infinity
    private var lastConfirmation = -Double.infinity
    private var lastFrame: Double?
    private var state: CupTrackingState = .searching
    #if DEBUG
    private var metricStart = 0.0
    private var metricFrames = 0
    private var metricDetections = 0
    private var metricProcessingTime = 0.0
    private var metricCaptureAge = 0.0
    #endif

    func reset() {
        sequence = VNSequenceRequestHandler()
        request = nil
        trackID = nil
        candidate = nil
        candidateCount = 0
        lastDetection = -Double.infinity
        lastConfirmation = -Double.infinity
        lastFrame = nil
        state = .searching
    }

    func process(
        _ image: CVPixelBuffer,
        timestamp: Double,
        generation: UUID,
        detector: VNCoreMLRequest
    ) throws -> CupEvidence {
        #if DEBUG
        let processingStarted = ProcessInfo.processInfo.systemUptime
        defer {
            let finished = ProcessInfo.processInfo.systemUptime
            if metricStart == 0 { metricStart = processingStarted }
            metricFrames += 1
            metricProcessingTime += finished - processingStarted
            metricCaptureAge += max(0, finished - timestamp)
            let interval = finished - metricStart
            if interval >= 2 {
                NSLog(
                    "Cup tracking updates=%.1f/s detections=%.1f/s processing=%.0fms age=%.0fms",
                    Double(metricFrames) / interval, Double(metricDetections) / interval,
                    metricProcessingTime / Double(metricFrames) * 1000,
                    metricCaptureAge / Double(metricFrames) * 1000)
                metricStart = finished
                metricFrames = 0
                metricDetections = 0
                metricProcessingTime = 0
                metricCaptureAge = 0
            }
        }
        #endif
        if self.generation != generation {
            reset()
            self.generation = generation
        }
        if let lastFrame, timestamp - lastFrame > 0.3 {
            reset()
        }
        lastFrame = timestamp
        let aspect = Double(CVPixelBufferGetWidth(image)) / Double(CVPixelBufferGetHeight(image))
        var observation: VNDetectedObjectObservation?

        if let request {
            try sequence.perform([request], on: image, orientation: .up)
            if let result = request.results?.first as? VNDetectedObjectObservation,
               result.confidence >= 0.5,
               valid(result.boundingBox) {
                observation = result
                request.inputObservation = result
            } else {
                lose(.lost)
            }
        }

        if timestamp - lastDetection >= 0.2 {
            lastDetection = timestamp
            #if DEBUG
            metricDetections += 1
            #endif
            try VNImageRequestHandler(cvPixelBuffer: image, orientation: .up).perform([detector])
            let detections = (detector.results as? [VNRecognizedObjectObservation] ?? []).filter {
                $0.labels.first?.identifier == "cup"
                    && ($0.labels.first?.confidence ?? 0) >= 0.45
                    && valid($0.boundingBox)
            }

            if let tracked = observation, trackID != nil {
                let matches = detections.filter { associated($0.boundingBox, with: tracked.boundingBox, aspect: aspect) }
                if matches.count == 1, let match = matches.first {
                    lastConfirmation = timestamp
                    seed(match)
                    observation = match
                    state = .tracking
                } else {
                    lose(matches.count > 1 ? .ambiguous : .lost)
                    observation = nil
                }
            } else if detections.count == 1, let detection = detections.first {
                if let candidate, associated(detection.boundingBox, with: candidate, aspect: aspect) {
                    candidateCount += 1
                } else {
                    candidateCount = 1
                }
                candidate = detection.boundingBox
                state = .searching
                if candidateCount >= 3 {
                    trackID = UUID()
                    lastConfirmation = timestamp
                    seed(detection)
                    observation = detection
                    state = .tracking
                }
            } else {
                lose(detections.count > 1 ? .ambiguous : .searching)
                observation = nil
            }
        }

        guard let observation, let trackID,
              timestamp - lastConfirmation <= 0.3 else {
            if self.trackID != nil {
                lose(.lost)
            }
            return CupEvidence(timestamp: timestamp, generation: generation, centers: [], state: state)
        }
        let box = observation.boundingBox
        return CupEvidence(
            timestamp: timestamp,
            generation: generation,
            centers: [TherapyPoint(x: box.midX * aspect, y: box.midY)],
            bounds: [TherapyRectangle(
                minX: box.minX * aspect, minY: box.minY,
                width: box.width * aspect, height: box.height)],
            trackID: trackID,
            confidence: (observation as? VNRecognizedObjectObservation)?.labels.first?.confidence
                ?? observation.confidence,
            lastDetectionTimestamp: lastConfirmation,
            state: .tracking
        )
    }

    private func seed(_ observation: VNDetectedObjectObservation) {
        let next = VNTrackObjectRequest(detectedObjectObservation: observation)
        next.trackingLevel = .accurate
        request = next
    }

    private func lose(_ state: CupTrackingState) {
        sequence = VNSequenceRequestHandler()
        request = nil
        trackID = nil
        candidate = nil
        candidateCount = 0
        self.state = state
    }

    private func valid(_ box: CGRect) -> Bool {
        box.minX.isFinite && box.minY.isFinite && box.width.isFinite && box.height.isFinite
            && box.width > 0 && box.height > 0
            && box.minX >= 0 && box.minY >= 0 && box.maxX <= 1 && box.maxY <= 1
    }

    private func associated(_ box: CGRect, with reference: CGRect, aspect: Double) -> Bool {
        let intersection = box.intersection(reference)
        let intersectionArea = intersection.isNull ? 0 : intersection.width * intersection.height
        let union = box.width * box.height + reference.width * reference.height - intersectionArea
        guard union > 0, intersectionArea / union >= 0.15 else {
            return false
        }
        let scale = max(reference.width * aspect, reference.height)
        let distance = hypot((box.midX - reference.midX) * aspect, box.midY - reference.midY)
        let ratio = box.width * box.height / (reference.width * reference.height)
        return distance <= scale * 0.75 && (0.4...2.5).contains(ratio)
    }
}
