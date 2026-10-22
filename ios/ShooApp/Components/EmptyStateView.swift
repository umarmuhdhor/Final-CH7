import SwiftUI

/// Centered icon + title + message for lists with nothing to show.
struct EmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey?

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
        } description: {
            if let message { Text(message) }
        }
    }
}

#Preview {
    EmptyStateView(systemImage: "list.bullet.rectangle", title: "No activity yet", message: "Risky sites you open will show up here.")
}
