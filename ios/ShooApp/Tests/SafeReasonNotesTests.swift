import Testing
@testable import Shoo

/// GD-07 "Aman" sheet: reasons + note packed into `POST /verdicts` `notes` (≤ 280 characters, contracts/api.md).
struct SafeReasonNotesTests {
    @Test func reasonsComeFirstInAFixedOrderThenTheNote() {
        let notes = SafeReasonNotes.compose(reasons: [.usedBefore, .officialSite], note: "  Situs bank saya. \n")
        #expect(notes == "reasons: official_site, used_before\nSitus bank saya.")
    }

    @Test func noNoteSendsTheReasonsOnly() {
        #expect(SafeReasonNotes.compose(reasons: [.other], note: "   ") == "reasons: other")
    }

    @Test func everythingAtOnceStaysUnderTheServerLimit() {
        let notes = SafeReasonNotes.compose(reasons: Set(SafeReason.allCases), note: String(repeating: "a", count: 500))
        #expect(notes.count <= 280)
        #expect(notes.hasSuffix(String(repeating: "a", count: SafeReasonNotes.maxNoteLength)))
    }
}
