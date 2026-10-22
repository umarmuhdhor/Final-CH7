import SwiftUI

/// ON-01: three slides, swipeable, page dots, Skip. No statistics (fase 02).
struct SplashView: View {
    let model: OnboardingModel
    @State private var page = 0

    private struct Slide: Identifiable {
        let id: Int
        let systemImage: String
        let title: LocalizedStringKey
        let message: LocalizedStringKey
    }

    private let slides = [
        Slide(id: 0, systemImage: "shield.lefthalf.filled", title: "Shoo keeps scam sites away", message: "Shoo checks the websites you open in Safari."),
        Slide(id: 1, systemImage: "hand.raised.fill", title: "A warning before it's too late", message: "Risky sites get a warning. Scam sites get blocked."),
        Slide(id: 2, systemImage: "person.2.fill", title: "Look after each other", message: "A Guardian looks after up to 3 family members who are Protected."),
    ]

    private var isLast: Bool { page == slides.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { model.skipSplash() } label: {
                    Text("Skip").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityIdentifier("splash.skip")
            }
            .padding(.horizontal, 16)

            TabView(selection: $page) {
                ForEach(slides) { slide in
                    ScrollView {
                        OnboardingHeader(systemImage: slide.systemImage, title: slide.title, message: slide.message)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 32)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    // Ends above the page dots, so large text scrolls instead of running under them (QA-A P2-1).
                    .padding(.bottom, 52)
                    .accessibilityIdentifier("splash.slide.\(slide.id)")
                    .tag(slide.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            OnboardingPrimaryButton(title: isLast ? "Get started" : "Next") {
                if isLast {
                    model.skipSplash()
                } else {
                    withAnimation { page += 1 }
                }
            }
            .accessibilityIdentifier("splash.next")
            .padding(24)
        }
    }
}
