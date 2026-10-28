import Foundation
import Testing
import UIKit
@testable import Shoo

/// Fase 14: invite links, Connect (PR-01/02/03) and Family code (GD-04).
struct DeepLinkTests {
    private static let hosts: Set<String> = ["shoo-api.afindo-mi01.workers.dev", "localhost"]

    @Test(arguments: [
        "shoo://join?code=482193",
        "https://shoo-api.afindo-mi01.workers.dev/j/482193",
        "https://SHOO-API.afindo-mi01.workers.dev/j/482193",
        "SHOO://JOIN?code=482193",
    ])
    func joinLinksGiveTheCode(link: String) {
        #expect(DeepLink(url: URL(string: link)!, inviteHosts: Self.hosts) == .join(code: "482193"))
    }

    @Test(arguments: [
        "shoo://join?code=48219",
        "shoo://join?code=4821930",
        "shoo://join?code=4821",
        "shoo://join?code=48a193",
        "shoo://join?code=%D9%A4%D9%A8%D9%A2%D9%A1%D9%A9%D9%A3",
        "shoo://join",
        "shoo://join?code=482193&code=111111",
        "https://evil.example/j/482193",
        "https://shoo-api.afindo-mi01.workers.dev/join?code=482193",
        "https://shoo-api.afindo-mi01.workers.dev/j/4821",
        "https://shoo-api.afindo-mi01.workers.dev/j/482193/x",
        "https://shoo-api.afindo-mi01.workers.dev/x/j/482193",
        "https://shoo-api.afindo-mi01.workers.dev/jj/482193",
        "https://shoo-api.afindo-mi01.workers.dev/j/%34%38%32%31%39%33",
        "http://shoo-api.afindo-mi01.workers.dev/j/482193",
        "shoo://settings",
        "mailto:a@b.c",
    ])
    func everythingElseIsUnknown(link: String) {
        #expect(DeepLink(url: URL(string: link)!, inviteHosts: Self.hosts) == .unknown)
    }

    /// http only for the Worker this build talks to over http, same host and port (never in Release).
    @Test func httpOnlyForTheLocalWorker() {
        let local = URL(string: "http://localhost:8787")!
        #expect(DeepLink.isLocalWorker(URL(string: "http://localhost:8787/j/482193")!, api: local))
        #expect(!DeepLink.isLocalWorker(URL(string: "http://localhost:9999/j/482193")!, api: local))
        #expect(!DeepLink.isLocalWorker(URL(string: "http://evil.example:8787/j/482193")!, api: local))
        let release = URL(string: "https://shoo-api.afindo-mi01.workers.dev")!
        #expect(!DeepLink.isLocalWorker(URL(string: "http://shoo-api.afindo-mi01.workers.dev/j/482193")!, api: release))
    }

    @Test func scanAndActivityLinks() {
        #expect(DeepLink(url: URL(string: "shoo://scan/6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03")!) == .scan(id: "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03"))
        #expect(DeepLink(url: URL(string: "shoo://scan/../devices")!) == .unknown)
        #expect(DeepLink(url: URL(string: "shoo://activity")!) == .activity)
    }
}

@MainActor
struct ConnectModelTests {
    @Test func codeKeepsSixDigitsOnly() {
        let model = ConnectModel(repository: MockRepository(mode: .protected, latency: .zero))
        model.code = "4a8 2-1 9"
        #expect(model.code == "48219")
        #expect(!model.canJoin)
        model.code = "482 193 7"
        #expect(model.code == "482193")
        #expect(model.canJoin)
    }

    /// T11: a link or QR only fills the code, the user still taps Connect.
    @Test func prefillNeverJoins() async throws {
        let repository = MockRepository(mode: .protected, latency: .zero)
        _ = try await repository.leaveGuardian()
        let model = ConnectModel(repository: repository, code: "482193")
        #expect(model.code == "482193")
        #expect(model.state == .entering)
        #expect(try await repository.me().guardian == nil)
    }

    @Test func joinShowsWhoProtectsMe() async throws {
        let repository = MockRepository(mode: .protected, latency: .zero)
        try await repository.leaveGuardian()
        let model = ConnectModel(repository: repository, code: "482193")
        await model.join()
        #expect(model.state == .joined(MockRepository.fixtureGuardian))
    }

    @Test(arguments: [
        ("000000", ConnectModel.Problem.invalid),
        ("999999", .expired),
        ("888888", .full),
        ("777777", .tooManyAttempts),
        ("666666", .alreadyConnected),
    ])
    func everyJoinErrorHasItsMessage(code: String, problem: ConnectModel.Problem) async {
        let model = ConnectModel(repository: MockRepository(mode: .protected, latency: .zero), code: code)
        await model.join()
        #expect(model.state == .entering)
        #expect(model.problem == problem)
        // Editing the code clears it.
        model.code = "123"
        #expect(model.problem == nil)
    }

    @Test func offlineIsItsOwnProblem() async {
        let model = ConnectModel(repository: FailingRepository(), code: "482193")
        await model.join()
        #expect(model.problem == .offline)
    }

    @Test(arguments: [ConnectModel.Problem.invalid, .expired, .full, .tooManyAttempts, .alreadyConnected, .offline, .other])
    func messagesExistInBothLanguages(problem: ConnectModel.Problem) {
        let english = L10n.string(problem.message, language: .english)
        let indonesian = L10n.string(problem.message, language: .indonesian)
        #expect(!english.isEmpty && !indonesian.isEmpty && english != indonesian)
    }

    @Test func scannedInviteFillsTheCode() {
        let model = ConnectModel(repository: MockRepository(mode: .protected, latency: .zero))
        #expect(model.scanned("https://shoo-api.afindo-mi01.workers.dev/j/482193"))
        #expect(model.code == "482193")
        #expect(!model.scanned("https://evil.example/j/111111"))
        #expect(!model.scanned("https://shoo-api.afindo-mi01.workers.dev/join?code=111111"))
        #expect(!model.scanned("hello"))
        #expect(!model.scanned("https://shoo-api.afindo-mi01.workers.dev/j/111111?x=" + String(repeating: "a", count: 600)))
        #expect(model.code == "482193")
    }
}

@MainActor
struct FamilyCodeModelTests {
    /// Read by the repository actor while the test moves it on: behind a lock.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_792_000_000)
        var now: Date {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
    }

    /// Answers `createFamilyCode` with a numbered code valid for `validFor` seconds by `clock`.
    actor CodeRepository: ShooRepository {
        private let base: MockRepository
        private let clock: Clock
        private let validFor: TimeInterval
        private(set) var codeCalls = 0
        private(set) var refreshes: [Bool] = []
        var codeFailure: RepositoryError?

        init(members: MockRepository.Scenario = .standard, clock: Clock, validFor: TimeInterval = 30 * 60) {
            base = MockRepository(mode: .guardian, scenario: members, latency: .zero)
            self.clock = clock
            self.validFor = validFor
        }

        func failCodes(with error: RepositoryError?) { codeFailure = error }

        func createFamilyCode(refresh: Bool) async throws -> FamilyCode {
            codeCalls += 1
            refreshes.append(refresh)
            if let codeFailure { throw codeFailure }
            let code = String(format: "%06d", 100_000 + codeCalls)
            return FamilyCode(
                code: code, expiresAt: clock.now.addingTimeInterval(validFor),
                inviteUrl: URL(string: "https://shoo-api.afindo-mi01.workers.dev/j/\(code)")!
            )
        }

        func registerDevice(name: String, mode: UserMode, avatarId: String?, apnsToken: String?) async throws -> DeviceRegistration {
            try await base.registerDevice(name: name, mode: mode, avatarId: avatarId, apnsToken: apnsToken)
        }
        func me() async throws -> DeviceProfile { try await base.me() }
        func updateMe(_ update: DeviceUpdate) async throws { try await base.updateMe(update) }
        func joinFamily(code: String) async throws -> GuardianInfo { try await base.joinFamily(code: code) }
        func familyMembers() async throws -> [FamilyMember] { try await base.familyMembers() }
        func removeMember(deviceId: String) async throws { try await base.removeMember(deviceId: deviceId) }
        func leaveGuardian() async throws { try await base.leaveGuardian() }
        func deleteMe() async throws { try await base.deleteMe() }
        func scans(owner: ScanOwnerFilter, status: ScanStatus?, cursor: String?) async throws -> ScanPage {
            try await base.scans(owner: owner, status: status, cursor: cursor)
        }
        func scan(id: String) async throws -> ScanResult { try await base.scan(id: id) }
        func setVerdict(scanId: String, value: Verdict.Value) async throws -> Verdict {
            try await base.setVerdict(scanId: scanId, value: value)
        }
    }

    @Test func countdownRunsAndANewCodeComesAtZero() async {
        let clock = Clock()
        let repository = CodeRepository(clock: clock)
        let model = FamilyCodeModel(repository: repository, now: { clock.now })
        await model.loadMembers()
        await model.refreshCode()
        #expect(model.code?.code == "100001")
        #expect(model.secondsLeft == 1800)
        #expect(model.timeLeft == "30:00")
        clock.now += 1799.2
        #expect(!model.tick())
        #expect(model.secondsLeft == 1)
        #expect(model.timeLeft == "0:01")
        clock.now += 1
        #expect(model.tick())
        await model.refreshCode()
        #expect(model.code?.code == "100002")
        #expect(model.secondsLeft == 1800)
        // Running out asks for the active code, never replaces one.
        #expect(await repository.refreshes == [false, false])
    }

    /// "Refresh code" replaces the code; the old one stops working on the server.
    @Test func refreshReplacesTheCode() async {
        let clock = Clock()
        let repository = CodeRepository(clock: clock)
        let model = FamilyCodeModel(repository: repository, now: { clock.now })
        await model.refreshCode()
        await model.refreshCode(replace: true)
        #expect(model.code?.code == "100002")
        #expect(await repository.refreshes == [false, true])
    }

    /// A phone clock far off from the server's never stalls at 0 or asks for codes in a loop.
    @Test(arguments: [-300.0, 7200.0])
    func clockSkewFallsBackToThirtyMinutes(validFor: TimeInterval) async {
        let clock = Clock()
        let model = FamilyCodeModel(repository: CodeRepository(clock: clock, validFor: validFor), now: { clock.now })
        await model.refreshCode()
        #expect(model.secondsLeft == 1800)
    }

    /// A code the server says ends sooner (it was handed out again) counts down from what is left.
    @Test func runLoopAsksAgainWhenTheCodeRunsOut() async {
        let clock = Clock()
        let repository = CodeRepository(clock: clock, validFor: 60)
        let model = FamilyCodeModel(repository: repository, now: { clock.now })
        var slept = 0
        await model.run { _ in
            slept += 1
            clock.now += 1
            if slept > 125 { throw CancellationError() }
        }
        #expect(await repository.codeCalls == 3)
    }

    @Test func codeUnavailableOffersTryAgain() async {
        let clock = Clock()
        let repository = CodeRepository(clock: clock)
        await repository.failCodes(with: .api(.codeUnavailable, message: "busy"))
        let model = FamilyCodeModel(repository: repository, now: { clock.now })
        await model.refreshCode()
        #expect(model.codeState == .unavailable)
        await repository.failCodes(with: nil)
        await model.refreshCode()
        #expect(model.code != nil)
    }

    @Test func fullFamilyAsksForNoCode() async {
        let clock = Clock()
        let repository = CodeRepository(members: .threeMembers, clock: clock)
        let model = FamilyCodeModel(repository: repository, now: { clock.now })
        await model.loadMembers()
        await model.refreshCode()
        #expect(model.members.count == 3)
        #expect(model.codeState == .full)
        #expect(await repository.codeCalls == 0)
        // Removing someone makes room: a code comes right away.
        await model.remove(model.members[0])
        #expect(model.members.count == 2)
        #expect(model.code != nil)
    }

    /// SECURITY §3 P8: this device only, gone when the code expires.
    @Test func inviteCopyStaysLocalAndExpiresWithTheCode() async throws {
        let clock = Clock()
        let model = FamilyCodeModel(repository: CodeRepository(clock: clock), now: { clock.now })
        await model.refreshCode()
        clock.now += 20
        let pasteboard = LinkCopyTests.FakePasteboard()
        #expect(model.copyInvite(language: .english, to: pasteboard))
        #expect(pasteboard.options[.localOnly] as? Bool == true)
        let expiry = try #require(pasteboard.options[.expirationDate] as? Date)
        #expect(abs(expiry.timeIntervalSince(clock.now) - 1780) < 0.01)
        let text = try #require(pasteboard.items.first?["public.plain-text"] as? String)
        #expect(text.contains("https://shoo-api.afindo-mi01.workers.dev/j/100001"))
        #expect(text.contains("100001"))
        #expect(model.copied)
        // A new code means nothing copied for it yet.
        await model.refreshCode(replace: true)
        #expect(!model.copied)
    }

    /// The QR and the copied text only ever carry our own link for this very code.
    @Test(arguments: [
        ("https://evil.example/j/482193", false),
        ("https://shoo-api.afindo-mi01.workers.dev/j/111111", false),
        ("https://shoo-api.afindo-mi01.workers.dev/join?code=482193", false),
        ("https://shoo-api.afindo-mi01.workers.dev/j/482193", true),
    ])
    func inviteURLMustBeOursForThisCode(link: String, accepted: Bool) {
        let code = FamilyCode(code: "482193", expiresAt: Date(), inviteUrl: URL(string: link)!)
        #expect((FamilyCodeModel.checkedInviteURL(for: code) != nil) == accepted)
    }

    @Test func foreignInviteURLIsNeitherShownNorCopied() async {
        let clock = Clock()
        let model = FamilyCodeModel(repository: ForeignLinkRepository(), now: { clock.now })
        await model.refreshCode()
        #expect(model.code != nil)
        #expect(model.inviteURL == nil)
        let pasteboard = LinkCopyTests.FakePasteboard()
        #expect(!model.copyInvite(language: .english, to: pasteboard))
        #expect(pasteboard.items.isEmpty)
    }

    /// A members answer asked for before a remove never brings the removed person back.
    @Test(.timeLimit(.minutes(1))) func lateMembersAnswerAfterRemoveIsDropped() async {
        let clock = Clock()
        let repository = SlowMembersRepository()
        let model = FamilyCodeModel(repository: repository, now: { clock.now })
        await model.loadMembers()
        #expect(model.members.count == 2)
        await repository.holdNextMembers()
        let late = Task { await model.loadMembers() }
        await repository.waitUntilHeld()
        await model.remove(model.members[1])
        await repository.release()
        await late.value
        #expect(model.members.count == 1)
    }

    @Test func inviteTextInBothLanguages() {
        let code = FamilyCode(code: "482193", expiresAt: Date(), inviteUrl: URL(string: "https://x.test/j/482193")!)
        let english = FamilyCodeModel.inviteText(for: code, language: .english)
        let indonesian = FamilyCodeModel.inviteText(for: code, language: .indonesian)
        #expect(english.contains("482193") && indonesian.contains("482193") && english != indonesian)
    }

    @Test func codeIsShownInTwoGroups() {
        #expect(FamilyCodeModel.display("482193") == "482 193")
    }

    @Test func qrCodeRenders() {
        #expect(QRCode.image(for: "https://shoo-api.afindo-mi01.workers.dev/j/482193") != nil)
    }
}

@MainActor
struct DeepLinkRoutingTests {
    private func environment(mode: UserMode?, onboarded: Bool) -> AppEnvironment {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test.links.\(UUID().uuidString)")!)
        if let mode { settings.chooseMode(mode) }
        settings.onboardingCompleted = onboarded
        return AppEnvironment(repository: MockRepository(mode: mode ?? .protected, latency: .zero), settings: settings)
    }

    @Test func protectedAfterOnboardingOpensConnectWithTheCode() {
        let env = environment(mode: .protected, onboarded: true)
        env.router.selectedTab = .activity
        env.open(URL(string: "shoo://join?code=482193")!)
        #expect(env.router.isConnectPresented)
        #expect(env.router.pendingJoinCode == "482193")
        #expect(env.router.selectedTab == .shield)
    }

    @Test func beforeRegistrationTheCodeWaitsForConnect() {
        let env = environment(mode: nil, onboarded: false)
        env.open(URL(string: "shoo://join?code=482193")!)
        #expect(!env.router.isConnectPresented)
        #expect(env.router.takePendingJoinCode() == "482193")
        #expect(env.router.pendingJoinCode == nil)
    }

    @Test func guardianLandsOnShield() {
        let env = environment(mode: .guardian, onboarded: true)
        env.router.selectedTab = .activity
        env.open(URL(string: "shoo://join?code=482193")!)
        #expect(!env.router.isConnectPresented)
        #expect(env.router.pendingJoinCode == nil)
        #expect(env.router.selectedTab == .shield)
    }

    /// One sheet at a time: Profile closes first, Connect follows from its `onDismiss`.
    @Test func linkWhileProfileIsOpenShowsConnectAfterIt() {
        let env = environment(mode: .protected, onboarded: true)
        env.router.isProfilePresented = true
        env.open(URL(string: "shoo://join?code=482193")!)
        #expect(!env.router.isProfilePresented)
        #expect(!env.router.isConnectPresented)
        env.router.sheetDismissed()
        #expect(env.router.isConnectPresented)
        #expect(env.router.pendingJoinCode == "482193")
    }

    @Test func secondLinkWhileConnectIsOpenOnlyRefillsTheCode() {
        let env = environment(mode: .protected, onboarded: true)
        env.open(URL(string: "shoo://join?code=482193")!)
        _ = env.router.takePendingJoinCode()
        env.open(URL(string: "shoo://join?code=123456")!)
        #expect(env.router.isConnectPresented)
        #expect(env.router.pendingJoinCode == "123456")
    }

    @Test func guardianRegistrationDropsAWaitingCode() async throws {
        let env = environment(mode: nil, onboarded: false)
        env.open(URL(string: "shoo://join?code=482193")!)
        _ = try await env.register(name: "Rina", mode: .guardian)
        #expect(env.router.pendingJoinCode == nil)
    }

    @Test func brokenLinkLandsOnShield() {
        let env = environment(mode: .protected, onboarded: true)
        env.router.selectedTab = .activity
        env.open(URL(string: "shoo://join?code=12")!)
        #expect(!env.router.isConnectPresented)
        #expect(env.router.selectedTab == .shield)
    }
}

/// Answers every code with a link to someone else's site.
private actor ForeignLinkRepository: ShooRepository {
    private let base = MockRepository(mode: .guardian, latency: .zero)
    func createFamilyCode(refresh: Bool) async throws -> FamilyCode {
        FamilyCode(code: "482193", expiresAt: Date().addingTimeInterval(30 * 60), inviteUrl: URL(string: "https://evil.example/j/482193")!)
    }
    func registerDevice(name: String, mode: UserMode, avatarId: String?, apnsToken: String?) async throws -> DeviceRegistration {
        try await base.registerDevice(name: name, mode: mode, avatarId: avatarId, apnsToken: apnsToken)
    }
    func me() async throws -> DeviceProfile { try await base.me() }
    func updateMe(_ update: DeviceUpdate) async throws { try await base.updateMe(update) }
    func joinFamily(code: String) async throws -> GuardianInfo { try await base.joinFamily(code: code) }
    func familyMembers() async throws -> [FamilyMember] { [] }
    func removeMember(deviceId: String) async throws {}
    func leaveGuardian() async throws {}
    func deleteMe() async throws {}
    func scans(owner: ScanOwnerFilter, status: ScanStatus?, cursor: String?) async throws -> ScanPage {
        try await base.scans(owner: owner, status: status, cursor: cursor)
    }
    func scan(id: String) async throws -> ScanResult { try await base.scan(id: id) }
    func setVerdict(scanId: String, value: Verdict.Value) async throws -> Verdict {
        try await base.setVerdict(scanId: scanId, value: value)
    }
}

/// `familyMembers` can be held until `release()`, to answer after a remove.
private actor SlowMembersRepository: ShooRepository {
    private let base = MockRepository(mode: .guardian, latency: .zero)
    private var hold = false
    private var held: CheckedContinuation<Void, Never>?
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []

    func holdNextMembers() { hold = true }
    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { heldWaiters.append($0) }
    }
    func release() {
        held?.resume()
        held = nil
    }

    func familyMembers() async throws -> [FamilyMember] {
        // Read before waiting: this is the "old" answer.
        let answer = try await base.familyMembers()
        if hold {
            hold = false
            await withCheckedContinuation { continuation in
                held = continuation
                heldWaiters.forEach { $0.resume() }
                heldWaiters = []
            }
        }
        return answer
    }
    func removeMember(deviceId: String) async throws { try await base.removeMember(deviceId: deviceId) }
    func createFamilyCode(refresh: Bool) async throws -> FamilyCode { try await base.createFamilyCode(refresh: refresh) }
    func registerDevice(name: String, mode: UserMode, avatarId: String?, apnsToken: String?) async throws -> DeviceRegistration {
        try await base.registerDevice(name: name, mode: mode, avatarId: avatarId, apnsToken: apnsToken)
    }
    func me() async throws -> DeviceProfile { try await base.me() }
    func updateMe(_ update: DeviceUpdate) async throws { try await base.updateMe(update) }
    func joinFamily(code: String) async throws -> GuardianInfo { try await base.joinFamily(code: code) }
    func leaveGuardian() async throws { try await base.leaveGuardian() }
    func deleteMe() async throws { try await base.deleteMe() }
    func scans(owner: ScanOwnerFilter, status: ScanStatus?, cursor: String?) async throws -> ScanPage {
        try await base.scans(owner: owner, status: status, cursor: cursor)
    }
    func scan(id: String) async throws -> ScanResult { try await base.scan(id: id) }
    func setVerdict(scanId: String, value: Verdict.Value) async throws -> Verdict {
        try await base.setVerdict(scanId: scanId, value: value)
    }
}

struct InviteShareTests {
    @Test func whatsAppGetsTheWholeInviteAsOneParameter() throws {
        let text = "Join me: https://x.dev/j/123456?a=b&c=d + more"
        let url = try #require(InviteShare.whatsAppURL(text: text))
        #expect(url.scheme == "whatsapp")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.map(\.name) == ["text"])
        #expect(items.first?.value == text)
    }

    @Test func messagesKeepsTheBodyInOnePiece() throws {
        let text = "code=1234&x"
        let url = try #require(InviteShare.messagesURL(body: text))
        #expect(url.absoluteString == "sms:&body=code%3D1234%26x")
    }
}
