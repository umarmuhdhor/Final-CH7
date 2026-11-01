import SwiftUI

/// Colours from the Figma HOME page (Pribadi/Home 435:20058, Guardian/Home 435:20373, protected/Home 441:3800).
/// Light only, like the onboarding screens.
enum HomeTheme {
    static let background = Color(red: 0xF9 / 255, green: 0xFB / 255, blue: 0xFC / 255)
    static let fade = Color(red: 0xF3 / 255, green: 0xF6 / 255, blue: 0xF8 / 255)
    static let heroDark = Color(red: 0x1E / 255, green: 0x78 / 255, blue: 0xBE / 255)
    static let heroLight = Color(red: 0x68 / 255, green: 0xCD / 255, blue: 0xFA / 255)
    static let heroGlow = Color(red: 0x8F / 255, green: 0xE9 / 255, blue: 0xEC / 255)
    static let navy = Color(red: 0x19 / 255, green: 0x1D / 255, blue: 0x2F / 255)
    static let ink = Color(red: 0x15 / 255, green: 0x16 / 255, blue: 0x17 / 255)
    /// Figma #6A717E is 4.6:1 on white.
    static let secondaryInk = Color(red: 0x6A / 255, green: 0x71 / 255, blue: 0x7E / 255)
    static let bodyInk = Color(red: 0x3A / 255, green: 0x3D / 255, blue: 0x42 / 255)
    static let tileIcon = Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x3B / 255)
    static let tileIconBackground = Color(red: 0xF3 / 255, green: 0xF6 / 255, blue: 0xF8 / 255)
    static let rowStroke = Color(red: 0xE2 / 255, green: 0xE8 / 255, blue: 0xF0 / 255)
    static let divider = Color(red: 0xE3 / 255, green: 0xE6 / 255, blue: 0xE7 / 255)
    /// Figma "Bagikan", step numbers and "Lihat Semua ▶".
    static let action = Color(red: 0x18 / 255, green: 0x6F / 255, blue: 0xB9 / 255)
    static let actionFill = Color(red: 0xEE / 255, green: 0xF4 / 255, blue: 0xFB / 255)
    static let quietFill = Color(red: 0xE6 / 255, green: 0xE8 / 255, blue: 0xEC / 255)
    /// Figma #D67D00 is 2.9:1 on its chip; darkened to 4.6:1 for 13 pt text.
    static let warningText = Color(red: 0xA8 / 255, green: 0x5A / 255, blue: 0x00 / 255)
    static let warningFill = Color(red: 0xFF / 255, green: 0xF8 / 255, blue: 0xEF / 255)
    static let warningStroke = Color(red: 0xFF / 255, green: 0xE1 / 255, blue: 0xB6 / 255)
    /// Figma "7 Waspada" orange, darkened to 3:1 on white for the 28 pt number.
    static let warningNumber = Color(red: 0xE0 / 255, green: 0x78 / 255, blue: 0x00 / 255)
    static let dangerText = Color(red: 0xBB / 255, green: 0x16 / 255, blue: 0x16 / 255)
    static let dangerButton = Color(red: 0xCE / 255, green: 0x20 / 255, blue: 0x20 / 255)
    static let dangerFill = Color(red: 0xFF / 255, green: 0xF4 / 255, blue: 0xF4 / 255)
    static let dangerStroke = Color(red: 0xFF / 255, green: 0xCD / 255, blue: 0xCD / 255)
    static let success = Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
    static let successText = Color(red: 0x1B / 255, green: 0x7F / 255, blue: 0x3A / 255)
    static let offline = Color(red: 0x8E / 255, green: 0x93 / 255, blue: 0x9C / 255)
}

// MARK: - Hero

/// The three hero looks of the Figma HOME page.
enum HomeHeroStyle {
    /// Blue: own Home (Pribadi, protected), and the empty family.
    case blue
    /// Teal: the family is protected.
    case teal

    var colors: (base: Color, deep: Color, mid: Color) {
        switch self {
        case .blue: (Color(red: 0x68 / 255, green: 0xCD / 255, blue: 0xFA / 255),
                     Color(red: 0x1D / 255, green: 0x82 / 255, blue: 0xD0 / 255),
                     Color(red: 0x23 / 255, green: 0xAF / 255, blue: 0xE9 / 255))
        case .teal: (Color(red: 0x5D / 255, green: 0xED / 255, blue: 0xF5 / 255),
                     Color(red: 0x00 / 255, green: 0xB3 / 255, blue: 0xBE / 255),
                     Color(red: 0x3C / 255, green: 0xDB / 255, blue: 0xDE / 255))
        }
    }
}

/// Rings, glass shield, headline (and an optional line or link under it). `accessory` sits under the text,
/// still on the hero (Protected: "Terhubung dengan …").
struct HomeHero<Accessory: View>: View {
    let style: HomeHeroStyle
    let title: LocalizedStringKey
    var titleColor: Color = .white
    var titleIdentifier: String
    var subtitle: LocalizedStringKey?
    var shieldOn = true
    var shieldTint: HalftoneShield.Tint = .blue
    var bottomPadding: CGFloat = 38
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HeroRings()
                HalftoneShield(isOn: shieldOn, tint: shieldTint)
                    .scaleEffect(1.25)
            }
            .frame(height: 236)
            // Figma: ring centre 204 pt from the top of the screen, under the bar.
            .padding(.top, -36)

            VStack(spacing: 6) {
                Text(title)
                    .onboardingFont(27, weight: .semibold, relativeTo: .title)
                    .tracking(-0.27)
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(titleIdentifier)
                if let subtitle {
                    Text(subtitle)
                        .onboardingFont(15, relativeTo: .subheadline)
                        .foregroundStyle(titleColor.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            // Figma: the headline sits inside the inner ring's bottom edge.
            .padding(.top, -21)
            accessory()
        }
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity)
        // Reaches up under the navigation bar, the status bar and the pull-to-refresh overscroll.
        .background { HeroBackground(style: style).padding(.top, -400) }
    }
}

extension HomeHero where Accessory == EmptyView {
    init(style: HomeHeroStyle, title: LocalizedStringKey, titleColor: Color = .white, titleIdentifier: String,
         subtitle: LocalizedStringKey? = nil, shieldOn: Bool = true, shieldTint: HalftoneShield.Tint = .blue) {
        self.init(style: style, title: title, titleColor: titleColor, titleIdentifier: titleIdentifier, subtitle: subtitle,
                  shieldOn: shieldOn, shieldTint: shieldTint, accessory: { EmptyView() })
    }
}

/// Figma "Latar Shield": three dotted rings (236 / 300 / 368 pt) and a slow sweep on the inner one.
/// Reduce Motion stops the sweep.
private struct HeroRings: View {
    @Environment(\.shooReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ring(368, opacity: 0.16, width: 1)
            ring(300, opacity: 0.28, width: 1.2)
            ring(236, opacity: 0.45, width: 1.5)
            TimelineView(.animation(paused: reduceMotion)) { context in
                let turn = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8) / 8
                Circle()
                    .fill(AngularGradient(stops: [
                        .init(color: .white.opacity(0), location: 0),
                        .init(color: .white.opacity(0), location: 0.84),
                        .init(color: .white.opacity(0.2), location: 1),
                    ], center: .center))
                    .frame(width: 236, height: 236)
                    .rotationEffect(.degrees(turn * 360))
            }
        }
        .frame(width: 368, height: 368)
        .frame(height: 236)
        .accessibilityHidden(true)
    }

    private func ring(_ size: CGFloat, opacity: Double, width: CGFloat) -> some View {
        Circle()
            .stroke(.white.opacity(opacity), style: StrokeStyle(lineWidth: width, lineCap: .round, dash: [0.1, 4]))
            .frame(width: size, height: size)
    }
}

/// Figma "Gradient-classic-2 lighter": a deep colour top left over a lighter one, film grain, and the
/// "box" fade into the page at the bottom.
private struct HeroBackground: View {
    let style: HomeHeroStyle

    var body: some View {
        let colors = style.colors
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [colors.deep, colors.mid, colors.base],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Ellipse()
                    .fill(colors.deep)
                    .frame(width: proxy.size.width * 1.4, height: proxy.size.height * 0.7)
                    .offset(x: -proxy.size.width * 0.25, y: -proxy.size.height * 0.2)
                    .blur(radius: 70)
                Image("HeroTexture")
                    .resizable(resizingMode: .tile)
                    .blendMode(.multiply)
                    .opacity(0.35)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(colors: [HomeTheme.fade.opacity(0), HomeTheme.fade], startPoint: .top, endPoint: .bottom)
                        .frame(height: 120)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Top bar

/// Top-left ⇆ glass circle: switches between the guardian's own Home and the family's (GD-02).
struct HomeSwitchToolbarItem: ToolbarContent {
    let isFamilyShown: Bool
    let action: () -> Void

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) { button }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { button }
        }
    }

    private var button: some View {
        Button(action: action) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HomeTheme.navy)
                .frame(width: 50, height: 50)
                .modifier(HomeGlassCircle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Family mode"))
        .accessibilityValue(Text(isFamilyShown ? "On" : "Off"))
        .accessibilityAddTraits(.isToggle)
        .accessibilityHint(Text("Switches between your own Shield and your family's"))
        .accessibilityIdentifier("familyModeToggle")
    }
}

struct HomeProfileToolbarItem: ToolbarContent {
    let name: String?
    let action: () -> Void

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarTrailing) { ProfileInitialButton(name: name, action: action) }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarTrailing) { ProfileInitialButton(name: name, action: action) }
        }
    }
}

/// Liquid Glass on iOS 26, frosted material before; a solid circle with "Kurangi efek kaca".
private struct HomeGlassCircle: ViewModifier {
    @Environment(\.shooReduceGlass) private var reduceGlass

    func body(content: Content) -> some View {
        if reduceGlass {
            content.background(.white, in: Circle())
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
    }
}

/// Top-right 50 pt circle with the user's initial; opens Profile (PF-01).
private struct ProfileInitialButton: View {
    let name: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            InitialAvatar(name: name, size: 50, gradient: [HomeTheme.heroLight, HomeTheme.heroDark], fontSize: 20)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: HomeTheme.heroDark.opacity(0.18), radius: 6, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Profile"))
        .accessibilityIdentifier("profileButton")
    }
}

/// Figma avatar: a gradient circle with the first letter of the name. Decorative.
struct InitialAvatar: View {
    let name: String?
    var size: CGFloat = 44
    var gradient: [Color] = InitialAvatar.gradients[0]
    var fontSize: CGFloat?

    /// Syahnaz, Bayu, Renatta in the Figma family row; the first one also for the guardian.
    static let gradients: [[Color]] = [
        [Color(red: 0x7D / 255, green: 0xE4 / 255, blue: 0x9C / 255), Color(red: 0x54 / 255, green: 0xCA / 255, blue: 0xE8 / 255)],
        [Color(red: 0xFF / 255, green: 0xBE / 255, blue: 0x8C / 255), Color(red: 0xFF / 255, green: 0x78 / 255, blue: 0x96 / 255)],
        [Color(red: 0xAF / 255, green: 0xA5 / 255, blue: 0xFF / 255), Color(red: 0x6E / 255, green: 0x8C / 255, blue: 0xFA / 255)],
    ]

    static func gradient(at index: Int) -> [Color] { gradients[index % gradients.count] }

    private var initial: String {
        name?.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? ""
    }

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            if initial.isEmpty {
                Image(systemName: "person.fill").font(.system(size: (fontSize ?? size * 0.4), weight: .semibold))
            } else {
                Text(verbatim: initial).font(.system(size: fontSize ?? size * 0.41, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Status strip and sheet

/// Coloured strip under the hero ("Status Keamanan : Bagus!"); the white sheet below overlaps its lower part.
struct StatusStrip: View {
    let title: LocalizedStringKey
    let value: LocalizedStringKey
    let fill: Color

    static let personal = Color(red: 0x1C / 255, green: 0x71 / 255, blue: 0xBA / 255)
    static let family = Color(red: 0x00 / 255, green: 0x9F / 255, blue: 0xA3 / 255)

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.grid.3x3.fill")
                .font(.system(size: 13))
                .accessibilityHidden(true)
            (Text(title) + Text(verbatim: " ") + Text(value).fontWeight(.semibold))
                .onboardingFont(15, relativeTo: .subheadline)
                .tracking(-0.15)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 45)
        .background(fill, in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.securityStatus")
    }
}

extension View {
    /// The white Figma "Status" sheet: 22 pt corners, pulled up over the strip.
    func homeSheet() -> some View {
        frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.top, -28)
    }

    /// Figma "Update card": white, 20 pt corners, a hairline of light and a very soft shadow.
    func homeCard(cornerRadius: CGFloat = 20) -> some View {
        background(.white, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(.white.opacity(0.9), lineWidth: 1))
            .figmaCardShadow()
    }
}

/// Gradient hairline that fades out at both ends (Figma Line 13 / 14).
struct FadingDivider: View {
    var axis: Axis = .horizontal

    var body: some View {
        let stops = [HomeTheme.divider.opacity(0), HomeTheme.divider, HomeTheme.divider.opacity(0)]
        Group {
            if axis == .horizontal {
                LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing).frame(height: 1)
            } else {
                LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom).frame(width: 1)
            }
        }
        .accessibilityHidden(true)
    }
}

/// "Aktivitas Terakhir", "Cara Kerja".
struct HomeSectionTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .onboardingFont(17, weight: .medium, relativeTo: .headline)
            .tracking(-0.17)
            .foregroundStyle(HomeTheme.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Risk gauge

/// The Detail "Scam Score Gauge" (370 × 237) fitted to the width it gets.
struct FittedScoreGauge: View {
    let scan: ScanResult
    var maxWidth: CGFloat = ScoreGauge.size.width
    @Environment(\.locale) private var locale

    var body: some View {
        let height: CGFloat = scan.status == .blocked ? 237 : 219
        Color.clear
            .aspectRatio(ScoreGauge.size.width / height, contentMode: .fit)
            .frame(maxWidth: maxWidth)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    ScoreGauge(score: scan.score, status: scan.status)
                        .scaleEffect(proxy.size.width / ScoreGauge.size.width, anchor: .topLeading)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Risk score"))
            .accessibilityValue(Text(verbatim: Formatters.percent(scan.score, language: AppLanguage(locale: locale))))
    }
}

// MARK: - Recent activity

/// Figma "Aktivitas Terakhir": three cards, then "Lihat Semua". Family Home adds whose site it was.
struct RecentActivity: View {
    enum SeeAllStyle {
        /// Pribadi / Guardian: centred glass text button.
        case centered
        /// protected/Home: blue "Lihat Semua ▶" on the right.
        case trailingLink
    }

    let scans: [ScanResult]
    let language: AppLanguage
    var showsOwner = false
    var seeAllStyle: SeeAllStyle = .centered
    let onOpen: (ScanResult) -> Void
    let onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HomeSectionTitle("Recent activity")
            if scans.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.shield",
                    title: "No risky sites yet",
                    message: "When Shoo warns about or blocks a site, you'll see it here."
                )
                .frame(maxWidth: .infinity, minHeight: 180)
                .homeCard()
                .accessibilityIdentifier("shield.nothingBlocked")
            } else {
                VStack(spacing: 12) {
                    ForEach(scans) { scan in
                        Button { onOpen(scan) } label: {
                            RecentRow(scan: scan, showsOwner: showsOwner, language: language)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.recent.\(scan.id)")
                    }
                }
                seeAll
            }
        }
    }

    @ViewBuilder
    private var seeAll: some View {
        switch seeAllStyle {
        case .centered:
            Button(action: onSeeAll) {
                Text("See all")
                    .onboardingFont(17, weight: .medium, relativeTo: .headline)
                    .foregroundStyle(HomeTheme.ink)
                    .padding(.horizontal, 20)
                    .frame(minWidth: 130, minHeight: 50)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("home.seeAll")
        case .trailingLink:
            Button(action: onSeeAll) {
                HStack(spacing: 6) {
                    Text("See all")
                    Image(systemName: "play.fill").font(.system(size: 13)).accessibilityHidden(true)
                }
                .onboardingFont(17, weight: .medium, relativeTo: .headline)
                .foregroundStyle(HomeTheme.action)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("home.seeAll")
        }
    }
}

private struct RecentRow: View {
    let scan: ScanResult
    let showsOwner: Bool
    let language: AppLanguage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var subtitle: String {
        let when = Formatters.dayAndTime(scan.detectedAt, language: language)
        return showsOwner ? "\(scan.ownerName) · \(when)" : when
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SiteIcon(url: scan.faviconUrl)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: scan.domain)
                    .onboardingFont(17, relativeTo: .body)
                    .tracking(-0.17)
                    .foregroundStyle(HomeTheme.navy)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .truncationMode(.middle)
                Text(verbatim: subtitle)
                    .onboardingFont(13, design: .rounded, relativeTo: .footnote)
                    .foregroundStyle(HomeTheme.secondaryInk)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            HomeStatusChip(badge: ScanBadge(scan: scan))
        }
        .padding(17)
        .homeCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the details"))
    }
}

/// Figma chip: pale fill, thin border, coloured text. Words always there, never colour only.
struct HomeStatusChip: View {
    let badge: ScanBadge
    var large = false

    private var colors: (text: Color, fill: Color, stroke: Color) {
        switch badge {
        case .warning: (HomeTheme.warningText, HomeTheme.warningFill, HomeTheme.warningStroke)
        case .blocked, .verifiedScam: (HomeTheme.dangerText, HomeTheme.dangerFill, HomeTheme.dangerStroke)
        case .markedSafe: (Color(red: 0x1B / 255, green: 0x6E / 255, blue: 0x35 / 255), Color(red: 0xEF / 255, green: 0xFA / 255, blue: 0xF2 / 255),
                           Color(red: 0xC4 / 255, green: 0xEB / 255, blue: 0xCF / 255))
        }
    }

    private var title: LocalizedStringKey { badge == .warning ? "Caution" : badge.title }

    var body: some View {
        let colors = colors
        HStack(spacing: large ? 8 : 4) {
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: large ? 17 : 11)).accessibilityHidden(true)
            Text(title).onboardingFont(large ? 21 : 13, relativeTo: large ? .title3 : .footnote).lineLimit(1)
        }
        .foregroundStyle(colors.text)
        .padding(.horizontal, large ? 16 : 8)
        .padding(.vertical, large ? 8 : 4)
        .background(colors.fill, in: Capsule())
        .overlay(Capsule().stroke(colors.stroke, lineWidth: 1))
        .fixedSize()
    }
}
