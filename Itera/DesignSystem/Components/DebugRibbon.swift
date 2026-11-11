//
//  DebugRibbon.swift
//  Itera
//
//  Created by dimaswisodewo on 12/11/2026.
//

#if DEBUG
import SwiftUI

// Debug-only UI must be obviously so: wrap the control in `#if DEBUG` and mark it with
// `.debugOnly()`, which draws a dashed orange outline and a "DEBUG" corner ribbon.

// MARK: - Ribbon

/// A diagonal "DEBUG" band for the top-trailing corner of a debug-only control.
struct TMDebugRibbon: View {
    private static var bandSize: CGSize { CGSize(width: 72, height: 14) }

    /// Distance of the band's centre from the corner along each axis.
    private static var cornerInset: CGFloat { 16 }

    var body: some View {
        Text(verbatim: "DEBUG")
            .typography(size: 9, weight: .extraBold, relativeTo: .caption2)
            .foregroundStyle(.white)
            .frame(width: Self.bandSize.width, height: Self.bandSize.height)
            .background(TherapyPalette.debugAccent)
            .rotationEffect(.degrees(45))
            // Top-trailing alignment puts the band's centre at (-width / 2, height / 2) from
            // the corner; move it onto the diagonal.
            .offset(
                x: Self.bandSize.width / 2 - Self.cornerInset,
                y: Self.cornerInset - Self.bandSize.height / 2
            )
    }
}

// MARK: - Modifier

private struct TMDebugOnlyModifier: ViewModifier {
    private static var cornerRadius: CGFloat { 10 }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)

        content
            // Room for the ribbon so it never covers the control's own label.
            .padding(.trailing, 20)
            .padding(.vertical, 4)
            .overlay {
                decoration(shape)
            }
            .accessibilityHint(Text(verbatim: "Debug only"))
    }

    private func decoration(_ shape: RoundedRectangle) -> some View {
        ZStack(alignment: .topTrailing) {
            shape
                .strokeBorder(
                    TherapyPalette.debugAccent,
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )

            TMDebugRibbon()
        }
        .clipShape(shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Debug action

/// A quiet text action marked as debug-only, for developer shortcuts such as finishing an exercise.
struct TMDebugActionButton: View {
    let title: LocalizedStringKey
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        TMTherapyTextButton(title: title, symbol: symbol, action: action)
            .debugOnly()
    }
}

extension View {
    /// Marks a debug-build control with a dashed orange outline and a "DEBUG" corner ribbon.
    /// Use only inside `#if DEBUG`; the modifier itself does not exist in Release builds.
    func debugOnly() -> some View {
        modifier(TMDebugOnlyModifier())
    }
}
#endif
