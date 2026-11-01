import Foundation
import Testing
@testable import Shoo

/// Fase 26 U6: the code field takes a pasted invite link or the whole invite message.
struct InvitePasteTests {
    @Test(arguments: [
        "https://shoo-api.afindo-mi01.workers.dev/j/482193",
        "https://shoo-api.afindo-mi01.workers.dev/j/482193.",
        "<https://shoo-api.afindo-mi01.workers.dev/j/482193>",
        "Join me: https://shoo-api.afindo-mi01.workers.dev/j/482193\nor enter code 111111",
        "x https://evil.example/j/111111 https://shoo-api.afindo-mi01.workers.dev/j/482193",
        "Link:https://shoo-api.afindo-mi01.workers.dev/j/482193",
        "[invite](https://shoo-api.afindo-mi01.workers.dev/j/482193)",
    ])
    func linkInTextGivesItsCode(text: String) {
        #expect(InvitePaste.code(inText: text) == "482193")
    }

    @Test(arguments: [
        "",
        "482193",
        "482 193",
        "https://evil.example/j/482193",
        "shoo://join?code=482193",
        "http://shoo-api.afindo-mi01.workers.dev/j/482193",
        "https://shoo-api.afindo-mi01.workers.dev/j/48219",
        "https://shoo-api.afindo-mi01.workers.dev/join?code=482193",
    ])
    func noInviteLinkGivesNothing(text: String) {
        #expect(InvitePaste.code(inText: text) == nil)
    }

    @Test func overlongTokenIsSkipped() {
        let long = "https://shoo-api.afindo-mi01.workers.dev/j/482193?x=" + String(repeating: "a", count: 600)
        #expect(InvitePaste.code(inText: long) == nil)
    }
}

/// Fase 26 K4: the Paste card takes exactly one invite link, nothing else.
struct InvitePasteStrictTests {
    @Test(arguments: [
        ["https://shoo-api.afindo-mi01.workers.dev/j/482193"],
        ["  https://shoo-api.afindo-mi01.workers.dev/j/482193\n"],
        ["https://SHOO-API.afindo-mi01.workers.dev/j/482193"],
    ])
    func oneInviteLinkGivesItsCode(items: [String]) {
        #expect(InvitePaste.code(from: items) == "482193")
    }

    @Test(arguments: [
        ["shoo://join?code=482193"],
        ["http://shoo-api.afindo-mi01.workers.dev/j/482193"],
        ["https://evil.example/j/482193"],
        ["https://shoo-api.afindo-mi01.workers.dev@evil.example/j/482193"],
        ["https://someone@shoo-api.afindo-mi01.workers.dev/j/482193"],
        ["https://shoo-api.afindo-mi01.workers.dev:8443/j/482193"],
        ["https://shoo-api.afindo-mi01.workers.dev/j/48219"],
        ["https://shoo-api.afindo-mi01.workers.dev/j/482193/x"],
        ["https://shoo-api.afindo-mi01.workers.dev/j/482193?x=1"],
        ["https://shoo-api.afindo-mi01.workers.dev/j/482193#x"],
        ["Join me: https://shoo-api.afindo-mi01.workers.dev/j/482193"],
        ["482193"],
        ["https://shoo-api.afindo-mi01.workers.dev/j/482193", "https://shoo-api.afindo-mi01.workers.dev/j/482193"],
        ["https://shoo-api.afindo-mi01.workers.dev/j/482193?" + String(repeating: "a", count: 600)],
        [],
        [""],
    ])
    func anythingElseIsRefused(items: [String]) {
        #expect(InvitePaste.code(from: items) == nil)
    }
}

/// A pasteboard the test controls: counts the "probably a URL" questions and the clears.
final class FakeInvitePasteboard: InvitePasteboard {
    var changeCount = 1
    var hasURL: Bool? = true
    /// Runs while `hasProbableWebURL` is asked, e.g. to copy something new meanwhile.
    var whileAsking: (() -> Void)?
    private(set) var detections = 0
    private(set) var clears: [Int] = []
    private(set) var cleared = false

    func hasProbableWebURL() async -> Bool? {
        detections += 1
        whileAsking?()
        return hasURL
    }

    func clear(ifChangeCount changeCount: Int) {
        clears.append(changeCount)
        guard self.changeCount == changeCount else { return }
        cleared = true
    }
}

/// Fase 26 K3/K7: the clipboard asks once per pasteboard change and clears only its own paste.
@MainActor
struct InviteClipboardTests {
    static let link = "https://shoo-api.afindo-mi01.workers.dev/j/482193"

    @Test func asksOncePerChange() async {
        let pasteboard = FakeInvitePasteboard()
        let clipboard = InviteClipboard(pasteboard: pasteboard)
        await clipboard.refresh()
        await clipboard.refresh()
        #expect(pasteboard.detections == 1)
        #expect(clipboard.offersPaste)
        pasteboard.changeCount = 2
        pasteboard.hasURL = false
        await clipboard.refresh()
        #expect(pasteboard.detections == 2)
        #expect(!clipboard.offersPaste)
    }

    @Test func joinClearsThePasteOnlyIfNothingNewWasCopied() {
        let pasteboard = FakeInvitePasteboard()
        let clipboard = InviteClipboard(pasteboard: pasteboard)
        #expect(clipboard.accept([Self.link]) == "482193")
        clipboard.joined(code: "482193")
        #expect(pasteboard.clears == [1])
        #expect(pasteboard.cleared)

        let later = FakeInvitePasteboard()
        let other = InviteClipboard(pasteboard: later)
        #expect(other.accept([Self.link]) == "482193")
        later.changeCount = 5
        other.joined(code: "482193")
        #expect(later.clears == [1])
        #expect(!later.cleared)
    }

    @Test func otherCodeOrRejectedPasteNeverClears() {
        let pasteboard = FakeInvitePasteboard()
        let clipboard = InviteClipboard(pasteboard: pasteboard)
        #expect(clipboard.accept(["hello"]) == nil)
        clipboard.joined(code: "482193")
        #expect(clipboard.accept([Self.link]) == "482193")
        clipboard.joined(code: "111111")
        #expect(pasteboard.clears.isEmpty)
    }

    @Test func unansweredDetectionIsAskedAgain() async {
        let pasteboard = FakeInvitePasteboard()
        pasteboard.hasURL = nil
        let clipboard = InviteClipboard(pasteboard: pasteboard)
        await clipboard.refresh()
        #expect(!clipboard.offersPaste)
        pasteboard.hasURL = true
        await clipboard.refresh()
        #expect(pasteboard.detections == 2)
        #expect(clipboard.offersPaste)
    }

    @Test func answerForAnOlderPasteboardIsDropped() async {
        let pasteboard = FakeInvitePasteboard()
        pasteboard.whileAsking = { pasteboard.changeCount = 2 }
        let clipboard = InviteClipboard(pasteboard: pasteboard)
        await clipboard.refresh()
        #expect(!clipboard.offersPaste)
        pasteboard.whileAsking = nil
        await clipboard.refresh()
        #expect(pasteboard.detections == 2)
        #expect(clipboard.offersPaste)
    }

    @Test func acceptedPasteHidesTheCardUntilSomethingNewIsCopied() async {
        let pasteboard = FakeInvitePasteboard()
        let clipboard = InviteClipboard(pasteboard: pasteboard)
        await clipboard.refresh()
        #expect(clipboard.accept([Self.link]) == "482193")
        #expect(!clipboard.offersPaste)
        await clipboard.refresh()
        #expect(!clipboard.offersPaste)
        pasteboard.changeCount = 2
        await clipboard.refresh()
        #expect(clipboard.offersPaste)
    }
}
