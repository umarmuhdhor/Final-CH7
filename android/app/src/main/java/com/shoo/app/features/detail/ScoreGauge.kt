package com.shoo.app.features.detail

import android.graphics.BlurMaskFilter
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.data.ScanStatus
import com.shoo.app.features.activity.activityFont
import com.shoo.app.support.Formatters
import com.shoo.app.support.t
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

/** The gauge's frame: 370 × 237 pt (Figma). `FittedScoreGauge` on Home scales it to the card. */
val ScoreGaugeSize: DpSize = DpSize(370.dp, 237.dp)

/**
 * Figma "Scam Score Gauge" (Detail score card, 416:9268 / 416:9481): a 205° band with a halo, the score filled in red
 * (blocked) or orange (warning), white dots on the fill, nine ticks, a needle at the tip, the percentage and the label
 * ("Bahaya" / "Risiko Tinggi"). Values are the Figma ones, in pt; the drawing turns them into pixels.
 */
object ScoreGauge {
    val size: DpSize get() = ScoreGaugeSize

    /** Centre and radii of the band (Track 298 pt at 36, 28; Halo 316 pt). */
    internal const val centerX = 185f
    internal const val centerY = 177f
    internal const val outer = 149f
    internal const val inner = 100f
    internal const val haloOuter = 158f
    /** The band runs 167.4° → 372.6° (clockwise from 3 o'clock); the score maps 0–100 onto 180° → 360°. */
    internal const val bandStart = 167.4
    internal const val bandEnd = 372.6

    /** Fill tip: 180° + 1.8° per point (Figma: 92 → 345.6°, 72 → 309.6°). */
    fun tipAngle(score: Int): Double = 180 + score.coerceIn(0, 100) * 1.8

    /** Figma "Dots strong" / "Dots soft" of the 92 % gauge (centres, r 1.2); a lower score shows fewer. */
    internal val strongDots: List<Offset> = listOf(
        231 to 53, 246 to 53, 126 to 68, 141 to 68, 186 to 68, 216 to 68, 231 to 68, 261 to 83, 96 to 98, 276 to 98, 306 to 113,
    ).map { Offset(it.first.toFloat(), it.second.toFloat()) }
    internal val softDots: List<Offset> = listOf(
        126 to 53, 141 to 53, 156 to 53, 171 to 53, 186 to 53, 201 to 53, 216 to 53, 111 to 68, 246 to 68, 261 to 68,
        126 to 83, 111 to 98, 261 to 98, 291 to 98, 66 to 113, 276 to 113,
    ).map { Offset(it.first.toFloat(), it.second.toFloat()) }

    internal fun angle(point: Offset): Double {
        val degrees = Math.toDegrees(atan2((point.y - centerY).toDouble(), (point.x - centerX).toDouble()))
        return if (degrees < 90) degrees + 360 else degrees
    }
}

@Composable
fun ScoreGauge(score: Int, status: ScanStatus, modifier: Modifier = Modifier) {
    val language = LocalAppLanguage.current
    val palette = if (status == ScanStatus.BLOCKED) GaugePalette.red else GaugePalette.orange
    val tip = ScoreGauge.tipAngle(score)
    val label = t(if (status == ScanStatus.BLOCKED) "Danger" else "detail.highRisk")
    Box(modifier.size(ScoreGaugeSize)) {
        Canvas(Modifier.fillMaxSize()) { drawGauge(palette, tip) }
        Column(Modifier.width(ScoreGaugeSize.width), horizontalAlignment = Alignment.CenterHorizontally) {
            // iOS `.minimumScaleFactor(0.6)`: both texts fit the 370 pt frame at every app text size this screen allows.
            Box(Modifier.padding(top = 116.dp).height(57.dp), contentAlignment = Alignment.Center) {
                Text(
                    Formatters.percent(score, language),
                    style = activityFont(48f, tracking = -0.48f),
                    color = DetailStyle.ink,
                    maxLines = 1,
                    softWrap = false,
                    textAlign = TextAlign.Center,
                )
            }
            Text(
                label,
                style = activityFont(20f, FontWeight.Medium, tracking = -0.1f),
                color = DetailStyle.ink,
                maxLines = 1,
                softWrap = false,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 7.dp),
            )
        }
    }
}

private class GaugePalette(
    val halo: Color,
    val track: List<Color>,
    val progress: List<Color>,
    val innerShade: Color,
    val glow: Color,
) {
    companion object {
        val red = GaugePalette(
            halo = DetailStyle.hex(0xFBE5E4),
            track = listOf(DetailStyle.hex(0xF9D9D6), DetailStyle.hex(0xFDEEEC)),
            progress = listOf(0xC42B1C, 0xE5483B, 0xFF7A6B, 0xE5483B, 0xBF3424).map(DetailStyle::hex),
            innerShade = DetailStyle.hex(0x8A1C12),
            glow = DetailStyle.hex(0xE5473B),
        )
        val orange = GaugePalette(
            halo = DetailStyle.hex(0xFFF0DB),
            track = listOf(DetailStyle.hex(0xFFE6C4), DetailStyle.hex(0xFFF4E3)),
            progress = listOf(0xEB8900, 0xFF9500, 0xFFB752, 0xFF9500, 0xE58600).map(DetailStyle::hex),
            innerShade = DetailStyle.hex(0xA66100),
            glow = DetailStyle.hex(0xFF9400),
        )
    }
}

// MARK: Drawing (Figma pt × density = px)

/** SwiftUI blur / shadow radius → Android blur radius (Skia: sigma = 0.57735 × radius + 0.5). */
private fun DrawScope.blurPx(radius: Float): Float = ((radius.dp.toPx() - 0.5f) / 0.57735f).coerceAtLeast(0.01f)

private fun DrawScope.pt(value: Float): Float = value.dp.toPx()

private fun DrawScope.point(angle: Double, radius: Float): Offset {
    val radians = Math.toRadians(angle)
    return Offset(
        pt(ScoreGauge.centerX + radius * cos(radians).toFloat()),
        pt(ScoreGauge.centerY + radius * sin(radians).toFloat()),
    )
}

/** A ring segment between two radii, `from` → `to` degrees clockwise from 3 o'clock. */
private fun DrawScope.band(inner: Float, outer: Float, from: Double, to: Double): Path {
    val path = Path()
    if (to <= from) return path
    val center = Offset(pt(ScoreGauge.centerX), pt(ScoreGauge.centerY))
    val sweep = (to - from).toFloat()
    path.arcTo(Rect(center, pt(outer)), from.toFloat(), sweep, forceMoveTo = true)
    path.arcTo(Rect(center, pt(inner)), to.toFloat(), -sweep, forceMoveTo = false)
    path.close()
    return path
}

private fun DrawScope.radial(colors: List<Color>, locations: List<Float>): Brush = Brush.radialGradient(
    *locations.zip(colors).toTypedArray(),
    center = Offset(pt(ScoreGauge.centerX), pt(ScoreGauge.centerY)),
    radius = pt(ScoreGauge.outer),
)

/**
 * Figma lays a white top-to-bottom gradient over each ellipse so the band's ends fade into the card (stops 0 / 0.26
 * clear, 0.45 at 55 %, 0.56 opaque). As a mask (`DstIn` on its own layer) it works on any card colour.
 */
private inline fun DrawScope.faded(top: Float, height: Float, strength: Float, block: DrawScope.() -> Unit) {
    val frameHeight = ScoreGaugeSize.height.value
    val start = top / frameHeight
    val span = height / frameHeight
    val margin = pt(30f)
    val bounds = Rect(-margin, -margin, size.width + margin, size.height + margin)
    drawIntoCanvas { it.saveLayer(bounds, Paint()) }
    block()
    drawRect(
        Brush.verticalGradient(
            start + 0.26f * span to Color.Black,
            start + 0.45f * span to Color.Black.copy(alpha = 1f - 0.55f * strength),
            start + 0.56f * span to Color.Black.copy(alpha = 1f - strength),
            startY = 0f,
            endY = size.height,
        ),
        topLeft = bounds.topLeft,
        size = bounds.size,
        blendMode = BlendMode.DstIn,
    )
    drawIntoCanvas { it.restore() }
}

/** Fills `path` with `color`, blurred by `radius` (SwiftUI `.blur(radius:)`). */
private fun DrawScope.blurredFill(path: Path, color: Color, radius: Float) {
    drawIntoCanvas { canvas ->
        val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color.toArgb()
            maskFilter = BlurMaskFilter(blurPx(radius), BlurMaskFilter.Blur.NORMAL)
        }
        canvas.nativeCanvas.drawPath(path.asAndroidPath(), paint)
    }
}

/** SwiftUI `.shadow(.inner(color:radius:x:y:))` on `shape`. */
private fun DrawScope.innerShadow(shape: Path, color: Color, radius: Float, x: Float, y: Float) {
    val margin = pt(60f)
    val outside = Path().apply {
        fillType = PathFillType.EvenOdd
        addRect(Rect(-margin, -margin, size.width + margin, size.height + margin))
        addPath(shape)
        translate(Offset(pt(x), pt(y)))
    }
    clipPath(shape) { blurredFill(outside, color, radius) }
}

private fun DrawScope.drawGauge(palette: GaugePalette, tip: Double) {
    // Halo: 9 pt rim outside the band, blur 3.
    faded(top = 19f, height = 316f, strength = 1f) {
        blurredFill(band(ScoreGauge.outer, ScoreGauge.haloOuter, ScoreGauge.bandStart, ScoreGauge.bandEnd), palette.halo, 1.5f)
    }
    // Track.
    faded(top = 28f, height = 298f, strength = 1f) {
        drawPath(
            band(ScoreGauge.inner, ScoreGauge.outer, ScoreGauge.bandStart, ScoreGauge.bandEnd),
            radial(palette.track, listOf(0.67f, 1f)),
        )
    }
    // Progress, with its coloured drop shadow, inner light and inner shade.
    val progress = band(ScoreGauge.inner, ScoreGauge.outer, ScoreGauge.bandStart, tip)
    if (!progress.isEmpty) {
        faded(top = 28f, height = 298f, strength = 0.45f) {
            drawIntoCanvas { canvas ->
                val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                    color = palette.progress[1].toArgb()
                    setShadowLayer(blurPx(10.65f), 0f, pt(8.5f), palette.glow.copy(alpha = 0.25f).toArgb())
                }
                canvas.nativeCanvas.drawPath(progress.asAndroidPath(), paint)
            }
            drawPath(progress, radial(palette.progress, listOf(0.68f, 0.76f, 0.86f, 0.95f, 1f)))
            innerShadow(progress, Color.White.copy(alpha = 0.45f), 4.25f, -4.3f, -4.3f)
            innerShadow(progress, palette.innerShade.copy(alpha = 0.35f), 5.3f, 4.3f, 6.4f)
        }
    }
    // White dots on the fill, only where the fill reaches.
    for ((dots, opacity) in listOf(ScoreGauge.strongDots to 0.95f, ScoreGauge.softDots to 0.55f)) {
        for (dot in dots) {
            if (ScoreGauge.angle(dot) > tip - 6) continue
            drawCircle(Color.White.copy(alpha = opacity), radius = pt(1.2f), center = Offset(pt(dot.x), pt(dot.y)))
        }
    }
    // Nine ticks every 22.5° from 180° to 360°, 7 × 1.8 pt between r 105 and 112.
    val opacities = listOf(0.18f, 0.34f, 0.48f, 0.57f, 0.6f, 0.57f, 0.48f, 0.34f, 0.18f)
    opacities.forEachIndexed { index, opacity ->
        radialBar(180 + index * 22.5, 105f, 112f, 1.8f, DetailStyle.tick.copy(alpha = opacity))
    }
    // 24 × 3 pt needle across the inner edge (r 99 → 123), at the fill's tip.
    radialBar(tip, 99f, 123f, 3f, DetailStyle.needle)
}

private fun DrawScope.radialBar(angle: Double, from: Float, to: Float, thickness: Float, color: Color) {
    val start = point(angle, from)
    rotate(angle.toFloat(), pivot = start) {
        drawRoundRect(
            color,
            topLeft = Offset(start.x, start.y - pt(thickness) / 2),
            size = Size(pt(to - from), pt(thickness)),
            cornerRadius = CornerRadius(pt(thickness) / 2),
        )
    }
}
