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
        await #expect(throws: RepositoryError.self) {
            // blocked-verified-scam belongs to dev_dad.
            try await protected().scan(id: "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e04")
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

    @Test func verdictOnWarningIsNotAllowed() async {
        await #expect {
            try await guardian().setVerdict(scanId: "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e01", value: .notSafe)
        } throws: { ($0 as? RepositoryError)?.apiCode == .verdictNotAllowed }
    }

    @Test func protectedCannotSetVerdict() async {
        await #expect {
            try await protected().setVerdict(scanId: "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03", value: .safe)
        } throws: { ($0 as? RepositoryError)?.apiCode == .verdictNotAllowed }
    }

    @Test(arguments: [
        ("0000", APIErrorCode.codeInvalid),
        ("9999", .codeExpired),
        ("8888", .familyFull),
        ("7777", .tooManyAttempts),
        ("6666", .alreadyConnected),
        ("12a4", .codeInvalid),
    ])
    func joinErrorCodes(code: String, expected: APIErrorCode) async {
        await #expect {
            try await protected().joinFamily(code: code)
        } throws: { ($0 as? RepositoryError)?.apiCode == expected }
    }

    @Test func joinWithValidCodeReturnsGuardian() async throws {
        let repo = protected()
        try await repo.leaveGuardian()
        let before = try await repo.me()
        #expect(before.guardian == nil)
        let guardian = try await repo.joinFamily(code: "4821")
        #expect(guardian.name == "Adhella")
        let after = try await repo.me()
        #expect(after.guardian == guardian)
    }

    @Test func familyCodeIsFourDigitsValidFor60Seconds() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let repo = MockRepository(mode: .guardian, latency: .zero, now: { now })
        let code = try await repo.createFamilyCode()
        #expect(code.code.count == 4)
        let digitsOnly = code.code.allSatisfy(\.isNumber)
        #expect(digitsOnly)
        #expect(code.expiresAt == now.addingTimeInterval(60))
        #expect(code.inviteUrl.scheme == "https")
    }

    @Test func protectedCannotCreateFamilyCode() async {
        await #expect { try await protected().createFamilyCode() } throws: { ($0 as? RepositoryError)?.apiCode == .forbidden }
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
        await #expect { try await repo.registerDevice(name: "  ", mode: .guardian, apnsToken: nil) } throws: {
            ($0 as? RepositoryError)?.apiCode == .invalidBody
        }
        await #expect { try await repo.registerDevice(name: String(repeating: "a", count: 21), mode: .guardian, apnsToken: nil) } throws: {
            ($0 as? RepositoryError)?.apiCode == .invalidBody
        }
        let registration = try await repo.registerDevice(name: " Rina ", mode: .guardian, apnsToken: nil)
        #expect(AvatarCatalog.ids.contains(registration.avatarId))
        #expect(try await repo.me().name == "Rina")
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

    @Test func emptyScenarioHasNothing() async throws {
        let repo = MockRepository(mode: .guardian, scenario: .empty, latency: .zero)
        #expect(try await repo.scans(owner: .family, status: nil, cursor: nil).items.isEmpty)
        #expect(try await repo.familyMembers().isEmpty)
    }
}
