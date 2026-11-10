//
//  TherapyTimeline.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 09/11/2026.
//

import SwiftUI

// MARK: - Marker

/// Where an item stands in a timeline. The caller decides what counts as done or next.
enum TherapyTimelineState: Equatable {
    case done
    case current
    case upcoming

    /// Spoken after the item's own label, so the state never relies on color alone.
    var accessibilityValue: LocalizedStringKey {
        switch self {
        case .done:
            return "plan.state.done"
        case .current:
            return "plan.state.next"
        case .upcoming:
            return "plan.state.upcoming"
        }
    }
}

/// A solid yellow dot for completed and current items, and a hollow ring for upcoming items.
struct TMTherapyTimelineMarker: View {
    let state: TherapyTimelineState
    var diameter: CGFloat = 32

    var body: some View {
        ZStack {
            switch state {
            case .current, .done:
                Circle()
                    .fill(TherapyPalette.planMarker)
            case .upcoming:
                Circle()
                    .fill(TherapyPalette.canvas)
                Circle()
                    .strokeBorder(TherapyPalette.planTrack, lineWidth: 3)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

// MARK: - Row

/// One timeline entry: a marker and its incoming and outgoing track segments.
///
/// Rows stack with no spacing of their own; the track spans the space between cards.
struct TMTherapyTimelineRow<Card: View>: View {
    let state: TherapyTimelineState
    var previousIsDone = false
    var isFirst = false
    var isLast = false
    var spacing: CGFloat = 32
    @ViewBuilder let card: Card

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            track
                .frame(width: 32)

            card
                .padding(.bottom, isLast ? 0 : spacing)
        }
    }

    /// Equal flexible segments above and below keep the marker centred on the card.
    private var track: some View {
        VStack(spacing: 0) {
            TMTherapyTimelineLine(completed: previousIsDone)
                .opacity(isFirst ? 0 : 1)

            TMTherapyTimelineMarker(state: state)

            TMTherapyTimelineLine(completed: state == .done)
                .opacity(isLast ? 0 : 1)

            if !isLast {
                TMTherapyTimelineLine(completed: state == .done)
                    .frame(height: spacing)
            }
        }
    }
}

/// A solid completed connector or a dashed upcoming connector.
private struct TMTherapyTimelineLine: View {
    let completed: Bool

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: geometry.size.width / 2, y: 0))
                path.addLine(to: CGPoint(x: geometry.size.width / 2, y: geometry.size.height))
            }
            .stroke(
                completed ? TherapyPalette.planMarker : TherapyPalette.planTrack,
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: completed ? [] : [6, 9])
            )
        }
        .frame(width: 4)
        .accessibilityHidden(true)
    }
}

// MARK: - Card

/// One value line under a plan card's title, such as "3 set" with its icon.
struct TherapyPlanDetail {
    let symbol: String
    let text: LocalizedStringKey
}

/// A warm card naming one exercise, its values and an illustration on the trailing side.
/// The whole card is one button and one accessibility element.
struct TMTherapyPlanCard: View {
    let title: LocalizedStringKey
    let details: [TherapyPlanDetail]
    let artwork: String
    var fallbackArtwork: String? = nil
    var state: TherapyTimelineState = .upcoming
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 24) {
                text

                Spacer(minLength: 0)

                if !typeSize.isAccessibilitySize {
                    TMTherapyArtwork(name: artwork, fallback: fallbackArtwork)
                        .frame(width: 110, height: 160)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TherapyPalette.planCard, in: RoundedRectangle(cornerRadius: 28))
            .contentShape(RoundedRectangle(cornerRadius: 28))
        }
        .buttonStyle(TMTherapySoundButtonStyle())
        .foregroundStyle(TherapyPalette.ink)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(state.accessibilityValue))
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .typography(size: 32, weight: .bold, relativeTo: .title2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(details.indices, id: \.self) { index in
                    detailLine(details[index])
                }
            }
        }
    }

    private func detailLine(_ detail: TherapyPlanDetail) -> some View {
        HStack(spacing: 14) {
            Image(systemName: detail.symbol)
                .frame(width: 30)
            Text(detail.text)
        }
        .typography(size: 24, weight: .regular, relativeTo: .body)
    }
}

// MARK: - Floating dock

/// Pins its content to the bottom of a scrolling page over a soft fade, so the page can scroll
/// beneath it. The fade never takes taps; only the content does.
struct TMTherapyFloatingActionDock<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        content
            .padding(.top, 72)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
            .background(alignment: .bottom) {
                fade
                    .allowsHitTesting(false)
            }
    }

    /// Clear at the top edge, fully covering behind the button.
    @ViewBuilder
    private var fade: some View {
        let mask = LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.55),
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        if reduceTransparency {
            TherapyPalette.canvas
                .mask(mask)
                .ignoresSafeArea(edges: .bottom)
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(mask)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}
