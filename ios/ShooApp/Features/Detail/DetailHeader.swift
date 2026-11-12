import SwiftUI

/// The two looks of the Detail hero (Figma "Detail Aktivitas Guardian REVISI PRU" 1252:9850 and
/// "Detail Aktivitas Ortu REVISI PRU" 1211:19924): red for a blocked or confirmed scam, orange for a
/// warning or a site a guardian marked safe.
enum DetailLook: Equatable {
    case danger
    case caution

    init(scan: ScanResult) {
        switch scan.verdict?.value {
        case .notSafe: self = .danger
        case .safe: self = .caution
        case nil: self = scan.status == .blocked ? .danger : .caution
        }
    }

    /// Figma "Hero BG": 402 × 360 picture with the rings in it.
    var heroImage: String {
        switch self {
        case .danger: "DetailHeroRed"
        case .caution: "DetailHeroAmber"
        }
    }

    /// The top row of the picture, carried on above it when the page is pulled down.
    var topColor: Color {
        switch self {
        case .danger: DetailStyle.hex(0xFF8A80)
        case .caution: DetailStyle.hex(0xFFBD6B)
        }
    }

    var shieldTint: HalftoneShield.Tint {
        switch self {
        case .danger: .red
        case .caution: .orange
        }
    }

    /// The link pill: pink with a white rim (danger), white with a grey rim (caution).
    var pillFill: Color { self == .danger ? DetailStyle.hex(0xFFF4F2) : .white }
    var pillStroke: Color { self == .danger ? .white : DetailStyle.hex(0xE2E8F0) }
    var pillText: Color { self == .danger ? DetailStyle.hex(0xB42318) : DetailStyle.ink }
}

/// Where the Figma frames put the hero parts, in points from the top of the 402 pt wide frame.
enum DetailHeroLayout {
    static let width: CGFloat = 402
    static let imageHeight: CGFloat = 360
    /// "Sheet": white, 32 pt corners, from y 284.
    static let sheetTop: CGFloat = 284
    /// Link pill: 34 pt high at y 266, half on the hero, half on the sheet.
    static let pillTop: CGFloat = 266
    /// Back: 50 × 50 at (20, 48).
    static let backTop: CGFloat = 48
    /// Big "Shield Kaca Halftone": the 130 × 150 Kaca at (136, 86), i.e. 1.25 × `HalftoneShield`.
    static let shieldScale: CGFloat = 1.25
    static let shieldKacaCenter = CGPoint(x: 201, y: 161)
    /// "Guardian Virellia": 148.29 pt circle at (121, 84).
    static let avatarSize: CGFloat = 148.29
    static let avatarCenter = CGPoint(x: 121 + 148.29 / 2, y: 84 + 148.29 / 2)
    /// The small shield on the avatar's lower right: Kaca 53.13 × 61.3 at (223.35, 179).
    static let badgeScale: CGFloat = 53.13 / 104
    static let badgeKacaCenter = CGPoint(x: 223.35 + 53.13 / 2, y: 179 + 61.3 / 2)
    /// `HalftoneShield`'s Kaca centre sits 0.33 pt above the middle of its 220 × 176 frame.
    static let kacaRise: CGFloat = 0.33
}

/// Rings, the shield (or the deciding guardian's avatar with a small shield) and the link pill.
struct DetailHero: View {
    let look: DetailLook
    /// The guardian who decided, on the protected person's own Detail (Figma "Guardian Virellia").
    var guardianAvatarId: String?
    let onBack: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            illustration
            OnboardingBackButton(identifier: "detail.back", action: onBack)
                .padding(.leading, 20)
                .padding(.top, DetailHeroLayout.backTop)
        }
        .frame(height: DetailHeroLayout.sheetTop)
    }

    /// Laid out on the 402 pt Figma frame and kept in the middle of wider or narrower screens.
    private var illustration: some View {
        ZStack(alignment: .topLeading) {
            if let guardianAvatarId {
                AvatarView(id: guardianAvatarId, size: DetailHeroLayout.avatarSize)
                    // Figma: #0D7380 25 %, y 11.7, blur 31.2.
                    .shadow(color: DetailStyle.hex(0x0D7380).opacity(0.25), radius: 15.6, y: 11.7)
                    .position(DetailHeroLayout.avatarCenter)
                shield(scale: DetailHeroLayout.badgeScale, kacaCenter: DetailHeroLayout.badgeKacaCenter)
            } else {
                shield(scale: DetailHeroLayout.shieldScale, kacaCenter: DetailHeroLayout.shieldKacaCenter)
            }
        }
        .frame(width: DetailHeroLayout.width, height: DetailHeroLayout.sheetTop, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func shield(scale: CGFloat, kacaCenter: CGPoint) -> some View {
        HalftoneShield(tint: look.shieldTint)
            .scaleEffect(scale)
            .position(x: kacaCenter.x, y: kacaCenter.y + DetailHeroLayout.kacaRise * scale)
    }
}

/// "bca-verifikasi.site/login": 17 pt in a 34 pt capsule with a 1 pt outside rim.
struct DetailLinkPill: View {
    let look: DetailLook
    let text: String
    /// Tail, not middle (BH-13): the text starts with the registrable domain (`DetailView.shownLink`),
    /// so a long path is what gets cut, never the domain.
    static let truncation: Text.TruncationMode = .tail

    var body: some View {
        Text(verbatim: text)
            .activityFont(17)
            .figmaLineHeight(22, relativeTo: .body)
            .foregroundStyle(look.pillText)
            .lineLimit(1)
            .truncationMode(Self.truncation)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 34)
            .background(look.pillFill, in: Capsule())
            .background(Capsule().fill(look.pillStroke).padding(-1))
            .padding(.horizontal, 24)
    }
}

/// Figma "Bar" under "92/100": one hatched segment per reason (by weight), a tick at the score, then the
/// grey track. 153 pt wide, 1.5 pt apart.
struct RiskScoreBar: View {
    let score: Int
    let weights: [Int]

    /// The weights scaled so they add up to the score: the tick sits at the score, the track shows the rest.
    static func scaled(score: Int, weights: [Int]) -> [Int] {
        let total = weights.reduce(0) { $0 + max($1, 0) }
        guard total > 0 else { return [] }
        let target = Double(min(max(score, 0), 100))
        return weights.map { Int((Double(max($0, 0)) * target / Double(total)).rounded()) }
    }

    var body: some View {
        ContributionBar(weights: Self.scaled(score: score, weights: weights), style: .score)
            .frame(width: 153)
            .frame(height: 18)
    }
}

/// "Status situs" chip: Diblokir (red), Waspada (orange), Blokir Dibuka / Ditandai aman (blue).
struct DetailStatusChip: View {
    enum Kind {
        case blocked
        case warning
        case unblocked
        case markedSafe
    }

    let kind: Kind

    var body: some View {
        Text(title)
            .activityFont(15, rounded: true)
            .figmaLineHeight(21, relativeTo: .subheadline)
            .foregroundStyle(colors.text)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(minHeight: 33)
            .background(colors.fill, in: Capsule())
            .overlay(Capsule().strokeBorder(colors.stroke))
            .fixedSize()
    }

    private var title: LocalizedStringKey {
        switch kind {
        case .blocked: "Blocked"
        case .warning: "detail.status.warning"
        case .unblocked: "detail.status.unblocked"
        case .markedSafe: "Marked safe"
        }
    }

    private var colors: (fill: Color, stroke: Color, text: Color) {
        switch kind {
        case .blocked: (HomeTheme.dangerFill, HomeTheme.dangerStroke, HomeTheme.dangerText)
        // Figma #D67D00 is 2.9:1 on its chip; the darker Home warning text keeps 4.5:1.
        case .warning: (DetailStyle.hex(0xFFF8EF), DetailStyle.hex(0xFFE0B8), HomeTheme.warningText)
        case .unblocked, .markedSafe: (DetailStyle.hex(0xDEF4FF), DetailStyle.hex(0x94DBFE), HomeTheme.action)
        }
    }
}

/// "Syahnaz" with their avatar, under "Profil yang mengakses" (Figma "Profil Dilindungi", 42 pt).
struct DetailOwnerChip: View {
    let name: String
    let avatarId: String?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let avatarId {
                    AvatarView(id: avatarId, size: 24)
                } else {
                    ActivityAvatar(name: name, avatarId: "1", size: 24)
                }
            }
            .overlay(Circle().strokeBorder(.white.opacity(0.5)))
            Text(verbatim: name)
                .activityFont(16, .semibold, rounded: true, tracking: -0.31)
                .figmaLineHeight(21, relativeTo: .body)
                .foregroundStyle(DetailStyle.title)
                .lineLimit(1)
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 42)
        .background(DetailStyle.hex(0xE7EFF8), in: Capsule())
        .overlay(Capsule().strokeBorder(DetailStyle.hex(0xAAD2FF)))
        .figmaCardShadow()
    }
}

extension View {
    /// How far the enclosing scroll view has scrolled (iOS 18+). Before iOS 18 nothing is reported.
    @ViewBuilder
    func onScrollOffset(_ action: @escaping (CGFloat) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                action(offset)
            }
        } else {
            self
        }
    }
}

/// Figma "Hero BG" brought to life: the rings in the picture breathe around their centre and soft white
/// discs grow out of the shield and fade (the Home hero's `SoftPulse`), both on a 4 s beat.
/// Reduce Motion keeps the still picture.
struct DetailHeroBackground: View {
    let look: DetailLook

    @Environment(\.shooReduceMotion) private var reduceMotion

    /// Centre of the rings in the 402 × 360 picture (inner ring x 72–330, y 41–300).
    static let ringCenterY: CGFloat = 170
    private static let period = 4.0
    /// The rings grow by this much at the top of a breath: kept subtle on a warning screen.
    private static let breathScale = 0.012

    var body: some View {
        let height = DetailHeroLayout.imageHeight
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let breath = (1 - cos(time * 2 * .pi / Self.period)) / 2
            Image(look.heroImage)
                .resizable()
                .frame(height: height)
                .scaleEffect(1 + Self.breathScale * breath, anchor: UnitPoint(x: 0.5, y: Self.ringCenterY / height))
        }
        .overlay(alignment: .top) {
            if !reduceMotion {
                SoftPulse(smallest: 140, largest: 420, peak: 0.1)
                    .offset(y: Self.ringCenterY - 210)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(height: height)
        .clipped()
        .accessibilityHidden(true)
    }
}
