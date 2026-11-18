import SwiftUI

/// ON-01: two swipeable slides with Skip and a round Next button (Figma 1352:4375, 1352:4039). First run only.
/// The brand splash before them (Figma 110:3585) is `LaunchSplash`, over the first screen of every launch.
struct SplashView: View {
    let model: OnboardingModel
    @State private var page = 0

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

    var body: some View {
        slidesView
            .environment(\.colorScheme, .light)
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
            .buttonStyle(OnboardingPressButtonStyle())
            .accessibilityLabel(isLast ? Text("Get started") : Text("Next"))
            .accessibilityIdentifier("splash.next")
        }
        .padding(.horizontal, 24)
        // Figma "Horizontal Slider": the 62 pt button ends 66 pt above the screen bottom.
        .padding(.bottom, 32)
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
                    // The asset already ends in Figma "Rectangle 953", the fade into the white page.
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
