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

    // MARK: host.marks (#497)

    private func marked(_ domain: String, _ kind: SignalKind, _ marks: [String]?) -> [String] {
        AddressEvidence.markedRanges(in: domain, kind: kind, marks: marks).map { String(domain[$0]) }
    }

    @Test func marksFromTheDetectorAreMarked() {
        #expect(marked("bca-verifikasi.site", .brandInAddress, ["bca", "verifikasi"]) == ["bca", "verifikasi"])
        #expect(marked("kl1kbca.com", .lookalikeDomain, ["kl1kbca"]) == ["kl1kbca"])
    }

    @Test func cheapEndingMarkFromTheDetector() {
        #expect(marked("bca-verifikasi.site", .cheapEnding, [".site"]) == [".site"])
    }

    @Test func aMarkNotInTheDomainIsIgnored() {
        #expect(marked("bca-verifikasi.site", .brandInAddress, ["mandiri", "bca", ""]) == ["bca"])
    }

    @Test func noMarkFoundFallsBackToTodaysMarks() {
        #expect(marked("bca-verifikasi.site", .brandInAddress, ["mandiri"]) == ["bca-verifikasi.site"])
        #expect(marked("bca-verifikasi.site", .cheapEnding, [".xyz"]) == [".site"])
        #expect(marked("bca-verifikasi.site", .brandInAddress, [""]) == ["bca-verifikasi.site"])
    }

    @Test func noMarksFallBackToTodaysMarks() {
        for marks in [nil, [String]()] {
            #expect(marked("bca-verifikasi.site", .brandInAddress, marks) == ["bca-verifikasi.site"])
            #expect(marked("bca-verifikasi.site", .cheapEnding, marks) == [".site"])
        }
        #expect(marked("", .brandInAddress, ["bca"]).isEmpty)
    }

    @Test func duplicateMarksMarkThePartOnce() {
        #expect(marked("bca-verifikasi.site", .brandInAddress, ["bca", "bca"]) == ["bca"])
    }

    @Test func aRepeatedPartIsMarkedWhereEachMarkReads() {
        // Marks come in reading order: the second "bca" is the second one in the domain.
        #expect(marked("bca-bca.com", .brandInAddress, ["bca", "bca"]) == ["bca", "bca"])
        let ranges = AddressEvidence.markedRanges(in: "bca-bca.com", kind: .brandInAddress, marks: ["bca", "bca"])
        #expect(ranges.map { "bca-bca.com".distance(from: "bca-bca.com".startIndex, to: $0.lowerBound) } == [0, 4])
    }

    @Test func overlappingMarksJoinIntoOne() {
        #expect(marked("bca-verifikasi.site", .brandInAddress, ["bca-veri", "verifikasi"]) == ["bca-verifikasi"])
        #expect(marked("bca-verifikasi.site", .brandInAddress, ["verifikasi", "bca"]) == ["bca", "verifikasi"])
    }

    @Test func marksMatchWhateverTheCase() {
        #expect(marked("bca-verifikasi.site", .brandInAddress, ["BCA"]) == ["bca"])
    }

    @Test func markedTextKeepsEveryCharacterWithMarks() {
        let domain = "bca-verifikasi.site"
        let ranges = AddressEvidence.markedRanges(in: domain, kind: .brandInAddress, marks: ["bca", "verifikasi"])
        let text = AddressEvidence.marked(domain, ranges: ranges)
        #expect(String(text.characters) == domain)
        let marked = text.runs.filter { $0.backgroundColor != nil }.map { String(text[$0.range].characters) }
        #expect(marked == ["bca", "verifikasi"])
    }

    @Test func evidenceCarriesTheSignalsHost() {
        let host = Signal.Host(marks: ["bca"], official: "bca.co.id")
        let signals = [
            Signal(id: "brand_plus_keyword", layer: 2, weight: 40, label: .init(en: "a", id: "a"),
                   labelSimple: .init(en: "a", id: "a"), host: host),
            Signal(id: "new_domain", layer: 3, weight: 30, label: .init(en: "b", id: "b"), labelSimple: .init(en: "b", id: "b")),
        ]
        let evidence = Evidence.top(signals, mode: .guardian, language: .english)
        #expect(evidence.map(\.host) == [host, nil])
    }

    @Test func officialAddressLineInBothLanguages() {
        #expect(L10n.string("Real: \("bca.co.id")", language: .english) == "Real: bca.co.id")
        #expect(L10n.string("Real: \("bca.co.id")", language: .indonesian) == "Yang asli: bca.co.id")
    }

    @Test func officialLineOnlyWhenTheDetectorNamesIt() {
        let host = Signal.Host(marks: ["bca"], official: "bca.co.id")
        #expect(AddressEvidence.official(in: host, kind: .brandInAddress) == "bca.co.id")
        #expect(AddressEvidence.official(in: host, kind: .lookalikeDomain) == "bca.co.id")
        #expect(AddressEvidence.official(in: Signal.Host(marks: ["bca"]), kind: .brandInAddress) == nil)
        #expect(AddressEvidence.official(in: Signal.Host(official: "  "), kind: .brandInAddress) == nil)
        #expect(AddressEvidence.official(in: nil, kind: .brandInAddress) == nil)
    }

    /// #497 follow-up (security, #551 review): "Real: X" sits next to a checkmark seal, so it shows only a value that
    /// looks like a domain (the backend's DOMAIN rule). Scans stored before the backend checked it may hold any text.
    @Test func officialLineOnlyWhenItLooksLikeADomain() {
        for official in ["bca.co.id", "www.bca.co.id", "xn--bca-0la.com", "192.168.1.1", "[2001:db8::1]", "router", " bca.co.id "] {
            #expect(AddressEvidence.official(in: Signal.Host(official: official), kind: .brandInAddress) != nil, "\(official)")
        }
        let longest = [String(repeating: "a", count: 63), String(repeating: "b", count: 63),
                       String(repeating: "c", count: 63), String(repeating: "d", count: 61)].joined(separator: ".")
        #expect(AddressEvidence.official(in: Signal.Host(official: longest), kind: .lookalikeDomain) == longest)
        for official in [
            "Bank resmi ✓ call 0800", "bca.co.id ✓", "BCA.co.id", "https://bca.co.id", "bca.co.id/login",
            "bca.co.id:443", "bca.co.id.", "bca .co.id", "-bca.co.id", "bca-.co.id", "bca..co.id", ".bca.co.id",
            "bca.co.id\u{7}", "bca\u{202E}di.oc", "bçä.co.id", "bca\u{301}.co.id", "[a\u{301}::1]", "[2001:db8::1", "[bca.co.id]", "[1:2]",
            String(repeating: "a", count: 64) + ".com", longest + "x",
        ] {
            #expect(AddressEvidence.official(in: Signal.Host(official: official), kind: .brandInAddress) == nil, "\(official)")
        }
    }

    /// The contract gives `official` only to `lookalike_domain` and `brand_plus_keyword`.
    @Test func officialLineOnlyOnBrandReasons() {
        let host = Signal.Host(marks: [".site"], official: "bca.co.id")
        for kind in [SignalKind.cheapEnding, .newDomain, .knownScam, .suspiciousLink] {
            #expect(AddressEvidence.official(in: host, kind: kind) == nil)
        }
    }

    @Test func touchingMarksJoinIntoOne() {
        #expect(marked("bcaverifikasi.site", .brandInAddress, ["bca", "verifikasi"]) == ["bcaverifikasi"])
    }

    @Test func punycodeLabelIsMarkedWhole() {
        #expect(marked("xn--bc-xja.site", .suspiciousLink, ["xn--bc-xja"]) == ["xn--bc-xja"])
    }

    @Test func atMostFourMarksAreRead() {
        let domain = "a-b-c-d-e.com"
        #expect(marked(domain, .suspiciousLink, ["a", "b", "c", "d", "e"]) == ["a", "b", "c", "d"])
    }

    @Test func aMarkOutOfOrderDoesNotPullTheNextOneBack() {
        // "a" is not after "c", so it is found from the start; "b" is still read after "c".
        let domain = "a-b-c-b.com"
        let ranges = AddressEvidence.markedRanges(in: domain, kind: .brandInAddress, marks: ["c", "a", "b"])
        #expect(ranges.map { domain.distance(from: domain.startIndex, to: $0.lowerBound) } == [0, 4, 6])
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
