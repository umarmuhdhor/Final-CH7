import SwiftUI

/// ON-01: brand splash, then two swipeable slides with Skip and a round Next button (Figma 110:3585, 110:3692, 110:3786).
struct SplashView: View {
    let model: OnboardingModel
    @State private var showsBrand: Bool
    @State private var page = 0
    @Environment(\.shooReduceMotion) private var reduceMotion

    private struct Slide: Identifiable {
        let id: Int
        let image: String
        let title: LocalizedStringKey
        let message: LocalizedStringKey
    }

    private let slides = [
        Slide(
            id: 0,
            image: "OnboardingSlide1",
            title: "Browse calmer, feeling safe.",
            message: "No worrying about dangerous sites. Let Shoo do the work for you and your family."
        ),
        Slide(
            id: 1,
            image: "OnboardingSlide2",
            title: "Looks real, may not be safe.\nLet Shoo check.",
            message: "Shoo checks the pages you open and blocks fake sites before they can hurt you."
        ),
    ]

    private var isLast: Bool { page == slides.count - 1 }

    init(model: OnboardingModel) {
        self.model = model
        _showsBrand = State(initialValue: !model.brandSplashShown)
    }

    var body: some View {
        ZStack {
            if showsBrand {
                BrandSplash()
                    .transition(.opacity)
            } else {
                slidesView
                    .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .light)
        .task {
            guard showsBrand else { return }
            try? await Task.sleep(for: .seconds(1.9))
            model.brandSplashShown = true
            withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.5)) { showsBrand = false }
        }
    }

    private var slidesView: some View {
        GeometryReader { proxy in
            // Figma: 463 of 874 pt is illustration; scales with the screen so small iPhones keep room for text.
            let fullHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            let headerHeight = (fullHeight * 463 / 874).rounded()

            TabView(selection: $page) {
                ForEach(slides) { slide in
                    SlidePage(image: slide.image, title: slide.title, message: slide.message, headerHeight: headerHeight)
                        .accessibilityIdentifier("splash.slide.\(slide.id)")
                        .tag(slide.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom) { controls }
        }
        .background(OnboardingTheme.card.ignoresSafeArea())
    }

    private var controls: some View {
        HStack {
            Button { model.skipSplash() } label: {
                Text("Skip")
                    // Figma "Subhead/Regular".
                    .onboardingFont(17, design: .rounded, relativeTo: .body)
                    .foregroundStyle(OnboardingTheme.ink)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("splash.skip")

            Spacer()

            Button { model.startDemo() } label: {
                Text("Try the demo")
                    .onboardingFont(17, design: .rounded, relativeTo: .body)
                    .foregroundStyle(OnboardingTheme.ink)
                    .underline()
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("splash.demo")

            Spacer()

            Button {
                if isLast {
                    model.skipSplash()
                } else {
                    withAnimation { page += 1 }
                }
            } label: {
                // Figma sets the symbol as SF Pro Rounded Semibold 20 text.
                Image(systemName: "arrow.right")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(OnboardingTheme.onButton)
                    .frame(width: 62, height: 62)
                    // Figma "Button/Full/Circle": gradient only, no shadow.
                    .background(OnboardingTheme.buttonGradient, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLast ? Text("Get started") : Text("Next"))
            .accessibilityIdentifier("splash.next")
        }
        .padding(.horizontal, 24)
        // Figma "Horizontal Slider": the 62 pt button ends 66 pt above the screen bottom.
        .padding(.bottom, 32)
    }
}

/// Figma "Splash Screen" in motion: the light band sweeps in and settles where the frame has it, the logo
/// springs in, then breathes, blinks and twinkles (`ShooBirdLogo`). With Reduce Motion it is the still frame.
private struct BrandSplash: View {
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var logoIn = false

    /// Where Figma "final" has the light stop, and how long the band takes to get there.
    private static let lightStop = 0.46
    private static let sweep = 1.2

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 402
            ZStack {
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let progress = reduceMotion ? 1 : min(context.date.timeIntervalSince(start) / Self.sweep, 1)
                    background(progress: progress, scale: scale)
                }
                logo
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .onAppear(perform: play)
    }

    private func background(progress: Double, scale: CGFloat) -> some View {
        // Ease out: the band slows down as it reaches its place.
        let eased = 1 - pow(1 - progress, 3)
        let light = -0.1 + (Self.lightStop + 0.1) * eased
        let band = Gradient(stops: [
            .init(color: Color(hex: 0x46A7FF), location: 0),
            .init(color: Color(hex: 0xBFE0FF), location: max(light, 0.001)),
            .init(color: Color(hex: 0x46A7FF), location: 1),
        ])
        return ZStack {
            LinearGradient(gradient: band, startPoint: .topLeading, endPoint: .bottomTrailing)
            // Figma "Ellipse 2" and "Ellipse 3": layer blur 115.
            Ellipse()
                .fill(Color(hex: 0x1E78BE))
                .frame(width: 86 * scale, height: 137 * scale)
                .blur(radius: 57 * scale)
                .position(x: (153 + 40 * (1 - eased)) * scale, y: 61 * scale)
            Ellipse()
                .fill(Color(hex: 0x5CC6D8))
                .frame(width: 86 * scale, height: 137 * scale)
                .blur(radius: 57 * scale)
                .position(x: (-21 - 40 * (1 - eased)) * scale, y: 111 * scale)
        }
        .accessibilityHidden(true)
    }

    private var logo: some View {
        ShooBirdLogo()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "Shoo"))
            .accessibilityIdentifier("splash.logo")
            .scaleEffect(logoIn ? 1 : 0.7)
            .opacity(logoIn ? 1 : 0)
    }

    private func play() {
        start = Date()
        guard !reduceMotion else {
            logoIn = true
            return
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.65)) { logoIn = true }
    }
}

private struct SlidePage: View {
    let image: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let headerHeight: CGFloat

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: headerHeight, alignment: .bottom)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        // Figma "Rectangle 953": the picture fades into the white page.
                        LinearGradient(colors: [OnboardingTheme.card.opacity(0), OnboardingTheme.card], startPoint: .top, endPoint: .bottom)
                            .frame(height: headerHeight * 153 / 463)
                    }
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(title).onboardingTitleStyle()
                    Text(message).onboardingBodyStyle()
                }
                .padding(.horizontal, 24)
                .padding(.top, 55)
                .padding(.bottom, 24)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
    }
}

#Preview {
    let env = AppEnvironment.preview()
    env.settings.reset()
    return SplashView(model: OnboardingModel(environment: env)).environment(env)
}
