//
//  TherapyDetailPanel.swift
//  Tuntun
//
//  Created by dimaswisodewo on 23/11/2026.
//

import SwiftUI

/// A floating detail card over a lightly frosted backdrop, like a detail card in the iPad App
/// Store. The card scrolls inside when its content is taller than the screen. Tapping the
/// backdrop or the close circle calls `onClose`; the caller owns whether the panel is shown and
/// fades it in and out with its own transition. The card itself settles in with a short spring,
/// a plain fade under Reduce Motion.
struct TMDetailPanel<Content: View>: View {
    let closeTitle: LocalizedStringKey
    var maxWidth: CGFloat = 820
    let onClose: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    private static var cornerRadius: CGFloat {
        32
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backdrop

                card
                    .frame(maxWidth: maxWidth)
                    .frame(maxHeight: max(proxy.size.height - 64, 320))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
                    .scaleEffect(settled || reduceMotion ? 1 : 0.94)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.4, bounce: 0.18)) {
                settled = true
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - Sections

    private var backdrop: some View {
        TMFrostedBackdrop(dimming: 0.2)
            .contentShape(Rectangle())
            .onTapGesture(perform: onClose)
    }

    private var card: some View {
        ScrollView {
            content
                .padding(.horizontal, 36)
                .padding(.top, 40)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(
            TherapyPalette.surface,
            in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            TMTherapyIconButton(
                title: closeTitle,
                symbol: "xmark",
                size: 48,
                circle: true,
                quiet: true,
                action: onClose
            )
            .padding(12)
        }
        .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Detail panel") {
    ZStack {
        TherapyPalette.canvas
            .ignoresSafeArea()

        TMDetailPanel(closeTitle: "action.close", onClose: {}) {
            VStack(alignment: .leading, spacing: 16) {
                Text(verbatim: "Mengangkat lengan")
                    .typography(size: 40, weight: .bold, relativeTo: .largeTitle)

                ForEach(0..<20) { index in
                    Text(verbatim: "Row \(index)")
                        .typography(.body)
                }
            }
        }
    }
}
#endif
