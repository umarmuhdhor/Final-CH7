import SwiftUI

/// Colours and type from the onboarding Figma ("ONBOARDING" section, node 141:5987).
/// Light values are Figma's; dark ones are ours (PF-01 Tema), the design has light only.
enum OnboardingTheme {
    static let background = Color.dynamic(0xF5F8FC, dark: 0x0E1116)
    /// Cards and fields.
    static let card = Color.dynamic(0xFFFFFF, dark: 0x1B1F26)
    static let ink = Color.dynamic(0x161618, dark: 0xF2F4F8, contrastLight: 0x000000, contrastDark: 0xFFFFFF)
    static let secondaryInk = Color.dynamic(0x67696C, dark: 0xA3A9B3, contrastLight: 0x45474A, contrastDark: 0xCDD1D8)
    static let cardStroke = Color.dynamic(0xD8DFE2, dark: 0x343B46, contrastLight: 0x9AA1AC, contrastDark: 0x6B7380)
    static let selectedStroke = Color.dynamic(0x0EA1DE, dark: 0x3DB8EE)
    static let disabledFill = Color.dynamic(0xDBE2E7, dark: 0x2A303A)
    static let placeholder = Color.dynamic(0x939393, dark: 0x7C828C)
    static let error = Color.dynamic(0xC81414, dark: 0xFF6B6B)
    static let link = Color.dynamic(0x0A6CB4, dark: 0x5EAAF0)
    /// Text on the dark capsule; the capsule turns light in dark mode.
    static let onButton = Color.dynamic(0xFFFFFF, dark: 0x0E1116)
    static let buttonGradient = LinearGradient(
        colors: [Color.dynamic(0x191C25, dark: 0xF2F4F8), Color.dynamic(0x3C435A, dark: 0xC9D0DB)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let avatarRing = LinearGradient(
        colors: [Color(red: 0x2C / 255, green: 0xBF / 255, blue: 0x81 / 255), Color(red: 0x8E / 255, green: 0xE9 / 255, blue: 0xEC / 255)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Figma point sizes that still follow Dynamic Type (persona: parents 45–65, PRD §3).
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    func onboardingFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, relativeTo style: Font.TextStyle) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design, relativeTo: style))
    }

    /// Headline 30 medium + body 15 rounded, centred (every onboarding title in Figma).
    func onboardingTitleStyle() -> some View {
        onboardingFont(30, weight: .medium, relativeTo: .title)
            .tracking(-0.3)
            .multilineTextAlignment(.center)
            .foregroundStyle(OnboardingTheme.ink)
            .accessibilityAddTraits(.isHeader)
    }

    func onboardingBodyStyle() -> some View {
        onboardingFont(15, design: .rounded, relativeTo: .subheadline)
            .lineSpacing(3)
            .multilineTextAlignment(.center)
            .foregroundStyle(OnboardingTheme.ink)
    }
}

/// Dark pill, 56 pt; grey when disabled ("Selanjutnya" in Figma).
struct OnboardingCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onboardingFont(17, weight: .medium, relativeTo: .body)
            .foregroundStyle(isEnabled ? OnboardingTheme.onButton : OnboardingTheme.ink.opacity(0.3))
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 16)
            .background {
                Capsule().fill(isEnabled ? AnyShapeStyle(OnboardingTheme.buttonGradient) : AnyShapeStyle(OnboardingTheme.disabledFill))
            }
            .shadow(color: .black.opacity(isEnabled ? 0.18 : 0), radius: 12, y: 6)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Round 50 pt back button over the header gradient (Liquid Glass on iOS 26+).
struct OnboardingBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.left")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(OnboardingTheme.ink)
                .frame(width: 50, height: 50)
                .modifier(GlassCircle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Back"))
        .accessibilityIdentifier("onboarding.back")
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

    var body: some View {
        Image("OnboardingHeaderGradient")
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
    let message: LocalizedStringKey
    /// `nil` where there is no way back (e.g. Connect inside onboarding, after the mode is saved).
    let onBack: (() -> Void)?
    /// `id` of a view to keep visible above the button, e.g. the focused field once the keyboard is up.
    var scrollTarget: String?
    @ViewBuilder let hero: Hero
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer
    @State private var footerHeight: CGFloat = 92

    init(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
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
                            .padding(.top, Hero.self == EmptyView.self ? 0 : 18)
                        HStack {
                            if let onBack {
                                OnboardingBackButton(action: onBack)
                            } else {
                                Color.clear.frame(width: 50, height: 50)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                    }

                    VStack(spacing: 4) {
                        Text(title).onboardingTitleStyle()
                        Text(message).onboardingBodyStyle()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, Hero.self == EmptyView.self ? 30 : 14)

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
        }
        .background(alignment: .top) {
            OnboardingHeaderBackground().ignoresSafeArea(edges: .top)
        }
        .background(OnboardingTheme.background.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) { footer }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 12)
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
}

extension OnboardingFormPage where Hero == EmptyView {
    init(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
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

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: 300, height: 300)
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onboardingFont(15, weight: weight, relativeTo: .subheadline)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
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
    @ViewBuilder let hero: Hero

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero

                VStack(spacing: 4) {
                    title
                        .onboardingFont(30, weight: .medium, relativeTo: .title)
                        .tracking(-0.3)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("\(idPrefix).title")
                    message
                        .onboardingFont(15, design: .rounded, relativeTo: .subheadline)
                        .lineSpacing(3)
                        .opacity(0.9)
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.top, 44)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .contentMargins(.bottom, 104, for: .scrollContent)
        .background {
            Image("SuccessBackground")
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
                .padding(.bottom, 12)
        }
        .environment(\.colorScheme, .light)
    }
}
