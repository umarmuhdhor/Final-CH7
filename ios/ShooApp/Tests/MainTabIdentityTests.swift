import Foundation
import Testing
@testable import Shoo

/// F-A6 (K8): the tabs' screen models start fresh for a new repository, the Family toggle, and a new device
/// session (Pribadi → Protected keeps the repository but deletes the old device).
@MainActor
struct MainTabIdentityTests {
    @Test func aNewDeviceStartsFreshScreens() {
        let repository = MockRepository(latency: .zero)
        let identity = MainTabView.identity(repository: repository, familyMode: false, deviceId: "dev_old")
        #expect(identity == MainTabView.identity(repository: repository, familyMode: false, deviceId: "dev_old"))
        #expect(identity != MainTabView.identity(repository: repository, familyMode: false, deviceId: "dev_new"))
        #expect(identity != MainTabView.identity(repository: repository, familyMode: false, deviceId: nil))
    }

    @Test func repositoryAndFamilyModeStillStartFreshScreens() {
        let repository = MockRepository(latency: .zero)
        let identity = MainTabView.identity(repository: repository, familyMode: false, deviceId: "dev_me")
        #expect(identity != MainTabView.identity(repository: repository, familyMode: true, deviceId: "dev_me"))
        #expect(identity != MainTabView.identity(repository: MockRepository(latency: .zero), familyMode: false, deviceId: "dev_me"))
    }
}
