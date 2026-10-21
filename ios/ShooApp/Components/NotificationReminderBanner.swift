import SwiftUI

/// ON-05 reminder on Home when a Guardian has not allowed notifications. Opens the app's notification settings.
struct NotificationReminderBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Notifications are off")
                    .font(.headline)
                Text("You won't hear when your family is at risk.")
                    .font(.subheadline)
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Turn on").frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("reminder.turnOn")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notificationReminder")
    }
}

#Preview {
    NotificationReminderBanner().padding()
}
