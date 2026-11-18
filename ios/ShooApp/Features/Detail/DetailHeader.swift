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
        // #493: an unknown verdict shows the detection status; an unknown status the warning look.
        case nil, .unknown: self = scan.status == .blocked ? .danger : .caution
        }
    }

    /// Figma "Hero BG": 402 × 360 picture with the rings in it.
    var heroImage: String {
        switch self {
        case .danger: "DetailHeroRed"
        case .caution: "DetailHeroAmber"
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
    static let sheetCorner: CGFloat = 32
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
    /// Middle of the shield (or the avatar) in the full hero.
    static let illustrationCenterY: CGFloat = 161
    /// The pinned hero once the page has scrolled: the back button's row plus 12 pt.
    static let compactHeight: CGFloat = backTop + 50 + 12
    /// In the compact hero the shield shrinks to this and sits in the middle of the back button's row.
    static let compactScale: CGFloat = 0.3
    static let compactCenterY: CGFloat = backTop + 25
    /// The hero ends where the link pill starts, so the pill is never drawn under it at rest.
    static let restHeight: CGFloat = pillTop
    /// Scrolled this far, the hero is compact.
    static let collapseDistance: CGFloat = restHeight - compactHeight

    /// Height of the pinned hero for a scroll offset (negative when the page is pulled down).
    static func height(offset: CGFloat) -> CGFloat {
        max(compactHeight, restHeight - offset)
    }

    /// 0 at rest, 1 once compact.
    static func progress(offset: CGFloat) -> CGFloat {
        min(max(offset / collapseDistance, 0), 1)
    }

    /// Parallax: the rings rise slower than the page and ease out, ending with their centre on the compact shield.
    /// The rows the compact hero shows then stay in the picture's pink part (it turns white below ~220 pt).
    static let parallaxShift: CGFloat = DetailHeroBackground.ringCenterY - compactCenterY
    /// Scrolled this far, the rings have done ~70 % of their rise, about when the hero turns compact.
    static let parallaxLength: CGFloat = 130

    /// Top of the ring picture for a scroll offset. Pulled down it stays at the top and stretches instead
    /// (`DetailHeroBackground.stretch`).
    static func imageTop(offset: CGFloat) -> CGFloat {
        offset < 0 ? 0 : -parallaxShift * (1 - exp(-offset / parallaxLength))
    }
}

/// The rings, placed for a scroll offset. Drawn behind the page (under the sheet's round corners) and again inside
/// the pinned hero, at the same place, so the two never show a seam.
struct DetailHeroBackdrop: View {
    let look: DetailLook
    let offset: CGFloat

    var body: some View {
        // Parallax (`DetailHeroLayout.imageTop`). Pulled down, the picture grows from its bottom edge by the pull,
        // so its bottom follows the sheet and no flat band shows above it.
        DetailHeroBackground(look: look, stretch: max(-offset, 0))
            .offset(y: DetailHeroLayout.imageTop(offset: offset))
            .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }
}

/// The pinned hero: rings, the shield (or the deciding guardian's avatar with a small shield) and the back button.
/// Full at rest; as the page scrolls it shrinks to the back button's row and the shield with it, while the white
/// sheet scrolls under it.
struct DetailHero: View {
    let look: DetailLook
    /// The guardian who decided, on the protected person's own Detail (Figma "Guardian Virellia").
    var guardianAvatarId: String?
    /// How far the page has scrolled; negative when pulled down.
    var offset: CGFloat = 0
    let onBack: () -> Void

    var body: some View {
        let progress = DetailHeroLayout.progress(offset: offset)
        let scale = 1 - (1 - DetailHeroLayout.compactScale) * progress
        let rise = (DetailHeroLayout.compactCenterY - DetailHeroLayout.illustrationCenterY) * progress
        // Pulled down, the shield moves down with the page as it used to.
        let pull = max(-offset, 0)
        // Once the sheet's top reaches the compact hero, its round top edge stays there and the page scrolls under
        // it: a straight cut across the cards looked like the page was chopped off.
        let lipStart = DetailHeroLayout.sheetTop - DetailHeroLayout.compactHeight
        let lipPinned = offset >= lipStart
        let lipFade = min(max((offset - lipStart) / 24, 0), 1)
        let lip = DetailHeroLayout.sheetCorner
        ZStack(alignment: .topLeading) {
            Group {
                DetailHeroBackdrop(look: look, offset: offset)
                illustration
                    .scaleEffect(
                        scale,
                        anchor: UnitPoint(x: 0.5, y: DetailHeroLayout.illustrationCenterY / DetailHeroLayout.sheetTop)
                    )
                    .offset(y: rise + pull)
            }
            .allowsHitTesting(false)
            OnboardingBackButton(identifier: "detail.back", action: onBack)
                .padding(.leading, 20)
                .padding(.top, DetailHeroLayout.backTop)
        }
        // Pinned, the hero is one corner taller: the rings show behind the sheet's round corners, as at rest.
        .frame(height: DetailHeroLayout.height(offset: offset) + (lipPinned ? lip : 0), alignment: .top)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .bottom) {
            if lipPinned {
                UnevenRoundedRectangle(topLeadingRadius: lip, topTrailingRadius: lip, style: .continuous)
                    .fill(.white)
                    .frame(height: lip)
                    // The cards come out of the white instead of meeting a hard line.
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 16)
                            .offset(y: 16)
                            .opacity(lipFade)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
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
    /// Tail, not middle (BH-13): the text starts with the scan's `domain` (`DetailView.shownLink`),
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
            // `nil` (family list not loaded or failed): the neutral person.
            AvatarView(id: avatarId ?? "", size: 24)
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
    /// How far the page is pulled down past its top: the picture grows by that much from its bottom edge, rings
    /// kept round, so the pull shows more hero instead of a flat band.
    var stretch: CGFloat = 0

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
        .scaleEffect((height + stretch) / height, anchor: .bottom)
        .frame(height: height + stretch, alignment: .bottom)
        .clipped()
        .accessibilityHidden(true)
    }
}
