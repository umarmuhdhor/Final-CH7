import StoreKit
import SwiftUI

/// Profile's sub-screens (PF-01, Figma "Pengaturan/*"), in the same style as Profile.
struct ProfilePageView: View {
    let page: ProfilePage
    @Environment(AppEnvironment.self) private var env
    @State private var model: ProfileModel?

    var body: some View {
        Group {
            if let model {
                switch page {
                case .mode: ModePage(model: model)
                case .editProfile: ManageProfilePage(model: model)
                case .editName: NamePage(model: model)
                case .connection: ConnectionPage(model: model)
                case .notifications: NotificationsPage(model: model)
                case .language: LanguagePage(model: model)
                case .theme: ThemePage()
                case .accessibility: AccessibilityPage()
                case .about: AboutPage()
                case .licenses: LicensesPage()
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
            if [.mode, .editProfile, .editName, .connection, .notifications, .language].contains(page) { await model?.load() }
        }
    }
}

// MARK: Shared pieces

/// Figma "Radio": a 24 pt ring, filled blue with a white dot when chosen.
struct ProfileRadio: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(ProfileStyle.link)
                Circle().fill(.white).frame(width: 9, height: 9)
            } else {
                Circle().strokeBorder(ProfileStyle.radioOff, lineWidth: 1.5)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

/// A 64 pt row with a title, a grey subtitle and a radio (Figma "Pengaturan/Bahasa").
private struct RadioRow: View {
    let title: Text
    var subtitle: Text?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    title.profileFont(17, tracking: -0.17).foregroundStyle(ProfileStyle.ink)
                    if let subtitle {
                        subtitle.profileFont(13).foregroundStyle(ProfileStyle.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ProfileRadio(isOn: isSelected)
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 12)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Grey label above a value, with a chevron (Figma "Info pribadi" rows).
private struct LabeledRow: View {
    let label: Text
    let value: String
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                label.profileFont(13).foregroundStyle(ProfileStyle.secondary)
                Text(verbatim: value).profileFont(17, tracking: -0.17).foregroundStyle(ProfileStyle.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ProfileStyle.chevron)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 10)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Grey note under a card.
private struct PageNote: View {
    let text: Text
    var alignment: TextAlignment = .leading

    var body: some View {
        text
            .profileFont(13)
            .foregroundStyle(ProfileStyle.secondary)
            .lineSpacing(3)
            .multilineTextAlignment(alignment)
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
            .padding(.horizontal, ProfileStyle.margin + 16)
            .padding(.top, 10)
    }
}

/// Failures of a page's action (save, switch), as an alert.
private struct ActionErrorAlert: ViewModifier {
    @Bindable var model: ProfileModel
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content.alert(
            Text(verbatim: model.actionError.map { L10n.string($0, language: AppLanguage(locale: locale)) } ?? ""),
            isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }
}

// MARK: Mode akun

/// Pribadi ↔ Guardian (Family mode); members stay connected. "Punya kode undangan?" joins another
/// family as protected (only without members). Protected devices get "Terhubung" instead.
private struct ModePage: View {
    let model: ProfileModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale
    @State private var selected: ProfileModel.Variant?
    @State private var isJoinPresented = false
    @State private var showsMembersFirst = false

    private var current: ProfileModel.Variant { model.variant }
    private var choice: ProfileModel.Variant { selected ?? current }

    var body: some View {
        ProfileScreen(title: "Account mode") {
            Text("Choose how you use Shoo. You can switch at any time.")
                .profileFont(15)
                .foregroundStyle(ProfileStyle.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, ProfileStyle.margin + 16)
                .padding(.bottom, 8)

            VStack(spacing: 12) {
                ModeCard(
                    title: Text("Personal"), subtitle: Text("Protect yourself"),
                    features: [Text("Scam sites blocked automatically"), Text("A warning on risky sites"), Text("Your own activity history")],
                    isCurrent: current == .personal, isSelected: choice == .personal
                ) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(ProfileStyle.link)
                        .frame(width: 44, height: 44)
                        .background(ModeCardColor.iconFill, in: Circle())
                } action: { selected = .personal }
                    .accessibilityIdentifier("mode.personal")
                ModeCard(
                    title: Text("Guardian"), subtitle: Text("Protect the people close to you"),
                    features: [Text("Everything in Personal"), Text("Look after up to 3 people"), Text("Confirm warnings for them")],
                    isCurrent: current == .guardian, isSelected: choice == .guardian
                ) {
                    AvatarStack(members: model.members)
                } action: { selected = .guardian }
                    .accessibilityIdentifier("mode.guardian")
            }
            .padding(.horizontal, ProfileStyle.margin)
            .padding(.top, 16)

            ProfileCard {
                Button {
                    if model.canJoinAnotherFamily { isJoinPresented = true } else { showsMembersFirst = true }
                } label: {
                    ProfileRow(
                        symbol: ProfileStyle.extensionSymbol, title: Text("Have an invite code?"),
                        subtitle: Text("Connect your account to a family guardian")
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mode.joinFamily")
            }
            .padding(.horizontal, ProfileStyle.margin)
            .padding(.top, 28)

            if choice != current {
                Button {
                    model.setFamilyMode(choice == .guardian)
                    selected = nil
                    AccessibilityNotification.Announcement(L10n.string(
                        choice == .guardian ? "Switched to Guardian" : "Switched to Personal", language: AppLanguage(locale: locale)
                    )).post()
                } label: {
                    Text(choice == .guardian ? "Switch to Guardian" : "Switch to Personal")
                        .profileFont(17, .semibold, tracking: -0.17)
                        .foregroundStyle(ProfileStyle.primaryText)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(ProfileStyle.primaryFill, in: Capsule())
                }
                .padding(.horizontal, ProfileStyle.margin)
                .padding(.top, 28)
                .accessibilityIdentifier("mode.switch")
            }
            PageNote(text: Text("Your protection stays on. You can switch back to Personal at any time."), alignment: .center)
                .padding(.top, choice != current ? 0 : 18)
        }
        .sheet(isPresented: $isJoinPresented) {
            JoinAnotherFamilySheet(name: model.profile?.name ?? "")
                .environment(\.locale, locale)
        }
        .alert(Text("You still protect someone"), isPresented: $showsMembersFirst) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Disconnect the people you protect first. Then you can join another family.")
        }
    }
}

/// Figma "Mode Pribadi" / "Mode Guardian": icon, title (+ "Saat ini"), subtitle, radio, three features.
private struct ModeCard<Icon: View>: View {
    let title: Text
    let subtitle: Text
    let features: [Text]
    let isCurrent: Bool
    let isSelected: Bool
    @ViewBuilder var icon: Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 12) {
                    icon
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            title.profileFont(19, .semibold, tracking: -0.38).foregroundStyle(ProfileStyle.nameInk)
                            if isCurrent {
                                Text("Current")
                                    .profileFont(12, .medium)
                                    .foregroundStyle(Color.dynamic(0x3A3D42, dark: 0xD5D9E0))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.dynamic(0xE6E8EC, dark: 0x2E343E), in: Capsule())
                            }
                        }
                        subtitle.profileFont(14).foregroundStyle(ProfileStyle.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ProfileRadio(isOn: isSelected)
                }
                (isSelected ? ModeCardColor.selectedDivider : ProfileStyle.divider).frame(height: 1)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(features.enumerated()), id: \.offset) { _, feature in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(isSelected ? ProfileStyle.link : ProfileStyle.chevron)
                                .accessibilityHidden(true)
                            feature.profileFont(15).foregroundStyle(ProfileStyle.ink)
                        }
                    }
                }
            }
            .padding(19)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? ModeCardColor.selectedFill : ProfileStyle.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(isSelected ? ProfileStyle.link : ProfileStyle.card, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private enum ModeCardColor {
    static let iconFill = Color.dynamic(0xEEF4FB, dark: 0x1C2A3B)
    static let selectedFill = Color.dynamic(0xF3F8FE, dark: 0x16263A)
    static let selectedDivider = Color.dynamic(0xD6E6F7, dark: 0x27405E)
}

/// Three overlapping initials ("S B R"): the members, or placeholders without any.
private struct AvatarStack: View {
    let members: [FamilyMember]

    var body: some View {
        let people: [(String, String)] = members.isEmpty
            ? [("S", "avatar_01"), ("B", "avatar_02"), ("R", "avatar_03")]
            : members.prefix(3).map { ($0.name, $0.avatarId) }
        HStack(spacing: -10) {
            ForEach(Array(people.enumerated()), id: \.offset) { _, person in
                InitialsAvatar(name: person.0, avatarId: person.1, size: 28)
                    .overlay(Circle().stroke(ProfileStyle.card, lineWidth: 1.5))
            }
        }
        .frame(width: 64, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// "Punya kode undangan?": the Connect screen, joining as protected (a new device on the server).
private struct JoinAnotherFamilySheet: View {
    let name: String
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var model: ConnectModel?

    var body: some View {
        Group {
            if let model {
                ConnectView(model: model, onBack: { dismiss() }, onFinish: {
                    dismiss()
                    env.router.reset()
                })
            }
        }
        .onAppear {
            guard model == nil else { return }
            model = ConnectModel(repository: env.repository) { [env, name] code in
                try await env.becomeProtected(code: code, name: name)
            }
        }
        // Once joined the old device is gone: no swipe back to a screen that no longer exists.
        .interactiveDismissDisabled(isJoined)
    }

    private var isJoined: Bool {
        if case .joined = model?.state { return true }
        return false
    }
}

// MARK: Kelola profil

private struct ManageProfilePage: View {
    let model: ProfileModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale
    @State private var isAvatarPickerPresented = false
    @State private var isDeleteConfirming = false

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        ProfileScreen(title: "Manage profile") {
            VStack(spacing: 12) {
                AvatarView(id: model.profile?.avatarId ?? "", size: 95)
                    .padding(4.5)
                    .background(ProfileStyle.card, in: Circle())
                    .accessibilityHidden(true)
                Button { isAvatarPickerPresented = true } label: {
                    Text("Change photo")
                        .profileFont(15, .medium)
                        .foregroundStyle(ProfileStyle.link)
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("profile.changePhoto")
            }
            .padding(.top, 4)

            ProfileSection(title: "Personal info") {
                Button { env.router.show(.profilePage(.editName)) } label: {
                    LabeledRow(label: Text("Display name"), value: model.profile?.name ?? "")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.displayName")
                ProfileDivider(leading: 17)
                // Made from the name (Profile card handle): shown, not editable on its own.
                LabeledRow(label: Text("Username"), value: model.username, showsChevron: false)
                    .accessibilityIdentifier("profile.username")
            }
            .padding(.top, -8)

            ProfileCard {
                Button { isDeleteConfirming = true } label: {
                    ProfileRow(
                        symbol: "xmark", title: Text("Delete account"),
                        subtitle: Text("All your data and history are deleted for good"),
                        titleColor: ProfileStyle.red, titleWeight: .medium,
                        iconTint: ProfileStyle.red, iconFill: ProfileStyle.redIconFill
                    )
                }
                .buttonStyle(.plain)
                .disabled(model.isWorking)
                .accessibilityIdentifier("profile.manage.delete")
            }
            .padding(.horizontal, ProfileStyle.margin)
            .padding(.top, 28)
        }
        .sheet(isPresented: $isAvatarPickerPresented) {
            AvatarPickerSheet(current: model.profile?.avatarId ?? "") { id in
                Task { if await model.chooseAvatar(id) { isAvatarPickerPresented = false } }
            }
            .environment(\.locale, locale)
        }
        .deleteAccountSheet(model: model, isPresented: $isDeleteConfirming)
        .modifier(ActionErrorAlert(model: model))
    }
}

/// "Ubah foto": the four onboarding memoji (ON-02).
private struct AvatarPickerSheet: View {
    let current: String
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Capsule().fill(ProfileStyle.grabber).frame(width: 36, height: 5)
                .padding(.top, 10)
                .accessibilityHidden(true)
            Text("Change photo")
                .profileFont(22, .semibold, tracking: -0.44)
                .foregroundStyle(ProfileStyle.nameInk)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                ForEach(Array(OnboardingAvatar.ids.enumerated()), id: \.element) { index, id in
                    Button { onPick(id) } label: {
                        AvatarView(id: id, size: 72)
                            .overlay {
                                Circle().strokeBorder(OnboardingTheme.avatarRing, lineWidth: 3).opacity(id == current ? 1 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Avatar \(index + 1)"))
                    .accessibilityAddTraits(id == current ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("avatar.\(id)")
                }
            }
            Button { dismiss() } label: {
                Text("Cancel")
                    .profileFont(17, .semibold, tracking: -0.17)
                    .foregroundStyle(ProfileStyle.ink)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(ProfileStyle.iconFill, in: Capsule())
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .presentationDetents([.height(330)])
        .presentationBackground(ProfileStyle.card)
    }
}

extension View {
    /// "Hapus akun?" confirm sheet (Profile and Kelola profil).
    func deleteAccountSheet(model: ProfileModel, isPresented: Binding<Bool>) -> some View {
        modifier(DeleteAccountSheet(model: model, isPresented: isPresented))
    }
}

private struct DeleteAccountSheet: ViewModifier {
    let model: ProfileModel
    @Binding var isPresented: Bool
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        let language = AppLanguage(locale: locale)
        content.sheet(isPresented: $isPresented) {
            ProfileConfirmSheet(
                title: L10n.string("Delete account?", language: language),
                message: model.deleteMessage(language: language),
                confirmTitle: L10n.string("Delete account", language: language),
                confirmIdentifier: "profile.delete.confirm",
                isWorking: model.isWorking
            ) {
                AvatarView(id: model.profile?.avatarId ?? "", size: 64)
            } onConfirm: {
                Task {
                    if await model.deleteMyData() { isPresented = false }
                }
            }
            .environment(\.locale, locale)
        }
    }
}

// MARK: Nama tampilan

private struct NamePage: View {
    @Bindable var model: ProfileModel
    @Environment(\.locale) private var locale
    @FocusState private var isNameFocused: Bool

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        ProfileScreen(title: "Display name") {
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
            .padding(.top, -12)
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
            .profileFont(13)
            .foregroundStyle(ProfileStyle.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ProfileStyle.margin + 16)
            .padding(.top, 10)

            Button { Task { await save() } } label: {
                Text("Save name")
                    .profileFont(17, .semibold, tracking: -0.17)
                    .foregroundStyle(saveDisabled ? ProfileStyle.secondary : ProfileStyle.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(saveDisabled ? ProfileStyle.disabledFill : ProfileStyle.primaryFill, in: Capsule())
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
                    .foregroundStyle(ProfileStyle.ink)
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .accessibilityIdentifier("profile.guardian.none")
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .modifier(ActionErrorAlert(model: model))
    }
}

// MARK: Notifikasi

/// The switches live on the server, which decides which pushes go out. iOS permission comes first:
/// with notifications off for Shoo, the page says so and links to the fix.
private struct NotificationsPage: View {
    let model: ProfileModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @State private var isQuietTimePresented = false

    private var settings: NotificationSettings { model.notificationSettings }
    private var language: AppLanguage { AppLanguage(locale: locale) }

    private func binding(_ keyPath: WritableKeyPath<NotificationSettings, Bool>, _ update: @escaping (Bool) -> NotificationSettingsUpdate) -> Binding<Bool> {
        Binding(get: { settings[keyPath: keyPath] }, set: { value in Task { await model.updateNotifications(update(value)) } })
    }

    var body: some View {
        ProfileScreen(title: "Notifications") {
            if let status = model.notificationStatus, status != .authorized {
                ProfileCard {
                    Button { Task { await permissionTapped() } } label: {
                        ProfileRow(
                            symbol: "bell.slash.fill", title: Text("Notifications are off"),
                            subtitle: Text(status == .notDetermined ? "Allow Shoo to send you alerts" : "Turn them on in iPhone Settings"),
                            accessory: .value(L10n.string("Turn on", language: language), color: ProfileStyle.link),
                            iconTint: ProfileStyle.red, iconFill: ProfileStyle.redIconFill
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("notifications.permission")
                }
                .padding(.horizontal, ProfileStyle.margin)
                .padding(.top, 4)
            }

            ProfileSection(title: "Warnings") {
                ProfileToggleRow(
                    symbol: "bell.fill", title: Text("Dangerous sites"), subtitle: Text("When you open a high-risk site"),
                    isOn: binding(\.warning) { NotificationSettingsUpdate(warning: $0) }
                )
                .accessibilityIdentifier("notifications.warning")
                ProfileDivider()
                ProfileToggleRow(
                    symbol: "network.badge.shield.half.filled", title: Text("Blocked sites"), subtitle: Text("Every time Shoo blocks a site"),
                    isOn: binding(\.blocked) { NotificationSettingsUpdate(blocked: $0) }
                )
                .accessibilityIdentifier("notifications.blocked")
            }
            .padding(.top, model.notificationStatus.map { $0 != .authorized } ?? false ? 0 : -12)

            if model.variant == .guardian {
                ProfileSection(title: "Family · Guardian mode") {
                    ProfileToggleRow(
                        symbol: "person.fill", title: Text("Activity of people you protect"), subtitle: Text("When they open a dangerous site"),
                        isOn: binding(\.family) { NotificationSettingsUpdate(family: $0) }
                    )
                    .accessibilityIdentifier("notifications.family")
                    ProfileDivider()
                    ProfileToggleRow(
                        symbol: ProfileStyle.extensionSymbol, title: Text("Protection off"), subtitle: Text("When their extension is off"),
                        isOn: binding(\.protectionOff) { NotificationSettingsUpdate(protectionOff: $0) }
                    )
                    .accessibilityIdentifier("notifications.protectionOff")
                }
            }

            ProfileSection(title: "Summary") {
                ProfileToggleRow(
                    symbol: "globe", title: Text("Weekly summary"), subtitle: Text("Every Monday, \(Self.clock("08:00", language: language))"),
                    isOn: binding(\.weeklySummary) { NotificationSettingsUpdate(weeklySummary: $0) }
                )
                .accessibilityIdentifier("notifications.summary")
            }

            ProfileSection(title: "Quiet hours") {
                ProfileToggleRow(
                    symbol: nil, title: Text("Quiet hours"),
                    isOn: binding(\.quietHours) { NotificationSettingsUpdate(quietHours: $0) }
                )
                .accessibilityIdentifier("notifications.quietHours")
                ProfileDivider(leading: 17)
                Button { isQuietTimePresented = true } label: {
                    ProfileRow(
                        symbol: nil, title: Text("Time"),
                        accessory: .value("\(Self.clock(settings.quietStart, language: language)) – \(Self.clock(settings.quietEnd, language: language))")
                    )
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(!settings.quietHours)
                .opacity(settings.quietHours ? 1 : 0.5)
                .accessibilityIdentifier("notifications.quietTime")
            }
            PageNote(text: Text("Blocked-site alerts still come during quiet hours."))
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.refreshNotifications()
        }
        .sheet(isPresented: $isQuietTimePresented) {
            QuietHoursSheet(start: settings.quietStart, end: settings.quietEnd) { start, end in
                Task { await model.updateNotifications(NotificationSettingsUpdate(quietStart: start, quietEnd: end)) }
            }
            .environment(\.locale, locale)
        }
        .modifier(ActionErrorAlert(model: model))
    }

    /// First time: the system prompt here. After a yes or a no only Settings can change it.
    private func permissionTapped() async {
        if await model.notificationsTapped() {
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
        } else {
            await env.registerForPushIfAllowed()
        }
    }

    /// "22:00" → "22.00" in Indonesian, "22:00" in English.
    static func clock(_ value: String, language: AppLanguage) -> String {
        guard let date = QuietHoursSheet.date(value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate("HHmm")
        return formatter.string(from: date)
    }
}

/// "Waktu": start and end of the quiet window, 24-hour.
private struct QuietHoursSheet: View {
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date

    init(start: String, end: String, onSave: @escaping (String, String) -> Void) {
        self.onSave = onSave
        _start = State(initialValue: Self.date(start) ?? Date(timeIntervalSince1970: 22 * 3600))
        _end = State(initialValue: Self.date(end) ?? Date(timeIntervalSince1970: 6 * 3600))
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(selection: $start, displayedComponents: .hourAndMinute) { Text("Starts") }
                    .accessibilityIdentifier("quiet.start")
                DatePicker(selection: $end, displayedComponents: .hourAndMinute) { Text("Ends") }
                    .accessibilityIdentifier("quiet.end")
            }
            .environment(\.timeZone, TimeZone(identifier: "UTC")!)
            .navigationTitle(Text("Quiet hours"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(Self.clock(start), Self.clock(end))
                        dismiss()
                    } label: { Text("Save") }
                    .accessibilityIdentifier("quiet.save")
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// "22:00" as a time on 1 Jan 1970 UTC, so pickers and formatters never shift it.
    static func date(_ clock: String) -> Date? {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(parts[0] * 3600 + parts[1] * 60))
    }

    static func clock(_ date: Date) -> String {
        let minutes = Int(date.timeIntervalSince1970) / 60 % (24 * 60)
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

// MARK: Bahasa

private struct LanguagePage: View {
    let model: ProfileModel
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ProfileScreen(title: "Language") {
            ProfileSection(title: "App language") {
                ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element) { index, language in
                    if index > 0 { ProfileDivider(leading: 17) }
                    RadioRow(
                        title: Text(Self.spokenName(language)),
                        subtitle: Text(Self.localName(language)),
                        isSelected: env.settings.language == language
                    ) { model.chooseLanguage(language) }
                        .accessibilityIdentifier("language.\(language.code)")
                }
            }
            .padding(.top, -12)
            PageNote(text: Text("Warnings in Safari and notifications use this language too."))
        }
    }

    /// The language's own name, read by VoiceOver in that language.
    private static func spokenName(_ language: AppLanguage) -> AttributedString {
        var name = AttributedString(language.nativeName)
        name.languageIdentifier = language.code
        return name
    }

    /// "Indonesia" / "Inggris" under it, in the app's current language.
    private static func localName(_ language: AppLanguage) -> LocalizedStringKey {
        switch language {
        case .indonesian: "Indonesian"
        case .english: "English (language)"
        }
    }
}

// MARK: Tema

private struct ThemePage: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var settings = env.settings
        ProfileScreen(title: "Theme") {
            ProfileSection(title: "Appearance") {
                HStack(alignment: .top, spacing: 0) {
                    ThemeOption(image: "ThemePreviewLight", title: Text("Light"), isSelected: settings.theme == .light) { settings.theme = .light }
                        .accessibilityIdentifier("theme.light")
                    ThemeOption(image: "ThemePreviewDark", title: Text("Dark"), isSelected: settings.theme == .dark) { settings.theme = .dark }
                        .accessibilityIdentifier("theme.dark")
                    ThemeOption(image: "ThemePreviewSystem", title: Text("Automatic"), isSelected: settings.theme == .system) { settings.theme = .system }
                        .accessibilityIdentifier("theme.system")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
            }
            .padding(.top, -12)
            PageNote(text: Text("Automatic follows light or dark mode on your iPhone."))

            ProfileSection(title: "Effects") {
                ProfileToggleRow(
                    symbol: "circle.lefthalf.filled", title: Text("Reduce glass effects"),
                    subtitle: Text("Solid backgrounds that also save battery"),
                    isOn: $settings.reduceGlass
                )
                .accessibilityIdentifier("theme.reduceGlass")
            }
        }
    }
}

/// One phone preview, its name and a radio (Figma "Terang" / "Gelap" / "Otomatis").
private struct ThemeOption: View {
    let image: String
    let title: Text
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 150)
                    .padding(5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 21, style: .continuous)
                            .strokeBorder(ProfileStyle.link, lineWidth: 2)
                            .opacity(isSelected ? 1 : 0)
                    )
                title
                    .profileFont(15, isSelected ? .medium : .regular)
                    .foregroundStyle(ProfileStyle.ink)
                ProfileRadio(isOn: isSelected)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: Aksesibilitas

private struct AccessibilityPage: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale

    var body: some View {
        @Bindable var settings = env.settings
        ProfileScreen(title: "Accessibility") {
            ProfileSection(title: "Text size") {
                VStack(alignment: .leading, spacing: 16) {
                    // Figma "Pratinjau": a sample Activity row at the chosen size.
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(ProfileStyle.ink)
                            .frame(width: 40, height: 40)
                            .background(ProfileStyle.card, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "bca-verifikasi.site").profileFont(20).foregroundStyle(ProfileStyle.ink)
                            Text("Today · \(Self.sampleTime(locale: locale))").profileFont(15, rounded: true).foregroundStyle(ProfileStyle.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(ProfileStyle.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityHidden(true)
                    TextSizeSlider(level: $settings.textSize)
                    Text(verbatim: L10n.string(settings.textSize.title, language: AppLanguage(locale: locale)))
                        .profileFont(15, .medium)
                        .foregroundStyle(ProfileStyle.ink)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                .padding(14)
            }
            .padding(.top, -12)

            ProfileSection(title: "Display") {
                ProfileToggleRow(symbol: "Aa", title: Text("Bold text"), isOn: $settings.boldText)
                    .accessibilityIdentifier("accessibility.bold")
                ProfileDivider()
                ProfileToggleRow(symbol: "circle.lefthalf.filled", title: Text("High contrast"), isOn: $settings.highContrast)
                    .accessibilityIdentifier("accessibility.contrast")
                ProfileDivider()
                ProfileToggleRow(
                    symbol: ProfileStyle.extensionSymbol, title: Text("Reduce motion"), subtitle: Text("Turns off animations in Shoo"),
                    isOn: $settings.reduceMotion
                )
                .accessibilityIdentifier("accessibility.reduceMotion")
            }

            ProfileSection(title: "When there is a warning") {
                ProfileToggleRow(symbol: "bell.fill", title: Text("Vibrate"), isOn: $settings.haptics)
                    .accessibilityIdentifier("accessibility.haptics")
                ProfileDivider()
                ProfileToggleRow(
                    symbol: "person.fill", title: Text("Read warnings aloud"), subtitle: Text("VoiceOver reads the score and reasons"),
                    isOn: $settings.readAloud
                )
                .accessibilityIdentifier("accessibility.readAloud")
            }
        }
    }

    /// "10.42" / "10:42".
    private static func sampleTime(locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate("HHmm")
        return formatter.string(from: Date(timeIntervalSince1970: 10 * 3600 + 42 * 60))
    }
}

/// Five stops from a small "A" to a large "A" (Figma "Slider"). VoiceOver: swipe up or down.
private struct TextSizeSlider: View {
    @Binding var level: TextSizeLevel
    @Environment(\.locale) private var locale

    private let levels = TextSizeLevel.allCases

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: "A").font(.system(size: 13, weight: .medium)).foregroundStyle(ProfileStyle.secondary)
            GeometryReader { geo in
                let inset: CGFloat = 4
                let step = (geo.size.width - inset * 2) / CGFloat(levels.count - 1)
                let x = { (i: Int) in inset + step * CGFloat(i) }
                ZStack(alignment: .leading) {
                    Capsule().fill(ProfileStyle.iconFill).frame(height: 4).padding(.horizontal, inset)
                    Capsule().fill(ProfileStyle.link).frame(width: x(level.rawValue), height: 4).padding(.leading, inset)
                    ForEach(levels, id: \.rawValue) { stop in
                        Circle()
                            .fill(stop.rawValue <= level.rawValue ? ProfileStyle.link : ProfileStyle.chevron)
                            .frame(width: 8, height: 8)
                            .offset(x: x(stop.rawValue) - 4)
                    }
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                        .frame(width: 28, height: 28)
                        .offset(x: x(level.rawValue) - 14)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let index = Int(((value.location.x - inset) / step).rounded())
                    if let new = TextSizeLevel(rawValue: min(max(index, 0), levels.count - 1)), new != level { level = new }
                })
            }
            .frame(height: 28)
            Text(verbatim: "A").font(.system(size: 22, weight: .medium)).foregroundStyle(ProfileStyle.ink)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Text size"))
        .accessibilityValue(Text(verbatim: L10n.string(level.title, language: AppLanguage(locale: locale))))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: level = TextSizeLevel(rawValue: level.rawValue + 1) ?? level
            case .decrement: level = TextSizeLevel(rawValue: level.rawValue - 1) ?? level
            @unknown default: break
            }
        }
        .accessibilityIdentifier("accessibility.textSize")
    }
}

// MARK: Tentang Shoo

private struct AboutPage: View {
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @Environment(AppEnvironment.self) private var env

    private var language: AppLanguage { AppLanguage(locale: locale) }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func page(_ path: String) -> URL {
        var components = URLComponents(url: AppConfig.apiBaseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "lang", value: language.code)]
        return components.url!
    }

    var body: some View {
        ProfileScreen(title: "About Shoo") {
            VStack(spacing: 0) {
                Image("AboutAppIcon")
                    .resizable()
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)
                Text(verbatim: "Shoo")
                    .profileFont(28, .bold)
                    .foregroundStyle(ProfileStyle.nameInk)
                    .padding(.top, 16)
                    .accessibilityAddTraits(.isHeader)
                Text("Version \(version)")
                    .profileFont(13, rounded: true)
                    .foregroundStyle(ProfileStyle.secondary)
                    .padding(.top, 3)
                Text("Protect yourself and your family from scam sites.")
                    .profileFont(15)
                    .foregroundStyle(ProfileStyle.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.horizontal, ProfileStyle.margin)
            }
            .padding(.top, 8)

            ProfileCard {
                linkRow(Text("Privacy policy"), id: "about.privacy") { openURL(page("privacy")) }
                ProfileDivider(leading: 17)
                linkRow(Text("Terms of use"), id: "about.terms") { openURL(page("terms")) }
                ProfileDivider(leading: 17)
                linkRow(Text("Third-party licenses"), id: "about.licenses", isLink: false) { env.router.show(.profilePage(.licenses)) }
            }
            .padding(.horizontal, ProfileStyle.margin)
            .padding(.top, 28)

            ProfileCard {
                linkRow(Text("Rate on the App Store"), id: "about.rate") { rate() }
                ProfileDivider(leading: 17)
                ShareLink(item: AppConfig.shareURL, message: Text("Shoo blocks scam sites in Safari. Try it:")) {
                    ProfileRow(symbol: nil, title: Text("Share Shoo")).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("about.share")
                ProfileDivider(leading: 17)
                linkRow(Text("Contact us"), value: AppConfig.supportEmail, id: "about.contact") {
                    if let url = URL(string: "mailto:\(AppConfig.supportEmail)") { openURL(url) }
                }
            }
            .padding(.horizontal, ProfileStyle.margin)
            .padding(.top, 16)

            Text("© 2026 Shoo · Made in Indonesia")
                .profileFont(13)
                .foregroundStyle(ProfileStyle.secondary)
                .padding(.top, 28)
        }
    }

    private func linkRow(_ title: Text, value: String? = nil, id: String, isLink: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ProfileRow(symbol: nil, title: title, accessory: value.map { .value($0) } ?? .chevron)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isLink ? .isLink : [])
        .accessibilityIdentifier(id)
    }

    /// The App Store's review page once the app is listed; before that, the system review prompt.
    private func rate() {
        if let id = AppConfig.appStoreId, let url = URL(string: "https://apps.apple.com/app/id\(id)?action=write-review") {
            openURL(url)
        } else {
            requestReview()
        }
    }
}

/// "Lisensi pihak ketiga".
private struct LicensesPage: View {
    var body: some View {
        ProfileScreen(title: "Third-party licenses") {
            ProfileCard {
                Text("Shoo uses no third-party libraries or SDKs. It is built only with Apple's frameworks, under the Apple Developer Program License Agreement.")
                    .profileFont(15)
                    .foregroundStyle(ProfileStyle.ink)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(17)
            }
            .padding(.horizontal, ProfileStyle.margin)
        }
    }
}
