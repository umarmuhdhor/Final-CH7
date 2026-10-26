import SwiftUI

/// ON-04's guide as a sheet (PR-04, GD-01, PF-01). Closes itself once the extension reports in.
struct TurnOnExtensionSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TurnOnExtensionView(refreshStatus: {
                let status = await env.extensionStatus()
                // Closes once Shoo is on and has checked in; until then the sheet says what is left (#135).
                if status.nextStep == nil { dismiss() }
                return status
            })
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("turnOn.close")
                }
            }
        }
    }
}
