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
            == "We found 2 warning signs on this page. It was marked safe, so it can be opened.")
    }

    @Test func noSignalsLeavesOnlyTheOutcome() {
        #expect(text("blocked-92") { $0.signals = [] } == "Kami memblokir otomatis halaman ini.")
    }

    @Test func everyAskedSignalHasANoun() {
        let asks = ["asks_pin", "asks_otp", "asks_password", "asks_card", "asks_cvv", "asks_ktp", "asks_selfie_ktp"]
        #expect(Set(DetailSummaryCard.askedDataKey.keys) == Set(asks))
    }
}
