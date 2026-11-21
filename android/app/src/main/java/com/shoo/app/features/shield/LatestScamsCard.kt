package com.shoo.app.features.shield

import androidx.compose.animation.core.animate
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.FlingBehavior
import androidx.compose.foundation.gestures.ScrollScope
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.figmaCardShadow
import com.shoo.app.components.hex
import com.shoo.app.components.textScale
import com.shoo.app.data.ScamCase
import com.shoo.app.features.onboarding.OnboardingTheme
import com.shoo.app.features.onboarding.onboardingFont
import com.shoo.app.support.t
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.roundToInt

/**
 * Figma "Frame 1618872186" (Pribadi/Home 1115:13601, protected/Home 1115:17238): the newest scam cases among Shoo
 * users. A red shield and the title (SF Pro Rounded 17, #6A717E), 16 pt, then the cases as 96 pt cards two to a
 * row, 8 apart; more than two scroll sideways.
 */
@Composable
fun LatestScamsCard(cases: List<ScamCase>, modifier: Modifier = Modifier) {
    Column(
        modifier.testTag("home.scamCases"),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Figma "Header": the symbol (SF Pro Semibold 16, #E5483B) 8 left of the title, 22 pt line.
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            SfSymbol(
                "exclamationmark.shield.fill",
                pointSize = 16f,
                tint = HomeTheme.tileIcon,
                modifier = Modifier.width(18.dp).clearAndSetSemantics { },
            )
            Text(
                text = t("Latest scams among Shoo users"),
                style = onboardingFont(17f, rounded = true, tracking = -0.17f, lineHeight = 22f),
                color = OnboardingTheme.bodyInk,
                modifier = Modifier
                    .weight(1f)
                    .semantics { heading() },
            )
        }
        if (isAccessibilityTextSize()) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                for (scamCase in cases) ScamCaseCard(scamCase)
            }
        } else {
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                // `containerRelativeFrame(.horizontal, count: 2, spacing: 8)`.
                val cardWidth = (maxWidth - 8.dp) / 2
                val scroll = rememberScrollState()
                val stepPx = with(LocalDensity.current) { (cardWidth + 8.dp).toPx() }
                val fling = remember(scroll, stepPx) { ViewAlignedFling(scroll, stepPx) }
                Row(
                    Modifier
                        // Room for the cards' shadow inside the clip (`.padding(.vertical, -8)` outside).
                        .verticalOutset(8.dp)
                        .horizontalScroll(scroll, flingBehavior = fling)
                        .padding(vertical = 8.dp)
                        // Every card as tall as the tallest.
                        .height(IntrinsicSize.Max),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.Top,
                ) {
                    for (scamCase in cases) {
                        ScamCaseCard(scamCase, Modifier.width(cardWidth).fillMaxHeight())
                    }
                }
            }
        }
    }
}

/**
 * Figma "Update card" (1115:17243): white, 12 pt corners, a 1 pt #E7E9ED ring, 12 pt padding (22 on the right); the case in
 * SF Pro Rounded 17 (22 pt lines, #191D2F), then when in 13 (18 pt, #564C51), 8 under it. Figma's "· Whatsapp" is left
 * out: Shoo sees the address, not where the link came from.
 */
@Composable
private fun ScamCaseCard(scamCase: ScamCase, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(12.dp)
    val language = LocalAppLanguage.current
    Column(
        modifier
            .heightIn(min = 96.dp)
            .figmaCardShadow(shape)
            .background(Color.White, shape)
            .border(1.dp, hex(0xE7E9ED), shape)
            // Figma: the text 139 wide, 12 from the left and 22 from the right.
            .padding(start = 12.dp, end = 22.dp, top = 12.dp, bottom = 12.dp)
            .semantics(mergeDescendants = true) { },
    ) {
        Text(
            text = scamCase.title.text(language.code),
            style = onboardingFont(17f, rounded = true, tracking = -0.17f, lineHeight = 22f),
            color = HomeTheme.navy,
            modifier = Modifier.fillMaxWidth(),
        )
        // VStack(spacing: 8) puts 8 on both sides of its `Spacer(minLength: 0)`.
        Spacer(Modifier.height(8.dp))
        Spacer(Modifier.weight(1f, fill = true))
        Spacer(Modifier.height(8.dp))
        ScamCaseAge(
            lastSeenAt = scamCase.lastSeenAt,
            style = onboardingFont(13f, rounded = true, tracking = -0.08f, lineHeight = 18f),
            color = HomeTheme.rowSubtitle,
        )
    }
}

/**
 * "Hari ini" / "Kemarin" / "3 hari lalu": calendar days on this phone, so a case from last night is "Kemarin".
 * A time a little ahead of the clock (server vs phone) is still today. iOS `ScamCaseAge` returns a `Text` the caller
 * styles; here the caller passes the style. `calendar` → `zone`.
 */
@Composable
fun ScamCaseAge(
    lastSeenAt: Instant,
    now: Instant = Instant.now(),
    zone: ZoneId = ZoneId.systemDefault(),
    style: TextStyle = TextStyle.Default,
    color: Color = Color.Unspecified,
    modifier: Modifier = Modifier,
) {
    val text = when (val days = scamCaseAgeDays(lastSeenAt, now, zone)) {
        0 -> t("Today")
        1 -> t("Yesterday")
        else -> t("%lld days ago", days)
    }
    Text(text = text, style = style, color = color, modifier = modifier)
}

/** `ScamCaseAge.days(from:to:calendar:)`. */
fun scamCaseAgeDays(lastSeenAt: Instant, now: Instant, zone: ZoneId = ZoneId.systemDefault()): Int {
    val start = lastSeenAt.atZone(zone).toLocalDate()
    val today = now.atZone(zone).toLocalDate()
    return ChronoUnit.DAYS.between(start, today).toInt().coerceAtLeast(0)
}

/** iOS `dynamicTypeSize.isAccessibilitySize` (AX1 and up), like HomeChrome's. */
@Composable
internal fun isAccessibilityTextSize(): Boolean = textScale() >= 1.6f

/** SwiftUI `.padding(.vertical, -d)`: the view reports `2 d` less height and draws `d` higher. */
private fun Modifier.verticalOutset(d: Dp): Modifier = layout { measurable, constraints ->
    val px = d.roundToPx()
    val placeable = measurable.measure(
        constraints.copy(
            minHeight = constraints.minHeight + 2 * px,
            maxHeight = if (constraints.hasBoundedHeight) constraints.maxHeight + 2 * px else constraints.maxHeight,
        ),
    )
    layout(placeable.width, (placeable.height - 2 * px).coerceAtLeast(0)) { placeable.place(0, -px) }
}

/** `.scrollTargetBehavior(.viewAligned)`: a fling ends with a card's leading edge at the start. */
private class ViewAlignedFling(private val scroll: ScrollState, private val step: Float) : FlingBehavior {
    override suspend fun ScrollScope.performFling(initialVelocity: Float): Float {
        if (step <= 0f) return initialVelocity
        val position = scroll.value / step
        val page = when {
            initialVelocity > 300f -> ceil(position)
            initialVelocity < -300f -> floor(position)
            else -> position.roundToInt().toFloat()
        }
        val target = (page * step).coerceIn(0f, scroll.maxValue.toFloat())
        val distance = target - scroll.value
        if (abs(distance) < 0.5f) return 0f
        var last = 0f
        animate(initialValue = 0f, targetValue = distance, initialVelocity = initialVelocity) { value, _ ->
            last += scrollBy(value - last)
        }
        return 0f
    }
}
