import UIKit
import UniformTypeIdentifiers

/// The part of `UIPasteboard` Detail uses, so tests can check the options.
@MainActor
protocol PasteboardWriting: AnyObject {
    func setItems(_ items: [[String: Any]], options: [UIPasteboard.OptionsKey: Any])
}

extension UIPasteboard: PasteboardWriting {}

/// DT-03: the link can be copied, never opened from the app (D-alief-A31).
enum LinkCopy {
    /// Plain text only (no URL type, so nothing offers to open it) and this device only:
    /// no Universal Clipboard to the user's other devices (SECURITY §3 P8).
    @MainActor
    static func copy(_ url: URL, to pasteboard: any PasteboardWriting = UIPasteboard.general) {
        pasteboard.setItems(
            [[UTType.plainText.identifier: url.absoluteString]],
            options: [.localOnly: true]
        )
    }
}
