import SwiftUI

/// Profile (PF-01), pushed from the avatar button on either tab. Figma "Profile/Pribadi" (Guardian,
/// Family mode off), "Profile/Guardian" (Family mode on) and the Protected profile ("Bu Maria").
struct ProfileView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var model: ProfileModel
    @State private var extensionStatus = ExtensionStatus.off(lastSeen: nil)
    @State private var isTurnOnPresented = false
    @State private var isInvitePresented = false
    @State private var isDeleteConfirming = false
    @State private var remindingId: String?

    init(repository: any ShooRepository, settings: AppSettings, notifications: (any NotificationPermission)? = nil) {
        _model = State(initialValue: ProfileModel(repository: repository, settings: settings, notifications: notifications))
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        ProfileScreen(title: "Profile") {
            switch model.state {
            case .loading:
                ShieldPulseLoader()
                    .frame(maxWidth: .infinity, minHeight: 300)
            case .failed:
                VStack(spacing: 12) {
                    Text("Couldn't load your profile").profileFont(17, .semibold)
                    Button { Task { await model.retry() } } label: { Text("Try again") }
                        .buttonStyle(ProfilePillButtonStyle(tint: ProfileStyle.link))
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            case .loaded:
                loaded
            }
        }
        .task {
            // Disconnect / delete hand the app back to onboarding: clear navigation first.
            model.onSessionEnd = { [env, router = env.router] in
                env.leaveDemo()
                router.reset()
                DeliveredPushes.clear()
            }
            await model.load()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            extensionStatus = await env.extensionStatus()
            await model.refreshNotifications()
            model.linked.refresh()
        }
        .sheet(isPresented: $isTurnOnPresented, onDismiss: { Task { extensionStatus = await env.extensionStatus() } }) {
            TurnOnExtensionSheet()
        }
        .sheet(isPresented: $isInvitePresented, onDismiss: { Task { await model.load() } }) {
            InviteSheet(repository: env.repository) { isInvitePresented = false }
                .environment(\.locale, locale)
        }
        .deleteAccountSheet(model: model, isPresented: $isDeleteConfirming)
        .alert(
            Text(verbatim: model.actionError.map { L10n.string($0, language: language) } ?? ""),
            isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
        // Names and the family list stay out of the app switcher snapshot (D-alief-A36).
        .privacyCover()
    }

    @ViewBuilder private var loaded: some View {
        ProfileHeaderCard(
            banner: "ProfileBanner",
            avatarShadow: model.variant == .protected ? .glow : .none,
            // Figma 455:10289: the pill's ring ends 20 pt above the avatar's bottom (its 44 pt tap frame 18.5).
            badgeBottom: model.variant == .protected ? -18.5 : 5,
            name: model.profile?.name ?? "",
            handle: model.handle(language: language),
            stats: model.stats(language: language)
        ) {
            AvatarView(id: model.profile?.avatarId ?? "", size: 88)
                .overlay(alignment: .bottomTrailing) {
                    if model.variant == .protected, let guardian = model.profile?.guardian {
                        GuardianBadge(name: guardian.name, avatarId: guardian.avatarId)
                            .offset(x: 16, y: 4)
                    }
                }
        } badge: {
            if model.variant == .protected {
                if model.profile?.guardian != nil {
                    Button { env.router.show(.profilePage(.connection)) } label: {
                        HStack(spacing: 5.5) {
                            ConnectedPillButtonStyle.glyph
                            Text("Connected")
                        }
                    }
                    .buttonStyle(ConnectedPillButtonStyle())
                    .accessibilityHint(Text("Shows your linked account"))
                    .accessibilityIdentifier("profile.connectedPill")
                    // Figma 455:10289: the pill ends 21.4 pt from the card's edge, 9.4 inside the 12 pt row inset.
                    .padding(.trailing, -2.4)
                }
            } else {
                Button { isInvitePresented = true } label: {
                    HStack(spacing: 8) {
                        QRGlyph()
                        Text("Share invite")
                    }
                }
                .buttonStyle(ProfilePillButtonStyle(padding: ProfilePillButtonStyle.invitePadding))
                .accessibilityIdentifier("profile.invite")
            }
        }

        if model.showsGuardianCard {
            GuardianModeCard {
                model.becomeGuardian()
            } onDismiss: {
                model.dismissGuardianCard()
            }
        }
        if model.variant == .guardian { familySection }
        if model.variant == .protected { guardianSection }
        protectionSection
        accountSection
        preferencesSection
        privacySection

        Button { isDeleteConfirming = true } label: {
            // Figma "Hapus Akun" (title case here, unlike the Kelola profil row): SF Pro Rounded 17.
            Text("Delete Account")
                .profileBody()
                .foregroundStyle(ProfileStyle.red)
                .frame(minWidth: 44, minHeight: 44)
        }
        .disabled(model.isWorking)
        // Figma: the text starts 28 pt under the last card; the 44 pt tap area adds 11 above its 22 pt line.
        .padding(.top, 17)
        .accessibilityIdentifier("profile.delete")
    }

    // MARK: Sections

    /// Protected sections sit 15 pt apart (Figma "Profile/Pribadi" of the protected user), others 28.
    private var sectionTop: CGFloat { model.variant == .protected ? 15 : 28 }

    /// Title to card: 12 on the Protected profile (Figma 455:10275), 10 elsewhere (1115:14392).
    private var sectionSpacing: CGFloat { model.variant == .protected ? 12 : 10 }

    /// Protected: "Terhubung", the guardian who gets the warnings.
    @ViewBuilder private var guardianSection: some View {
        if let guardian = model.profile?.guardian {
            ProfileSection(title: "Connected", spacing: 24) {
                Button { env.router.show(.profilePage(.connection)) } label: {
                    HStack(spacing: 12) {
                        InitialsAvatar(name: guardian.name, avatarId: guardian.avatarId, size: 33)
                        Text(verbatim: guardian.name)
                            .profileBody()
                            .foregroundStyle(ProfileStyle.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ProfileStyle.chevron)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 17)
                    .frame(minHeight: 55)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Shows your linked account"))
                .accessibilityIdentifier("profile.guardianRow")
            }
        }
    }

    /// Pribadi and Protected: "Perlindungan" with the extension status (the switch lives in Safari).
    @ViewBuilder private var protectionSection: some View {
        if model.variant != .guardian {
            ProfileSection(title: "Protection", top: protectionTop, spacing: sectionSpacing) {
                extensionRow
            }
        }
    }

    private var extensionRow: some View {
        Button { if !extensionStatus.isActive { isTurnOnPresented = true } } label: {
            ProfileRow(
                symbol: ProfileStyle.extensionSymbol,
                title: Text("Safari extension"),
                // Pribadi (1115:14424): a green dot and "Terhubung" in green. Protected (455:10275): "Aktif" in grey.
                // No chevron either way: the row does nothing while on.
                accessory: extensionStatus.isActive
                    ? (model.variant == .protected
                        ? .value(L10n.string("Active", language: language), chevron: false)
                        : .status(L10n.string("Connected", language: language), dot: ProfileStyle.green, color: ProfileStyle.greenText))
                    : .value(L10n.string("Off", language: language), color: ProfileStyle.red)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(extensionStatus.isActive ? Text(verbatim: "") : Text("Shows how to switch Shoo on in Safari"))
        .accessibilityIdentifier(extensionStatus.isActive ? "profile.extension.active" : "profile.extension.off")
    }

    /// Figma: 32 pt under the profile card, 28 under the "Mode Guardian" card, 15 on the Protected profile.
    private var protectionTop: CGFloat {
        if model.variant == .protected { return model.profile?.guardian != nil ? sectionTop : 28 }
        return model.showsGuardianCard ? 28 : 32
    }

    private var familySection: some View {
        // Figma: 32 pt under the profile card (416:10447, 480:5353).
        ProfileSection(title: "People you protect", top: 32) {
            if model.membersFailed {
                VStack(spacing: 8) {
                    Text("Couldn't load your family").profileFont(15).foregroundStyle(ProfileStyle.secondary)
                    Button { Task { await model.load() } } label: { Text("Try again") }
                        .buttonStyle(ProfilePillButtonStyle(tint: ProfileStyle.link))
                        .accessibilityIdentifier("profile.members.retry")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else if model.members.isEmpty {
                FamilyEmptyCard { isInvitePresented = true }
            } else {
                ForEach(Array(model.members.enumerated()), id: \.element.id) { index, member in
                    if index > 0 { ProfileDivider(leading: 73) }
                    memberRow(member)
                }
            }
        }
    }

    private func memberRow(_ member: FamilyMember) -> some View {
        HStack(spacing: 12) {
            Button { env.router.show(.member(deviceId: member.deviceId)) } label: {
                HStack(spacing: 12) {
                    // Figma: a member whose extension is off has a half-faded avatar.
                    InitialsAvatar(name: member.name, avatarId: member.avatarId)
                        .opacity(member.extensionActive ? 1 : 0.5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: member.name)
                            .profileBody()
                            .foregroundStyle(ProfileStyle.nameInk)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(member.extensionActive ? ProfileStyle.green : ProfileStyle.offDot)
                                .frame(width: 7, height: 7)
                                .accessibilityHidden(true)
                            Text(verbatim: MemberText.status(member, now: Date(), language: language))
                                .profileCaption()
                                .foregroundStyle(ProfileStyle.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if member.extensionActive, let seen = member.lastSeenAt {
                        Text(verbatim: MemberText.ago(seen, language: language))
                            .profileCaption()
                            .foregroundStyle(ProfileStyle.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("Shows this person's protection"))
            .accessibilityIdentifier("profile.member.\(member.deviceId)")
            if !member.extensionActive {
                RemindButton(member: member, isWorking: remindingId == member.deviceId) {
                    remindingId = member.deviceId
                    if let message = await model.remind(member) { announce(message) }
                    remindingId = nil
                }
            }
        }
        .padding(.horizontal, 17)
        .frame(minHeight: 72)
    }

    private var accountSection: some View {
        ProfileSection(title: "Account", top: sectionTop, spacing: sectionSpacing) {
            if model.variant == .protected {
                // Figma: Kelola profil first, then Terhubung.
                navRow(symbol: "person.fill", title: Text("Manage profile"), page: .editProfile, id: "profile.manage")
                ProfileDivider()
                navRow(symbol: ProfileStyle.switchSymbol, title: Text("Connected"), page: .connection, id: "profile.connection")
            } else {
                navRow(
                    symbol: ProfileStyle.switchSymbol, title: Text("Account mode"),
                    value: L10n.string(model.variant == .guardian ? "Guardian" : "Personal", language: language),
                    page: .mode, id: "profile.mode"
                )
                ProfileDivider()
                navRow(symbol: "person.fill", title: Text("Manage profile"), page: .editProfile, id: "profile.manage")
            }
            ProfileDivider()
            navRow(symbol: "bell.fill", title: Text("Notifications"), page: .notifications, id: "profile.notifications")
            ProfileDivider()
            navRow(symbol: "globe", title: Text("Language"), value: language.shortName, page: .language, id: "profile.language")
        }
    }

    private var preferencesSection: some View {
        ProfileSection(title: "Preferences", top: sectionTop, spacing: sectionSpacing) {
            navRow(
                symbol: "circle.lefthalf.filled", title: Text("Theme"),
                value: L10n.string(themeTitle, language: language),
                page: .theme, id: "profile.theme"
            )
            ProfileDivider()
            navRow(
                symbol: "Aa", title: Text("Accessibility"),
                value: L10n.string(env.settings.textSize.title, language: language),
                page: .accessibility, id: "profile.accessibility"
            )
            ProfileDivider()
            navRow(symbol: "text.magnifyingglass", title: Text("About Shoo"), page: .about, id: "profile.about")
        }
    }

    /// Apple 5.1.1: the online check can be taken back at any time.
    private var privacySection: some View {
        ProfileSection(title: "Privacy", top: sectionTop, spacing: sectionSpacing) {
            ProfileToggleRow(
                symbol: "checkmark.shield",
                title: Text("Online check"),
                subtitle: Text("Sends pages to Shoo's server and suspicious-page summaries to DeepSeek"),
                isOn: Binding(
                    get: { env.settings.dataConsent == .granted },
                    set: { env.setDataConsent($0 ? .granted : .declined) }
                )
            )
            .accessibilityIdentifier("profile.onlineCheck")
        }
    }

    private var themeTitle: String.LocalizationValue {
        switch env.settings.theme {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "Automatic"
        }
    }

    private func navRow(symbol: String, title: Text, value: String? = nil, page: ProfilePage, id: String) -> some View {
        Button { env.router.show(.profilePage(page)) } label: {
            ProfileRow(symbol: symbol, title: title, accessory: value.map { .value($0) } ?? .chevron)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // MARK: Actions

    private func announce(_ message: String.LocalizationValue) {
        AccessibilityNotification.Announcement(L10n.string(message, language: language)).post()
    }
}

/// "Ingatkan" pill; "Sent" (disabled) for 6 hours after a reminder.
struct RemindButton: View {
    let member: FamilyMember
    let isWorking: Bool
    let action: () async -> Void

    var body: some View {
        let sent = MemberText.recentlyReminded(member)
        Button { Task { await action() } } label: {
            if isWorking {
                ProgressView().frame(width: 62)
            } else {
                Text(sent ? "Sent" : "Remind")
            }
        }
        .buttonStyle(ProfilePillButtonStyle(tint: sent ? ProfileStyle.secondary : ProfileStyle.link, large: true))
        .disabled(sent || isWorking)
        .accessibilityLabel(sent ? Text("Reminder sent to \(member.name)") : Text("Remind \(member.name)"))
        .accessibilityHint(sent ? Text(verbatim: "") : Text("Sends a notification to turn on Shoo in Safari"))
        .accessibilityIdentifier("profile.remind.\(member.deviceId)")
    }
}

/// Text built from a member (rows and the member detail).
enum MemberText {
    /// "Active · iPhone · Safari" / "Extension off for 2 days".
    static func status(_ member: FamilyMember, now: Date, language: AppLanguage) -> String {
        if member.extensionActive {
            let device = member.deviceModel.map { $0.hasPrefix("iPad") ? "iPad" : "iPhone" }
            return [L10n.string("Active", language: language), device, "Safari"].compactMap { $0 }.joined(separator: " · ")
        }
        guard let seen = member.lastSeenAt else { return L10n.string("Extension off", language: language) }
        return L10n.string("Extension off for \(duration(from: seen, to: now, language: language))", language: language)
    }

    /// "2 mnt lalu".
    static func ago(_ date: Date, now: Date = Date(), language: AppLanguage) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = language.locale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }

    /// "2 days" / "2 hari".
    static func duration(from start: Date, to end: Date, language: AppLanguage) -> String {
        var calendar = Calendar.current
        calendar.locale = language.locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = [.day, .hour, .minute]
        return formatter.string(from: start, to: max(start, end)) ?? ""
    }

    static func recentlyReminded(_ member: FamilyMember, now: Date = Date()) -> Bool {
        guard let last = member.remindedAt else { return false }
        return now.timeIntervalSince(last) < 6 * 3600
    }
}

extension AppLanguage {
    /// "Indonesia" / "English" on the Language row (Figma).
    var shortName: String {
        switch self {
        case .english: "English"
        case .indonesian: "Indonesia"
        }
    }
}

#Preview("Pribadi") {
    let env = AppEnvironment.preview()
    return NavigationStack {
        ProfileView(repository: env.repository, settings: env.settings, notifications: env.notifications)
    }
    .environment(env)
}
