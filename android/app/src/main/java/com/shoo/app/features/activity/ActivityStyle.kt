package com.shoo.app.features.activity

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.shoo.app.components.AvatarRing
import com.shoo.app.components.AvatarView
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.LocalReduceGlass
import com.shoo.app.components.ScanBadge
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.figmaTextStyle
import com.shoo.app.components.hex
import com.shoo.app.components.shooShadow
import com.shoo.app.data.FamilyMember
import com.shoo.app.support.t

/**
 * Figma "Aktivitas – Profil Pribadi / Guardian" + "Picker" (PR-05, GD-05): colours, type and the pieces of the
 * Activity list. Values are the Figma ones. Light only, like Profile (PF-01): dark mode is a backlog issue.
 */
object ActivityStyle {
    val backgroundTop = hex(0xDFEFFC)
    val backgroundMiddle = hex(0xE6F2FC)
    val background = hex(0xF5FAFC)
    val title = hex(0x191C25)
    val ink = hex(0x191D2F)
    val secondary = hex(0x6A717E)
    val time = hex(0x564C51)
    val separator = hex(0xC7C7CE)
    val segmentTrack = hex(0x767680, 0.12f)
    val iconFill = hex(0xF3F6F8)
    val iconStroke = hex(0xE2E8F0)
    val menuText = hex(0x1A1A1A)
    // Empty states (Figma 480:5490 …).
    val emptyTitle = hex(0x151617)
    val activeDot = hex(0x34C759)
    val pillShadow = hex(0x1A1C2E)
    val blueButtonTop = hex(0x68CDFA)
    val blueButtonBottom = hex(0x136CB7)
    val blueButtonStroke = hex(0x0098D7)

    /** Screen side margin; cards are 354 wide on the 402 pt Figma frame. */
    val margin: Dp = 24.dp

    /** Figma's thin white rim on the people's avatars (rows, the person picker, Detail's owner chip). */
    val avatarRing = AvatarRing(color = Color.White.copy(alpha = 0.5f))

    fun hex(value: Int): Color = com.shoo.app.components.hex(value)
}

// MARK: Type

/** Figma sizes that follow the text size (shared `FigmaFont`). Swift `.activityFont(size, weight, rounded:, tracking:)`. */
@Composable
fun activityFont(
    size: Float,
    weight: FontWeight = FontWeight.Normal,
    rounded: Boolean = false,
    tracking: Float = 0f,
): TextStyle = figmaTextStyle(size, weight, rounded, tracking = tracking)

/**
 * Figma "Liquid Glass – Regular": the real glass on iOS 26, a material before it. Android can't blur what lies behind
 * a view, so it is a frosted white with a hairline and the material's soft shadow (black 8 %, radius 12, y 4).
 * "Kurangi efek kaca": solid white.
 */
fun Modifier.activityGlass(shape: Shape): Modifier = composed {
    if (LocalReduceGlass.current) {
        this.background(Color.White, shape)
    } else {
        this
            .shooShadow(Color.Black.copy(alpha = 0.08f), radius = 12.dp, y = 4.dp, shape = shape)
            .background(Color.White.copy(alpha = 0.82f), shape)
            .border(0.5.dp, Color.White.copy(alpha = 0.5f), shape)
    }
}

// MARK: Background

/** The light blue wash at the top fading into the page grey (Figma frame fill). */
@Composable
fun ActivityBackground(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize().background(ActivityStyle.background)) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(200.dp)
                .background(
                    Brush.verticalGradient(
                        0f to ActivityStyle.backgroundTop,
                        0.3f to ActivityStyle.backgroundMiddle,
                        1f to ActivityStyle.background,
                    ),
                ),
        )
    }
}

// MARK: Badge

/** Catalog key of the badge's title ("Waspada" / "Diblokir", and the guardian's verdicts). */
val ScanBadge.activityTitle: String
    get() = when (this) {
        ScanBadge.WARNING -> "activity.warning"
        ScanBadge.BLOCKED -> "Blocked"
        ScanBadge.VERIFIED_SCAM -> "Verified scam"
        ScanBadge.MARKED_SAFE -> "Marked safe"
    }

private data class BadgeColors(val icon: Color, val text: Color, val fill: Color, val stroke: Color)

/**
 * "Waspada" / "Diblokir" (and the guardian's "Verified scam" / "Marked safe") at the top right of a row (Figma
 * "Button" instance). The text is always there, so colour is never the only signal.
 */
@Composable
fun ActivityBadge(badge: ScanBadge, modifier: Modifier = Modifier) {
    val symbol = when (badge) {
        ScanBadge.WARNING, ScanBadge.BLOCKED -> "exclamationmark.circle.fill"
        ScanBadge.VERIFIED_SCAM -> "xmark.circle.fill"
        ScanBadge.MARKED_SAFE -> "checkmark.circle.fill"
    }
    val colors = when (badge) {
        ScanBadge.WARNING -> BadgeColors(hex(0xD67D00), hex(0xD67D00), hex(0xFFF8EF), hex(0xFFE1B6))
        ScanBadge.BLOCKED, ScanBadge.VERIFIED_SCAM -> BadgeColors(hex(0xBB1616), hex(0xBB1616), hex(0xFFF4F4), hex(0xFFCDCD))
        ScanBadge.MARKED_SAFE -> BadgeColors(hex(0x34C759), hex(0x1B7F3A), hex(0xE8F8EE), hex(0xBFEBCD))
    }
    Row(
        modifier
            .wrapContentSize()
            .heightIn(min = 23.dp)
            .background(colors.fill, CapsuleShape)
            // Figma: 0.75 pt inside stroke.
            .border(0.75.dp, colors.stroke, CapsuleShape)
            .padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SfSymbol(
            name = symbol,
            pointSize = 10f,
            tint = colors.icon,
            modifier = Modifier.clearAndSetSemantics { },
        )
        Text(
            text = t(badge.activityTitle),
            style = activityFont(13f, tracking = -0.1625f),
            color = colors.text,
            maxLines = 1,
            overflow = TextOverflow.Clip,
        )
    }
}

// MARK: Avatars

/** Up to three overlapping avatars, each half its size to the right of the previous (Figma "Avatar Stack"). */
@Composable
fun ActivityAvatarStack(people: List<FamilyMember>, modifier: Modifier = Modifier, size: Dp = 24.dp) {
    Row(
        modifier.clearAndSetSemantics { },
        horizontalArrangement = Arrangement.spacedBy(-size / 2),
    ) {
        people.take(3).forEachIndexed { index, member ->
            AvatarView(
                id = member.avatarId,
                size = size,
                ring = ActivityStyle.avatarRing,
                modifier = Modifier.zIndex(-index.toFloat()),
            )
        }
    }
}
