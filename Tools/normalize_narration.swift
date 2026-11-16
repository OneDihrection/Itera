// normalize_narration.swift
// Created by Amelia Putri Aftiana on 05/11/2026.
//
// Makes every narration clip equally loud and clearly audible, then saves it as AAC.
//
// Recordings from ElevenLabs arrive quiet and uneven (speech around -22 dBFS, varying
// by about 11 dB between sentences). Each clip is scaled so its speech level reaches
// `targetSpeechDBFS`, and a soft limiter keeps peaks under `ceilingDBFS` so loud syllables
// never distort. Sources stay untouched in Tools/NarrationRaw, so this can be rerun
// without generating speech again.
//
// Usage, from the repository root:
//     swift Tools/normalize_narration.swift Tools/NarrationRaw Tuntun/Resources/Audio/NarrationID

import AVFoundation
import Foundation

let targetSpeechDBFS = -15.0
let ceilingDBFS = -1.0
/// Where the soft limiter starts bending, as a fraction of the ceiling.
let limiterKnee = 0.7
/// Never amplify near-silence or noise by more than this.
let maximumGainDB = 24.0
/// Samples quieter than this do not count as speech when measuring level.
let speechGate = 0.01

func decibels(_ linear: Double) -> Double {
    20 * log10(max(linear, 1e-9))
}

func linear(_ decibels: Double) -> Double {
    pow(10, decibels / 20)
}

/// Speech level: RMS over samples above the gate, so pauses do not lower the measurement.
func speechRMS(_ samples: UnsafePointer<Float>, count: Int) -> Double {
    var sum = 0.0
    var voiced = 0

    for index in 0..<count {
        let value = Double(abs(samples[index]))
        if value > speechGate {
            sum += value * value
            voiced += 1
        }
    }

    return voiced > 0 ? sqrt(sum / Double(voiced)) : 0
}

/// Unchanged below the knee; above it, approaches the ceiling smoothly instead of clipping.
func softLimit(_ value: Double, ceiling: Double) -> Double {
    let knee = ceiling * limiterKnee
    let magnitude = abs(value)

    guard magnitude > knee else {
        return value
    }

    let limited = knee + (ceiling - knee) * tanh((magnitude - knee) / (ceiling - knee))
    return value < 0 ? -limited : limited
}

/// Silence kept around a spoken number after trimming, in seconds.
struct EdgePadding {
    let leading: Double
    let trailing: Double
}

/// Number takes are trimmed; other narration keeps its recorded edges.
///
/// Countdown takes have their own one-second clock, so only a short breath of space stays
/// on both sides. Marizka repetition takes play back to back in the count queue; about
/// 100 ms after the number keeps the last syllable's natural decay without the ~0.4 s of
/// trailing silence ElevenLabs adds. The older `narration-id-*` clips are left unchanged.
func edgePadding(forClipNamed name: String) -> EdgePadding? {
    if name.contains("-countdown-") {
        return EdgePadding(leading: 0.02, trailing: 0.02)
    }

    if name.hasPrefix("marizka-"), name.contains("-repetition-") {
        return EdgePadding(leading: 0.02, trailing: 0.10)
    }

    return nil
}

/// Removes edge silence, keeping `padding` around the spoken sound.
func trimEdges(_ buffer: AVAudioPCMBuffer, padding: EdgePadding) {
    let frames = Int(buffer.frameLength)
    let channels = Int(buffer.format.channelCount)
    guard let data = buffer.floatChannelData, frames > 0 else {
        return
    }

    let threshold: Float = 0.008
    let leadingFrames = Int(buffer.format.sampleRate * padding.leading)
    let trailingFrames = Int(buffer.format.sampleRate * padding.trailing)
    var first = frames
    var last = -1

    for index in 0..<frames {
        for channel in 0..<channels where abs(data[channel][index]) >= threshold {
            first = min(first, index)
            last = index
        }
    }

    guard last >= first else {
        return
    }

    let start = max(0, first - leadingFrames)
    let end = min(frames, last + trailingFrames + 1)
    for channel in 0..<channels {
        for index in 0..<(end - start) {
            data[channel][index] = data[channel][start + index]
        }
    }
    buffer.frameLength = AVAudioFrameCount(end - start)
}

func normalize(_ source: URL, into destination: URL) throws -> (before: Double, gain: Double, after: Double) {
    let input = try AVAudioFile(forReading: source)
    let format = input.processingFormat

    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(input.length)) else {
        throw CocoaError(.fileReadCorruptFile)
    }

    try input.read(into: buffer)

    let frames = Int(buffer.frameLength)
    let channels = Int(format.channelCount)
    guard let data = buffer.floatChannelData, frames > 0 else {
        throw CocoaError(.fileReadCorruptFile)
    }

    let before = decibels(speechRMS(data[0], count: frames))
    let gainDB = min(maximumGainDB, targetSpeechDBFS - before)
    let gain = linear(gainDB)
    let ceiling = linear(ceilingDBFS)

    for channel in 0..<channels {
        let samples = data[channel]
        for index in 0..<frames {
            samples[index] = Float(softLimit(Double(samples[index]) * gain, ceiling: ceiling))
        }
    }

    if let padding = edgePadding(forClipNamed: source.deletingPathExtension().lastPathComponent) {
        trimEdges(buffer, padding: padding)
    }

    let after = decibels(speechRMS(data[0], count: Int(buffer.frameLength)))

    // AVAudioFile pads AAC output with ~55 KB per file, so write lossless audio first and
    // let Apple's afconvert produce a tightly packed AAC file.
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("caf")
    defer { try? FileManager.default.removeItem(at: temporary) }

    guard let pcmFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: format.sampleRate,
        channels: format.channelCount,
        interleaved: false
    ) else {
        throw CocoaError(.fileReadCorruptFile)
    }

    do {
        let lossless = try AVAudioFile(
            forWriting: temporary,
            settings: pcmFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try lossless.write(from: buffer)
    }

    try? FileManager.default.removeItem(at: destination)
    try encodeAAC(temporary, to: destination)

    return (before, gainDB, after)
}

/// AAC at 96 kbps: transparent for a single speaking voice and small enough to bundle.
func encodeAAC(_ source: URL, to destination: URL) throws {
    let converter = Process()
    converter.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
    converter.arguments = ["-f", "m4af", "-d", "aac", "-b", "96000", source.path, destination.path]
    try converter.run()
    converter.waitUntilExit()

    guard converter.terminationStatus == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("Usage: swift Tools/normalize_narration.swift <source folder> <output folder>")
    exit(1)
}

let sourceFolder = URL(fileURLWithPath: arguments[1], isDirectory: true)
let outputFolder = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

let sources = try FileManager.default
    .contentsOfDirectory(at: sourceFolder, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "mp3" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

var results: [(before: Double, gain: Double, after: Double)] = []

for source in sources {
    let name = source.deletingPathExtension().lastPathComponent
    let destination = outputFolder.appendingPathComponent(name).appendingPathExtension("m4a")
    results.append(try normalize(source, into: destination))
}

func summary(_ values: [Double]) -> String {
    let sorted = values.sorted()
    return String(format: "%.1f to %.1f (median %.1f)", sorted.first ?? 0, sorted.last ?? 0, sorted[sorted.count / 2])
}

print("Normalized \(results.count) clips into \(outputFolder.path)")
if !results.isEmpty {
    print("speech level before: \(summary(results.map(\.before))) dBFS")
    print("gain applied:        \(summary(results.map(\.gain))) dB")
    print("speech level after:  \(summary(results.map(\.after))) dBFS")
}
