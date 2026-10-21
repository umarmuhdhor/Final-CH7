import SwiftUI

/// Centered icon + title + message for lists with nothing to show.
/// Own layout instead of `ContentUnavailableView`, whose title stays on one line and truncates
/// at accessibility text sizes (QA-A P2-5).
struct EmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(.largeTitle))
                .imageScale(.large)
                .foregroundStyle(.readableSecondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.readableSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        // One VoiceOver stop, and the caller's identifier lands on one element.
        .accessibilityElement(children: .combine)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView(systemImage: "list.bullet.rectangle", title: "No activity yet", message: "Risky sites you open will show up here.")
}
