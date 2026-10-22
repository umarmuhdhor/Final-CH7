import Foundation
import SafariServices
import os.log

/// Answers `browser.runtime.sendNativeMessage` from the extension's background script.
/// Message types: contracts/app-group-keys.md.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let log = Logger(subsystem: "com.shoo.app.extension", category: "native")

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        let type = message?["type"] as? String

        let reply: [String: Any]
        switch type {
        case "heartbeat":
            AppGroup.defaults.set(Date(), forKey: AppGroup.Key.extensionLastSeenAt)
            // Missing when the extension can't tell (no permissions API): keep the last known value.
            if let allSites = message?["allSites"] as? Bool {
                AppGroup.defaults.set(allSites, forKey: AppGroup.Key.extensionAllSites)
            }
            reply = ["ok": true]
        case "getSession":
            reply = sessionReply()
        default:
            log.error("Unknown native message type: \(type ?? "nil", privacy: .public)")
            reply = ["ok": false, "error": "unknown_type"]
        }

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    private func sessionReply() -> [String: Any] {
        let defaults = AppGroup.defaults
        guard
            let deviceId = defaults.string(forKey: AppGroup.Key.deviceId),
            let token = defaults.string(forKey: AppGroup.Key.deviceToken),
            let mode = defaults.string(forKey: AppGroup.Key.deviceMode)
        else {
            return ["ok": false, "error": "not_onboarded"]
        }
        return [
            "ok": true,
            "deviceId": deviceId,
            "token": token,
            "mode": mode,
            "name": defaults.string(forKey: AppGroup.Key.deviceName) ?? "",
            "guardianName": defaults.string(forKey: AppGroup.Key.guardianName) ?? NSNull(),
            "apiBaseURL": defaults.string(forKey: AppGroup.Key.apiBaseURL) ?? NSNull(),
            "aiBaseURL": defaults.string(forKey: AppGroup.Key.aiBaseURL) ?? NSNull(),
        ]
    }
}
