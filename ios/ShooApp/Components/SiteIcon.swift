import SwiftUI
import UIKit

/// Loads the favicon behind `faviconUrl`.
protocol FaviconLoading: Sendable {
    func image(at url: URL) async throws -> UIImage
    /// An image already in memory for this link, without waiting (no grey flash on a list reload).
    func cachedImage(at url: URL) -> UIImage?
}

extension FaviconLoading {
    func cachedImage(at url: URL) -> UIImage? { nil }
}

enum FaviconLoadError: Error, Equatable {
    /// Not our Worker's link, gone, expired, too big or not an image.
    case unavailable
}

/// SECURITY §3 P9 (D-alief-A41): the app never contacts the scanned site. `faviconUrl` is a signed,
/// short-lived link to our own Worker, which serves the favicon the backend downloaded once and
/// stores with the scan (deleted with it). Loaded like screenshots: ephemeral session, no URL cache,
/// no cookies, no `Authorization` header, redirects refused, image kept in memory only.
struct URLSessionFaviconLoader: FaviconLoading {
    /// Favicons are small; anything bigger is not one of ours.
    static let maxBytes = 64 * 1024
    /// Stops decompression bombs; real favicons are ≤ 256 px.
    static let maxPixelSide = 512
    static let shared = URLSessionFaviconLoader(configuration: URLSessionScreenshotLoader.configuration())

    private let session: URLSession
    private let allowedHost: String?

    init(configuration: URLSessionConfiguration, allowedHost: String? = AppConfig.apiBaseURL.host()) {
        session = URLSession(configuration: configuration, delegate: RedirectRefuser(), delegateQueue: nil)
        self.allowedHost = allowedHost
    }

    func image(at url: URL) async throws -> UIImage {
        guard Self.isAllowed(url, host: allowedHost) else { throw FaviconLoadError.unavailable }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError where error.code != .cancelled {
            throw FaviconLoadError.unavailable
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              data.count <= Self.maxBytes,
              ScreenshotDecoder.hasSafeDimensions(data, maxSide: Self.maxPixelSide),
              let image = ScreenshotDecoder.image(from: data, maxPixelSize: 144)
        else { throw FaviconLoadError.unavailable }
        return image
    }

    /// Our Worker's `/favicons/` path only, over HTTPS (SECURITY §3 P5);
    /// plain HTTP only for the local Worker (`wrangler dev`) in Debug builds.
    static func isAllowed(_ url: URL, host allowedHost: String?) -> Bool {
        guard let host = url.host(), host == allowedHost, url.path().hasPrefix("/favicons/") else { return false }
        if url.scheme == "https" { return true }
        #if DEBUG
        return url.scheme == "http" && ["localhost", "127.0.0.1"].contains(host)
        #else
        return false
        #endif
    }
}

/// Fase 22c (K10 a): `faviconUrl` is signed again on every `GET /scans` (`exp` moves), so without this
/// every list reload downloads every icon again. The key is the host plus the scan id from
/// `/favicons/<id>`, never the signed link with its query.
///
/// SECURITY §3 P9/P13: memory only (`NSCache`, never disk), at most 100 icons, failures not kept.
/// `clear()` runs when data goes (`SessionStore.forgetCachedData`: delete my data, session cleared or
/// expired, a new session, losing the guardian; `ApiRepository.removeMember`; leaving the demo) and on a
/// memory warning. A download that was running during `clear()` is returned but not kept. An icon is
/// kept at most `maxAge` (the lifetime of the signed link, 1 h): after that the Worker is asked again,
/// so a scan that was deleted or a member who left is never shown from the cache past its link.
///
/// `@unchecked Sendable`: `NSCache` is thread-safe, and `generation` is only touched under `lock`.
final class CachedFaviconLoader: FaviconLoading, @unchecked Sendable {
    static let maxEntries = 100
    /// `exp` of a signed favicon link is now + 3600 s (`backend/api/src/services/screenshotLinks.ts`).
    static let maxAge: TimeInterval = 3600
    static let shared = CachedFaviconLoader(loader: URLSessionFaviconLoader.shared)

    private let loader: any FaviconLoading
    private final class Entry {
        let image: UIImage
        let storedAt: Date
        init(image: UIImage, storedAt: Date) { self.image = image; self.storedAt = storedAt }
    }

    private let cache = NSCache<NSString, Entry>()
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    /// Bumped by `clear()`: a download that started before it is not stored.
    private var generation = 0
    private let notificationCenter: NotificationCenter
    private var memoryWarning: (any NSObjectProtocol)?

    init(
        loader: any FaviconLoading,
        countLimit: Int = maxEntries,
        notificationCenter: NotificationCenter = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.loader = loader
        self.now = now
        self.notificationCenter = notificationCenter
        cache.countLimit = countLimit
        memoryWarning = notificationCenter.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.clear() }
    }

    deinit {
        if let memoryWarning { notificationCenter.removeObserver(memoryWarning) }
    }

    var countLimit: Int { cache.countLimit }

    func image(at url: URL) async throws -> UIImage {
        // Not a favicon link: the loader decides (it refuses it), nothing is kept.
        guard let key = Self.key(for: url) else { return try await loader.image(at: url) }
        if let hit = fresh(key) { return hit }
        let started = lock.withLock { generation }
        let image = try await loader.image(at: url)
        lock.withLock {
            if generation == started { cache.setObject(Entry(image: image, storedAt: now()), forKey: key) }
        }
        return image
    }

    func cachedImage(at url: URL) -> UIImage? {
        Self.key(for: url).flatMap(fresh)
    }

    /// The stored icon while it is younger than `maxAge`; an older one is dropped.
    private func fresh(_ key: NSString) -> UIImage? {
        guard let entry = cache.object(forKey: key) else { return nil }
        guard now().timeIntervalSince(entry.storedAt) < Self.maxAge else {
            cache.removeObject(forKey: key)
            return nil
        }
        return entry.image
    }

    func clear() {
        lock.withLock {
            generation += 1
            cache.removeAllObjects()
        }
    }

    /// `host[:port]/<id>` for `https://host/favicons/<id>?v=…&exp=…&sig=…`; `nil` for any other path.
    /// The host is lowercased and the port kept, so two local Workers never share an entry.
    static func key(for url: URL) -> NSString? {
        let prefix = "/favicons/"
        let path = url.path(percentEncoded: true)
        guard let host = url.host()?.lowercased(), path.hasPrefix(prefix) else { return nil }
        let id = path.dropFirst(prefix.count)
        guard !id.isEmpty, !id.contains("/") else { return nil }
        let origin = url.port.map { "\(host):\($0)" } ?? host
        return "\(origin)/\(id)" as NSString
    }

    /// Same scan on the same Worker: only the signature differs.
    static func sameFavicon(_ a: URL, _ b: URL) -> Bool {
        guard let ka = key(for: a), let kb = key(for: b) else { return a == b }
        return ka == kb
    }
}

extension EnvironmentValues {
    @Entry var faviconLoader: any FaviconLoading = CachedFaviconLoader.shared
}

/// A site's favicon in a 48 pt circle (Figma "Update card" icon). No link, still loading, or failed:
/// the empty grey circle, exactly as Figma draws it.
struct SiteIcon: View {
    let url: URL?
    var size: CGFloat = 48

    @Environment(\.faviconLoader) private var loader
    /// The image together with the link it was loaded for: a row that now shows another link never
    /// keeps the old icon.
    @State private var loaded: (url: URL, image: UIImage)?

    /// The loaded image for this scan's link (also after a reload signed it again), else a cache hit:
    /// shown in the first frame, without the grey flash.
    private var image: UIImage? {
        guard let url else { return nil }
        if let loaded, CachedFaviconLoader.sameFavicon(loaded.url, url) { return loaded.image }
        return loader.cachedImage(at: url)
    }

    var body: some View {
        Circle()
            .fill(ActivityStyle.iconFill)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.25)
                }
            }
            .overlay(Circle().stroke(ActivityStyle.iconStroke))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .task(id: url) { await load() }
    }

    @MainActor
    private func load() async {
        guard let url else {
            loaded = nil
            return
        }
        if let cached = loader.cachedImage(at: url) {
            loaded = (url, cached)
            return
        }
        // Same scan already on screen (the cache was emptied, e.g. by a memory warning): keep it while
        // the new link loads. Another scan's icon is never shown, see `image`.
        if let loaded, !CachedFaviconLoader.sameFavicon(loaded.url, url) { self.loaded = nil }
        do {
            let image = try await loader.image(at: url)
            // `.task(id:)` cancelled this load for a newer link: that load sets the image.
            guard !Task.isCancelled else { return }
            loaded = (url, image)
        } catch {
            // Grey circle stays; the row still reads fine without the icon.
        }
    }
}

#Preview {
    HStack {
        SiteIcon(url: nil)
        SiteIcon(url: URL(string: "https://example.invalid/favicons/x.png"))
    }
}
