import SwiftUI

/// Figma "Pengaturan/Kelola profil · Sheet ubah avatar" (1286:12383), "· Sheet ubah nama" (1286:12451) and
/// "Profile/Pribadi · Konfirmasi hapus akun" (1115:14173). Values are the Figma ones.

extension ProfileStyle {
    /// "Ubah avatar" link and the focused name field's ring and cursor (#3866ED).
    static let accent = Color.dynamic(0x3866ED, dark: 0x7D9BFF, contrastLight: 0x1F47C4, contrastDark: 0xA9BDFF)
    /// Name field fill (#F3F6F8).
    static let fieldFill = Color.dynamic(0xF3F6F8, dark: 0x2A303A, contrastLight: 0xE2E7EE, contrastDark: 0x3A414D)
    /// Sheet grabber (#D9DFE6).
    static let sheetGrabber = Color.dynamic(0xD9DFE6, dark: 0x4A515C)
    /// "Batal" in the delete alert (#ECECF0).
    static let alertCancelFill = Color.dynamic(0xECECF0, dark: 0x2A303A, contrastLight: 0xD6D6DD, contrastDark: 0x3A414D)
}

// MARK: Sheet parts

/// Grabber, title + subtitle and the round close button of a Kelola profil sheet.
struct ProfileSheetHeader: View {
    let title: Text
    let subtitle: Text
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Capsule().fill(ProfileStyle.sheetGrabber).frame(width: 36, height: 5)
                .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    title
                        .profileFont(28, .semibold)
                        .figmaLineHeight(34, relativeTo: .title)
                        .foregroundStyle(ProfileStyle.ink)
                        .accessibilityAddTraits(.isHeader)
                    subtitle
                        .profileBody()
                        .foregroundStyle(ProfileStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) {
                    Image("ProfileSheetClose")
                        .resizable()
                        .frame(width: 30, height: 30)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // The 44 pt tap area around Figma's 30 pt button.
                .padding(-7)
                .accessibilityLabel(Text("Close"))
                .accessibilityIdentifier("profile.sheet.close")
            }
        }
    }
}

/// Figma "Button" in the Kelola profil sheets: dark blue capsule, a white compass and "Simpan" (54 pt).
struct ProfileSaveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            // The export keeps the glyph's shadow, so it is 26 × 28 around a 22 pt frame.
            Image("ProfileSaveIcon")
                .resizable()
                .frame(width: 26, height: 28)
                .offset(y: 3)
                .frame(width: 22, height: 22)
                .opacity(isEnabled ? 1 : 0)
                .accessibilityHidden(true)
            configuration.label
                .profileFont(17, .semibold)
                .figmaLineHeight(22, relativeTo: .body)
                // Figma: black 20 %, y 4, blur 4 under the label.
                .shadow(color: .black.opacity(isEnabled ? 0.2 : 0), radius: 2, y: 4)
        }
        .foregroundStyle(isEnabled ? Color.white : ProfileStyle.secondary)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(isEnabled ? AnyShapeStyle(ModeOfferCard.button) : AnyShapeStyle(ProfileStyle.disabledFill), in: Capsule())
        .overlay(Capsule().strokeBorder(isEnabled ? Color(hex: 0x191D2F) : .clear, lineWidth: 1.5))
        .opacity(configuration.isPressed ? 0.85 : 1)
        .contentShape(Capsule())
    }
}

/// The sheet chrome: 8 pt above the grabber, 24 at the sides, 40 under the button, r 32, sized to its content.
private struct ProfileSheetChrome: ViewModifier {
    @State private var height: CGFloat = 300

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 24)
            .padding(.top, 8)
            // Figma's 40 pt includes the home indicator's 34 pt safe area.
            .padding(.bottom, 6)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .presentationDetents([.height(height)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(32)
            .presentationBackground(ProfileStyle.card)
    }
}

// MARK: Ubah avatar

/// The four ON-02 memoji in 66 pt tiles; the chosen one has a gradient ring and a check. "Simpan" saves.
struct AvatarPickerSheet: View {
    let current: String
    let isWorking: Bool
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String

    /// Figma tiles: Ungu, Pink, Oranye, Biru (avatar_01, 03, 02, 04).
    private static let order = ["avatar_01", "avatar_03", "avatar_02", "avatar_04"].filter(OnboardingAvatar.ids.contains)

    init(current: String, isWorking: Bool, onSave: @escaping (String) -> Void) {
        self.current = current
        self.isWorking = isWorking
        self.onSave = onSave
        _selected = State(initialValue: current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ProfileSheetHeader(title: Text("Change avatar"), subtitle: Text("Pick a character.")) { dismiss() }
            HStack(spacing: 6) {
                ForEach(Array(Self.order.enumerated()), id: \.element) { index, id in
                    Button { selected = id } label: { tile(id) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Avatar \(index + 1)"))
                        .accessibilityAddTraits(id == selected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityIdentifier("avatar.\(id)")
                }
            }
            Button {
                if selected == current { dismiss() } else { onSave(selected) }
            } label: {
                if isWorking { ProgressView().tint(.white) } else { Text("Save") }
            }
            .buttonStyle(ProfileSaveButtonStyle())
            .disabled(isWorking)
            .accessibilityIdentifier("profile.avatar.save")
        }
        .modifier(ProfileSheetChrome())
    }

    /// Figma "Tile": a 58 pt avatar in a 66 pt tile; ring and check on the chosen one.
    private func tile(_ id: String) -> some View {
        AvatarView(id: id, size: 58)
            .frame(width: 66, height: 66)
            .overlay {
                if id == selected {
                    Image("ProfileAvatarRing").resizable().frame(width: 66, height: 66)
                }
            }
            .overlay(alignment: .topLeading) {
                if id == selected {
                    Image("ProfileAvatarCheck").resizable().frame(width: 22, height: 22).offset(x: 44, y: 44)
                }
            }
            .contentShape(Circle())
    }
}

// MARK: Ubah nama

/// Name field with a clear button and a character counter; the onboarding rule (1–20 characters).
struct NameSheet: View {
    @Bindable var model: ProfileModel
    let subtitle: Text
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @FocusState private var isFocused: Bool

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ProfileSheetHeader(title: Text("Change name"), subtitle: subtitle) { dismiss() }
            VStack(alignment: .leading, spacing: 8) {
                field
                HStack(alignment: .top, spacing: 8) {
                    if let message {
                        message
                            .foregroundStyle(Color.readableRed)
                            .accessibilityIdentifier("profile.error")
                    }
                    Spacer(minLength: 0)
                    Text(verbatim: "\(model.nameDraft.count)/\(NameRule.maxLength)")
                        .foregroundStyle(model.nameProblem == .tooLong ? Color.readableRed : ProfileStyle.secondary)
                        .accessibilityLabel(Text("\(model.nameDraft.count) of \(NameRule.maxLength) characters"))
                }
                .profileCaption()
                .padding(.trailing, 4)
            }
            Button { Task { await save() } } label: {
                if model.isWorking { ProgressView().tint(.white) } else { Text("Save") }
            }
            .buttonStyle(ProfileSaveButtonStyle())
            .disabled(saveDisabled)
            .accessibilityIdentifier("profile.saveName")
        }
        .modifier(ProfileSheetChrome())
        .onAppear { isFocused = true }
        .onChange(of: model.nameError) { _, message in
            if let message { announce(message) }
        }
    }

    /// Figma "Text field (fokus)": #F3F6F8, r 16, 56 pt, a 1.5 pt #3866ED ring while focused.
    private var field: some View {
        HStack(spacing: 0) {
            // The label is the sheet's own title word, so Voice Control "Tap Name" works (WCAG 2.5.3).
            TextField(text: $model.nameDraft) { Text("Name") }
                .profileBody()
                .foregroundStyle(ProfileStyle.ink)
                .tint(ProfileStyle.accent)
                .textContentType(.givenName)
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit { Task { await save() } }
                .accessibilityHint(Text("1 to 20 characters"))
                .accessibilityIdentifier("profile.name")
            if !model.nameDraft.isEmpty {
                Button { model.nameDraft = "" } label: {
                    Image("ProfileFieldClear")
                        .resizable()
                        .frame(width: 18, height: 18)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -13)
                .padding(.trailing, -13)
                .accessibilityLabel(Text("Clear name"))
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .background(ProfileStyle.fieldFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(ProfileStyle.accent, lineWidth: 1.5)
                .opacity(isFocused ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }

    private var message: Text? {
        switch model.nameProblem {
        case .empty: return Text("Enter a name.")
        case .tooLong: return Text("Use 20 characters or fewer.")
        case nil: return model.nameError.map { Text(verbatim: L10n.string($0, language: language)) }
        }
    }

    private var saveDisabled: Bool {
        model.nameDraft == model.profile?.name || model.nameProblem != nil || model.isWorking
    }

    private func save() async {
        guard !saveDisabled else { return }
        if await model.saveName() {
            announce("Name saved")
            dismiss()
        }
    }

    private func announce(_ message: String.LocalizationValue) {
        AccessibilityNotification.Announcement(L10n.string(message, language: language)).post()
    }
}

// MARK: Hapus akun

extension View {
    /// "Hapus akun?" alert (Profile and Kelola profil).
    func deleteAccountSheet(model: ProfileModel, isPresented: Binding<Bool>) -> some View {
        modifier(DeleteAccountAlert(model: model, isPresented: isPresented))
    }
}

/// Figma "Alert/Hapus akun" (1115:14268): a 320 pt card over a #0A0F1F 38 % dim, "Batal" and a red "Hapus".
private struct DeleteAccountAlert: ViewModifier {
    let model: ProfileModel
    @Binding var isPresented: Bool
    @Environment(\.locale) private var locale
    @AccessibilityFocusState private var isTitleFocused: Bool

    func body(content: Content) -> some View {
        content
            // The screen under the dim is out of reach, so VoiceOver and the audit skip it too.
            .accessibilityHidden(isPresented)
            .overlay {
                if isPresented {
                    ZStack {
                        Color(hex: 0x0A0F1F, opacity: 0.38)
                            .ignoresSafeArea()
                            .accessibilityHidden(true)
                        card
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: isPresented)
    }

    private var card: some View {
        let language = AppLanguage(locale: locale)
        return VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("Delete account?")
                    .profileFont(17, .semibold)
                    .figmaLineHeight(22, relativeTo: .body)
                    .foregroundStyle(ProfileStyle.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isTitleFocused)
                Text(verbatim: model.deleteMessage(language: language))
                    .profileValue()
                    .foregroundStyle(ProfileStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button { isPresented = false } label: {
                    Text("Cancel").alertButton(fill: ProfileStyle.alertCancelFill, ink: ProfileStyle.ink)
                }
                .buttonStyle(.plain)
                .disabled(model.isWorking)
                .accessibilityIdentifier("profile.confirm.cancel")
                Button {
                    Task { if await model.deleteMyData() { isPresented = false } }
                } label: {
                    Group {
                        if model.isWorking { ProgressView().tint(.white) } else { Text("Delete") }
                    }
                    .alertButton(fill: ProfileStyle.red, ink: .white)
                }
                .buttonStyle(.plain)
                .disabled(model.isWorking)
                .accessibilityIdentifier("profile.delete.confirm")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 26)
        .padding(.bottom, 18)
        .frame(maxWidth: 320)
        .background(ProfileStyle.card.opacity(0.96), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        // Figma: black 18 %, y 12, blur 40.
        .shadow(color: .black.opacity(0.18), radius: 20, y: 12)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { if !model.isWorking { isPresented = false } }
        .accessibilityIdentifier("profile.deleteAlert")
        .onAppear { isTitleFocused = true }
    }
}

private extension View {
    /// Figma "Tombol/Batal", "Tombol/Hapus": 50 pt, r 24, SF Pro Display Semibold 17.
    func alertButton(fill: Color, ink: Color) -> some View {
        profileFont(17, .semibold)
            .figmaLineHeight(22, relativeTo: .body)
            .foregroundStyle(ink)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(fill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(Rectangle())
    }
}
