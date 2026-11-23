package com.shoo.app.features.detail

import android.net.Uri
import androidx.compose.ui.geometry.Rect
import com.shoo.app.data.ShooJson
import java.time.Instant
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

/** Where a signal sits on the copied page (`marks` in the meta, #176): document coordinates in CSS px. */
data class ReplicaMark(val signalId: String, val rect: Rect)

/**
 * What the extension wrote into `<meta name="shoo-replica" content="…">` (replica.js `headMeta`).
 * The device writes it, so every field is untrusted: anything off means "render from the top" (K13).
 */
data class ReplicaMeta(
    val url: String?,
    val capturedAt: Instant,
    /** Document y to scroll to first (the sensitive form, else what was on screen). Never negative. */
    val focusY: Double,
    val truncated: Boolean,
    /** Areas per signal for the spotlight on Detail. Out-of-range or null entries are dropped; a wrong JSON type
     * breaks the whole meta like any other key. */
    val marks: List<ReplicaMark> = emptyList(),
) {
    /** "Copied from <host+path>" when the copy came from another page of the same site (24-hour reuse, K4).
     * Only for the scan's domain or a subdomain: the device could write any URL here. Plain text, shortened. */
    fun copiedFrom(scanURL: String, domain: String): String? {
        val url = url ?: return null
        if (url == scanURL) return null
        val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return null
        val scheme = uri.scheme?.lowercase() ?: return null
        if (scheme != "http" && scheme != "https") return null
        val bare = uri.host?.lowercase()?.removePrefix("[")?.removeSuffix("]") ?: return null
        if (bare.isEmpty()) return null
        val lowerDomain = domain.lowercase()
        val host: String
        if (bare.contains(":")) {
            // Only an IPv6 literal has a colon in its host. The scan's `domain` is bracketed and compressed (#487,
            // `[2001:db8::1]`), the device may spell it otherwise: the two addresses are compared, and the line shows
            // the scan's own form. A zone id (`%25en0`) is refused: the extension's URL parser refuses one.
            if (bare.contains("%") || !lowerDomain.startsWith("[") || !lowerDomain.endsWith("]")) return null
            val a = ipv6Bytes(bare) ?: return null
            val b = ipv6Bytes(lowerDomain.drop(1).dropLast(1)) ?: return null
            if (!a.contentEquals(b)) return null
            host = lowerDomain
        } else {
            if (bare != lowerDomain && !bare.endsWith(".$lowerDomain")) return null
            host = bare
        }
        // The decoded path is device text: no line breaks or bidi controls that could reorder the line.
        val decodedPath = uri.path ?: ""
        val path = buildString {
            var index = 0
            while (index < decodedPath.length) {
                val codePoint = decodedPath.codePointAt(index)
                val type = Character.getType(codePoint)
                if (type != Character.CONTROL.toInt() && type != Character.FORMAT.toInt() &&
                    type != Character.LINE_SEPARATOR.toInt() && type != Character.PARAGRAPH_SEPARATOR.toInt()
                ) {
                    appendCodePoint(codePoint)
                }
                index += Character.charCount(codePoint)
            }
        }
        val text = host + path
        val length = text.codePointCount(0, text.length)
        if (length <= maxCopiedFromLength) return text
        val end = text.offsetByCodePoints(0, maxCopiedFromLength - 1)
        return text.substring(0, end) + "…"
    }

    companion object {
        /** The meta sits in `<head>`, but `<html style>` can carry a data URI before it. */
        const val searchLimit = 64 * 1024
        /** Longest "Copied from …" text on the Detail screen. */
        const val maxCopiedFromLength = 80
        /** More marks than any real page needs; the rest are ignored. */
        const val maxMarks = 24

        private const val marker = "<meta name=\"shoo-replica\" content=\""
        private val keys = setOf("v", "url", "capturedAt", "viewport", "focusY", "truncated", "marks")
        /** replica.js metaToken (`shoo` + up to 8 base-36 chars + `-meta`). Seeing it inside the value means `$&` in
         * the page URL made `String.replace` paste the token back in (replica.js:279, C26). */
        private val leakedToken = Regex("shoo[a-z0-9]{0,8}-meta")

        /** null when the meta is missing or broken in any way; the caller then starts at the top. */
        fun read(html: String): ReplicaMeta? {
            val head = headPrefix(html)
            val markerAt = head.indexOf(marker)
            if (markerAt < 0) return null
            val start = markerAt + marker.length
            val end = head.indexOf('"', start)
            if (end < 0) return null
            // escapeAttr (replica.js:56) wrote these four; `&amp;` last so `&amp;quot;` stays `&quot;`.
            val value = head.substring(start, end)
                .replace("&lt;", "<")
                .replace("&gt;", ">")
                .replace("&quot;", "\"")
                .replace("&amp;", "&")
            if (leakedToken.containsMatchIn(value)) return null
            return try {
                decode(value)
            } catch (_: Exception) {
                null
            }
        }

        /** Strict, like Swift's `JSONDecoder`: one JSON object with known keys only, each of the right type. */
        private fun decode(value: String): ReplicaMeta? {
            val tokener = JSONTokener(value)
            val obj = tokener.nextValue() as? JSONObject ?: return null
            // A `$'` in the URL pastes the rest of the page in: nothing may follow the object.
            if (tokener.more()) return null
            for (key in obj.keys()) if (key !in keys) return null
            val v = obj.opt("v") as? Number ?: return null
            if (v.toDouble() != 1.0) return null
            val url = when (val raw = obj.opt("url")) {
                null, JSONObject.NULL -> null
                is String -> raw
                else -> return null
            }
            val capturedText = obj.opt("capturedAt") as? String ?: return null
            val capturedAt = ShooJson.parseDate(capturedText)
            val focusRaw = when (val raw = obj.opt("focusY")) {
                null, JSONObject.NULL -> null
                is Number -> raw.toDouble()
                else -> return null
            }
            val truncated = when (val raw = obj.opt("truncated")) {
                null, JSONObject.NULL -> false
                is Boolean -> raw
                else -> return null
            }
            val marks = when (val raw = obj.opt("marks")) {
                null, JSONObject.NULL -> emptyList()
                is JSONArray -> {
                    val wire = ArrayList<ReplicaMark?>()
                    for (index in 0 until raw.length()) {
                        when (val entry = raw.opt(index)) {
                            null, JSONObject.NULL -> wire.add(null)
                            is JSONObject -> wire.add(wireMark(entry) ?: return null)
                            else -> return null
                        }
                    }
                    wire.take(maxMarks).mapNotNull { entry -> entry?.let { mark(it) } }
                }
                else -> return null
            }
            // JSON.stringify(NaN) is null.
            val focusY = focusRaw?.takeIf { it.isFinite() && it > 0 } ?: 0.0
            return ReplicaMeta(url = url, capturedAt = capturedAt, focusY = focusY, truncated = truncated, marks = marks)
        }

        /** The wire shape: every field present and of the right type, else the whole meta is broken. */
        private fun wireMark(json: JSONObject): ReplicaMark? {
            val signalId = json.opt("signalId") as? String ?: return null
            val x = (json.opt("x") as? Number)?.toFloat() ?: return null
            val y = (json.opt("y") as? Number)?.toFloat() ?: return null
            val w = (json.opt("w") as? Number)?.toFloat() ?: return null
            val h = (json.opt("h") as? Number)?.toFloat() ?: return null
            return ReplicaMark(signalId, Rect(x, y, x + w, y + h))
        }

        /** A known-looking id and a finite, non-empty box inside the page; anything else is dropped. */
        private fun mark(wire: ReplicaMark): ReplicaMark? {
            val r = wire.rect
            val numbers = listOf(r.left, r.top, r.width, r.height)
            if (!numbers.all { it.isFinite() && it >= 0f && it < 100_000f }) return null
            if (r.width <= 0f || r.height <= 0f) return null
            if (wire.signalId.length !in 1..40) return null
            if (!wire.signalId.all { it in 'a'..'z' || it == '_' }) return null
            return wire
        }

        /** Time for "Copy of the page · …": the device clock, kept near the scan (K14). No meta → `detectedAt`. */
        fun capturedAt(meta: ReplicaMeta?, detectedAt: Instant): Instant {
            if (meta == null) return detectedAt
            val earliest = detectedAt.minusSeconds(24 * 60 * 60)
            val latest = detectedAt.plusSeconds(5 * 60)
            return minOf(maxOf(meta.capturedAt, earliest), latest)
        }

        /** The 16 bytes of an IPv6 address in text form (no brackets), or null when it is not one (inet_pton rules,
         * an IPv4 tail included). Parsed here, never through `InetAddress`, so nothing can turn into a DNS lookup. */
        internal fun ipv6Bytes(text: String): ByteArray? {
            if (text.isEmpty() || text.count { it == ':' } < 2) return null
            val doubleColon = text.indexOf("::")
            if (doubleColon >= 0 && text.indexOf("::", doubleColon + 1) >= 0) return null
            val words: List<Int> = if (doubleColon >= 0) {
                val head = ipv6Groups(text.substring(0, doubleColon), allowIPv4 = false) ?: return null
                val tail = ipv6Groups(text.substring(doubleColon + 2), allowIPv4 = true) ?: return null
                if (head.size + tail.size > 7) return null
                head + List(8 - head.size - tail.size) { 0 } + tail
            } else {
                ipv6Groups(text, allowIPv4 = true)?.takeIf { it.size == 8 } ?: return null
            }
            val bytes = ByteArray(16)
            for ((index, word) in words.withIndex()) {
                bytes[index * 2] = (word shr 8).toByte()
                bytes[index * 2 + 1] = (word and 0xFF).toByte()
            }
            return bytes
        }

        /** 16-bit groups of one side of `::`; the last one may be a dotted IPv4 address (two groups). */
        private fun ipv6Groups(part: String, allowIPv4: Boolean): List<Int>? {
            if (part.isEmpty()) return emptyList()
            val pieces = part.split(':')
            val result = ArrayList<Int>()
            for ((index, piece) in pieces.withIndex()) {
                if (allowIPv4 && index == pieces.lastIndex && piece.contains('.')) {
                    val octets = piece.split('.')
                    if (octets.size != 4) return null
                    val bytes = ArrayList<Int>()
                    for (octet in octets) {
                        if (octet.isEmpty() || octet.length > 3 || !octet.all { it in '0'..'9' }) return null
                        val number = octet.toInt()
                        if (number > 255) return null
                        bytes.add(number)
                    }
                    result.add((bytes[0] shl 8) or bytes[1])
                    result.add((bytes[2] shl 8) or bytes[3])
                } else {
                    if (piece.isEmpty() || piece.length > 4) return null
                    if (!piece.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) return null
                    result.add(piece.toInt(16))
                }
            }
            return result
        }

        private fun headPrefix(html: String): String {
            val window = if (html.length > searchLimit) html.substring(0, searchLimit) else html
            val headEnd = window.indexOf("</head>", ignoreCase = true)
            return if (headEnd >= 0) window.substring(0, headEnd) else window
        }
    }
}
