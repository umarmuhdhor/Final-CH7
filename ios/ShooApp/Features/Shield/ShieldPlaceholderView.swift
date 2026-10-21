import SwiftUI

/// Stand-in for Shield (PR-04 fase 04, GD-01/GD-03 fase 05). Shows the extension status already.
struct ShieldPlaceholderView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = ExtensionStatus.off(lastSeen: nil)
    @State private var notificationStatus = NotificationAuthorization.authorized

    var body: some View {
        EmptyStateView(
            systemImage: status.isActive ? "checkmark.shield.fill" : "shield.slash",
            title: status.isActive ? "Protection is on" : "Safari extension is off",
            message: "Your Shield screen is coming soon."
        )
        .navigationTitle(localized: "Shield")
        .safeAreaInset(edge: .top) {
            if NotificationReminder.isShown(status: notificationStatus, mode: env.settings.mode) {
                NotificationReminderBanner(status: notificationStatus) {
                    Task { notificationStatus = await env.notifications.request() }
                }
                .padding(.horizontal, 16)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            status = env.extensionStatus()
            notificationStatus = await env.notifications.status()
        }
    }
}
