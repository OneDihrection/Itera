//
//  TherapyDetailStats.swift
//  Tuntun
//
//  Created by dimaswisodewo on 23/11/2026.
//

import SwiftUI

/// One figure on a detail panel: a large value over a short caption, on a soft rounded tile.
/// With `lines` the caption leads, the value follows, and a thin rule sits above one or more
/// short explanatory lines. A line keeps any colour its caller gave it; the rest are muted.
struct TMDetailStatTile: View {
    let value: Text
    let caption: LocalizedStringKey
    var lines: [Text] = []
    var fill: Color = TherapyPalette.panel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !lines.isEmpty {
                Text(caption)
                    .typography(size: 20, weight: .regular, relativeTo: .body)
                    .foregroundStyle(TherapyPalette.ink)
            }

            value
                .typography(size: 26, weight: .bold, relativeTo: .title2)
                .foregroundStyle(TherapyPalette.ink)

            if lines.isEmpty {
                Text(caption)
                    .typography(size: 20, weight: .regular, relativeTo: .body)
                    .foregroundStyle(TherapyPalette.ink)
            } else {
                Divider()

                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    line
                        .typography(size: 18, weight: .regular, relativeTo: .subheadline)
                        .foregroundStyle(TherapyPalette.muted)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A thin dashed rule between the sections of a detail panel.
struct TMDashedDivider: View {
    var body: some View {
        Line()
            .stroke(
                TherapyPalette.outline,
                style: StrokeStyle(lineWidth: 1, dash: [6, 4])
            )
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

/// Two labelled values, each behind a coloured dot, with the change between them on a pill:
/// "● First session 84°  ● Now 112°  [+28°]". The dots repeat the colours of the picture they
/// describe; the words carry the meaning, so colour is never the only cue.
struct TMComparisonLegend: View {
    let baselineTitle: Text
    let baselineValue: Text
    var baselineColor: Color = TherapyPalette.guidanceBlue.opacity(0.45)
    let currentTitle: Text
    let currentValue: Text
    var currentColor: Color = TherapyPalette.brand
    /// The change, already signed and formatted; nil hides the pill.
    var change: Text? = nil
    var changeFill: Color = TherapyPalette.green

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                row(color: baselineColor, title: baselineTitle, value: baselineValue)
                row(color: currentColor, title: currentTitle, value: currentValue)
            }

            Spacer(minLength: 8)

            if let change {
                change
                    .typography(size: 20, weight: .bold, relativeTo: .body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(changeFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(TherapyPalette.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func row(color: Color, title: Text, value: Text) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)

            title + Text(verbatim: "  ") + value.bold()
        }
        .typography(size: 20, weight: .medium, relativeTo: .body)
        .foregroundStyle(TherapyPalette.ink)
    }
}

/// A pale blue call-out with a one-line heading over its own content, used to point at one
/// moment of a session ("Your movement was a little different in repetition 5").
struct TMHighlightCallout<Content: View>: View {
    let heading: Text
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading
                .typography(size: 20, weight: .semiBold, relativeTo: .headline)
                .foregroundStyle(TherapyPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            TherapyPalette.historyCard,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }
}

/// One short observation: a small coloured bullet beside a sentence, with an optional muted
/// line beneath. The tone colours only the bullet; the sentence carries the meaning.
struct TMInsightRow: View {
    enum Tone {
        /// Something improved.
        case positive
        /// A neutral fact.
        case neutral
        /// Worth a gentle look; never alarming, so it is yellow rather than red.
        case attention
    }

    let text: Text
    var detail: Text? = nil
    var tone: Tone = .neutral

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    // Centres the bullet on the first line's x-height.
                    dimensions[VerticalAlignment.center] + 4
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                text
                    .typography(size: 19, weight: .medium, relativeTo: .body)
                    .foregroundStyle(TherapyPalette.ink)

                if let detail {
                    detail
                        .typography(size: 17, weight: .regular, relativeTo: .subheadline)
                        .foregroundStyle(TherapyPalette.muted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch tone {
        case .positive:
            return TherapyPalette.green
        case .neutral:
            return TherapyPalette.muted
        case .attention:
            return TherapyPalette.brandPressed
        }
    }
}

/// A row of capsule chips choosing one value, for a short choice inside a panel (for example
/// First / Hardest / Last). The chosen chip is brand yellow with dark text.
struct TMChoiceChips<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: LocalizedStringKey
    }

    let options: [Option]
    @Binding var selection: Value

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            ForEach(options, id: \.value) { option in
                chip(option)
            }
        }
    }

    private func chip(_ option: Option) -> some View {
        let selected = option.value == selection

        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                selection = option.value
            }
        } label: {
            Text(option.title)
                .typography(size: 18, weight: selected ? .semiBold : .medium, relativeTo: .body)
                .foregroundStyle(selected ? TherapyPalette.onBrand : TherapyPalette.ink)
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .background(
                    selected ? TherapyPalette.brand : TherapyPalette.panel,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(TMTherapySoundButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A soft grey card holding a short list of `TMInsightRow`s.
struct TMInsightCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TherapyPalette.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Detail stats") {
    VStack(alignment: .leading, spacing: 20) {
        HStack(spacing: 16) {
            TMDetailStatTile(value: Text(verbatim: "112°"), caption: "exerciseDetail.stat.peakAngle")
            TMDetailStatTile(value: Text(verbatim: "12,5 detik"), caption: "exerciseDetail.stat.averageDuration")
            TMDetailStatTile(value: Text(verbatim: "1 mnt 40 dtk"), caption: "exerciseDetail.stat.activeTime")
        }
        .fixedSize(horizontal: false, vertical: true)

        TMDashedDivider()

        TMComparisonLegend(
            baselineTitle: Text(verbatim: "Sesi pertama"),
            baselineValue: Text(verbatim: "84°"),
            currentTitle: Text(verbatim: "Saat ini"),
            currentValue: Text(verbatim: "112°"),
            change: Text(verbatim: "+28°")
        )

        TMChoiceChips(
            options: [
                .init(value: 0, title: "history.role.first"),
                .init(value: 1, title: "history.role.hardest"),
                .init(value: 2, title: "history.role.last"),
            ],
            selection: .constant(1)
        )

        TMInsightCard {
            TMInsightRow(text: Text(verbatim: "Tempomu 2,1 detik lebih cepat per repetisi"))
            TMInsightRow(
                text: Text(verbatim: "Repetisi terakhir 8° lebih rendah, wajar jika mulai lelah"),
                tone: .attention
            )
            TMInsightRow(
                text: Text(verbatim: "10 repetisi hari ini, 4 lebih banyak"),
                detail: Text(verbatim: "5 sesi latihan sejak sesi pertama"),
                tone: .positive
            )
        }

        TMHighlightCallout(heading: Text(verbatim: "Di gerakan ke-5, gerakanmu sedikit berbeda. Yuk kita lihat!")) {
            HStack(spacing: 16) {
                TMDetailStatTile(
                    value: Text(verbatim: "27,3 detik"),
                    caption: "exerciseDetail.callout.duration",
                    lines: [Text(verbatim: "Lebih lama dari biasanya (rata-rata 12,5 detik)")],
                    fill: TherapyPalette.surface
                )
                TMDetailStatTile(
                    value: Text(verbatim: "≈ 93°"),
                    caption: "exerciseDetail.callout.change",
                    lines: [
                        Text(verbatim: "19° lebih rendah dari sesi pertama").foregroundStyle(TherapyPalette.warning),
                        Text(verbatim: "Terbaikmu hari ini: 112°"),
                    ],
                    fill: TherapyPalette.surface
                )
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
    .padding(32)
}
#endif
