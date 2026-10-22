import Foundation
@testable import Shoo

/// A fake backend per test: every request to `server.baseURL` is answered by its handler.
/// Handlers and recorded requests are keyed by a random host, so suites run in parallel safely.
final class HostStubProtocol: URLProtocol {
    struct Reply: Sendable {
        var status: Int
        var body: Data
        var failure: URLError?

        static func json(_ status: Int, _ text: String) -> Reply { Reply(status: status, body: Data(text.utf8)) }
        static func offline() -> Reply { Reply(status: 0, body: Data(), failure: URLError(.notConnectedToInternet)) }
    }

    /// One request as the server saw it (URLProtocol moves the body into a stream).
    struct Seen: Sendable {
        var method: String
        var path: String
        var query: [String: String]
        var headers: [String: String]
        var body: Data?

        var json: [String: Any]? {
            body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: @Sendable (Seen) -> Reply] = [:]
    nonisolated(unsafe) private static var seen: [String: [Seen]] = [:]

    static func register(host: String, _ handler: @escaping @Sendable (Seen) -> Reply) {
        lock.withLock { handlers[host] = handler }
    }

    static func requests(host: String) -> [Seen] { lock.withLock { seen[host] ?? [] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary((components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
        let entry = Seen(
            method: request.httpMethod ?? "GET",
            path: components?.percentEncodedPath ?? "",
            query: query,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody ?? request.httpBodyStream.map(Self.read)
        )
        let host = url.host() ?? ""
        let handler = Self.lock.withLock {
            Self.seen[host, default: []].append(entry)
            return Self.handlers[host]
        }
        let reply = handler?(entry) ?? .json(404, #"{"error":{"code":"not_found","message":"no stub"}}"#)
        if let failure = reply.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// A stubbed backend plus a session store in a throwaway App Group suite and Keychain item.
final class StubServer: @unchecked Sendable {
    let host = "t\(UUID().uuidString.prefix(8).lowercased()).shoo.test"
    var baseURL: URL { URL(string: "https://\(host)")! }
    let session: SessionStore
    let suiteName = "test.session.\(UUID().uuidString)"
    private let lock = NSLock()
    private var _unauthorizedCount = 0

    init(token: String? = "shoo_test_token_123") {
        let defaults = UserDefaults(suiteName: suiteName)!
        session = SessionStore(
            defaults: defaults,
            keychain: KeychainItem(service: "test.\(UUID().uuidString)", account: "device-session"),
            apiBaseURL: URL(string: "https://api.shoo.test")!,
            aiBaseURL: nil
        )
        if let token {
            try? session.save(
                DeviceRegistration(deviceId: "dev_me", token: token, avatarId: "avatar_01"), name: "Adhella", mode: .guardian
            )
        }
    }

    deinit {
        session.clear()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    var unauthorizedCount: Int { lock.withLock { _unauthorizedCount } }
    var requests: [HostStubProtocol.Seen] { HostStubProtocol.requests(host: host) }

    func reply(_ handler: @escaping @Sendable (HostStubProtocol.Seen) -> HostStubProtocol.Reply) {
        HostStubProtocol.register(host: host, handler)
    }

    func client() -> APIClient {
        let configuration = APIClient.configuration()
        configuration.protocolClasses = [HostStubProtocol.self]
        let session = session
        return APIClient(
            baseURL: baseURL, configuration: configuration, token: { session.token },
            onUnauthorized: { [weak self] in self?.countUnauthorized() }
        )
    }

    func repository() -> ApiRepository { ApiRepository(client: client(), session: session) }

    private func countUnauthorized() { lock.withLock { _unauthorizedCount += 1 } }
}
