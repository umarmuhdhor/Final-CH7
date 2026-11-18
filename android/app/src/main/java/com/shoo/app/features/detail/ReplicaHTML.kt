package com.shoo.app.features.detail

/**
 * Makes a page replica safe to hand to the locked `WebView` (K11, K12).
 * The Worker's CSP header is lost once the HTML is a string, and the CSP `<meta>` inside the file was written by the
 * device, so the app adds its own lock in front and refuses markup a real capture never has.
 */
object ReplicaHTML {
    /** Same as the Worker's REPLICA_CSP, except fonts: the device's binary fonts are not loaded, system fonts only. */
    const val csp = "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src 'none'; form-action 'none'; base-uri 'none'"

    /** Second layer under `LockedWebView`: inline `!important` page styles can beat these, the native lock can't be beaten. */
    const val lockStyle =
        "*{-webkit-user-select:none!important;-webkit-touch-callout:none!important;animation:none!important;transition:none!important}" +
            "input,textarea,select,button{pointer-events:none!important;-webkit-user-modify:read-only!important}"

    /**
     * Tags replica.js never writes (stylesheets become `<style>`, `<` in text and attributes is escaped).
     * Any of these means a modified device. A tag name only counts when the name ends there, so SVG's
     * `<linearGradient` is not `<link`.
     */
    private val refusedTags = listOf(
        "<link", "<base", "<script", "<iframe", "<frame", "<frameset", "<object", "<embed", "<noscript",
    )

    private val refusedNames: List<String> = refusedTags.map { it.drop(1) }
    private val firstLetters: Set<Char> = refusedNames.map { it.first() }.toSet()

    private val doctype = Regex("^﻿?\\s*<!doctype[^>]*>", RegexOption.IGNORE_CASE)

    /** The HTML with our CSP, DNS-prefetch-off and lock style first, or null when it must not be rendered. */
    fun locked(html: String): String? {
        if (!passesGate(html)) return null
        val lock = "<meta http-equiv=\"Content-Security-Policy\" content=\"$csp\">" +
            "<meta http-equiv=\"x-dns-prefetch-control\" content=\"off\">" +
            "<style>$lockStyle</style>"
        // Before the doctype would put the page in quirks mode; after it, nothing else comes first.
        // A BOM or whitespace before the doctype is still a doctype (no quirks mode, marks stay in place).
        val match = doctype.find(html)
        if (match != null) {
            val end = match.range.last + 1
            return html.substring(0, end) + lock + html.substring(end)
        }
        return lock + html
    }

    /**
     * Fail-closed lexical gate (K11), case-insensitive. A real capture has exactly one `<meta http-equiv>` (its CSP).
     * `http-equiv` is counted anywhere in the file, not per tag: a `>` inside an attribute can't hide a second one.
     * One linear pass, so a hostile 3 MB file stays fast (`<meta <meta …` flood, review H1).
     * iOS walks the UTF-8 bytes; here the UTF-16 chars. Every needle is ASCII, so the result is the same.
     */
    fun passesGate(html: String): Boolean {
        val count = html.length
        // ASCII-only lowercasing: every needle is ASCII.
        fun lower(c: Char): Char = if (c in 'A'..'Z') (c.code or 0x20).toChar() else c
        fun matches(needle: String, start: Int): Boolean {
            if (start < 0 || start + needle.length > count) return false
            for (k in needle.indices) {
                if (lower(html[start + k]) != needle[k]) return false
            }
            return true
        }
        var at = html.indexOf('<')
        while (at >= 0) {
            if (at + 1 < count && lower(html[at + 1]) in firstLetters) {
                for (name in refusedNames) {
                    if (!matches(name, at + 1)) continue
                    // The name must end there, so SVG's `<linearGradient` is not `<link`.
                    val end = at + 1 + name.length
                    if (end >= count) return false
                    val next = html[end]
                    if (next == ' ' || next.code in 0x09..0x0D || next == '/' || next == '>') return false
                }
            }
            at = html.indexOf('<', at + 1)
        }
        var equivs = 0
        at = html.indexOf('-')
        while (at >= 0) {
            if (matches("http", at - 4) && matches("equiv", at + 1)) {
                equivs += 1
                if (equivs > 1) return false
            }
            at = html.indexOf('-', at + 1)
        }
        return true
    }
}
