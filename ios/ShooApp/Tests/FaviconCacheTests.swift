import Foundation
import Testing
import SwiftUI
import UIKit
@testable import Shoo

/// Fase 22c (K10 a): `faviconUrl` is signed again on every `GET /scans`, so the cache key is the scan id
/// from `/favicons/<id>`, never the signed link. Memory only (SECURITY §3 P9), emptied when data goes (P13).
struct FaviconCacheTests {
    /// Counts downloads; `failing` makes the next ones throw, `whileLoading` runs before the answer.
    final class CountingLoader: FaviconLoading, @unchecked Sendable {
        private let lock = NSLock()
        private var _urls: [URL] = []
        private var _failing = false
        private var _whileLoading: (@Sendable () -> Void)?

        var count: Int { lock.withLock { _urls.count } }
        var urls: [URL] { lock.withLock { _urls } }
        var failing: Bool {
            get { lock.withLock { _failing } }
            set { lock.withLock { _failing = newValue } }
        }
        var whileLoading: (@Sendable () -> Void)? {
            get { lock.withLock { _whileLoading } }
            set { lock.withLock { _whileLoading = newValue } }
        }

        func image(at url: URL) async throws -> UIImage {
            let (fails, hook) = lock.withLock { () -> (Bool, (@Sendable () -> Void)?) in
                _urls.append(url)
                return (_failing, _whileLoading)
            }
            hook?()
            if fails { throw FaviconLoadError.unavailable }
            return UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }
        }
    }

    private static let scanA = "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e01"
    private static let scanB = "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e02"

    private static func link(_ id: String, exp: Int, host: String = "api.shoo.test") -> URL {
        URL(string: "https://\(host)/favicons/\(id)?v=dev_me&exp=\(exp)&sig=sig\(exp)")!
    }

    @Test func sameScanWithANewSignatureIsDownloadedOnce() async throws {
        let loader = CountingLoader()
        let cache = CachedFaviconLoader(loader: loader, notificationCenter: NotificationCenter())
        let first = try await cache.image(at: Self.link(Self.scanA, exp: 1000))
        let second = try await cache.image(at: Self.link(Self.scanA, exp: 4600))
        #expect(loader.count == 1)
        #expect(first === second)
    }

    @Test func differentScansAreDownloadedEach() async throws {
        let loader = CountingLoader()
        let cache = CachedFaviconLoader(loader: loader, notificationCenter: NotificationCenter())
        _ = try await cache.image(at: Self.link(Self.scanA, exp: 1000))
        _ = try await cache.image(at: Self.link(Self.scanB, exp: 1000))
        #expect(loader.count == 2)
    }

    @Test func clearDownloadsAgain() async throws {
        let loader = CountingLoader()
        let cache = CachedFaviconLoader(loader: loader, notificationCenter: NotificationCenter())
        _ = try await cache.image(at: Self.link(Self.scanA, exp: 1000))
        cache.clear()
        #expect(cache.cachedImage(at: Self.link(Self.scanA, exp: 1000)) == nil)
        _ = try await cache.image(at: Self.link(Self.scanA, exp: 4600))
        #expect(loader.count == 2)
    }

    @Test func failuresAreNotCached() async throws {
        let loader = CountingLoader()
        loader.failing = true
        let cache = CachedFaviconLoader(loader: loader, notificationCenter: NotificationCenter())
        await #expect(throws: FaviconLoadError.unavailable) {
            _ = try await cache.image(at: Self.link(Self.scanA, exp: 1000))
        }
        loader.failing = false
        _ = try await cache.image(at: Self.link(Self.scanA, exp: 1000))
        #expect(loader.count == 2)
    }

    @Test func memoryWarningEmptiesTheCache() async throws {
        let loader = CountingLoader()
        let center = NotificationCenter()
        let cache = CachedFaviconLoader(loader: loader, notificationCenter: center)
        _ = try await cache.image(at: Self.link(Self.scanA, exp: 1000))
        center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        #expect(cache.cachedImage(at: Self.link(Self.scanA, exp: 1000)) == nil)
        _ = try await cache.image(at: Self.link(Self.scanA, exp: 1000))
        #expect(loader.count == 2)
    }

    /// P13: a download that was already running when the data went must not refill the cache.
    @Test func aDownloadFinishingAfterClearIsNotKept() async throws {
        let loader = CountingLoader()
        let cache = CachedFaviconLoader(loader: loader, notificationCenter: NotificationCenter())
        loader.whileLoading = { cache.clear() }
        _ = try await cache.image(at: Self.link(Self.scanA, exp: 1000))
        #expect(cache.cachedImage(at: Self.link(Self.scanA, exp: 1000)) == nil)
    }

    /// `SiteIcon` shows a hit at once (no grey flash on a list reload); another scan never gets it.
    @Test func cachedImageIsSynchronousAndPerScan() async throws {
        let loader = CountingLoader()
        let cache = CachedFaviconLoader(loader: loader, notificationCenter: NotificationCenter())
        #expect(cache.cachedImage(at: Self.link(Self.scanA, exp: 1000)) == nil)
        let image = try await cache.image(at: Self.link(Self.scanA, exp: 1000))
        #expect(cache.cachedImage(at: Self.link(Self.scanA, exp: 4600)) === image)
        #expect(cache.cachedImage(at: Self.link(Self.scanB, exp: 1000)) == nil)
    }

    /// Another host's `/favicons/<same id>` is a different key: a hit never answers a link the
    /// real loader would refuse.
    @Test func theHostIsPartOfTheKey() async throws {
        let loader = CountingLoader()
        let cache = CachedFaviconLoader(loader: loader, notificationCenter: NotificationCenter())
        _ = try await cache.image(at: Self.link(Self.scanA, exp: 1000))
        #expect(cache.cachedImage(at: Self.link(Self.scanA, exp: 1000, host: "evil.example")) == nil)
    }

    /// Not a favicon link: passed straight to the loader (which refuses it), nothing kept.
    @Test func otherPathsAreNeverCached() async throws {
        let loader = CountingLoader()
        let cache = CachedFaviconLoader(loader: loader, notificationCenter: NotificationCenter())
        let url = try #require(URL(string: "https://api.shoo.test/screenshots/\(Self.scanA)?exp=1"))
        _ = try await cache.image(at: url)
        _ = try await cache.image(at: url)
        #expect(loader.count == 2)
        #expect(cache.cachedImage(at: url) == nil)
    }

    @Test func atMostAHundredEntries() {
        let cache = CachedFaviconLoader(loader: CountingLoader(), notificationCenter: NotificationCenter())
        #expect(cache.countLimit == 100)
    }

    @Test func theAppDefaultIsTheCachedLoader() {
        #expect(EnvironmentValues().faviconLoader is CachedFaviconLoader)
    }
}

/// Fase 22c: which events empty the favicon cache (P13). One counter per store, no shared state.
struct FaviconCacheHookTests {
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var _count = 0
        var count: Int { lock.withLock { _count } }
        func hit() { lock.withLock { _count += 1 } }
        /// After setup: `StubServer` saves a session, which already empties the cache once.
        func reset() { lock.withLock { _count = 0 } }
    }

    private static let ok = HostStubProtocol.Reply.json(200, #"{"ok":true}"#)
    private static let guardian = GuardianInfo(deviceId: "dev_me", name: "Adhella", avatarId: "avatar_01")

    @Test func clearingTheSessionEmptiesIt() {
        let counter = Counter()
        let server = StubServer(token: nil, forgetCachedData: { counter.hit() })
        server.session.clear()
        #expect(counter.count == 1)
    }

    /// A new device (registration, guardian → protected) sees other scans.
    @Test func aNewSessionEmptiesIt() throws {
        let counter = Counter()
        let server = StubServer(token: nil, forgetCachedData: { counter.hit() })
        try server.session.save(DeviceRegistration(deviceId: "dev_new", token: "shoo_t", avatarId: "avatar_05"), name: "Rina", mode: .protected)
        #expect(counter.count == 1)
    }

    @Test func deleteMyDataEmptiesIt() async throws {
        let counter = Counter()
        let server = StubServer(forgetCachedData: { counter.hit() })
        server.reply { _ in Self.ok }
        counter.reset()
        try await server.repository().deleteMe()
        #expect(counter.count == 1)
    }

    @Test func removingAMemberEmptiesIt() async throws {
        let counter = Counter()
        let server = StubServer(forgetCachedData: { counter.hit() })
        server.reply { _ in Self.ok }
        counter.reset()
        try await server.repository().removeMember(deviceId: "dev_mom")
        #expect(counter.count == 1)
    }

    @Test func leavingTheGuardianEmptiesIt() async throws {
        let counter = Counter()
        let server = StubServer(forgetCachedData: { counter.hit() })
        server.session.setGuardian(Self.guardian)
        counter.reset()
        server.reply { _ in Self.ok }
        try await server.repository().leaveGuardian()
        #expect(counter.count == 1)
    }

    /// The guardian removed this phone: `GET /devices/me` comes back without a guardian.
    @Test func losingTheGuardianEmptiesIt() {
        let counter = Counter()
        let server = StubServer(forgetCachedData: { counter.hit() })
        server.session.setGuardian(Self.guardian)
        counter.reset()
        server.session.setGuardian(nil)
        #expect(counter.count == 1)
    }

    /// A guardian's every foreground refresh sets "no guardian" again: the cache stays.
    @Test func noGuardianBeforeAndAfterKeepsIt() {
        let counter = Counter()
        let server = StubServer(forgetCachedData: { counter.hit() })
        counter.reset()
        server.session.setGuardian(nil)
        server.session.setGuardian(nil)
        #expect(counter.count == 0)
    }
}
