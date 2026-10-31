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
