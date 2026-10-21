import SwiftUI

/// Stand-in for Shield (PR-04 fase 04, GD-01/GD-03 fase 05). Shows the extension status already.
struct ShieldPlaceholderView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = ExtensionStatus.off(lastSeen: nil)

    var body: some View {
        EmptyStateView(
            systemImage: status.isActive ? "checkmark.shield.fill" : "shield.slash",
            title: status.isActive ? "Protection is on" : "Safari extension is off",
            message: "Your Shield screen is coming soon."
        )
        .navigationTitle(localized: "Shield")
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
    }

    private func refresh() {
        status = ExtensionStatus.current()
    }
}
