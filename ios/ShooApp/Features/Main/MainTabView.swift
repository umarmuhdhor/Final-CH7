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
                        FamilyModeToggle()
                        ProfileButton()
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
        .sheet(isPresented: $router.isProfilePresented) {
            ProfilePlaceholderView()
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

    /// Own scans (PR-05, guardian with Family mode off); Family mode → the family's, owner shown (GD-05).
    @ViewBuilder
    private var activityRoot: some View {
        if env.settings.mode == .guardian && env.settings.familyModeOn {
            ActivityView(repository: env.repository, owner: .family, showsOwner: true)
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
        }
    }
}

/// Top-left Family mode switch, guardian only (GD-02). Remembered in `AppSettings.familyModeOn`.
private struct FamilyModeToggle: ToolbarContent {
    @Environment(AppEnvironment.self) private var env

    var body: some ToolbarContent {
        if env.settings.mode == .guardian {
            ToolbarItem(placement: .topBarLeading) {
                @Bindable var settings = env.settings
                Toggle(isOn: $settings.familyModeOn) {
                    Label { Text("Family mode") } icon: { Image(systemName: "person.3.fill") }
                }
                .toggleStyle(.button)
                .labelStyle(.titleAndIcon)
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
                env.router.isProfilePresented = true
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
