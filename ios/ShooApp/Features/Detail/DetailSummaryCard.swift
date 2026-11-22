import SwiftUI

/// Figma "Ringkasan" (1668:10650, in 1619:6617): a tinted card under the score row with two plain sentences:
/// what the page is, then what happened to it ("Halaman BCA palsu yang meminta PIN kamu. Kami memblokir otomatis
/// halaman ini."). The scan carries no summary text (contracts/scan-result.schema.json) and the LLM only sees
/// scores 30–79, so the sentences are built here from the signals, the status and the guardian's verdict.
struct DetailSummaryCard: View {
    let text: String
    let look: DetailLook

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("detail.summary.title")
                .activityFont(17, .semibold)
                .figmaLineHeight(22, relativeTo: .headline)
                .foregroundStyle(DetailStyle.title)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: text)
                .activityFont(16, rounded: true, tracking: -0.31)
                .figmaLineHeight(21, relativeTo: .callout)
                .foregroundStyle(DetailStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(look.summaryFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail.summary")
    }

    /// "Halaman BCA palsu yang meminta PIN kamu. Kami memblokir otomatis halaman ini." Nil when there is nothing to say.
    static func text(_ scan: ScanResult, language: AppLanguage) -> String? {
        let parts = [finding(scan.signals, language: language), outcome(scan, language: language)]
        let text = parts.compactMap { $0 }.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    /// What the page is, from the strongest facts first: the brand it copies and the data it asks for, a known
    /// scam, else how many warning signs there were.
    static func finding(_ signals: [Signal], language: AppLanguage) -> String? {
        let heaviestFirst = signals.enumerated()
            .sorted { ($0.element.weight, $1.offset) > ($1.element.weight, $0.offset) }
            .map(\.element)
        let brand = heaviestFirst.lazy.compactMap(SummaryBrand.name(of:)).first
        let asked = askedData(heaviestFirst, language: language)
        switch (brand, asked) {
        case let (brand?, asked?):
            return L10n.string("detail.summary.fakeBrandAsks \(brand) \(asked)", language: language)
        case let (brand?, nil):
            return L10n.string("detail.summary.fakeBrand \(brand)", language: language)
        case let (nil, asked?):
            return L10n.string("detail.summary.asks \(asked)", language: language)
        case (nil, nil):
            break
        }
        if signals.contains(where: { $0.id == "db_match" }) {
            return L10n.string("detail.summary.knownScam", language: language)
        }
        switch signals.count {
        case 0: return nil
        case 1: return L10n.string("detail.summary.oneSign", language: language)
        default: return L10n.string("detail.summary.signs \(signals.count)", language: language)
        }
    }

    /// "PIN dan kode OTP": the two heaviest `asks_*` signals, joined the way the language joins a list.
    static func askedData(_ heaviestFirst: [Signal], language: AppLanguage) -> String? {
        var seen = Set<String>()
        let names = heaviestFirst
            .compactMap { askedDataKey[$0.id] }
            .filter { seen.insert($0).inserted }
            .prefix(2)
            .map { L10n.string(String.LocalizationValue($0), language: language) }
        guard !names.isEmpty else { return nil }
        let formatter = ListFormatter()
        formatter.locale = language.locale
        return formatter.string(from: Array(names)) ?? names.joined(separator: ", ")
    }

    /// Layer 3 form signals (contracts/detector-interface.md) and the noun each one asks for.
    static let askedDataKey: [String: String] = [
        "asks_pin": "detail.summary.data.pin",
        "asks_otp": "detail.summary.data.otp",
        "asks_password": "detail.summary.data.password",
        "asks_card": "detail.summary.data.card",
        "asks_cvv": "detail.summary.data.cvv",
        "asks_ktp": "detail.summary.data.ktp",
        "asks_selfie_ktp": "detail.summary.data.selfieKtp",
    ]

    /// What happened to the page, by the same rules as the "Status situs" chip (`DetailView.statusKind`).
    static func outcome(_ scan: ScanResult, language: AppLanguage) -> String {
        switch DetailView.statusKind(scan) {
        case .blocked:
            scan.verdict?.value == .notSafe
                ? L10n.string("detail.summary.confirmedBlocked", language: language)
                : L10n.string("detail.summary.autoBlocked", language: language)
        case .warning:
            L10n.string("detail.summary.warned", language: language)
        case .unblocked, .markedSafe:
            L10n.string("detail.summary.markedSafe", language: language)
        }
    }
}

/// The brand an address signal says the page copies, by its display name ("BCA", "Bank Mandiri").
enum SummaryBrand {
    /// Only `lookalike_domain` and `brand_plus_keyword` name a brand (contracts/detector-interface.md "host"): its
    /// `brand`, else its real domain (`official`, scans from a detector before `brand`). Nothing usable gives nil.
    static func name(of signal: Signal) -> String? {
        guard signal.id == "lookalike_domain" || signal.id == "brand_plus_keyword", let host = signal.host else {
            return nil
        }
        for value in [host.brand, host.official] {
            if let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        }
        return nil
    }
}

extension DetailLook {
    /// Figma "Ringkasan" fill: #E5483B at 6 % on the red frames; the amber frames get the orange of the bar.
    var summaryFill: Color {
        switch self {
        case .danger: DetailStyle.hex(0xE5483B).opacity(0.06)
        case .caution: DetailStyle.hex(0xFF9500).opacity(0.08)
        case .safe: DetailStyle.hex(0x34C759).opacity(0.08)
        }
    }
}
