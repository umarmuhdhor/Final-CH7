import CoreText
import SwiftUI
import UIKit

/// The one font every Figma-styled text in the app goes through (`onboardingFont`, `profileFont`,
/// `activityFont`, and Home via `onboardingFont`).
///
/// Figma sets almost all text in "SF Pro Display" / "SF Pro Rounded" at every size. The system font picks
/// its optical size from the point size, so below 20 pt it draws the wider-spaced Text cut and lines ran
/// 5–11 % wider than in Figma (≈3 % wider even at 30 pt). Pinning the system font's optical-size axis to
/// its top end draws the same advance widths as those static Figma fonts; it stays the system font.
enum FigmaFont {
    /// The Figma font family a text layer uses (measured against the static fonts Figma draws with).
    enum Family {
        /// "SF Pro Display" / "SF Pro Rounded": almost every text in the file. Optical size 96.
        case display
        /// The static "SF Pro Text" (name field, "Lewati", "Terkendala? Tonton Tutorial", the invite code):
        /// optical size 17 without the system's size-specific tracking, i.e. +2.54 % of the size wider.
        case text
        /// The variable "SF Pro" (the "Pindai QR | Kode" segments, Splash "Lewati"): Figma picks its optical
        /// size and tracking from the point size like iOS does, so it gets the plain system font.
        case sfPro
    }

    /// Top of SF Pro's `opsz` axis (17–96): the static "SF Pro Display" cut.
    static let displayOpticalSize: CGFloat = 96
    /// Bottom of the axis: the static "SF Pro Text" cut.
    static let textOpticalSize: CGFloat = 17
    /// Static "SF Pro Text" runs this fraction of the point size wider per character than the system font
    /// at optical size 17 (the system's tracking table; the same at 11–20 pt).
    static let textExtraTracking: CGFloat = 0.0254

    /// A fixed-size Figma font. Prefer the view modifiers, which also follow Dynamic Type and Bold Text,
    /// and add `.text`'s extra tracking.
    static func font(
        size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, family: Family = .display
    ) -> Font {
        let opticalSize: CGFloat
        switch family {
        case .display: opticalSize = displayOpticalSize
        case .text: opticalSize = textOpticalSize
        case .sfPro: return .system(size: size, weight: weight, design: design)
        }
        var descriptor = UIFont.systemFont(ofSize: size, weight: weight.uiFontWeight).fontDescriptor
        if let designed = descriptor.withDesign(design.uiFontDesign) {
            descriptor = designed
        }
        descriptor = descriptor.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: kCTFontOpticalSizeAttribute as String): opticalSize,
        ])
        return Font(UIFont(descriptor: descriptor, size: size))
    }
}

/// Figma size that still follows Dynamic Type: the size scales with `relativeTo`, tracking with it.
/// `tracking == nil` leaves tracking to the caller (an outer `.tracking` would lose to an inner one); `.text`
/// always sets tracking, so pass its Figma letter spacing here.
struct FigmaScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    @Environment(\.legibilityWeight) private var legibilityWeight
    private let base: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    private let tracking: CGFloat?
    private let family: FigmaFont.Family

    init(
        size: CGFloat, weight: Font.Weight, design: Font.Design, tracking: CGFloat?, family: FigmaFont.Family,
        relativeTo style: Font.TextStyle
    ) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        base = size
        self.weight = weight
        self.design = design
        self.tracking = tracking
        self.family = family
    }

    func body(content: Content) -> some View {
        // `Font(UIFont)` doesn't follow Bold Text by itself the way `.system` does.
        let bold = legibilityWeight == .bold && family != .sfPro
        let font = FigmaFont.font(size: size, weight: bold ? weight.bolder : weight, design: design, family: family)
        let extra = family == .text ? FigmaFont.textExtraTracking * size : 0
        if tracking != nil || extra != 0 {
            content.font(font).tracking((tracking ?? 0) * size / base + extra)
        } else {
            content.font(font)
        }
    }
}

extension View {
    /// Figma text at `size` pt that scales with `style`.
    func figmaFont(
        _ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default,
        tracking: CGFloat? = nil, family: FigmaFont.Family = .display, relativeTo style: Font.TextStyle
    ) -> some View {
        modifier(FigmaScaledFont(size: size, weight: weight, design: design, tracking: tracking, family: family, relativeTo: style))
    }
}

private extension Font.Weight {
    var uiFontWeight: UIFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }

    /// What Bold Text turns each weight into.
    var bolder: Font.Weight {
        switch self {
        case .ultraLight: .light
        case .thin: .regular
        case .light: .medium
        case .medium: .bold
        case .semibold: .bold
        case .bold: .heavy
        case .heavy, .black: .black
        default: .semibold
        }
    }
}

private extension Font.Design {
    var uiFontDesign: UIFontDescriptor.SystemDesign {
        switch self {
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        default: .default
        }
    }
}

/// Figma's fixed line height (e.g. 110 % on the 30 pt headlines), scaled with Dynamic Type. iOS 26+ only:
/// before it SwiftUI has no way to set a line height below the font's own. `glyphOffset` moves the drawn
/// glyphs where Figma centres them in the line (iOS places them differently; measured per style).
private struct FigmaLineHeight: ViewModifier {
    @ScaledMetric private var points: CGFloat
    private let base: CGFloat
    private let glyphOffset: CGFloat

    init(points: CGFloat, glyphOffset: CGFloat, relativeTo style: Font.TextStyle) {
        _points = ScaledMetric(wrappedValue: points, relativeTo: style)
        base = points
        self.glyphOffset = glyphOffset
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // The exact height replaces any `lineSpacing` set further out (the pre-iOS 26 approximation).
            content
                .lineHeight(.exact(points: points))
                .lineSpacing(0)
                .offset(y: glyphOffset * points / base)
        } else {
            content
        }
    }
}

extension View {
    /// Figma "line height" in points (`fontSize × percent / 100`).
    func figmaLineHeight(_ points: CGFloat, glyphOffset: CGFloat = 0, relativeTo style: Font.TextStyle) -> some View {
        modifier(FigmaLineHeight(points: points, glyphOffset: glyphOffset, relativeTo: style))
    }
}
