import Foundation
import Observation
import UIKit

/// Invite links pasted by the user (PR-03, fase 26). Nothing here reads the pasteboard: it only parses
/// text the user already put in the app.
enum InvitePaste {
    /// U6: the code of the first of our invite links (`https://<invite host>/j/<6 digits>`) in a pasted
    /// text, such as the link alone or the whole invite message. `nil` when there is none, so the code
    /// field falls back to its digit filter, as before U6 (also for a link that isn't ours). Lenient on
    /// purpose: the result only fills the field, joining still needs the Connect tap (T11).
    static func code(inText text: String) -> String? {
        for token in text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            // A link is under 100 characters; a much longer token is not ours.
            guard token.utf8.count <= maxLength else { continue }
            // "Link:https://…" or "[x](https://…)": the link starts at its scheme, not at the token.
            let start = token.range(of: "https://", options: .caseInsensitive)?.lowerBound
                ?? token.range(of: "http://", options: .caseInsensitive)?.lowerBound ?? token.startIndex
            let trimmed = token[start...].trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            guard let url = URL(string: trimmed), isInviteLink(url), case .join(let code) = DeepLink(url: url) else { continue }
            return code
        }
        return nil
    }

    /// The Paste card (fase 26, K4): strict. The whole pasted content must be one invite link and nothing
    /// else, as the invite page copies it (`navigator.clipboard.writeText`). A message with a link in it,
    /// a bare code, `shoo://`, a query, fragment, user or port are refused: the code field still takes those.
    static func code(from items: [String]) -> String? {
        guard items.count == 1 else { return nil }
        let text = items[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= maxLength, !text.contains(where: \.isWhitespace),
              let url = URL(string: text), isInviteLink(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.query == nil, components.fragment == nil,
              // The page never copies a user, password or port; only the local Worker has a port.
              components.user == nil, components.password == nil,
              components.port == nil || DeepLink.isLocalWorker(url),
              case .join(let code) = DeepLink(url: url)
        else { return nil }
        return code
    }

    static let maxLength = 512

    /// Only the `/j/<code>` page link: `https`, or `http` to the local Worker in Debug. Not `shoo://`.
    private static func isInviteLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" || DeepLink.isLocalWorker(url)
    }
}

/// What the app may know about the pasteboard without the "Allow Paste" prompt (SECURITY §3 P8): the
/// change count and whether it probably holds a web address. Its content is only read through the
/// system `PasteButton`, which the user taps.
protocol InvitePasteboard: AnyObject {
    var changeCount: Int { get }
    /// `nil` when iOS could not tell: asked again on the next refresh.
    func hasProbableWebURL() async -> Bool?
    /// Empties the pasteboard unless something new was copied since `changeCount` (K7). Writing needs no prompt.
    func clear(ifChangeCount changeCount: Int)
}

extension UIPasteboard: InvitePasteboard {
    func hasProbableWebURL() async -> Bool? {
        // Only the kind of content, never the content: iOS shows no banner for this (iOS 15+).
        let patterns = try? await detectedPatterns(for: [\UIPasteboard.DetectedValues.probableWebURL])
        return patterns?.contains(\UIPasteboard.DetectedValues.probableWebURL)
    }

    func clear(ifChangeCount changeCount: Int) {
        guard self.changeCount == changeCount else { return }
        setItems([])
    }
}

/// The invite on the pasteboard (PR-03, fase 26): offers the Paste card when there is probably a link,
/// remembers which code came from a paste, and empties the pasteboard after that code joined (K7).
@MainActor
@Observable
final class InviteClipboard {
    /// U1/U2: show the Paste card. Never set from the content, only from its kind.
    private(set) var offersPaste = false

    @ObservationIgnored private let pasteboard: any InvitePasteboard
    /// The change count already checked: the same pasteboard is not asked twice (K3). Observed, so a view
    /// can drop a "not an invite" message once something new is copied.
    private(set) var checkedChangeCount: Int?
    @ObservationIgnored private var pasted: (code: String, changeCount: Int)?

    /// Nonisolated: `AppEnvironment` makes one in a default argument.
    nonisolated init(pasteboard: any InvitePasteboard) {
        self.pasteboard = pasteboard
    }

    /// On appear, back in the foreground, or when the pasteboard changed.
    func refresh() async {
        let count = pasteboard.changeCount
        guard count != checkedChangeCount else { return }
        // Set before asking, so the refreshes that start together ask once.
        checkedChangeCount = count
        let found = await pasteboard.hasProbableWebURL()
        // Something newer was copied while we asked: that answer is for the next refresh.
        guard pasteboard.changeCount == count else { return }
        guard let found else {
            checkedChangeCount = nil
            return
        }
        offersPaste = found
    }

    /// The text the user pasted with the system button. The code when it is our invite link, else `nil`.
    func accept(_ items: [String]) -> String? {
        guard let code = InvitePaste.code(from: items) else {
            Log.ui.info("Invite paste rejected")
            return nil
        }
        Log.ui.info("Invite paste accepted")
        pasted = (code, pasteboard.changeCount)
        offersPaste = false
        return code
    }

    /// After a join: the pasted invite leaves the pasteboard, unless the user copied something else since.
    func joined(code: String) {
        guard let pasted, pasted.code == code else { return }
        pasteboard.clear(ifChangeCount: pasted.changeCount)
        self.pasted = nil
        offersPaste = false
    }
}
