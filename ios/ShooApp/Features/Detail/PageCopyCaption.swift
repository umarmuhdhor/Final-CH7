import SwiftUI

/// Where the page copy is on the Detail screen (fase 18b).
enum PageCopyState: Equatable {
    /// The scan has no copy link.
    case none
    /// A scan from the last minute: the Worker may still be storing it (`DetailModel.waitForCopy`).
    case saving
    case loading
    case shown
    /// Gone, expired twice, refused by the lock, or WebKit couldn't draw it.
    case unavailable
    /// 429 from `GET /replicas/:id`.
    case rateLimited
}

/// One line above the evidence cards: "Copy of the page · Today 10.42 WIB", "Copied from …",
/// "Page cut short", or why there is no copy. Plain text only (K4).
struct PageCopyCaption: View {
    let state: PageCopyState
    let meta: ReplicaMeta?
    let scan: ScanResult
    /// An old build's screenshot is shown instead: no "no copy" line then.
    let hasScreenshot: Bool

    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        let lines = Self.lines(state: state, meta: meta, scan: scan, hasScreenshot: hasScreenshot, language: language)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines, id: \.self) { line in
                    Text(verbatim: line)
                }
            }
            .activityFont(13, tracking: -0.13)
            .foregroundStyle(DetailStyle.secondary)
            .lineLimit(2)
            .truncationMode(.middle)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("detail.pageCopy")
        }
    }

    static func lines(
        state: PageCopyState, meta: ReplicaMeta?, scan: ScanResult, hasScreenshot: Bool,
        language: AppLanguage, now: Date = Date()
    ) -> [String] {
        switch state {
        case .saving:
            return [L10n.string("Saving a copy of the page…", language: language)]
        case .loading:
            return []
        case .rateLimited:
            return [L10n.string("Couldn't show the copy of the page. Try again later.", language: language)]
        case .none, .unavailable:
            return hasScreenshot ? [] : [L10n.string("No copy of this page", language: language)]
        case .shown:
            let captured = ReplicaMeta.capturedAt(meta, detectedAt: scan.detectedAt)
            let when = Formatters.dayAndTime(captured, now: now, language: language)
            var lines = [L10n.string("Copy of the page · \(when)", language: language)]
            if let from = meta?.copiedFrom(scanURL: scan.url, domain: scan.domain) {
                lines.append(L10n.string("Copied from \(from)", language: language))
            }
            if meta?.truncated == true {
                lines.append(L10n.string("Page cut short", language: language))
            }
            return lines
        }
    }
}
