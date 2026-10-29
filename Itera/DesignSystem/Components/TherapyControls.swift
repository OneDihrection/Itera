//
//  TherapyControls.swift
//  Itera
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

enum TherapyPalette {
    static let cameraBackground = Color(red: 0.08, green: 0.14, blue: 0.13)
    static let ink = Color.primary
    static let muted = Color.secondary
    static let green = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.61, green: 0.85, blue: 0.75, alpha: 1)
            : UIColor(red: 0.08, green: 0.38, blue: 0.31, alpha: 1)
    })
    static let onAccent = Color(uiColor: .systemBackground)
    static let cream = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let subtleSurface = Color(uiColor: .tertiarySystemGroupedBackground)
    static let mint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.14, green: 0.24, blue: 0.20, alpha: 1)
            : UIColor(red: 0.85, green: 0.93, blue: 0.87, alpha: 1)
    })
    static let peach = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.28, green: 0.19, blue: 0.13, alpha: 1)
            : UIColor(red: 0.98, green: 0.88, blue: 0.77, alpha: 1)
    })
    static let warning = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.72, blue: 0.51, alpha: 1)
            : UIColor(red: 0.55, green: 0.22, blue: 0.12, alpha: 1)
    })
    static let primary = green
    static let secondary = mint
    static let tertiary = peach
    static let mediaBackground = Color(red: 0.743, green: 0.775, blue: 0.757)
    static let hero = Color(red: 0.85, green: 0.93, blue: 0.87)
    static let pastelInk = Color(red: 0.10, green: 0.16, blue: 0.18)
    static let lavender = peach
    static let rose = mint

    static func illustrationBackground(at index: Int) -> Color {
        switch index {
        case 0: return hero
        case 1: return tertiary
        case 2: return secondary
        case 3: return tertiary
        default: return secondary
        }
    }
}

struct TherapyButton: View {
    let title: LocalizedStringKey
    var symbol: String? = nil
    var secondary = false
    var destructive = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(role: destructive ? .destructive : nil, action: action) {
            HStack(spacing: 12) {
                if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
            }
            .typography(.headline)
            .frame(maxWidth: .infinity, minHeight: 68)
            .padding(.horizontal, 20)
            .foregroundStyle(secondary ? TherapyPalette.ink : TherapyPalette.onAccent)
            .background(background, in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(TherapySoundButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    private var background: Color {
        if destructive {
            return TherapyPalette.warning
        }
        return secondary ? TherapyPalette.mint : TherapyPalette.green
    }
}

struct TherapyCard<Content: View>: View {
    var color: Color = TherapyPalette.surface
    @ViewBuilder let content: Content

    var body: some View {
        content.padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: 30))
    }
}

struct TherapyMetric: View {
    let title: LocalizedStringKey
    let value: String
    var light = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).typography(.footnote).fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 50, alignment: .bottomLeading)
                .foregroundStyle(light ? TherapyPalette.onAccent.opacity(0.8) : TherapyPalette.muted)
            Text(verbatim: value).typography(size: 36, weight: .bold)
                .foregroundStyle(light ? TherapyPalette.onAccent : TherapyPalette.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct TherapyStatus: View {
    let title: LocalizedStringKey
    let symbol: String
    var color: Color = TherapyPalette.green

    var body: some View {
        Label(title, systemImage: symbol)
            .typography(.footnote)
            .foregroundStyle(color)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(color.opacity(0.08), in: Capsule())
    }
}

struct TherapyNumberControl: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var showsBackground = true

    var body: some View {
        HStack {
            Text(title).typography(.body)
            Spacer()
            Button { value = max(range.lowerBound, value - step) } label: {
                Image(systemName: "minus").frame(width: 64, height: 64)
            }
            .accessibilityLabel(Text("action.decrease") + Text(title))
            .disabled(value <= range.lowerBound)
            Text(verbatim: String(value)).typography(.title2).frame(minWidth: 55)
            Button { value = min(range.upperBound, value + step) } label: {
                Image(systemName: "plus").frame(width: 64, height: 64)
            }
            .accessibilityLabel(Text("action.increase") + Text(title))
            .disabled(value >= range.upperBound)
        }
        .foregroundStyle(TherapyPalette.ink)
        .background(showsBackground ? TherapyPalette.cream : .clear, in: RoundedRectangle(cornerRadius: 20))
        .buttonStyle(TherapySoundButtonStyle())
    }
}

struct TherapyError: View {
    let key: String
    var body: some View {
        Label(LocalizedStringKey(key), systemImage: "exclamationmark.circle.fill")
            .typography(.body)
            .foregroundStyle(TherapyPalette.warning)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TherapyPalette.peach, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

struct TherapyIconButton: View {
    let title: LocalizedStringKey
    let symbol: String
    var size: CGFloat = 88
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .typography(size: 36, weight: .bold)
                .foregroundStyle(TherapyPalette.primary)
                .frame(width: size, height: size)
                .background(TherapyPalette.secondary, in: RoundedRectangle(cornerRadius: 26))
                .contentShape(RoundedRectangle(cornerRadius: 26))
        }
        .buttonStyle(TherapySoundButtonStyle())
        .accessibilityLabel(title)
    }
}
