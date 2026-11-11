import SwiftUI

/// Colours and type from the onboarding Figma ("ONBOARDING" section, node 141:5987).
/// Light values are Figma's; dark ones are ours (PF-01 Tema), the design has light only.
enum OnboardingTheme {
    static let background = Color.dynamic(0xF5F8FC, dark: 0x0E1116)
    /// Cards and fields.
    static let card = Color.dynamic(0xFFFFFF, dark: 0x1B1F26)
    static let ink = Color.dynamic(0x151617, dark: 0xF2F4F8, contrastLight: 0x000000, contrastDark: 0xFFFFFF)
    static let secondaryInk = Color.dynamic(0x67696C, dark: 0xA3A9B3, contrastLight: 0x45474A, contrastDark: 0xCDD1D8)
    /// Figma's small notes under a field ("*Nama harus terdiri dari maksimal 20 karakter").
    static let noteInk = Color.dynamic(0x191C25, dark: 0xF2F4F8, contrastLight: 0x000000, contrastDark: 0xFFFFFF)
    /// Figma's numbered steps ("Tekan tombol di bawah…").
    static let stepInk = Color.dynamic(0x191D2F, dark: 0xF2F4F8, contrastLight: 0x000000, contrastDark: 0xFFFFFF)
    /// Figma "Body" under every onboarding headline.
    static let bodyInk = Color.dynamic(0x6A717E, dark: 0xA3A9B3, contrastLight: 0x4A505B, contrastDark: 0xCDD1D8)
    static let cardStroke = Color.dynamic(0xD8DFE2, dark: 0x343B46, contrastLight: 0x9AA1AC, contrastDark: 0x6B7380)
    static let selectedStroke = Color.dynamic(0x0EA1DE, dark: 0x3DB8EE)
    static let selectedStrokeProtected = Color.dynamic(0x11D0DA, dark: 0x3FDDE5)
    static let disabledFill = Color.dynamic(0xDBE2E7, dark: 0x2A303A)
    static let placeholder = Color.dynamic(0x939393, dark: 0x7C828C)
    static let error = Color.dynamic(0xC81414, dark: 0xFF6B6B)
    static let link = Color.dynamic(0x0367B6, dark: 0x5EAAF0)
    /// Text on the blue capsule.
    static let onButton = Color.white
    /// Figma style "Gradient/Dark Button"; the design has no dark variant.
    static let buttonGradient = LinearGradient(
        colors: [Color(hex: 0x446EB4), Color(hex: 0x214889)],
        startPoint: .top,
        endPoint: .bottom
    )
    /// Figma frame on the chosen ON-02 avatar.
    static let avatarSelectedStroke = Color(hex: 0x7DE49C)
    static let avatarRing = LinearGradient(
        colors: [Color(red: 0x2C / 255, green: 0xBF / 255, blue: 0x81 / 255), Color(red: 0x8E / 255, green: 0xE9 / 255, blue: 0xEC / 255)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Figma point sizes that still follow Dynamic Type (persona: parents 45–65, PRD §3).
extension View {
    func onboardingFont(
        _ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default,
        tracking: CGFloat? = nil, family: FigmaFont.Family = .display, relativeTo style: Font.TextStyle
    ) -> some View {
        figmaFont(size, weight: weight, design: design, tracking: tracking, family: family, relativeTo: style)
    }

    /// Headline 28 medium + body 17 rounded, centred (every onboarding title in Figma).
    func onboardingTitleStyle() -> some View {
        onboardingFont(28, weight: .medium, relativeTo: .title)
            .tracking(-0.56)
            // Figma "Title 1/Regular": 120 %.
            .figmaLineHeight(33.6, glyphOffset: -2, relativeTo: .title)
            .multilineTextAlignment(.center)
            .foregroundStyle(OnboardingTheme.ink)
            .accessibilityAddTraits(.isHeader)
    }

    /// Figma "Large Title/Regular" over an illustration: 34 semibold, 41 pt lines.
    func onboardingLargeTitleStyle() -> some View {
        onboardingFont(34, weight: .semibold, relativeTo: .largeTitle)
            .tracking(-0.68)
            .figmaLineHeight(41, glyphOffset: -1, relativeTo: .largeTitle)
            .multilineTextAlignment(.center)
            .foregroundStyle(OnboardingTheme.ink)
            .accessibilityAddTraits(.isHeader)
    }

    /// Figma "Body/Regular": 17 rounded, 22 pt lines, under a large title.
    func onboardingLargeBodyStyle() -> some View {
        onboardingFont(17, design: .rounded, tracking: -0.17, relativeTo: .body)
            .multilineTextAlignment(.center)
            .foregroundStyle(OnboardingTheme.bodyInk)
    }

    /// `lineHeight`: Figma "Subhead/Regular", 140 % (23.8).
    func onboardingBodyStyle(lineHeight: CGFloat = 23.8) -> some View {
        onboardingFont(17, design: .rounded, relativeTo: .body)
            // iOS sets the glyphs higher in a tall line than Figma, which centres them.
            .figmaLineHeight(lineHeight, glyphOffset: (lineHeight - 22) / 2, relativeTo: .body)
            .lineSpacing(3)
            .multilineTextAlignment(.center)
            .foregroundStyle(OnboardingTheme.bodyInk)
    }
}

/// Blue pill, 56 pt; grey when disabled ("Selanjutnya" in Figma).
struct OnboardingCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onboardingFont(17, weight: .semibold, relativeTo: .body)
            // Figma disabled "Button": #DBE2E7 with #000 25 % text, the whole button at 75 %.
            .foregroundStyle(isEnabled ? OnboardingTheme.onButton : OnboardingTheme.ink.opacity(0.25))
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 16)
            .background {
                Capsule().fill(isEnabled ? AnyShapeStyle(OnboardingTheme.buttonGradient) : AnyShapeStyle(OnboardingTheme.disabledFill))
            }
            // Figma "Button": inner white 20 %, y 1.
            .overlay {
                Capsule()
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(isEnabled ? 0.2 : 0), .clear], startPoint: .top, endPoint: .center),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            // Figma "Button": #121112 20%, y 8, blur 18.
            .shadow(color: Color(hex: 0x121112, opacity: isEnabled ? 0.2 : 0), radius: 9, y: 8)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.75)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A `.plain` button that gives under the finger like the pill (splash Next, the avatar picker). The look
/// and hit area are the label's own. Reduce Motion: it dims instead of shrinking.
struct OnboardingPressButtonStyle: ButtonStyle {
    @Environment(\.shooReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Round 50 pt back button over the header gradient (Liquid Glass on iOS 26+).
struct OnboardingBackButton: View {
    var identifier = "onboarding.back"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Figma sets the symbol as SF Pro Semibold 19 text ("􀄪"), which draws at the large symbol scale
            // (≈ 23 pt wide), not the default medium one (≈ 18 pt).
            Image(systemName: "arrow.left")
                .font(.system(size: 19, weight: .semibold))
                .imageScale(.large)
                .foregroundStyle(OnboardingTheme.ink)
                .frame(width: 50, height: 50)
                .modifier(GlassCircle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Back"))
        .accessibilityIdentifier(identifier)
    }
}

private struct GlassCircle: ViewModifier {
    @Environment(\.shooReduceGlass) private var reduceGlass

    func body(content: Content) -> some View {
        if reduceGlass {
            // "Kurangi efek kaca": a solid circle.
            content.background(OnboardingTheme.card, in: Circle())
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
    }
}

/// Blue gradient behind the title that fades into the page colour (Figma "Gradient-classic-2 lighter" + "box").
struct OnboardingHeaderBackground: View {
    var height: CGFloat = 252
    /// `OnboardingHeaderGradientTeal` on Figma "To be guardian".
    var image = "OnboardingHeaderGradient"

    var body: some View {
        Image(image)
            .resizable()
            .scaledToFill()
            .frame(height: height, alignment: .bottom)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [OnboardingTheme.background.opacity(0), OnboardingTheme.background], startPoint: .top, endPoint: .bottom)
                    .frame(height: height * 180 / 252)
            }
            .accessibilityHidden(true)
    }
}

/// Name and mode screens: header gradient, back button, title, scrolling content, button pinned at the bottom.
/// `hero` is the 300 pt illustration above the title (invite, ON-04); it sits beside the back button.
struct OnboardingFormPage<Hero: View, Content: View, Footer: View>: View {
    let title: LocalizedStringKey
    /// `nil` where Figma has only the headline (ON-04, Safari Default).
    let message: LocalizedStringKey?
    /// `nil` where there is no way back (e.g. Connect inside onboarding, after the mode is saved).
    let onBack: (() -> Void)?
    /// `id` of a view to keep visible above the button, e.g. the focused field once the keyboard is up.
    var scrollTarget: String?
    @ViewBuilder let hero: Hero
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer
    @State private var footerHeight: CGFloat = 92
    /// The footer's top padding, where the page fades out under it.
    private static var footerFade: CGFloat { 24 }
    /// Figma "Footer": a lone button ends 68 pt above the screen bottom (34 over the home indicator inset);
    /// a button + text link ends 40 pt above it. See `footerEndsWithLink()`.
    private var footerBottom: CGFloat = 34
    /// Figma "Frame 2" side inset: 20 on Atur Nama / Pilih Mode, 24 on Hubungkan Akun, 46 under a hero.
    private var headlineInset: CGFloat = Hero.self == EmptyView.self ? 20 : 46
    private var largeHeadline = false
    private var messageLineHeight: CGFloat = 23.8
    private var messageSpacing: CGFloat?
    private var headerImage = "OnboardingHeaderGradient"

    init(
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        onBack: (() -> Void)?,
        scrollTarget: String? = nil,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.message = message
        self.onBack = onBack
        self.scrollTarget = scrollTarget
        self.hero = hero()
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        hero
                            // The hero sets its own Figma offsets (`OnboardingHeroImage(top:bottom:)`).
                        // Room for the back button, pinned over the page.
                        Color.clear.frame(height: 50)
                    }

                    VStack(spacing: messageSpacing ?? (largeHeadline ? 8 : 4)) {
                        if largeHeadline {
                            Text(title).onboardingLargeTitleStyle()
                            if let message { Text(message).onboardingLargeBodyStyle() }
                        } else {
                            Text(title).onboardingTitleStyle()
                            if let message { Text(message).onboardingBodyStyle(lineHeight: messageLineHeight) }
                        }
                    }
                    .padding(.horizontal, headlineInset)
                    // Figma puts the headline at y 120 with the back button at y 40; the button stays under
                    // the status bar here (62 on a 402 × 874 iPhone), so only 8 pt are left to keep y 120.
                    .padding(.top, Hero.self == EmptyView.self ? 8 : 0)

                    content
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            }
            // The footer is an overlay, not `safeAreaInset`: with the keyboard up, a ScrollView ignores the
            // inset and the field ends up under the button. This margin keeps the last content above it.
            .contentMargins(.bottom, footerHeight, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                Task {
                    // Wait for the keyboard to finish moving the button up.
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(.smooth) { proxy.scrollTo(target, anchor: .bottom) }
                }
            }
            .mask { scrollMask }
        }
        .background(alignment: .top) {
            // Figma "box": 252 pt, 345 where an illustration sits on it.
            OnboardingHeaderBackground(height: Hero.self == EmptyView.self ? 252 : 345, image: headerImage).ignoresSafeArea(edges: .top)
        }
        .background(OnboardingTheme.background.ignoresSafeArea())
        // Outside the scroll view: with the keyboard up the page scrolls and Back has to stay reachable.
        .overlay(alignment: .topLeading) {
            if let onBack {
                OnboardingBackButton(action: onBack)
                    .padding(.leading, 24)
                    .accessibilitySortPriority(1)
            }
        }
        .overlay(alignment: .bottom) {
            // Figma "Footer": 16 between the button and the text link under it.
            VStack(spacing: 16) { footer }
                .padding(.horizontal, 24)
                .padding(.top, Self.footerFade)
                .padding(.bottom, footerBottom)
                .background {
                    // Only the 24 pt above the first row fades; behind the rows it is solid. A fade that
                    // scaled with the footer let a tall one (ON-04's consent box) show the steps scrolled
                    // under it through its own text (QA 2026-11-11 #7).
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [OnboardingTheme.background.opacity(0), OnboardingTheme.background],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: Self.footerFade)
                        OnboardingTheme.background
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear { footerHeight = geometry.size.height }
                            .onChange(of: geometry.size.height) { _, height in footerHeight = height }
                    }
                }
        }
        .environment(\.colorScheme, .light)
    }

    /// A scrolled headline fades out under the back button instead of running through it and the status
    /// bar. A hero sits beside the button by design, so it stays whole.
    @ViewBuilder
    private var scrollMask: some View {
        if Hero.self == EmptyView.self {
            VStack(spacing: 0) {
                Color.clear.frame(height: 50)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 8)
                Color.black.ignoresSafeArea(edges: .bottom)
            }
        } else {
            Color.black.ignoresSafeArea()
        }
    }
}

extension OnboardingFormPage {
    /// The footer ends with a text link ("Lewati", "Terkendala? Tonton Tutorial"): Figma keeps it 40 pt
    /// above the screen bottom, 6 over the home indicator inset.
    /// Figma's side inset for the headline and message (see `headlineInset`).
    func headlineInset(_ inset: CGFloat) -> Self {
        var page = self
        page.headlineInset = inset
        return page
    }

    /// Figma's message line height when it isn't 140 %.
    func messageLineHeight(_ points: CGFloat) -> Self {
        var page = self
        page.messageLineHeight = points
        return page
    }

    /// Headline to message. Figma's headline boxes are taller than their lines on some frames ("Aktifkan
    /// Ekstensi": 38 for one 33 pt line), so the message sits lower there.
    func messageSpacing(_ spacing: CGFloat) -> Self {
        var page = self
        page.messageSpacing = spacing
        return page
    }

    /// The teal header of Figma "To be guardian" (1229:1904).
    func tealHeader() -> Self {
        var copy = self
        copy.headerImage = "OnboardingHeaderGradientTeal"
        return copy
    }

    /// The 34 pt headline and 22 pt message lines of "Lindungi dirimu dan orang terdekat".
    func largeHeadline(_ large: Bool = true) -> Self {
        var page = self
        page.largeHeadline = large
        return page
    }

    func footerEndsWithLink(_ endsWithLink: Bool = true) -> Self {
        var page = self
        page.footerBottom = endsWithLink ? 6 : 34
        return page
    }
}

extension OnboardingFormPage where Hero == EmptyView {
    init(
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        onBack: (() -> Void)?,
        scrollTarget: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.init(title: title, message: message, onBack: onBack, scrollTarget: scrollTarget, hero: { EmptyView() }, content: content, footer: footer)
    }
}

/// 300 pt illustration at the top of an onboarding page (Figma "image 1").
struct OnboardingHeroImage: View {
    let name: String
    /// From the top safe area (62 on the 402 × 874 Figma iPhone) to the image.
    var top: CGFloat = 0
    /// From the image to the headline.
    var bottom: CGFloat = 0

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: 300, height: 300)
            .padding(.top, top)
            .padding(.bottom, bottom)
            .accessibilityHidden(true)
    }
}

/// Red line under a field or the scanner, e.g. "Kode kadaluarsa…" (Figma "Kode Kadaluarsa").
struct OnboardingErrorLabel: View {
    let text: Text
    var systemImage = "exclamationmark.circle"

    var body: some View {
        Label { text } icon: { Image(systemName: systemImage) }
            .onboardingFont(15, design: .rounded, relativeTo: .subheadline)
            .foregroundStyle(OnboardingTheme.error)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Text-only secondary action under the pill ("Lewati", "Nanti saja"; dark for "Terkendala? Tonton Tutorial").
struct OnboardingLinkButtonStyle: ButtonStyle {
    var color = OnboardingTheme.link
    var weight = Font.Weight.medium
    /// Figma's text links ("Lewati", "Terkendala? Tonton Tutorial") are SF Pro Text 15, -2 %.
    var family = FigmaFont.Family.text
    var tracking: CGFloat = -0.3

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onboardingFont(15, weight: weight, tracking: tracking, family: family, relativeTo: .subheadline)
            // Figma: a 20 pt row.
            .figmaLineHeight(20, relativeTo: .subheadline)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            // A 44 pt tall hit area that lays out as the text's own height (Figma's 20 pt row).
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .padding(.vertical, -12)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// The success text rises 8 pt into place 0.15 s after the step slides in. Reduce Motion: a fade only.
private struct SuccessTextEntrance: ViewModifier {
    let isOn: Bool
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(isOn && !shown ? 0 : 1)
            .offset(y: isOn && !shown && !reduceMotion ? 8 : 0)
            .onAppear {
                guard isOn, !shown else { return }
                withAnimation(.smooth(duration: 0.4).delay(0.15)) { shown = true }
            }
    }
}

/// The celebrated success text (`OnboardingSuccessPage.celebrates`): the title rises 16 pt and grows from 94 %
/// on a light spring, the message follows without bounce. Reduce Motion: a 0.2 s fade at the same moment.
private struct CelebrationTextEntrance: ViewModifier {
    let isOn: Bool
    let delay: Double
    let bounces: Bool
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        let waiting = isOn && !shown
        content
            .opacity(waiting ? 0 : 1)
            .offset(y: waiting && !reduceMotion ? 16 : 0)
            .scaleEffect(waiting && !reduceMotion && bounces ? 0.94 : 1)
            .onAppear {
                guard isOn, !shown else { return }
                let animation: Animation = reduceMotion
                    ? .easeInOut(duration: 0.2)
                    : bounces ? .spring(duration: 0.45, bounce: 0.25) : .smooth(duration: 0.45)
                withAnimation(animation.delay(delay)) { shown = true }
            }
    }
}

private struct SuccessCelebrationKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set by `OnboardingSuccessPage(celebrates: true)` for its hero.
    var successCelebration: Bool {
        get { self[SuccessCelebrationKey.self] }
        set { self[SuccessCelebrationKey.self] = newValue }
    }
}

extension View {
    /// The hero's centre piece on a celebrated success page: it pops in, two white rings ripple out behind it
    /// and one confetti burst leaves its centre. Does nothing on a page that doesn't celebrate.
    /// `ringSize`: the rings' starting diameter, about the piece's visible width.
    func successCelebrationHero(ringSize: CGFloat) -> some View {
        modifier(SuccessCelebrationHero(ringSize: ringSize))
    }
}

/// One shot, about 1.2 s: the piece scales 0.6 → 1 on a bouncy spring from 0.1 s; when it lands (0.35 s) two
/// rings grow 0.8 → 2.2 and fade (0.8 s, the second 0.12 s later) and ~28 confetti bits fall away. Transform and
/// opacity only, so the layout is the same as without it. Reduce Motion: a 0.2 s fade, no rings or confetti.
private struct SuccessCelebrationHero: ViewModifier {
    let ringSize: CGFloat
    @Environment(\.successCelebration) private var isOn
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var landed = false
    @State private var ringsArmed = false
    @State private var firstRingOut = false
    @State private var secondRingOut = false
    @State private var confettiStart: Date?

    func body(content: Content) -> some View {
        let waiting = isOn && !landed
        content
            .scaleEffect(waiting && !reduceMotion ? 0.6 : 1)
            .opacity(waiting ? 0 : 1)
            // Behind the piece: the bits burst out from under its edges instead of clumping on its face.
            .background {
                if isOn, !reduceMotion, ringsArmed {
                    ZStack {
                        if let confettiStart { ConfettiBurst(start: confettiStart) }
                        ring(out: firstRingOut)
                        ring(out: secondRingOut)
                    }
                }
            }
            .onAppear(perform: play)
    }

    private func ring(out: Bool) -> some View {
        Circle()
            .strokeBorder(.white, lineWidth: 3)
            .frame(width: ringSize, height: ringSize)
            .scaleEffect(out ? 2.2 : 0.8)
            .opacity(out ? 0 : 0.5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func play() {
        guard isOn, !landed else { return }
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { landed = true }
            return
        }
        withAnimation(.spring(duration: 0.5, bounce: 0.35).delay(0.1)) { landed = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            ringsArmed = true
            confettiStart = .now
            // Let the rings draw once at their start before they grow.
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.easeOut(duration: 0.8)) { firstRingOut = true }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.8)) { secondRingOut = true }
            try? await Task.sleep(for: .milliseconds(Int(ConfettiBurst.life * 1000)))
            // Burst over: drop the canvas so its timeline stops.
            confettiStart = nil
            ringsArmed = false
        }
    }
}

/// ~28 white, teal and yellow bits thrown up from the centre that fall under gravity and fade; gone after `life`.
/// Drawn in one `Canvas`; the `TimelineView` stops when the view is removed.
private struct ConfettiBurst: View {
    let start: Date

    static let life: Double = 0.85
    private static let gravity: Double = 1400

    private struct Bit {
        let velocity: CGVector
        let size: CGSize
        let spin: Double
        let color: Color
    }

    /// The same throw every time (a fixed-seed generator), so the burst looks designed, not noisy.
    private static let bits: [Bit] = {
        var seed: UInt64 = 0x5EED_5100
        func random() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(1 << 53)
        }
        let colors = [Color.white, Color(hex: 0x5FE3D6), Color(hex: 0xFFD84A)]
        return (0..<28).map { index in
            // Up and out: −165° … −15°, 340–640 pt/s.
            let angle = (-165 + 150 * random()) * .pi / 180
            let speed = 340 + 300 * random()
            return Bit(
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                size: CGSize(width: 5 + 3 * random(), height: 7 + 4 * random()),
                spin: (random() - 0.5) * 16,
                color: colors[index % colors.count]
            )
        }
    }()

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { canvas, size in
                let t = context.date.timeIntervalSince(start)
                guard t >= 0, t < Self.life else { return }
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let fade = min(1, (Self.life - t) / 0.3)
                for bit in Self.bits {
                    var piece = canvas
                    piece.opacity = fade
                    piece.translateBy(
                        x: centre.x + bit.velocity.dx * t,
                        y: centre.y + bit.velocity.dy * t + 0.5 * Self.gravity * t * t
                    )
                    piece.rotate(by: .radians(bit.spin * t))
                    let rect = CGRect(x: -bit.size.width / 2, y: -bit.size.height / 2, width: bit.size.width, height: bit.size.height)
                    piece.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(bit.color))
                }
            }
        }
        // Wider than the hero so the bits can fly out; a background, so the layout doesn't change.
        .frame(width: 640, height: 720)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Blue success screen: illustration, white title + message, "Next" at the bottom
/// (Figma "Berhasil Terhubung", "Yeay, kamu berhasil"). Ids: `<idPrefix>.title`, `<idPrefix>.continue`.
struct OnboardingSuccessPage<Hero: View>: View {
    let title: Text
    let message: Text
    let idPrefix: String
    let onContinue: () -> Void
    /// Each success screen has its own Figma gradient.
    var background = "SuccessBackground"
    /// Figma "Berhasil Terhubung" has a 34 pt headline, "Yeay, kamu berhasil" a 28 pt one.
    var largeTitle = true
    /// The title and message rise in a moment after the step slides in (ON-04 passed).
    var revealsText = false
    /// A one-shot celebration (~1.2 s): the hero's `successCelebrationHero` piece pops in with rings and confetti,
    /// the title and message come in one after the other, a heavy tap as the hero lands and a success tap with
    /// the title. "Next" works from the start. Replaces `revealsText`.
    var celebrates = false
    /// Brings the headline to Figma's y under the hero.
    @ViewBuilder let hero: Hero

    @State private var heroLanded = 0
    @State private var titleLanded = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                    .environment(\.successCelebration, celebrates)

                // Figma "Frame 2": Large Title, 8, Body; or Title 1, 4, Subhead.
                VStack(spacing: largeTitle ? 8 : 4) {
                    styledTitle
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("\(idPrefix).title")
                        .modifier(CelebrationTextEntrance(isOn: celebrates, delay: 0.3, bounces: true))
                    styledMessage
                        .foregroundStyle(Color(hex: 0xFAF9FB))
                        .modifier(CelebrationTextEntrance(isOn: celebrates, delay: 0.42, bounces: false))
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .modifier(SuccessTextEntrance(isOn: revealsText && !celebrates))
            }
            .frame(maxWidth: .infinity)
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: heroLanded)
        .sensoryFeedback(.success, trigger: titleLanded)
        .task {
            // The two taps of the celebration, with Reduce Motion too: the hero lands, then the title.
            guard celebrates, heroLanded == 0 else { return }
            try? await Task.sleep(for: .milliseconds(350))
            heroLanded += 1
            try? await Task.sleep(for: .milliseconds(300))
            titleLanded += 1
        }
        .scrollBounceBehavior(.basedOnSize)
        .contentMargins(.bottom, 104, for: .scrollContent)
        .background {
            Image(background)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .overlay(alignment: .bottom) {
            Button("Next", action: onContinue)
                .buttonStyle(OnboardingCapsuleButtonStyle())
                .accessibilityIdentifier("\(idPrefix).continue")
                .padding(.horizontal, 24)
                // Figma "Footer": the button ends 68 pt above the screen bottom.
                .padding(.bottom, 34)
        }
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private var styledTitle: some View {
        if largeTitle {
            title
                .onboardingFont(34, weight: .semibold, relativeTo: .largeTitle)
                .tracking(-0.68)
                .figmaLineHeight(41, glyphOffset: -1, relativeTo: .largeTitle)
        } else {
            title
                .onboardingFont(28, weight: .medium, relativeTo: .title)
                .tracking(-0.56)
                .figmaLineHeight(33.6, glyphOffset: -2, relativeTo: .title)
        }
    }

    @ViewBuilder
    private var styledMessage: some View {
        if largeTitle {
            message.onboardingFont(17, design: .rounded, tracking: -0.17, relativeTo: .body)
        } else {
            message
                .onboardingFont(17, design: .rounded, relativeTo: .body)
                .figmaLineHeight(23.8, glyphOffset: 0.9, relativeTo: .body)
                .lineSpacing(3)
        }
    }
}
