import SwiftUI
import UIKit

/// Loads the favicon behind `faviconUrl`.
protocol FaviconLoading: Sendable {
    func image(at url: URL) async throws -> UIImage
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

extension EnvironmentValues {
    @Entry var faviconLoader: any FaviconLoading = URLSessionFaviconLoader.shared
}

/// A site's favicon in a 48 pt circle (Figma "Update card" icon). No link, still loading, or failed:
/// the empty grey circle, exactly as Figma draws it.
struct SiteIcon: View {
    let url: URL?
    var size: CGFloat = 48

    @Environment(\.faviconLoader) private var loader
    @State private var image: UIImage?

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

    private func load() async {
        image = nil
        guard let url else { return }
        do {
            image = try await loader.image(at: url)
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
