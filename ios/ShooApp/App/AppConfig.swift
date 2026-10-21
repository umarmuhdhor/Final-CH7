import Foundation

/// Build-time configuration (plan/alief/ref/R5 §6). Not in Info.plist: that file is generated
/// from ios/project.yml (lead-owned).
enum AppConfig {
    #if DEBUG
    static let apiBaseURL = URL(string: "http://localhost:8787")!
    #else
    // TODO(sync:alief): Worker cloud URL — replace after fase 12 deploy
    static let apiBaseURL = URL(string: "https://shoo-api.example.workers.dev")!
    #endif

    /// Scan QR (PR-01) needs `NSCameraUsageDescription` from the lead (TODO C3).
    static let cameraEnabled = false
    /// "Delete my data" (SECURITY §3 P3) needs `DELETE /devices/me` in contracts (TODO C19).
    static let dataDeletionEnabled = false
}
