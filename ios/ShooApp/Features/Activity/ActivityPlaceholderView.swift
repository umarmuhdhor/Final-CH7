import SwiftUI

/// Stand-in for Activity (PR-05 fase 04, GD-05 fase 05).
struct ActivityPlaceholderView: View {
    var body: some View {
        EmptyStateView(
            systemImage: "list.bullet.rectangle",
            title: "No activity yet",
            message: "Risky sites you open will show up here."
        )
        .navigationTitle(localized: "Activity")
    }
}
