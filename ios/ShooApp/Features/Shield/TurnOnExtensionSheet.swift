import SwiftUI

/// ON-04's guide as a sheet (PR-04, GD-01, PF-01). Closes itself once the extension reports in.
struct TurnOnExtensionSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TurnOnExtensionView {
                if env.extensionStatus().isActive { dismiss() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("turnOn.close")
                }
            }
        }
    }
}
