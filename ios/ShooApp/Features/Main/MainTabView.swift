import SwiftUI

/// Shield / Activity tabs with the profile button top right (PRD §7).
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var router = env.router
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.shieldPath) {
                shieldRoot
                    // A new repository (mode switch, later a new session) starts a fresh screen model.
                    .id(ObjectIdentifier(env.repository))
                    .toolbar { ProfileButton() }
                    .navigationDestination(for: Route.self, destination: destination)
            }
            .tabItem { Label("Shield", systemImage: "shield.lefthalf.filled") }
            .tag(AppTab.shield)

            NavigationStack(path: $router.activityPath) {
                activityRoot
                    .id(ObjectIdentifier(env.repository))
                    .toolbar { ProfileButton() }
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
            ProtectedShieldView(repository: env.repository)
        } else {
            // TODO(sync:alief): Guardian Shield (GD-01) lands in fase 05
            ShieldPlaceholderView()
        }
    }

    /// Protected sees its own scans (PR-05); the guardian sees the family's (GD-05, owner shown).
    @ViewBuilder
    private var activityRoot: some View {
        if env.settings.mode == .protected {
            ActivityView(repository: env.repository, owner: .me)
        } else {
            ActivityView(repository: env.repository, owner: .family, showsOwner: true)
        }
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
