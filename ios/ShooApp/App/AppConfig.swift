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
    // TODO(sync:imelda): AI service URL — replace after the ai/ service is deployed
    static let aiBaseURL: URL? = nil

    /// Scan QR (PR-01): `NSCameraUsageDescription` came with C3 (#27). Off = Enter code only.
    static let cameraEnabled = true
}
