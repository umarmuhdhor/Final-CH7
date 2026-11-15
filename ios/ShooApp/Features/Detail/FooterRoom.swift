import CoreGraphics

/// U-07 (DT-01, fase 28n): the guardian's footer is pinned at the bottom of Detail only while it leaves the
/// whole title visible when the page opens. At accessibility sizes on a small iPhone (SE, AX3) the question and
/// the stacked Aman / Bahaya buttons, or the verified card with its notes, grow taller than the room under the
/// title; then the footer goes into the page right under the score, where the title, the score and the
/// buttons can all be read and reached by scrolling.
///
/// Every value is read from views the decision never moves: the title in the page's own coordinate space
/// (scrolling doesn't change it, and the footer in the page sits below it), the screen room outside the
/// bottom inset, and the footer's own height (the same pinned or in the page: full width either way).
/// So placing the footer can't change what decided it, and the layout settles in one pass.
///
/// The footer's height counts at its tallest at this text size: "Ubah" brings the buttons back and a saved choice
/// swaps them for the verified card, and neither may send the footer back and forth under the guardian's finger.
/// So it moves from the bottom into the page at most once, never back (Detail resets it for a new text size).
struct FooterRoom: Equatable {
    /// The named coordinate space of Detail's scrolling page. The page is drawn from the top of the screen
    /// (under the status bar), so before any scroll a y in it is the same y on screen.
    static let page = "detail.page"
    /// How far the title may reach into the footer's top edge: the clear fade above the question (U-17: the
    /// footer's 28 pt top padding, whose fade ends 4 pt above the question). Never into the question or a button.
    static let clearTop: CGFloat = 24

    /// The title's lower edge in the page's coordinate space.
    var titleBottom: CGFloat = 0
    /// Where a pinned footer ends on screen (global y, at the home indicator).
    var bottom: CGFloat = .infinity
    /// The footer's tallest height so far, its top padding and fade included. 0 until measured.
    var footer: CGFloat = 0

    mutating func measured(footer height: CGFloat) {
        footer = max(footer, height)
    }

    /// True when a pinned footer would cover part of the title at the first look.
    var footerInPage: Bool {
        footer > 0 && titleBottom > bottom - footer + Self.clearTop
    }
}
