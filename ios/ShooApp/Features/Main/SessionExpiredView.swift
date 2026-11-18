import SwiftUI

/// The server no longer knows this iPhone (401), or its token didn't come along from a backup.
/// MVP answer (SECURITY T3, P1): say so plainly and start onboarding again.
/// Figma "Sesi berakhir" (1665:2991): the switched-off shield on the blue hero, "Tidak terhubung", the line,
/// "iPhone ini belum terlindungi" and "Siapkan lagi".
struct SessionExpiredView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var appeared = 0

    var body: some View {
        StateHeroPage(
            chip: "Not connected",
            title: "Session expired",
            message: "This iPhone isn't connected to Shoo anymore. Set it up again to stay protected.",
            titleIdentifier: "sessionExpired"
        ) {
            // Figma "Shield Kaca Halftone · Mati": 210 × 230, the top 110 pt down the frame.
            HalftoneShield(isOn: false)
                .scaleEffect(1.25)
                .offset(y: -38)
        } content: {
            StateInfoList(rows: [.init(systemImage: "exclamationmark.shield.fill", text: "This iPhone isn't protected yet")])
        } footer: {
            Button("Set up again") { env.restartOnboarding() }
                .buttonStyle(OnboardingCapsuleButtonStyle())
                .accessibilityIdentifier("sessionExpired.restart")
        }
        // Felt as well as read: something needs the person's attention.
        .sensoryFeedback(.warning, trigger: appeared)
        .onAppear { appeared += 1 }
    }
}

#Preview {
    SessionExpiredView().environment(AppEnvironment.preview())
}
