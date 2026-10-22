import SwiftUI

/// ON-04 (fallback PRD §10): where the switch is, a Turn on button, a status check whenever the app
/// comes back, and a tutorial video. Reused as a sheet from PR-04 / GD-01 "Turn on" later.
struct TurnOnExtensionView: View {
    /// Re-reads the heartbeat (on appear and when the user is back from Settings).
    var refreshStatus: () -> Void = {}
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVideoPresented = false
    @ScaledMetric(relativeTo: .headline) private var badgeSize: CGFloat = 36
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let steps = ExtensionSetup.steps(for: ProcessInfo.processInfo.operatingSystemVersion)

    var body: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: 24) {
                OnboardingHeader(
                    systemImage: "safari.fill",
                    title: "Turn on Shoo in Safari",
                    message: "Shoo only works after you switch it on."
                )
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 16) {
                            Text(verbatim: "\(index + 1)")
                                .font(.headline)
                                .frame(width: badgeSize, height: badgeSize)
                                .background(Color.accentColor.opacity(0.15), in: Circle())
                                .accessibilityLabel(Text("Step \(index + 1)"))
                            Label {
                                Text(step.text)
                            } icon: {
                                Image(systemName: step.systemImage).foregroundStyle(.tint).accessibilityHidden(true)
                            }
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Label { Text("Shoo is off.") } icon: {
                    Image(systemName: "info.circle.fill")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("extension.offHint")
                // At accessibility text sizes the pinned footer would hide the steps, so the link scrolls.
                if dynamicTypeSize.isAccessibilitySize { videoLink }
            }
        } footer: {
            OnboardingPrimaryButton(title: "Turn on") {
                Task { await ExtensionSetup.openSettings() }
            }
            .accessibilityIdentifier("extension.turnOn")
            if !dynamicTypeSize.isAccessibilitySize { videoLink }
        }
        .onAppear(perform: refreshStatus)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshStatus() }
        }
        .fullScreenCover(isPresented: $isVideoPresented) {
            TutorialVideoPlayer()
        }
    }

    private var videoLink: some View {
        Button { isVideoPresented = true } label: {
            Text("Still can't? Watch the video").frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityIdentifier("extension.video")
    }
}
