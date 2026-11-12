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
                    message: "Check your internet connection, then try again."
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
                    message: "This person has disconnected. You no longer get warnings from them."
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
        .sheet(isPresented: $isDisconnectConfirming) {
            if let member = model.member {
                ProfileConfirmSheet(
                    title: L10n.string("Disconnect from \(member.name)?", language: language),
                    message: L10n.string(
                        "You will no longer get warnings from \(member.name)'s activity. To connect again, \(member.name) needs to enter a new invite code.",
                        language: language
                    ),
                    confirmTitle: L10n.string("Disconnect", language: language),
                    confirmIdentifier: "member.disconnect.confirm",
                    isWorking: model.isWorking
                ) {
                    AvatarView(id: member.avatarId, size: 64)
                } onConfirm: {
                    Task {
                        guard await model.disconnect() else { return }
                        isDisconnectConfirming = false
                        env.router.pop()
                    }
                }
                .environment(\.locale, locale)
            }
        }
        .alert(
            Text(verbatim: model.actionError.map { L10n.string($0, language: language) } ?? ""),
            isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
        .privacyCover()
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
                    : .value(L10n.string("Off", language: language), color: ProfileStyle.red, chevron: false)
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

    /// Figma "Pesan ekstensi mati" (1681:6718) and "Pengingat terkirim" (1681:6837): orange with **Ingatkan** while
    /// the extension is off, green once a reminder went out. The swap cross-fades; the check bounces in.
    private func offBanner(_ member: FamilyMember) -> some View {
        let sent = MemberText.recentlyReminded(member)
        return HStack(spacing: 12) {
            Image(systemName: sent ? "checkmark" : "exclamationmark.triangle.fill")
                .font(.system(size: 21.67, weight: sent ? .semibold : .regular))
                .foregroundStyle(sent ? Color(hex: 0x269E4A) : Color(hex: 0xEF871C))
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                .frame(width: 40, height: 40)
                .background(sent ? Color(hex: 0x34C759).opacity(0.14) : Color(hex: 0xEF871C).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(sent ? "Reminder sent" : "Safari extension off")
                    .profileFont(16, .semibold, tracking: -0.31)
                    .foregroundStyle(Color(hex: 0x151617))
                Text(sent ? "\(member.name) will get a notification." : "\(member.name) isn't protected yet.")
                    .profileFont(13, rounded: true)
                    .foregroundStyle(Color(hex: 0x6A717E))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if !sent {
                Button {
                    Task {
                        if let message = await model.remind() {
                            AccessibilityNotification.Announcement(L10n.string(message, language: language)).post()
                        }
                    }
                } label: {
                    ZStack {
                        Text("Remind").opacity(model.isReminding ? 0 : 1)
                        if model.isReminding { ProgressView().controlSize(.small).tint(ProfileStyle.link) }
                    }
                    .profileFont(15, .semibold, tracking: -0.23)
                    .foregroundStyle(Color(hex: 0x136CB7))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(model.isReminding)
                .accessibilityLabel(Text("Remind \(member.name)"))
                .accessibilityHint(Text("Sends a notification to turn on Shoo in Safari"))
                .accessibilityIdentifier("profile.remind.\(member.deviceId)")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 72)
        .background(sent ? Color(hex: 0xEBF8ED).opacity(0.9) : Color(hex: 0xF8F2EB).opacity(0.9))
        .overlay(alignment: .top) {
            Rectangle().fill(sent ? Color(hex: 0x1CEF1C).opacity(0.35) : Color(hex: 0xEF871C).opacity(0.35)).frame(height: 1)
        }
        .animation(.easeInOut(duration: 0.25), value: sent)
        .sensoryFeedback(.success, trigger: sent) { was, now in !was && now }
        .accessibilityIdentifier(sent ? "member.reminded" : "member.off")
    }

    private func activityRow(_ scan: ScanResult) -> some View {
        HStack(spacing: 12) {
            ProfileIcon(symbol: "globe")
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: scan.domain)
                    .profileFont(17, tracking: -0.17)
                    .foregroundStyle(ProfileStyle.ink)
                    .lineLimit(1)
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
            Text(active ? "Protection on" : "Protection off")
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
