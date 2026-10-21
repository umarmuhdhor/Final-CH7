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
    static let shared = URLSessionScreenshotLoader(configuration: configuration())

    private let session: URLSession

    init(configuration: URLSessionConfiguration) {
        session = URLSession(configuration: configuration)
    }

    /// Ephemeral session with a memory-only cache.
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 0, directory: nil)
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        return configuration
    }

    func imageData(at url: URL) async throws -> Data {
        guard Self.isAllowed(url) else { throw ScreenshotLoadError.unavailable }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              data.count <= Self.maxBytes,
              UIImage(data: data) != nil
        else { throw ScreenshotLoadError.unavailable }
        return data
    }

    /// HTTPS only (SECURITY §3 P5); the local Worker (`wrangler dev`) in Debug builds.
    private static func isAllowed(_ url: URL) -> Bool {
        if url.scheme == "https" { return true }
        #if DEBUG
        return url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host())
        #else
        return false
        #endif
    }
}

extension EnvironmentValues {
    @Entry var screenshotLoader: any ScreenshotLoading = URLSessionScreenshotLoader.shared
}

/// DT-04: large evidence screenshot, tap to zoom. No share, save or context menu (SECURITY §3 P9).
struct ScreenshotView: View {
    let url: URL

    @Environment(\.screenshotLoader) private var loader
    @State private var image: UIImage?
    @State private var failed = false
    @State private var isZoomed = false

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
            Label("Screenshot isn't available anymore", systemImage: "photo.badge.exclamationmark")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("detail.screenshotUnavailable")
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityLabel(Text("Loading screenshot"))
        }
    }

    private func load() async {
        failed = false
        do {
            let data = try await loader.imageData(at: url)
            image = UIImage(data: data)
            failed = image == nil
        } catch is CancellationError {
            // The view went away.
        } catch {
            Log.ui.error("Screenshot load failed")
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
