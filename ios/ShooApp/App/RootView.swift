import SwiftUI

/// Onboarding until it is finished, then the two tabs, under the launch splash (ON-01). Applies the in-app language (PF-01).
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency

    /// Which top-level screen shows; changing it cross-fades (onboarding → tabs, → "Session expired").
    private enum Phase: Equatable {
        case gallery, sessionExpired, dataConsent, main, onboarding
    }

    private var phase: Phase {
        if Self.showsGallery { return .gallery }
        if env.sessionExpired { return .sessionExpired }
        if env.needsDataConsent { return .dataConsent }
        if env.settings.onboardingCompleted, env.settings.mode != nil { return .main }
        return .onboarding
    }

    private var reducesMotion: Bool {
        env.settings.reduceMotion || systemReduceMotion || env.reducesMotionForUITests
    }

    var body: some View {
        Group {
            switch phase {
            case .gallery:
                #if DEBUG
                ComponentGalleryView()
                #endif
            case .sessionExpired:
                SessionExpiredView().transition(.opacity)
            case .dataConsent:
                DataConsentView(onBack: nil) { env.setDataConsent($0) }.transition(.opacity)
            case .main:
                MainTabView().transition(.opacity)
            case .onboarding:
                OnboardingFlow().transition(.opacity)
            }
        }
        // A cross-fade instead of a hard cut between top-level screens. At launch the phase doesn't change, so the
        // splash's own fade below is the only one.
        .animation(.easeOut(duration: reducesMotion ? 0.2 : 0.3), value: phase)
        // ON-01: the screen is built and routed under the launch splash (its data loads, a push or link lands on
        // Detail). Transparent while the splash shows; the two cross-fade.
        .opacity(env.launchSplash == .showing ? 0 : 1)
        .overlay { LaunchSplash() }
        .environment(\.locale, env.settings.language.locale)
        .environment(\.shooReduceMotion, reducesMotion)
        .environment(\.shooReduceGlass, env.settings.reduceGlass || systemReduceTransparency)
        // PF-01 Tema and Aksesibilitas: theme, text size, bold text and contrast for every window.
        .background(AppearanceOverrides(
            theme: env.settings.theme, textSize: env.settings.textSize,
            boldText: env.settings.boldText, highContrast: env.settings.highContrast
        ))
        .onOpenURL { env.open($0) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // An invite code waits only while the app is in use.
            if phase == .background { env.router.pendingJoinCode = nil }
            guard phase == .active else { return }
            Task { await env.sceneBecameActive() }
        }
    }

    private static var showsGallery: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "debug.gallery")
        #else
        false
        #endif
    }
}

#Preview("Guardian") {
    RootView().environment(AppEnvironment.preview())
}

#Preview("Protected · ID") {
    RootView().environment(AppEnvironment.preview(mode: .protected, language: .indonesian))
}
