import Foundation

/// Build-time configuration (plan/alief/ref/R5 §6). Not in Info.plist: that file is generated
/// from ios/project.yml (lead-owned).
enum AppConfig {
    #if DEBUG && targetEnvironment(simulator)
    /// `wrangler dev` (`pnpm -C backend/api dev`); the simulator reaches the Mac at localhost.
    static let apiBaseURL = URL(string: "http://localhost:8787")!
    #else
    /// Cloudflare Worker deployed from `main` (fase 12, TODO D8). Also Debug builds on a real iPhone,
    /// where localhost is the phone itself.
    static let apiBaseURL = URL(string: "https://shoo-api.afindo-mi01.workers.dev")!
    #endif

    /// Team AI service (`POST /analyze`, `GET /public-blocklist`). `nil` = not written to the App Group,
    /// so the extension skips layer 3–4 instead of sending pages to a placeholder host.
    #if DEBUG
    /// Debug builds (simulator and Xcode installs on an iPhone) stay on layer 1–2, so local testing
    /// never sends pages to the deployed AI Worker (#82).
    static let aiBaseURL: URL? = nil
    #else
    /// AI Worker deployed 23 Oct 2026 (#82); since 3 Nov 2026 on the same account as shoo-api, where
    /// `ai/wrangler.toml` deploys it and public-blocklist.yml publishes its list.
    static let aiBaseURL: URL? = URL(string: "https://shoo-ai.afindo-mi01.workers.dev")!
    #endif

    /// PF-01 Tentang Shoo: share link and support address, always the public ones (also in Debug,
    /// where `apiBaseURL` may be localhost). `/get` redirects to TestFlight or the App Store.
    static let shareURL = URL(string: "https://shoo-api.afindo-mi01.workers.dev/get")!
    static let supportEmail = "Apple.a.day.bali@gmail.com"
    /// App Store id for "Beri nilai di App Store". `nil` until the app is listed: the system review
    /// prompt is asked for instead.
    static let appStoreId: String? = nil

    /// The policy or terms page in the app's language, served by the Worker.
    static func legalPage(_ path: String, language: AppLanguage) -> URL {
        var components = URLComponents(url: apiBaseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "lang", value: language.code)]
        return components.url!
    }

    /// Scan QR (PR-01): `NSCameraUsageDescription` came with C3 (#27). Off = Enter code only.
    static let cameraEnabled = true
}
