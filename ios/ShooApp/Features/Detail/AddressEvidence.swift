import SwiftUI

/// DT-04: the proof for a reason about the **address**, not the page (`lookalike_domain`, `brand_plus_keyword`,
/// `cheap_tld`, `new_domain`, `suspicious_link`, `db_match`). A photo of the page points at nothing for these,
/// so the card shows the address the way Safari does, with the suspicious part marked, and one line that says
/// what is wrong with it.
///
/// Only the scan's `domain` is shown (the registrable domain; the full host on a shared platform such as
/// `sites.google.com`, #495), as in the link pill (BH-13): a deceiving subdomain
/// (`klikbca.co.id.secure-login.<domain>`) never gets a second, bigger stage here.
/// Which part to mark: the parts the detector names in `host.marks` (#497). Without them, `cheap_tld` marks the
/// ending and every other reason the whole domain. When the detector names the brand's real address
/// (`host.official`), a line under the note shows it.
struct AddressEvidence: View {
    let domain: String
    let kind: SignalKind
    /// The reason in the viewer's words (`label` or `labelSimple`): the age of a new domain is read from it.
    let reasonText: String
    /// The signal's `host` (#497): which parts to mark and the brand's real address. nil = today's marks.
    var host: Signal.Host?

    static let height: CGFloat = 132

    var body: some View {
        let panel = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(spacing: 14) {
            addressBar
            VStack(spacing: 4) {
                note
                if let official = Self.official(in: host, kind: kind) {
                    officialLine(official)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        // At least the photo card's height; larger text or the real-address line may need more.
        .frame(minHeight: Self.height)
        .background(DetailStyle.photoFill)
        .clipShape(panel)
        .overlay(panel.stroke(DetailStyle.photoStroke))
        .accessibilityElement(children: .combine)
    }

    /// Safari's address field: a white capsule with the domain, the marked part on the marker yellow.
    private var addressBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DetailStyle.secondary)
                .accessibilityHidden(true)
            Text(Self.marked(domain, ranges: Self.markedRanges(in: domain, kind: kind, marks: host?.marks)))
                .activityFont(17)
                .foregroundStyle(DetailStyle.title)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // Never cut the end: for a cheap ending, the ending is the proof.
                .truncationMode(.head)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(.white, in: Capsule())
        .shadow(color: DetailStyle.pageShadow.opacity(0.08), radius: 7.5, y: 4.3)
    }

    private var note: some View {
        HStack(spacing: 6) {
            Image(systemName: Self.symbol(for: kind))
                .font(.system(size: 14, weight: .semibold))
                .accessibilityHidden(true)
            noteText
                .activityFont(15)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(DetailStyle.secondary)
        .multilineTextAlignment(.center)
    }

    /// "Real: bca.co.id": the address the scam copies, from the detector's brand list (public data).
    private func officialLine(_ official: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 14, weight: .semibold))
                .accessibilityHidden(true)
            Text("Real: \(official)")
                .activityFont(15, .semibold)
                .lineLimit(2)
                // Keep both ends of a long address readable; the middle goes first.
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(DetailStyle.title)
        .accessibilityIdentifier("detail.address.official")
    }

    @ViewBuilder
    private var noteText: some View {
        switch kind {
        case .newDomain:
            if let days = Self.days(in: reasonText) {
                days == 1 ? Text("Address is 1 day old") : Text("Address is \(days) days old")
            } else {
                Text("Address made recently")
            }
        case .knownScam: Text("On a scam list")
        case .cheapEnding: Text("Cheap ending often used by scam sites")
        case .lookalikeDomain: Text("Not the brand's official address")
        case .brandInAddress: Text("Brand name with extra words")
        case .suspiciousLink: Text("The link itself looks like a scam link")
        default: Text("Something is off with this address")
        }
    }

    static func symbol(for kind: SignalKind) -> String {
        switch kind {
        case .newDomain: "calendar"
        case .knownScam: "xmark.shield"
        case .cheapEnding: "tag"
        case .lookalikeDomain, .brandInAddress: "textformat.abc"
        case .suspiciousLink: "link"
        default: "exclamationmark.circle"
        }
    }

    /// Parts of `domain` to mark: the detector's `marks` that are in it (#497). When none is, today's marks:
    /// `cheap_tld` the last label with its dot (`.site`), everything else all of it.
    static func markedRanges(in domain: String, kind: SignalKind, marks: [String]? = nil) -> [Range<String.Index>] {
        guard !domain.isEmpty else { return [] }
        let found = ranges(of: marks ?? [], in: domain)
        if !found.isEmpty { return found }
        if kind == .cheapEnding, let dot = domain.lastIndex(of: "."), domain.index(after: dot) < domain.endIndex {
            return [dot..<domain.endIndex]
        }
        return [domain.startIndex..<domain.endIndex]
    }

    /// Where each mark reads in `domain`, ignoring case, in domain order. Only the first 4 marks count (the
    /// contract's limit). Marks come in reading order, so each one is looked for after the previous; one that is
    /// not there is looked for from the start (without moving the search back), and one not found at all is left
    /// out. Overlapping or touching parts join into one, so a duplicate mark marks its part once.
    static func ranges(of marks: [String], in domain: String) -> [Range<String.Index>] {
        let options: String.CompareOptions = [.caseInsensitive, .literal]
        var found: [Range<String.Index>] = []
        var cursor = domain.startIndex
        for mark in marks.prefix(4) where !mark.isEmpty {
            guard let range = domain.range(of: mark, options: options, range: cursor..<domain.endIndex)
                ?? domain.range(of: mark, options: options)
            else { continue }
            found.append(range)
            cursor = max(cursor, range.upperBound)
        }
        var joined: [Range<String.Index>] = []
        for range in found.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = joined.last, range.lowerBound <= last.upperBound {
                joined[joined.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                joined.append(range)
            }
        }
        return joined
    }

    /// The brand's real address to show, or nil when the detector names none. Only brand reasons
    /// (`lookalike_domain`, `brand_plus_keyword`) have one in the contract.
    static func official(in host: Signal.Host?, kind: SignalKind) -> String? {
        guard kind == .lookalikeDomain || kind == .brandInAddress,
              let official = host?.official?.trimmingCharacters(in: .whitespacesAndNewlines), !official.isEmpty
        else { return nil }
        return official
    }

    /// The domain with `ranges` on the marker yellow, bold; the rest regular.
    static func marked(_ domain: String, ranges: [Range<String.Index>]) -> AttributedString {
        var text = AttributedString(domain)
        for range in ranges {
            guard let lower = AttributedString.Index(range.lowerBound, within: text),
                  let upper = AttributedString.Index(range.upperBound, within: text)
            else { continue }
            text[lower..<upper].backgroundColor = DetailStyle.marker
            text[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        }
        return text
    }

    /// The first whole number in the reason ("Domain age 3 days", "Situs ini baru dibuat 3 hari lalu"),
    /// or `nil`: the label is the only place the age reaches the app (`rdapRegisteredAt` is request-only, #270).
    static func days(in text: String) -> Int? {
        guard let match = text.firstMatch(of: /\d{1,5}/) else { return nil }
        return Int(match.output)
    }
}

extension SignalKind {
    /// DT-04: reasons about the address; their card shows `AddressEvidence` instead of the page.
    var isAddress: Bool {
        switch self {
        case .lookalikeDomain, .brandInAddress, .cheapEnding, .suspiciousLink, .newDomain, .knownScam: true
        default: false
        }
    }
}

#Preview("Address reasons") {
    ScrollView {
        VStack(spacing: 12) {
            AddressEvidence(domain: "bca-verifikasi.site", kind: .newDomain, reasonText: "Domain age 3 days")
            AddressEvidence(domain: "bca-verifikasi.site", kind: .cheapEnding, reasonText: "Cheap ending .site")
            AddressEvidence(domain: "p0stindonesia.com", kind: .knownScam, reasonText: "Verified scam")
            AddressEvidence(domain: "lphone-login.com", kind: .lookalikeDomain, reasonText: "Spelled like Apple")
            AddressEvidence(domain: "bca-verifikasi.site", kind: .brandInAddress, reasonText: "BCA name with extra words",
                            host: Signal.Host(marks: ["bca", "verifikasi"], official: "bca.co.id"))
        }
        .padding()
    }
}
