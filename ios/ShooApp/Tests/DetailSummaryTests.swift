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

    /// blocked-92: brand_plus_keyword (bca) + asks_pin, like the Figma example.
    private func withBCA(_ scan: inout ScanResult) {
        let index = scan.signals.firstIndex { $0.id == "brand_plus_keyword" }!
        scan.signals[index].host = Signal.Host(marks: ["bca"], official: "bca.co.id")
    }

    @Test func fakeBrandAskingForDataReadsLikeFigma() {
        #expect(text("blocked-92", edit: withBCA)
            == "Halaman BCA palsu yang meminta PIN kamu. Kami memblokir otomatis halaman ini.")
        #expect(text("blocked-92", .english, edit: withBCA)
            == "A fake BCA page that asks for your PIN. We blocked this page automatically.")
    }

    @Test func twoAskedDataAreJoinedLikeTheLanguage() {
        let summary = text("blocked-92") { scan in
            withBCA(&scan)
            scan.signals.append(Signal(id: "asks_otp", layer: 3, weight: 20, label: .init(en: "", id: ""),
                                       labelSimple: .init(en: "", id: "")))
        }
        #expect(summary == "Halaman BCA palsu yang meminta PIN dan kode OTP kamu. Kami memblokir otomatis halaman ini.")
    }

    @Test func olderScansNameTheBrandFromTheEvidence() {
        let summary = text("blocked-92", .english) { scan in
            let index = scan.signals.firstIndex { $0.id == "brand_plus_keyword" }!
            scan.signals[index].evidence = "mandiri · level 2 · verifikasi"
        }
        #expect(summary == "A fake Bank Mandiri page that asks for your PIN. We blocked this page automatically.")
    }

    @Test func unknownBrandShowsItsOfficialDomain() {
        let summary = text("warning-41") { scan in
            let index = scan.signals.firstIndex { $0.id == "brand_plus_keyword" }!
            scan.signals[index].host = Signal.Host(marks: nil, official: "newbank.co.id")
        }
        #expect(summary == "Halaman ini meniru newbank.co.id. Kami memberi peringatan sebelum halaman ini dibuka.")
    }

    @Test func dataWithoutABrand() {
        #expect(text("warning-63")
            == "Halaman ini meminta data KTP kamu. Kami memberi peringatan sebelum halaman ini dibuka.")
    }

    @Test func knownScamWithAGuardianDecision() {
        #expect(text("blocked-verified-scam")
            == "Halaman ini sudah tercatat sebagai penipuan. Halaman ini sudah dipastikan berbahaya, jadi diblokir.")
    }

    @Test func otherwiseCountsTheSigns() {
        #expect(text("warning-41")
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

    /// The brand names must follow detector/data/brands.json.
    @Test func brandNamesMatchTheDetectorList() throws {
        struct Brands: Decodable {
            struct Brand: Decodable { let id: String; let name: String; let domains: [String] }
            let brands: [Brand]
        }
        let url = RepoPaths.root.appending(path: "detector/data/brands.json")
        let brands = try JSONDecoder().decode(Brands.self, from: Data(contentsOf: url)).brands
        #expect(SummaryBrand.names.map(\.id) == brands.map(\.id))
        #expect(SummaryBrand.names.map(\.name) == brands.map(\.name))
        #expect(SummaryBrand.names.map(\.official) == brands.map { $0.domains.first ?? "" })
    }
}
