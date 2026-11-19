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

    /// The server counts code points: 200 "❤️" are 200 characters but 400 code points, which used to give a 422.
    @Test func emojiAreCountedAsTheServerCountsThem() {
        #expect(SafeReasonNotes.length("❤️") == 2)
        let notes = SafeReasonNotes.compose(reasons: Set(SafeReason.allCases), note: String(repeating: "❤️", count: 200))
        #expect(notes.unicodeScalars.count <= 280)
        #expect(notes.hasSuffix(String(repeating: "❤️", count: SafeReasonNotes.maxNoteLength / 2)))
    }

    @Test func clampNeverSplitsAnEmoji() {
        let clamped = SafeReasonNotes.clamp(String(repeating: "a", count: 199) + "👍🏽")
        #expect(clamped == String(repeating: "a", count: 199))
    }
}
