package com.shoo.app.features.detail

/**
 * U-07 (DT-01, fase 28n): the guardian's footer is pinned at the bottom of Detail only while it leaves the
 * whole title visible when the page opens. At large text sizes on a small phone the question and the stacked
 * Aman / Bahaya buttons, or the verified card with its notes, grow taller than the room under the title; then the
 * footer goes into the page right under the score, where the title, the score and the buttons can all be read and
 * reached by scrolling.
 *
 * Every value is read from views the decision never moves: the title in the page's own coordinates (scrolling
 * doesn't change it), the screen room above the navigation bar, and the footer's own height (the same pinned or in
 * the page). So placing the footer can't change what decided it, and the layout settles in one pass.
 *
 * The footer's height counts at its tallest at this text size, so it moves from the bottom into the page at most
 * once, never back (Detail resets it for a new text size). All values in dp.
 */
data class FooterRoom(
    /** The title's lower edge in the page's coordinates. */
    val titleBottom: Float = 0f,
    /** Where a pinned footer ends (page y, above the navigation bar). */
    val bottom: Float = Float.POSITIVE_INFINITY,
    /** The footer's tallest height so far, its top padding and fade included. 0 until measured. */
    val footer: Float = 0f,
) {
    fun measured(footer: Float): FooterRoom = copy(footer = maxOf(this.footer, footer))

    /** True when a pinned footer would cover part of the title at the first look. */
    val footerInPage: Boolean
        get() = footer > 0f && titleBottom > bottom - footer + clearTop

    companion object {
        /** iOS's named coordinate space of the scrolling page; on Android the page Box's own coordinates. */
        const val page = "detail.page"

        /** How far the title may reach into the footer's top edge: the clear fade above the question (U-17). */
        const val clearTop = 24f
    }
}
