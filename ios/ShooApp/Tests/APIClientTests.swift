import Foundation
import Testing
@testable import Shoo

/// Fase 13: `APIClient` against a stubbed backend (contracts/api.md).
struct APIClientTests {
    @Test func sendsBearerTokenAndJSON() async throws {
        let server = StubServer()
        server.reply { _ in .json(200, #"{"ok":true}"#) }
        let _: OkResponse = try await server.client().send(.init(
            method: .patch, path: ["devices", "me"], body: DeviceUpdate(name: "Rina")
        ))
        let request = try #require(server.requests.last)
        #expect(request.method == "PATCH")
        #expect(request.path == "/devices/me")
        #expect(request.headers["Authorization"] == "Bearer shoo_test_token_123")
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.json?["name"] as? String == "Rina")
    }

    @Test func nilFieldsAreLeftOutOfTheBody() async throws {
        let server = StubServer()
        server.reply { _ in .json(200, #"{"ok":true}"#) }
        let _: OkResponse = try await server.client().send(.init(
            method: .patch, path: ["devices", "me"], body: DeviceUpdate(language: "id")
        ))
        let body = try #require(server.requests.last?.json)
        #expect(Set(body.keys) == ["language"])
    }

    @Test func datesGoOutAsISO8601() async throws {
        let server = StubServer()
        server.reply { _ in .json(200, #"{"ok":true}"#) }
        let seen = Date(timeIntervalSince1970: 1_792_000_000)
        let _: OkResponse = try await server.client().send(.init(
            method: .patch, path: ["devices", "me"], body: DeviceUpdate(extensionLastSeenAt: seen)
        ))
        let text = try #require(server.requests.last?.json?["extensionLastSeenAt"] as? String)
        #expect(ISO8601DateFormatter().date(from: text) == seen)
    }

    @Test func unauthenticatedCallSendsNoToken() async throws {
        let server = StubServer()
        server.reply { _ in .json(201, #"{"deviceId":"d1","token":"shoo_new","avatarId":"avatar_04"}"#) }
        let registration: DeviceRegistration = try await server.client().send(.init(
            method: .post, path: ["devices"], authorized: false
        ))
        #expect(registration.avatarId == "avatar_04")
        #expect(server.requests.last?.headers["Authorization"] == nil)
    }

    @Test func contractErrorBodyBecomesRepositoryError() async {
        let server = StubServer()
        server.reply { _ in .json(409, #"{"error":{"code":"family_full","message":"Guardian already has 3 members"}}"#) }
        await #expect(throws: RepositoryError.api(.familyFull, message: "Guardian already has 3 members")) {
            let _: OkResponse = try await server.client().send(.init(method: .post, path: ["family", "join"]))
        }
        #expect(server.unauthorizedCount == 0)
    }

    @Test func unauthorizedMarksTheSessionBroken() async {
        let server = StubServer()
        server.reply { _ in .json(401, #"{"error":{"code":"unauthorized","message":"Unknown token"}}"#) }
        await #expect(throws: RepositoryError.api(.unauthorized, message: "Unknown token")) {
            let _: DeviceProfile = try await server.client().send(.init(method: .get, path: ["devices", "me"]))
        }
        #expect(server.unauthorizedCount == 1)
    }

    @Test func unauthorizedCanBeExpectedByTheCaller() async {
        let server = StubServer()
        server.reply { _ in .json(401, #"{"error":{"code":"unauthorized","message":"Unknown token"}}"#) }
        await #expect(throws: RepositoryError.self) {
            let _: OkResponse = try await server.client().send(.init(
                method: .delete, path: ["devices", "me"], reportsUnauthorized: false
            ))
        }
        #expect(server.unauthorizedCount == 0)
    }

    @Test func missingTokenNeverReachesTheServer() async {
        let server = StubServer(token: nil)
        await #expect(throws: RepositoryError.api(.unauthorized, message: "No device session")) {
            let _: DeviceProfile = try await server.client().send(.init(method: .get, path: ["devices", "me"]))
        }
        #expect(server.requests.isEmpty)
        #expect(server.unauthorizedCount == 1)
    }

    @Test(arguments: [(401, APIErrorCode.unauthorized), (404, .notFound), (429, .rateLimited), (502, .internal)])
    func statusWithoutContractBodyMapsToCommonCode(status: Int, code: APIErrorCode) async {
        let server = StubServer()
        server.reply { _ in .json(status, "<html>Bad gateway</html>") }
        await #expect(throws: RepositoryError.api(code, message: "HTTP \(status)")) {
            let _: OkResponse = try await server.client().send(.init(method: .get, path: ["devices", "me"]))
        }
    }

    @Test func successThatBreaksTheContractIsADecodingError() async {
        let server = StubServer()
        server.reply { _ in .json(200, #"{"unexpected":true}"#) }
        await #expect(throws: RepositoryError.decoding) {
            let _: DeviceProfile = try await server.client().send(.init(method: .get, path: ["devices", "me"]))
        }
    }

    @Test func offlineIsANetworkError() async {
        let server = StubServer()
        server.reply { _ in .offline() }
        await #expect(throws: RepositoryError.network) {
            let _: OkResponse = try await server.client().send(.init(method: .get, path: ["devices", "me"]))
        }
    }

    /// T15: ids also come from deep links; anything but a plain id never leaves the app.
    @Test(arguments: ["..", ".", "", "../devices/me", "a/b", "%2e%2e", "abc?x=1", "é"])
    func oddIdsNeverReachTheServer(id: String) async {
        let server = StubServer()
        server.reply { _ in .json(200, "{}") }
        await #expect(throws: RepositoryError.api(.notFound, message: "Invalid id")) {
            _ = try await server.repository().scan(id: id)
        }
        #expect(server.requests.isEmpty)
    }

    @Test func plainIdsPass() {
        #expect(APIClient.isPlainSegment("6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03"))
        #expect(APIClient.isPlainSegment("dev_mom"))
    }

    @Test func redirectAnswerIsNotASuccess() async {
        let server = StubServer()
        server.reply { _ in .json(302, "") }
        await #expect(throws: RepositoryError.self) {
            let _: OkResponse = try await server.client().send(.init(method: .get, path: ["devices", "me"]))
        }
        #expect(server.requests.count == 1)
    }

    /// SECURITY §3 P9 + P13: answers carry user data; nothing is kept on disk.
    @Test func sessionKeepsNothingOnDisk() {
        let configuration = APIClient.configuration()
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.urlCredentialStorage == nil)
    }
}
