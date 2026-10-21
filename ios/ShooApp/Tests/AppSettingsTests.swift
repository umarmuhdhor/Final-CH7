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
        first.mode = .protected
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
}
