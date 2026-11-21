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
    /// A member whose extension is off (C3): Figma #D9480F, darkened for 4.5:1 at 13 pt.
    static let memberOff = Color(red: 0xC2 / 255, green: 0x41 / 255, blue: 0x0C / 255)
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
struct HomeHeroLayout: Equatable {
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
    /// Where the frame puts the gradient and the "box" fade, when they don't follow the sheet (nil: they end
    /// `backgroundOverhang` under it).
    var backdrop: HeroBackdrop?

    /// Pribadi/Home 435:20058 / 1382:10567: the gradient at y −7.08, the "box" fade 323…443, the sheet at 372.
    static let personal = HomeHeroLayout(backdrop: HeroBackdrop(boxTop: 323))
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
    /// The headline's text box ends here on the frame (`titleTop` + one 34 pt line).
    var titleBottom: CGFloat { titleTop + 34 }
}

/// Figma "Gradient-classic-2 lighter" and "box" in points from the top of the 402 × 874 frame.
struct HeroBackdrop: Equatable {
    /// Top of the 450 pt gradient.
    var imageTop: CGFloat = -7.08
    /// Top and height of the "box" fade into the page (#F3F6F8, clear to solid).
    var boxTop: CGFloat
    var boxHeight: CGFloat = 120
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
    @Environment(\.homeHeroCollapse) private var collapse

    private var textOpacity: Double { max(0, 1 - collapse.progress * 2.5) }

    var body: some View {
        let ringCenter = HomeHeroLayout.ringCenter
        VStack(spacing: 0) {
            ZStack {
                // Scrolled up, the rings fade before they reach the top bar.
                if layout.showsRings { HeroPulse().opacity(max(0, 1 - collapse.progress * 2)) }
                HalftoneShield(isOn: shieldOn, tint: shieldTint)
                    .scaleEffect(layout.shieldScale)
                    .offset(y: layout.shieldTop - (ringCenter - HomeHeroLayout.kacaRise * layout.shieldScale))
                    // `collapsesHomeHero()` draws it on top of the page instead; its room stays here.
                    .opacity(collapse.pinsShield ? 0 : 1)
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
                    // A new headline in an animated update cross-fades (e.g. "You're protected!"); no effect otherwise.
                    .contentTransition(.opacity)
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
            // Scrolled up, the headline fades early: the shrinking shield passes over it on its way to the top bar.
            .opacity(textOpacity)
            accessory()
                .opacity(textOpacity)
        }
        .padding(.bottom, bottomPadding ?? layout.bottomGap - 0.6)
        .frame(maxWidth: .infinity)
        // Where the hero is and what its shield looks like, for `collapsesHomeHero()`.
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HomeHeroSnapshotKey.self,
                    value: HomeHeroSnapshot(frame: proxy.frame(in: .global), style: style, layout: layout,
                                            shieldOn: shieldOn, shieldTint: shieldTint)
                )
            }
        }
        .modifier(HomeHeroBackdropLayer(style: style, layout: layout))
    }
}

/// The hero background around a frame of the hero's size. Reaches up under the navigation bar, the status bar and
/// the pull-to-refresh overscroll, and down under the strip. Shared by the hero and the strip that stays under the
/// top bar once the hero has collapsed.
struct HomeHeroBackdropLayer: ViewModifier {
    let style: HomeHeroStyle
    let layout: HomeHeroLayout

    func body(content: Content) -> some View {
        content.background(alignment: layout.backdrop == nil ? .bottom : .top) {
            if let backdrop = layout.backdrop {
                AnchoredHeroBackground(style: style, backdrop: backdrop)
                    .padding(.top, backdrop.imageTop - HomeHeroLayout.heroTop - AnchoredHeroBackground.overscroll)
            } else {
                HeroBackground(style: style)
                    .padding(.top, -400)
                    .padding(.bottom, -layout.backgroundOverhang)
            }
        }
    }
}

/// The hero background at fixed frame positions (`HeroBackdrop`): the top colour above, the gradient, the page
/// colour under it where the "box" runs on, and the box fade over both.
private struct AnchoredHeroBackground: View {
    /// Room above the frame for the status bar and the pull-to-refresh overscroll.
    static let overscroll: CGFloat = 400
    let style: HomeHeroStyle
    let backdrop: HeroBackdrop
    @Environment(\.heroPull) private var pull

    var body: some View {
        let boxTop = backdrop.boxTop - backdrop.imageTop
        let below = max(0, boxTop + backdrop.boxHeight - 450)
        VStack(spacing: 0) {
            style.topColor.frame(height: Self.overscroll)
            HeroGradient(style: style, stretch: pull)
            HomeTheme.background.frame(height: below)
        }
        .overlay(alignment: .top) {
            LinearGradient(colors: [HomeTheme.fade.opacity(0), HomeTheme.fade], startPoint: .top, endPoint: .bottom)
                .frame(height: backdrop.boxHeight)
                .padding(.top, Self.overscroll + boxTop)
        }
        .accessibilityHidden(true)
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
struct HeroPulse: View {
    var body: some View {
        ZStack {
            // 9 s per disc, so a new one every 3 s: at the loader's 4 s the big Home hero felt hurried and overwhelming.
            SoftPulse(smallest: 120, largest: 368, peak: 0.2, period: 9)
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
struct HeroBackground: View {
    let style: HomeHeroStyle
    @Environment(\.heroPull) private var pull

    var body: some View {
        VStack(spacing: 0) {
            style.topColor
            HeroGradient(style: style, stretch: pull)
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

/// Figma "Top Bar" (435:20380): ⇆ and the profile circle, 50 pt each, 24 pt in from the sides. Figma puts them at
/// y 40, over the clock and battery; here they sit right under the status bar. Drawn over the page (not as toolbar items, which the bar puts 20 pt lower). The navigation bar is
/// hidden on Home: a see-through bar still takes every tap from y 62 to 116, over these buttons. Place as an overlay
/// of the scroll view; it starts at the status bar's bottom edge.
struct HomeTopBar: View {
    /// An inline navigation bar's height: Home has none, so its page keeps this room (`HomeHeroLayout.heroTop`).
    static let barHeight: CGFloat = 54
    var isFamilyShown = false
    /// The user's picked avatar; `nil` (not known yet) draws the neutral person.
    let avatarId: String?
    /// nil: no ⇆ (protected/Home 1115:17282 has the profile circle only).
    let onSwitch: (() -> Void)?
    let onProfile: () -> Void

    var body: some View {
        // Right under the status bar (Figma's y 40 put the circles over the clock and battery).
        HStack(alignment: .top) {
            if let onSwitch {
                HomeSwitchButton(isFamilyShown: isFamilyShown, action: onSwitch)
            }
            Spacer(minLength: 16)
            ProfileAvatarButton(avatarId: avatarId, action: onProfile)
        }
        .padding(.horizontal, 24)
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

/// Top-right 50 pt circle with the user's picked avatar and a 2 pt white rim; opens Profile (PF-01).
private struct ProfileAvatarButton: View {
    let avatarId: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AvatarView(id: avatarId ?? "", size: 50, ring: .init(width: 2))
                .shadow(color: HomeTheme.heroDark.opacity(0.18), radius: 6, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Profile"))
        .accessibilityIdentifier("profileButton")
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

/// Figma "Frame 1618872237": the white 70 % risk panel (338 × 211) with the alert shield, "Situs Mencurigakan!" /
/// "Situs Berbahaya!" and the bar with the score. Guardian/Home draws a second panel inset in it (328 × 205);
/// protected/Home 1115:17294 one.
struct HomeRiskPanel: View {
    let scan: ScanResult
    /// Red "Situs Berbahaya!" (blocked, or marked not safe); otherwise orange "Situs Mencurigakan!".
    let isDanger: Bool
    var layered = false

    private static let titleTop: CGFloat = 129.5

    /// Figma "Kaca": orange 71.6 pt wide 27.1 under the panel's top (Guardian 1382:10989, protected 1363:12167);
    /// red 67.8 at 28.5 on protected/Home 1115:17294. Guardian's blocked frame (1382:10314) is the warning card
    /// scaled to 97 %, so it keeps the orange numbers.
    private var kaca: (width: CGFloat, top: CGFloat) {
        isDanger && !layered ? (67.83, 28.46) : (71.6, 27.1)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Figma: SF Pro Display Semibold 28, +2 %, 34 pt lines, #191D2F.
            Text(isDanger ? "Dangerous site!" : "Suspicious site!")
                .onboardingFont(28, weight: .semibold, tracking: 0.56, relativeTo: .title)
                .figmaLineHeight(34, relativeTo: .title)
                .foregroundStyle(HomeTheme.navy)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 16)
                .padding(.top, Self.titleTop)
            HomeRiskBar(scan: scan)
                .padding(.top, 6.7)
                .padding(.bottom, 6.8)
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .top) { shield }
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22.9, style: .continuous).fill(.white.opacity(0.7))
                if layered {
                    RoundedRectangle(cornerRadius: 22.3, style: .continuous).fill(.white.opacity(0.7))
                        .padding(EdgeInsets(top: 3.1, leading: 4.9, bottom: 3, trailing: 4.9))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The Home shield at Figma's size: "Kaca" `kaca.width` wide (104 pt at scale 1), its top `kaca.top` down.
    private var shield: some View {
        let scale = kaca.width / 104
        let size = HalftoneShield.size
        return HalftoneShield(tint: isDanger ? .redAlert : .orange)
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
            .padding(.top, kaca.top - (size.height * scale / 2 - 61.3 * scale))
            .accessibilityHidden(true)
    }
}

/// Figma "Bar" (1382:10996): one capsule per detection layer that found something (`RiskScoreBar.layerWeights`),
/// by weight and scaled to the score, 1.5 pt apart; a 2 pt tick at the score; the hatched grey track for the
/// rest. 153 pt, the score 8 pt beside it.
struct HomeRiskBar: View {
    let scan: ScanResult

    private static let width: CGFloat = 153
    private static let gap: CGFloat = 1.5
    private static let tickWidth: CGFloat = 2
    private static let colors = [Color(hex: 0xFF9500), Color(hex: 0xF87541), Color(hex: 0xE5483B)]
    private static let tick = Color(hex: 0xE5483B)

    /// Segment widths: the weight per layer, lowest layer first, sharing the score's part of the bar.
    private var segments: [CGFloat] {
        let score = CGFloat(min(max(scan.score, 0), 100)) / 100
        let weights = RiskScoreBar.layerWeights(scan.signals).map(CGFloat.init)
        let parts = weights.isEmpty ? [1] : weights
        let total = parts.reduce(0, +)
        let usable = Self.width - CGFloat(parts.count + 1) * Self.gap - Self.tickWidth
        return parts.map { usable * score * $0 / total }
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: Self.gap) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, width in
                    HatchedBar(fill: Self.colors[min(index, Self.colors.count - 1)], hatch: .white.opacity(0.3))
                        .frame(width: width)
                        .shadow(color: Self.tick.opacity(0.35), radius: 2, y: 1.5)
                }
                RoundedRectangle(cornerRadius: 0.6)
                    .fill(Self.tick)
                    .frame(width: Self.tickWidth, height: 16)
                HatchedBar(fill: Color(hex: 0xE9ECF1), hatch: Color(hex: 0xCFD5DD))
            }
            .frame(width: Self.width, height: 18)
            // Figma: SF Pro Display Semibold 15, +2 %, in a 34 pt line.
            Text(verbatim: "\(scan.score)/100")
                .onboardingFont(15, weight: .semibold, tracking: 0.3, relativeTo: .subheadline)
                .foregroundStyle(HomeTheme.navy)
                .frame(minHeight: 34)
                .fixedSize()
        }
        // Figma "Frame 1618872328" sits 4.5 pt left of the panel's centre.
        .padding(.trailing, 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Risk score"))
        .accessibilityValue(Text(verbatim: "\(scan.score)/100"))
    }
}

/// 10 pt capsule with 0.6 pt 45° hatching every 2.48 pt (Figma "Hatch").
private struct HatchedBar: View {
    let fill: Color
    let hatch: Color

    var body: some View {
        Capsule()
            .fill(fill)
            .overlay {
                Canvas { context, size in
                    var path = Path()
                    var x: CGFloat = -size.height
                    while x < size.width + size.height {
                        path.move(to: CGPoint(x: x, y: size.height))
                        path.addLine(to: CGPoint(x: x + size.height, y: 0))
                        x += 2.48
                    }
                    context.stroke(path, with: .color(hatch), lineWidth: 0.6)
                }
            }
            .clipShape(Capsule())
            .frame(height: 10)
    }
}

// MARK: - Supervised mode

/// Figma "CTA Jadi Guardian" with the "MODE TERAWASI" copy (Pribadi 1382:10600, protected/Home 1382:2393): asks to
/// connect so someone close can check sites again. 354 × 205, 24 pt corners; the teal shield (exported from Figma,
/// 145 × 177 at 209, 19) is clipped by the card. X hides it on this iPhone.
struct SupervisedModeCard: View {
    /// The same card twice on Figma's HOME: "Mode Terawasi" (become protected) and, on a Pribadi Home that has never
    /// been Guardian, "Jadi Penjaga" (2366:10994): only the words and the button change.
    enum Kind {
        case supervised
        case guardian
    }

    var kind: Kind = .supervised
    let onConnect: () -> Void
    let onDismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let fill = LinearGradient(colors: [Color(hex: 0xF3F8FF), Color(hex: 0xE2F8F5)], startPoint: .leading, endPoint: .trailing)
    /// Figma "Tombol / Jadi Guardian": #214889 three quarters down, #446EB4 just above the top.
    private static let button = LinearGradient(colors: [Color(hex: 0x214889), Color(hex: 0x446EB4)],
                                               startPoint: UnitPoint(x: 0.5, y: 0.75), endPoint: UnitPoint(x: 0.5, y: -0.05))

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image("HomeSupervisedShield")
                    .resizable()
                    .frame(width: 145, height: 177)
                    .padding(.top, 19)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                // Figma: SF Pro Rounded Semibold 11, 13 pt lines, 0.06 tracking, #0D8F93.
                Text(kind == .guardian ? "BECOME A GUARDIAN" : "PROTECTED MODE")
                    .onboardingFont(11, weight: .semibold, design: .rounded, tracking: 0.06, relativeTo: .caption2)
                    .figmaLineHeight(13, relativeTo: .caption2)
                    .foregroundStyle(Color(hex: 0x0D8F93))
                    .padding(.top, 22)
                // SF Pro Display Semibold 20, 25 pt lines, -0.45, #151617.
                Text(kind == .guardian ? "Protect the people closest to you" : "Not sure?")
                    .onboardingFont(20, weight: .semibold, tracking: -0.45, relativeTo: .title3)
                    .figmaLineHeight(25, relativeTo: .title3)
                    .foregroundStyle(HomeTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 7)
                // SF Pro Rounded 16, 21 pt lines, -0.31, #6A717E, 206 wide.
                Text(kind == .guardian ? "Help check suspicious sites your family opens." : "Connect so someone you love can check it again")
                    .onboardingFont(16, design: .rounded, tracking: -0.31, relativeTo: .callout)
                    .figmaLineHeight(21, relativeTo: .callout)
                    .foregroundStyle(OnboardingTheme.bodyInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 206, alignment: .leading)
                    .padding(.top, 5)
                Button(action: onConnect) {
                    // SF Pro Display Semibold 17, 22 pt line; 38 pt capsule, 18 pt sides.
                    Text(kind == .guardian ? "Become a Guardian" : "Connect")
                        .onboardingFont(17, weight: .semibold, relativeTo: .headline)
                        .figmaLineHeight(22, relativeTo: .headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 38)
                        .background(Self.button, in: Capsule())
                        // A 38 pt capsule; the touch area still reaches 44.
                        .contentShape(Rectangle().inset(by: -3))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(kind == .guardian ? "home.guardianCard.action" : "home.supervised.connect")
                .padding(.top, 10)
            }
            .padding(.leading, 20)
            .padding(.trailing, 20)
            .padding(.bottom, 22)

            // Figma "Tutup": 28 pt, white 75 % with a white ring, a 9 pt × in 1.6 pt #6A717E strokes; 12 from the corner.
            Button(action: onDismiss) {
                Path { path in
                    path.move(to: .zero); path.addLine(to: CGPoint(x: 9, y: 9))
                    path.move(to: CGPoint(x: 9, y: 0)); path.addLine(to: CGPoint(x: 0, y: 9))
                }
                .stroke(HomeTheme.secondaryInk, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .frame(width: 9, height: 9)
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.75), in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))
            .accessibilityIdentifier(kind == .guardian ? "home.guardianCard.close" : "home.supervised.close")
            .frame(maxWidth: .infinity, alignment: .topTrailing)
            .padding(.top, 4)
            .padding(.trailing, 4)
        }
        .frame(minHeight: 205)
        .background(Self.fill)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 1))
        .figmaCardShadow()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(kind == .guardian ? "home.guardianCard" : "home.supervised")
    }
}

// MARK: - Recent activity

/// Figma "Aktivitas Terakhir": the title, then the cards. "Lihat Semua" sits beside the title on your own Home
/// (Pribadi/Home 435:20058) and under the cards as a glass button on the family's (Guardian/Home/warning 1382:2644).
/// Figma "Empty State · Aktivitas" (Pribadi/Home · Empty Aktivitas 1883:11955): the 128 pt shield, then "Belum ada
/// aktivitas" (SF Pro Rounded Semibold 17, 22 pt lines, #191D2F) and the hint in 13 (18 pt lines, #6A717E) at most 197
/// wide, 2 apart; 20 above, 24 below, 32 at the sides. Straight on the white sheet, no card of its own.
///
/// Motion: the shield springs in and the copy follows 0.12 s / 0.2 s later, 6 pt up; then the shield floats 4 pt
/// (2.4 s each way) while a hairline ring ripples out of it every 2.6 s, as if Shoo keeps watching. Reduce Motion
/// (system, Profile, or `-UITestStillLoops`) keeps only a plain fade.
private struct RecentActivityEmptyState: View {
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var floating = false
    @State private var rippling = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .strokeBorder(Color(hex: 0xC9D2DE), lineWidth: 1)
                    .frame(width: 88, height: 88)
                    .scaleEffect(rippling ? 1.45 : 1)
                    .opacity(rippling ? 0 : 0.7)
                Image("HomeEmptyShield")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128, height: 128)
                    .offset(y: floating ? -4 : 0)
            }
            .frame(width: 128, height: 128)
            .scaleEffect(shown || reduceMotion ? 1 : 0.85)
            .opacity(shown ? 1 : 0)
            .accessibilityHidden(true)
            VStack(spacing: 2) {
                Text("No activity yet")
                    .onboardingFont(17, weight: .semibold, design: .rounded, tracking: -0.43, relativeTo: .body)
                    .figmaLineHeight(22, relativeTo: .body)
                    .foregroundStyle(HomeTheme.navy)
                    .accessibilityAddTraits(.isHeader)
                    .modifier(RiseIn(shown: shown, still: reduceMotion, delay: 0.12))
                Text("When a suspicious site shows up, you'll see it here.")
                    .onboardingFont(13, design: .rounded, tracking: -0.08, relativeTo: .footnote)
                    .figmaLineHeight(18, glyphOffset: 1, relativeTo: .footnote)
                    .foregroundStyle(OnboardingTheme.bodyInk)
                    .frame(maxWidth: 197)
                    .modifier(RiseIn(shown: shown, still: reduceMotion, delay: 0.2))
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 20)
        .padding(.bottom, 24)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        // One VoiceOver stop, and the caller's identifier lands on one element.
        .accessibilityElement(children: .combine)
        .onAppear {
            guard !shown else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.72)) {
                shown = true
            }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true).delay(0.5)) { floating = true }
            withAnimation(.easeOut(duration: 2.6).repeatForever(autoreverses: false).delay(0.5)) { rippling = true }
        }
        .onChange(of: reduceMotion) { _, still in
            guard still else { return }
            // Stop the loops where they rest.
            var stop = Transaction(animation: nil)
            stop.disablesAnimations = true
            withTransaction(stop) {
                floating = false
                rippling = false
            }
        }
    }
}

/// Fades a line in and lifts it 6 pt, `delay` after the shield; under Reduce Motion only the fade.
private struct RiseIn: ViewModifier {
    let shown: Bool
    let still: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || still ? 0 : 6)
            .animation(still ? .easeOut(duration: 0.2) : .easeOut(duration: 0.35).delay(delay), value: shown)
    }
}

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
                RecentActivityEmptyState()
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
    /// Beside the site name these would squeeze it to a few letters ("Penipuan terverifikasi"). At accessibility
    /// sizes every chip would: "bca-verifik / a…ite" next to "Waspada" at AX3 (U-04), so there it always goes under.
    private var badgeGoesBelow: Bool {
        dynamicTypeSize.isAccessibilitySize || badge == .verifiedScam || badge == .markedSafe
    }

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        }
        .foregroundStyle(colors.text)
        .padding(.horizontal, large ? 13.3 : 8)
        .padding(.vertical, large ? 10 : 6)
        .background(colors.fill, in: Capsule())
        .overlay(Capsule().strokeBorder(colors.stroke, lineWidth: large ? 1.24 : 0.75))
        // Its own width at the usual sizes. At accessibility sizes "Penipuan terverifikasi" is wider than the row,
        // and a chip that cannot shrink pushed the whole Home past the screen (U-03): there it wraps instead.
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
    }
}

// MARK: - Pull-down stretch

/// Figma "Gradient-classic-2 lighter", 450 pt high, with its film grain. Pulled down (`stretch`), it grows from its
/// bottom edge by that much, so the overscroll shows more gradient instead of a flat band of `topColor`.
private struct HeroGradient: View {
    let style: HomeHeroStyle
    var stretch: CGFloat = 0

    var body: some View {
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
            .scaleEffect((450 + stretch) / 450, anchor: .bottom)
    }
}

extension EnvironmentValues {
    /// How far the page is pulled down past its top (0 at rest or scrolled up); the hero gradient grows by it.
    @Entry var heroPull: CGFloat = 0
}

extension View {
    /// On Home's scroll view: hands the pull-down distance to the hero (`heroPull`). iOS 18+; before that the
    /// overscroll keeps the flat `topColor`.
    func readsHeroPull() -> some View {
        modifier(HeroPullReader())
    }
}

private struct HeroPullReader: ViewModifier {
    @State private var pull: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollOffset { offset in
                let next = max(0, -offset)
                if next != pull { pull = next }
            }
            .environment(\.heroPull, pull)
    }
}

// MARK: - Collapsing hero

/// What `collapsesHomeHero()` tells the hero while the page scrolls.
struct HomeHeroCollapse: Equatable {
    /// The pinned layer draws the shield; the hero keeps its room empty.
    var pinsShield = false
    /// 0 at rest (or pulled down), 1 once the hero's bottom edge is down to the top bar.
    var progress: CGFloat = 0
}

extension EnvironmentValues {
    @Entry var homeHeroCollapse = HomeHeroCollapse()
}

/// The hero's frame on screen and the look of its shield, handed up to `collapsesHomeHero()`.
struct HomeHeroSnapshot: Equatable {
    var frame: CGRect
    var style: HomeHeroStyle
    var layout: HomeHeroLayout
    var shieldOn: Bool
    var shieldTint: HalftoneShield.Tint
}

struct HomeHeroSnapshotKey: PreferenceKey {
    static var defaultValue: HomeHeroSnapshot? { nil }

    static func reduce(value: inout HomeHeroSnapshot?, nextValue: () -> HomeHeroSnapshot?) {
        value = nextValue() ?? value
    }
}

extension View {
    /// On Home's scroll view, as on Detail: scrolled up, the hero's shield stays on top of the page and shrinks into
    /// the top bar's row, between ⇆ and the profile circle. Once the hero's bottom edge is down to the top bar, a
    /// strip of the hero stays there with the page's round top edge under it, and the page runs on underneath.
    /// Put it before the `HomeTopBar` overlay, so the buttons stay on top.
    func collapsesHomeHero() -> some View {
        modifier(HomeHeroCollapser())
    }
}

private struct HomeHeroCollapser: ViewModifier {
    @State private var hero: HomeHeroSnapshot?
    /// The scroll view's top edge on screen and its safe area (the status bar).
    @State private var frame = ScreenFrame()

    struct ScreenFrame: Equatable {
        var minY: CGFloat = 0
        var safeTop: CGFloat = 0
    }

    func body(content: Content) -> some View {
        let geometry = hero.map { HomeHeroCollapseGeometry(hero: $0, frame: frame) }
        content
            .environment(\.homeHeroCollapse, HomeHeroCollapse(pinsShield: geometry != nil, progress: geometry?.progress ?? 0))
            .onPreferenceChange(HomeHeroSnapshotKey.self) { hero = $0 }
            .onGeometryChange(for: ScreenFrame.self) {
                ScreenFrame(minY: $0.frame(in: .global).minY, safeTop: $0.safeAreaInsets.top)
            } action: { frame = $0 }
            .overlay(alignment: .top) {
                if let hero, let geometry {
                    PinnedHomeHero(hero: hero, geometry: geometry)
                }
            }
    }
}

/// Where the pinned parts go, in points from the top of the screen.
private struct HomeHeroCollapseGeometry {
    /// Rest height of the strip that stays under the top bar: the status bar, the 50 pt buttons and 12 under them.
    let compactHeight: CGFloat
    /// The hero's bottom edge (the top of the page under it).
    let sheetTop: CGFloat
    let progress: CGFloat
    let isPinned: Bool
    let shieldCenterY: CGFloat
    let shieldScale: CGFloat

    /// On Detail the compact shield is 0.3 of its 1.25 scale.
    static let compactShieldScale: CGFloat = 1.25 * 0.3

    init(hero: HomeHeroSnapshot, frame: HomeHeroCollapser.ScreenFrame) {
        // The scroll view starts under the status bar; the screen's top edge is `safeTop` above it.
        let screenTop = frame.minY - frame.safeTop
        let heroTop = hero.frame.minY - screenTop
        // At rest the page starts where the hidden navigation bar would end.
        let restTop = frame.safeTop + HomeTopBar.barHeight
        let offset = restTop - heroTop
        compactHeight = frame.safeTop + 50 + 12
        sheetTop = heroTop + hero.frame.height
        let distance = max(restTop + hero.frame.height - compactHeight, 1)
        progress = min(max(offset / distance, 0), 1)
        isPinned = offset >= distance

        let layout = hero.layout
        // The shield's centre in the hero (`HomeHero`): its Kaca top at `shieldTop` on the Figma frame.
        let restCenterY = restTop - HomeHeroLayout.heroTop + layout.shieldTop + HomeHeroLayout.kacaRise * layout.shieldScale
        let compactCenterY = frame.safeTop + 25
        // Pulled down, the shield moves down with the page as it used to.
        shieldCenterY = offset < 0 ? restCenterY - offset : restCenterY + (compactCenterY - restCenterY) * progress
        shieldScale = layout.shieldScale + (Self.compactShieldScale - layout.shieldScale) * progress
    }
}

/// The shield over the page, cut off at the hero's bottom edge (the page slides over it as before); once pinned, the
/// strip of hero behind it and the page's round top edge under it.
private struct PinnedHomeHero: View {
    let hero: HomeHeroSnapshot
    let geometry: HomeHeroCollapseGeometry

    /// The page's (and the family card's) corner radius.
    private let lip: CGFloat = 22

    var body: some View {
        let shieldHeight = HalftoneShield.size.height
        ZStack(alignment: .top) {
            if geometry.isPinned {
                // The hero as it stood when its bottom edge reached the top bar.
                Color.clear
                    .frame(width: hero.frame.width, height: hero.frame.height)
                    .modifier(HomeHeroBackdropLayer(style: hero.style, layout: hero.layout))
                    .environment(\.heroPull, 0)
                    .offset(y: geometry.compactHeight - hero.frame.height)
            }
            HalftoneShield(isOn: hero.shieldOn, tint: hero.shieldTint)
                .scaleEffect(geometry.shieldScale)
                .offset(y: geometry.shieldCenterY - shieldHeight / 2)
        }
        .frame(maxWidth: .infinity)
        // Pinned, the strip is one corner taller: the hero shows behind the page's round corners, as at rest.
        .frame(height: max(geometry.sheetTop, geometry.compactHeight) + (geometry.isPinned ? lip : 0), alignment: .top)
        .clipped()
        .overlay(alignment: .bottom) {
            if geometry.isPinned {
                UnevenRoundedRectangle(topLeadingRadius: lip, topTrailingRadius: lip, style: .continuous)
                    .fill(HomeTheme.background)
                    .frame(height: lip)
                    // The cards come out of the page colour instead of meeting a hard line.
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [HomeTheme.background, HomeTheme.background.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 16)
                            .offset(y: 16)
                    }
            }
        }
        .allowsHitTesting(false)
        // Pinned, the strip takes the taps meant for the page under it (as a navigation bar would).
        .overlay(alignment: .top) {
            if geometry.isPinned {
                Color.clear
                    .frame(height: geometry.compactHeight)
                    .contentShape(Rectangle())
            }
        }
        .accessibilityHidden(true)
        .ignoresSafeArea(edges: .top)
    }
}
