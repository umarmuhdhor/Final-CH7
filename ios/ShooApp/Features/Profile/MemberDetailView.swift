import SwiftUI

/// Figma "Guardian/Detail Orang Dilindungi" (PF-01): a protected member as their guardian sees them.
struct MemberDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale
    @State private var model: MemberDetailModel
    @State private var isDisconnectConfirming = false

    init(deviceId: String, repository: any ShooRepository) {
        _model = State(initialValue: MemberDetailModel(deviceId: deviceId, repository: repository))
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        ProfileScreen(title: "Protected person") {
            switch model.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .accessibilityLabel(Text("Loading"))
            case .failed:
                VStack(spacing: 12) {
                    Text("Couldn't load your family").profileFont(17, .semibold)
                    Button { Task { await model.load() } } label: { Text("Try again") }
                        .buttonStyle(ProfilePillButtonStyle(tint: ProfileStyle.link))
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            case .gone:
                Text("This person is no longer connected")
                    .profileFont(17, .semibold)
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .accessibilityIdentifier("member.gone")
            case .loaded:
                if let member = model.member { loaded(member) }
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
                    InitialsAvatar(name: member.name, avatarId: member.avatarId, size: 64)
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
            name: member.name,
            handle: handle(member),
            stats: stats(member)
        ) {
            InitialsAvatar(name: member.name, avatarId: member.avatarId, size: 86)
                .frame(width: 88, height: 88)
        } badge: {
            statusPill(active: member.extensionActive)
        }

        ProfileSection(title: "Protection") {
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
            if !member.extensionActive {
                ProfileDivider()
                HStack {
                    Text("Ask \(member.name) to turn Shoo on")
                        .profileFont(15)
                        .foregroundStyle(ProfileStyle.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    RemindButton(member: member, isWorking: model.isReminding) {
                        if let message = await model.remind() {
                            AccessibilityNotification.Announcement(L10n.string(message, language: language)).post()
                        }
                    }
                }
                .padding(.horizontal, 17)
                .frame(minHeight: 58)
            }
        }

        ProfileSection(title: "Recent activity", trailing: AnyView(
            Button { env.router.show(.memberActivity(deviceId: member.deviceId)) } label: {
                Text("See all")
                    .profileFont(15, .medium, tracking: -0.15)
                    .foregroundStyle(ProfileStyle.link)
                    .frame(minHeight: 44)
            }
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
        .padding(.horizontal, 12)
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
            ProfileStat(value: number(stats.blocked), label: "Sites blocked"),
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
