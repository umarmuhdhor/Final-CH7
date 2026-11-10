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
                .padding(.top, 24)
                .padding(.bottom, footerBottom)
                .background {
                    LinearGradient(
                        stops: [
                            .init(color: OnboardingTheme.background.opacity(0), location: 0),
                            .init(color: OnboardingTheme.background.opacity(0.96), location: 0.3),
                            .init(color: OnboardingTheme.background, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
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
    /// Brings the headline to Figma's y under the hero.
    @ViewBuilder let hero: Hero

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero

                // Figma "Frame 2": Large Title, 8, Body; or Title 1, 4, Subhead.
                VStack(spacing: largeTitle ? 8 : 4) {
                    styledTitle
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("\(idPrefix).title")
                    styledMessage
                        .foregroundStyle(Color(hex: 0xFAF9FB))
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
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
