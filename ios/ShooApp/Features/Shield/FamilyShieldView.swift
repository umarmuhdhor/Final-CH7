import SwiftUI

/// Guardian Shield (GD-01/GD-02): Family mode off → own Shield, on → the family (GD-03).
/// The toggle only changes this view; the guardian's Safari stays protected either way.
struct GuardianShieldView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationStatus = NotificationAuthorization.authorized

    var body: some View {
        Group {
            if env.settings.familyModeOn {
                FamilyShieldView(repository: env.repository, reminder: reminder)
            } else {
                ProtectedShieldView(
                    repository: env.repository, extensionStatus: env.extensionStatus, perspective: .guardian, reminder: reminder
                )
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            notificationStatus = await env.notifications.status()
        }
    }

    /// Push alerts are how the guardian hears about the family: remind while they are off (D-alief-A08).
    /// It scrolls with the screen: pinned, it filled most of a small iPhone at large text sizes (QA-A P2-7).
    private var reminder: NotificationReminderBanner? {
        guard NotificationReminder.isShown(status: notificationStatus, mode: env.settings.mode) else { return nil }
        return NotificationReminderBanner(status: notificationStatus) {
            Task { notificationStatus = await env.notifications.request() }
        }
    }
}

/// Family mode (GD-03): one slim card per protected person (max 3); tap → Detail of their newest site.
struct FamilyShieldView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: FamilyShieldModel
    @State private var isInvitePresented = false
    private let reminder: NotificationReminderBanner?

    init(repository: any ShooRepository, reminder: NotificationReminderBanner? = nil) {
        _model = State(initialValue: FamilyShieldModel(repository: repository))
        self.reminder = reminder
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let reminder { reminder }
                content
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        // Its own title, so it is clear which view Family mode shows.
        .navigationTitle(localized: "Family")
        // App switcher snapshot on disk must not hold scam URLs or names (D-alief-A36).
        .privacyCover()
        // Pinned above the tab bar so the only action of an empty family is in view without scrolling (QA-A P2-4).
        .safeAreaInset(edge: .bottom) {
            if model.state == .loaded && model.members.isEmpty && !dynamicTypeSize.isAccessibilitySize {
                inviteButton.padding(16)
            }
        }
        .refreshable { await model.refresh() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.refresh()
        }
        .sheet(isPresented: $isInvitePresented, onDismiss: { Task { await model.refresh() } }) {
            FamilyCodeView(repository: env.repository)
                .environment(\.locale, locale)
        }
    }

    private var inviteButton: some View {
        Button { isInvitePresented = true } label: {
            Text("Invite your family")
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("family.invite")
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
                .accessibilityLabel(Text("Loading"))
        case .failed:
            VStack(spacing: 12) {
                Text("Couldn't load your family").font(.headline)
                Text("Check your connection and try again.").foregroundStyle(.primary)
                Button { Task { await model.retry() } } label: { Text("Try again").frame(minHeight: 44) }
                    .buttonStyle(.borderedProminent)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        case .loaded where model.members.isEmpty:
            VStack(spacing: 16) {
                EmptyStateView(
                    systemImage: "person.2",
                    title: "No one to look after yet",
                    message: "Invite the people you want to keep safe."
                )
                // At accessibility text sizes a pinned button would take a third of the screen, so it scrolls.
                if dynamicTypeSize.isAccessibilitySize { inviteButton }
            }
            .frame(minHeight: 320)
        case .loaded:
            FamilyHeader(members: model.members, language: language)
            ForEach(model.members) { member in
                // Only a card with a site to open is a button; the others stay full contrast.
                if let scanId = model.lastScanId(for: member.deviceId) {
                    Button {
                        env.router.showDetail(scanId: scanId)
                    } label: {
                        FamilyMemberCard(member: member, language: language, opensDetail: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("family.member.\(member.deviceId)")
                } else {
                    FamilyMemberCard(member: member, language: language)
                        .accessibilityIdentifier("family.member.\(member.deviceId)")
                }
            }
        }
    }
}

/// Circle of the people looked after (max 3 avatars) and how many are connected.
private struct FamilyHeader: View {
    let members: [FamilyMember]
    let language: AppLanguage

    private var names: String {
        members.map(\.name).formatted(.list(type: .and).locale(language.locale))
    }

    private var notConnected: Int { members.filter { !$0.isConnected }.count }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: -12) {
                ForEach(members) { member in
                    AvatarView(id: member.avatarId, size: 56)
                        .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 3))
                }
            }
            .accessibilityHidden(true)
            Text(verbatim: L10n.string("You look after \(names)", language: language))
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if notConnected > 0 {
                Label {
                    Text(verbatim: L10n.string("\(notConnected) not connected", language: language))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.warningIcon)
                        .accessibilityHidden(true)
                }
                .font(.body)
                .foregroundStyle(.primary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("family.header")
    }
}

/// Slim card per person: name, newest risky site (status, host+path, time) or "Not connected".
struct FamilyMemberCard: View {
    let member: FamilyMember
    let language: AppLanguage
    var opensDetail = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(id: member.avatarId, size: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: member.name).font(.headline)
                if !member.isConnected {
                    Label { Text("Not connected") } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.warningIcon)
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                }
                if let scan = member.lastScan {
                    StatusChip(badge: ScanBadge(status: scan.status))
                    Text(verbatim: ActivityRow.displayLink(scan.url))
                        .font(.subheadline)
                        .foregroundStyle(.readableSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .truncationMode(.middle)
                    Text(verbatim: Formatters.relative(scan.detectedAt, language: language))
                        .font(.subheadline)
                        .foregroundStyle(.readableSecondary)
                } else if member.isConnected {
                    Text("No risky sites yet")
                        .font(.subheadline)
                        .foregroundStyle(.readableSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if opensDetail && !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(opensDetail ? Text("Opens the details") : Text(verbatim: ""))
        .accessibilityAddTraits(opensDetail ? .isButton : [])
    }
}

#Preview {
    NavigationStack { FamilyShieldView(repository: MockRepository(mode: .guardian, latency: .zero)) }
        .environment(AppEnvironment.preview())
}

private extension Color {
    /// Darker orange: ≥ 3:1 on white cards (system orange is about 2.2:1), still clear on dark.
    static var warningIcon: Color { Color(red: 0.72, green: 0.33, blue: 0) }
}
