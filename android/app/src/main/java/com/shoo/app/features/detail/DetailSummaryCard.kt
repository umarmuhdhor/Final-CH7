package com.shoo.app.features.detail

import android.icu.text.ListFormatter
import android.icu.util.ULocale
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.shoo.app.components.figmaTextStyle
import com.shoo.app.data.ScanResult
import com.shoo.app.data.Signal
import com.shoo.app.data.Verdict
import com.shoo.app.support.AppLanguage
import com.shoo.app.support.L10n
import com.shoo.app.support.t

/**
 * Figma "Ringkasan" (1668:10650, in 1619:6617, DT-04): a tinted card under the score row with two plain sentences: what
 * the page is, then what happened to it ("Halaman BCA palsu yang meminta PIN kamu. Kami memblokir otomatis halaman
 * ini."). The scan carries no summary text (contracts/scan-result.schema.json) and the LLM only sees scores 30–79, so
 * the sentences are built here from the signals, the status and the guardian's verdict.
 */
object DetailSummaryCard {
    /** "Halaman BCA palsu yang meminta PIN kamu. Kami memblokir otomatis halaman ini." null when there is nothing to say. */
    fun text(scan: ScanResult, language: AppLanguage): String? {
        val text = listOfNotNull(finding(scan.signals, language), outcome(scan, language)).joinToString(" ")
        return text.ifEmpty { null }
    }

    /** What the page is, from the strongest facts first: the brand it copies and the data it asks for, a known scam,
     * else how many warning signs there were. */
    fun finding(signals: List<Signal>, language: AppLanguage): String? {
        // Stable sort: equal weights keep their order.
        val heaviestFirst = signals.sortedByDescending { it.weight }
        val brand = heaviestFirst.firstNotNullOfOrNull { SummaryBrand.name(it) }
        val asked = askedData(heaviestFirst, language)
        when {
            brand != null && asked != null -> return L10n.string("detail.summary.fakeBrandAsks %@ %@", language, brand, asked)
            brand != null -> return L10n.string("detail.summary.fakeBrand %@", language, brand)
            asked != null -> return L10n.string("detail.summary.asks %@", language, asked)
        }
        if (signals.any { it.id == "db_match" }) return L10n.string("detail.summary.knownScam", language)
        return when (signals.size) {
            0 -> null
            1 -> L10n.string("detail.summary.oneSign", language)
            else -> L10n.string("detail.summary.signs %lld", language, signals.size)
        }
    }

    /** "PIN dan kode OTP": the two heaviest `asks_*` signals, joined the way the language joins a list. */
    fun askedData(heaviestFirst: List<Signal>, language: AppLanguage): String? {
        val names = heaviestFirst
            .mapNotNull { askedDataKey[it.id] }
            .distinct()
            .take(2)
            .map { L10n.string(it, language) }
        if (names.isEmpty()) return null
        return runCatching { ListFormatter.getInstance(ULocale.forLanguageTag(language.code)).format(names) }
            .getOrNull() ?: names.joinToString(", ")
    }

    /** Layer 3 form signals (contracts/detector-interface.md) and the noun each one asks for. */
    val askedDataKey: Map<String, String> = mapOf(
        "asks_pin" to "detail.summary.data.pin",
        "asks_otp" to "detail.summary.data.otp",
        "asks_password" to "detail.summary.data.password",
        "asks_card" to "detail.summary.data.card",
        "asks_cvv" to "detail.summary.data.cvv",
        "asks_ktp" to "detail.summary.data.ktp",
        "asks_selfie_ktp" to "detail.summary.data.selfieKtp",
    )

    /** What happened to the page, by the same rules as the "Status situs" chip (`DetailView.statusKind`). */
    fun outcome(scan: ScanResult, language: AppLanguage): String = when (DetailView.statusKind(scan)) {
        DetailStatusChip.Kind.BLOCKED ->
            if (scan.verdict?.value == Verdict.Value.NOT_SAFE) {
                L10n.string("detail.summary.confirmedBlocked", language)
            } else {
                L10n.string("detail.summary.autoBlocked", language)
            }
        DetailStatusChip.Kind.WARNING -> L10n.string("detail.summary.warned", language)
        DetailStatusChip.Kind.UNBLOCKED, DetailStatusChip.Kind.MARKED_SAFE -> L10n.string("detail.summary.markedSafe", language)
    }
}

@Composable
fun DetailSummaryCard(text: String, look: DetailLook, modifier: Modifier = Modifier) {
    val title = t("detail.summary.title")
    val shape = RoundedCornerShape(16.dp)
    Column(
        modifier
            .fillMaxWidth()
            .background(look.summaryFill, shape)
            .clearAndSetSemantics {
                contentDescription = "$title, $text"
                testTag = "detail.summary"
            }
            .padding(vertical = 14.dp, horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(title, style = figmaTextStyle(17f, FontWeight.SemiBold, lineHeight = 22f), color = DetailStyle.title)
        Text(
            text,
            style = figmaTextStyle(16f, rounded = true, tracking = -0.31f, lineHeight = 21f),
            color = DetailStyle.secondary,
        )
    }
}

/** The brand an address signal says the page copies, by its display name ("BCA", "Bank Mandiri"). */
object SummaryBrand {
    /** Only `lookalike_domain` and `brand_plus_keyword` name a brand (contracts/detector-interface.md "host"): its
     * `brand`, else its real domain (`official`, scans from a detector before `brand`). Nothing usable gives null. */
    fun name(signal: Signal): String? {
        if (signal.id != "lookalike_domain" && signal.id != "brand_plus_keyword") return null
        val host = signal.host ?: return null
        for (value in listOf(host.brand, host.official)) {
            val text = value?.trim()
            if (!text.isNullOrEmpty()) return text
        }
        return null
    }
}

/** Figma "Ringkasan" fill: #E5483B at 6 % on the red frames; the amber frames get the orange of the bar. */
val DetailLook.summaryFill: Color
    get() = when (this) {
        DetailLook.DANGER -> DetailStyle.hex(0xE5483B).copy(alpha = 0.06f)
        DetailLook.CAUTION -> DetailStyle.hex(0xFF9500).copy(alpha = 0.08f)
    }
