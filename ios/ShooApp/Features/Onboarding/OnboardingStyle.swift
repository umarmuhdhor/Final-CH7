import SwiftUI

/// Colours and type from the onboarding Figma ("ONBOARDING" section, node 141:5987).
/// Light only: the design has no dark variant yet, so these screens pin `.light`.
enum OnboardingTheme {
    static let background = Color(red: 0xF5 / 255, green: 0xF8 / 255, blue: 0xFC / 255)
    static let ink = Color(red: 0x16 / 255, green: 0x16 / 255, blue: 0x18 / 255)
    static let secondaryInk = Color(red: 0x67 / 255, green: 0x69 / 255, blue: 0x6C / 255)
    static let cardStroke = Color(red: 0xD8 / 255, green: 0xDF / 255, blue: 0xE2 / 255)
    static let selectedStroke = Color(red: 0x0E / 255, green: 0xA1 / 255, blue: 0xDE / 255)
    static let disabledFill = Color(red: 0xDB / 255, green: 0xE2 / 255, blue: 0xE7 / 255)
    static let placeholder = Color(red: 0x93 / 255, green: 0x93 / 255, blue: 0x93 / 255)
    static let buttonGradient = LinearGradient(
        colors: [Color(red: 0x19 / 255, green: 0x1C / 255, blue: 0x25 / 255), Color(red: 0x3C / 255, green: 0x43 / 255, blue: 0x5A / 255)],
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
            .foregroundStyle(.black)
            .accessibilityAddTraits(.isHeader)
    }

    func onboardingBodyStyle() -> some View {
        onboardingFont(15, design: .rounded, relativeTo: .subheadline)
            .lineSpacing(3)
            .multilineTextAlignment(.center)
            .foregroundStyle(.black)
    }
}

/// Dark pill, 56 pt; grey when disabled ("Selanjutnya" in Figma).
struct OnboardingCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onboardingFont(17, weight: .medium, relativeTo: .body)
            .foregroundStyle(isEnabled ? Color.white : Color.black.opacity(0.25))
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
                .foregroundStyle(Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255))
                .frame(width: 50, height: 50)
                .modifier(GlassCircle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Back"))
        .accessibilityIdentifier("onboarding.back")
    }
}

private struct GlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
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
struct OnboardingFormPage<Content: View, Footer: View>: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let onBack: () -> Void
    /// `id` of a view to keep visible above the button, e.g. the focused field once the keyboard is up.
    var scrollTarget: String?
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer
    @State private var footerHeight: CGFloat = 92

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        OnboardingBackButton(action: onBack)
                        Spacer()
                    }
                    .padding(.horizontal, 24)

                    VStack(spacing: 4) {
                        Text(title).onboardingTitleStyle()
                        Text(message).onboardingBodyStyle()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 30)

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
