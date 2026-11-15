import Testing
@testable import Shoo

/// DT-04: reasons about the address show the domain, with the suspicious part marked.
struct AddressEvidenceTests {
    @Test func addressReasonsAreTheSixDomainSignals() {
        let address = ["lookalike_domain", "brand_plus_keyword", "cheap_tld", "suspicious_link", "new_domain", "db_match"]
        #expect(address.allSatisfy { SignalKind(signalId: $0).isAddress })
        let page = ["asks_pin", "brand_logo_offsite", "urgent_language", "unreasonable_request", "hoax_claim", "x"]
        #expect(page.allSatisfy { !SignalKind(signalId: $0).isAddress })
    }

    @Test func cheapEndingMarksOnlyTheEnding() {
        let domain = "bca-verifikasi.site"
        let ranges = AddressEvidence.markedRanges(in: domain, kind: .cheapEnding)
        #expect(ranges.map { String(domain[$0]) } == [".site"])
    }

    @Test func otherAddressReasonsMarkTheWholeDomain() {
        let domain = "lphone-login.com"
        for kind in [SignalKind.lookalikeDomain, .brandInAddress, .newDomain, .knownScam, .suspiciousLink] {
            #expect(AddressEvidence.markedRanges(in: domain, kind: kind).map { String(domain[$0]) } == [domain])
        }
        // A domain with no dot or a trailing dot has no ending to mark: all of it is marked.
        #expect(AddressEvidence.markedRanges(in: "router", kind: .cheapEnding).map { String("router"[$0]) } == ["router"])
        #expect(AddressEvidence.markedRanges(in: "x.", kind: .cheapEnding).map { String("x."[$0]) } == ["x."])
        #expect(AddressEvidence.markedRanges(in: "", kind: .cheapEnding).isEmpty)
    }

    @Test func markedTextKeepsEveryCharacter() {
        let domain = "bca-verifikasi.site"
        let text = AddressEvidence.marked(domain, ranges: AddressEvidence.markedRanges(in: domain, kind: .cheapEnding))
        #expect(String(text.characters) == domain)
        let marked = text.runs.filter { $0.backgroundColor != nil }.map { String(text[$0.range].characters) }
        #expect(marked == [".site"])
    }

    @Test func ageIsReadFromTheReasonInEitherLanguage() {
        #expect(AddressEvidence.days(in: "Domain age 3 days") == 3)
        #expect(AddressEvidence.days(in: "Situs ini baru dibuat 12 hari lalu") == 12)
        #expect(AddressEvidence.days(in: "This site was made recently") == nil)
    }
}
