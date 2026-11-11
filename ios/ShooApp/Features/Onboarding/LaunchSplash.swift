import SwiftUI

/// ON-01: where the launch splash is. One value per process: a cold launch (from the icon, a push tap or a
/// link) starts at `.showing`; coming back from the background keeps `.done`.
enum LaunchSplashPhase {
    case showing
    /// Fading out over the screen that is already there.
    case leaving
    case done
}

/// ON-01: the brand splash over the first screen of every cold launch (Figma 110:3585). The screen under it is
/// already routed (onboarding step, Home, or Detail from a push or link), so it only fades away: no wait for data,
/// and no route is lost. The two cross-fade; taps and VoiceOver reach the screen once the splash starts to fade.
struct LaunchSplash: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.shooReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// The logo has sprung in by then (spring response 0.6 s); the band is all but settled.
    private static let hold = 0.8
    private static let fade = 0.3

    var body: some View {
        if env.launchSplash != .done {
            BrandSplash()
                .environment(\.colorScheme, .light)
                .opacity(env.launchSplash == .leaving ? 0 : 1)
                // While it fades, taps already reach the screen.
                .allowsHitTesting(env.launchSplash == .showing)
                // VoiceOver stays on the splash until it goes.
                .accessibilityAddTraits(env.launchSplash == .showing ? .isModal : [])
                // Timed from when the app is active: before that iOS may still show its own launch screen.
                .task(id: scenePhase == .active) {
                    guard scenePhase == .active else { return }
                    await play()
                }
        }
    }

    private func play() async {
        try? await Task.sleep(for: .seconds(env.launchSplashHold ?? (reduceMotion ? 0.4 : Self.hold)))
        // Sent to the background meanwhile: the splash starts over when the app is back.
        guard !Task.isCancelled else { return }
        let fade = reduceMotion ? 0.2 : Self.fade
        withAnimation(.easeOut(duration: fade)) {
            env.launchSplash = .leaving
        } completion: {
            env.launchSplash = .done
        }
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

#Preview {
    let env = AppEnvironment.preview()
    env.launchSplash = .showing
    return Color.white.overlay { LaunchSplash() }.environment(env)
}
