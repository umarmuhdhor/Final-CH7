import Foundation
import Testing
@testable import Shoo

@MainActor
struct MemberDetailModelTests {
    /// 14 Sep 2026, the mock members' `connectedAt`.
    static let start = Date(timeIntervalSince1970: 1_789_351_800)

    func model(
        _ deviceId: String = "dev_mom",
        repository: (any ShooRepository)? = nil,
        onDisconnected: @escaping @MainActor () -> Void = {}
    ) -> MemberDetailModel {
        MemberDetailModel(
            deviceId: deviceId,
            repository: repository ?? MockRepository(mode: .guardian, latency: .zero),
            now: { Self.start.addingTimeInterval(2 * 86_400) },
            onDisconnected: onDisconnected
        )
    }

    func text(_ value: String.LocalizationValue?) -> String? {
        value.map { L10n.string($0, language: .english) }
    }

    @Test func loadsTheMemberAndAtMostThreeScans() async {
        let model = model()
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.member?.name == "Mom")
        #expect(model.member?.deviceModel == "iPhone 15")
        #expect(model.recent.count <= 3)
        #expect(!model.recentFailed)
        #expect(model.daysProtected == 3)
    }

    @Test func unknownMemberIsGone() async {
        let model = model("dev_stranger")
        await model.load()
        #expect(model.state == .gone)
        #expect(model.member == nil)
    }

    @Test func failingMemberListFails() async {
        let model = model(repository: FailingRepository())
        await model.load()
        #expect(model.state == .failed)
    }

    /// The member still shows when only the activity could not be read.
    @Test func failingActivityKeepsTheMember() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        repository.failingOwner = .device("dev_mom")
        let model = model(repository: repository)
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.recent.isEmpty)
        #expect(model.recentFailed)
    }

    @Test func notifyReachesTheServer() async throws {
        let repository = MockRepository(mode: .guardian, latency: .zero)
        let model = model(repository: repository)
        await model.load()
        await model.setNotify(false)
        #expect(model.member?.notify == false)
        #expect(try await repository.familyMembers().first { $0.deviceId == "dev_mom" }?.notify == false)
    }

    /// BH-30: a second tap while the first change is still on its way is ignored, so two failures arriving
    /// in any order cannot leave the switch on a value the server never had.
    @Test func secondNotifyTapWhileOneIsInFlightIsIgnored() async throws {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        repository.notifyFailure = RepositoryError.network
        let first = NotifyGate(), second = NotifyGate()
        repository.beforeNotify = { on in on ? await second.wait() : await first.wait() }
        let model = model(repository: repository)
        await model.load()
        #expect(model.member?.notify == true)
        let t1 = Task { await model.setNotify(false) }
        try await Task.sleep(for: .milliseconds(50))
        let t2 = Task { await model.setNotify(true) }
        try await Task.sleep(for: .milliseconds(50))
        first.release()
        await t1.value
        second.release()
        await t2.value
        #expect(model.member?.notify == true)
    }

    @Test func failedNotifyGoesBackAndSaysSo() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        repository.notifyFailure = RepositoryError.network
        let model = model(repository: repository)
        await model.load()
        await model.setNotify(false)
        #expect(model.member?.notify == true)
        #expect(model.actionError != nil)
    }

    @Test func remindOnceThenTooSoon() async {
        let model = model("dev_dad")
        await model.load()
        #expect(text(await model.remind()) == "Reminder sent to Dad")
        #expect(model.member?.remindedAt != nil)
        #expect(text(await model.remind()) == "You already reminded Dad recently")
    }

    @Test func remindFailureIsGeneric() async {
        let repository = DelayedScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        repository.remindFailure = RepositoryError.network
        let model = model("dev_dad", repository: repository)
        await model.load()
        #expect(text(await model.remind()) == "Couldn't send. Check your connection and try again.")
        #expect(model.member?.remindedAt == nil)
    }

    @Test func disconnectRemovesTheMember() async throws {
        let repository = MockRepository(mode: .guardian, latency: .zero)
        let model = model(repository: repository)
        await model.load()
        #expect(await model.disconnect())
        #expect(try await repository.familyMembers().map(\.deviceId) == ["dev_dad"])
    }

    /// Removed before (an earlier answer got lost): same end state.
    @Test func disconnectThatAlreadyHappenedCountsAsDone() async throws {
        let repository = MockRepository(mode: .guardian, latency: .zero)
        let model = model(repository: repository)
        await model.load()
        try await repository.removeMember(deviceId: "dev_mom")
        #expect(await model.disconnect())
    }

    @Test func failedDisconnectSaysSo() async {
        var cleared = 0
        let model = model(repository: FailingRepository(), onDisconnected: { cleared += 1 })
        #expect(await model.disconnect() == false)
        #expect(model.actionError != nil)
        #expect(cleared == 0, "the member is still connected: their pushes stay")
    }

    /// Fase 27g (F-N3, K9, P13): disconnecting from the member page clears the shown pushes, as the
    /// family list does (`FamilyCodeModel.remove`).
    @Test func disconnectClearsDeliveredPushes() async {
        var cleared = 0
        let model = model(onDisconnected: { cleared += 1 })
        await model.load()
        #expect(await model.disconnect())
        #expect(cleared == 1)
    }

    /// Already removed (an earlier answer got lost): the pushes go too.
    @Test func disconnectThatAlreadyHappenedClearsDeliveredPushes() async throws {
        var cleared = 0
        let repository = MockRepository(mode: .guardian, latency: .zero)
        let model = model(repository: repository, onDisconnected: { cleared += 1 })
        await model.load()
        try await repository.removeMember(deviceId: "dev_mom")
        #expect(await model.disconnect())
        #expect(cleared == 1)
    }
}

/// Holds a call until `release` (BH-30).
final class NotifyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isOpen { lock.unlock(); continuation.resume(); return }
            waiter = continuation
            lock.unlock()
        }
    }

    func release() {
        lock.lock()
        isOpen = true
        let waiter = waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume()
    }
}
