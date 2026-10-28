import SwiftUI

/// Shield / Activity tabs with the profile button top right (PRD §7).
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var router = env.router
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.shieldPath) {
                shieldRoot
                    .id(screenIdentity)
                    .toolbar {
                        // Guardian Shield has its own family pill; Guardian Home also its own profile button.
                        if !isGuardianHome { ProfileButton() }
                    }
                    .navigationDestination(for: Route.self, destination: destination)
            }
            .tabItem { Label("Shield", systemImage: "shield.lefthalf.filled") }
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
            .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }
            .tag(AppTab.activity)
        }
        .sheet(isPresented: $router.isConnectPresented) {
            ConnectSheet()
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

    /// Guardian with Family mode off: Home draws its own top bar over the hero (GD-01).
    private var isGuardianHome: Bool {
        env.settings.mode == .guardian && !env.settings.familyModeOn
    }

    /// Own scans (PR-05, guardian with Family mode off); Family mode → the members' scans, owner shown (GD-05).
    @ViewBuilder
    private var activityRoot: some View {
        if env.settings.mode == .guardian && env.settings.familyModeOn {
            ActivityView(repository: env.repository, owner: .family, ownDeviceId: env.session?.deviceId)
        } else {
            ActivityView(repository: env.repository, owner: .me)
        }
    }

    /// A new repository (mode switch, later a new session) or the Family toggle starts fresh screen models.
    /// Protected screens ignore the toggle, so it never resets them.
    private var screenIdentity: String {
        let familyMode = env.settings.mode == .guardian && env.settings.familyModeOn
        return "\(ObjectIdentifier(env.repository).hashValue)-\(familyMode)"
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .detail(let scanId):
            DetailView(scanId: scanId, repository: env.repository)
                .id(scanId)
        case .profile:
            ProfileView(repository: env.repository, settings: env.settings, notifications: env.notifications)
        case .profilePage(let page):
            ProfilePageView(page: page)
        case .member(let deviceId):
            MemberDetailView(deviceId: deviceId, repository: env.repository)
                .id(deviceId)
        case .memberActivity(let deviceId):
            ActivityView(repository: env.repository, owner: .device(deviceId))
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
                    env.settings.familyModeOn.toggle()
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
