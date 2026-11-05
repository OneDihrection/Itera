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
//     swift Tools/normalize_narration.swift Tools/NarrationRaw Itera/Resources/Audio/NarrationID

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

    let after = decibels(speechRMS(data[0], count: frames))

    // AVAudioFile pads AAC output with ~55 KB per file, so write lossless audio first and
    // let Apple's afconvert produce a tightly packed AAC file.
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("caf")
    defer { try? FileManager.default.removeItem(at: temporary) }

    do {
        let lossless = try AVAudioFile(
            forWriting: temporary,
            settings: format.settings,
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
