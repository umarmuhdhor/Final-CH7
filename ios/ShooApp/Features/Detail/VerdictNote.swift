import Foundation

/// DT-06: who decided. "by you" when the viewer decided (PRD §5 Validasi).
enum VerdictNote {
    /// One line for VoiceOver and the header value: "Verified scam by Adhella".
    static func text(for verdict: Verdict, viewerDeviceId: String?, language: AppLanguage) -> String {
        let name = verdict.byName
        switch (verdict.value, verdict.byDeviceId == viewerDeviceId) {
        case (.notSafe, true): return L10n.string("Verified scam by you", language: language)
        case (.safe, true): return L10n.string("Marked safe by you", language: language)
        case (.notSafe, false): return L10n.string("Verified scam by \(name)", language: language)
        case (.safe, false): return L10n.string("Marked safe by \(name)", language: language)
        }
    }

    /// Under the card title (Figma "oleh Adhella · Baru saja").
    static func byline(for verdict: Verdict, viewerDeviceId: String?, now: Date = Date(), language: AppLanguage) -> String {
        let when = now.timeIntervalSince(verdict.decidedAt) < 60
            ? L10n.string("Just now", language: language)
            : Formatters.relative(verdict.decidedAt, now: now, language: language)
        return verdict.byDeviceId == viewerDeviceId
            ? L10n.string("by you · \(when)", language: language)
            : L10n.string("by \(verdict.byName) · \(when)", language: language)
    }

    /// The chip under a safe item's badge (Figma "Anda menandai ini aman").
    static func markedSafeChip(for verdict: Verdict, viewerDeviceId: String?, language: AppLanguage) -> String {
        verdict.byDeviceId == viewerDeviceId
            ? L10n.string("You marked this safe", language: language)
            : L10n.string("Marked safe by \(verdict.byName)", language: language)
    }
}
