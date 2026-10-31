import Foundation
import Testing
@testable import Shoo

struct MockRepositoryTests {
    func guardian(pageSize: Int = MockRepository.pageSize) -> MockRepository {
        MockRepository(mode: .guardian, latency: .zero, pageSize: pageSize)
    }

    func protected() -> MockRepository {
        MockRepository(mode: .protected, latency: .zero)
    }

    @Test func familyListsEveryFixtureNewestFirstWithoutScreenshots() async throws {
        let page = try await guardian().scans(owner: .family, status: nil, cursor: nil)
        #expect(page.items.count == 5)
        #expect(page.items.map(\.detectedAt) == page.items.map(\.detectedAt).sorted(by: >))
        #expect(page.items.allSatisfy { $0.screenshotUrl == nil })
        #expect(page.nextCursor == nil)
    }

    @Test func ownerMeIsOnlyMyScans() async throws {
        let page = try await guardian().scans(owner: .me, status: nil, cursor: nil)
        #expect(page.items.map(\.ownerDeviceId) == ["dev_me"])
    }

    @Test func ownerDeviceAndStatusFilter() async throws {
        let page = try await guardian().scans(owner: .device("dev_mom"), status: .blocked, cursor: nil)
        #expect(!page.items.isEmpty)
        #expect(page.items.allSatisfy { $0.ownerDeviceId == "dev_mom" && $0.status == .blocked })
    }

    @Test func cursorPagesThroughEverything() async throws {
        let repo = guardian(pageSize: 2)
        var cursor: String?
        var ids: [String] = []
        repeat {
            let page = try await repo.scans(owner: .family, status: nil, cursor: cursor)
            #expect(page.items.count <= 2)
            ids += page.items.map(\.id)
            cursor = page.nextCursor
        } while cursor != nil
        #expect(ids.count == 5)
        #expect(Set(ids).count == 5)
    }

    @Test func protectedCannotListFamily() async {
        await #expect(throws: RepositoryError.api(.forbidden, message: "Guardian only")) {
            try await protected().scans(owner: .family, status: nil, cursor: nil)
        }
    }

    @Test func protectedSeesOnlyOwnScans() async throws {
        let page = try await protected().scans(owner: .me, status: nil, cursor: nil)
        #expect(!page.items.isEmpty)
        #expect(page.items.allSatisfy { $0.ownerDeviceId == "dev_mom" })
    }

    @Test func scanDetailKeepsScreenshotUrl() async throws {
        let scan = try await guardian().scan(id: "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03")
        #expect(scan.screenshotUrl != nil)
    }

    @Test func protectedCannotOpenSomeoneElsesScan() async {
        await #expect {
            // blocked-verified-scam belongs to dev_dad.
            try await protected().scan(id: "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e04")
        } throws: { ($0 as? RepositoryError)?.apiCode == .notFound }
    }

    @Test func unknownScanIsNotFound() async {
        await #expect { try await guardian().scan(id: "nope") } throws: { ($0 as? RepositoryError)?.apiCode == .notFound }
        await #expect { try await guardian().setVerdict(scanId: "nope", value: .safe) } throws: {
            ($0 as? RepositoryError)?.apiCode == .notFound
        }
    }

    @Test func badCursorIsInvalidBody() async {
        await #expect { try await guardian().scans(owner: .family, status: nil, cursor: "99") } throws: {
            ($0 as? RepositoryError)?.apiCode == .invalidBody
        }
    }

    @Test func removedMemberScansAreNoLongerVisible() async throws {
        let repo = guardian()
        try await repo.removeMember(deviceId: "dev_dad")
        let page = try await repo.scans(owner: .family, status: nil, cursor: nil)
        #expect(!page.items.contains { $0.ownerDeviceId == "dev_dad" })
        await #expect { try await repo.scans(owner: .device("dev_dad"), status: nil, cursor: nil) } throws: {
            ($0 as? RepositoryError)?.apiCode == .notFound
        }
        // blocked-verified-scam belongs to dev_dad.
        await #expect { try await repo.scan(id: "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e04") } throws: {
            ($0 as? RepositoryError)?.apiCode == .notFound
        }
    }

    @Test func verdictAppliesToBlockedScanAndIsStored() async throws {
        let repo = guardian()
        let verdict = try await repo.setVerdict(scanId: "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03", value: .safe)
        #expect(verdict.value == .safe)
        #expect(verdict.byDeviceId == "dev_me")
        let scan = try await repo.scan(id: "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03")
        #expect(scan.verdict == verdict)
    }

    /// GD-07 (#191): warnings take a verdict too.
    @Test func verdictOnWarningIsSaved() async throws {
        let repo = guardian()
        let verdict = try await repo.setVerdict(scanId: "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e01", value: .notSafe)
        #expect(try await repo.scan(id: "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e01").verdict == verdict)
    }

    @Test func protectedCannotSetVerdict() async {
        await #expect {
            try await protected().setVerdict(scanId: "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03", value: .safe)
        } throws: { ($0 as? RepositoryError)?.apiCode == .verdictNotAllowed }
    }

    @Test(arguments: [
        ("000000", APIErrorCode.codeInvalid),
        ("999999", .codeExpired),
        ("888888", .familyFull),
        ("777777", .tooManyAttempts),
        ("666666", .alreadyConnected),
        ("12a456", .codeInvalid),
        ("4821", .codeInvalid),
        ("12345", .codeInvalid),
        ("1234567", .codeInvalid),
        ("\u{0661}\u{0662}\u{0663}\u{0664}\u{0665}\u{0666}", .codeInvalid),
    ])
    func joinErrorCodes(code: String, expected: APIErrorCode) async {
        await #expect {
            try await protected().joinFamily(code: code)
        } throws: { ($0 as? RepositoryError)?.apiCode == expected }
    }

    @Test func joinWhileConnectedIsAlreadyConnected() async {
        await #expect { try await protected().joinFamily(code: "482193") } throws: {
            ($0 as? RepositoryError)?.apiCode == .alreadyConnected
        }
    }

    @Test func leaveWithoutGuardianIsNotFound() async throws {
        let repo = protected()
        try await repo.leaveGuardian()
        await #expect { try await repo.leaveGuardian() } throws: { ($0 as? RepositoryError)?.apiCode == .notFound }
    }

    @Test func wrongModeIsForbidden() async {
        await #expect { try await guardian().joinFamily(code: "482193") } throws: { ($0 as? RepositoryError)?.apiCode == .forbidden }
        await #expect { try await protected().removeMember(deviceId: "dev_dad") } throws: {
            ($0 as? RepositoryError)?.apiCode == .forbidden
        }
    }

    @Test func joinWithValidCodeReturnsGuardian() async throws {
        let repo = protected()
        try await repo.leaveGuardian()
        let before = try await repo.me()
        #expect(before.guardian == nil)
        let guardian = try await repo.joinFamily(code: "482193")
        #expect(guardian.name == "Adhella")
        let after = try await repo.me()
        #expect(after.guardian == guardian)
    }

    @Test func familyCodeIsSixDigitsValidFor30Minutes() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let repo = MockRepository(mode: .guardian, latency: .zero, now: { now })
        let code = try await repo.createFamilyCode(refresh: false)
        #expect(DeepLink.isCode(code.code))
        #expect(code.expiresAt == now.addingTimeInterval(30 * 60))
        #expect(code.inviteUrl.absoluteString == "https://shoo-api.afindo-mi01.workers.dev/j/\(code.code)")
    }

    /// Like the server: the same code while more than 5 min is left, a new one on refresh.
    @Test func familyCodeIsReusedUntilRefreshed() async throws {
        let clock = FamilyCodeModelTests.Clock()
        let repo = MockRepository(mode: .guardian, latency: .zero, now: { clock.now })
        let first = try await repo.createFamilyCode(refresh: false)
        clock.now += 24 * 60
        #expect(try await repo.createFamilyCode(refresh: false) == first)
        clock.now += 60
        let second = try await repo.createFamilyCode(refresh: false)
        #expect(second.expiresAt == clock.now.addingTimeInterval(30 * 60))
        let third = try await repo.createFamilyCode(refresh: true)
        #expect(third.expiresAt == clock.now.addingTimeInterval(30 * 60))
    }

    @Test func protectedCannotCreateFamilyCode() async {
        await #expect { try await protected().createFamilyCode(refresh: false) } throws: { ($0 as? RepositoryError)?.apiCode == .forbidden }
    }

    @Test func membersAndRemove() async throws {
        let repo = guardian()
        #expect(try await repo.familyMembers().count == 2)
        try await repo.removeMember(deviceId: "dev_dad")
        #expect(try await repo.familyMembers().map(\.deviceId) == ["dev_mom"])
        await #expect { try await repo.removeMember(deviceId: "dev_dad") } throws: { ($0 as? RepositoryError)?.apiCode == .notFound }
    }

    @Test func registerValidatesNameLength() async throws {
        let repo = guardian()
        await #expect { try await repo.registerDevice(name: "  ", mode: .guardian, avatarId: nil, apnsToken: nil) } throws: {
            ($0 as? RepositoryError)?.apiCode == .invalidBody
        }
        await #expect { try await repo.registerDevice(name: String(repeating: "a", count: 21), mode: .guardian, avatarId: nil, apnsToken: nil) } throws: {
            ($0 as? RepositoryError)?.apiCode == .invalidBody
        }
        let registration = try await repo.registerDevice(name: " Rina ", mode: .guardian, avatarId: nil, apnsToken: nil)
        #expect(AvatarCatalog.ids.contains(registration.avatarId))
        #expect(try await repo.me().name == "Rina")
    }

    @Test func registerKeepsKnownAvatarOnly() async throws {
        let repo = guardian()
        #expect(try await repo.registerDevice(name: "Rina", mode: .guardian, avatarId: "avatar_02", apnsToken: nil).avatarId == "avatar_02")
        #expect(try await repo.me().avatarId == "avatar_02")
        let unknown = try await repo.registerDevice(name: "Rina", mode: .guardian, avatarId: "avatar_99", apnsToken: nil)
        #expect(AvatarCatalog.ids.contains(unknown.avatarId))
    }

    @Test func updateMeChangesNameAndLanguage() async throws {
        let repo = guardian()
        try await repo.updateMe(DeviceUpdate(name: "Ade", language: "id"))
        let me = try await repo.me()
        #expect(me.name == "Ade")
        #expect(me.language == "id")
        await #expect { try await repo.updateMe(DeviceUpdate(language: "fr")) } throws: {
            ($0 as? RepositoryError)?.apiCode == .invalidBody
        }
    }

    @Test func updateMeIsAllOrNothing() async throws {
        let repo = guardian()
        await #expect { try await repo.updateMe(DeviceUpdate(name: "Budi", language: "fr")) } throws: {
            ($0 as? RepositoryError)?.apiCode == .invalidBody
        }
        #expect(try await repo.me().name == "Adhella")
    }

    @Test func verdictCoversSameDomainAndOwnerAndCanBeReplaced() async throws {
        let repo = guardian()
        let blocked = "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03"
        _ = try await repo.setVerdict(scanId: blocked, value: .notSafe)
        let replaced = try await repo.setVerdict(scanId: blocked, value: .safe)
        #expect(try await repo.scan(id: blocked).verdict == replaced)
        // Other scans (other domains) keep their own verdicts.
        let others = try await repo.scans(owner: .family, status: nil, cursor: nil).items.filter { $0.id != blocked }
        #expect(others.allSatisfy { $0.verdict != replaced })
    }

    @Test func emptyScenarioHasNothing() async throws {
        let repo = MockRepository(mode: .guardian, scenario: .empty, latency: .zero)
        #expect(try await repo.scans(owner: .family, status: nil, cursor: nil).items.isEmpty)
        #expect(try await repo.familyMembers().isEmpty)
    }
}
