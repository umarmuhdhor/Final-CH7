import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Shoo

/// Durations a `DetailModel` asked to sleep; the test never really waits.
private actor SleepLog {
    private(set) var delays: [Duration] = []
    func add(_ delay: Duration) { delays.append(delay) }
}

/// fase 18b step 5: a push opens Detail before the Worker stored the page copy.
@MainActor
struct PageCopyWaitTests {
    static let replica = URL(string: "https://shoo-api.example/replicas/abc?e=1&s=x")!
    static let now = Date(timeIntervalSince1970: 2_000_000_000)

    /// A scan `age` seconds old with no copy and no screenshot; the copy shows up on call `copyOnCall`.
    private func model(
        _ id: String = FixtureScan.blocked92, age: TimeInterval, copyOnCall: Int?,
        edit: (@Sendable (inout ScanResult, Int) -> Void)? = nil
    ) async -> (DetailModel, StubRepository, SleepLog) {
        let repository = StubRepository()
        let detectedAt = Self.now.addingTimeInterval(-age)
        await repository.setEditScan { scan, call in
            scan.detectedAt = detectedAt
            scan.screenshotUrl = nil
            scan.pageReplicaUrl = copyOnCall.map { call >= $0 ? Self.replica : nil } ?? nil
            edit?(&scan, call)
        }
        let log = SleepLog()
        let model = DetailModel(scanId: id, repository: repository, now: { Self.now }, sleep: { await log.add($0) })
        await model.load()
        return (model, repository, log)
    }

    @Test func copyAfterThreeSeconds() async {
        let (model, repository, log) = await model(age: 2, copyOnCall: 2)
        #expect(model.awaitsCopy)
        await model.waitForCopy()
        #expect(model.scan?.pageReplicaUrl == Self.replica)
        #expect(await log.delays == [.seconds(3)])
        #expect(await repository.scanCalls == 2)
        #expect(!model.isSavingCopy)
    }

    @Test func copyAfterFifteenSeconds() async {
        let (model, repository, log) = await model(age: 2, copyOnCall: 3)
        await model.waitForCopy()
        #expect(model.scan?.pageReplicaUrl == Self.replica)
        #expect(await log.delays == [.seconds(3), .seconds(12)])
        #expect(await repository.scanCalls == 3)
    }

    @Test func noCopyAfterTwoTriesStops() async {
        let (model, repository, log) = await model(age: 2, copyOnCall: nil)
        await model.waitForCopy()
        #expect(model.scan?.pageReplicaUrl == nil)
        #expect(await log.delays.count == 2)
        #expect(await repository.scanCalls == 3)
        #expect(!model.isSavingCopy)
    }

    @Test(arguments: [61.0, -5.0])
    func oldOrFutureScanDoesNotWait(age: TimeInterval) async {
        let (model, repository, log) = await model(age: age, copyOnCall: 2)
        #expect(!model.awaitsCopy)
        await model.waitForCopy()
        #expect(await log.delays.isEmpty)
        #expect(await repository.scanCalls == 1)
    }

    @Test func screenshotScanDoesNotWait() async {
        let (model, _, log) = await model(age: 2, copyOnCall: 2) { scan, _ in
            scan.screenshotUrl = URL(string: "https://shoo-api.example/screenshots/abc")
        }
        await model.waitForCopy()
        #expect(await log.delays.isEmpty)
    }

    /// Only the link is taken from the later answer: the verdict on screen stays.
    @Test func onlyTheLinkIsPatched() async {
        let (model, _, _) = await model(FixtureScan.verifiedScam, age: 2, copyOnCall: 2) { scan, call in
            if call > 1 {
                scan.verdict = nil
                scan.score = 1
            }
        }
        let before = model.scan
        await model.waitForCopy()
        #expect(model.scan?.verdict != nil)
        #expect(model.scan?.verdict == before?.verdict)
        #expect(model.scan?.score == before?.score)
        #expect(model.scan?.pageReplicaUrl == Self.replica)
    }
}

/// The line above the evidence cards (fase 18b step 5).
struct PageCopyCaptionTests {
    private static func scan() -> ScanResult {
        ScanResult(
            id: "s", url: URL(string: "https://bca-verifikasi.site/login")!, domain: "bca-verifikasi.site",
            pageTitle: nil, faviconUrl: nil, score: 92, status: .blocked, signals: [],
            screenshotUrl: nil, pageReplicaUrl: nil, ownerDeviceId: "d", ownerName: "Ibu",
            detectedAt: Date(timeIntervalSince1970: 2_000_000_000), verdict: nil
        )
    }

    @Test func shownSaysCopiedFromAndCutShort() {
        let meta = ReplicaMeta(
            url: URL(string: "https://m.bca-verifikasi.site/otp"), capturedAt: Date(timeIntervalSince1970: 2_000_000_000),
            focusY: 0, truncated: true
        )
        let lines = PageCopyCaption.lines(
            state: .shown, meta: meta, scan: Self.scan(), hasScreenshot: false, language: .english,
            now: Date(timeIntervalSince1970: 2_000_000_100)
        )
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("Copy of the page · "))
        #expect(lines[1] == "Copied from m.bca-verifikasi.site/otp")
        #expect(lines[2] == "Page cut short")
    }

    @Test func otherSiteIsNeverNamed() {
        let meta = ReplicaMeta(
            url: URL(string: "https://evil.example/x"), capturedAt: Date(timeIntervalSince1970: 2_000_000_000),
            focusY: 0, truncated: false
        )
        let lines = PageCopyCaption.lines(state: .shown, meta: meta, scan: Self.scan(), hasScreenshot: false, language: .english)
        #expect(lines.count == 1)
    }

    @Test func noCopyLineOnlyWithoutScreenshot() {
        #expect(PageCopyCaption.lines(state: .none, meta: nil, scan: Self.scan(), hasScreenshot: true, language: .english).isEmpty)
        #expect(PageCopyCaption.lines(state: .unavailable, meta: nil, scan: Self.scan(), hasScreenshot: false, language: .english)
            == ["No copy of this page"])
    }

    @Test func savingAndRateLimitedInIndonesian() {
        #expect(PageCopyCaption.lines(state: .saving, meta: nil, scan: Self.scan(), hasScreenshot: false, language: .indonesian)
            == ["Menyimpan salinan halaman…"])
        #expect(PageCopyCaption.lines(state: .rateLimited, meta: nil, scan: Self.scan(), hasScreenshot: false, language: .indonesian)
            == ["Salinan halaman belum bisa ditampilkan. Coba lagi nanti."])
    }
}

/// The picture the cards draw (fase 18b steps 3, 6).
@MainActor
struct ReplicaSnapshotTests {
    @Test func windowKeepsLeadInAboveTheFocus() {
        let kept = ReplicaSnapshot.window(focusY: 5000, zoom: 1, contentHeight: 20_000)
        #expect(kept.top == 4400)
        #expect(kept.height == 3000)
    }

    @Test func windowStaysInsideThePage() {
        let short = ReplicaSnapshot.window(focusY: 900, zoom: 1, contentHeight: 1200)
        #expect(short == (top: 0, height: 1200))
        let end = ReplicaSnapshot.window(focusY: 19_900, zoom: 1, contentHeight: 20_000)
        #expect(end == (top: 17_000, height: 3000))
        let nan = ReplicaSnapshot.window(focusY: .nan, zoom: 1, contentHeight: 20_000)
        #expect(nan.top == 0)
    }

    @Test func marksMoveWithTheWindowAndOutsideOnesDrop() {
        let marks = [
            ReplicaMark(signalId: "asks_pin", rect: CGRect(x: 10, y: 4500, width: 100, height: 40)),
            ReplicaMark(signalId: "asks_otp", rect: CGRect(x: 10, y: 100, width: 100, height: 40)),
            ReplicaMark(signalId: "brand_logo_offsite", rect: CGRect(x: 10, y: 4390, width: 100, height: 20)),
        ]
        let shifted = ReplicaSnapshot.shifted(marks, topCSS: 4400, heightCSS: 3000)
        #expect(shifted.map(\.signalId) == ["asks_pin", "brand_logo_offsite"])
        #expect(shifted[0].rect.minY == 100)
        #expect(shifted[1].rect.minY == -10)
    }

    /// Draws a real locked replica: white page with a red block at the bottom.
    @Test func rendersTheLockedPage() async throws {
        let html = """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>\
            <body style="margin:0"><div style="height:1000px;background:#ffffff"></div>\
            <div style="height:200px;background:#ff0000"></div></body></html>
            """
        let locked = try #require(ReplicaHTML.locked(html))
        let ruleList = try #require(await ReplicaRules.compiled())
        let window = try #require(ReplicaSnapshot.keyWindow)
        let meta = ReplicaMeta(
            url: nil, capturedAt: Date(), focusY: 1000, truncated: false,
            marks: [ReplicaMark(signalId: "asks_pin", rect: CGRect(x: 0, y: 1000, width: 390, height: 200))]
        )
        let copy = try #require(await ReplicaSnapshot.render(locked, meta: meta, ruleList: ruleList, in: window))
        #expect(copy.cssWidth == 390)
        #expect(abs(copy.image.size.width - ReplicaSnapshot.imageWidth) < 1)
        #expect(abs(copy.image.size.height - 1200 * ReplicaSnapshot.imageWidth / 390) < 2)
        #expect(copy.marks.first?.rect.minY == 1000)
        #expect(window.subviews.allSatisfy { !($0 is LockedWebView) })
        let bottom = try #require(Self.color(copy.image, atFraction: CGPoint(x: 0.5, y: 0.95)))
        #expect(bottom.red > 0.9 && bottom.green < 0.1)
        let top = try #require(Self.color(copy.image, atFraction: CGPoint(x: 0.5, y: 0.1)))
        #expect(top.red > 0.9 && top.green > 0.9)
    }

    private static func color(_ image: UIImage, atFraction point: CGPoint) -> (red: CGFloat, green: CGFloat)? {
        guard let cgImage = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let x = CGFloat(cgImage.width) * point.x
        let y = CGFloat(cgImage.height) * (1 - point.y)
        context.draw(cgImage, in: CGRect(x: -x, y: -y, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255)
    }
}
