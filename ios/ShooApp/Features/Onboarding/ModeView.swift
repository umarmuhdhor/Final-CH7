import SwiftUI

/// ON-03: Guardian or Protected, saved for good. Saving registers the device.
struct ModeView: View {
    @Bindable var model: OnboardingModel
    @Environment(\.locale) private var locale

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: 16) {
                Text("How will you use Shoo?")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                ModeCard(
                    mode: .guardian,
                    systemImage: "shield.lefthalf.filled",
                    title: "Protect myself and my family",
                    message: "You get alerts and decide which sites are safe.",
                    selection: $model.selectedMode
                )
                ModeCard(
                    mode: .protected,
                    systemImage: "heart.fill",
                    title: "Protected by others",
                    message: "A family member looks after you.",
                    selection: $model.selectedMode
                )
                Label { Text("You can't change this later.") } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                if model.registrationFailed {
                    Label { Text("Couldn't save. Check your connection and try again.") } icon: {
                        Image(systemName: "wifi.exclamationmark")
                    }
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("mode.error")
                }
            }
        } footer: {
            OnboardingPrimaryButton(title: "Continue", isWorking: model.isWorking) {
                Task { await model.register() }
            }
            .disabled(model.selectedMode == nil || model.isWorking)
            .accessibilityIdentifier("mode.continue")
        }
        .onChange(of: model.registrationFailed) { _, failed in
            if failed {
                AccessibilityNotification.Announcement(L10n.string("Couldn't save. Check your connection and try again.", language: language)).post()
            }
        }
    }
}

private struct ModeCard: View {
    let mode: UserMode
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @Binding var selection: UserMode?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isSelected: Bool { selection == mode }

    var body: some View {
        Button {
            selection = mode
        } label: {
            Group {
                // At accessibility sizes the icons get their own row, so words are not split (QA-A P2-2).
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            icon
                            Spacer()
                            checkmark
                        }
                        texts
                    }
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        icon.frame(width: 40)
                        texts
                        checkmark
                    }
                }
            }
            .multilineTextAlignment(.leading)
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("mode.\(mode.rawValue)")
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.title)
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(message).font(.body).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var checkmark: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .accessibilityHidden(true)
    }
}
