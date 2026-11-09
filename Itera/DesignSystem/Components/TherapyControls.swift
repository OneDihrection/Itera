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
    /// Backdrop behind the 3D exercise examples. Bright and fixed (the 3D view takes a static
    /// colour) so the figure stands out from it instead of matching a grey panel.
    static let exerciseBackdrop = Color(red: 0.95, green: 0.98, blue: 0.96)
    static let pastelInk = Color(red: 0.10, green: 0.16, blue: 0.18)
    static let lavender = peach
    static let rose = mint

    // MARK: - Monochrome page palette
    //
    // System semantic colors wherever one fits, so these follow dark mode and
    // Increase Contrast automatically, as the Human Interface Guidelines recommend.

    /// Plain page background of the redesigned home, session and progress pages.
    static let canvas = Color(uiColor: .systemBackground)
    /// High-contrast hero and program cards: black in light mode, a raised grey in dark mode.
    static let heroCard = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.secondarySystemBackground.resolvedColor(with: traits)
            : .black
    })
    static let onHero = Color.white
    /// Soft grey panels for media, targets and upcoming sets.
    static let panel = Color(uiColor: .secondarySystemBackground)
    /// Thin outline for white cards on the progress page.
    static let outline = Color(uiColor: .separator)
    /// Primary pill buttons, such as "Mulai Latihan" and "Lanjutkan Latihan".
    static let action = Color(uiColor: .label)
    static let onAction = Color(uiColor: .systemBackground)
    /// The alternative pill beside a primary action; its label uses `ink` for contrast.
    static let actionMuted = Color(uiColor: .systemGray5)
    /// Completion check for a finished session or set.
    static let success = Color(uiColor: .systemGreen)
    /// A completed set row. Darker than system teal so the check keeps 3:1 contrast.
    static let setDone = adaptive(light: (0.0, 0.47, 0.43), dark: (0.36, 0.80, 0.74))
    static let setDoneFill = adaptive(light: (0.89, 0.96, 0.95), dark: (0.10, 0.22, 0.21))
    /// Countdown ring shown while resting.
    static let restRing = Color(uiColor: .systemBlue)
    static let restTrack = Color(uiColor: .systemGray5)
    /// Mint green and peach for camera guidance bubbles, rings and arrows, matching the finger
    /// exercise identity (`secondary` and `tertiary`). Fixed rather than adaptive because they sit
    /// on live video under a dark underlay. Guidance never uses red. The names are historical.
    static let calmTeal = Color(red: 0.62, green: 0.90, blue: 0.76)
    static let calmBlue = Color(red: 0.99, green: 0.80, blue: 0.60)
    /// Dark edge drawn under every guidance shape so it keeps contrast on light and dark video.
    static let calmUnderlay = Color.black.opacity(0.5)
    /// Challenge card fill and its bold green ink (custom pair, contrast above 7:1).
    static let challengeFill = adaptive(light: (0.93, 0.96, 0.94), dark: (0.12, 0.18, 0.15))
    static let challengeInk = adaptive(light: (0.10, 0.27, 0.20), dark: (0.66, 0.86, 0.75))

    // MARK: - Daily plan palette

    /// Rust brand fill of the prominent "Mulai Latihan" capsule. White text on it is about 5.9:1.
    static let brand = Color(red: 0.71, green: 0.22, blue: 0.10)
    static let onBrand = Color.white
    /// Warm off-white card behind each exercise in the plan timeline.
    static let planCard = adaptive(light: (0.973, 0.957, 0.945), dark: (0.17, 0.155, 0.145))
    /// Filled timeline dot of the exercise that comes next. Fixed: it is a marker, not text.
    static let planMarker = Color(red: 1.0, green: 0.72, blue: 0.0)
    /// Dashed timeline line and the outline of upcoming dots.
    static let planTrack = Color(uiColor: .systemGray4)

    private static func adaptive(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
        })
    }

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
    /// The monochrome pill appearance: dark when primary, grey when `secondary`.
    var pill = false
    /// The large rust capsule that starts today's plan. It sizes to its label instead of
    /// filling the width, and ignores `pill` and `secondary`.
    var prominent = false
    let action: () -> Void

    var body: some View {
        if prominent {
            prominentButton
        } else {
            standardButton
        }
    }

    private var prominentButton: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .typography(size: 36, weight: .semiBold, relativeTo: .title)
            .frame(minHeight: 96)
            .padding(.horizontal, 48)
            .foregroundStyle(TherapyPalette.onBrand)
            .background(TherapyPalette.brand, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(TherapySoundButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    private var standardButton: some View {
        Button(role: destructive ? .destructive : nil, action: action) {
            HStack(spacing: 12) {
                if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
            }
            .typography(.headline)
            .frame(maxWidth: .infinity, minHeight: pill ? 60 : 68)
            .padding(.horizontal, 20)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: pill ? 30 : 22))
            .contentShape(RoundedRectangle(cornerRadius: pill ? 30 : 22))
        }
        .buttonStyle(TherapySoundButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    private var foreground: Color {
        if pill {
            if destructive {
                return .white
            }
            return secondary ? TherapyPalette.ink : TherapyPalette.onAction
        }
        return secondary ? TherapyPalette.ink : TherapyPalette.onAccent
    }

    private var background: Color {
        if destructive {
            return pill ? Color(uiColor: .systemRed) : TherapyPalette.warning
        }
        if pill {
            return secondary ? TherapyPalette.actionMuted : TherapyPalette.action
        }
        return secondary ? TherapyPalette.mint : TherapyPalette.green
    }
}

struct TherapyCard<Content: View>: View {
    var color: Color = TherapyPalette.surface
    /// Draws a thin border, for white cards on a white page.
    var outlined = false
    var padding: CGFloat = 28
    @ViewBuilder let content: Content

    var body: some View {
        content.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: 30))
            .overlay {
                if outlined {
                    RoundedRectangle(cornerRadius: 30)
                        .strokeBorder(TherapyPalette.outline, lineWidth: 1.5)
                }
            }
    }
}

struct TherapyMetric: View {
    let title: LocalizedStringKey
    let value: String
    var light = false
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).typography(.footnote).fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: compact ? 0 : 50, alignment: .bottomLeading)
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

/// A labeled number with decrease and increase controls.
///
/// The two controls are tap targets rather than `Button`s. Inside a `Form` row, SwiftUI treats
/// several buttons as one row-wide button and fires all of them for any tap, so a decrease and an
/// increase cancel each other or only the increase seems to work.
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
            stepControl(
                symbol: "minus",
                label: "action.decrease",
                isEnabled: value > range.lowerBound
            ) {
                value = max(range.lowerBound, value - step)
            }
            Text(verbatim: String(value)).typography(.title2).frame(minWidth: 55)
            stepControl(
                symbol: "plus",
                label: "action.increase",
                isEnabled: value < range.upperBound
            ) {
                value = min(range.upperBound, value + step)
            }
        }
        .foregroundStyle(TherapyPalette.ink)
        .background(showsBackground ? TherapyPalette.cream : .clear, in: RoundedRectangle(cornerRadius: 20))
    }

    private func stepControl(
        symbol: String,
        label: LocalizedStringKey,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        TherapyStepControl(
            symbol: symbol,
            label: Text(label) + Text(title),
            isEnabled: isEnabled,
            action: action
        )
    }
}

/// One decrease or increase target that works inside a list row.
private struct TherapyStepControl: View {
    let symbol: String
    let label: Text
    let isEnabled: Bool
    let action: () -> Void
    @Environment(\.buttonFeedback) private var feedback

    var body: some View {
        Image(systemName: symbol)
            .frame(width: 64, height: 64)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.3)
            .onTapGesture(perform: activate)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, activate)
    }

    private func activate() {
        guard isEnabled else {
            return
        }

        feedback()
        action()
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
    /// The page-level black circle used for back and close.
    var circle = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if circle {
                Image(systemName: symbol)
                    .typography(size: size * 0.4, weight: .semiBold)
                    .foregroundStyle(TherapyPalette.onHero)
                    .frame(width: size, height: size)
                    .background(TherapyPalette.heroCard, in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    // Keep at least a 64-point touch target around the small visual circle.
                    .frame(minWidth: 64, minHeight: 64)
                    .contentShape(Rectangle())
            } else {
                Image(systemName: symbol)
                    .typography(size: 36, weight: .bold)
                    .foregroundStyle(TherapyPalette.primary)
                    .frame(width: size, height: size)
                    .background(TherapyPalette.secondary, in: RoundedRectangle(cornerRadius: 26))
                    .contentShape(RoundedRectangle(cornerRadius: 26))
            }
        }
        .buttonStyle(TherapySoundButtonStyle())
        .accessibilityLabel(title)
    }
}

/// A quiet text action for secondary choices beneath primary buttons.
struct TherapyTextButton: View {
    let title: LocalizedStringKey
    var symbol: String? = nil
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
            }
            .typography(size: 18, weight: .semiBold, relativeTo: .subheadline)
            .foregroundStyle(TherapyPalette.muted)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(TherapySoundButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}
