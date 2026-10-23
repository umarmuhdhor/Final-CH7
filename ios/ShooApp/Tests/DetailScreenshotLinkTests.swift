import Foundation
import Testing
@testable import Shoo

/// D-alief-C04: a failed screenshot link may only have expired (1 h). Detail asks for the scan once
/// more before saying the screenshot is gone.
@MainActor
struct DetailScreenshotLinkTests {
    private static func scanJSON(link: String?) -> Data {
        let url = Bundle.main.url(forResource: "blocked-92", withExtension: "json")!
        var object = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        object["screenshotUrl"] = link ?? NSNull()
        return try! JSONSerialization.data(withJSONObject: object)
    }

    private static let me = HostStubProtocol.Reply.json(
        200, #"{"deviceId":"dev_me","name":"Adhella","avatarId":"avatar_01","mode":"guardian","language":"en","guardian":null}"#
    )

    /// Answers `GET /scans/{id}` with the given replies in order (the last one repeats).
    private func model(scanReplies: [HostStubProtocol.Reply]) -> (DetailModel, StubServer) {
        let server = StubServer()
        let lock = NSLock()
        nonisolated(unsafe) var remaining = scanReplies
        server.reply { request in
            guard request.path.hasPrefix("/scans/") else { return Self.me }
            return lock.withLock { remaining.count > 1 ? remaining.removeFirst() : remaining[0] }
        }
        return (DetailModel(scanId: FixtureScan.blocked92, repository: server.repository()), server)
    }

    @Test func expiredLinkIsReplacedOnce() async {
        let (model, server) = model(scanReplies: [
            HostStubProtocol.Reply(status: 200, body: Self.scanJSON(link: "https://api.shoo.test/screenshots/a?sig=old")),
            HostStubProtocol.Reply(status: 200, body: Self.scanJSON(link: "https://api.shoo.test/screenshots/a?sig=new")),
        ])
        await model.load()
        #expect(await model.refreshScreenshotLink())
        #expect(model.scan?.screenshotUrl?.absoluteString == "https://api.shoo.test/screenshots/a?sig=new")
        // A second failure is final until the next load.
        #expect(await !model.refreshScreenshotLink())
        withExtendedLifetime(server) {}
    }

    @Test func sameLinkMeansReallyUnavailable() async {
        let (model, server) = model(scanReplies: [
            HostStubProtocol.Reply(status: 200, body: Self.scanJSON(link: "https://api.shoo.test/screenshots/a?sig=old")),
        ])
        await model.load()
        #expect(await !model.refreshScreenshotLink())
        #expect(model.state == .loaded)
        withExtendedLifetime(server) {}
    }

    @Test func deletedScanShowsNotFound() async {
        let (model, server) = model(scanReplies: [
            HostStubProtocol.Reply(status: 200, body: Self.scanJSON(link: "https://api.shoo.test/screenshots/a?sig=old")),
            .json(404, #"{"error":{"code":"not_found","message":"gone"}}"#),
        ])
        await model.load()
        #expect(await !model.refreshScreenshotLink())
        #expect(model.state == .notFound)
        #expect(model.scan == nil)
        withExtendedLifetime(server) {}
    }
}
