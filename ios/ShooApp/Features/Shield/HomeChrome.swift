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
    static let dangerText = Color(red: 0xBB / 255, green: 0x16 / 255, blue: 0x16 / 255)
    static let dangerFill = Color(red: 0xFF / 255, green: 0xF4 / 255, blue: 0xF4 / 255)
    static let dangerStroke = Color(red: 0xFF / 255, green: 0xCD / 255, blue: 0xCD / 255)
    static let success = Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
    static let successText = Color(red: 0x1B / 255, green: 0x7F / 255, blue: 0x3A / 255)
    static let offline = Color(red: 0x8E / 255, green: 0x93 / 255, blue: 0x9C / 255)
    /// Figma "Kartu/Scam Terbaru" icon circle, State/Danger/Background.
    static let scamIconFill = Color(red: 0xFD / 255, green: 0xEC / 255, blue: 0xEA / 255)
    /// Figma "Aktif" under a family member: Labels/Secondary, #3C3C43 at 60 %.
    static let memberStatus = Color(red: 0x3C / 255, green: 0x3C / 255, blue: 0x43 / 255).opacity(0.6)
    /// Figma "icon/switch" stroke and the "Lihat Semua" glass button text.
    static let glassInk = Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255)
}

// MARK: - Hero

/// The hero looks of the Figma HOME page.
enum HomeHeroStyle {
    /// Blue: own Home (Pribadi, protected).
    case blue
    /// Teal: the family is protected, or a family site waits.
    case teal
    /// Blue with a teal glow: nobody in the family yet (435:20630).
    case empty
    /// Orange: own Home after a warning (Pribadi/Home · Waspada 955:10369).
    case amber
    /// Red: own Home after a block (Pribadi/Home · Bahaya 955:10467).
    case red
    /// Deep red: a blocked family site waits (Guardian/Home · Bahaya 955:10565).
    case crimson

    /// The Figma "Gradient-classic-2 lighter" frame (402 × 450, rectangle and two 134-blur ellipses): the
    /// blurred shapes are rotated paths SwiftUI can't redraw one to one.
    var gradientImage: String {
        switch self {
        case .blue: "HeroGradientBlue"
        case .teal: "HeroGradientTeal"
        case .empty: "HeroGradientEmpty"
        case .amber: "HeroGradientAmber"
        case .red: "HeroGradientRed"
        case .crimson: "HeroGradientCrimson"
        }
    }

    /// Blue and empty were exported without the film grain; the others carry it in the image (teal re-exported
    /// with its "texture" from Guardian/Home 435:20374).
    var needsGrain: Bool {
        switch self {
        case .blue, .empty: true
        case .teal, .amber, .red, .crimson: false
        }
    }

    /// Figma "Ellipse 1", the colour at the top of the frame; fills the pull-to-refresh overscroll above it.
    var topColor: Color {
        switch self {
        case .blue: Color(red: 0x1D / 255, green: 0x82 / 255, blue: 0xD0 / 255)
        case .teal: Color(red: 0x00 / 255, green: 0xB3 / 255, blue: 0xBE / 255)
        case .empty: Color(red: 0x1E / 255, green: 0x78 / 255, blue: 0xBE / 255)
        case .amber: Color(red: 0xD0 / 255, green: 0x7A / 255, blue: 0x1E / 255)
        case .red: Color(red: 0xD0 / 255, green: 0x1E / 255, blue: 0x28 / 255)
        case .crimson: Color(red: 0xBE / 255, green: 0x08 / 255, blue: 0x12 / 255)
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
    /// From the bottom of the last line of text to the top of the status strip (or the sheet).
    var bottomGap: CGFloat = 49
    var showsRings = true
    /// The background runs on under the strip (or the sheet), to the end of the Figma "box" fade.
    var backgroundOverhang: CGFloat = 72

    /// Pribadi/Home 435:20058 and protected/Home 441:3800.
    static let personal = HomeHeroLayout()
    /// Guardian/Home 435:20373: no strip, the white sheet starts at y 374; the "box" fade ends at 443.
    /// `titleTop` 309 and `bottomGap` 32.67: Figma's 308 and 32, measured against the simulator (the 28 pt glyphs
    /// sit 1 pt higher in SwiftUI's box).
    static let family = HomeHeroLayout(shieldTop: 130, titleTop: 309, bottomGap: 32.67, backgroundOverhang: 69)
    /// Guardian/Home/warning 1382:2599 and /blocked 1382:10314: Kaca 130 wide at y 126.
    static let familyPending = HomeHeroLayout(shieldTop: 126, titleTop: 309, bottomGap: 32.67, backgroundOverhang: 69)
    /// Guardian/Home · Belum ada orang 1382:10466: no rings, a line under the headline; sheet at 377, fade to 436.
    /// `titleTop` 284: Figma's 283, measured against the simulator.
    static let familyEmpty = HomeHeroLayout(shieldTop: 104, shieldScale: 1.25 * 133 / 130, titleTop: 284, bottomGap: 34,
                                            showsRings: false, backgroundOverhang: 59)

    // The ring centre is 204 pt from the top of the frame; the hero itself starts under the navigation bar,
    // 115 pt down on this 402 × 874 screen.
    fileprivate static let ringCenter: CGFloat = 204
    static let heroTop: CGFloat = 115.3
    /// Kaca top above the shield's centre at scale 1.
    fileprivate static let kacaRise: CGFloat = 61.3
    /// SwiftUI's text box for 28 pt starts 1.4 pt above Figma's (34 pt lines) for the same glyphs.
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
                    // Figma "Title 1/Emphasized".
                    .onboardingFont(28, weight: .bold, relativeTo: .title)
                    .tracking(-0.56)
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(titleIdentifier)
                if let subtitle {
                    // Figma "Sub" (1382:10498): SF Pro Rounded 17, 140 % lines, 4 under the headline.
                    Text(subtitle)
                        .onboardingFont(17, design: .rounded, relativeTo: .body)
                        .figmaLineHeight(23.8, relativeTo: .body)
                        .foregroundStyle(titleColor)
                        .multilineTextAlignment(.center)
                        .padding(.top, -3)
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
                    if style.needsGrain {
                        Image("HeroTexture")
                            .resizable(resizingMode: .tile)
                            .blendMode(.multiply)
                            .opacity(0.35)
                    }
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

/// Figma "Top Bar" (435:20380): ⇆ and the profile circle, 50 pt each, 24 pt in from the sides, at y 40 under the
/// Dynamic Island. Drawn over the page (not as toolbar items, which the bar puts 20 pt lower). The navigation bar is
/// hidden on Home: a see-through bar still takes every tap from y 62 to 116, over these buttons. Place as an overlay
/// of the scroll view; it starts at the status bar's bottom edge.
struct HomeTopBar: View {
    /// The buttons' top on the 402 × 874 frame.
    static let figmaTop: CGFloat = 40.7
    /// An inline navigation bar's height: Home has none, so its page keeps this room (`HomeHeroLayout.heroTop`).
    static let barHeight: CGFloat = 54
    let isFamilyShown: Bool
    let name: String?
    let onSwitch: () -> Void
    let onProfile: () -> Void

    var body: some View {
        GeometryReader { proxy in
            // The reader sits at the status bar's bottom edge: move up to y 40 of the screen, never above it.
            let top = proxy.safeAreaInsets.top
            HStack(alignment: .top) {
                HomeSwitchButton(isFamilyShown: isFamilyShown, action: onSwitch)
                Spacer(minLength: 16)
                ProfileInitialButton(name: name, action: onProfile)
            }
            .padding(.horizontal, 24)
            .offset(y: -max(0, top - Self.figmaTop))
        }
        .frame(height: 50, alignment: .top)
    }
}

/// The ⇆ glass circle on its own (the top bar's left button).
private struct HomeSwitchButton: View {
    let isFamilyShown: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Figma "icon/switch" (435:20383): the exported 18 pt vector, #1A1A1A 1.65 pt strokes.
            Image("HomeSwitch")
                .resizable()
                .frame(width: 18, height: 18)
                .foregroundStyle(HomeTheme.glassInk)
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

/// Profile circle as a toolbar item (protected/Home).
struct HomeProfileToolbarItem: ToolbarContent {
    let name: String?
    let action: () -> Void

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarTrailing) { button }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarTrailing) { button }
        }
    }

    private var button: some View {
        // Figma: 24 pt from the screen edge; the bar puts the item at 21.
        ProfileInitialButton(name: name, action: action).padding(.trailing, 3)
    }
}

/// Frosted circle; a solid circle with "Kurangi efek kaca".
/// Figma "Liquid Glass - Regular - Small" lays grey and white fills over the glass, so it reads as light frost on
/// every hero (about 57% light grey over 43% hero colour). The system `glassEffect` and materials make their content
/// vibrant and turn it into the hero's own colour instead (vivid red on "Bahaya"), so the frost is a plain fill.
private struct HomeGlassCircle: ViewModifier {
    @Environment(\.shooReduceGlass) private var reduceGlass

    func body(content: Content) -> some View {
        if reduceGlass {
            content.background(.white, in: Circle())
        } else {
            content.background {
                Circle()
                    .fill(Color(white: 0.9).opacity(0.57))
                    .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1))
            }
        }
    }
}

/// Top-right 50 pt circle with the user's initial; opens Profile (PF-01).
private struct ProfileInitialButton: View {
    let name: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Figma "Profile": SF Pro Display Semibold 20, -0.45.
            InitialAvatar(name: name, size: 50, gradient: [HomeTheme.heroLight, HomeTheme.heroDark], fontSize: 20,
                          design: .default, tracking: -0.45)
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
    /// Members are SF Pro Rounded (Figma "S" / "B"), the profile button SF Pro Display.
    var design: Font.Design = .rounded
    var tracking: CGFloat = 0

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
                Text(verbatim: initial)
                    .font(FigmaFont.font(size: fontSize ?? size * 0.41, weight: .semibold, design: design))
                    .tracking(tracking)
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Sheet

extension View {
    /// The white Figma "Status" / "Konten" sheet over the bottom of the hero: 22 pt corners all round.
    func homeSheet() -> some View {
        frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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

/// "Aktivitas Terakhir", "Orang yang dilindungi", "Cara Kerja": SF Pro Rounded 17, -1 %, 22 pt lines, #6A717E.
struct HomeSectionTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .onboardingFont(17, design: .rounded, tracking: -0.17, relativeTo: .body)
            .figmaLineHeight(22, relativeTo: .body)
            .foregroundStyle(OnboardingTheme.bodyInk)
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

/// Figma "Aktivitas Terakhir": the title, then the cards. "Lihat Semua" sits beside the title on your own Home
/// (Pribadi/Home 435:20058) and under the cards as a glass button on the family's (Guardian/Home/warning 1382:2644).
/// Family Home adds whose site it was.
struct RecentActivity: View {
    enum SeeAllPlacement {
        case header
        case below
    }

    let scans: [ScanResult]
    let language: AppLanguage
    var showsOwner = false
    /// The only sites are already on Home above the list (Protected's blocked card): no "nothing yet" message,
    /// but "See all" still leads to Activity.
    var hasSitesAbove = false
    var seeAllPlacement: SeeAllPlacement = .header
    let onOpen: (ScanResult) -> Void
    let onSeeAll: () -> Void

    private var hasSeeAll: Bool { !scans.isEmpty || hasSitesAbove }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if scans.isEmpty, hasSitesAbove {
                EmptyView()
            } else if scans.isEmpty {
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
                    if seeAllPlacement == .below {
                        GlassSeeAllButton(action: onSeeAll)
                    }
                }
            }
        }
    }

    /// Figma "Aktivitas Terakhir" / "Lihat Semua" (1253:8664, 1253:8665): SF Pro Rounded 17, -1 %, 22 pt lines;
    /// the title grey regular, the link blue bold.
    private var header: some View {
        HStack(spacing: 12) {
            Text("Recent activity")
                .onboardingFont(17, design: .rounded, tracking: -0.17, relativeTo: .body)
                .figmaLineHeight(22, relativeTo: .body)
                .foregroundStyle(OnboardingTheme.bodyInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if hasSeeAll, seeAllPlacement == .header {
                Button(action: onSeeAll) {
                    Text("See all")
                        .onboardingFont(17, weight: .bold, design: .rounded, tracking: -0.17, relativeTo: .body)
                        .figmaLineHeight(22, relativeTo: .body)
                        .foregroundStyle(Color.dynamic(0x175CD3, dark: 0x5EAAF0))
                        // A 22 pt line in Figma; the touch area still reaches 44.
                        .contentShape(Rectangle().inset(by: -12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.seeAll")
            }
        }
    }
}

/// Figma "Button - Liquid Glass - Text" (1382:2644): 130 × 50 capsule, 20 × 16 padding, SF Pro Medium 17
/// (-1 %, 18 pt line), #1A1A1A, centred under the cards.
private struct GlassSeeAllButton: View {
    let action: () -> Void
    @Environment(\.shooReduceGlass) private var reduceGlass

    var body: some View {
        Button(action: action) {
            Text("See all")
                .onboardingFont(17, weight: .medium, tracking: -0.17, relativeTo: .body)
                .figmaLineHeight(18, relativeTo: .body)
                .foregroundStyle(HomeTheme.glassInk)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(minWidth: 130, minHeight: 50)
                .background { background }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("home.seeAll")
    }

    @ViewBuilder
    private var background: some View {
        if reduceGlass {
            Capsule().fill(.white)
        } else if #available(iOS 26.0, *) {
            Capsule().fill(.clear).glassEffect(.regular.interactive(), in: Capsule())
        } else {
            Capsule().fill(.ultraThinMaterial)
        }
    }
}

/// Figma "Update card" (1128:18725): 48 pt icon, the site in SF Pro Rounded 17 and the time in 13 under it,
/// the chip top right; 82 pt tall.
private struct RecentRow: View {
    let scan: ScanResult
    let showsOwner: Bool
    let language: AppLanguage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var badge: ScanBadge { ScanBadge(scan: scan) }
    /// Beside the site name these would squeeze it to a few letters ("Penipuan terverifikasi").
    private var badgeGoesBelow: Bool { badge == .verifiedScam || badge == .markedSafe }

    private var subtitle: String {
        // Figma: "Hari ini · 10.42 WIB" on your own Home, "Syahnaz · Hari ini, 10.42" on the family's.
        guard showsOwner else { return Formatters.dayAndTime(scan.detectedAt, language: language) }
        return "\(scan.ownerName) · \(Formatters.dayAndTime(scan.detectedAt, language: language, compact: true))"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SiteIcon(url: scan.faviconUrl)
            VStack(alignment: .leading, spacing: 0) {
                // Figma: a 24 pt row holding the 22 pt line, then the 18 pt line.
                Text(verbatim: scan.domain)
                    .onboardingFont(17, design: .rounded, tracking: -0.17, relativeTo: .body)
                    .figmaLineHeight(22, relativeTo: .body)
                    .foregroundStyle(HomeTheme.navy)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .truncationMode(.middle)
                    .padding(.vertical, 1)
                Text(verbatim: subtitle)
                    .onboardingFont(13, design: .rounded, tracking: -0.08, relativeTo: .footnote)
                    // The exact 18 pt line puts the glyphs 1 pt higher than Figma does.
                    .figmaLineHeight(18, glyphOffset: 1, relativeTo: .footnote)
                    .foregroundStyle(HomeTheme.rowSubtitle)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                if badgeGoesBelow {
                    HomeStatusChip(badge: badge)
                        .padding(.top, 8)
                }
            }
            // Figma "stack": 42 pt of text centred on the 48 pt icon.
            .padding(.top, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !badgeGoesBelow {
                HomeStatusChip(badge: badge)
                    .padding(.leading, 4)
            }
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
        // Figma "Button" (1128:18733): the exported 16 pt alert icon, 4 gap, SF Pro Rounded 13 (120 %, -0.04),
        // 8 × 6 padding, 0.75 inside stroke, 28 pt tall;
        // the large "Status Badge" on protected/Home: 14 pt semibold, 18 pt icon, 13.3 × 10 padding.
        HStack(spacing: large ? 6.6 : 4) {
            Image("HomeAlertCircle")
                .resizable()
                .frame(width: large ? 18.2 : 16, height: large ? 18.2 : 16)
                .accessibilityHidden(true)
            Text(title)
                .onboardingFont(large ? 14 : 13, weight: large ? .semibold : .regular, design: large ? .default : .rounded,
                                tracking: -0.04, relativeTo: .footnote)
                .figmaLineHeight(large ? 18.2 : 15.6, relativeTo: .footnote)
                .lineLimit(1)
        }
        .foregroundStyle(colors.text)
        .padding(.horizontal, large ? 13.3 : 8)
        .padding(.vertical, large ? 10 : 6)
        .background(colors.fill, in: Capsule())
        .overlay(Capsule().strokeBorder(colors.stroke, lineWidth: large ? 1.24 : 0.75))
        .fixedSize()
    }
}
