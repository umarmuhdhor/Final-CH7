import SwiftUI

/// Placeholder. Team App replaces this with onboarding (ON-01) and the Shield tab.
/// The extension status row is kept for the ON-04 spike; move it into the real screens later.
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastSeen: Date?

    var body: some View {
        VStack(spacing: 16) {
            Text("Shoo")
                .font(.largeTitle.bold())
            Text(statusText)
                .foregroundStyle(isActive ? .green : .secondary)
        }
        .padding()
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
    }

    private var isActive: Bool {
        guard let lastSeen else { return false }
        return Date().timeIntervalSince(lastSeen) < AppGroup.extensionActiveWindow
    }

    private var statusText: String {
        guard let lastSeen else { return "Extension: Off (never seen)" }
        return "Extension: \(isActive ? "Active" : "Off") · last seen \(lastSeen.formatted(.relative(presentation: .named)))"
    }

    private func refresh() {
        lastSeen = AppGroup.defaults.object(forKey: AppGroup.Key.extensionLastSeenAt) as? Date
    }
}

#Preview {
    ContentView()
}
