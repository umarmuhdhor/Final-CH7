import SwiftUI

/// The four memoji of the ON-02 picker (Figma "Atur Profilmu"). Ids follow the avatar catalog and are
/// sent as `avatarId` in `POST /devices` (#120).
enum OnboardingAvatar {
    static let ids = ["avatar_01", "avatar_02", "avatar_03", "avatar_04"]

    static func imageName(for id: String) -> String {
        let index = ids.firstIndex(of: id) ?? 0
        return String(format: "Memoji%02d", index + 1)
    }

    /// The memoji asset for a picker id, nil for the rest of the catalog.
    static func memoji(for id: String) -> String? {
        ids.contains(id) ? imageName(for: id) : nil
    }
}

/// ON-02: avatar + name (D-alief-22). 1–20 characters, Next stays disabled until valid.
struct NameView: View {
    @Bindable var model: OnboardingModel
    @FocusState private var focused: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        OnboardingFormPage(
            title: "Set up your profile",
            message: "Choose an avatar and enter your name!",
            onBack: model.goBack,
            scrollTarget: focused ? "name.form" : nil
        ) {
            VStack(spacing: 0) {
                Image(OnboardingAvatar.imageName(for: model.selectedAvatarId))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .accessibilityHidden(true)
                    .padding(.top, 32)

                avatarPicker
                    .padding(.top, 42)

                nameField
                    .padding(.top, 33)
                    .id("name.form")
            }
        } footer: {
            Button {
                model.submitName()
            } label: {
                // An invite link registers right here (Protected), so Next can be busy for a moment.
                ZStack {
                    Text("Next").opacity(model.isWorking ? 0 : 1)
                    if model.isWorking { ProgressView().tint(.white) }
                }
            }
            .buttonStyle(OnboardingCapsuleButtonStyle())
            .disabled(!model.canSubmitName)
            .accessibilityIdentifier("name.continue")
        }
        .onChange(of: visibleProblem) { _, problem in
            guard let problem else { return }
            let key: String.LocalizationValue = problem == .empty ? "Enter your name." : "Use 20 characters or fewer."
            AccessibilityNotification.Announcement(L10n.string(key, language: AppLanguage(locale: locale))).post()
        }
    }

    private var avatarPicker: some View {
        // Figma "Frame 8": four 80 pt avatars, 12 apart, 1 pt wider than the content on each side.
        HStack(spacing: 12) {
            ForEach(Array(OnboardingAvatar.ids.enumerated()), id: \.element) { index, id in
                AvatarChoice(
                    imageName: OnboardingAvatar.imageName(for: id),
                    number: index + 1,
                    isSelected: model.selectedAvatarId == id
                ) {
                    withAnimation(.snappy(duration: 0.25)) { model.selectedAvatarId = id }
                }
                .accessibilityIdentifier("name.avatar.\(index + 1)")
            }
        }
        .padding(.horizontal, -1)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(text: $model.name) {
                    Text("Write your name").foregroundStyle(OnboardingTheme.placeholder)
                }
                // Figma "SF Pro Text Regular 17", -2 %.
                .onboardingFont(17, tracking: -0.34, family: .text, relativeTo: .body)
                .foregroundStyle(OnboardingTheme.ink)
                .tint(OnboardingTheme.ink)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.continue)
                .focused($focused)
                .onSubmit { model.submitName() }
                .accessibilityIdentifier("name.field")

                if !model.name.isEmpty {
                    Button {
                        model.name = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(OnboardingTheme.placeholder)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear name"))
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 6)
            .frame(minHeight: 56)
            .background(OnboardingTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Figma "row": #784650 4%, y 1, blur 2.
            .shadow(color: Color(hex: 0x784650, opacity: 0.04), radius: 1, y: 1)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(visibleProblem == .empty ? Color.red : OnboardingTheme.ink.opacity(0.25), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            // Figma "Atur Nama · nama terlalu panjang": too long shows the limit as a plain note under the
            // field (no red); while typing within the limit there is no note ("Atur Nama · mengetik").
            if visibleProblem == .tooLong {
                Text("*Your name can be up to 20 characters")
                    .onboardingFont(13, design: .rounded, relativeTo: .footnote)
                    .foregroundStyle(OnboardingTheme.noteInk)
                    .accessibilityIdentifier("name.error")
            } else if let message = problemMessage {
                Label { Text(message) } icon: { Image(systemName: "exclamationmark.circle.fill") }
                    .onboardingFont(13, design: .rounded, relativeTo: .footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("name.error")
            }
        }
    }

    private var visibleProblem: NameRule.Problem? {
        model.name.isEmpty ? nil : model.nameProblem
    }

    /// Nothing typed yet is not an error; spaces only or too long is.
    private var problemMessage: LocalizedStringKey? {
        guard let problem = visibleProblem else { return nil }
        switch problem {
        case .empty: return "Enter your name."
        case .tooLong: return "Use 20 characters or fewer."
        }
    }
}

/// One 80 pt memoji (smaller on narrow screens); the chosen one gets the green ring from Figma ("Main Avatar",
/// stroke #2CBF81 → #8EE9EC), the others a white one, both 2.67 pt.
private struct AvatarChoice: View {
    let imageName: String
    let number: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 80, maxHeight: 80)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(OnboardingTheme.avatarRing, lineWidth: 2.67)
                    } else {
                        Circle().strokeBorder(OnboardingTheme.card, lineWidth: 2.67)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Avatar \(number)"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    let env = AppEnvironment.preview()
    env.settings.reset()
    let model = OnboardingModel(environment: env)
    model.skipSplash()
    return NameView(model: model).environment(env)
}
