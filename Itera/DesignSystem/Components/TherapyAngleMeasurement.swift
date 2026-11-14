//
//  TherapyAngleMeasurement.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 11/11/2026.
//

import SwiftUI

// MARK: - Readout

/// A large degree value with a hold ring that fills while the joint is held still.
/// Shows a dash when there is no value. Displays supplied values only.
struct TMTherapyAngleReadout: View {
    let title: LocalizedStringKey
    let degrees: Double?
    /// 0 to 1: how far the current stillness is toward a held reading.
    var holdProgress = 0.0
    var caption: LocalizedStringKey? = nil

    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                TMTherapyProgressRing(
                    progress: holdProgress,
                    lineWidth: 10,
                    tint: TherapyPalette.guidanceBlue
                )

                Text(verbatim: TMTherapyAngleText.format(degrees))
                    .typography(size: 44, weight: .bold, relativeTo: .largeTitle)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(14)
            }
            .frame(width: 150, height: 150)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .typography(.headline)

                if let caption {
                    Text(caption)
                        .typography(.footnote)
                        .foregroundStyle(TherapyPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

enum TMTherapyAngleText {
    /// Whole degrees: camera estimates are not more precise than that.
    static func format(_ degrees: Double?) -> String {
        guard let degrees, degrees.isFinite else {
            return "–"
        }

        return "\(Int(degrees.rounded()))°"
    }
}

// MARK: - Camera overlay

/// Draws the measured bones as a line through supplied joint points over an aspect-fit camera
/// preview, with the reading beside the vertex. Points are unmirrored normalized image
/// coordinates (origin bottom-left); `mirrored` matches a mirrored front-camera preview.
struct TMTherapyAngleOverlay: View {
    let points: [CGPoint]
    let aspect: Double
    var mirrored = true
    var label: String? = nil

    var body: some View {
        GeometryReader { proxy in
            let geometry = CameraDisplayGeometry(aspect: aspect, viewport: proxy.size)
            let screen = points.map { geometry.point($0, mirrored: mirrored) }

            ZStack {
                bones(screen)
                    .stroke(TherapyPalette.calmUnderlay, style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                bones(screen)
                    .stroke(TherapyPalette.guidanceYellow, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))

                ForEach(screen.indices, id: \.self) { index in
                    Circle()
                        .fill(TherapyPalette.guidanceBlue)
                        .overlay(Circle().strokeBorder(TherapyPalette.calmUnderlay, lineWidth: 4))
                        .frame(width: 26, height: 26)
                        .position(screen[index])
                }

                if let label, let vertex = vertex(screen) {
                    Text(verbatim: label)
                        .typography(size: 28, weight: .bold, relativeTo: .title2)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(TherapyPalette.calmUnderlay, in: Capsule())
                        .position(x: vertex.x, y: vertex.y - 44)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func bones(_ screen: [CGPoint]) -> Path {
        Path { path in
            guard let first = screen.first else {
                return
            }

            path.move(to: first)
            screen.dropFirst().forEach { path.addLine(to: $0) }
        }
    }

    /// The middle point of a three-joint angle; for longer lines, the midpoint of the middle bone.
    private func vertex(_ screen: [CGPoint]) -> CGPoint? {
        guard screen.count >= 3 else {
            return nil
        }

        guard screen.count.isMultiple(of: 2) else {
            return screen[screen.count / 2]
        }

        let a = screen[screen.count / 2 - 1]
        let b = screen[screen.count / 2]

        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

// MARK: - Report

/// One labelled value line in an angle report card.
struct TherapyAngleLine: Identifiable {
    let id: Int
    let label: LocalizedStringKey
    let value: Text
    var emphasized = false
}

/// A report card for one measured angle: its name, a source badge, then labelled lines such as
/// before and after practice. Displays supplied text only.
struct TMTherapyAngleReportCard: View {
    let title: LocalizedStringKey
    let badge: LocalizedStringKey
    let lines: [TherapyAngleLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "angle")
                    .accessibilityHidden(true)
                Text(title)
                    .typography(size: 20, weight: .semiBold, relativeTo: .headline)
                Spacer(minLength: 8)
                Text(badge)
                    .typography(.footnote)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(TherapyPalette.panel, in: Capsule())
            }

            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(line.label)
                        .typography(.subheadline)
                        .foregroundStyle(TherapyPalette.muted)
                        .frame(minWidth: 180, alignment: .leading)
                    line.value
                        .typography(size: 20, weight: line.emphasized ? .semiBold : .regular, relativeTo: .subheadline)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(TherapyPalette.outline, lineWidth: 1.5)
        }
        .accessibilityElement(children: .contain)
    }
}
