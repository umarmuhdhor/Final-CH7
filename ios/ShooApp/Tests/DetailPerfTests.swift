import UIKit
import XCTest
@testable import Shoo

/// fase 22 S6–S8: memory, time and CPU of the page copy at its biggest (3 MB). Opt-in only:
/// `TEST_RUNNER_SHOO_PERF=1 xcodebuild test …` (xcodebuild drops the `TEST_RUNNER_` prefix). The numbers go
/// to `plan/alief/log/fase-22.md`; there is no baseline to fail against.
final class DetailPerfTests: XCTestCase {
    /// About `URLSessionReplicaLoader.maxHTMLBytes`, far taller than `ReplicaSnapshot.windowHeight`.
    static let biggestPage: String = {
        let head = #"<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0">"#
        let row = #"<p style="margin:0;padding:8px;font:16px -apple-system">Masukkan PIN dan kode OTP Anda untuk melanjutkan.</p>"#
        let tail = "</body></html>"
        let count = (URLSessionReplicaLoader.maxHTMLBytes - head.utf8.count - tail.utf8.count) / row.utf8.count
        return head + String(repeating: row, count: count) + tail
    }()

    static let metrics: [any XCTMetric] = [XCTMemoryMetric(), XCTClockMetric(), XCTCPUMetric()]

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["SHOO_PERF"] == "1" else {
            throw XCTSkip("Opt-in: TEST_RUNNER_SHOO_PERF=1")
        }
    }

    /// S6: the hidden web view draws the biggest copy once (load, place, snapshot).
    @MainActor
    func testRenderBiggestCopy() throws {
        let locked = try XCTUnwrap(ReplicaHTML.locked(Self.biggestPage))
        let ruleList = try XCTUnwrap(wait { await ReplicaRules.compiled() })
        let window = ReplicaSnapshot.keyWindow ?? {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.makeKeyAndVisible()
            return window
        }()
        let meta = ReplicaMeta(url: nil, capturedAt: Date(), focusY: 20_000, truncated: false, marks: [])
        measure(metrics: Self.metrics) {
            let copy = wait { await ReplicaSnapshot.render(locked, meta: meta, ruleList: ruleList, in: window) }
            XCTAssertNotNil(copy)
        }
    }

    /// C14: lock + meta of the biggest copy, off the main actor.
    func testPrepareBiggestCopy() {
        measure(metrics: Self.metrics) {
            let prepared = wait { await DetailView.prepare(Self.biggestPage) }
            XCTAssertNotNil(prepared.locked)
        }
    }

    /// S8: the loader reads the biggest copy from a stub server.
    func testLoadBiggestCopy() throws {
        let configuration = URLSessionScreenshotLoader.configuration()
        configuration.protocolClasses = [BiggestPageProtocol.self]
        let loader = URLSessionReplicaLoader(configuration: configuration, allowedHost: "shoo-api.example.workers.dev")
        let url = try XCTUnwrap(URL(string: "https://shoo-api.example.workers.dev/replicas/abc?exp=1&sig=x"))
        measure(metrics: Self.metrics) {
            let html = wait { try? await loader.html(at: url) }
            XCTAssertEqual(html?.utf8.count, Self.biggestPage.utf8.count)
        }
    }

    /// Runs `work` and waits for it; the main run loop keeps turning, so main-actor work inside still runs.
    private func wait<T>(_ work: @escaping @MainActor () async -> T) -> T {
        let done = expectation(description: "done")
        var result: T?
        Task { @MainActor in
            result = await work()
            done.fulfill()
        }
        wait(for: [done], timeout: 60)
        return result!
    }
}

/// Answers every request with `DetailPerfTests.biggestPage`. Its own class: `ReplicaStubProtocol` belongs to
/// `ReplicaLoaderTests`.
private final class BiggestPageProtocol: URLProtocol {
    static let body = Data(DetailPerfTests.biggestPage.utf8)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
