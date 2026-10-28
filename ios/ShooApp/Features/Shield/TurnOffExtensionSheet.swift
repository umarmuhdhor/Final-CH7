import SwiftUI

/// Guardian Home "Disconnect?" (GD-01): how to switch Shoo off in Safari. Only a guide; Shoo never switches
/// itself off, and Home shows "not protected" once Safari reports the switch off.
struct TurnOffExtensionSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let steps = TurnOffExtensionSheet.steps(for: ProcessInfo.processInfo.operatingSystemVersion)

    /// iOS 26.2+ opens Shoo's own page in Safari settings, so the path step is not needed there.
    static func steps(for version: OperatingSystemVersion) -> [LocalizedStringKey] {
        let switchOff: LocalizedStringKey = "Tap Shoo and switch it off."
        if (version.majorVersion, version.minorVersion) >= (26, 2) {
            return ["Tap the button below to open Safari settings.", "Switch Shoo off."]
        }
        let path = ExtensionSetup.steps(for: version).first ?? .openSettingsModern
        return [path.text, switchOff]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label {
                        Text("While Shoo is off, it can't warn you about scam sites, and your family won't hear about yours.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(HomeTheme.warningText)
                    }
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HomeTheme.warningFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("turnOff.warning")

                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text(verbatim: "\(index + 1)")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(HomeTheme.navy, in: Circle())
                                .accessibilityHidden(true)
                            Text(step)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await ExtensionSetup.openSettings() }
                } label: {
                    Text("Open Safari settings").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(HomeTheme.navy)
                .padding(16)
                .accessibilityIdentifier("turnOff.openSettings")
            }
            .navigationTitle(localized: "Switch off Shoo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("turnOff.close")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
