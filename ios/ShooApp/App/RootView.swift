import SwiftUI

/// Onboarding until it is finished, then the two tabs. Applies the in-app language (PF-01).
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if Self.showsGallery {
                #if DEBUG
                ComponentGalleryView()
                #endif
            } else if env.sessionExpired {
                SessionExpiredView()
            } else if env.settings.onboardingCompleted, env.settings.mode != nil {
                MainTabView()
            } else {
                OnboardingFlow()
            }
        }
        .environment(\.locale, env.settings.language.locale)
        .onChange(of: scenePhase, initial: true) { _, phase in
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
