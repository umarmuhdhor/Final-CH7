import Foundation
import Testing
@testable import Shoo

/// PR-05 guardian note under own Activity rows (Figma 450:8734 / 450:8739 / 450:8744).
@MainActor
struct ActivityNoteTests {
    func scan(_ status: ScanStatus, verdict: Verdict.Value? = nil, by deviceId: String = "dev_me") -> ScanResult {
        ScanResult(
            id: "s1", url: URL(string: "https://promo-shopee88.xyz")!, domain: "promo-shopee88.xyz",
            pageTitle: nil, faviconUrl: nil, score: 92, status: status, signals: [],
            screenshotUrl: nil, pageReplicaUrl: nil, ownerDeviceId: "dev_mom", ownerName: "Mom",
            detectedAt: Date(timeIntervalSince1970: 1_793_000_000),
            verdict: verdict.map { Verdict(value: $0, byDeviceId: deviceId, byName: "Virellia", decidedAt: Date()) }
        )
    }

    @Test func notSafeVerdictNamesTheGuardian() {
        let note = ActivityNote(scan: scan(.blocked, verdict: .notSafe), guardianName: "Virellia", viewerDeviceId: "dev_mom")
        #expect(note == .notSafe(name: "Virellia"))
    }

    @Test func safeVerdictNamesTheGuardian() {
        let note = ActivityNote(scan: scan(.blocked, verdict: .safe), guardianName: "Virellia", viewerDeviceId: "dev_mom")
        #expect(note == .safe(name: "Virellia"))
    }

    @Test func ownVerdictReadsYou() {
        let note = ActivityNote(scan: scan(.blocked, verdict: .safe, by: "dev_me"), guardianName: nil, viewerDeviceId: "dev_me")
        #expect(note == .safe(name: nil))
    }

    @Test func blockedWithoutVerdictSaysUnseen() {
        let note = ActivityNote(scan: scan(.blocked), guardianName: "Virellia", viewerDeviceId: "dev_mom")
        #expect(note == .unseen(guardianName: "Virellia"))
    }

    @Test func noGuardianNoUnseenNote() {
        #expect(ActivityNote(scan: scan(.blocked), guardianName: nil, viewerDeviceId: "dev_me") == nil)
        #expect(ActivityNote(scan: scan(.blocked), guardianName: "", viewerDeviceId: "dev_me") == nil)
    }

    @Test func warningWithoutVerdictHasNoNote() {
        #expect(ActivityNote(scan: scan(.warning), guardianName: "Virellia", viewerDeviceId: "dev_mom") == nil)
    }

    @Test func warningWithVerdictShowsIt() {
        let note = ActivityNote(scan: scan(.warning, verdict: .notSafe), guardianName: "Virellia", viewerDeviceId: "dev_mom")
        #expect(note == .notSafe(name: "Virellia"))
    }

    @Test func ownListKnowsTheGuardian() async {
        let model = ActivityModel(
            repository: MockRepository(mode: .protected, latency: .zero), owner: .me
        )
        await model.load()
        #expect(model.guardianName == "Adhella")
        let blocked = model.items.first { $0.status == .blocked && $0.verdict == nil }
        if let blocked {
            #expect(model.note(for: blocked) == .unseen(guardianName: "Adhella"))
        }
    }

    @Test func familyListHasNoNotes() async {
        let model = ActivityModel(
            repository: MockRepository(mode: .guardian, latency: .zero), owner: .family
        )
        await model.load()
        #expect(model.guardianName == nil)
        #expect(model.items.allSatisfy { model.note(for: $0) == nil })
    }
}
