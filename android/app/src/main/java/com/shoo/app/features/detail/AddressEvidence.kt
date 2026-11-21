package com.shoo.app.features.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.shooShadow
import com.shoo.app.data.Signal
import com.shoo.app.features.activity.activityFont
import com.shoo.app.support.t

/** DT-04: reasons about the address; their card shows `AddressEvidence` instead of the page. */
val SignalKind.isAddress: Boolean
    get() = when (this) {
        SignalKind.LOOKALIKE_DOMAIN, SignalKind.BRAND_IN_ADDRESS, SignalKind.CHEAP_ENDING,
        SignalKind.SUSPICIOUS_LINK, SignalKind.NEW_DOMAIN, SignalKind.KNOWN_SCAM -> true
        else -> false
    }

/**
 * DT-04: the proof for a reason about the **address**, not the page (`lookalike_domain`, `brand_plus_keyword`,
 * `cheap_tld`, `new_domain`, `suspicious_link`, `db_match`). A photo of the page points at nothing for these, so the
 * card shows the address the way a browser does, with the suspicious part marked, and one line that says what is
 * wrong with it.
 *
 * Only the scan's `domain` is shown (the registrable domain; the full host on a shared platform such as
 * `sites.google.com`, #495), as in the link pill (BH-13): a deceiving subdomain never gets a second, bigger stage here.
 * Which part to mark: the parts the detector names in `host.marks` (#497). Without them, `cheap_tld` marks the ending
 * and every other reason the whole domain. When the detector names the brand's real address (`host.official`), a line
 * under the note shows it.
 */
object AddressEvidence {
    const val height = 132f

    fun symbol(kind: SignalKind): String = when (kind) {
        SignalKind.NEW_DOMAIN -> "calendar"
        SignalKind.KNOWN_SCAM -> "xmark.shield"
        SignalKind.CHEAP_ENDING -> "tag"
        SignalKind.LOOKALIKE_DOMAIN, SignalKind.BRAND_IN_ADDRESS -> "textformat.abc"
        SignalKind.SUSPICIOUS_LINK -> "link"
        else -> "exclamationmark.circle"
    }

    /**
     * Parts of `domain` to mark: the detector's `marks` that are in it (#497). When none is, today's marks:
     * `cheap_tld` the last label with its dot (`.site`), everything else all of it. Ranges are end-exclusive.
     */
    fun markedRanges(domain: String, kind: SignalKind, marks: List<String>? = null): List<IntRange> {
        if (domain.isEmpty()) return emptyList()
        val found = ranges(marks ?: emptyList(), domain)
        if (found.isNotEmpty()) return found
        val dot = domain.lastIndexOf('.')
        if (kind == SignalKind.CHEAP_ENDING && dot >= 0 && dot + 1 < domain.length) {
            return listOf(dot until domain.length)
        }
        return listOf(0 until domain.length)
    }

    /**
     * Where each mark reads in `domain`, ignoring case, in domain order. Only the first 4 marks count (the contract's
     * limit). Marks come in reading order, so each one is looked for after the previous; one that is not there is
     * looked for from the start (without moving the search back), and one not found at all is left out. Overlapping
     * or touching parts join into one, so a duplicate mark marks its part once.
     */
    fun ranges(marks: List<String>, domain: String): List<IntRange> {
        val found = ArrayList<IntRange>()
        var cursor = 0
        for (mark in marks.take(4)) {
            if (mark.isEmpty()) continue
            var at = domain.indexOf(mark, startIndex = cursor, ignoreCase = true)
            if (at < 0) at = domain.indexOf(mark, startIndex = 0, ignoreCase = true)
            if (at < 0) continue
            val range = at until at + mark.length
            found.add(range)
            cursor = maxOf(cursor, range.last + 1)
        }
        val joined = ArrayList<IntRange>()
        for (range in found.sortedBy { it.first }) {
            val last = joined.lastOrNull()
            if (last != null && range.first <= last.last + 1) {
                joined[joined.size - 1] = last.first until maxOf(last.last, range.last) + 1
            } else {
                joined.add(range)
            }
        }
        return joined
    }

    /**
     * The brand's real address to show, or null when the detector names none. Only brand reasons (`lookalike_domain`,
     * `brand_plus_keyword`) have one in the contract. "Real: X" sits next to a checkmark seal, so a value that does not
     * look like a domain is never shown (#497 follow-up): scans stored before the backend checked `official` may hold
     * any text a device sent.
     */
    fun official(host: Signal.Host?, kind: SignalKind): String? {
        if (kind != SignalKind.LOOKALIKE_DOMAIN && kind != SignalKind.BRAND_IN_ADDRESS) return null
        val official = host?.official?.trim() ?: return null
        return if (looksLikeDomain(official)) official else null
    }

    /**
     * The backend's `DOMAIN` rule (backend/api/src/http/validate.ts), at most 253 characters: lowercase ASCII labels
     * of 1–63 letters, digits and inner hyphens joined by dots (an IPv4 address and a single label pass), or an IPv6
     * literal in brackets. No scheme, path, port, space or trailing dot.
     */
    fun looksLikeDomain(value: String): Boolean {
        // Bytes, not characters: a combining mark must not ride along with an allowed letter.
        val bytes = value.toByteArray(Charsets.UTF_8)
        if (bytes.isEmpty() || bytes.size > 253) return false
        fun digit(b: Byte) = b in '0'.code.toByte()..'9'.code.toByte()
        fun hexLetter(b: Byte) = b in 'a'.code.toByte()..'f'.code.toByte()
        fun letter(b: Byte) = b in 'a'.code.toByte()..'z'.code.toByte()
        val hyphen = '-'.code.toByte()
        if (bytes.first() == '['.code.toByte()) {
            if (bytes.size < 2 || bytes.last() != ']'.code.toByte()) return false
            val groups = String(bytes, 1, bytes.size - 2, Charsets.UTF_8).split(':')
            return groups.size in 3..8 && groups.all { group ->
                val g = group.toByteArray(Charsets.UTF_8)
                g.size <= 4 && g.all { digit(it) || hexLetter(it) }
            }
        }
        return value.split('.').all { label ->
            val l = label.toByteArray(Charsets.UTF_8)
            l.size in 1..63 && l.first() != hyphen && l.last() != hyphen &&
                l.all { letter(it) || digit(it) || it == hyphen }
        }
    }

    /** The domain with `ranges` on the marker yellow, bold; the rest regular. */
    fun marked(domain: String, ranges: List<IntRange>): AnnotatedString = buildAnnotatedString {
        append(domain)
        for (range in ranges) {
            if (range.first < 0 || range.last >= domain.length || range.isEmpty()) continue
            addStyle(SpanStyle(background = DetailStyle.marker, fontWeight = FontWeight.Bold), range.first, range.last + 1)
        }
    }

    /** The first whole number in the reason ("Domain age 3 days", "Situs ini baru dibuat 3 hari lalu"), or null: the
     * label is the only place the age reaches the app (`rdapRegisteredAt` is request-only, #270). */
    fun days(text: String): Int? = Regex("\\d{1,5}").find(text)?.value?.toIntOrNull()
}

/**
 * `reasonText`: the reason in the viewer's words (`label` or `labelSimple`): the age of a new domain is read from it.
 * `host`: the signal's `host` (#497): which parts to mark and the brand's real address. null = today's marks.
 */
@Composable
fun AddressEvidence(
    domain: String,
    kind: SignalKind,
    reasonText: String,
    host: Signal.Host? = null,
    modifier: Modifier = Modifier,
) {
    val panel = RoundedCornerShape(12.dp)
    val note = when (kind) {
        SignalKind.NEW_DOMAIN -> {
            val days = AddressEvidence.days(reasonText)
            when (days) {
                null -> t("Address made recently")
                1 -> t("Address is 1 day old")
                else -> t("Address is %lld days old", days)
            }
        }
        SignalKind.KNOWN_SCAM -> t("On a scam list")
        SignalKind.CHEAP_ENDING -> t("Cheap ending often used by scam sites")
        SignalKind.LOOKALIKE_DOMAIN -> t("Not the brand's official address")
        SignalKind.BRAND_IN_ADDRESS -> t("Brand name with extra words")
        SignalKind.SUSPICIOUS_LINK -> t("The link itself looks like a scam link")
        else -> t("Something is off with this address")
    }
    val official = AddressEvidence.official(host, kind)
    val officialText = official?.let { t("Real: %@", it) }
    val spoken = listOfNotNull(domain, note, officialText).joinToString(", ")
    Column(
        modifier
            .fillMaxWidth()
            // At least the photo card's height; larger text or the real-address line may need more.
            .heightIn(min = AddressEvidence.height.dp)
            .clip(panel)
            .background(DetailStyle.photoFill)
            .border(1.dp, DetailStyle.photoStroke, panel)
            .clearAndSetSemantics { contentDescription = spoken }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // A browser's address field: a white capsule with the domain, the marked part on the marker yellow.
        Row(
            Modifier
                .fillMaxWidth()
                .height(44.dp)
                .shooShadow(DetailStyle.pageShadow.copy(alpha = 0.08f), radius = 7.5.dp, y = 4.3.dp, shape = CapsuleShape)
                .background(Color.White, CapsuleShape)
                .padding(horizontal = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SfSymbol("globe", pointSize = 15f, tint = DetailStyle.secondary)
            HeadTruncatedText(
                text = AddressEvidence.marked(domain, AddressEvidence.markedRanges(domain, kind, host?.marks)),
                style = activityFont(17f).copy(color = DetailStyle.title),
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                SfSymbol(AddressEvidence.symbol(kind), pointSize = 14f, tint = DetailStyle.secondary)
                Text(note, style = activityFont(15f), color = DetailStyle.secondary, textAlign = TextAlign.Center)
            }
            if (officialText != null) {
                // "Real: bca.co.id": the address the scam copies, from the detector's brand list (public data).
                Row(
                    Modifier.tagged("detail.address.official"),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    SfSymbol("checkmark.seal", pointSize = 14f, tint = DetailStyle.title)
                    // iOS truncates in the middle; Compose 1.7 has no middle ellipsis, so the end goes.
                    Text(
                        officialText,
                        style = activityFont(15f, FontWeight.SemiBold),
                        color = DetailStyle.title,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}


/**
 * One line that shrinks to 70 % before it cuts, and then cuts the head, never the end: for a cheap ending, the ending
 * is the proof (iOS `.minimumScaleFactor(0.7)` + `.truncationMode(.head)`, which Compose 1.7 does not have).
 */
@Composable
private fun HeadTruncatedText(text: AnnotatedString, style: TextStyle, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier) {
        val measurer = rememberTextMeasurer()
        val density = LocalDensity.current
        val maxPx = constraints.maxWidth
        val fitted = remember(text, style, maxPx, density) {
            fun width(candidate: AnnotatedString, scale: Float): Int = measurer.measure(
                candidate,
                style.copy(fontSize = style.fontSize * scale),
                maxLines = 1,
                softWrap = false,
                constraints = Constraints(),
            ).size.width
            if (maxPx == Constraints.Infinity) return@remember text to 1f
            var scale = 1f
            while (scale > 0.7f && width(text, scale) > maxPx) scale -= 0.05f
            scale = scale.coerceAtLeast(0.7f)
            if (width(text, scale) <= maxPx) return@remember text to scale
            var drop = 1
            while (drop < text.length) {
                val candidate = buildAnnotatedString {
                    append("…")
                    append(text.subSequence(drop, text.length))
                }
                if (width(candidate, scale) <= maxPx) return@remember candidate to scale
                drop += 1
            }
            text to scale
        }
        Text(
            fitted.first,
            style = style.copy(fontSize = style.fontSize * fitted.second),
            maxLines = 1,
            softWrap = false,
        )
    }
}
