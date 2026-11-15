import CoreGraphics
import Testing
@testable import Shoo

/// U-07 (fase 28n): where Detail's guardian footer goes. Numbers from the 28n trees and this branch's layout.
struct FooterRoomTests {
    /// SE, ID, AX3, `dt-g-warning`: the title ends y 441.5; the footer starts y 369 (its question at y 397) and
    /// ends at the screen's bottom, y 667, so it is 298 pt tall and would cover 44.5 pt of the title.
    @Test func goesIntoThePageWhenItWouldCoverTheTitle() {
        let room = FooterRoom(titleBottom: 441.5, bottom: 667, footer: 298)
        #expect(room.footerInPage)
    }

    /// iPhone 17, ID, AX3, `dt-g-safe`: the title ends y 441.3; the footer runs from y 433.3 to the home indicator
    /// at y 840 (406.7 pt), its card from y 475.3. The title only reaches 8 pt into the clear top: pinned.
    @Test func staysPinnedWhenTheTitleOnlyReachesTheClearTop() {
        let room = FooterRoom(titleBottom: 441.3, bottom: 840, footer: 406.7)
        #expect(!room.footerInPage)
    }

    /// The title may end exactly where the clear top ends; one point lower it would be behind the footer.
    @Test func clearTopIsTheLimit() {
        #expect(!FooterRoom(titleBottom: 369 + FooterRoom.clearTop, bottom: 667, footer: 298).footerInPage)
        #expect(FooterRoom(titleBottom: 369 + FooterRoom.clearTop + 1, bottom: 667, footer: 298).footerInPage)
    }

    /// Before the footer has been measured nothing moves.
    @Test func staysPinnedUntilMeasured() {
        #expect(!FooterRoom(titleBottom: 441.5, bottom: 667).footerInPage)
    }
}
