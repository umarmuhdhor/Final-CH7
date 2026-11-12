import SwiftUI

/// Shield / Activity tabs with the profile button top right (PRD §7).
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.shooReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var router = env.router
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.shieldPath) {
                // Every Home draws its own top bar over the hero (Figma HOME: ⇆ and the profile avatar).
                shieldRoot
                    .id(screenIdentity)
                    .navigationDestination(for: Route.self, destination: destination)
            }
            // Figma tab bar: "Shield" bolt-shield and "Activity" list circle.
            .tabItem { Label("Shield", systemImage: "bolt.shield.fill") }
            .tag(AppTab.shield)

            NavigationStack(path: $router.activityPath) {
                activityRoot
                    .id(screenIdentity)
                    .toolbar {
                        FamilyModeToggle()
                        ProfileButton()
                    }
                    .navigationDestination(for: Route.self, destination: destination)
            }
            .tabItem { Label("Activity", systemImage: "list.bullet.circle.fill") }
            .tag(AppTab.activity)
        }
        .overlay(alignment: .top) {
            if env.settings.demoMode, router.shieldPath.isEmpty, router.activityPath.isEmpty { DemoBanner() }
        }
        // PR-03: an invite link opened after onboarding. Waits for the launch splash, like Connect below.
        .overlay(alignment: .top) {
            if let notice = router.inviteNotice, env.launchSplash == .done {
                InviteNoticeBanner(notice: notice, router: router)
                    .padding(.top, 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth, value: router.inviteNotice)
        // PR-03: an invite link opened before or during onboarding opens its join sheet now the tabs are here.
        .onAppear { env.presentInviteAfterOnboarding() }
        // An invite link that started the app (PR-03): Connect comes up once the launch splash (ON-01) is gone.
        .sheet(isPresented: Binding(
            get: { router.isConnectPresented && env.launchSplash == .done },
            set: { router.isConnectPresented = $0 }
        )) {
            ConnectSheet()
                .environment(\.locale, env.settings.language.locale)
        }
        // Pribadi "Mode Terawasi" → Hubungkan (Figma 1253:8630).
        .sheet(isPresented: $router.isJoinFamilyPresented) {
            JoinAnotherFamilySheet(name: "")
                .environment(\.locale, env.settings.language.locale)
        }
        // Figma "To be guardian" (1229:1904).
        .fullScreenCover(isPresented: $router.isGuardianIntroPresented) {
            GuardianIntroView(onBack: { router.isGuardianIntroPresented = false }, onStart: env.startGuardian)
                .environment(\.locale, env.settings.language.locale)
        }
    }

    @ViewBuilder
    private var shieldRoot: some View {
        if env.settings.mode == .protected {
            ProtectedShieldView(repository: env.repository, extensionStatus: env.extensionStatus)
        } else {
            GuardianShieldView()
        }
    }

    /// Own scans (PR-05, guardian with Family mode off); Family mode → the members' scans, owner shown (GD-05).
    @ViewBuilder
    private var activityRoot: some View {
        if env.settings.mode == .guardian && env.settings.familyModeOn {
            ActivityView(repository: env.repository, owner: .family, ownDeviceId: env.session?.deviceId, verdictSaves: verdictSaves)
        } else {
            ActivityView(repository: env.repository, owner: .me, verdictSaves: verdictSaves)
        }
    }

    /// A new repository (mode switch), a new device session, or the Family toggle starts fresh screen models.
    /// Protected screens ignore the toggle, so it never resets them.
    private var screenIdentity: String {
        // `session` is `@ObservationIgnored`: this is read again because `settings.mode` changes in the same switch
        // (Pribadi → Protected keeps the repository but deletes the old device, F-A6).
        Self.identity(
            repository: env.repository,
            familyMode: env.settings.mode == .guardian && env.settings.familyModeOn,
            deviceId: env.session?.deviceId
        )
    }

    static func identity(repository: any ShooRepository, familyMode: Bool, deviceId: String?) -> String {
        "\(ObjectIdentifier(repository).hashValue)-\(familyMode)-\(deviceId ?? "-")"
    }

    /// Activity reads the app-wide verdict counter (K8).
    private var verdictSaves: @MainActor () -> Int {
        { [env] in env.verdictSaves }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .detail(let scanId):
            DetailView(scanId: scanId, repository: env.repository, onVerdictSaved: { [env] in env.verdictSaves += 1 })
                .id(scanId)
        case .profile:
            ProfileView(repository: env.repository, settings: env.settings, notifications: env.notifications)
        case .profilePage(let page):
            ProfilePageView(page: page)
        case .member(let deviceId):
            MemberDetailView(deviceId: deviceId, repository: env.repository)
                .id(deviceId)
        case .memberActivity(let deviceId):
            ActivityView(repository: env.repository, owner: .device(deviceId), verdictSaves: verdictSaves)
                .id(deviceId)
        }
    }
}

/// Top-left Family mode switch, guardian only (GD-02). Remembered in `AppSettings.familyModeOn`.
/// Visible text plus a filled/outlined icon, so the state is never colour only (WCAG 1.4.1, 2.5.3).
private struct FamilyModeToggle: ToolbarContent {
    @Environment(AppEnvironment.self) private var env

    var body: some ToolbarContent {
        if env.settings.mode == .guardian {
            ToolbarItem(placement: .topBarLeading) {
                let isOn = env.settings.familyModeOn
                Button {
                    if isOn { env.settings.familyModeOn = false } else { env.requestFamilyMode() }
                    AccessibilityNotification.Announcement(
                        L10n.string(isOn ? "Family mode off. Showing your Shield." : "Family mode on. Showing your family.",
                                    language: env.settings.language)
                    ).post()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isOn ? "person.3.fill" : "person.3")
                        Text(isOn ? "Family: On" : "Family: Off")
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityLabel(Text("Family mode"))
                .accessibilityValue(Text(isOn ? "On" : "Off"))
                .accessibilityAddTraits(.isToggle)
                .accessibilityHint(Text("Switches between your own Shield and your family's"))
                .accessibilityIdentifier("familyModeToggle")
            }
        }
    }
}

/// Top-right avatar button that opens Profile (PF-01).
private struct ProfileButton: ToolbarContent {
    @Environment(AppEnvironment.self) private var env

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                env.router.openProfile()
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.title2)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(Text("Profile"))
            .accessibilityIdentifier("profileButton")
        }
    }
}

#Preview("Guardian") {
    MainTabView().environment(AppEnvironment.preview())
}

/// PR-01 after onboarding (Shield "Connect", or an invite link).
private struct ConnectSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var model: ConnectModel?

    var body: some View {
        Group {
            if let model {
                ConnectView(model: model, onBack: { dismiss() }, onSkip: { dismiss() }, onFinish: { dismiss() })
            } else {
                // An empty Group never appears, so `onAppear` below would never run.
                Color(.systemBackground)
            }
        }
        .interactiveDismissDisabled(model?.state == .joining)
        .onAppear {
            guard model == nil else { return }
            model = ConnectModel(repository: env.repository, code: env.router.takePendingJoinCode())
        }
        .onChange(of: env.router.pendingJoinCode) { _, code in
            guard code != nil, let pending = env.router.takePendingJoinCode() else { return }
            model?.prefill(pending)
        }
    }
}

/// Sample data must never pass for a real family: on both tabs, between the top bar's two buttons.
/// Pushed screens keep their own top bar free.
private struct DemoBanner: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        HStack(spacing: 8) {
            Text("Demo: sample data")
            Button("Exit demo") { env.leaveDemo() }
                .fontWeight(.semibold)
                .accessibilityIdentifier("demo.exit")
        }
        .font(.footnote)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, 8)
        // Stays clear of the title and the buttons on every iPhone width.
        .padding(.horizontal, 120)
    }
}
