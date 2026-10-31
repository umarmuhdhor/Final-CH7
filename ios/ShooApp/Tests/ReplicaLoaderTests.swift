import Foundation
import Testing
@testable import Shoo

/// Answers every request from `handler` instead of the network. Only `ReplicaLoaderTests` (serialized) uses it;
/// `StubURLProtocol` belongs to `ScreenshotLoaderTests`, and the two suites may run at the same time.
final class ReplicaStubProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: (@Sendable (URLRequest) -> (Int, Data))?
    nonisolated(unsafe) private static var _requests: [URLRequest] = []

    static func reset(_ handler: (@Sendable (URLRequest) -> (Int, Data))?) {
        lock.withLock {
            _handler = handler
            _requests = []
        }
    }

    static var requests: [URLRequest] { lock.withLock { _requests } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.lock.withLock {
            Self._requests.append(request)
            return Self._handler
        }
        let (status, data) = handler?(request) ?? (404, Data())
        if status == 302 {
            let elsewhere = URL(string: "https://evil.example/replicas/abc")!
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 302, httpVersion: nil, headerFields: ["Location": elsewhere.absoluteString]
            )!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: elsewhere), redirectResponse: response)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct ReplicaLoaderTests {
    static let url = URL(string: "https://shoo-api.example.workers.dev/replicas/abc?v=dev&exp=1&sig=x")!
    static let page = Data("<!doctype html><html><body>Saldo</body></html>".utf8)

    private func loader() -> URLSessionReplicaLoader {
        let configuration = URLSessionScreenshotLoader.configuration()
        configuration.protocolClasses = [ReplicaStubProtocol.self]
        return URLSessionReplicaLoader(configuration: configuration, allowedHost: "shoo-api.example.workers.dev")
    }

    @Test func sharedSessionKeepsNoCopy() {
        // Same configuration as screenshots (P9 + P13): every view asks the Worker, which re-checks access.
        let configuration = URLSessionScreenshotLoader.configuration()
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCredentialStorage == nil)
    }

    @Test func loadsHTMLWithoutAuthorizationHeader() async throws {
        let page = Self.page
        ReplicaStubProtocol.reset { _ in (200, page) }
        let html = try await loader().html(at: Self.url)
        #expect(html == String(decoding: page, as: UTF8.self))
        let request = try #require(ReplicaStubProtocol.requests.last)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func goneReplicaThrows() async {
        ReplicaStubProtocol.reset { _ in (404, Data()) }
        await #expect(throws: ReplicaLoadError.unavailable) {
            try await loader().html(at: Self.url)
        }
    }

    @Test func tooManyViewsSaysTryLater() async {
        ReplicaStubProtocol.reset { _ in (429, Data(#"{"error":{"code":"rate_limited"}}"#.utf8)) }
        await #expect(throws: ReplicaLoadError.rateLimited) {
            try await loader().html(at: Self.url)
        }
    }

    @Test func exactlyThreeMegabytesLoads() async throws {
        let body = Data(repeating: UInt8(ascii: "a"), count: URLSessionReplicaLoader.maxHTMLBytes)
        ReplicaStubProtocol.reset { _ in (200, body) }
        #expect(try await loader().html(at: Self.url).utf8.count == URLSessionReplicaLoader.maxHTMLBytes)
    }

    @Test func overThreeMegabytesStops() async {
        let body = Data(repeating: UInt8(ascii: "a"), count: URLSessionReplicaLoader.maxHTMLBytes + 1)
        ReplicaStubProtocol.reset { _ in (200, body) }
        await #expect(throws: ReplicaLoadError.unavailable) {
            try await loader().html(at: Self.url)
        }
    }

    @Test func nonUTF8Throws() async {
        ReplicaStubProtocol.reset { _ in (200, Data([0xff, 0xfe, 0xfd])) }
        await #expect(throws: ReplicaLoadError.unavailable) {
            try await loader().html(at: Self.url)
        }
    }

    @Test func otherHostsAndPathsAreNeverContacted() async {
        ReplicaStubProtocol.reset { _ in (200, Self.page) }
        for link in [
            "https://evil.example/replicas/abc",
            "https://shoo-api.example.workers.dev/screenshots/abc",
            "https://shoo-api.example.workers.dev/devices/me",
            "http://shoo-api.example.workers.dev/replicas/abc",
        ] {
            await #expect(throws: ReplicaLoadError.unavailable) {
                try await loader().html(at: URL(string: link)!)
            }
        }
        #expect(ReplicaStubProtocol.requests.isEmpty)
    }

    @Test func redirectsAreNotFollowed() async {
        ReplicaStubProtocol.reset { request in
            request.url?.host() == "evil.example" ? (200, Self.page) : (302, Data())
        }
        await #expect(throws: ReplicaLoadError.unavailable) {
            try await loader().html(at: Self.url)
        }
        #expect(ReplicaStubProtocol.requests.allSatisfy { $0.url?.host() != "evil.example" })
    }

    @Test func otherPortOrDotSegmentsAreRefused() throws {
        let port = try #require(URL(string: "https://shoo.example:8443/replicas/abc"))
        #expect(!URLSessionReplicaLoader.isAllowed(port, host: "shoo.example"))
        let dots = try #require(URL(string: "https://shoo.example/replicas/../screenshots/abc"))
        #expect(!URLSessionReplicaLoader.isAllowed(dots, host: "shoo.example"))
        let fine = try #require(URL(string: "https://shoo.example/replicas/abc?e=1"))
        #expect(URLSessionReplicaLoader.isAllowed(fine, host: "shoo.example"))
    }

    @Test func localWorkerOverHTTPInDebugOnly() throws {
        let url = try #require(URL(string: "http://localhost:8787/replicas/abc"))
        #if DEBUG
        #expect(URLSessionReplicaLoader.isAllowed(url, host: "localhost"))
        #else
        #expect(!URLSessionReplicaLoader.isAllowed(url, host: "localhost"))
        #endif
    }
}
