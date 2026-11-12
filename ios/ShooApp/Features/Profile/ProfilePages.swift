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
        // A new name or avatar saved (the Kelola profil sheets close on success).
        .sensoryFeedback(.success, trigger: model?.profileSaves ?? 0)
        // Member and Guardian names: covered in the app-switcher snapshot, as on Profile (BH-33, SECURITY §3 P13).
        .privacyCover()
        .task {
            if model == nil {
                let model = ProfileModel(repository: env.repository, settings: env.settings, notifications: env.notifications)
                model.onSessionEnd = { [env] in
                    env.returnToOnboardingAfterDelete()
                }
                self.model = model
            }
            if [.mode, .editProfile, .connection, .notifications, .language].contains(page) { await model?.load() }
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
        // Ring ↔ fill: a 0.2 s cross-fade, gentle enough for Reduce Motion.
        .animation(.easeInOut(duration: 0.2), value: isOn)
        .accessibilityHidden(true)
    }
}

/// A choice in a Profile list eases into its chosen look and taps once (pattern: the onboarding avatars).
/// Reduce Motion: a 0.2 s ease. `movesLayout`: the choice changes its size, so Reduce Motion snaps it instead.
private struct ProfileSelectionMotion: ViewModifier {
    let isSelected: Bool
    var movesLayout = false
    @Environment(\.shooReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .animation(
                reduceMotion ? (movesLayout ? nil : .easeInOut(duration: 0.2)) : .snappy(duration: 0.2),
                value: isSelected
            )
            .sensoryFeedback(.selection, trigger: isSelected) { _, now in now }
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
        .modifier(ProfileSelectionMotion(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Grey label above a value, with a chevron (Figma "Info pribadi" rows, 1278:12077: 62 pt, 10 pt padding).
private struct LabeledRow: View {
    let label: Text
    let value: String
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                label.profileCaption().foregroundStyle(ProfileStyle.secondary)
                Text(verbatim: value).profileBody().foregroundStyle(ProfileStyle.ink)
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
        .frame(minHeight: 62)
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

    /// A protected iPhone without a guardian works like Pribadi (QA 2026-11-10 #4: no card was marked). It can't
    /// become a Guardian: the device mode never changes on the server.
    private var current: ProfileModel.Variant { model.variant == .protected ? .personal : model.variant }
    private var isProtected: Bool { model.variant == .protected }
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
                    .disabled(isProtected)
                    .opacity(isProtected ? 0.45 : 1)
                    .accessibilityIdentifier("mode.guardian")
            }
            .padding(.horizontal, ProfileStyle.margin)
            .padding(.top, 16)

            ProfileCard {
                Button {
                    if !model.canJoinAnotherFamily {
                        showsMembersFirst = true
                    } else if isProtected {
                        // Already protected: a plain join with the code (POST /family/join), as on Home.
                        env.router.showConnect()
                    } else {
                        isJoinPresented = true
                    }
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
                    if choice == .guardian { env.requestFamilyMode() } else { model.setFamilyMode(false) }
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
        .alert(isProtected ? Text("You're already connected") : Text("You still protect someone"), isPresented: $showsMembersFirst) {
            Button("OK", role: .cancel) {}
        } message: {
            if isProtected {
                Text("Only your guardian can disconnect you. Ask them first, then join another family.")
            } else {
                Text("Disconnect the people you protect first. Then you can join another family.")
            }
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
        .modifier(ProfileSelectionMotion(isSelected: isSelected))
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

/// "Punya kode undangan?" and Home Pribadi "Mode Terawasi": the Connect screen, joining as protected (a new
/// device on the server). An empty `name` is read from the server first.
struct JoinAnotherFamilySheet: View {
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
                let name = name.isEmpty ? try await env.repository.me().name : name
                return try await env.becomeProtected(code: code, name: name)
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
    @State private var isNamePresented = false
    @State private var isDeleteConfirming = false

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        if model.variant == .protected {
            ProtectedManageProfilePage(model: model)
        } else {
            guardianBody
        }
    }

    /// Figma "Pengaturan/Kelola profil" (416:12854): avatar with an edit badge, "Ubah avatar", Info pribadi
    /// (name, status), the people this guardian protects, and "Hapus akun". No phone number row.
    private var guardianBody: some View {
        ProfileScreen(title: "Manage profile") {
            VStack(spacing: 1) {
                avatar
                Button { isAvatarPickerPresented = true } label: {
                    Text("Change avatar")
                        .profileBody()
                        .foregroundStyle(ProfileStyle.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.changePhoto")
            }
            // Figma: the avatar 20 pt under the back button.
            .padding(.top, 4)

            // Figma: 20 pt under "Ubah avatar"; its 44 pt tap area already adds 11.
            ProfileSection(title: "Personal info", top: 9) {
                Button {
                    model.nameDraft = model.profile?.name ?? ""
                    isNamePresented = true
                } label: {
                    LabeledRow(label: Text("Display name"), value: model.profile?.name ?? "")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.displayName")
                ProfileDivider(leading: 17)
                LabeledRow(label: Text("Status"), value: L10n.string(model.statusTitle, language: language), showsChevron: false)
                    .accessibilityIdentifier("profile.status")
            }

            if model.variant == .guardian, !model.members.isEmpty {
                ProfileSection(title: "Connected with", top: 32) {
                    ForEach(Array(model.members.enumerated()), id: \.element.id) { index, member in
                        if index > 0 { ProfileDivider() }
                        connectedRow(member)
                    }
                }
            }

            ProfileSection(title: "Account", top: 32) {
                Button { isDeleteConfirming = true } label: {
                    ProfileRow(
                        symbol: "xmark", title: Text("Delete account"),
                        subtitle: Text("All data and history will be deleted for good"),
                        titleColor: ProfileStyle.red,
                        iconTint: ProfileStyle.red, iconFill: ProfileStyle.redIconFill,
                        style: .settings
                    )
                }
                .buttonStyle(.plain)
                .disabled(model.isWorking)
                .accessibilityIdentifier("profile.manage.delete")
            }
        }
        .sheet(isPresented: $isAvatarPickerPresented) {
            AvatarPickerSheet(current: model.profile?.avatarId ?? "", isWorking: model.isWorking) { id in
                Task { if await model.chooseAvatar(id) { isAvatarPickerPresented = false } }
            }
            .environment(\.locale, locale)
        }
        .sheet(isPresented: $isNamePresented) {
            NameSheet(model: model, subtitle: nameSubtitle)
                .environment(\.locale, locale)
        }
        .deleteAccountSheet(model: model, isPresented: $isDeleteConfirming)
        .modifier(ActionErrorAlert(model: model))
    }

    /// Figma "Avatar" (104 pt: a 100 pt photo in a 2 pt white ring, card shadow) and "Badge edit avatar".
    private var avatar: some View {
        AvatarView(id: model.profile?.avatarId ?? "", size: 100)
            .overlay(Circle().strokeBorder(ProfileStyle.card, lineWidth: 2.5))
            .padding(2)
            .background(ProfileStyle.card, in: Circle())
            .shadow(color: ProfileStyle.cardShadow, radius: 8, y: 6)
            .overlay(alignment: .bottomTrailing) {
                Image("ProfileEditBadge")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .offset(x: 2, y: -2)
            }
            .onTapGesture { isAvatarPickerPresented = true }
            // "Ubah avatar" right under it does the same for VoiceOver and Voice Control.
            .accessibilityHidden(true)
    }

    /// Figma "Terhubung · Virellia" (1278:12105): avatar, name, "dilindungi sejak 12 Okt 2026", chevron.
    private func connectedRow(_ member: FamilyMember) -> some View {
        Button { env.router.show(.member(deviceId: member.deviceId)) } label: {
            HStack(spacing: 12) {
                AvatarView(id: member.avatarId, size: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: member.name)
                        .profileBody()
                        .foregroundStyle(ProfileStyle.ink)
                    if let since = member.connectedAt {
                        Text("Protected since \(since.formatted(.dateTime.day().month(.abbreviated).year().locale(language.locale)))")
                            .profileCaption()
                            .foregroundStyle(ProfileStyle.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ProfileStyle.chevron)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 12)
            .frame(minHeight: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Shows this person's protection"))
        .accessibilityIdentifier("profile.connected.\(member.deviceId)")
    }

    /// Figma "Nama ini terlihat di app Virellia.": the one person this guardian protects, else the family.
    private var nameSubtitle: Text {
        if model.variant == .guardian, model.members.count == 1, let member = model.members.first {
            return Text("This name shows in \(member.name)'s app.")
        }
        return Text("Your family sees this name.")
    }
}

/// Figma "Pengaturan/Kelola profil" of the protected user: avatar, "Aktif sejak", the name edited in
/// place, and "Hapus akun" low on the page.
private struct ProtectedManageProfilePage: View {
    @Bindable var model: ProfileModel
    @Environment(\.locale) private var locale
    @FocusState private var isNameFocused: Bool
    @State private var isDeleteConfirming = false

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        ProfileScreen(title: "Manage profile") {
            AvatarView(id: model.profile?.avatarId ?? "", size: 95)
                .padding(4.5)
                .background(ProfileStyle.card, in: Circle())
                // Figma "Avatar": #1A1C2E 12 %, y 6, blur 16.
                .shadow(color: ProfileStyle.cardShadow, radius: 8, y: 6)
                .accessibilityHidden(true)
                .padding(.top, 4)

            if let since = model.activeSince(language: language) {
                HStack(spacing: 6) {
                    Image(systemName: "shield.fill").accessibilityHidden(true)
                    Text(verbatim: since)
                }
                .profileFont(22, .medium, tracking: -0.22)
                .foregroundStyle(ProfileStyle.secondary)
                // Figma 242 × 39: 5.2 / 20.7 inside, plus its 1.3 pt ring drawn outside.
                .padding(.horizontal, 22)
                .padding(.vertical, 6.5)
                .overlay(Capsule().stroke(ProfileStyle.card.opacity(0.9), lineWidth: 1.3))
                .padding(.top, 12)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("profile.activeSince")
            }

            ProfileSection(title: "Personal info", top: 72) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Name").profileCaption().foregroundStyle(ProfileStyle.secondary)
                            .accessibilityHidden(true)
                        // Same word as the label, so Voice Control "Tap Name" works (WCAG 2.5.3).
                        TextField(text: $model.nameDraft) { Text("Name") }
                            .profileBody()
                            .foregroundStyle(ProfileStyle.ink)
                            .textContentType(.givenName)
                            .submitLabel(.done)
                            .focused($isNameFocused)
                            .onSubmit { Task { await save() } }
                            .accessibilityHint(Text("1 to 20 characters"))
                            .accessibilityIdentifier("profile.name")
                    }
                    Button { isNameFocused = true } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ProfileStyle.chevron)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Edit name"))
                    .padding(.trailing, -14)
                }
                .padding(.horizontal, 17)
                // Figma "Row/Adhella": 62 pt, the label and name 10 pt from its edges.
                .padding(.vertical, 9)
                .frame(minHeight: 62)
                ProfileDivider(leading: 17)
            }

            if let message = nameMessage {
                message
                    .profileFont(13)
                    .foregroundStyle(Color.readableRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ProfileStyle.margin + 16)
                    .padding(.top, 10)
                    .accessibilityIdentifier("profile.error")
            }

            ProfileCard {
                Button { isDeleteConfirming = true } label: {
                    ProfileRow(
                        symbol: "xmark", title: Text("Delete account"),
                        subtitle: Text("All data and history will be deleted for good"),
                        titleColor: ProfileStyle.red,
                        iconTint: ProfileStyle.red, iconFill: ProfileStyle.redIconFill,
                        style: .settings
                    )
                }
                .buttonStyle(.plain)
                .disabled(model.isWorking)
                .accessibilityIdentifier("profile.manage.delete")
            }
            .padding(.horizontal, ProfileStyle.margin)
            // Figma keeps "Hapus akun" near the bottom of the screen: its card starts at y 738.
            .padding(.top, 293)
        }
        .onChange(of: isNameFocused) { _, focused in
            // Leaving the field keeps a valid edit, like Return does.
            if !focused, model.nameDraft != model.profile?.name, model.nameProblem == nil { Task { await save() } }
        }
        .onChange(of: model.nameError) { _, message in
            if let message { announce(message) }
        }
        .deleteAccountSheet(model: model, isPresented: $isDeleteConfirming)
        .modifier(ActionErrorAlert(model: model))
    }

    private var nameMessage: Text? {
        switch model.nameProblem {
        case .empty: return Text("Enter a name.")
        case .tooLong: return Text("Use 20 characters or fewer.")
        case nil: return model.nameError.map { Text(verbatim: L10n.string($0, language: language)) }
        }
    }

    private func save() async {
        guard model.nameDraft != model.profile?.name else { return }
        if await model.saveName() {
            isNameFocused = false
            announce("Name saved")
        }
    }

    private func announce(_ message: String.LocalizationValue) {
        AccessibilityNotification.Announcement(L10n.string(message, language: language)).post()
    }
}

// MARK: Akun Tertaut (Protected)

/// Figma "Pengaturan/Mode akun" of the protected user ("Akun Tertaut"): who this iPhone is linked to,
/// what the guardian gets, and "Putuskan koneksi" locked — only the guardian can disconnect.
private struct ConnectionPage: View {
    let model: ProfileModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        ProfileScreen(title: "Linked account") {
            if let guardian = model.profile?.guardian {
                linked(guardian)
            } else if model.state == .loaded {
                notLinked
            } else {
                ShieldPulseLoader().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .task { model.linked.refresh() }
    }

    /// QA 2026-11-10 #6: the guardian disconnected this iPhone or deleted their account. Say what that means and
    /// offer the way back, the same Connect as on Home.
    private var notLinked: some View {
        VStack(spacing: 12) {
            Text("Not connected to a guardian yet")
                .profileFont(17, .semibold)
                .foregroundStyle(ProfileStyle.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("profile.guardian.none")
            Text("If your guardian disconnected you or deleted their account, ask them for a new invite code. Shoo keeps protecting you in the meantime.")
                .profileFont(15)
                .foregroundStyle(ProfileStyle.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Button { env.router.showConnect() } label: {
                Text("Connect")
                    .profileFont(17, .semibold, tracking: -0.17)
                    .foregroundStyle(ProfileStyle.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(ProfileStyle.primaryFill, in: Capsule())
            }
            .padding(.top, 12)
            .accessibilityIdentifier("profile.guardian.connect")
        }
        .padding(.horizontal, ProfileStyle.margin + 16)
        .padding(.top, 48)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func linked(_ guardian: GuardianInfo) -> some View {
        @Bindable var linked = model.linked

        // Figma 455:9520: SF Pro Rounded 17, line height 140 %.
        Text("This account is linked to another account.")
            .profileValue()
            .foregroundStyle(ProfileStyle.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .padding(.top, 24)

        HStack(alignment: .top, spacing: 17) {
            person(name: Text("You")) {
                AvatarView(id: model.profile?.avatarId ?? "", size: 84)
                    .padding(3.66)
                    .background(ProfileStyle.card, in: Circle())
                    .shadow(color: Color(hex: 0x1F78BF, opacity: 0.18), radius: 11, y: 7)
            }
            // Figma 1618872250: the dots start 53.8 pt under the avatars' top.
            LinkDots().padding(.top, 54)
            person(name: Text(verbatim: guardian.name)) {
                AvatarView(id: guardian.avatarId, size: 85)
                    .padding(3.5)
                    .background(ProfileStyle.card, in: Circle())
                    .shadow(color: Color(hex: 0x1A1C2E, opacity: 0.12), radius: 7, y: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Linked with \(guardian.name)"))
        .accessibilityIdentifier("profile.guardian")
        .padding(.top, 38)

        ProfileCard {
            if LinkedAccountSettings.switchesAreLive {
                ProfileToggleRow(symbol: "paperplane.fill", title: Text("Send links automatically"), isOn: $linked.autoSendLinks)
                    .accessibilityIdentifier("linked.autoSend")
                ProfileDivider()
                ProfileToggleRow(symbol: "clock", title: Text("Share caution history"), isOn: $linked.shareWarnings)
                    .disabled(!linked.autoSendLinks)
                    .opacity(linked.autoSendLinks ? 1 : 0.45)
                    .accessibilityIdentifier("linked.shareWarnings")
            } else {
                // Today the extension sends every check to the guardian, so both read on and can't change.
                ProfileToggleRow(symbol: "paperplane.fill", title: Text("Send links automatically"), subtitle: Text("Coming soon"), isOn: .constant(true))
                    .disabled(true)
                    .accessibilityIdentifier("linked.autoSend")
                ProfileDivider()
                ProfileToggleRow(symbol: "clock", title: Text("Share caution history"), subtitle: Text("Coming soon"), isOn: .constant(true))
                    .disabled(true)
                    .accessibilityIdentifier("linked.shareWarnings")
            }
        }
        .padding(.horizontal, ProfileStyle.margin)
        // Figma: the card starts at y 340, 27 pt under the names.
        .padding(.top, 25)

        (Text(verbatim: guardian.name).fontWeight(.semibold) + Text(" ") + Text("can always see the blocked history"))
            .profileFont(15)
            .foregroundStyle(ProfileStyle.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(6)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 9)

        ProfileCard {
            ProfileRow(
                symbol: "lock.fill", title: Text("Disconnect"),
                subtitle: Text("Must use \(guardian.name)'s account"),
                accessory: .none, titleColor: ProfileStyle.secondary,
                iconTint: Color.dynamic(0x727272, dark: 0x9EA6B4), iconFill: Color.dynamic(0xEDEDED, dark: 0x2A303A)
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("profile.disconnect.locked")
        }
        .padding(.horizontal, ProfileStyle.margin)
        // Figma keeps the row near the bottom of the screen: its card starts at y 736.
        .padding(.top, 226)
    }

    private func person<Avatar: View>(name: Text, @ViewBuilder avatar: () -> Avatar) -> some View {
        VStack(spacing: 8) {
            avatar()
            // Figma "You" / "Adhella": SF Pro Display Semibold 17, line height 22.
            name
                .profileFont(17, .semibold)
                .figmaLineHeight(22, relativeTo: .body)
                .foregroundStyle(ProfileStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 92)
    }
}

/// The five blue dots between the two avatars, largest in the middle (Figma "Frame 1618872250").
/// A soft pulse runs from "You" to the guardian, so the link reads as live. Reduce Motion (Shoo's
/// setting or iOS's) keeps the Figma frame still.
private struct LinkDots: View {
    private static let dots: [(size: CGFloat, opacity: Double)] = [(9.16, 0.56), (11, 0.77), (14, 1), (11, 0.77), (9.16, 0.56)]
    /// One pass takes 1.4 s, then the dots rest for 0.6 s.
    private static let pass = 1.4, rest = 0.6

    @Environment(\.shooReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let phase = reduceMotion ? nil : Self.phase(at: context.date)
            HStack(spacing: 9.5) {
                ForEach(Array(Self.dots.enumerated()), id: \.offset) { index, dot in
                    let lift = phase.map { Self.lift(index: index, phase: $0) } ?? 0
                    Circle()
                        .fill(Color(hex: 0x0088FF, opacity: dot.opacity + (1 - dot.opacity) * lift))
                        .frame(width: dot.size, height: dot.size)
                        .scaleEffect(1 + 0.3 * lift)
                }
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    /// Where the pulse is: 0 before the first dot, 1 past the last, nil while resting.
    private static func phase(at date: Date) -> Double? {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: pass + rest)
        return t < pass ? t / pass : nil
    }

    /// 0…1: how close the pulse is to this dot (a smooth bump about 1.5 dots wide).
    private static func lift(index: Int, phase: Double) -> Double {
        let centre = -1 + phase * Double(dots.count + 1)
        let distance = abs(Double(index) - centre)
        guard distance < 1.5 else { return 0 }
        return 0.5 * (1 + cos(.pi * distance / 1.5))
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
                    style: .settings, isOn: binding(\.warning) { NotificationSettingsUpdate(warning: $0) }
                )
                .accessibilityIdentifier("notifications.warning")
                ProfileDivider()
                ProfileToggleRow(
                    symbol: "network.badge.shield.half.filled", title: Text("Blocked sites"), subtitle: Text("Every time Shoo blocks a site"),
                    style: .settings, isOn: binding(\.blocked) { NotificationSettingsUpdate(blocked: $0) }
                )
                .accessibilityIdentifier("notifications.blocked")
            }
            // Figma: the first title sits 24 pt under the back button; the header leaves 16.
            .padding(.top, model.notificationStatus.map { $0 != .authorized } ?? false ? 0 : -20)

            if model.variant == .guardian {
                ProfileSection(title: "Family · Guardian mode") {
                    ProfileToggleRow(
                        symbol: "person.fill", title: Text("Activity of people you protect"), subtitle: Text("When they open a dangerous site"),
                        style: .settings, isOn: binding(\.family) { NotificationSettingsUpdate(family: $0) }
                    )
                    .accessibilityIdentifier("notifications.family")
                    ProfileDivider()
                    ProfileToggleRow(
                        symbol: ProfileStyle.extensionSymbol, title: Text("Protection off"), subtitle: Text("When their extension is off"),
                        style: .settings, isOn: binding(\.protectionOff) { NotificationSettingsUpdate(protectionOff: $0) }
                    )
                    .accessibilityIdentifier("notifications.protectionOff")
                }
            }

            if model.variant == .protected {
                // Figma: Protected has no summary or quiet hours, and a switch for its guardian's checks.
                // Hidden until the server sends that push (#183).
                if LinkedAccountSettings.switchesAreLive {
                    @Bindable var linked = model.linked
                    ProfileSection(title: "Connected account") {
                        ProfileToggleRow(
                            symbol: "lock.fill", title: Text("Blocked link"), subtitle: Text("When the linked account verifies a link"),
                            style: .settings, isOn: $linked.notifyLinkVerified
                        )
                        .accessibilityIdentifier("notifications.linkVerified")
                    }
                }
            } else {
                summaryAndQuietHours
            }
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

    @ViewBuilder private var summaryAndQuietHours: some View {
        ProfileSection(title: "Summary") {
            ProfileToggleRow(
                symbol: "globe", title: Text("Weekly summary"), subtitle: Text("Every Monday, \(Self.clock("08:00", language: language))"),
                style: .settings, isOn: binding(\.weeklySummary) { NotificationSettingsUpdate(weeklySummary: $0) }
            )
            .accessibilityIdentifier("notifications.summary")
        }

        ProfileSection(title: "Quiet hours") {
            ProfileToggleRow(
                symbol: nil, title: Text("Quiet hours"),
                style: .settings, isOn: binding(\.quietHours) { NotificationSettingsUpdate(quietHours: $0) }
            )
            .accessibilityIdentifier("notifications.quietHours")
            ProfileDivider(leading: 17)
            Button { isQuietTimePresented = true } label: {
                ProfileRow(
                    symbol: nil, title: Text("Time"),
                    accessory: .value("\(Self.clock(settings.quietStart, language: language)) – \(Self.clock(settings.quietEnd, language: language))"),
                    minHeight: 44
                )
            }
            .buttonStyle(.plain)
            .disabled(!settings.quietHours)
            .opacity(settings.quietHours ? 1 : 0.5)
            .accessibilityIdentifier("notifications.quietTime")
        }
        PageNote(text: Text("Blocked-site alerts still come during quiet hours."))
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
        return Formatters.dateFormatter(template: "HHmm", locale: language.locale, timeZone: .gmt).string(from: date)
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
                Section {
                    DatePicker(selection: $start, displayedComponents: .hourAndMinute) { Text("Starts") }
                        .accessibilityIdentifier("quiet.start")
                    DatePicker(selection: $end, displayedComponents: .hourAndMinute) { Text("Ends") }
                        .accessibilityIdentifier("quiet.end")
                } footer: {
                    // Start = end would silence warnings all day (fase 27i, F-N6).
                    if !canSave {
                        Text("Start and end can't be the same time.")
                            .accessibilityIdentifier("quiet.sameTime")
                    }
                }
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
                    .disabled(!canSave)
                    .accessibilityIdentifier("quiet.save")
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var canSave: Bool { ProfileModel.canSaveQuietHours(start: Self.clock(start), end: Self.clock(end)) }

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
                // Figma lists Bahasa Indonesia first.
                ForEach(Array([AppLanguage.indonesian, .english].enumerated()), id: \.element) { index, language in
                    if index > 0 { ProfileDivider(leading: 17) }
                    RadioRow(
                        title: Text(Self.spokenName(language)),
                        subtitle: Text(Self.localName(language)),
                        isSelected: env.settings.language == language
                    ) { model.chooseLanguage(language) }
                        .accessibilityIdentifier("language.\(language.code)")
                }
            }
            // Figma: the first title sits 24 pt under the back button; the header leaves 16.
            .padding(.top, -20)
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
                // Figma "Pilihan Tema": three columns spread edge to edge, 20 / 16 inside the card.
                HStack(alignment: .top, spacing: 0) {
                    ThemeOption(image: "ThemePreviewLight", title: Text("Light"), isSelected: settings.theme == .light) { settings.theme = .light }
                        .accessibilityIdentifier("theme.light")
                    Spacer(minLength: 8)
                    ThemeOption(image: "ThemePreviewDark", title: Text("Dark"), isSelected: settings.theme == .dark) { settings.theme = .dark }
                        .accessibilityIdentifier("theme.dark")
                    Spacer(minLength: 8)
                    ThemeOption(image: "ThemePreviewSystem", title: Text("Automatic"), isSelected: settings.theme == .system) { settings.theme = .system }
                        .accessibilityIdentifier("theme.system")
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 16)
            }
            // Figma: the first title sits 24 pt under the back button; the header leaves 16.
            .padding(.top, -20)
            PageNote(text: Text("Automatic follows light or dark mode on your iPhone."))

            ProfileSection(title: "Effects", top: 24) {
                ProfileToggleRow(
                    symbol: "circle.lefthalf.filled", title: Text("Reduce glass effects"),
                    subtitle: Text("Solid card backgrounds that also save battery"),
                    style: .settings, isOn: $settings.reduceGlass
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
            // Figma: the chosen preview sits in a 2 pt blue ring 3 pt out (94 × 160); the others keep
            // only the 3 pt inset (90 × 156), so their name and radio sit 4 pt higher.
            VStack(spacing: 10) {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 150)
                    .padding(isSelected ? 5 : 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 21, style: .continuous)
                            .strokeBorder(ProfileStyle.link, lineWidth: 2)
                            .opacity(isSelected ? 1 : 0)
                            // The ring still fades with Reduce Motion, when the 4 pt move snaps.
                            .animation(.easeInOut(duration: 0.2), value: isSelected)
                    )
                title
                    .profileFont(15, isSelected ? .medium : .regular, tracking: -0.15)
                    .foregroundStyle(ProfileStyle.ink)
                ProfileRadio(isOn: isSelected)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The 5 ↔ 3 pt inset moves the name and radio 4 pt: eased, or snapped with Reduce Motion.
        .modifier(ProfileSelectionMotion(isSelected: isSelected, movesLayout: true))
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
                            Text(verbatim: "bca-verifikasi.site").profileFont(20, tracking: -0.2).foregroundStyle(ProfileStyle.ink)
                            Text("Today · \(Self.sampleTime(locale: locale))").profileFont(15, rounded: true).foregroundStyle(ProfileStyle.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(ProfileStyle.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityHidden(true)
                    TextSizeSlider(level: $settings.textSize)
                    Text(verbatim: L10n.string(settings.textSize.title, language: AppLanguage(locale: locale)))
                        .profileFont(15, .medium, tracking: -0.15)
                        .foregroundStyle(ProfileStyle.ink)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                // Figma: 18 inside the card's 1 pt border; ProfileCard already adds 5 above and below.
                .padding(.horizontal, 19)
                .padding(.vertical, 14)
            }
            // Figma: the first title sits 24 pt under the back button; the header leaves 16.
            .padding(.top, -20)

            ProfileSection(title: "Display") {
                ProfileToggleRow(symbol: "Aa", title: Text("Bold text"), style: .settings, isOn: $settings.boldText)
                    .accessibilityIdentifier("accessibility.bold")
                ProfileDivider()
                ProfileToggleRow(symbol: "circle.lefthalf.filled", title: Text("High contrast"), style: .settings, isOn: $settings.highContrast)
                    .accessibilityIdentifier("accessibility.contrast")
                ProfileDivider()
                ProfileToggleRow(
                    symbol: ProfileStyle.extensionSymbol, title: Text("Reduce motion"), subtitle: Text("Turns off gauge and card-swipe animations"),
                    style: .settings, isOn: $settings.reduceMotion
                )
                .accessibilityIdentifier("accessibility.reduceMotion")
            }

            ProfileSection(title: "When there is a warning") {
                ProfileToggleRow(symbol: "bell.fill", title: Text("Vibrate"), style: .settings, isOn: $settings.haptics)
                    .accessibilityIdentifier("accessibility.haptics")
                ProfileDivider()
                ProfileToggleRow(
                    symbol: "person.fill", title: Text("Read warnings aloud"), subtitle: Text("The score and reasons are read with VoiceOver"),
                    style: .settings, isOn: $settings.readAloud
                )
                .accessibilityIdentifier("accessibility.readAloud")
            }
        }
    }

    /// "10.42" / "10:42".
    private static func sampleTime(locale: Locale) -> String {
        Formatters.dateFormatter(template: "HHmm", locale: locale, timeZone: .gmt)
            .string(from: Date(timeIntervalSince1970: 10 * 3600 + 42 * 60))
    }
}

/// Five stops from a small "A" to a large "A" (Figma "Slider"). VoiceOver: swipe up or down.
private struct TextSizeSlider: View {
    @Binding var level: TextSizeLevel
    @Environment(\.locale) private var locale
    @Environment(\.shooReduceMotion) private var reduceMotion

    private let levels = TextSizeLevel.allCases

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: "A").font(FigmaFont.font(size: 13, weight: .medium)).foregroundStyle(ProfileStyle.secondary)
            GeometryReader { geo in
                // Figma "Track" 268: the rail runs from its left edge to 6 pt short of its right edge.
                let inset: CGFloat = 0
                let trailing: CGFloat = 6
                let step = (geo.size.width - inset - trailing) / CGFloat(levels.count - 1)
                let x = { (i: Int) in inset + step * CGFloat(i) }
                ZStack(alignment: .leading) {
                    Capsule().fill(ProfileStyle.sliderRail).frame(height: 4).padding(.leading, inset).padding(.trailing, trailing)
                    Capsule().fill(ProfileStyle.link).frame(width: x(level.rawValue) - inset, height: 4).padding(.leading, inset)
                    ForEach(levels, id: \.rawValue) { stop in
                        Circle()
                            .fill(stop.rawValue <= level.rawValue ? ProfileStyle.link : ProfileStyle.chevron)
                            .frame(width: 8, height: 8)
                            .offset(x: x(stop.rawValue) - 4)
                    }
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
                        .frame(width: 28, height: 28)
                        .offset(x: x(level.rawValue) - 14)
                }
                // The thumb and the blue rail glide to the next stop; Reduce Motion: they jump.
                .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: level)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let index = Int(((value.location.x - inset) / step).rounded())
                    if let new = TextSizeLevel(rawValue: min(max(index, 0), levels.count - 1)), new != level { level = new }
                })
            }
            .frame(height: 28)
            Text(verbatim: "A").font(FigmaFont.font(size: 22, weight: .medium)).foregroundStyle(ProfileStyle.ink)
        }
        .sensoryFeedback(.selection, trigger: level)
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

    private func page(_ path: String) -> URL { AppConfig.legalPage(path, language: language) }

    var body: some View {
        ProfileScreen(title: "About Shoo") {
            VStack(spacing: 0) {
                Image("AboutAppIcon")
                    .resizable()
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)
                Text(verbatim: "Shoo")
                    .profileFont(28, .bold, tracking: -0.56)
                    .foregroundStyle(ProfileStyle.nameInk)
                    .padding(.top, 16)
                    .accessibilityAddTraits(.isHeader)
                Text("Version \(version)")
                    .profileFont(13, rounded: true)
                    .foregroundStyle(ProfileStyle.secondary)
                    // Figma sets it on a 20 pt line.
                    .padding(.vertical, 2)
                    .padding(.top, 3)
                Text("Protect yourself and your family from scam sites.")
                    .profileFont(15, tracking: -0.15)
                    .foregroundStyle(ProfileStyle.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.horizontal, ProfileStyle.margin)
            }
            // Figma: the icon starts 28 pt under the back button; the header leaves 16.
            .padding(.top, 12)

            // Apple 5.1.1(ii), 5.1.2(i): the online check can be taken back at any time. It lives here, not on
            // Profile, next to the privacy policy that explains it.
            ProfileCard {
                ProfileToggleRow(
                    symbol: nil,
                    title: Text("Online check"),
                    subtitle: Text("Sends pages to Shoo's server and suspicious-page summaries to DeepSeek"),
                    style: .settings,
                    isOn: Binding(
                        get: { env.settings.dataConsent == .granted },
                        set: { env.setDataConsent($0 ? .granted : .declined) }
                    )
                )
                .accessibilityIdentifier("about.onlineCheck")
            }
            .padding(.horizontal, ProfileStyle.margin)
            .padding(.top, 32)

            ProfileCard {
                linkRow(Text("Privacy policy"), id: "about.privacy") { openURL(page("privacy")) }
                ProfileDivider(leading: 17)
                linkRow(Text("Terms of use"), id: "about.terms") { openURL(page("terms")) }
                ProfileDivider(leading: 17)
                linkRow(Text("Third-party licenses"), id: "about.licenses", isLink: false) { env.router.show(.profilePage(.licenses)) }
            }
            .padding(.horizontal, ProfileStyle.margin)
            .padding(.top, 20)

            ProfileCard {
                linkRow(Text("Rate on the App Store"), id: "about.rate") { rate() }
                ProfileDivider(leading: 17)
                ShareLink(item: AppConfig.shareURL, message: Text("Shoo blocks scam sites in Safari. Try it:")) {
                    ProfileRow(symbol: nil, title: Text("Share Shoo"), minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("about.share")
                ProfileDivider(leading: 17)
                linkRow(Text("Contact us"), value: AppConfig.supportEmail, id: "about.contact") {
                    if let url = URL(string: "mailto:\(AppConfig.supportEmail)") { openURL(url) }
                }
            }
            .padding(.horizontal, ProfileStyle.margin)
            .padding(.top, 20)

            Text("© 2026 Shoo · Made in Indonesia")
                .profileFont(13, rounded: true)
                .foregroundStyle(ProfileStyle.secondary)
                // Figma sets it on a 20 pt line.
                .padding(.vertical, 2)
                .padding(.top, 28)
        }
    }

    private func linkRow(_ title: Text, value: String? = nil, id: String, isLink: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Figma "Tentang Shoo": 44 pt text rows.
            ProfileRow(symbol: nil, title: title, accessory: value.map { .value($0) } ?? .chevron, minHeight: 44)
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
