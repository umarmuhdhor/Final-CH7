import SwiftUI

/// ON-05: a short reason, then the system prompt. Guardian must answer (no skip); Protected may skip.
struct NotificationPermissionView: View {
    let model: OnboardingModel

    var body: some View {
        OnboardingPage {
            Group {
                if model.mode == .guardian {
                    OnboardingHeader(
                        systemImage: "bell.badge.fill",
                        title: "Know when your family is at risk",
                        message: "We'll tell you when a family member opens a risky site."
                    )
                } else {
                    OnboardingHeader(
                        systemImage: "bell.fill",
                        title: "Allow notifications",
                        message: "You can turn them on now or later in Settings."
                    )
                }
            }
            .padding(.top, 32)
        } footer: {
            OnboardingPrimaryButton(title: "Allow notifications", isWorking: model.isWorking) {
                Task { await model.requestNotifications() }
            }
            .accessibilityIdentifier("notifications.allow")
            if model.canSkipNotifications {
                Button { model.skipNotifications() } label: {
                    Text("Not now").frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("notifications.skip")
            }
        }
    }
}
