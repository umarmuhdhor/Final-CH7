import Foundation

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

    static let maxLength = 512

    /// Only the `/j/<code>` page link: `https`, or `http` to the local Worker in Debug. Not `shoo://`.
    private static func isInviteLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" || DeepLink.isLocalWorker(url)
    }
}
