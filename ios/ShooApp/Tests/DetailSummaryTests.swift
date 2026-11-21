import Foundation
import Testing
@testable import Shoo

/// DT-04 "Ringkasan" card (Figma 1668:10650): what the page is, then what happened to it.
struct DetailSummaryTests {
    private func text(_ name: String, _ language: AppLanguage = .indonesian, edit: (inout ScanResult) -> Void = { _ in })
        -> String? {
        var scan = FixtureLoader.scan(name)
        edit(&scan)
        return DetailSummaryCard.text(scan, language: language)
    }

    private func editBrandSignal(_ scan: inout ScanResult, _ change: (inout Signal) -> Void) {
        let index = scan.signals.firstIndex { $0.id == "brand_plus_keyword" }!
        change(&scan.signals[index])
    }

    /// blocked-92: brand_plus_keyword with host.brand "BCA" + asks_pin, like the Figma example.
    @Test func fakeBrandAskingForDataReadsLikeFigma() {
        #expect(text("blocked-92") == "Halaman BCA palsu yang meminta PIN kamu. Kami memblokir otomatis halaman ini.")
        #expect(text("blocked-92", .english)
            == "A fake BCA page that asks for your PIN. We blocked this page automatically.")
        #expect(text("warning-63")
            == "Halaman Kemensos palsu yang meminta data KTP kamu. Kami memberi peringatan sebelum halaman ini dibuka.")
    }

    @Test func twoAskedDataAreJoinedLikeTheLanguage() {
        let summary = text("blocked-92") { scan in
            scan.signals.append(Signal(id: "asks_otp", layer: 3, weight: 20, label: .init(en: "", id: ""),
                                       labelSimple: .init(en: "", id: "")))
        }
        #expect(summary == "Halaman BCA palsu yang meminta PIN dan kode OTP kamu. Kami memblokir otomatis halaman ini.")
    }

    @Test func brandWithoutAskedData() {
        #expect(text("warning-41") == "Halaman ini meniru Shopee. Kami memberi peringatan sebelum halaman ini dibuka.")
    }

    /// A detector from before `brand` sends only the real domain.
    @Test func olderDetectorNamesTheOfficialDomain() {
        let summary = text("warning-41") { editBrandSignal(&$0) { $0.host?.brand = nil } }
        #expect(summary == "Halaman ini meniru shopee.co.id. Kami memberi peringatan sebelum halaman ini dibuka.")
    }

    /// Before #497 there was no host: the evidence is never parsed (contracts/detector-interface.md "host").
    @Test func noHostNamesNoBrand() {
        let summary = text("blocked-92", .english) { scan in
            editBrandSignal(&scan) {
                $0.host = nil
                $0.evidence = "bca · level 2 · verifikasi"
            }
        }
        #expect(summary == "This page asks for your PIN. We blocked this page automatically.")
    }

    @Test func onlyAddressSignalsNameABrand() {
        var signal = Signal(id: "cheap_tld", layer: 2, weight: 15, label: .init(en: "", id: ""),
                            labelSimple: .init(en: "", id: ""))
        signal.host = Signal.Host(marks: [".site"], official: "bca.co.id", brand: "BCA")
        #expect(SummaryBrand.name(of: signal) == nil)
        signal.id = "lookalike_domain"
        #expect(SummaryBrand.name(of: signal) == "BCA")
        signal.host?.brand = "  "
        #expect(SummaryBrand.name(of: signal) == "bca.co.id")
    }

    @Test func knownScamWithAGuardianDecision() {
        #expect(text("blocked-verified-scam")
            == "Halaman ini sudah tercatat sebagai penipuan. Halaman ini sudah dipastikan berbahaya, jadi diblokir.")
    }

    @Test func otherwiseCountsTheSigns() {
        #expect(text("warning-41") { editBrandSignal(&$0) { $0.host = nil } }
            == "Kami menemukan 3 tanda mencurigakan di halaman ini. Kami memberi peringatan sebelum halaman ini dibuka.")
        #expect(text("blocked-marked-safe", .english) { $0.signals.removeAll { $0.id == "asks_card" } }
            == "We found 2 warning signs on this page. Adhella marked it safe, so it can be opened.")
    }

    /// C1 (goldfish 21 Nov): a guardian reading Mom's scan sees "PIN Mom", not "PIN kamu".
    @Test func someoneElsesScanNamesTheOwner() {
        let summary = { (language: AppLanguage) in
            DetailSummaryCard.text(FixtureLoader.scan("blocked-92"), owner: "Mom", language: language)
        }
        #expect(summary(.indonesian) == "Halaman BCA palsu yang meminta PIN Mom. Kami memblokir otomatis halaman ini.")
        #expect(summary(.english) == "A fake BCA page that asks for Mom's PIN. We blocked this page automatically.")
        var warned = FixtureLoader.scan("warning-63")
        warned.signals.removeAll { $0.id == "brand_plus_keyword" }
        #expect(DetailSummaryCard.text(warned, owner: "Mom", language: .indonesian)
            == "Halaman ini meminta data KTP Mom. Kami memberi peringatan ke Mom sebelum halaman ini dibuka.")
    }

    /// C1: once marked safe it no longer says "fake … so it can be opened"; it says what Shoo thought, and who.
    @Test func markedSafeSaysWhatShooThoughtAndWho() {
        var scan = FixtureLoader.scan("blocked-92")
        scan.verdict = Verdict(value: .safe, byDeviceId: "dev_budi", byName: "Budi", decidedAt: Date())
        #expect(DetailSummaryCard.text(scan, owner: "Mom", viewerDeviceId: "dev_me", language: .indonesian)
            == "Shoo mengira halaman ini meniru BCA. Budi menandainya aman, jadi bisa dibuka.")
        #expect(DetailSummaryCard.text(scan, owner: "Mom", viewerDeviceId: "dev_budi", language: .english)
            == "Shoo thought this page copied BCA. You marked it safe, so it can be opened.")
        scan.signals = [Signal(id: "db_match", layer: 1, weight: 100, label: .init(en: "", id: ""),
                               labelSimple: .init(en: "", id: ""))]
        #expect(DetailSummaryCard.text(scan, language: .indonesian)
            == "Halaman ini ada di daftar penipuan Shoo. Budi menandainya aman, jadi bisa dibuka.")
    }

    @Test func noSignalsLeavesOnlyTheOutcome() {
        #expect(text("blocked-92") { $0.signals = [] } == "Kami memblokir otomatis halaman ini.")
    }

    @Test func everyAskedSignalHasANoun() {
        let asks = ["asks_pin", "asks_otp", "asks_password", "asks_card", "asks_cvv", "asks_ktp", "asks_selfie_ktp"]
        #expect(Set(DetailSummaryCard.askedDataKey.keys) == Set(asks))
    }
}
