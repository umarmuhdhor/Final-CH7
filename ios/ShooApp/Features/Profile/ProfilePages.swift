import SwiftUI

/// Profile's sub-screens (PF-01), in the same style as Profile.
struct ProfilePageView: View {
    let page: ProfilePage
    @Environment(AppEnvironment.self) private var env
    @State private var model: ProfileModel?

    var body: some View {
        Group {
            if let model {
                switch page {
                case .mode: ModePage(model: model)
                case .editProfile: EditProfilePage(model: model)
                case .connection: ConnectionPage(model: model)
                case .language: LanguagePage(model: model)
                case .accessibility: AccessibilityPage()
                case .about: AboutPage()
                }
            } else {
                ProfileStyle.background.ignoresSafeArea()
            }
        }
        .task {
            if model == nil {
                let model = ProfileModel(repository: env.repository, settings: env.settings, notifications: env.notifications)
                model.onSessionEnd = { [router = env.router] in
                    router.reset()
                    DeliveredPushes.clear()
                }
                self.model = model
            }
            if [.editProfile, .connection, .language].contains(page) { await model?.load() }
        }
    }
}

/// A row with a check mark for the chosen option.
private struct ChoiceRow: View {
    let symbol: String
    let title: Text
    var subtitle: Text?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ProfileIcon(symbol: symbol)
                VStack(alignment: .leading, spacing: 1) {
                    title.profileFont(17, tracking: -0.17).foregroundStyle(ProfileStyle.ink)
                    if let subtitle {
                        subtitle.profileFont(13, rounded: true).foregroundStyle(ProfileStyle.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ProfileStyle.link)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 11)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Grey note under a card.
private struct PageNote: View {
    let text: Text

    var body: some View {
        text
            .profileFont(13, rounded: true)
            .foregroundStyle(ProfileStyle.secondary)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ProfileStyle.margin + 16)
            .padding(.top, 10)
    }
}

// MARK: Mode akun

/// Pribadi ↔ Guardian (Family mode). Guardian vs Protected was chosen once in onboarding and stays.
private struct ModePage: View {
    let model: ProfileModel

    var body: some View {
        ProfileScreen(title: "Account mode") {
            ProfileSection(title: "Mode") {
                ChoiceRow(
                    symbol: "person.fill", title: Text("Personal"), subtitle: Text("Shoo protects only you"),
                    isSelected: model.variant == .personal
                ) { model.setFamilyMode(false) }
                    .accessibilityIdentifier("mode.personal")
                ProfileDivider()
                ChoiceRow(
                    symbol: "person.2.fill", title: Text("Guardian"), subtitle: Text("You also look after your family"),
                    isSelected: model.variant == .guardian
                ) { model.setFamilyMode(true) }
                    .accessibilityIdentifier("mode.guardian")
            }
            PageNote(text: Text("Switching to Personal keeps your family connected. You can switch back at any time."))
        }
    }
}

// MARK: Kelola profil

private struct EditProfilePage: View {
    @Bindable var model: ProfileModel
    @Environment(\.locale) private var locale
    @FocusState private var isNameFocused: Bool

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        ProfileScreen(title: "Manage profile") {
            AvatarView(id: model.profile?.avatarId ?? "", size: 88)
                .padding(4)
                .background(.white, in: Circle())
                .padding(.top, 8)
                .accessibilityHidden(true)
            ProfileSection(title: "Name") {
                // Same word as the section title, so Voice Control "Tap Name" works (WCAG 2.5.3).
                TextField(text: $model.nameDraft) { Text("Name") }
                    .profileFont(17, tracking: -0.17)
                    .foregroundStyle(ProfileStyle.ink)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .onSubmit { Task { await save() } }
                    .padding(.horizontal, 17)
                    .frame(minHeight: 52)
                    .accessibilityHint(Text("1 to 20 characters"))
                    .accessibilityIdentifier("profile.name")
            }
            VStack(alignment: .leading, spacing: 4) {
                switch model.nameProblem {
                case .empty: Text("Enter a name.")
                case .tooLong: Text("Use 20 characters or fewer.")
                case nil: Text("1–20 characters. Your family sees this name.")
                }
                if let message = model.nameError {
                    Text(verbatim: L10n.string(message, language: language))
                        .foregroundStyle(Color.readableRed)
                        .accessibilityIdentifier("profile.error")
                }
            }
            .profileFont(13, rounded: true)
            .foregroundStyle(ProfileStyle.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ProfileStyle.margin + 16)
            .padding(.top, 10)

            Button { Task { await save() } } label: {
                Text("Save name")
                    .profileFont(17, .semibold, tracking: -0.17)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(saveDisabled ? Color(hex: 0xB8C0CC) : ProfileStyle.ink, in: Capsule())
            }
            .disabled(saveDisabled)
            .padding(.horizontal, ProfileStyle.margin)
            .padding(.top, 24)
            .accessibilityIdentifier("profile.saveName")
        }
        .onChange(of: model.nameError) { _, message in
            if let message { announce(message) }
        }
    }

    private var saveDisabled: Bool {
        model.nameDraft == model.profile?.name || model.nameProblem != nil || model.isWorking
    }

    private func save() async {
        if await model.saveName() {
            isNameFocused = false
            announce("Name saved")
        }
    }

    private func announce(_ message: String.LocalizationValue) {
        AccessibilityNotification.Announcement(L10n.string(message, language: language)).post()
    }
}

// MARK: Terhubung (Protected)

private struct ConnectionPage: View {
    let model: ProfileModel
    @Environment(\.locale) private var locale
    @State private var isDisconnectConfirming = false

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        ProfileScreen(title: "Connected") {
            if let guardian = model.profile?.guardian {
                ProfileSection(title: "Your guardian") {
                    HStack(spacing: 12) {
                        AvatarView(id: guardian.avatarId, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: guardian.name)
                                .profileFont(17, .medium, tracking: -0.17)
                                .foregroundStyle(ProfileStyle.nameInk)
                            Text("Gets your warnings")
                                .profileFont(13, rounded: true)
                                .foregroundStyle(ProfileStyle.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 17)
                    .frame(minHeight: 72)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("profile.guardian")
                }
                VStack(spacing: 10) {
                    ProfileCard {
                        Button { isDisconnectConfirming = true } label: {
                            ProfileRow(
                                symbol: "xmark", title: Text("Disconnect"), titleColor: ProfileStyle.red, titleWeight: .medium,
                                iconTint: ProfileStyle.red, iconFill: ProfileStyle.redIconFill
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("profile.disconnect")
                    }
                    PageNote(text: Text("\(guardian.name) will no longer see the sites Shoo warns you about."))
                        .padding(.horizontal, -ProfileStyle.margin)
                }
                .padding(.horizontal, ProfileStyle.margin)
                .padding(.top, 28)
                .sheet(isPresented: $isDisconnectConfirming) {
                    ProfileConfirmSheet(
                        title: L10n.string("Disconnect from \(guardian.name)?", language: language),
                        message: L10n.string("\(guardian.name) will no longer see the sites Shoo warns you about.", language: language),
                        confirmTitle: L10n.string("Disconnect", language: language),
                        confirmIdentifier: "profile.disconnect.confirm",
                        isWorking: model.isWorking
                    ) {
                        AvatarView(id: guardian.avatarId, size: 64)
                    } onConfirm: {
                        Task { if await model.disconnect() { isDisconnectConfirming = false } }
                    }
                    .environment(\.locale, locale)
                }
            } else if model.state == .loaded {
                Text("Not connected to a guardian yet")
                    .profileFont(17, .semibold)
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .accessibilityIdentifier("profile.guardian.none")
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .alert(
            Text(verbatim: model.actionError.map { L10n.string($0, language: language) } ?? ""),
            isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }
}

// MARK: Bahasa

private struct LanguagePage: View {
    let model: ProfileModel
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ProfileScreen(title: "Language") {
            ProfileSection(title: "Language") {
                ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element) { index, language in
                    if index > 0 { ProfileDivider() }
                    ChoiceRow(
                        symbol: "globe", title: Text(Self.spokenName(language)),
                        isSelected: env.settings.language == language
                    ) { model.chooseLanguage(language) }
                        .accessibilityIdentifier("language.\(language.code)")
                }
            }
            PageNote(text: Text("Shoo and its alerts use this language."))
        }
    }

    /// The language's own name, read by VoiceOver in that language.
    private static func spokenName(_ language: AppLanguage) -> AttributedString {
        var name = AttributedString(language.nativeName)
        name.languageIdentifier = language.code
        return name
    }
}

// MARK: Aksesibilitas

private struct AccessibilityPage: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var settings = env.settings
        ProfileScreen(title: "Accessibility") {
            ProfileSection(title: "Text") {
                ProfileToggleRow(
                    symbol: "Aa", title: Text("Large text"), subtitle: Text("Bigger text in Shoo"),
                    isOn: $settings.largeText
                )
                .accessibilityIdentifier("accessibility.largeText")
            }
            PageNote(text: Text("If your iPhone already uses a bigger text size, Shoo keeps it."))
        }
    }
}

// MARK: Tentang Shoo

private struct AboutPage: View {
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private var privacyURL: URL {
        var components = URLComponents(url: AppConfig.apiBaseURL.appending(path: "privacy"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "lang", value: AppLanguage(locale: locale).code)]
        return components.url!
    }

    var body: some View {
        ProfileScreen(title: "About Shoo") {
            ProfileSection(title: "Shoo") {
                ProfileRow(symbol: "info.circle", title: Text("Version"), accessory: .value(version, chevron: false))
                    .accessibilityElement(children: .combine)
                ProfileDivider()
                Button { openURL(privacyURL) } label: {
                    ProfileRow(symbol: "hand.raised.fill", title: Text("Privacy policy"))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isLink)
                .accessibilityIdentifier("about.privacy")
            }
            PageNote(text: Text("Shoo checks the sites you open in Safari and blocks scams. Flagged sites and their screenshots are deleted automatically after 14 days. No ads, no tracking."))
        }
    }
}
