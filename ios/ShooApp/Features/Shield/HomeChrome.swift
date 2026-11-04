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
    /// Figma "Cara Kerja" step dividers.
    static let stepDivider = Color(red: 0xEE / 255, green: 0xF1 / 255, blue: 0xF5 / 255)
    /// Figma recent-row second line ("Hari ini · 10.42 WIB"), 7.6:1 on white.
    static let rowSubtitle = Color(red: 0x56 / 255, green: 0x4C / 255, blue: 0x51 / 255)
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
    /// Blue: own Home (Pribadi, protected).
    case blue
    /// Teal: the family is protected, or a family site waits.
    case teal
    /// Blue with a teal glow: nobody in the family yet (435:20630).
    case empty

    /// The Figma "Gradient-classic-2 lighter" frame (402 × 450, rectangle and two 134-blur ellipses), exported
    /// without its grain: the blurred shapes are rotated paths SwiftUI can't redraw one to one.
    var gradientImage: String {
        switch self {
        case .blue: "HeroGradientBlue"
        case .teal: "HeroGradientTeal"
        case .empty: "HeroGradientEmpty"
        }
    }

    /// Figma "Ellipse 1", the colour at the top of the frame; fills the pull-to-refresh overscroll above it.
    var topColor: Color {
        switch self {
        case .blue: Color(red: 0x1D / 255, green: 0x82 / 255, blue: 0xD0 / 255)
        case .teal: Color(red: 0x00 / 255, green: 0xB3 / 255, blue: 0xBE / 255)
        case .empty: Color(red: 0x1E / 255, green: 0x78 / 255, blue: 0xBE / 255)
        }
    }
}

/// Where each Figma HOME frame puts the hero parts, in points from the top of the 402 × 874 frame.
struct HomeHeroLayout {
    /// Top of the glass shield ("Kaca").
    var shieldTop: CGFloat = 124
    /// "Shield Kaca Halftone" is 210 wide (1.25 × the onboarding shield); "Shield G" 213.
    var shieldScale: CGFloat = 1.25
    /// Top of the headline's text box.
    var titleTop: CGFloat = 290
    /// From the bottom of the last line of text to the top of the status strip.
    var bottomGap: CGFloat = 49
    var showsRings = true
    var titleWeight: Font.Weight = .semibold
    /// The background runs on under the strip, to Figma y 443 (end of the "box" fade).
    var backgroundOverhang: CGFloat = 72

    /// Pribadi/Home 435:20058 and protected/Home 441:3800.
    static let personal = HomeHeroLayout()
    /// Guardian/Home 435:20373.
    static let family = HomeHeroLayout(shieldTop: 130, titleTop: 308, bottomGap: 31)
    /// Guardian/Home · Keluarga butuh konfirmasi 435:20899.
    static let familyPending = HomeHeroLayout(shieldTop: 126, shieldScale: 1.25 * 133 / 130, titleTop: 308, bottomGap: 31)
    /// Guardian/Home · Belum ada orang 435:20630: no rings, bold headline and a line under it.
    static let familyEmpty = HomeHeroLayout(shieldTop: 104, shieldScale: 1.25 * 133 / 130, titleTop: 284, bottomGap: 32,
                                            showsRings: false, titleWeight: .bold)

    // The ring centre is 204 pt from the top of the frame; the hero itself starts under the navigation bar,
    // 115 pt down on this 402 × 874 screen.
    fileprivate static let ringCenter: CGFloat = 204
    fileprivate static let heroTop: CGFloat = 115.3
    /// Kaca top above the shield's centre at scale 1.
    fileprivate static let kacaRise: CGFloat = 61.3
    /// SwiftUI's text box for 27 pt starts 1.4 pt above Figma's (110 % line height) for the same glyphs.
    fileprivate static let titleBoxShift: CGFloat = 1.4
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
    var layout: HomeHeroLayout = .personal
    /// nil: `layout.bottomGap`.
    var bottomPadding: CGFloat?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        let ringCenter = HomeHeroLayout.ringCenter
        VStack(spacing: 0) {
            ZStack {
                if layout.showsRings { HeroPulse() }
                HalftoneShield(isOn: shieldOn, tint: shieldTint)
                    .scaleEffect(layout.shieldScale)
                    .offset(y: layout.shieldTop - (ringCenter - HomeHeroLayout.kacaRise * layout.shieldScale))
            }
            .frame(height: 236)
            .padding(.top, ringCenter - 118 - HomeHeroLayout.heroTop)

            VStack(spacing: 6) {
                Text(title)
                    .onboardingFont(27, weight: layout.titleWeight, relativeTo: .title)
                    .tracking(-0.27)
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(titleIdentifier)
                if let subtitle {
                    Text(subtitle)
                        .onboardingFont(15, weight: .medium, relativeTo: .subheadline)
                        .tracking(-0.15)
                        .foregroundStyle(titleColor.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, layout.titleTop - HomeHeroLayout.titleBoxShift - (ringCenter + 118))
            accessory()
        }
        .padding(.bottom, bottomPadding ?? layout.bottomGap - 0.6)
        .frame(maxWidth: .infinity)
        // Reaches up under the navigation bar, the status bar and the pull-to-refresh overscroll, and down
        // under the strip.
        .background(alignment: .bottom) {
            HeroBackground(style: style)
                .padding(.top, -400)
                .padding(.bottom, -layout.backgroundOverhang)
        }
    }
}

extension HomeHero where Accessory == EmptyView {
    init(style: HomeHeroStyle, title: LocalizedStringKey, titleColor: Color = .white, titleIdentifier: String,
         subtitle: LocalizedStringKey? = nil, shieldOn: Bool = true, shieldTint: HalftoneShield.Tint = .blue,
         layout: HomeHeroLayout = .personal) {
        self.init(style: style, title: title, titleColor: titleColor, titleIdentifier: titleIdentifier, subtitle: subtitle,
                  shieldOn: shieldOn, shieldTint: shieldTint, layout: layout, accessory: { EmptyView() })
    }
}

/// Figma "Latar Shield": three dashed rings (236 / 300 / 368 pt, 2 on 6 off) over soft white discs that grow
/// out of the shield and fade.
private struct HeroPulse: View {
    var body: some View {
        ZStack {
            SoftPulse(smallest: 120, largest: 368, peak: 0.2)
            ring(368, opacity: 0.16, width: 1)
            ring(300, opacity: 0.28, width: 1.2)
            ring(236, opacity: 0.45, width: 1.5)
        }
        .frame(width: 368, height: 368)
        .frame(height: 236)
        .accessibilityHidden(true)
    }

    /// Figma strokes are inside the ellipse.
    private func ring(_ size: CGFloat, opacity: Double, width: CGFloat) -> some View {
        Circle()
            .strokeBorder(.white.opacity(opacity), style: StrokeStyle(lineWidth: width, lineCap: .butt, dash: [2, 6]))
            .frame(width: size, height: size)
    }
}

/// Figma "Gradient-classic-2 lighter" (y −7…443 of the frame) with its film grain, then the "box" fade
/// (the last 120 pt) into the page. Above the frame the top colour carries on.
private struct HeroBackground: View {
    let style: HomeHeroStyle

    var body: some View {
        VStack(spacing: 0) {
            style.topColor
            Image(style.gradientImage)
                .resizable()
                .frame(height: 450)
                .overlay {
                    Image("HeroTexture")
                        .resizable(resizingMode: .tile)
                        .blendMode(.multiply)
                        .opacity(0.35)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [HomeTheme.fade.opacity(0), HomeTheme.fade], startPoint: .top, endPoint: .bottom)
                        .frame(height: 120)
                }
        }
        .clipped()
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
            // Figma "icon/switch": 14 × 12 inside an 18 pt box.
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HomeTheme.navy)
                .frame(width: 50, height: 50)
                .modifier(HomeGlassCircle())
        }
        .buttonStyle(.plain)
        // Figma: 24 pt from the screen edge; the bar puts the item at 20.
        .padding(.leading, 4)
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
        // Figma: 24 pt from the screen edge; the bar puts the item at 21.
        .padding(.trailing, 3)
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
                Text(verbatim: initial).font(FigmaFont.font(size: fontSize ?? size * 0.41, weight: .semibold, design: .rounded))
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
    /// Figma: Medium for "Bagus!", Regular and grey for "Belum ada anggota".
    var valueWeight: Font.Weight = .medium
    var valueColor: Color = .white

    static let personal = Color(red: 0x1C / 255, green: 0x71 / 255, blue: 0xBA / 255)
    static let family = Color(red: 0x00 / 255, green: 0x9F / 255, blue: 0xA3 / 255)
    /// Figma "Belum ada anggota" #C7C7CE on navy.
    static let mutedValue = Color(red: 0xC7 / 255, green: 0xC7 / 255, blue: 0xCE / 255)
    /// Figma "Frame 1618872173": 62 pt tall; the sheet covers all but its top 37.
    static let height: CGFloat = 62
    static let visibleHeight: CGFloat = 37

    /// Figma glyph U+102DF8 is `app.background.dotted` (iOS 26); older systems get the closest dot grid.
    private static let symbol = UIImage(systemName: "app.background.dotted") != nil ? "app.background.dotted" : "circle.grid.3x3.fill"

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: Self.symbol)
                .font(.system(size: 15))
                .foregroundStyle(Color(red: 0xFA / 255, green: 0xF9 / 255, blue: 0xFB / 255))
                .accessibilityHidden(true)
            (Text(title).foregroundStyle(Color(red: 0xFA / 255, green: 0xF9 / 255, blue: 0xFB / 255))
                + Text(verbatim: " ") + Text(value).fontWeight(valueWeight).foregroundStyle(valueColor))
                .onboardingFont(15, relativeTo: .subheadline)
                .tracking(-0.15)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        // 10 + the 18 pt line + 34 = 62; larger text grows the strip, the sheet keeps covering only the bottom.
        .padding(.bottom, Self.height - Self.visibleHeight + 9)
        .background(fill, in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.securityStatus")
    }
}

extension View {
    /// The white Figma "Status" sheet: 22 pt corners, pulled up over the strip so 37 pt of it shows.
    func homeSheet() -> some View {
        frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.top, StatusStrip.visibleHeight - StatusStrip.height)
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
    /// Figma's Home cards keep the full 237 pt gauge frame whatever the status.
    var reservesBlockedHeight = false
    @Environment(\.locale) private var locale

    var body: some View {
        let height: CGFloat = scan.status == .blocked || reservesBlockedHeight ? 237 : 219
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
                // Figma: "Lihat Semua" sits in the same 12 pt stack as the cards.
                VStack(spacing: 12) {
                    ForEach(scans) { scan in
                        Button { onOpen(scan) } label: {
                            RecentRow(scan: scan, showsOwner: showsOwner, language: language)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.recent.\(scan.id)")
                    }
                    seeAll
                }
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
                    .tracking(-0.17)
                    .foregroundStyle(Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255))
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
                .tracking(-0.17)
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
        // Figma: "Hari ini · 10.42 WIB" on your own Home, "Syahnaz · Hari ini, 10.42" on the family's.
        guard showsOwner else { return Formatters.dayAndTime(scan.detectedAt, language: language) }
        return "\(scan.ownerName) · \(Formatters.dayAndTime(scan.detectedAt, language: language, compact: true))"
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
                    .foregroundStyle(HomeTheme.rowSubtitle)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
            }
            // Figma: the 32 pt title line starts 2 pt below the icon's top.
            .padding(.top, 4)
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
        // Figma "Button": 13 pt text (−1.25 %), 11 pt icon, 4 gap, 8 × 6 padding, 0.75 inside stroke;
        // the large "Status Badge" on protected/Home is the same at 1.66×.
        HStack(spacing: large ? 6.6 : 4) {
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: large ? 17.5 : 11)).accessibilityHidden(true)
            Text(title)
                .onboardingFont(large ? 21.5 : 13, relativeTo: large ? .title3 : .footnote)
                .tracking(large ? -0.27 : -0.16)
                .lineLimit(1)
        }
        .foregroundStyle(colors.text)
        .padding(.horizontal, large ? 13.3 : 8)
        .padding(.vertical, large ? 6.6 : 3.75)
        .background(colors.fill, in: Capsule())
        .overlay(Capsule().strokeBorder(colors.stroke, lineWidth: large ? 1.24 : 0.75))
        .fixedSize()
    }
}
