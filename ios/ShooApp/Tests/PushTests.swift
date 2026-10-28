import Foundation
import Testing
@testable import Shoo

/// Fase 15: push payloads (GD-06), the APNs token (ON-05), and `shoo://scan` / `shoo://activity`.
struct NotificationRouterTests {
    private static let scanId = "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03"

    @Test(arguments: [
        "Mom hit a blocked site · 92%",
        "Mom opened a suspicious site · 41%",
    ])
    func contractPayloadsGiveTheScan(body: String) {
        let userInfo: [AnyHashable: Any] = ["aps": ["alert": ["body": body], "sound": "default"], "scanId": Self.scanId]
        #expect(NotificationRouter.scanId(userInfo: userInfo) == Self.scanId)
    }

    @Test(arguments: [
        [:],
        ["scanId": 42],
        ["scanId": ""],
        ["scanId": "../devices/me"],
        ["scanId": "a/b"],
        ["scanId": String(repeating: "a", count: 129)],
    ] as [[String: AnyHashable]])
    func unusableScanIdIsNil(userInfo: [String: AnyHashable]) {
        #expect(NotificationRouter.scanId(userInfo: userInfo) == nil)
    }

    @Test func tokenIsLowercaseHex() {
        #expect(NotificationRouter.hex(token: Data([0x00, 0x0f, 0xab, 0xff])) == "000fabff")
        #expect(NotificationRouter.hex(token: Data()) == "")
    }
}

@MainActor
struct PushRoutingTests {
    private static let scanId = "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03"

    /// Records `PATCH /devices/me` bodies; `hold()` keeps them in flight until `release()`.
    actor RecordingRepository: ShooRepository {
        private let base: MockRepository
        private(set) var updates: [DeviceUpdate] = []
        private var failNext = false
        private var holding = false
        private var held: [CheckedContinuation<Void, Never>] = []

        func failNextUpdate() { failNext = true }
        func hold() { holding = true }
        func release() {
            holding = false
            held.forEach { $0.resume() }
            held = []
        }
        var inFlight: Int { held.count }

        init(mode: UserMode) {
            base = MockRepository(mode: mode, latency: .zero)
        }

        func updateMe(_ update: DeviceUpdate) async throws {
            if holding { await withCheckedContinuation { held.append($0) } }
            if failNext {
                failNext = false
                throw RepositoryError.network
            }
            updates.append(update)
            try await base.updateMe(update)
        }

        func registerDevice(name: String, mode: UserMode, avatarId: String?, apnsToken: String?) async throws -> DeviceRegistration {
            try await base.registerDevice(name: name, mode: mode, avatarId: avatarId, apnsToken: apnsToken)
        }
        func me() async throws -> DeviceProfile { try await base.me() }
        func createFamilyCode(refresh: Bool) async throws -> FamilyCode { try await base.createFamilyCode(refresh: refresh) }
        func joinFamily(code: String) async throws -> GuardianInfo { try await base.joinFamily(code: code) }
        func familyMembers() async throws -> [FamilyMember] { try await base.familyMembers() }
        func removeMember(deviceId: String) async throws { try await base.removeMember(deviceId: deviceId) }
        func leaveGuardian() async throws { try await base.leaveGuardian() }
        func setMemberNotify(deviceId: String, notify: Bool) async throws { try await base.setMemberNotify(deviceId: deviceId, notify: notify) }
        func remindMember(deviceId: String) async throws { try await base.remindMember(deviceId: deviceId) }
        func becomeProtected(code: String) async throws -> ProtectedSwitch { try await base.becomeProtected(code: code) }
        func deleteMe() async throws { try await base.deleteMe() }
        func scans(owner: ScanOwnerFilter, status: ScanStatus?, cursor: String?) async throws -> ScanPage {
            try await base.scans(owner: owner, status: status, cursor: cursor)
        }
        func scan(id: String) async throws -> ScanResult { try await base.scan(id: id) }
        func setVerdict(scanId: String, value: Verdict.Value) async throws -> Verdict {
            try await base.setVerdict(scanId: scanId, value: value)
        }
    }

    @MainActor
    private final class Calls {
        var registered = 0
    }

    private func waitUntilInFlight(_ repository: RecordingRepository) async {
        while await repository.inFlight == 0 { await Task.yield() }
    }

    private func environment(
        mode: UserMode?,
        onboarded: Bool = true,
        repository: (any ShooRepository)? = nil,
        notifications: NotificationAuthorization = .authorized,
        calls: Calls? = nil
    ) -> AppEnvironment {
        let calls = calls ?? Calls()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test.push.\(UUID().uuidString)")!)
        if let mode { _ = settings.chooseMode(mode) }
        settings.onboardingCompleted = onboarded
        return AppEnvironment(
            repository: repository ?? MockRepository(mode: mode ?? .guardian, latency: .zero),
            settings: settings,
            notifications: FixedStatus(value: notifications),
            registerForPush: { calls.registered += 1 }
        )
    }

    struct FixedStatus: NotificationPermission {
        let value: NotificationAuthorization
        func status() async -> NotificationAuthorization { value }
        func request() async -> NotificationAuthorization { value }
    }

    // MARK: Taps and links

    @Test func pushTapOpensDetailOnActivityOverAnything() {
        let env = environment(mode: .guardian)
        env.router.shieldPath = [.profile, .detail(scanId: "other")]
        env.openPush(scanId: Self.scanId)
        #expect(env.router.selectedTab == .activity)
        #expect(env.router.activityPath == [.detail(scanId: Self.scanId)])
        #expect(env.router.shieldPath.isEmpty)
    }

    /// The Protected device only gets family pushes (PF-01: "Ingatkan", disconnect): a tap opens Shield.
    @Test func protectedPushTapOpensShield() {
        let env = environment(mode: .protected)
        env.router.selectedTab = .activity
        env.router.activityPath = [.profile]
        env.openPush(scanId: Self.scanId)
        #expect(env.router.activityPath.isEmpty)
        #expect(env.router.selectedTab == .shield)
    }

    @Test(arguments: [
        (UserMode.guardian, true, true),
        (.guardian, false, false),
        (.protected, true, true),
        (.protected, false, false),
    ])
    func bannerOnlyWhereATapCanOpenIt(mode: UserMode, onboarded: Bool, expected: Bool) {
        #expect(environment(mode: mode, onboarded: onboarded).showsPushBanner == expected)
    }

    @Test func pushWithoutScanOpensShield() {
        let env = environment(mode: .guardian)
        env.router.selectedTab = .activity
        env.openPush(scanId: nil)
        #expect(env.router.selectedTab == .shield)
        #expect(env.router.activityPath.isEmpty)
    }

    @Test func nothingOpensDuringOnboarding() {
        let env = environment(mode: .guardian, onboarded: false)
        env.openPush(scanId: Self.scanId)
        env.open(URL(string: "shoo://scan/\(Self.scanId)")!)
        #expect(env.router.activityPath.isEmpty)
        #expect(env.router.selectedTab == .shield)
    }

    /// The extension's block screen links here (Protected: Detail without verdict buttons).
    @Test(arguments: [UserMode.guardian, .protected])
    func scanLinkOpensDetail(mode: UserMode) {
        let env = environment(mode: mode)
        env.open(URL(string: "shoo://scan/\(Self.scanId)")!)
        #expect(env.router.selectedTab == .activity)
        #expect(env.router.activityPath == [.detail(scanId: Self.scanId)])
    }

    @Test func activityLinkOpensTheList() {
        let env = environment(mode: .protected)
        env.router.isTurnOnPresented = true
        env.router.activityPath = [.detail(scanId: "old")]
        env.open(URL(string: "shoo://activity")!)
        #expect(env.router.selectedTab == .activity)
        #expect(env.router.activityPath.isEmpty)
        #expect(!env.router.isTurnOnPresented)
    }

    @Test(arguments: ["shoo://scan/../devices", "shoo://scan", "shoo://settings", "https://evil.example/scan/1"])
    func brokenLinksOpenShield(link: String) {
        let env = environment(mode: .guardian)
        env.router.selectedTab = .activity
        env.open(URL(string: link)!)
        #expect(env.router.selectedTab == .shield)
        #expect(env.router.activityPath.isEmpty)
    }

    // MARK: APNs token (ON-05)

    @Test func guardianSendsTheTokenOnce() async {
        let repository = RecordingRepository(mode: .guardian)
        let env = environment(mode: .guardian, repository: repository)
        await env.pushTokenReceived(Data([0xab, 0xcd]))
        await env.pushTokenReceived(Data([0xab, 0xcd]))
        #expect(await repository.updates == [DeviceUpdate(apnsToken: "abcd")])
        // A new token (restore, reinstall) is sent again.
        await env.pushTokenReceived(Data([0x01]))
        #expect(await repository.updates.last == DeviceUpdate(apnsToken: "01"))
    }

    /// PF-01 (proposed in backend/API.md): the Protected device sends its token for family pushes.
    @Test func protectedSendsItsTokenToo() async {
        let repository = RecordingRepository(mode: .protected)
        let env = environment(mode: .protected, repository: repository)
        await env.pushTokenReceived(Data([0xab]))
        #expect(await repository.updates == [DeviceUpdate(apnsToken: "ab")])
    }

    @Test func noTokenBeforeAModeIsChosen() async {
        let repository = RecordingRepository(mode: .guardian)
        let env = environment(mode: nil, onboarded: false, repository: repository)
        await env.pushTokenReceived(Data([0xab]))
        #expect(await repository.updates.isEmpty)
    }

    /// A new registration is a new device on the server: the same APNs token goes again.
    @Test func newRegistrationSendsTheTokenAgain() async throws {
        let repository = RecordingRepository(mode: .guardian)
        let env = environment(mode: .guardian, repository: repository)
        await env.pushTokenReceived(Data([0xab]))
        _ = try await env.register(name: "Rina", mode: .guardian)
        await env.pushTokenReceived(Data([0xab]))
        #expect(await repository.updates.filter { $0.apnsToken == "ab" }.count == 2)
    }

    @Test func sameTokenWhileTheFirstSendIsInFlightIsNotSentTwice() async {
        let repository = RecordingRepository(mode: .guardian)
        let env = environment(mode: .guardian, repository: repository)
        await repository.hold()
        let first = Task { await env.pushTokenReceived(Data([0xab])) }
        await waitUntilInFlight(repository)
        await env.pushTokenReceived(Data([0xab]))
        await repository.release()
        await first.value
        #expect(await repository.updates == [DeviceUpdate(apnsToken: "ab")])
    }

    /// The old device's send finishing late must not mark the new device's token as sent.
    @Test func registrationDuringASendStillSendsForTheNewDevice() async throws {
        let repository = RecordingRepository(mode: .guardian)
        let env = environment(mode: .guardian, repository: repository)
        await repository.hold()
        let old = Task { await env.pushTokenReceived(Data([0xab])) }
        await waitUntilInFlight(repository)
        _ = try await env.register(name: "Rina", mode: .guardian)
        await repository.release()
        await old.value
        await env.pushTokenReceived(Data([0xab]))
        #expect(await repository.updates.filter { $0.apnsToken == "ab" }.count == 2)
    }

    @Test func expiredSessionNeitherSendsTheTokenNorOpensAPush() async {
        let repository = RecordingRepository(mode: .guardian)
        let env = environment(mode: .guardian, repository: repository)
        env.markSessionExpired()
        await env.pushTokenReceived(Data([0xab]))
        env.openPush(scanId: Self.scanId)
        env.open(URL(string: "shoo://scan/\(Self.scanId)")!)
        #expect(await repository.updates.isEmpty)
        #expect(env.router.activityPath.isEmpty)
        #expect(!env.showsPushBanner)
    }

    @Test func failedTokenSyncIsRetriedNextTime() async {
        let repository = RecordingRepository(mode: .guardian)
        let env = environment(mode: .guardian, repository: repository)
        await repository.failNextUpdate()
        await env.pushTokenReceived(Data([0xab]))
        #expect(await repository.updates.isEmpty)
        await env.pushTokenReceived(Data([0xab]))
        #expect(await repository.updates == [DeviceUpdate(apnsToken: "ab")])
    }

    @Test(arguments: [
        (UserMode.guardian, NotificationAuthorization.authorized, 1),
        (.guardian, .denied, 0),
        (.guardian, .notDetermined, 0),
        (.protected, .authorized, 1),
        (.protected, .denied, 0),
    ])
    func registersForPushOnlyWhenAllowed(mode: UserMode, status: NotificationAuthorization, expected: Int) async {
        let calls = Calls()
        let env = environment(mode: mode, notifications: status, calls: calls)
        await env.registerForPushIfAllowed()
        #expect(calls.registered == expected)
    }
}
