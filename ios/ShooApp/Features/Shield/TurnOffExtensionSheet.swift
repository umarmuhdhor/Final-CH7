import SwiftUI

/// "Matikan Shoo" (GD-01, Figma "Sheet · Matikan Shoo" 1681:5372): how to switch Shoo off in Safari. Only a guide;
/// Shoo never switches itself off, and Home shows "not protected" once Safari reports the switch off.
/// Opened from the active "Safari extension" row in Profile.
struct TurnOffExtensionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.shooReduceMotion) private var reduceMotion
    @State private var height: CGFloat = 451
    @State private var shown = false

    private let steps = TurnOffExtensionSheet.steps(for: ProcessInfo.processInfo.operatingSystemVersion)

    /// iOS 26.2+ opens Shoo's own page in Safari settings, so the path step is not needed there.
    static func steps(for version: OperatingSystemVersion) -> [LocalizedStringKey] {
        let switchOff: LocalizedStringKey = "Tap Shoo and switch it off."
        if (version.majorVersion, version.minorVersion) >= (26, 2) {
            return ["Tap the button below to open Safari settings.", "Switch the Shoo extension off."]
        }
        let path = ExtensionSetup.steps(for: version).first ?? .openSettingsModern
        return [path.text, switchOff]
    }

    /// Figma: the warning in #D97805, the step numbers on #1E376B.
    private static let warning = Color(hex: 0xD97805)
    private static let stepFill = Color(hex: 0x1E376B)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Capsule().fill(ProfileStyle.sheetGrabber).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 0) {
                Text("Switch off Shoo")
                    .onboardingFont(28, weight: .semibold, relativeTo: .title)
                    .tracking(0.56)
                    .figmaLineHeight(34, relativeTo: .title)
                    .foregroundStyle(HomeTheme.navy)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { dismiss() } label: {
                    Image("ProfileSheetClose")
                        .resizable()
                        .frame(width: 30, height: 30)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(-7)
                .accessibilityLabel(Text("Close"))
                .accessibilityIdentifier("turnOff.close")
            }
            // Figma "Peringatan": the triangle (SF Pro Semibold 17) and SF Pro Rounded 16 / 22, 8 apart.
            HStack(alignment: .top, spacing: 8) {
                warningIcon
                Text("Shoo off means protection stops. Your family won't get warnings anymore.")
                    .onboardingFont(16, design: .rounded, relativeTo: .callout)
                    .figmaLineHeight(22, relativeTo: .callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Self.warning)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("turnOff.warning")
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text(verbatim: "\(index + 1)")
                        .onboardingFont(17, weight: .semibold, relativeTo: .headline)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Self.stepFill, in: Circle())
                        .accessibilityHidden(true)
                    Text(step)
                        .onboardingFont(17, design: .rounded, relativeTo: .body)
                        .figmaLineHeight(22, relativeTo: .body)
                        .foregroundStyle(HomeTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                // The steps arrive one after the other as the sheet settles.
                .opacity(shown ? 1 : 0)
                .offset(y: shown || reduceMotion ? 0 : 8)
                .animation(StateMotion.enter(reduceMotion: reduceMotion).delay(0.08 * Double(index + 1)), value: shown)
            }
            Button("Open Safari settings") {
                Task { await ExtensionSetup.openSettings() }
            }
            .buttonStyle(OnboardingCapsuleButtonStyle())
            .padding(.top, 20)
            .accessibilityIdentifier("turnOff.openSettings")
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(32)
        .presentationBackground(.white)
        .environment(\.colorScheme, .light)
        .sensoryFeedback(.warning, trigger: shown) { _, now in now }
        .onAppear { shown = true }
    }

    @ViewBuilder
    private var warningIcon: some View {
        let icon = Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 17, weight: .semibold))
            .frame(height: 22)
            .accessibilityHidden(true)
        if reduceMotion {
            icon
        } else if #available(iOS 18, *) {
            icon.symbolEffect(.wiggle, options: .nonRepeating, value: shown)
        } else {
            icon.symbolEffect(.bounce, options: .nonRepeating, value: shown)
        }
    }
}

#Preview {
    Color.gray.sheet(isPresented: .constant(true)) { TurnOffExtensionSheet() }
}
