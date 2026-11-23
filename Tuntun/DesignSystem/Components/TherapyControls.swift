//
//  TherapyControls.swift
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 29/10/2026.
//

import SwiftUI

enum TherapyPalette {
    // MARK: - Foundation colors
    //
    // Raw values from the Figma "Foundation Colors" page (2026-11-20). Semantic tokens below map
    // onto these; feature code uses the semantic tokens only.

    private static let yellowBackground = rgb(0xFFFAEC)
    private static let yellowNormal = rgb(0xFFB700)
    private static let yellowPressed = rgb(0xE28C00)
    private static let secondaryBlue = rgb(0x58A7F8)
    private static let errorNormal = rgb(0xC5423D)
    private static let successNormal = rgb(0x40895D)
    private static let successPressed = rgb(0x2A6342)
    private static let neutralBackground = rgb(0xF9F9F9)
    private static let mainDark = rgb(0x1A1A1A)
    private static let disabledFill = rgb(0xD9D7D5)

    // MARK: - Semantic tokens

    static let cameraBackground = Color(red: 0.08, green: 0.14, blue: 0.13)
    static let ink = Color.primary
    static let muted = Color.secondary
    /// Green text, tints and fills under white text. Uses Success/Pressed so white keeps about 7:1.
    static let green = adaptive(light: successPressed, dark: (0.61, 0.85, 0.75))
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
    /// Destructive pill fill under white text: Error/Normal in both appearances, about 5:1.
    static let destructive = fixed(errorNormal)
    /// Error/Normal. About 5:1 on white, so it serves as text and as a fill under white text.
    static let warning = adaptive(light: errorNormal, dark: (1, 0.72, 0.51))
    /// Marks debug-only UI (`.debugOnly()`). Fixed orange so it never blends into the app's palette.
    static let debugAccent = Color(uiColor: .systemOrange)
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
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.systemBackground.resolvedColor(with: traits)
            : uiColor(neutralBackground)
    })
    /// White page surface behind the neutral Progress calendar and history cards.
    static let progressCanvas = Color(uiColor: .systemBackground)
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
    static let action = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.label.resolvedColor(with: traits)
            : uiColor(mainDark)
    })
    static let onAction = Color(uiColor: .systemBackground)
    /// The alternative pill beside a primary action; its label uses `ink` for contrast.
    static let actionMuted = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.systemGray5.resolvedColor(with: traits)
            : uiColor(disabledFill)
    })
    /// Completion check for a finished session or set.
    static let success = adaptive(light: successNormal, dark: (0.36, 0.80, 0.50))
    /// A completed set row: Success/Normal, so the check keeps 3:1 contrast on its fill.
    static let setDone = adaptive(light: successNormal, dark: (0.36, 0.80, 0.74))
    static let setDoneFill = adaptive(light: (0.89, 0.96, 0.95), dark: (0.10, 0.22, 0.21))
    /// Countdown ring shown while resting.
    static let restRing = fixed(secondaryBlue)
    static let restTrack = Color(uiColor: .systemGray5)
    /// Fixed guidance colors for rings and landmarks over live video.
    static let guidanceBlue = fixed(secondaryBlue)
    static let guidanceYellow = fixed(yellowNormal)
    /// Finger-exercise rings and connectors: the plan's bright orange, readable on live video.
    static let guidanceOrange = Color(red: 0.96, green: 0.44, blue: 0.09)
    /// Dark edge drawn under every guidance shape so it keeps contrast on light and dark video.
    static let calmUnderlay = Color.black.opacity(0.5)
    /// Challenge card fill and its bold green ink (custom pair, contrast above 7:1).
    static let challengeFill = adaptive(light: (0.93, 0.96, 0.94), dark: (0.12, 0.18, 0.15))
    static let challengeInk = adaptive(light: (0.10, 0.27, 0.20), dark: (0.66, 0.86, 0.75))

    // MARK: - Daily plan palette

    /// Warm panel behind progress tiles and the movement report: Primary Yellow/BG.
    static let progressPanel = adaptive(light: yellowBackground, dark: (0.21, 0.16, 0.12))
    static let progressBar = fixed(yellowNormal)
    /// Lighter bars beside an emphasized `progressBar`: Primary Yellow/Normal halfway to its BG.
    static let progressSoftBar = Color(red: 1, green: 0.85, blue: 0.46)
    /// Primary Yellow fill of the prominent "Mulai Latihan" capsule, pills, rings and icons.
    /// Too light for text on white (about 1.8:1): text uses `brandInk`, and labels on it `onBrand`.
    static let brand = fixed(yellowNormal)
    /// Primary Yellow/Pressed, the deeper band of the long-rest waves.
    static let brandPressed = fixed(yellowPressed)
    /// Main Dark label on a `brand` fill, about 10.5:1.
    static let onBrand = fixed(mainDark)
    /// Text that the design shows in the brand color, such as target numbers and "Kembali".
    static let brandInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.label.resolvedColor(with: traits)
            : uiColor(mainDark)
    })
    /// Warm off-white card behind each exercise in the plan timeline: Primary Yellow/BG.
    static let planCard = adaptive(light: yellowBackground, dark: (0.17, 0.155, 0.145))
    /// Filled timeline dot and completed connector. Fixed: it is a marker, not text.
    static let planMarker = brand
    /// Dashed timeline line and the outline of upcoming dots.
    static let planTrack = Color(uiColor: .systemGray4)
    /// Slightly deeper warm grey behind demo media and the set results panel.
    static let planPanel = adaptive(light: (0.937, 0.918, 0.894), dark: (0.20, 0.185, 0.17))
    /// Secondary text in Beranda's date and plan states.
    static let planMutedInk = fixed(rgb(0x797877))
    /// Step numbers inside Beranda's timeline markers.
    static let planStepInk = fixed(rgb(0x6C6363))
    /// Divider between Beranda's daily-plan rows.
    static let planDivider = fixed(rgb(0xB3AEAE))
    /// Illustration tile for a locked daily-plan row.
    static let planDisabledTile = fixed(rgb(0xF1F0F0))
    /// Illustration tile for an available daily-plan row.
    static let planAvailableTile = fixed(rgb(0xFFF8E6))

    // MARK: - Progress palette

    /// Secondary Blue ribbon behind the progress badge's number. Fixed: it is an illustration.
    static let badgeRibbon = fixed(secondaryBlue)
    /// Lighter inner fold of the badge ribbon.
    static let badgeRibbonLight = Color(red: 0.62, green: 0.80, blue: 0.99)
    /// Pale blue behind each exercise on a day's progress page (`TMHistoryCard`).
    static let historyCard = adaptive(light: (0.937, 0.961, 0.996), dark: (0.11, 0.15, 0.21))
    /// The calm slate line and joint ring of the detail panel's figure (#5B7A99, lighter in dark).
    static let figureLine = adaptive(light: (0.357, 0.478, 0.6), dark: (0.616, 0.706, 0.8))

    private static func adaptive(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return uiColor(value)
        })
    }

    private static func fixed(_ value: (Double, Double, Double)) -> Color {
        Color(red: value.0, green: value.1, blue: value.2)
    }

    private static func uiColor(_ value: (Double, Double, Double)) -> UIColor {
        UIColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
    }

    /// Splits a 0xRRGGBB design value into sRGB components.
    private static func rgb(_ hex: UInt32) -> (Double, Double, Double) {
        (
            Double((hex >> 16) & 0xFF) / 255,
            Double((hex >> 8) & 0xFF) / 255,
            Double(hex & 0xFF) / 255
        )
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

struct TMTherapyButton: View {
    let title: LocalizedStringKey
    var symbol: String? = nil
    var secondary = false
    var destructive = false
    var disabled = false
    /// The monochrome pill appearance: dark when primary, grey when `secondary`.
    var pill = false
    /// The large yellow brand capsule that starts today's plan. It sizes to its label instead of
    /// filling the width, and ignores `pill` and `secondary`.
    var prominent = false
    /// With `pill`, fills the pill with the yellow brand color instead of the dark action color.
    var brand = false
    /// No fill: the icon and title alone in `tint` (muted by default), for Pause beside End and
    /// the quiet actions on rest pages. Ignores `pill`, `secondary` and `brand`.
    var plain = false
    /// Underlines the title, as the rest pages' plain actions do.
    var underlined = false
    /// The plain label's colour, such as `onBrand` over the long rest's yellow waves.
    var tint: Color? = nil
    var extraVerticalPadding: CGFloat = 0
    let action: () -> Void

    var body: some View {
        if prominent {
            prominentButton
        } else if plain {
            plainButton
        } else {
            standardButton
        }
    }

    private var plainButton: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
                    .underline(underlined)
            }
            .typography(.headline)
            .foregroundStyle(tint ?? TherapyPalette.muted)
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(.horizontal, 20)
            .padding(.vertical, extraVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(TMTherapySoundButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
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
        .buttonStyle(TMTherapySoundButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    private var standardButton: some View {
        let outline = RoundedRectangle(cornerRadius: pill ? 30 + extraVerticalPadding : 22)

        return Button(role: destructive ? .destructive : nil, action: action) {
            HStack(spacing: 12) {
                if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
            }
            .typography(.headline)
            .frame(maxWidth: .infinity, minHeight: pill ? 60 : 68)
            .padding(.horizontal, 20)
            .padding(.vertical, extraVerticalPadding)
            .foregroundStyle(foreground)
            .background(background, in: outline)
            .contentShape(outline)
        }
        .buttonStyle(TMTherapySoundButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    private var foreground: Color {
        if pill {
            if destructive {
                return .white
            }
            if brand {
                return TherapyPalette.onBrand
            }
            return secondary ? TherapyPalette.ink : TherapyPalette.onAction
        }
        return secondary ? TherapyPalette.ink : TherapyPalette.onAccent
    }

    private var background: Color {
        if destructive {
            return pill ? TherapyPalette.destructive : TherapyPalette.warning
        }
        if pill {
            if brand {
                return TherapyPalette.brand
            }
            return secondary ? TherapyPalette.actionMuted : TherapyPalette.action
        }
        return secondary ? TherapyPalette.mint : TherapyPalette.green
    }
}

struct TMTherapyCard<Content: View>: View {
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

struct TMTherapyMetric: View {
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

struct TMTherapyStatus: View {
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
struct TMTherapyNumberControl: View {
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
        TMTherapyStepControl(
            symbol: symbol,
            label: Text(label) + Text(title),
            isEnabled: isEnabled,
            action: action
        )
    }
}

/// One decrease or increase target that works inside a list row.
private struct TMTherapyStepControl: View {
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

struct TMTherapyError: View {
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

struct TMTherapyIconButton: View {
    let title: LocalizedStringKey
    let symbol: String
    var size: CGFloat = 88
    /// The page-level black circle used for back and close.
    var circle = false
    /// With `circle`, a light grey circle with a dark glyph, for closing a floating panel.
    var quiet = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if circle {
                Image(systemName: symbol)
                    .typography(size: size * 0.4, weight: .semiBold)
                    .foregroundStyle(quiet ? TherapyPalette.ink : TherapyPalette.onHero)
                    .frame(width: size, height: size)
                    .background(quiet ? TherapyPalette.panel : TherapyPalette.heroCard, in: Circle())
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
        .buttonStyle(TMTherapySoundButtonStyle())
        .accessibilityLabel(title)
    }
}

/// A quiet text action for secondary choices beneath primary buttons.
struct TMTherapyTextButton: View {
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
        .buttonStyle(TMTherapySoundButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}
