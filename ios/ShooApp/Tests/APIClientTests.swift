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

    /// EX-03 (QA 2026-11-10 #5): the island's tokens as contracts/api.md asks: hex, `{ activityId, token }`,
    /// and an explicit `null` to clear (a plain `nil` would leave the key out).
    @Test func liveActivityTokensAreSetAndClearedExplicitly() async throws {
        let server = StubServer()
        server.reply { _ in .json(200, #"{"ok":true}"#) }
        let client = server.client()
        let _: OkResponse = try await client.send(.init(
            method: .patch, path: ["devices", "me"], body: DeviceUpdate(liveActivityStartToken: .set("ab12"))
        ))
        #expect(server.requests.last?.json as? [String: String] == ["liveActivityStartToken": "ab12"])

        let _: OkResponse = try await client.send(.init(
            method: .patch, path: ["devices", "me"],
            body: DeviceUpdate(liveActivityUpdateToken: .set(LiveActivityUpdateToken(activityId: "A-1", token: "cd34")))
        ))
        let update = try #require(server.requests.last?.json?["liveActivityUpdateToken"] as? [String: String])
        #expect(update == ["activityId": "A-1", "token": "cd34"])

        let _: OkResponse = try await client.send(.init(
            method: .patch, path: ["devices", "me"], body: DeviceUpdate(liveActivityUpdateToken: .clear)
        ))
        let cleared = try #require(server.requests.last?.json)
        #expect(Set(cleared.keys) == ["liveActivityUpdateToken"])
        #expect(cleared["liveActivityUpdateToken"] is NSNull)
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
        // Not "Session expired": no token means never registered or just cleared (launch check covers restores).
        #expect(server.unauthorizedCount == 0)
    }

    /// A captive portal, proxy or edge 401 is not the backend saying the token is dead.
    @Test(arguments: [#"{"error":{"code":"blocked_by_proxy","message":"x"}}"#, "<html>Log in to Wi-Fi</html>", ""])
    func nonContract401KeepsTheSession(body: String) async {
        let server = StubServer()
        server.reply { _ in .json(401, body) }
        await #expect(throws: RepositoryError.self) {
            let _: DeviceProfile = try await server.client().send(.init(method: .get, path: ["devices", "me"]))
        }
        #expect(server.unauthorizedCount == 0)
    }

    @Test(arguments: [(401, APIErrorCode.unauthorized), (404, .notFound), (429, .rateLimited), (502, .internal)])
    func statusWithoutContractBodyMapsToCommonCode(status: Int, code: APIErrorCode) async {
        let server = StubServer()
        server.reply { _ in .json(status, "<html>Bad gateway</html>") }
        await #expect(throws: RepositoryError.api(code, message: "HTTP \(status)")) {
            let _: OkResponse = try await server.client().send(.init(method: .get, path: ["devices", "me"]))
        }
        #expect(server.unauthorizedCount == 0)
    }

    /// Row 2 (Connect countdown): a 429 with `Retry-After` keeps the code and says how long to wait.
    @Test func tooManyAttemptsCarriesRetryAfter() async {
        let server = StubServer()
        server.reply { _ in
            .json(429, #"{"error":{"code":"too_many_attempts","message":"Too many join attempts"}}"#, headers: ["Retry-After": "299"])
        }
        await #expect(throws: RepositoryError.throttled(.tooManyAttempts, message: "Too many join attempts", retryAfter: 299)) {
            let _: OkResponse = try await server.client().send(.init(method: .post, path: ["family", "join"]))
        }
    }

    @Test func throttledStillReadsAsItsCode() {
        let error = RepositoryError.throttled(.rateLimited, message: "Too many requests", retryAfter: 60)
        #expect(error.apiCode == .rateLimited)
        #expect(error.retryAfter == 60)
        #expect(RepositoryError.api(.rateLimited, message: "x").retryAfter == nil)
        // Only a 429 waits: other statuses keep the plain contract error.
        #expect(APIClient.error(status: 409, body: Data(#"{"error":{"code":"has_members","message":"m"}}"#.utf8), retryAfter: 5)
            == .api(.hasMembers, message: "m"))
        #expect(APIClient.error(status: 429, body: Data(), retryAfter: 5) == .throttled(.rateLimited, message: "HTTP 429", retryAfter: 5))
    }

    @Test func retryAfterReadsSecondsAndDates() {
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        #expect(APIClient.retryAfter("120", now: now) == 120)
        #expect(APIClient.retryAfter(" 0 ", now: now) == 0)
        #expect(APIClient.retryAfter("-5", now: now) == 0)
        #expect(APIClient.retryAfter("99999999", now: now) == APIClient.maxRetryAfter)
        #expect(APIClient.retryAfter(nil, now: now) == nil)
        #expect(APIClient.retryAfter("soon", now: now) == nil)
        // 1_792_000_000 is Wed, 14 Oct 2026 17:46:40 GMT.
        #expect(APIClient.retryAfter("Wed, 14 Oct 2026 17:47:40 GMT", now: now) == 60)
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
