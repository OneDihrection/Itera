// measure_pitch.swift
// Created by dimaswisodewo on 16/11/2026.
//
// Measures how high and how settled each narration take sounds, so the calmest take can be
// chosen and energetic outliers caught (Tools/generate_marizka_counts.py).
//
// For each file it prints one tab-separated row:
//     name    medianHz    riseSemitones    spanSeconds    gapSeconds
// medianHz is the median voice pitch. riseSemitones compares the last 30% of voiced frames
// with the rest: positive values are rising, upbeat endings. spanSeconds predicts the length
// after Tools/normalize_narration.swift levels and trims the take, without its padding.
// gapSeconds is the longest silence inside that span: a long one is an odd mid-word pause or
// an extra sound.
// Files without enough voiced audio are skipped.
//
// Usage, from the repository root:
//     swiftc -O -o /tmp/measure_pitch Tools/measure_pitch.swift
//     /tmp/measure_pitch Tools/NarrationRaw/MarizkaCounts/*.mp3

import AVFoundation
import Foundation

/// Lowest and highest pitch searched; covers Marizka's speaking range with margin.
let minimumPitchHz = 70.0
let maximumPitchHz = 400.0
/// Autocorrelation below this is treated as unvoiced (breath, consonants, noise).
let voicingThreshold: Float = 0.6
/// Frames quieter than this fraction of the peak are ignored.
let loudnessGate: Float = 0.08
/// Fraction of voiced frames counted as the ending.
let endingFraction = 0.3
/// Must match normalize_narration.swift: speech level target, gain cap, level gate and the
/// edge-trim threshold, so spanSeconds predicts the trimmed length.
let targetSpeechDBFS = -15.0
let maximumGainDB = 24.0
let speechGate: Float = 0.01
let trimThreshold: Float = 0.008

struct Measurement {
    let medianHz: Double
    let riseSemitones: Double
    let spanSeconds: Double
    let gapSeconds: Double
}

func semitones(_ hertz: Double) -> Double {
    12 * log2(hertz / 100)
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}

/// The first channel at its recorded rate.
func monoSamples(of url: URL) -> (samples: [Float], rate: Double)? {
    guard
        let file = try? AVAudioFile(forReading: url),
        let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ),
        (try? file.read(into: buffer)) != nil,
        let data = buffer.floatChannelData
    else {
        return nil
    }

    let samples = Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
    return (samples, buffer.format.sampleRate)
}

/// Averages groups of three samples: about 14.7 kHz, plenty for speech pitch and three times
/// less autocorrelation work.
func decimated(_ samples: [Float]) -> [Float] {
    var result = [Float]()
    result.reserveCapacity(samples.count / 3)

    var index = 0
    while index + 2 < samples.count {
        result.append((samples[index] + samples[index + 1] + samples[index + 2]) / 3)
        index += 3
    }

    return result
}

/// Seconds between the first and last sample the normalizer keeps, after its levelling gain,
/// and the longest silence between them.
func trimmedSpan(of samples: [Float], rate: Double) -> (span: Double, gap: Double) {
    var sum = 0.0
    var voiced = 0
    for sample in samples where abs(sample) > speechGate {
        sum += Double(sample * sample)
        voiced += 1
    }

    guard voiced > 0 else {
        return (0, 0)
    }

    let level = 20 * log10(sqrt(sum / Double(voiced)))
    let gain = Float(pow(10, min(maximumGainDB, targetSpeechDBFS - level) / 20))
    let threshold = trimThreshold / gain

    guard
        let first = samples.firstIndex(where: { abs($0) >= threshold }),
        let last = samples.lastIndex(where: { abs($0) >= threshold })
    else {
        return (0, 0)
    }

    var longestGap = 0
    var previous = first
    for index in first...last where abs(samples[index]) >= threshold {
        longestGap = max(longestGap, index - previous)
        previous = index
    }

    return (Double(last - first) / rate, Double(longestGap) / rate)
}

/// The best normalized autocorrelation lag in the pitch range, or nil when unvoiced.
func pitch(in samples: [Float], start: Int, window: Int, lags: ClosedRange<Int>, energy: Float) -> Int? {
    var bestLag = 0
    var bestCorrelation: Float = 0

    for lag in lags {
        var product: Float = 0
        var laggedEnergy: Float = 0
        for index in start..<(start + window) {
            product += samples[index] * samples[index + lag]
            laggedEnergy += samples[index + lag] * samples[index + lag]
        }

        let correlation = product / max(sqrt(energy * laggedEnergy), 1e-9)
        if correlation > bestCorrelation {
            bestCorrelation = correlation
            bestLag = lag
        }
    }

    return bestCorrelation > voicingThreshold ? bestLag : nil
}

func measure(_ url: URL) -> Measurement? {
    guard let (fullSamples, fullRate) = monoSamples(of: url) else {
        return nil
    }

    let samples = decimated(fullSamples)
    let rate = fullRate / 3

    let peak = samples.map(abs).max() ?? 0
    guard peak > 0 else {
        return nil
    }

    let window = Int(rate * 0.04)
    let hop = Int(rate * 0.01)
    let lags = Int(rate / maximumPitchHz)...Int(rate / minimumPitchHz)
    var pitches = [Double]()

    var start = 0
    while start + window + lags.upperBound < samples.count {
        var energy: Float = 0
        for index in start..<(start + window) {
            energy += samples[index] * samples[index]
        }

        if sqrt(energy / Float(window)) > peak * loudnessGate {
            if let lag = pitch(in: samples, start: start, window: window, lags: lags, energy: energy) {
                pitches.append(rate / Double(lag))
            }
        }

        start += hop
    }

    guard pitches.count >= 5 else {
        return nil
    }

    let split = Int(Double(pitches.count) * (1 - endingFraction))
    let rise = semitones(median(Array(pitches[split...]))) - semitones(median(Array(pitches[..<split])))

    let trimmed = trimmedSpan(of: fullSamples, rate: fullRate)
    return Measurement(
        medianHz: median(pitches),
        riseSemitones: rise,
        spanSeconds: trimmed.span,
        gapSeconds: trimmed.gap
    )
}

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let measurement = measure(url) else {
        continue
    }

    print(
        String(
            format: "%@\t%.1f\t%.2f\t%.3f\t%.3f",
            url.deletingPathExtension().lastPathComponent,
            measurement.medianHz,
            measurement.riseSemitones,
            measurement.spanSeconds,
            measurement.gapSeconds
        )
    )
}
