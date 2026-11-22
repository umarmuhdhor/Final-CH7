import Testing
@testable import Shoo

/// Goldfish V3 option A: each "Scam terbaru" card opens an example for its category (`admin.categories`).
struct ScamModusTests {
    static let known = [
        "phishing_bank", "phishing_ewallet", "marketplace_palsu", "undian_palsu",
        "investasi_bodong", "judi", "pinjol_ilegal",
    ]

    @Test func everyServerCategoryHasItsOwnExample() {
        let links = Self.known.map { ScamModus.forCategory($0).link }
        #expect(Set(links).count == Self.known.count)
        #expect(!links.contains(ScamModus.forCategory("lainnya").link))
    }

    @Test(arguments: ["lainnya", "bansos_palsu", ""])
    func anUnknownCategoryGetsTheGeneralExample(category: String) {
        #expect(ScamModus.forCategory(category) == ScamModus.forCategory("lainnya"))
    }

    /// Made-up addresses only: never a real bank or shop's domain.
    @Test(arguments: known + ["lainnya"])
    func examplesUseMadeUpSiteAddresses(category: String) {
        #expect(ScamModus.forCategory(category).link.hasSuffix(".site"))
    }
}
