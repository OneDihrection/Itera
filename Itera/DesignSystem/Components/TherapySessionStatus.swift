//
//  TherapySessionStatus.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 05/11/2026.
//

import SwiftUI

// MARK: - Completion mark

/// A large circle with a white check, for a finished set or session. Green by default; the
/// shared exercise screens pass `TherapyPalette.brand`.
struct TherapyCompletionMark: View {
    var size: CGFloat = 128
    var tint: Color = TherapyPalette.success

    var body: some View {
        Image(systemName: "checkmark")
            .typography(size: size * 0.42, weight: .bold)
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(tint, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Target tile

/// A grey tile with one large number and its unit, such as "3 Set" or "8x Repetisi".
struct TherapyTargetTile: View {
    let value: Int
    let unit: LocalizedStringKey
    /// A small mark after the number, such as "x".
    var suffix: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(value, format: .number)
                    .typography(size: 64, weight: .bold, relativeTo: .largeTitle)
                    .monospacedDigit()
                if let suffix {
                    Text(verbatim: suffix)
                        .typography(size: 32, weight: .bold, relativeTo: .title)
                }
            }
            Text(unit)
                .typography(size: 26, weight: .regular, relativeTo: .title3)
        }
        .foregroundStyle(TherapyPalette.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .leading)
        .background(TherapyPalette.panel, in: RoundedRectangle(cornerRadius: 30))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Numbered steps

/// An ordered list of short instructions with hanging numbers.
struct TherapyNumberedSteps: View {
    let steps: [LocalizedStringKey]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: "\(index + 1).")
                        .monospacedDigit()
                        .frame(minWidth: 26, alignment: .trailing)
                    Text(step)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .typography(size: 22, weight: .regular, relativeTo: .body)
                .lineSpacing(8)
            }
        }
        .foregroundStyle(TherapyPalette.ink)
    }
}

// MARK: - Set row

/// One set in a set checklist: done, next, or still to come.
struct TherapySetRow: View {
    enum State {
        case done, next, upcoming
    }

    let title: LocalizedStringKey
    var detail: LocalizedStringKey? = nil
    let state: State

    var body: some View {
        HStack(spacing: 16) {
            indicator
            Text(title)
                .typography(size: 22, weight: .medium, relativeTo: .headline)
            Spacer(minLength: 12)
            if let detail {
                Text(detail)
                    .typography(size: 18, weight: .medium, relativeTo: .subheadline)
            }
        }
        .foregroundStyle(state == .upcoming ? TherapyPalette.muted : TherapyPalette.ink)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(fill, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            if state == .next {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(TherapyPalette.ink, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var indicator: some View {
        if state == .done {
            Image(systemName: "checkmark.circle.fill")
                .typography(size: 26, weight: .regular)
                .foregroundStyle(TherapyPalette.setDone)
        } else {
            Image(systemName: "circle")
                .typography(size: 26, weight: .regular)
        }
    }

    private var fill: Color {
        switch state {
        case .done:
            return TherapyPalette.setDoneFill
        case .next:
            return TherapyPalette.canvas
        case .upcoming:
            return TherapyPalette.panel
        }
    }
}

// MARK: - Rest countdown

/// A large blue ring with the remaining whole seconds and a unit underneath.
struct TherapyRestCountdown: View {
    let remaining: Double
    let total: Double
    let unit: LocalizedStringKey
    var diameter: CGFloat = 230

    var body: some View {
        ZStack {
            TherapyProgressRing(
                progress: total > 0 ? remaining / total : 0,
                lineWidth: diameter * 0.09,
                animationDuration: 0.25,
                tint: TherapyPalette.restRing,
                track: TherapyPalette.restTrack,
                lineCap: .butt
            )
            VStack(spacing: -4) {
                Text(verbatim: String(Int(ceil(max(0, remaining)))))
                    .typography(size: diameter * 0.42, weight: .bold, relativeTo: .largeTitle)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(unit)
                    .typography(size: diameter * 0.1, weight: .regular, relativeTo: .title3)
            }
            .foregroundStyle(TherapyPalette.ink)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Repetition panel

/// "Repetisi" with a large "done/total" count and one dot per repetition in the current set.
struct TherapyRepetitionPanel: View {
    let title: LocalizedStringKey
    let unit: LocalizedStringKey
    let completed: Int
    let total: Int
    /// A shorter card, so a neighbouring illustration can be the larger panel.
    var compact = false

    private let dotColumns = [GridItem(.adaptive(minimum: 22, maximum: 26), spacing: 6)]

    var body: some View {
        let done = min(max(0, completed), max(0, total))

        VStack(alignment: .leading, spacing: compact ? 8 : 14) {
            Text(title)
                .typography(size: compact ? 22 : 26, weight: .medium, relativeTo: .title3)
                .accessibilityAddTraits(.isHeader)

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text(done, format: .number)
                        .typography(size: compact ? 56 : 88, weight: .bold, relativeTo: .largeTitle)
                    Text(verbatim: "/\(total)")
                        .typography(size: compact ? 34 : 52, weight: .bold, relativeTo: .largeTitle)
                }
                .monospacedDigit()
                .contentTransition(.numericText())
                Text(unit)
                    .typography(size: 22, weight: .regular, relativeTo: .body)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity)

            LazyVGrid(columns: dotColumns, spacing: 6) {
                ForEach(0..<max(0, total), id: \.self) { index in
                    Circle()
                        .strokeBorder(TherapyPalette.muted, lineWidth: index < done ? 0 : 1.5)
                        .background(Circle().fill(index < done ? TherapyPalette.success : .clear))
                        .frame(width: 20, height: 20)
                }
            }
            .accessibilityHidden(true)
        }
        .foregroundStyle(TherapyPalette.ink)
        .padding(compact ? 18 : 22)
        .frame(maxWidth: .infinity, maxHeight: compact ? nil : .infinity, alignment: .topLeading)
        .background(TherapyPalette.panel, in: RoundedRectangle(cornerRadius: compact ? 28 : 34))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Feedback pill

/// A short live cue drawn over the camera, such as "Bagus! Gerakan sudah sesuai".
struct TherapyFeedbackPill: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .typography(size: 26, weight: .medium, relativeTo: .title3)
            .foregroundStyle(TherapyPalette.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityAddTraits(.updatesFrequently)
    }
}
