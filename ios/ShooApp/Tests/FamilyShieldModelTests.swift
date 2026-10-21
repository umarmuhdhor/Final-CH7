import Foundation
import Testing
@testable import Shoo

@MainActor
struct FamilyShieldModelTests {
    func model(scenario: MockRepository.Scenario = .standard) -> FamilyShieldModel {
        FamilyShieldModel(repository: MockRepository(mode: .guardian, scenario: scenario, latency: .zero))
    }

    @Test func showsTheFamilyFromTheFixture() async {
        let model = model()
        await model.refresh()
        #expect(model.state == .loaded)
        #expect(model.members.map(\.name) == ["Mom", "Dad"])
        #expect(!model.isEmpty)
    }

    @Test func notConnectedOnlyWhenTheServerSaysSo() async throws {
        let model = model()
        await model.refresh()
        let mom = try #require(model.members.first { $0.deviceId == "dev_mom" })
        let dad = try #require(model.members.first { $0.deviceId == "dev_dad" })
        #expect(mom.isConnected)
        #expect(!dad.isConnected)
    }

    @Test func cardOpensTheNewestScanOfThatPerson() async throws {
        let repository = MockRepository(mode: .guardian, latency: .zero)
        let model = FamilyShieldModel(repository: repository)
        await model.refresh()
        let newest = try await repository.scans(owner: .device("dev_mom"), status: nil, cursor: nil).items.first
        #expect(model.lastScanId(for: "dev_mom") == newest?.id)
        #expect(model.lastScanId(for: "dev_dad") == nil)
    }

    @Test(arguments: [(MockRepository.Scenario.empty, 0), (.oneMember, 1), (.standard, 2), (.threeMembers, 3)])
    func memberCountPerScenario(scenario: MockRepository.Scenario, count: Int) async {
        let model = model(scenario: scenario)
        await model.refresh()
        #expect(model.members.count == count)
        #expect(model.isEmpty == (count == 0))
    }

    @Test func failureShowsError() async {
        let model = FamilyShieldModel(repository: FailingRepository())
        await model.refresh()
        #expect(model.state == .failed)
    }

    @Test func failedRefreshKeepsTheFamily() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        let model = FamilyShieldModel(repository: repository)
        await model.refresh()
        repository.failure = RepositoryError.network
        await model.refresh()
        #expect(model.state == .loaded)
        #expect(model.members.count == 2)
    }
}
