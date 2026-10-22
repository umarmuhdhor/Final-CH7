import ImageIO
import SwiftUI
import UIKit

enum ScreenshotLoadError: Error, Equatable {
    /// Gone (deleted, retention, disconnected: the Worker answers 404), expired, or not an image.
    case unavailable
}

/// Loads the evidence screenshot behind `screenshotUrl`.
protocol ScreenshotLoading: Sendable {
    func imageData(at url: URL) async throws -> Data
}

/// SECURITY §3 P9 + P13: the screenshot lives in memory only.
/// `screenshotUrl` is a short-lived Worker link re-checked on every request (D-alief-B08), so it is
/// loaded as-is: no `Authorization` header, no cookies, nothing written to disk.
struct URLSessionScreenshotLoader: ScreenshotLoading {
    /// The backend keeps screenshots ≤ 150 KB (contracts/api.md); anything far bigger is not ours.
    static let maxBytes = 2 * 1024 * 1024
    /// Larger than any real screenshot (≤ 1280 px, contracts/api.md); stops decompression bombs.
    static let maxPixelSide = 4096
    static let shared = URLSessionScreenshotLoader(configuration: configuration())

    private let session: URLSession
    /// `screenshotUrl` always points at our Worker (D-alief-B08); nothing else is fetched.
    private let allowedHost: String?

    init(configuration: URLSessionConfiguration, allowedHost: String? = AppConfig.apiBaseURL.host()) {
        session = URLSession(configuration: configuration, delegate: RedirectRefuser(), delegateQueue: nil)
        self.allowedHost = allowedHost
    }

    /// Ephemeral session without any URL cache: the image exists only while the Detail view holds it,
    /// and every view asks the Worker again, which re-checks access (P13).
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        return configuration
    }

    func imageData(at url: URL) async throws -> Data {
        guard isAllowed(url) else { throw ScreenshotLoadError.unavailable }
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(from: url)
        } catch let error as URLError where error.code != .cancelled {
            // Offline, TLS failure, refused redirect: all mean "no screenshot" to the screen.
            throw ScreenshotLoadError.unavailable
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              response.expectedContentLength <= Int64(Self.maxBytes)
        else { throw ScreenshotLoadError.unavailable }
        // Stop reading as soon as the body is bigger than any real screenshot.
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > Self.maxBytes { throw ScreenshotLoadError.unavailable }
        }
        guard ScreenshotDecoder.hasSafeDimensions(data, maxSide: Self.maxPixelSide) else {
            throw ScreenshotLoadError.unavailable
        }
        return data
    }

    /// Our Worker's `/screenshots/` path only, over HTTPS (SECURITY §3 P5);
    /// plain HTTP only for the local Worker (`wrangler dev`) in Debug builds.
    private func isAllowed(_ url: URL) -> Bool {
        guard let host = url.host(), host == allowedHost, url.path().hasPrefix("/screenshots/") else { return false }
        if url.scheme == "https" { return true }
        #if DEBUG
        return url.scheme == "http" && ["localhost", "127.0.0.1"].contains(host)
        #else
        return false
        #endif
    }
}

/// The Worker never redirects screenshots; a redirect would leave our origin, so it is not followed.
private final class RedirectRefuser: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

/// Decodes untrusted image bytes without ever building a full-size bitmap.
enum ScreenshotDecoder {
    /// Reads only the header: a few-KB file can claim 30000 × 30000 px.
    static func hasSafeDimensions(_ data: Data, maxSide: Int) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return false }
        return width > 0 && height > 0 && width <= maxSide && height <= maxSide
    }

    /// Downsampled once, at load time, so the view and the zoom screen share one small bitmap.
    static func image(from data: Data, maxPixelSize: Int = 2048) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

extension EnvironmentValues {
    @Entry var screenshotLoader: any ScreenshotLoading = URLSessionScreenshotLoader.shared
}

/// DT-04: large evidence screenshot, tap to zoom. No share, save or context menu (SECURITY §3 P9).
struct ScreenshotView: View {
    let url: URL
    /// Asked once when the link fails: `true` = a fresh `url` is on its way (the old one had expired).
    var refreshLink: (() async -> Bool)?

    @Environment(\.screenshotLoader) private var loader
    @State private var image: UIImage?
    @State private var failed = false
    @State private var isZoomed = false
    @State private var askedForFreshLink = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screenshot")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .task(id: url) { await load() }
        .fullScreenCover(isPresented: $isZoomed) {
            if let image { ZoomedScreenshot(image: image) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Button {
                isZoomed = true
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Screenshot of the page"))
            .accessibilityAddTraits(.isImage)
            .accessibilityHint(Text("Opens a larger view"))
            .accessibilityIdentifier("detail.screenshot")
        } else if failed {
            VStack(alignment: .leading, spacing: 8) {
                Label("Screenshot isn't available anymore", systemImage: "photo.badge.exclamationmark")
                    .font(.subheadline)
                    .accessibilityIdentifier("detail.screenshotUnavailable")
                Button("Try again") {
                    Task { await load() }
                }
                .frame(minHeight: 44)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityLabel(Text("Loading screenshot"))
        }
    }

    private func load() async {
        image = nil
        failed = false
        do {
            let data = try await loader.imageData(at: url)
            image = ScreenshotDecoder.image(from: data)
            failed = image == nil
        } catch is CancellationError {
            // The view went away.
        } catch {
            Log.ui.error("Screenshot load failed")
            if let refreshLink, !askedForFreshLink {
                askedForFreshLink = true
                // A new link restarts `.task(id: url)`.
                if await refreshLink() { return }
            }
            failed = true
        }
    }
}

/// Full-screen screenshot: pinch or double-tap to zoom, drag when zoomed.
private struct ZoomedScreenshot: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    private static let maxScale: CGFloat = 5
    private static let doubleTapScale: CGFloat = 2.5

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            GeometryReader { proxy in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnify(in: proxy.size).simultaneously(with: drag(in: proxy.size)))
                    .onTapGesture(count: 2) { toggleZoom() }
                    .accessibilityLabel(Text("Screenshot of the page"))
                    .accessibilityAddTraits(.isImage)
                    .accessibilityAction(named: scale > 1 ? Text("Zoom out") : Text("Zoom in")) { toggleZoom() }
                    .accessibilityIdentifier("detail.screenshotZoomed")
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .white.opacity(0.3))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding()
            .accessibilityLabel(Text("Close"))
            .accessibilitySortPriority(1)
            .accessibilityIdentifier("detail.screenshotClose")
        }
        // VoiceOver two-finger scrub closes it like any modal.
        .accessibilityAction(.escape) { dismiss() }
        .privacyCover()
    }

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { scale = min(max(baseScale * $0.magnification, 1), Self.maxScale) }
            .onEnded { _ in
                baseScale = scale
                offset = clamped(offset, in: size)
                baseOffset = offset
            }
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = clamped(CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                ), in: size)
            }
            .onEnded { _ in baseOffset = offset }
    }

    /// Keeps the zoomed image covering the screen: it can't be dragged off.
    private func clamped(_ offset: CGSize, in size: CGSize) -> CGSize {
        let maxX = size.width * (scale - 1) / 2
        let maxY = size.height * (scale - 1) / 2
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
    }

    private func toggleZoom() {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) {
            scale = scale > 1 ? 1 : Self.doubleTapScale
            baseScale = scale
            offset = .zero
            baseOffset = .zero
        }
    }
}

#if DEBUG
/// Fixture screenshot URLs point at `example.invalid`, which never resolves. With `MockRepository`
/// the Detail screen draws a stand-in page instead, so previews and the UI gate show the block.
struct FixtureScreenshotLoader: ScreenshotLoading {
    func imageData(at url: URL) async throws -> Data {
        let size = CGSize(width: 390, height: 520)
        return UIGraphicsImageRenderer(size: size).pngData { context in
            UIColor.systemGray6.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: 64))
            let title = url.lastPathComponent as NSString
            title.draw(at: CGPoint(x: 20, y: 22), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 18), .foregroundColor: UIColor.white,
            ])
            // Blurred inputs, as the extension sends them (contracts/api.md).
            for row in 0..<3 {
                let field = CGRect(x: 20, y: 120 + CGFloat(row) * 90, width: size.width - 40, height: 52)
                UIColor.systemGray3.setFill()
                UIBezierPath(roundedRect: field, cornerRadius: 8).fill()
            }
            UIColor.systemRed.setStroke()
            let highlight = UIBezierPath(roundedRect: CGRect(x: 16, y: 116, width: size.width - 32, height: 60), cornerRadius: 10)
            highlight.lineWidth = 3
            highlight.stroke()
        }
    }
}
#endif
