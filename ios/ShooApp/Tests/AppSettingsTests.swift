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
        env.finishOnboarding()
        #expect(settings.onboardingCompleted)
    }

    @Test func modeCanBeChosenOnlyOnce() throws {
        let settings = AppSettings(defaults: try freshDefaults(), preferredLanguages: ["en"])
        #expect(settings.chooseMode(.guardian))
        #expect(!settings.chooseMode(.protected))
        #expect(settings.mode == .guardian)
    }
}
