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
                FamilyShieldView(repository: env.repository)
            } else {
                ProtectedShieldView(repository: env.repository, extensionStatus: env.extensionStatus, perspective: .guardian)
            }
        }
        // Push alerts are how the guardian hears about the family: remind while they are off (D-alief-A08).
        .safeAreaInset(edge: .top) {
            if NotificationReminder.isShown(status: notificationStatus, mode: env.settings.mode) {
                NotificationReminderBanner(status: notificationStatus) {
                    Task { notificationStatus = await env.notifications.request() }
                }
                .padding(.horizontal, 16)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            notificationStatus = await env.notifications.status()
        }
    }
}

/// Family mode (GD-03): one slim card per protected person (max 3); tap → Detail of their newest site.
struct FamilyShieldView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var model: FamilyShieldModel
    @State private var isInvitePresented = false

    init(repository: any ShooRepository) {
        _model = State(initialValue: FamilyShieldModel(repository: repository))
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                content
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(localized: "Shield")
        // App switcher snapshot on disk must not hold scam URLs or names (D-alief-A36).
        .privacyCover()
        .refreshable { await model.refresh() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.refresh()
        }
        .alert(Text("Invite your family"), isPresented: $isInvitePresented) {
            Button("OK", role: .cancel) {}
        } message: {
            // TODO(sync:alief): open Family code (GD-04) — replace after fase 14
            Text("Family codes are coming soon.")
        }
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
                Button { isInvitePresented = true } label: {
                    Text("Invite your family").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("family.invite")
            }
            .frame(minHeight: 320)
        case .loaded:
            FamilyHeader(members: model.members, language: language)
            ForEach(model.members) { member in
                let scanId = model.lastScanId(for: member.deviceId)
                Button {
                    if let scanId { env.router.showDetail(scanId: scanId) }
                } label: {
                    FamilyMemberCard(member: member, language: language, opensDetail: scanId != nil)
                }
                .buttonStyle(.plain)
                .disabled(scanId == nil)
                .accessibilityIdentifier("family.member.\(member.deviceId)")
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
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
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
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
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
    }
}

#Preview {
    NavigationStack { FamilyShieldView(repository: MockRepository(mode: .guardian, latency: .zero)) }
        .environment(AppEnvironment.preview())
}
