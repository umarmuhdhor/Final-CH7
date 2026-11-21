import SwiftUI

/// Figma "Guardian/Detail Orang Dilindungi" (PF-01): a protected member as their guardian sees them.
struct MemberDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale
    @State private var model: MemberDetailModel
    @State private var isDisconnectConfirming = false
    @Environment(\.shooReduceMotion) private var reduceMotion

    init(deviceId: String, repository: any ShooRepository) {
        _model = State(initialValue: MemberDetailModel(deviceId: deviceId, repository: repository))
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        ProfileScreen(title: "Protected person", titleSize: 17) {
            switch model.state {
            case .loading:
                ShieldPulseLoader()
                    .frame(maxWidth: .infinity, minHeight: 300)
            case .failed:
                // Figma "Gagal memuat" (1681:6968).
                StateMessage(
                    systemImage: "exclamationmark.arrow.circlepath",
                    tint: Color(hex: 0xE5483B),
                    tileFill: .white,
                    title: "Data can't be viewed yet",
                    message: Text(verbatim: L10n.string(
                        model.loadFailure.message(connection: "Check your internet connection, then try again."), language: language
                    ))
                )
                .padding(.horizontal, ProfileStyle.margin)
                .padding(.top, 90)
                .accessibilityIdentifier("member.failed")
            case .gone:
                // Figma "Sudah tidak terhubung" (1681:6955).
                StateMessage(
                    systemImage: "person.2.fill",
                    symbolSize: 27,
                    tint: Color(hex: 0x6A717E),
                    tileFill: .white,
                    title: "No longer connected",
                    message: Text("This person has disconnected. You no longer get warnings from them.")
                )
                .padding(.horizontal, ProfileStyle.margin)
                .padding(.top, 90)
                .accessibilityIdentifier("member.gone")
            case .loaded:
                if let member = model.member { loaded(member) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.state == .failed || model.state == .gone {
                Button("Back") { env.router.pop() }
                    .buttonStyle(OnboardingCapsuleButtonStyle())
                    // Figma: 306 wide (48 in from each side), its foot 84 above the frame's.
                    .padding(.horizontal, 48)
                    .padding(.bottom, 48)
                    .transition(.opacity)
                    .accessibilityIdentifier("member.back")
            }
        }
        .task { await model.load() }
        // A push while this screen is open (new scan, verdict, member change): reload, as Guardian Home does (A-12).
        .onChange(of: env.pushesWhileOpen) { _, count in
            Task { await model.pushesWhileOpenChanged(to: count) }
        }
        // Figma "Dialog Shoo · Putuskan koneksi" (2428:12722), pose Kaget. F10: it says what happens to them.
        // Action errors use the same dialog (one cover at a time): a failed disconnect turns into the error.
        .shooDialog(isPresented: Binding(
            get: { isDisconnectConfirming || model.actionError != nil },
            set: { if !$0 { isDisconnectConfirming = false; model.actionError = nil } }
        )) {
            if let error = model.actionError { return ShooDialog.error(L10n.string(error, language: language)) }
            let name = model.member?.name ?? ""
            return ShooDialog(
                pose: .shock,
                title: Text("Disconnect from \(name)?"),
                // DELETE /family/members: only the link goes; the member keeps Shoo, gets a push, and the
                // guardian's Safe / Not safe marks on their sites are dropped (dropVerdicts).
                message: Text("Shoo stays on on \(name)'s iPhone. You stop seeing their activity, and your Safe / Not safe marks are removed. \(name) will be told."),
                tone: .danger,
                primary: .init(title: Text("Yes, disconnect"), identifier: "member.disconnect.confirm", closes: false) {
                    disconnect()
                },
                secondary: .init(title: Text("Cancel"), identifier: "profile.confirm.cancel"),
                isWorking: model.isWorking,
                identifier: "member.disconnectDialog"
            )
        }
        .privacyCover()
    }

    private func disconnect() {
        guard let member = model.member else { return }
        Task {
            // On failure `actionError` turns the open dialog into the error.
            guard await model.disconnect() else { return }
            env.familyChanges += 1
            isDisconnectConfirming = false
            // Option A: back on Home, which says who is gone (neutral, no success tap).
            env.router.landOnHome(saying: .disconnected(name: member.name))
        }
    }

    @ViewBuilder private func loaded(_ member: FamilyMember) -> some View {
        ProfileHeaderCard(
            banner: "MemberBanner",
            bannerHeight: 112,
            badgeBottom: -1,
            name: member.name,
            handle: handle(member),
            stats: stats(member),
            attachment: member.extensionActive ? nil : AnyView(offBanner(member))
        ) {
            AvatarView(id: member.avatarId, size: 86)
                .frame(width: 88, height: 88)
        } badge: {
            statusPill(active: member.extensionActive)
        }

        // Figma: 32 pt under the profile card.
        ProfileSection(title: "Protection", top: 32) {
            ProfileRow(
                symbol: ProfileStyle.extensionSymbol, title: Text("Safari extension"),
                accessory: member.extensionActive
                    ? .value(L10n.string("Active", language: language), color: ProfileStyle.greenText, chevron: false)
                    : .value(L10n.string("Not active", language: language), color: ProfileStyle.red, chevron: false)
            )
            .accessibilityElement(children: .combine)
            if let device = deviceText(member) {
                ProfileDivider()
                ProfileRow(symbol: "person.fill", title: Text("Device"), accessory: .value(device, chevron: false))
                    .accessibilityElement(children: .combine)
            }
            if let since = member.connectedAt {
                ProfileDivider()
                ProfileRow(
                    symbol: "globe", title: Text("Connected since"),
                    accessory: .value(since.formatted(.dateTime.day().month(.abbreviated).year().locale(language.locale)), chevron: false)
                )
                .accessibilityElement(children: .combine)
            }
            if let notify = member.notify {
                ProfileDivider()
                ProfileToggleRow(
                    symbol: "bell.fill", title: Text("Notify me"), subtitle: Text("When they open a dangerous site"),
                    isOn: Binding(get: { notify }, set: { on in Task { await model.setNotify(on) } })
                )
                .accessibilityIdentifier("member.notify")
            }
        }

        ProfileSection(title: "Latest activity", trailing: AnyView(
            Button { env.router.show(.memberActivity(deviceId: member.deviceId)) } label: {
                Text("View all")
                    .profileFont(15, .medium, tracking: -0.15)
                    .foregroundStyle(ProfileStyle.link)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            // Keeps the 44 pt tap area without pushing the card down (Figma: card 32 pt under the title).
            .padding(.vertical, -12)
            .accessibilityIdentifier("member.seeAll")
        )) {
            if model.recent.isEmpty {
                Text(model.recentFailed ? "Couldn't load activity" : "No activity yet")
                    .profileFont(15)
                    .foregroundStyle(ProfileStyle.secondary)
                    .frame(maxWidth: .infinity, minHeight: 58)
            } else {
                ForEach(Array(model.recent.enumerated()), id: \.element.id) { index, scan in
                    if index > 0 { ProfileDivider() }
                    Button { env.router.show(.detail(scanId: scan.id)) } label: { activityRow(scan) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("member.scan.\(scan.id)")
                }
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            ProfileCard {
                Button { isDisconnectConfirming = true } label: {
                    ProfileRow(
                        symbol: "xmark", title: Text("Disconnect"), titleColor: ProfileStyle.red, titleWeight: .medium,
                        iconTint: ProfileStyle.red, iconFill: ProfileStyle.redIconFill
                    )
                }
                .buttonStyle(.plain)
                .disabled(model.isWorking)
                .accessibilityIdentifier("member.disconnect")
            }
            Text("You stop getting warnings from \(member.name)'s activity. \(member.name) will be told.")
                .profileFont(13, rounded: true)
                .foregroundStyle(ProfileStyle.secondary)
                .lineSpacing(3)
                .padding(.horizontal, 16)
        }
        .padding(.horizontal, ProfileStyle.margin)
        .padding(.top, 28)
    }

    /// Figma "Pesan ekstensi mati" (1681:6718) and "Pengingat terkirim" (1681:6837): orange while the extension is
    /// off, green once a reminder went out. The swap cross-fades; the check bounces in.
    /// C3 (goldfish 21 Nov, Figma "Usulan · detail anggota"): the server only knows Shoo on their phone sent no word
    /// for 24 h, not why, so the card lists what to check on that phone, then a full-width "Ingatkan {nama}".
    private func offBanner(_ member: FamilyMember) -> some View {
        let sent = MemberText.recentlyReminded(member)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: sent ? "checkmark" : "exclamationmark.triangle.fill")
                    .font(.system(size: 21.67, weight: sent ? .semibold : .regular))
                    .foregroundStyle(sent ? Color(hex: 0x269E4A) : Color(hex: 0xEF871C))
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                    .frame(width: 40, height: 40)
                    .background(sent ? Color(hex: 0x34C759).opacity(0.14) : Color(hex: 0xEF871C).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sent ? "Reminder sent" : "Safari extension off")
                        .profileFont(16, .semibold, tracking: -0.31)
                        .foregroundStyle(Color(hex: 0x151617))
                    Text(verbatim: sent
                        ? L10n.string("\(member.name) will get a notification.", language: language)
                        : Self.quietText(member, language: language))
                        .profileFont(13, rounded: true)
                        .foregroundStyle(Color(hex: 0x6A717E))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }

            Rectangle().fill(Color(hex: 0xEF871C).opacity(0.2)).frame(height: 1)
                .padding(.vertical, 14)
                .accessibilityHidden(true)

            Text("To check on \(member.name)'s phone")
                .profileFont(13, .semibold)
                .foregroundStyle(Color(hex: 0x151617))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) {
                checkItem(1, "Settings › Apps › Safari › Extensions › Shoo is on, with “Allow” for every website.")
                checkItem(2, "Safari is used to open sites. Shoo only sends word while Safari is in use.")
                checkItem(3, "The phone is online, and the Shoo app is still installed.")
            }
            .padding(.top, 12)

            if !sent {
                Button {
                    Task {
                        // A problem shows as an alert, which VoiceOver reads; only "sent" is announced.
                        if let message = await model.remind(), model.actionError == nil {
                            AccessibilityNotification.Announcement(L10n.string(message, language: language)).post()
                        }
                    }
                } label: {
                    ZStack {
                        Text("Remind \(member.name)").opacity(model.isReminding ? 0 : 1)
                        if model.isReminding { ProgressView().controlSize(.small).tint(.white) }
                    }
                }
                .buttonStyle(MemberRemindButtonStyle())
                .disabled(model.isReminding)
                .padding(.top, 16)
                .accessibilityHint(Text("Sends a notification to turn on Shoo in Safari"))
                .accessibilityIdentifier("profile.remind.\(member.deviceId)")
                .transition(.opacity)
            }
        }
        .padding(16)
        .background(sent ? Color(hex: 0xEBF8ED).opacity(0.9) : Color(hex: 0xF8F2EB).opacity(0.9))
        .overlay(alignment: .top) {
            Rectangle().fill(sent ? Color(hex: 0x1CEF1C).opacity(0.35) : Color(hex: 0xEF871C).opacity(0.35)).frame(height: 1)
        }
        .animation(.easeInOut(duration: 0.25), value: sent)
        .sensoryFeedback(.success, trigger: sent) { was, now in !was && now }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(sent ? "member.reminded" : "member.off")
    }

    /// One numbered line of "Yang perlu dicek di HP {nama}" (Figma: 22 pt circle, 11 pt bold number, 13 pt text).
    private func checkItem(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "\(number)")
                .profileFont(11, .bold)
                .foregroundStyle(Color(hex: 0x6A717E))
                .frame(width: 22, height: 22)
                .background(Circle().fill(.white))
                .overlay(Circle().strokeBorder(Color(hex: 0xEF871C).opacity(0.35), lineWidth: 1))
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                .accessibilityHidden(true)
            Text(text)
                .profileFont(13, rounded: true)
                .foregroundStyle(Color(hex: 0x3C3C43))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Belum ada kabar dari Shoo di HP Dad sejak 21 hari lalu." Without a last heartbeat: "… di HP Dad."
    static func quietText(_ member: FamilyMember, now: Date = Date(), language: AppLanguage) -> String {
        guard let seen = member.lastSeenAt else {
            return L10n.string("No word yet from Shoo on \(member.name)'s phone.", language: language)
        }
        let span = MemberText.duration(from: seen, to: now, language: language)
        return L10n.string("No word from Shoo on \(member.name)'s phone for \(span).", language: language)
    }

    private func activityRow(_ scan: ScanResult) -> some View {
        HStack(spacing: 12) {
            ProfileIcon(symbol: "globe")
            VStack(alignment: .leading, spacing: 1) {
                // U-05 (K8): cut in the middle, so the end of the domain (its public suffix, which a scammer cannot
                // make read as the bank's) always shows, not only the start they picked.
                Text(verbatim: scan.domain)
                    .profileFont(17, tracking: -0.17)
                    .foregroundStyle(ProfileStyle.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: Self.when(scan.detectedAt, language: language))
                    .profileFont(13, rounded: true)
                    .foregroundStyle(ProfileStyle.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ProfileScanChip(status: scan.status)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 11)
        .frame(minHeight: 63)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func statusPill(active: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(active ? ProfileStyle.green : ProfileStyle.offDot).frame(width: 8, height: 8)
            // C3: the extension's state. The server only knows "no heartbeat for 24 h", not why.
            Text(active ? "Extension on" : "Extension off")
                .profileFont(14, .medium, tracking: -0.14)
                .foregroundStyle(active ? ProfileStyle.greenText : ProfileStyle.secondary)
        }
        // Figma "Status": 7 / 12 leading / 14 trailing.
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 7)
        .background(active ? ProfileStyle.greenPill : ProfileStyle.iconFill, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(active ? "member.status.on" : "member.status.off")
    }

    // MARK: Text

    /// "iPhone · Safari · aktif 2 mnt lalu".
    private func handle(_ member: FamilyMember) -> String {
        var parts = [member.deviceModel.map { $0.hasPrefix("iPad") ? "iPad" : "iPhone" } ?? "", "Safari"].filter { !$0.isEmpty }
        if let seen = member.lastSeenAt {
            parts.append(L10n.string("active \(MemberText.ago(seen, language: language))", language: language))
        }
        return parts.joined(separator: " · ")
    }

    private func stats(_ member: FamilyMember) -> [ProfileStat] {
        guard let stats = member.stats else { return [] }
        let number = { (n: Int) in n.formatted(.number.locale(language.locale)) }
        return [
            ProfileStat(value: model.daysProtected.map(number) ?? "–", label: "Days under protection"),
            ProfileStat(value: number(stats.blocked), label: "Blocked"),
            ProfileStat(value: number(stats.warnings), label: "Warnings"),
        ]
    }

    /// "iPhone 15 · iOS 26".
    private func deviceText(_ member: FamilyMember) -> String? {
        guard let model = member.deviceModel else { return nil }
        let os = model.hasPrefix("iPad") ? "iPadOS" : "iOS"
        return member.osVersion.map { "\(model) · \(os) \($0)" } ?? model
    }

    /// "Hari ini · 10.42 WIB" / "25 Okt · 19.08 WIB".
    static func when(_ date: Date, now: Date = Date(), language: AppLanguage, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        var time = Date.FormatStyle(date: .omitted, time: .shortened, locale: language.locale)
        time.timeZone = timeZone
        let zone = timeZone.abbreviation(for: date).map { " \(Self.zoneName($0))" } ?? ""
        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = L10n.string("Today", language: language)
        } else {
            var style = Date.FormatStyle(locale: language.locale).day().month(.abbreviated)
            style.timeZone = timeZone
            day = date.formatted(style)
        }
        return "\(day) · \(date.formatted(time))\(zone)"
    }

    /// Indonesian zones by their usual names (GMT+7 → WIB).
    private static func zoneName(_ abbreviation: String) -> String {
        switch abbreviation {
        case "GMT+7": "WIB"
        case "GMT+8": "WITA"
        case "GMT+9": "WIT"
        default: abbreviation
        }
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack {
        MemberDetailView(deviceId: "dev_mom", repository: env.repository)
    }
    .environment(env)
}

/// "Ingatkan {nama}" under the checklist (Figma "Tombol · Ingatkan Dad"): full width, 44 pt, the app's blue capsule.
private struct MemberRemindButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .profileFont(15, .semibold, tracking: -0.23)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule().fill(OnboardingTheme.buttonGradient))
            .opacity(isEnabled ? 1 : 0.6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}
