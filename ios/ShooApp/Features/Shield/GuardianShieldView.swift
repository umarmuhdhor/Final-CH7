import SwiftUI

/// Guardian Shield (GD-01/GD-02): Family mode off → own Home, on → the family's Home (GD-03).
/// The toggle only changes this view; the guardian's Safari stays protected either way.
struct GuardianShieldView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationStatus = NotificationAuthorization.authorized
    @State private var isReminderPresented = false

    var body: some View {
        Group {
            GuardianHomeView(
                repository: env.repository,
                settings: env.settings,
                scope: env.settings.familyModeOn ? .family : .personal,
                extensionStatus: env.extensionStatus
            )
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            notificationStatus = await env.notifications.status()
            isReminderPresented = NotificationReminder.isShown(status: notificationStatus, mode: env.settings.mode)
                && !env.router.notificationReminderShown
        }
        // Push alerts are how the guardian hears about the family: remind while they are off (D-alief-A08).
        // A popup once per launch, so it never takes room on Home (QA-A P2-7).
        .alert(Text("Notifications are off"), isPresented: $isReminderPresented) {
            Button("Turn on") { turnOnNotifications() }
                .accessibilityIdentifier("reminder.turnOn")
            Button("Not now", role: .cancel) {}
                .accessibilityIdentifier("reminder.notNow")
        } message: {
            Text("You won't hear when your family is at risk.")
        }
        .onChange(of: isReminderPresented) { _, isPresented in
            if isPresented { env.router.notificationReminderShown = true }
        }
    }

    /// Never asked yet: the system prompt. Denied: only Settings can change it.
    private func turnOnNotifications() {
        if notificationStatus == .notDetermined {
            Task {
                notificationStatus = await env.notifications.request()
                await env.registerForPushIfAllowed()
            }
        } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
