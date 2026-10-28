import Foundation
import Testing
@testable import Shoo

struct AppSettingsTests {
    func freshDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
    }

    @Test func defaultsOnFreshInstall() throws {
        let settings = AppSettings(defaults: try freshDefaults(), preferredLanguages: ["id-ID"])
        #expect(settings.language == .indonesian)
        #expect(settings.mode == nil)
        #expect(!settings.onboardingCompleted)
        #expect(!settings.familyModeOn)
    }

    @Test func valuesPersistAcrossLaunches() throws {
        let defaults = try freshDefaults()
        let first = AppSettings(defaults: defaults, preferredLanguages: ["en"])
        first.language = .indonesian
        #expect(first.chooseMode(.protected))
        first.onboardingCompleted = true
        first.familyModeOn = true
        let second = AppSettings(defaults: defaults, preferredLanguages: ["en"])
        #expect(second.language == .indonesian)
        #expect(second.mode == .protected)
        #expect(second.onboardingCompleted)
        #expect(second.familyModeOn)
    }

    @Test func routerPushesDetailOnSelectedTab() {
        let router = Router()
        router.selectedTab = .activity
        router.showDetail(scanId: "s1")
        #expect(router.activityPath == [.detail(scanId: "s1")])
        #expect(router.shieldPath.isEmpty)
        router.popToRoot()
        #expect(router.activityPath.isEmpty)
    }

    @Test func registerKeepsMockScenarioAndAnswersAsTheChosenMode() async throws {
        let settings = AppSettings(defaults: try freshDefaults(), preferredLanguages: ["en"])
        let env = AppEnvironment(
            repository: MockRepository(mode: .guardian, scenario: .empty, latency: .zero), settings: settings
        )
        let registration = try await env.register(name: "Rina", mode: .protected)
        #expect(settings.mode == .protected)
        #expect(!settings.onboardingCompleted)
        let me = try await env.repository.me()
        #expect(me.mode == .protected)
        #expect(me.name == "Rina")
        #expect(me.avatarId == registration.avatarId)
        #expect(try await env.repository.scans(owner: .me, status: nil, cursor: nil).items.isEmpty)
        await env.finishOnboarding()
        #expect(settings.onboardingCompleted)
    }

    @Test func modeCanBeChosenOnlyOnce() throws {
        let settings = AppSettings(defaults: try freshDefaults(), preferredLanguages: ["en"])
        #expect(settings.chooseMode(.guardian))
        #expect(!settings.chooseMode(.protected))
        #expect(settings.mode == .guardian)
    }

    // MARK: PF-01 Tema and Aksesibilitas

    @Test func appearanceDefaultsFollowTheIPhone() throws {
        let settings = AppSettings(defaults: try freshDefaults(), preferredLanguages: ["en"])
        #expect(settings.theme == .system)
        #expect(settings.textSize == .standard)
        #expect(settings.textSize.category == nil)
        #expect(!settings.boldText && !settings.highContrast && !settings.reduceMotion && !settings.reduceGlass)
        #expect(settings.haptics)
        #expect(!settings.readAloud)
    }

    @Test func appearanceChoicesPersist() throws {
        let defaults = try freshDefaults()
        let first = AppSettings(defaults: defaults, preferredLanguages: ["en"])
        first.theme = .dark
        first.textSize = .largest
        first.highContrast = true
        first.haptics = false
        let second = AppSettings(defaults: defaults, preferredLanguages: ["en"])
        #expect(second.theme == .dark)
        #expect(second.textSize == .largest)
        #expect(second.highContrast)
        #expect(!second.haptics)
    }

    /// The old "Teks besar" switch (before the slider) becomes the "Large" stop.
    @Test func oldLargeTextSwitchBecomesLarge() throws {
        let defaults = try freshDefaults()
        defaults.set(true, forKey: "settings.largeText")
        #expect(AppSettings(defaults: defaults, preferredLanguages: ["en"]).textSize == .large)
    }

    @Test func becomingProtectedLeavesFamilyModeAndSkipsConnect() throws {
        let settings = AppSettings(defaults: try freshDefaults(), preferredLanguages: ["en"])
        settings.chooseMode(.guardian)
        settings.familyModeOn = true
        settings.becameProtected()
        #expect(settings.mode == .protected)
        #expect(!settings.familyModeOn)
        #expect(settings.onboardingConnectPassed)
    }

    @Test func clearRemovesAppearanceToo() throws {
        let defaults = try freshDefaults()
        let settings = AppSettings(defaults: defaults, preferredLanguages: ["en"])
        settings.theme = .dark
        settings.readAloud = true
        AppSettings.clear(defaults: defaults)
        let fresh = AppSettings(defaults: defaults, preferredLanguages: ["en"])
        #expect(fresh.theme == .system)
        #expect(!fresh.readAloud)
    }
}
