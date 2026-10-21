import SwiftUI

/// Hides the Detail content while the app is not active, so the app-switcher snapshot iOS writes
/// to disk never holds the scam URL, the owner's name or the evidence screenshot (SECURITY §3 P9, P13).
private struct PrivacyCover: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.overlay {
            if scenePhase != .active {
                ZStack {
                    Rectangle().fill(.background)
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                }
                .ignoresSafeArea()
                .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    func privacyCover() -> some View {
        modifier(PrivacyCover())
    }
}
