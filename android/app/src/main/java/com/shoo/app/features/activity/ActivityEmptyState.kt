package com.shoo.app.features.activity

import android.icu.text.MeasureFormat
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import android.icu.util.ULocale
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.HalftoneShield
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.shooEaseOut
import com.shoo.app.components.shooShadow
import com.shoo.app.data.CheckStats
import com.shoo.app.data.ExtensionStatus
import com.shoo.app.support.AppLanguage
import com.shoo.app.support.Formatters
import com.shoo.app.support.L10n
import com.shoo.app.support.t
import java.text.NumberFormat
import java.time.Duration
import java.time.Instant
import java.time.ZoneId

/**
 * Which empty Activity the user sees (Figma "Aktivitas · Semua / Waspada / Diblokir · Kosong" and "· Perlindungan mati").
 * Pure, so the rule is testable without views.
 */
enum class ActivityEmptyKind {
    ALL,
    WARNING,
    BLOCKED,
    /** Nothing to show *because* nothing is checked: grey shield and one button to turn Shoo on. */
    PROTECTION_OFF;

    /** Figma: the empty block's top below the list's usual 32 pt gap under the segments; differs per kind so the
     * centre stays put. */
    val topPadding: Float
        get() = when (this) {
            ALL, BLOCKED -> 103f
            WARNING -> 93f
            PROTECTION_OFF -> 83f
        }

    companion object {
        /** Off wins over the filter: an empty list with the extension off says nothing about safety. Family Activity
         * lists other people's scans, so this phone's add-on doesn't decide there. */
        fun of(filter: ActivityFilter, family: Boolean, extensionStatus: ExtensionStatus?): ActivityEmptyKind {
            if (!family && extensionStatus != null && !extensionStatus.isActive) return PROTECTION_OFF
            return when (filter) {
                ActivityFilter.ALL -> ALL
                ActivityFilter.WARNING -> WARNING
                ActivityFilter.BLOCKED -> BLOCKED
            }
        }
    }
}

/** Texts of the status pill and the "off since" line, from what the extension wrote (#183). */
object ActivityEmptyText {
    /** Android copy (Firefox add-on instead of the Safari extension), in `android-activity-pairing.xcstrings`. */
    const val extensionOnKey = "Firefox add-on on"

    /**
     * Semua: "Add-on Firefox aktif". Waspada / Diblokir: "1.284 situs diperiksa · terakhir 10.42 WIB", shorter when the
     * extension hasn't written the time or the count yet.
     */
    fun pill(
        kind: ActivityEmptyKind,
        stats: CheckStats,
        now: Instant = Instant.now(),
        language: AppLanguage,
        zone: ZoneId = ZoneId.systemDefault(),
    ): String {
        val extensionOn = L10n.string(extensionOnKey, language)
        val checked = stats.checked
        if ((kind != ActivityEmptyKind.WARNING && kind != ActivityEmptyKind.BLOCKED) || checked == null) return extensionOn
        val count = NumberFormat.getIntegerInstance(language.locale).format(checked)
        val last = stats.lastCheckedAt ?: return L10n.string("%@ sites checked", language, count)
        val sameDay = last.atZone(zone).toLocalDate() == now.atZone(zone).toLocalDate()
        val time = if (sameDay) {
            Formatters.time(last, language, zone)
        } else {
            Formatters.dayAndTime(last, language, now, zone)
        }
        return L10n.string("%@ sites checked · last at %@", language, count, time)
    }

    /** "Mati sejak 2 hari lalu" / "Off for 2 days", from the last heartbeat; null when it never ran. */
    fun offSince(lastSeen: Instant?, now: Instant = Instant.now(), language: AppLanguage): String? {
        if (lastSeen == null) return null
        // iOS `DateComponentsFormatter`, `.full`, one unit of day / hour / minute, at least a minute.
        val seconds = maxOf(60L, Duration.between(lastSeen, now).seconds)
        val measure = when {
            seconds >= 86_400 -> Measure(seconds / 86_400, MeasureUnit.DAY)
            seconds >= 3_600 -> Measure(seconds / 3_600, MeasureUnit.HOUR)
            else -> Measure(seconds / 60, MeasureUnit.MINUTE)
        }
        val span = MeasureFormat.getInstance(ULocale.forLanguageTag(language.code), MeasureFormat.FormatWidth.WIDE).format(measure)
        return L10n.string("Off for %@", language, span)
    }
}

/**
 * Figma "Empty State" (480:5500 / 5530 / 5560 / 5590): shield, title, message, then a status pill, or the "Aktifkan
 * ekstensi" button with "Mati sejak …" when protection is off.
 *
 * `pill`: null hides it (Family Activity: this phone's add-on says nothing about the members).
 */
@Composable
fun ActivityEmptyState(
    kind: ActivityEmptyKind,
    pill: String?,
    offSince: String?,
    modifier: Modifier = Modifier,
    turnOn: () -> Unit = {},
) {
    val title = t(
        when (kind) {
            ActivityEmptyKind.ALL -> "No activity yet"
            ActivityEmptyKind.WARNING -> "Nothing suspicious"
            ActivityEmptyKind.BLOCKED -> "No sites blocked yet"
            ActivityEmptyKind.PROTECTION_OFF -> "Protection is off"
        },
    )
    val message = t(
        when (kind) {
            // Android copy: the add-on runs in Firefox.
            ActivityEmptyKind.ALL -> "Suspicious sites found while you browse in Firefox will show up here."
            ActivityEmptyKind.WARNING -> "The sites you opened lately look safe. We'll let you know if anything seems off."
            ActivityEmptyKind.BLOCKED -> "Shoo blocks scam sites automatically before the page can open."
            ActivityEmptyKind.PROTECTION_OFF -> "Shoo's Firefox add-on is off, so the sites you open aren't checked."
        },
    )
    Column(
        modifier
            .fillMaxWidth()
            .padding(top = kind.topPadding.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        HalftoneShield(isOn = kind != ActivityEmptyKind.PROTECTION_OFF)
        // One TalkBack stop for the words; the pill and button stay their own.
        Column(
            Modifier
                .padding(top = 10.dp)
                .clearAndSetSemantics {
                    contentDescription = "$title. $message"
                    heading()
                },
            verticalArrangement = Arrangement.spacedBy(8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                title,
                style = activityFont(22f, FontWeight.SemiBold, tracking = -0.22f),
                color = ActivityStyle.emptyTitle,
                textAlign = TextAlign.Center,
            )
            Text(
                message,
                // Figma 140 % lines (21 pt), 296 pt wide.
                style = com.shoo.app.components.figmaTextStyle(15f, lineHeight = 21f),
                color = ActivityStyle.secondary,
                textAlign = TextAlign.Center,
                modifier = Modifier.widthIn(max = 296.dp),
            )
        }

        if (kind == ActivityEmptyKind.PROTECTION_OFF) {
            Column(
                Modifier.padding(top = 34.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                ActivityBlueButton(title = "Turn on add-on", systemImage = "safari.fill", identifier = "activity.turnOn", onClick = turnOn)
                if (offSince != null) {
                    Text(
                        offSince,
                        style = activityFont(13f, rounded = true),
                        color = ActivityStyle.secondary,
                        modifier = Modifier.semantics { testTag = "activity.offSince" },
                    )
                }
            }
        } else if (pill != null) {
            ActivityStatusPill(pill, Modifier.padding(top = 22.dp))
        }
    }
}

/** Figma "Status Pill": green dot + text on 72 % white, white hairline, soft shadow. */
@Composable
private fun ActivityStatusPill(text: String, modifier: Modifier = Modifier) {
    Row(
        modifier
            .shooShadow(ActivityStyle.pillShadow.copy(alpha = 0.05f), radius = 4.dp, y = 2.dp, shape = CapsuleShape)
            .background(Color.White.copy(alpha = 0.72f), CapsuleShape)
            .border(1.dp, Color.White, CapsuleShape)
            .padding(start = 12.dp, end = 13.dp, top = 7.dp, bottom = 7.dp)
            .clearAndSetSemantics {
                contentDescription = text
                testTag = "activity.statusPill"
            },
        horizontalArrangement = Arrangement.spacedBy(7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(7.dp).background(ActivityStyle.activeDot, CircleShape))
        Text(text, style = activityFont(13f, rounded = true), color = ActivityStyle.secondary)
    }
}

/** Figma "Button / Blue Button / Primary": blue gradient capsule, 1.5 pt stroke, white icon + label. `title`: catalog key. */
@Composable
private fun ActivityBlueButton(title: String, systemImage: String, identifier: String, onClick: () -> Unit) {
    val reduceMotion = LocalReduceMotion.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val alpha by animateFloatAsState(if (pressed) 0.8f else 1f, shooEaseOut(0.15), label = "blueAlpha")
    // Reduce Motion: the dim alone.
    val scale by animateFloatAsState(if (pressed && !reduceMotion) 0.97f else 1f, shooEaseOut(0.15), label = "blueScale")
    val density = LocalDensity.current
    // Label shadow: black 20 %, radius 2, y 4.
    val labelShadow = with(density) { Shadow(Color.Black.copy(alpha = 0.2f), Offset(0f, 4.dp.toPx()), 2.dp.toPx() * 2) }
    Row(
        Modifier
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
                this.alpha = alpha
            }
            .heightIn(min = 46.dp)
            .background(Brush.verticalGradient(listOf(ActivityStyle.blueButtonTop, ActivityStyle.blueButtonBottom)), CapsuleShape)
            .border(1.5.dp, ActivityStyle.blueButtonStroke, CapsuleShape)
            .clickable(interactionSource = interaction, indication = null, role = Role.Button, onClick = onClick)
            .semantics { testTag = identifier }
            .padding(start = 16.dp, end = 20.dp, top = 12.dp, bottom = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(22.dp), contentAlignment = Alignment.Center) {
            SfSymbol(systemImage, pointSize = 19f, tint = Color.White)
        }
        Text(
            t(title),
            style = activityFont(15f, FontWeight.SemiBold, tracking = -0.19f).copy(shadow = labelShadow),
            color = Color.White,
        )
    }
}
