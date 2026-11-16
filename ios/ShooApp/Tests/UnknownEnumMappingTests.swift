import Foundation
import SwiftUI
import Testing
@testable import Shoo

/// #493 part 2: a scan status or verdict value this build does not know decodes to `.unknown` (ShooShared, #543).
/// Every screen that switches on them must show it no safer than a warning: an unknown status looks like a
/// warning, an unknown verdict like no verdict yet (the detection status shows), and neither ever reads "safe".
@MainActor
struct UnknownEnumMappingTests {
    /// A scan as the server sends it, with any `status` and an optional verdict `value` string.
    private func scan(status: String, verdict: String? = nil, by deviceId: String = "dev_me",
                      detectedAt: String = "2026-10-21T04:05:00Z") throws -> ScanResult {
        let verdictJSON = verdict.map {
            #","verdict":{"value":"\#($0)","byDeviceId":"\#(deviceId)","byName":"Virellia","decidedAt":"2026-10-21T05:00:00Z"}"#
        } ?? ""
        let json = #"""
        {"id":"s493","url":"https://promo-shopee88.xyz/","domain":"promo-shopee88.xyz","score":70,"status":"\#(status)",
         "signals":[],"ownerDeviceId":"dev_mom","ownerName":"Mom","detectedAt":"\#(detectedAt)"\#(verdictJSON)}
        """#
        return try JSONDecoder.shoo.decode(ScanResult.self, from: Data(json.utf8))
    }

    @Test func newWireValuesDecodeToUnknown() throws {
        let decoded = try scan(status: "reviewing", verdict: "maybe")
        #expect(decoded.status == .unknown)
        #expect(decoded.verdict?.value == .unknown)
    }

    // MARK: 1. ScanBadge (Activity rows, Detail chips)

    @Test(arguments: [
        ("reviewing", nil, ScanBadge.warning),
        ("reviewing", "maybe", .warning),
        ("warning", "maybe", .warning),
        ("blocked", "maybe", .blocked),
    ] as [(String, String?, ScanBadge)])
    func badgeShowsUnknownAsNoSaferThanAWarning(status: String, verdict: String?, expected: ScanBadge) throws {
        #expect(ScanBadge(scan: try scan(status: status, verdict: verdict)) == expected)
    }

    @Test func familyCardBadgeShowsAnUnknownStatusAsAWarning() {
        #expect(ScanBadge(status: .unknown) == .warning)
    }

    // MARK: 2. DetailLook (Detail hero)

    @Test(arguments: [
        ("reviewing", nil, DetailLook.caution),
        ("warning", "maybe", .caution),
        ("blocked", "maybe", .danger),
    ] as [(String, String?, DetailLook)])
    func detailLookFollowsTheStatusForAnUnknownVerdict(status: String, verdict: String?, expected: DetailLook) throws {
        #expect(DetailLook(scan: try scan(status: status, verdict: verdict)) == expected)
    }

    // MARK: 3. DetailView.statusKind ("Status situs" chip)

    @Test(arguments: [
        ("reviewing", nil, DetailStatusChip.Kind.warning),
        ("warning", "maybe", .warning),
        ("blocked", "maybe", .blocked),
    ] as [(String, String?, DetailStatusChip.Kind)])
    func statusChipIsNeverMarkedSafeForUnknown(status: String, verdict: String?, expected: DetailStatusChip.Kind) throws {
        #expect(DetailView.statusKind(try scan(status: status, verdict: verdict)) == expected)
    }

    // MARK: 4. DetailView.title

    @Test(arguments: [
        ("reviewing", nil, "detail.title.suspicious"),
        ("warning", "maybe", "detail.title.suspicious"),
        ("blocked", "maybe", "detail.title.dangerous"),
    ] as [(String, String?, String)])
    func titleIsSuspiciousOrDangerousForUnknown(status: String, verdict: String?, key: String) throws {
        let viewer = MockRepository.guardianProfile
        for language in [AppLanguage.english, .indonesian] {
            let title = DetailView.title(try scan(status: status, verdict: verdict), viewer: viewer, language: language)
            #expect(title == L10n.string(String.LocalizationValue(key), language: language))
        }
    }

    // MARK: 5. VerdictNote (Detail header value)

    @Test func unknownVerdictNoteSaysCheckedNeverSafe() throws {
        let theirs = try #require(try scan(status: "blocked", verdict: "maybe", by: "dev_virellia").verdict)
        let mine = try #require(try scan(status: "blocked", verdict: "maybe", by: "dev_me").verdict)
        #expect(VerdictNote.text(for: theirs, viewerDeviceId: "dev_me", language: .english) == "Checked by Virellia")
        #expect(VerdictNote.text(for: mine, viewerDeviceId: "dev_me", language: .english) == "Checked by you")
        #expect(VerdictNote.text(for: theirs, viewerDeviceId: "dev_me", language: .indonesian) == "Diperiksa oleh Virellia")
        #expect(VerdictNote.text(for: mine, viewerDeviceId: "dev_me", language: .indonesian) == "Diperiksa oleh kamu")
    }

    // MARK: 6. GuardianHomeModel.level (Family Home)

    @Test func pendingScanWithAnUnknownStatusIsAWarningWithButtons() async throws {
        let model = try homeModel(scope: .family, scans: [try scan(status: "reviewing")])
        await model.refresh()
        #expect(model.pendingScan?.status == .unknown)
        #expect(model.level == .warning)
        #expect(model.canDecide)
    }

    /// An unknown verdict counts as not decided: the scan stays the pending card (a warning, with buttons to
    /// decide again) instead of dropping Family Home to normal.
    @Test func scanWithAnUnknownVerdictStaysPending() async throws {
        let model = try homeModel(scope: .family, scans: [try scan(status: "warning", verdict: "maybe", by: "dev_virellia")])
        await model.refresh()
        #expect(model.pendingScan?.id == "s493")
        #expect(model.level == .warning)
        #expect(model.canDecide)
    }

    @Test func personalHomeCountsAnUnknownVerdictAsOpen() async throws {
        let model = try homeModel(scope: .personal, scans: [try scan(status: "blocked", verdict: "maybe", by: "dev_virellia")])
        await model.refresh()
        #expect(model.level == .danger)
    }

    private func homeModel(scope: GuardianHomeModel.Scope, scans: [ScanResult]) throws -> GuardianHomeModel {
        let repository = CountingScansRepository(base: MockRepository(mode: .guardian, latency: .zero))
        repository.pages[""] = ScanPage(items: scans, nextCursor: nil)
        let defaults = try #require(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        return GuardianHomeModel(
            repository: repository, settings: AppSettings(defaults: defaults), scope: scope,
            extensionStatus: { .active(lastSeen: nil) }, now: { GuardianHomeModelTests.fixtureNow }
        )
    }

    // MARK: 7. ProtectedShieldView card (via `Verdict.known`)

    /// The card's `decision` is `scan.verdict?.known?.value`: nil for an unknown verdict, so its footer says
    /// "will check it again" and its colour follows the status, never the blue "safe" check.
    @Test func unknownVerdictIsNotAKnownDecision() throws {
        #expect(try scan(status: "blocked", verdict: "maybe").verdict?.known == nil)
        let safe = try #require(try scan(status: "blocked", verdict: "safe").verdict)
        #expect(safe.known == safe)
        let notSafe = try #require(try scan(status: "blocked", verdict: "not_safe").verdict)
        #expect(notSafe.known == notSafe)
    }

    // MARK: Not compile errors, but read an unknown verdict as "safe" before #543

    @Test func activityRowWithAnUnknownVerdictHasNoNote() throws {
        let blocked = try scan(status: "blocked", verdict: "maybe", by: "dev_virellia")
        #expect(ActivityNote(scan: blocked, guardianName: "Virellia", viewerDeviceId: "dev_mom") == nil)
        let warning = try scan(status: "warning", verdict: "maybe", by: "dev_virellia")
        #expect(ActivityNote(scan: warning, guardianName: "Virellia", viewerDeviceId: "dev_mom") == nil)
    }

    @Test func detailFooterTreatsAnUnknownVerdictAsUndecided() throws {
        let verdict = try scan(status: "blocked", verdict: "maybe", by: "dev_virellia").verdict
        func footer(canValidate: Bool) -> DetailFooter {
            DetailFooter(
                verdict: verdict, viewerDeviceId: "dev_me", canValidate: canValidate, failure: nil,
                ownerName: "Mom", isBlocked: true, changing: .constant(false), onDecide: { _ in }
            )
        }
        // A guardian can decide again; a protected person sees no "Verified safe" card.
        #expect(footer(canValidate: true).showsButtons)
        #expect(!footer(canValidate: false).showsButtons)
    }
}
