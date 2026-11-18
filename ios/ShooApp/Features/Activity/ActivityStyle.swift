import CoreText
import SwiftUI
import UIKit

/// Figma "Aktivitas – Profil Pribadi / Guardian" + "Picker" (PR-05, GD-05): colours, type and
/// the pieces of the Activity list. Values are the Figma ones. Light only, like Profile (PF-01):
/// dark mode is a backlog issue, the app stays light (`RootView`).
enum ActivityStyle {
    static let backgroundTop = hex(0xDFEFFC)
    static let backgroundMiddle = hex(0xE6F2FC)
    static let background = hex(0xF5FAFC)
    static let title = hex(0x191C25)
    static let ink = hex(0x191D2F)
    static let secondary = hex(0x6A717E)
    static let time = hex(0x564C51)
    static let separator = hex(0xC7C7CE)
    static let segmentTrack = hex(0x767680).opacity(0.12)
    static let iconFill = hex(0xF3F6F8)
    static let iconStroke = hex(0xE2E8F0)
    static let menuText = hex(0x1A1A1A)
    // Empty states (Figma 480:5490 …).
    static let emptyTitle = hex(0x151617)
    static let activeDot = hex(0x34C759)
    static let pillShadow = hex(0x1A1C2E)
    static let blueButtonTop = hex(0x68CDFA)
    static let blueButtonBottom = hex(0x136CB7)
    static let blueButtonStroke = hex(0x0098D7)

    /// Screen side margin; cards are 354 wide on the 402 pt Figma frame.
    static let margin: CGFloat = 24

    /// File-local so it doesn't clash with other screens' hex helpers.
    static func hex(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

// MARK: Type

/// Figma sizes that still follow Dynamic Type (shared `FigmaFont`: the SF Pro Display widths Figma uses).
extension View {
    func activityFont(
        _ size: CGFloat, _ weight: Font.Weight = .regular, rounded: Bool = false, tracking: CGFloat = 0
    ) -> some View {
        let style: Font.TextStyle = switch size {
        case ..<12: .caption
        case ..<14: .footnote
        case ..<16: .subheadline
        case ..<19: .body
        case ..<24: .title2
        default: .title
        }
        return figmaFont(size, weight: weight, design: rounded ? .rounded : .default, tracking: tracking, relativeTo: style)
    }

    /// Figma "Liquid Glass – Regular": the real glass on iOS 26, a material before it.
    @ViewBuilder
    func activityGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
    }
}

// MARK: Background

/// The light blue wash at the top fading into the page grey (Figma frame fill).
struct ActivityBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            ActivityStyle.background
            LinearGradient(
                stops: [
                    .init(color: ActivityStyle.backgroundTop, location: 0),
                    .init(color: ActivityStyle.backgroundMiddle, location: 0.3),
                    .init(color: ActivityStyle.background, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 200)
        }
        .ignoresSafeArea()
    }
}

// MARK: Badge

/// "Waspada" / "Diblokir" (and the guardian's "Verified scam" / "Marked safe") at the top right
/// of a row (Figma "Button" instance). The text is always there, so colour is never the only signal.
struct ActivityBadge: View {
    let badge: ScanBadge

    var title: LocalizedStringKey {
        switch badge {
        case .warning: "activity.warning"
        case .blocked: "Blocked"
        case .verifiedScam: "Verified scam"
        case .markedSafe: "Marked safe"
        }
    }

    private var symbol: String {
        switch badge {
        case .warning, .blocked: "exclamationmark.circle.fill"
        case .verifiedScam: "xmark.circle.fill"
        case .markedSafe: "checkmark.circle.fill"
        }
    }

    /// (icon, text, fill, stroke), the Figma values.
    private var colors: (icon: Color, text: Color, fill: Color, stroke: Color) {
        switch badge {
        case .warning:
            (ActivityStyle.hex(0xD67D00), ActivityStyle.hex(0xD67D00), ActivityStyle.hex(0xFFF8EF), ActivityStyle.hex(0xFFE1B6))
        case .blocked, .verifiedScam:
            (ActivityStyle.hex(0xBB1616), ActivityStyle.hex(0xBB1616), ActivityStyle.hex(0xFFF4F4), ActivityStyle.hex(0xFFCDCD))
        case .markedSafe:
            (ActivityStyle.hex(0x34C759), ActivityStyle.hex(0x1B7F3A), ActivityStyle.hex(0xE8F8EE), ActivityStyle.hex(0xBFEBCD))
        }
    }

    var body: some View {
        let colors = colors
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .activityFont(10, .semibold)
                .foregroundStyle(colors.icon)
                .accessibilityHidden(true)
            Text(title)
                .activityFont(13, tracking: -0.1625)
                .foregroundStyle(colors.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minHeight: 23)
        .background(colors.fill, in: Capsule())
        // Figma: 0.75 pt inside stroke.
        .overlay(Capsule().strokeBorder(colors.stroke, lineWidth: 0.75))
        .fixedSize()
    }
}

// MARK: Avatars

extension ActivityStyle {
    /// Figma's thin white rim on the people's avatars (rows, the person picker, Detail's owner chip).
    static let avatarRing = AvatarView.Ring(color: .white.opacity(0.5))
}

/// Up to three overlapping avatars, each 12 pt to the right of the previous (Figma "Avatar Stack").
struct ActivityAvatarStack: View {
    let people: [FamilyMember]
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: -size / 2) {
            ForEach(Array(people.prefix(3).enumerated()), id: \.offset) { index, member in
                AvatarView(id: member.avatarId, size: size, ring: ActivityStyle.avatarRing)
                    .zIndex(Double(-index))
            }
        }
        .accessibilityHidden(true)
    }
}
