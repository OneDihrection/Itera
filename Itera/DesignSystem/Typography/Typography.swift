//
//  Typography.swift
//  Itera
//
//  Created by dimaswisodewo on 28/10/2026.
//

import SwiftUI

// MARK: - Poppins Font Weights

/// Available font weights for the Poppins font family.
public enum AppFontWeight: String, CaseIterable, Sendable {
    case thin = "Thin"
    case extraLight = "ExtraLight"
    case light = "Light"
    case regular = "Regular"
    case medium = "Medium"
    case semiBold = "SemiBold"
    case bold = "Bold"
    case extraBold = "ExtraBold"
    case black = "Black"

    /// Resolves the PostScript font name for this weight, accounting for italics.
    public nonisolated func postScriptName(isItalic: Bool = false) -> String {
        switch (self, isItalic) {
        case (.regular, true):
            return "Poppins-Italic"
        case (.regular, false):
            return "Poppins-Regular"
        case (let weight, true):
            return "Poppins-\(weight.rawValue)Italic"
        case (let weight, false):
            return "Poppins-\(weight.rawValue)"
        }
    }

    /// Converts SwiftUI's `Font.Weight` to the nearest `AppFontWeight`.
    public init(fontWeight: Font.Weight) {
        switch fontWeight {
        case .ultraLight:
            self = .extraLight
        case .thin:
            self = .thin
        case .light:
            self = .light
        case .regular:
            self = .regular
        case .medium:
            self = .medium
        case .semibold:
            self = .semiBold
        case .bold:
            self = .bold
        case .heavy:
            self = .extraBold
        case .black:
            self = .black
        default:
            self = .regular
        }
    }
}

// MARK: - App Typography Styles

/// Semantic typography styles scaled for Dynamic Type accessibility.
public enum AppTypography: Equatable, Sendable {
    case largeTitle
    case title
    case title2
    case title3
    case headline
    case body
    case callout
    case subheadline
    case footnote
    case caption
    case caption2
    case custom(size: CGFloat, weight: AppFontWeight = .regular, isItalic: Bool = false, relativeTo: Font.TextStyle = .body)

    public var defaultSize: CGFloat {
        switch self {
        case .largeTitle:
            return 34
        case .title:
            return 28
        case .title2:
            return 22
        case .title3:
            return 20
        case .headline, .body:
            return 17
        case .callout:
            return 16
        case .subheadline:
            return 15
        case .footnote:
            return 13
        case .caption:
            return 12
        case .caption2:
            return 11
        case .custom(let size, _, _, _):
            return size
        }
    }

    public var defaultWeight: AppFontWeight {
        switch self {
        case .largeTitle, .title:
            return .bold
        case .title2, .title3, .headline:
            return .semiBold
        case .body, .callout, .subheadline, .footnote, .caption:
            return .regular
        case .caption2:
            return .medium
        case .custom(_, let weight, _, _):
            return weight
        }
    }

    public var defaultItalic: Bool {
        switch self {
        case .custom(_, _, let isItalic, _):
            return isItalic
        default:
            return false
        }
    }

    public var textStyle: Font.TextStyle {
        switch self {
        case .largeTitle:
            return .largeTitle
        case .title:
            return .title
        case .title2:
            return .title2
        case .title3:
            return .title3
        case .headline:
            return .headline
        case .body:
            return .body
        case .callout:
            return .callout
        case .subheadline:
            return .subheadline
        case .footnote:
            return .footnote
        case .caption:
            return .caption
        case .caption2:
            return .caption2
        case .custom(_, _, _, let relativeTo):
            return relativeTo
        }
    }

    /// Resolves the corresponding SwiftUI `Font` with dynamic scaling.
    public func font(weight: AppFontWeight? = nil, isItalic: Bool? = nil) -> Font {
        let resolvedWeight = weight ?? defaultWeight
        let resolvedItalic = isItalic ?? defaultItalic
        return AppFont.font(
            resolvedWeight,
            size: defaultSize,
            relativeTo: textStyle,
            isItalic: resolvedItalic
        )
    }
}

// MARK: - Font Helpers

enum AppFont {
    /// Returns a Poppins font configured with weight, size, optional italic style, and Dynamic Type scaling.
    static func font(
        _ weight: AppFontWeight = .regular,
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle? = nil,
        isItalic: Bool = false
    ) -> Font {
        let fontName = weight.postScriptName(isItalic: isItalic)
        if let textStyle {
            return Font.custom(fontName, size: size, relativeTo: textStyle)
        } else {
            return Font.custom(fontName, size: size)
        }
    }

    /// Returns a Poppins font corresponding to an `AppTypography` semantic style.
    static func font(
        _ style: AppTypography,
        weight: AppFontWeight? = nil,
        isItalic: Bool? = nil
    ) -> Font {
        style.font(weight: weight, isItalic: isItalic)
    }
}

// MARK: - Typography View Modifier

/// A ViewModifier that applies the Poppins typography system with accessibility scaling.
public struct TypographyModifier: ViewModifier {
    public let font: Font

    public init(font: Font) {
        self.font = font
    }

    public init(
        _ style: AppTypography,
        weight: AppFontWeight? = nil,
        isItalic: Bool = false
    ) {
        self.font = style.font(weight: weight, isItalic: isItalic)
    }

    public init(
        size: CGFloat,
        weight: AppFontWeight = .regular,
        isItalic: Bool = false,
        relativeTo textStyle: Font.TextStyle = .body
    ) {
        self.font = AppFont.font(weight, size: size, relativeTo: textStyle, isItalic: isItalic)
    }

    public func body(content: Content) -> some View {
        content.font(font)
    }
}

// MARK: - View Extension

public extension View {
    /// Applies a semantic typography style using the Poppins font family.
    /// - Parameters:
    ///   - style: The semantic typography style (e.g. `.headline`, `.body`, `.title`).
    ///   - weight: Optional weight override (e.g. `.bold`, `.medium`). If nil, uses style default.
    ///   - isItalic: Whether to use the italic variation. Defaults to `false`.
    func typography(
        _ style: AppTypography,
        weight: AppFontWeight? = nil,
        isItalic: Bool = false
    ) -> some View {
        modifier(TypographyModifier(style, weight: weight, isItalic: isItalic))
    }

    /// Applies custom Poppins typography with explicit size and weight.
    /// - Parameters:
    ///   - size: Point size of the font.
    ///   - weight: Poppins weight. Defaults to `.regular`.
    ///   - isItalic: Whether to use the italic variation. Defaults to `false`.
    ///   - relativeTo: Font text style for Dynamic Type scaling. Defaults to `.body`.
    func typography(
        size: CGFloat,
        weight: AppFontWeight = .regular,
        isItalic: Bool = false,
        relativeTo: Font.TextStyle = .body
    ) -> some View {
        modifier(TypographyModifier(size: size, weight: weight, isItalic: isItalic, relativeTo: relativeTo))
    }
}
