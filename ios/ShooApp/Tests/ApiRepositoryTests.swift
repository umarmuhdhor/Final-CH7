import Foundation
import Testing
@testable import Shoo

/// Fase 13: every `ShooRepository` call hits the contract path, and the App Group follows the server.
struct ApiRepositoryTests {
    private static let ok = HostStubProtocol.Reply.json(200, #"{"ok":true}"#)
    private static let guardianJSON = #"{"deviceId":"dev_me","name":"Adhella","avatarId":"avatar_01"}"#

    private static func fixture(_ name: String) -> Data {
        let url = Bundle.main.url(forResource: name, withExtension: "json")!
        return try! Data(contentsOf: url)
    }

    // MARK: Paths

    @Test func registerPostsNameAndModeWithoutToken() async throws {
        let server = StubServer(token: nil)
        server.reply { _ in .json(201, #"{"deviceId":"d1","token":"shoo_x","avatarId":"avatar_07"}"#) }
        let registration = try await server.repository().registerDevice(name: "Rina", mode: .protected, apnsToken: nil)
        #expect(registration == DeviceRegistration(deviceId: "d1", token: "shoo_x", avatarId: "avatar_07"))
        let request = try #require(server.requests.last)
        #expect(request.method == "POST" && request.path == "/devices")
        #expect(request.headers["Authorization"] == nil)
        #expect(request.json?["name"] as? String == "Rina")
        #expect(request.json?["mode"] as? String == "protected")
        #expect(request.json?.keys.contains("apnsToken") == false)
    }

    @Test func scansSendsOwnerStatusAndCursor() async throws {
        let server = StubServer()
        let page = Self.fixture("activity-family")
        server.reply { _ in HostStubProtocol.Reply(status: 200, body: page) }
        let result = try await server.repository().scans(owner: .family, status: .blocked, cursor: "abc")
        #expect(!result.items.isEmpty)
        let request = try #require(server.requests.last)
        #expect(request.method == "GET" && request.path == "/scans")
        #expect(request.query == ["owner": "family", "status": "blocked", "cursor": "abc"])
    }

    @Test func scansForOneMemberUseTheirId() async throws {
        let server = StubServer()
        server.reply { _ in .json(200, #"{"items":[],"nextCursor":null}"#) }
        _ = try await server.repository().scans(owner: .device("dev_mom"), status: nil, cursor: nil)
        #expect(server.requests.last?.query == ["owner": "dev_mom"])
    }

    @Test func everyCallUsesItsContractRoute() async throws {
        let server = StubServer()
        let scan = Self.fixture("blocked-92")
        let members = Self.fixture("family-members")
        server.reply { request in
            switch (request.method, request.path) {
            case ("GET", "/devices/me"):
                .json(200, #"{"deviceId":"dev_me","name":"Adhella","avatarId":"avatar_01","mode":"guardian","language":"en","guardian":null}"#)
            case ("POST", "/family/code"):
                .json(200, #"{"code":"4821","expiresAt":"2026-10-22T03:00:00.123Z","inviteUrl":"https://api.shoo.test/join?code=4821"}"#)
            case ("POST", "/family/join"): .json(200, #"{"guardian":\#(Self.guardianJSON)}"#)
            case ("GET", "/family/members"): HostStubProtocol.Reply(status: 200, body: members)
            case ("GET", "/scans/scan_1"): HostStubProtocol.Reply(status: 200, body: scan)
            case ("POST", "/verdicts"):
                .json(200, #"{"verdict":{"value":"safe","byDeviceId":"dev_me","byName":"Adhella","decidedAt":"2026-10-22T03:00:00Z"}}"#)
            case ("DELETE", "/family/members/dev_mom"), ("DELETE", "/family/guardian"), ("PATCH", "/devices/me"),
                 ("DELETE", "/devices/me"):
                Self.ok
            default: .json(404, #"{"error":{"code":"not_found","message":"unexpected"}}"#)
            }
        }
        let repository = server.repository()
        #expect(try await repository.me().deviceId == "dev_me")
        try await repository.updateMe(DeviceUpdate(language: "id"))
        #expect(try await repository.createFamilyCode().code == "4821")
        #expect(try await repository.joinFamily(code: "4821").name == "Adhella")
        #expect(try await !repository.familyMembers().isEmpty)
        try await repository.removeMember(deviceId: "dev_mom")
        try await repository.leaveGuardian()
        #expect(try await repository.scan(id: "scan_1").status == .blocked)
        #expect(try await repository.setVerdict(scanId: "scan_1", value: .safe).value == .safe)
        try await repository.deleteMe()
        let verdictBody = try #require(server.requests.first { $0.path == "/verdicts" }?.json)
        #expect(verdictBody["scanId"] as? String == "scan_1" && verdictBody["value"] as? String == "safe")
        #expect(server.requests.first { $0.path == "/family/join" }?.json?["code"] as? String == "4821")
        #expect(server.requests.allSatisfy { $0.headers["Authorization"] == "Bearer shoo_test_token_123" })
    }

    // MARK: Session follows the server

    @Test func renameRewritesDeviceNameInTheAppGroup() async throws {
        let server = StubServer()
        server.reply { _ in Self.ok }
        try await server.repository().updateMe(DeviceUpdate(name: "Ibu"))
        #expect(server.session.defaults.string(forKey: AppGroup.Key.deviceName) == "Ibu")
    }

    @Test func failedRenameKeepsTheOldName() async {
        let server = StubServer()
        server.reply { _ in .json(422, #"{"error":{"code":"invalid_body","message":"name"}}"#) }
        await #expect(throws: RepositoryError.self) { try await server.repository().updateMe(DeviceUpdate(name: "Ibu")) }
        #expect(server.session.defaults.string(forKey: AppGroup.Key.deviceName) == "Adhella")
    }

    @Test func joinStoresTheGuardianName() async throws {
        let server = StubServer()
        server.reply { _ in .json(200, #"{"guardian":\#(Self.guardianJSON)}"#) }
        _ = try await server.repository().joinFamily(code: "4821")
        #expect(server.session.defaults.string(forKey: AppGroup.Key.guardianName) == "Adhella")
        #expect(server.session.guardian?.avatarId == "avatar_01")
    }

    @Test func leavingClearsTheGuardianName() async throws {
        let server = StubServer()
        server.session.setGuardian(GuardianInfo(deviceId: "dev_me", name: "Adhella", avatarId: "avatar_01"))
        server.reply { _ in Self.ok }
        try await server.repository().leaveGuardian()
        #expect(server.session.defaults.object(forKey: AppGroup.Key.guardianName) == nil)
    }

    @Test func noGuardianOnTheServerClearsTheGuardianName() async {
        let server = StubServer()
        server.session.setGuardian(GuardianInfo(deviceId: "dev_me", name: "Adhella", avatarId: "avatar_01"))
        server.reply { _ in .json(404, #"{"error":{"code":"not_found","message":"No guardian"}}"#) }
        await #expect(throws: RepositoryError.api(.notFound, message: "No guardian")) {
            try await server.repository().leaveGuardian()
        }
        #expect(server.session.defaults.object(forKey: AppGroup.Key.guardianName) == nil)
    }

    @Test func profileWithoutGuardianClearsTheGuardianName() async throws {
        let server = StubServer()
        server.session.setGuardian(GuardianInfo(deviceId: "dev_me", name: "Adhella", avatarId: "avatar_01"))
        server.reply { _ in
            .json(200, #"{"deviceId":"dev_mom","name":"Ibu","avatarId":"avatar_03","mode":"protected","language":"id","guardian":null}"#)
        }
        _ = try await server.repository().me()
        #expect(server.session.defaults.object(forKey: AppGroup.Key.guardianName) == nil)
        #expect(server.session.defaults.string(forKey: AppGroup.Key.deviceName) == "Ibu")
    }

    @Test func profileWithGuardianStoresIt() async throws {
        let server = StubServer()
        server.reply { _ in
            .json(200, #"{"deviceId":"dev_mom","name":"Mom","avatarId":"avatar_03","mode":"protected","language":"en","guardian":\#(Self.guardianJSON)}"#)
        }
        _ = try await server.repository().me()
        #expect(server.session.defaults.string(forKey: AppGroup.Key.guardianName) == "Adhella")
    }

    // MARK: Delete my data (SECURITY §3 P3, P13)

    @Test func deleteClearsKeychainAndAppGroup() async throws {
        let server = StubServer()
        server.reply { _ in Self.ok }
        try await server.repository().deleteMe()
        #expect(server.session.token == nil)
        for key in SessionStore.appKeys { #expect(server.session.defaults.object(forKey: key) == nil, "\(key)") }
    }

    @Test(arguments: [404, 401])
    func alreadyDeletedStillClearsTheSession(status: Int) async {
        let server = StubServer()
        let code = status == 404 ? "not_found" : "unauthorized"
        server.reply { _ in .json(status, #"{"error":{"code":"\#(code)","message":"gone"}}"#) }
        await #expect(throws: RepositoryError.self) { try await server.repository().deleteMe() }
        #expect(server.session.token == nil)
        #expect(server.session.defaults.object(forKey: AppGroup.Key.deviceToken) == nil)
        // Not "Session expired": Profile treats this as done and starts onboarding over.
        #expect(server.unauthorizedCount == 0)
    }

    @Test func failedDeleteKeepsTheSession() async {
        let server = StubServer()
        server.reply { _ in .offline() }
        await #expect(throws: RepositoryError.network) { try await server.repository().deleteMe() }
        #expect(server.session.token == "shoo_test_token_123")
    }
}
