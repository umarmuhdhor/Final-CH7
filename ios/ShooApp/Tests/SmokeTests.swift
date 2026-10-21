import Testing
@testable import Shoo

/// Placeholder so the ShooAppTests target builds and runs; real tests arrive with feat/APP-foundation.
struct SmokeTests {
    @Test func appModuleLoads() {
        #expect(UserMode.guardian.rawValue == "guardian")
    }
}
