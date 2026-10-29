import SwiftUI

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

/// Figma sizes that still follow Dynamic Type: the size scales with `relativeTo`, tracking with it.
private struct ActivityFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let base: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let tracking: CGFloat

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, tracking: CGFloat, relativeTo: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
        base = size
        self.weight = weight
        self.design = design
        self.tracking = tracking
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: weight, design: design))
            .tracking(tracking * size / base)
    }
}

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
        return modifier(ActivityFont(
            size: size, weight: weight, design: rounded ? .rounded : .default, tracking: tracking, relativeTo: style
        ))
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
        .overlay(Capsule().stroke(colors.stroke))
        .fixedSize()
    }
}

// MARK: Avatars

/// A member's initial on a gradient with a thin white rim (Figma "Avatar/S", "Avatar/B", "Avatar/R").
/// The gradient is picked by avatar id, so a member keeps the same colour everywhere.
struct ActivityAvatar: View {
    let name: String
    let avatarId: String
    let size: CGFloat

    /// Figma's three avatar gradients, top-left → bottom-right.
    static let gradients: [[Color]] = [
        [ActivityStyle.hex(0x7DE49C), ActivityStyle.hex(0x54CAE8)],
        [ActivityStyle.hex(0xFFBE8C), ActivityStyle.hex(0xFF7896)],
        [ActivityStyle.hex(0xAFA5FF), ActivityStyle.hex(0x6E8CFA)],
    ]

    static func gradient(avatarId: String) -> [Color] {
        let number = Int(avatarId.filter(\.isNumber)) ?? 1
        return gradients[(max(number, 1) - 1) % gradients.count]
    }

    static func initial(of name: String) -> String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        Text(verbatim: Self.initial(of: name))
            // Figma: 9.5 pt on 24, 6.33 pt on 16.
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: Self.gradient(avatarId: avatarId), startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Circle()
            )
            .overlay(Circle().stroke(.white.opacity(0.5)))
            .accessibilityHidden(true)
    }
}

/// Up to three overlapping avatars, each 12 pt to the right of the previous (Figma "Avatar Stack").
struct ActivityAvatarStack: View {
    let people: [FamilyMember]
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: -size / 2) {
            ForEach(Array(people.prefix(3).enumerated()), id: \.offset) { index, member in
                ActivityAvatar(name: member.name, avatarId: member.avatarId, size: size)
                    .zIndex(Double(-index))
            }
        }
        .accessibilityHidden(true)
    }
}
