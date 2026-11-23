package com.shoo.app.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.shoo.app.R
import java.util.concurrent.ConcurrentHashMap

/**
 * The one font every Figma-styled text in the app goes through (`onboardingFont`, `profileFont`, `activityFont`,
 * and Home via `onboardingFont`).
 *
 * iOS draws SF Pro with its optical-size axis pinned to the top (the static "SF Pro Display" Figma uses). Android
 * may not ship SF Pro (Apple license), so this is Inter's variable font with the same idea: `opsz` 32 (Inter's
 * display cut) for `DISPLAY`, 14 (text cut) for `TEXT`, and the point size for `SF_PRO`.
 * iOS: SF Pro Rounded has no Inter counterpart; `rounded` texts use the same Inter.
 */
object FigmaFont {
    /** The Figma font family a text layer uses. */
    enum class Family {
        /** "SF Pro Display" / "SF Pro Rounded": almost every text in the file. */
        DISPLAY,
        /** The static "SF Pro Text" (name field, "Lewati", "Terkendala? Tonton Tutorial", the invite code). */
        TEXT,
        /** The variable "SF Pro": optical size follows the point size, like the system font. */
        SF_PRO,
    }

    /** Top of Inter's `opsz` axis (14–32). */
    const val displayOpticalSize = 32f
    /** Bottom of the axis. */
    const val textOpticalSize = 14f
    /** Static "SF Pro Text" runs this fraction of the point size wider per character (iOS tracking table). */
    const val textExtraTracking = 0.0254f

    private val families = ConcurrentHashMap<Long, FontFamily>()

    /** Inter at `weight` and optical size `opsz`, one `FontFamily` per pair (they are cached by Compose too). */
    @OptIn(ExperimentalTextApi::class)
    fun family(weight: FontWeight, opsz: Float): FontFamily {
        val key = (weight.weight.toLong() shl 32) or opsz.toBits().toLong().and(0xFFFFFFFFL)
        return families.getOrPut(key) {
            FontFamily(
                Font(
                    R.font.inter_variable,
                    weight = weight,
                    variationSettings = FontVariation.Settings(
                        FontVariation.weight(weight.weight),
                        FontVariation.Setting("opsz", opsz),
                    ),
                ),
            )
        }
    }

    fun opticalSize(family: Family, size: Float): Float = when (family) {
        Family.DISPLAY -> displayOpticalSize
        Family.TEXT -> textOpticalSize
        Family.SF_PRO -> size.coerceIn(textOpticalSize, displayOpticalSize)
    }

    /** What Bold Text turns each weight into (iOS `Font.Weight.bolder`). */
    fun bolder(weight: FontWeight): FontWeight = when (weight.weight) {
        in 0..199 -> FontWeight.Light
        in 200..299 -> FontWeight.Normal
        in 300..399 -> FontWeight.Medium
        in 400..499 -> FontWeight.SemiBold
        in 500..699 -> FontWeight.Bold
        in 700..799 -> FontWeight.ExtraBold
        else -> FontWeight.Black
    }
}

/**
 * Figma text at `size` pt that follows the app's text size (`LocalTextSizeLevel`, on top of the phone's font scale)
 * and Bold Text (`LocalBoldText`). Swift `.figmaFont(size, weight:, design:, tracking:, family:)` +
 * `.figmaLineHeight(points)`.
 *
 * - `tracking`: Figma / SwiftUI letter spacing in pt (→ em = tracking / size, so it scales with the text).
 * - `lineHeight`: Figma line height in pt (`fontSize × percent / 100`), glyphs centred in the line like Figma.
 * - `rounded`: SF Pro Rounded in Figma; iOS only (see `FigmaFont`).
 */
@Composable
@ReadOnlyComposable
fun figmaTextStyle(
    size: Float,
    weight: FontWeight = FontWeight.Normal,
    rounded: Boolean = false,
    tracking: Float? = null,
    lineHeight: Float? = null,
    family: FigmaFont.Family = FigmaFont.Family.DISPLAY,
): TextStyle {
    val scale = LocalTextSizeLevel.current.fontScale
    val bold = LocalBoldText.current && family != FigmaFont.Family.SF_PRO
    return figmaTextStyleFixed(size, weight, tracking, lineHeight, family, scale, bold)
}

/** Non-composable form (fixed scale, no Bold Text), for code that has no composition (Canvas text, tests). */
fun figmaTextStyleFixed(
    size: Float,
    weight: FontWeight = FontWeight.Normal,
    tracking: Float? = null,
    lineHeight: Float? = null,
    family: FigmaFont.Family = FigmaFont.Family.DISPLAY,
    scale: Float = 1f,
    bold: Boolean = false,
): TextStyle {
    val resolvedWeight = if (bold) FigmaFont.bolder(weight) else weight
    val extra = if (family == FigmaFont.Family.TEXT) FigmaFont.textExtraTracking else 0f
    val letterSpacing: TextUnit = if (tracking != null || extra != 0f) {
        ((tracking ?: 0f) / size + extra).em
    } else {
        TextUnit.Unspecified
    }
    return TextStyle(
        fontFamily = FigmaFont.family(resolvedWeight, FigmaFont.opticalSize(family, size)),
        fontWeight = resolvedWeight,
        fontSize = (size * scale).sp,
        letterSpacing = letterSpacing,
        lineHeight = if (lineHeight != null) (lineHeight * scale).sp else TextUnit.Unspecified,
        lineHeightStyle = if (lineHeight != null) {
            LineHeightStyle(alignment = LineHeightStyle.Alignment.Center, trim = LineHeightStyle.Trim.None)
        } else {
            null
        },
    )
}

/**
 * SwiftUI's built-in text styles (`.font(.body)`, `.font(.title2.bold())`) at their default (Large) sizes, in the
 * system optical size like `.system(.body)`.
 */
enum class SystemTextStyle(val size: Float, val lineHeight: Float, val defaultWeight: FontWeight) {
    LARGE_TITLE(34f, 41f, FontWeight.Normal),
    TITLE(28f, 34f, FontWeight.Normal),
    TITLE2(22f, 28f, FontWeight.Normal),
    TITLE3(20f, 25f, FontWeight.Normal),
    HEADLINE(17f, 22f, FontWeight.SemiBold),
    BODY(17f, 22f, FontWeight.Normal),
    CALLOUT(16f, 21f, FontWeight.Normal),
    SUBHEADLINE(15f, 20f, FontWeight.Normal),
    FOOTNOTE(13f, 18f, FontWeight.Normal),
    CAPTION(12f, 16f, FontWeight.Normal),
    CAPTION2(11f, 13f, FontWeight.Normal),
}

/** `.font(.body)`, `.font(.caption.weight(.semibold))`, `.font(.title2.bold())`. */
@Composable
@ReadOnlyComposable
fun systemTextStyle(style: SystemTextStyle, weight: FontWeight = style.defaultWeight, rounded: Boolean = false): TextStyle =
    figmaTextStyle(style.size, weight, rounded, family = FigmaFont.Family.SF_PRO)

/** `.font(.system(size:weight:design:))`: the plain system font at a fixed size (still follows the text size). */
@Composable
@ReadOnlyComposable
fun systemFont(size: Float, weight: FontWeight = FontWeight.Normal, rounded: Boolean = false): TextStyle =
    figmaTextStyle(size, weight, rounded, family = FigmaFont.Family.SF_PRO)

/**
 * `@ScaledMetric`: a length that grows with the app's text size (`LocalTextSizeLevel`) and the phone's font scale,
 * at most `maxScale` times.
 */
@Composable
@ReadOnlyComposable
fun scaled(value: Float, maxScale: Float = Float.MAX_VALUE): Dp {
    val factor = (LocalTextSizeLevel.current.fontScale * androidx.compose.ui.platform.LocalDensity.current.fontScale)
        .coerceAtMost(maxScale)
    return (value * factor).dp
}

/** The text scale `@ScaledMetric(relativeTo:) var x: CGFloat = 1` reads (1 at the default size). */
@Composable
@ReadOnlyComposable
fun textScale(): Float =
    LocalTextSizeLevel.current.fontScale * androidx.compose.ui.platform.LocalDensity.current.fontScale
