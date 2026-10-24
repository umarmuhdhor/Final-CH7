import SwiftUI

/// ON-01: brand splash, then two swipeable slides with Skip and a round Next button (Figma 110:3585, 110:3692, 110:3786).
struct SplashView: View {
    let model: OnboardingModel
    @State private var showsBrand: Bool
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            message: "No need to guess which sites are safe. Let Shoo do the work for you and your family."
        ),
        Slide(
            id: 1,
            image: "OnboardingSlide2",
            title: "Scams look real.\nShoo looks closer.",
            message: "Shoo checks the pages you open in Safari and blocks fake sites before they can hurt you."
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
            try? await Task.sleep(for: .seconds(1.5))
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
        .background(Color.white.ignoresSafeArea())
    }

    private var controls: some View {
        HStack {
            Button { model.skipSplash() } label: {
                Text("Skip")
                    .onboardingFont(14, weight: .medium, relativeTo: .subheadline)
                    .tracking(-0.14)
                    .foregroundStyle(.black)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("splash.skip")

            Spacer()

            Button {
                if isLast {
                    model.skipSplash()
                } else {
                    withAnimation { page += 1 }
                }
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(OnboardingTheme.buttonGradient, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLast ? Text("Get started") : Text("Next"))
            .accessibilityIdentifier("splash.next")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}

/// Full-screen gradient with the white Shoo logo.
private struct BrandSplash: View {
    var body: some View {
        ZStack {
            Image("SplashBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .accessibilityHidden(true)
            Image("ShooLogo")
                .accessibilityLabel(Text(verbatim: "Shoo"))
                .accessibilityIdentifier("splash.logo")
        }
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
                        LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom)
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
