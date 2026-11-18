package com.shoo.app.components

import android.os.Build
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp

/**
 * Core colours per screen: blue (Activity, own Home), teal (Family Home), orange (a family site waits), amber / red
 * (own Home after a warning / a block), crimson (a blocked family site waits), red alert ("!" in the dots: the blocked
 * site waiting on Guardian Home, Figma 1382:3248).
 */
enum class HalftoneShieldTint { BLUE, TEAL, ORANGE, AMBER, RED, CRIMSON, RED_ALERT }

/** Figma "Ilustrasi": 220 × 176; the 184 × 201 shield frame sits at (18, −13) and overflows it (`HalftoneShield.size`). */
val HalftoneShieldSize = DpSize(220.dp, 176.dp)

/**
 * Figma "Shield Kaca Halftone" (Activity empty states, node 480:5502): a glass shield over a blue core with a halftone
 * dot pattern. On: the glow breathes, a light wave runs up the dots and a shine sweeps the glass. Off ("Perlindungan
 * sedang mati", node 480:5592): grey with a power symbol in the dots, still. Reduce Motion keeps the On look without
 * movement. Drawn in one Canvas; it draws outside its 220 × 176 bounds like the iOS frame.
 * iOS: blurs and inner shadows use the paint's shadow layer, which Android 8.x (API 26–27) can't draw on shapes.
 */
@Composable
fun HalftoneShield(
    modifier: Modifier = Modifier,
    isOn: Boolean = true,
    tint: HalftoneShieldTint = HalftoneShieldTint.BLUE,
) {
    val reduceMotion = LocalReduceMotion.current
    val moving = isOn && !reduceMotion
    var time by remember { mutableDoubleStateOf(0.0) }
    var running by remember { mutableStateOf(false) }
    LaunchedEffect(moving) {
        running = moving
        if (!moving) return@LaunchedEffect
        while (true) {
            withFrameNanos { nanos -> time = nanos / 1_000_000_000.0 }
        }
    }
    val palette = if (isOn) ShieldPalette.palette(tint) else ShieldPalette.off
    Canvas(
        modifier
            .size(HalftoneShieldSize)
            .clearAndSetSemantics { },
    ) {
        // Points → pixels: the Figma frame is drawn in pt and scaled once.
        scale(density, density, pivot = Offset.Zero) {
            translate(18f, -13f) {
                drawShieldLayers(palette, if (moving && running) time else null, density)
            }
        }
    }
}

// MARK: Layers

/** 0…1, slow breath of the glow (2.4 s in, 2.4 s out). 0.5 when still. */
private fun breath(time: Double?): Float =
    if (time == null) 0.5f else ((1 - cos(time * PI / 2.4)) / 2).toFloat()

/** All layers in the 184 × 201.33 pt shield frame. The scope is in pt (scaled by `density`). */
private fun DrawScope.drawShieldLayers(palette: ShieldPalette, time: Double?, density: Float) {
    val breath = breath(time)
    // Shadow-layer radii are in device pixels; this scope is scaled by `density`.
    fun px(points: Float) = points * density

    // Glow: 114 × 109 ellipse, 10 % fill, 40 blur. `.position` is the centre.
    run {
        val scale = 0.96f + 0.08f * breath
        val w = 114.4f * scale
        val h = 109.2f * scale
        val center = Offset(35f + 57.2f, 61f + 54.6f)
        blurredShape(
            Offset(center.x - w / 2, center.y - h / 2), Size(w, h), EllipseShape,
            palette.glow.copy(alpha = 0.1f + 0.06f * breath), px(20f),
        )
    }

    // Kaca shadow: the big soft glow under the glass (y 16, blur 30, 35 %), drawn as its own blurred shape.
    blurredShape(
        Offset(40f, 40f + 16f), Size(104f, 121.33f), GlassShieldShape,
        palette.glow.copy(alpha = 0.27f + 0.16f * breath), px(15f + 4f * breath),
    )

    // Core: 85 × 99, gradient, 1 pt stroke, two inner shadows.
    run {
        val topLeft = Offset(49f, 55f)
        val size = Size(85.28f, 99.49f)
        val path = glassShieldPath(topLeft, size)
        drawPath(path, Brush.verticalGradient(listOf(palette.coreTop, palette.coreBottom), topLeft.y, topLeft.y + size.height))
        innerShadow(path, Color.White.copy(alpha = 0.55f), px(4f), yPx = px(4f))
        innerShadow(path, palette.glow.copy(alpha = 0.45f), px(7f), yPx = px(-6f))
        drawPath(path, palette.coreStroke.copy(alpha = 0.9f), style = Stroke(1f))
    }

    // Titik halftone: 70.7 × 86.8 at (56, 60).
    translate(49f + 7f, 55f + 5f) {
        drawHalftoneDots(palette.dots, palette.glow, time, density)
    }

    // Kaca: 104 × 121 glass with a 2 pt gradient stroke and a small inner light.
    run {
        val topLeft = Offset(40f, 40f)
        val size = Size(104f, 121.33f)
        val path = glassShieldPath(topLeft, size)
        val start = topLeft
        val end = Offset(topLeft.x + size.width, topLeft.y + size.height)
        drawPath(
            path,
            Brush.linearGradient(
                0f to Color.White.copy(alpha = 0.42f),
                0.45f to Color.White.copy(alpha = 0.12f),
                1f to Color.White.copy(alpha = 0.22f),
                start = start, end = end,
            ),
        )
        innerShadow(path, Color.White.copy(alpha = 0.5f), px(1.5f), yPx = px(2f))
        drawPath(
            path,
            Brush.linearGradient(
                0f to Color.White.copy(alpha = 0.95f),
                0.5f to Color.White.copy(alpha = 0.25f),
                1f to Color.White.copy(alpha = 0.7f),
                start = start, end = end,
            ),
            style = Stroke(2f),
        )
        clipPath(path) { drawGlassSweep(time, topLeft, size) }
    }

    // Kilau: 44 × 19 white highlight, 55 %, blur 8.
    blurredShape(Offset(55f, 57f), Size(43.68f, 19.41f), EllipseShape, Color.White.copy(alpha = 0.55f), px(4f))
}

/** A light streak that crosses the glass every 5 s (0.9 s pass, then rest). */
private fun DrawScope.drawGlassSweep(time: Double?, topLeft: Offset, size: Size) {
    if (time == null) return
    val period = 5.0
    val pass = 0.9
    val phase = ((time % period) / pass).toFloat()
    if (phase >= 1f) return
    val width = size.width
    val bandWidth = width * 0.45f
    val bandHeight = size.height * 1.6f
    // SwiftUI: the band sits at the top-left of the glass, rotates about its own centre, then moves.
    val x = topLeft.x - width * 0.6f + phase * width * 1.7f
    val y = topLeft.y - size.height * 0.3f
    translate(x, y) {
        rotate(20f, pivot = Offset(bandWidth / 2, bandHeight / 2)) {
            drawRect(
                Brush.horizontalGradient(
                    listOf(Color.White.copy(alpha = 0f), Color.White.copy(alpha = 0.45f), Color.White.copy(alpha = 0f)),
                    startX = 0f, endX = bandWidth,
                ),
                size = Size(bandWidth, bandHeight),
                blendMode = BlendMode.Plus,
            )
        }
    }
}

// MARK: Dots

private const val DOT_PITCH = 3.8875f
private val DOT_ORIGIN = Offset(0.45f, 0.35f)

/** White at the top to #D7F6FF at the bottom. */
private fun dotShade(fraction: Float): Color {
    val f = fraction.coerceIn(0f, 1f)
    return Color(red = 1 - f * (1 - 0xD7 / 255f), green = 1 - f * (1 - 0xF6 / 255f), blue = 1f)
}

/**
 * "Titik halftone": 335 dots on a 3.89 pt grid, radii from Figma. White → #D7F6FF top to bottom, with the two Figma
 * drop shadows. While moving, a soft wave of light runs from bottom to top.
 */
private fun DrawScope.drawHalftoneDots(rows: List<FloatArray>, glow: Color, time: Double?, density: Float) {
    val height = (rows.size - 1) * DOT_PITCH
    // Wave centre runs from below the dots to above them in 2.6 s, then rests 1.4 s.
    var waveY: Float? = null
    if (time != null) {
        val t = ((time % 4.0) / 2.6).toFloat()
        if (t < 1f) waveY = height + 12f - t * (height + 24f)
    }
    val all = Path()
    val dots = ArrayList<Triple<Offset, Float, Color>>(340)
    rows.forEachIndexed { row, radii ->
        val y = DOT_ORIGIN.y + row * DOT_PITCH
        val shade = dotShade(y / maxOf(height, 1f))
        var boost = 0f
        if (waveY != null) {
            val distance = (y - waveY) / 9f
            boost = exp(-distance * distance)
        }
        radii.forEachIndexed { column, radius ->
            if (radius > 0f) {
                val x = DOT_ORIGIN.x + column * DOT_PITCH
                val r = radius * (1 + 0.35f * boost)
                all.addOval(Rect(x - r, y - r, x + r, y + r))
                dots.add(Triple(Offset(x, y), r, shade.copy(alpha = 0.85f + 0.15f * boost)))
            }
        }
    }
    // The two Canvas shadow filters (glow 50 % y 1 blur 1.5, white 45 % blur 2.5), cast by all dots at once.
    castShadow(all, Color.White.copy(alpha = 0.45f), 1.25f * density, 0f)
    castShadow(all, glow.copy(alpha = 0.5f), 0.75f * density, 1f * density)
    for ((center, r, color) in dots) drawCircle(color, r, center)
}

// MARK: Blur and shadow helpers (paint shadow layer, hardware from API 28)

private val EllipseShape: Shape = GenericShape { size, _ -> addOval(Rect(Offset.Zero, size)) }

/** `.blur(radius:)` on a filled shape: only its Gaussian copy is drawn (transparent paint, shadow at 0, 0). */
private fun DrawScope.blurredShape(topLeft: Offset, size: Size, shape: Shape, color: Color, radiusPx: Float) {
    val outline = shape.createOutline(size, LayoutDirection.Ltr, Density(1f))
    val path = Path().apply {
        when (outline) {
            is Outline.Generic -> addPath(outline.path)
            is Outline.Rectangle -> addRect(outline.rect)
            is Outline.Rounded -> addRoundRect(outline.roundRect)
        }
        translate(topLeft)
    }
    castShadow(path, color, radiusPx, 0f)
}

/**
 * Draws only the Gaussian shadow of `path` (sigma `radiusPx`, SwiftUI radius, in pixels) offset by `yPx` pixels.
 * The scope is scaled by `density` (pt units), so the path is scaled up and drawn on an unscaled canvas: the blur and
 * offset are then plain pixels whether or not the shadow layer follows the canvas matrix.
 */
private fun DrawScope.castShadow(path: Path, color: Color, radiusPx: Float, yPx: Float) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || color.alpha <= 0f) return
    val blur = ((radiusPx - 0.5f) / 0.57735f).coerceAtLeast(0.01f)
    val shadowColor = color.copy(alpha = color.alpha.coerceAtMost(0.996f)).toArgb()
    val d = density
    val scaled = android.graphics.Path(path.asAndroidPath()).apply {
        transform(android.graphics.Matrix().apply { setScale(d, d) })
    }
    drawIntoCanvas { canvas ->
        val native = canvas.nativeCanvas
        val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            this.color = android.graphics.Color.TRANSPARENT
            setShadowLayer(blur, 0f, yPx, shadowColor)
        }
        native.save()
        native.scale(1f / d, 1f / d)
        native.drawPath(scaled, paint)
        native.restore()
    }
}

/** SwiftUI `.shadow(.inner(color:radius:y:))`: the shadow of everything outside `path`, seen inside it. */
private fun DrawScope.innerShadow(path: Path, color: Color, radiusPx: Float, yPx: Float) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return
    val bounds = path.getBounds()
    val outside = Path().apply {
        fillType = PathFillType.EvenOdd
        addRect(Rect(bounds.left - 200f, bounds.top - 200f, bounds.right + 200f, bounds.bottom + 200f))
        addPath(path)
    }
    clipPath(path) { castShadow(outside, color, radiusPx, yPx) }
}

// MARK: Shape and colours

/** Outline of the glass and the core (same proportions), traced from the Figma vector (104 × 121.33). */
fun glassShieldPath(topLeft: Offset, size: Size): Path {
    val w = size.width / 104f
    val h = size.height / 121.33f
    fun x(v: Float) = topLeft.x + v * w
    fun y(v: Float) = topLeft.y + v * h
    return Path().apply {
        moveTo(x(52f), y(0f))
        cubicTo(x(66.44f), y(8.67f), x(83.78f), y(14.44f), x(104f), y(15.89f))
        lineTo(x(104f), y(57.78f))
        cubicTo(x(104f), y(89.56f), x(80.89f), y(111.22f), x(52f), y(121.33f))
        cubicTo(x(23.11f), y(111.22f), x(0f), y(89.56f), x(0f), y(57.78f))
        lineTo(x(0f), y(15.89f))
        cubicTo(x(20.22f), y(14.44f), x(37.56f), y(8.67f), x(52f), y(0f))
        close()
    }
}

/** `GlassShieldShape` as a Compose shape (for clips and backgrounds). */
val GlassShieldShape: Shape = GenericShape { size, _ -> addPath(glassShieldPath(Offset.Zero, size)) }

private class ShieldPalette(
    val glow: Color,
    val coreTop: Color,
    val coreBottom: Color,
    val coreStroke: Color,
    val dots: List<FloatArray>,
) {
    companion object {
        /** Rows split by "|", radii in 1/100 pt split by ",", 0 = no dot. */
        private fun decode(text: String): List<FloatArray> = text.split("|").map { row ->
            row.split(",").map { (it.trim().toIntOrNull() ?: 0) / 100f }.toFloatArray()
        }

        /** Figma 480:5506 (shield "on", a person in the dots). */
        private const val ON_DOTS =
            "0,0,0,0,0,0,0,0,0,35,0,0,0,0,0,0,0,0,0|0,0,0,0,0,0,0,40,37,38,40,40,0,0,0,0,0,0,0|" +
                "0,0,0,0,0,40,40,40,42,45,40,40,40,38,0,0,0,0,0|35,35,38,38,40,45,43,45,45,50,45,45,45,45,40,37,35,35,32|" +
                "35,35,40,40,45,45,47,78,105,112,102,78,45,45,45,40,40,35,35|38,40,40,43,47,47,80,120,135,138,135,120,78,47,48,40,40,37,37|" +
                "37,40,42,45,47,50,105,137,140,140,140,137,105,53,50,47,45,43,40|35,45,47,47,55,55,115,142,145,145,142,142,115,55,53,47,45,45,37|" +
                "43,45,47,50,55,55,108,140,145,145,145,140,105,55,55,50,45,45,40|42,48,50,50,58,60,80,127,145,147,145,130,80,58,57,50,50,48,40|" +
                "42,45,50,52,55,60,62,80,110,122,110,80,65,60,55,52,50,45,42|45,45,50,55,55,62,65,67,75,75,73,67,65,65,55,52,50,45,45|" +
                "45,45,50,55,55,60,65,67,73,75,70,67,65,63,55,53,50,45,45|42,48,50,50,58,60,60,68,68,70,70,70,63,60,57,50,50,48,42|" +
                "42,45,50,50,55,58,70,80,90,92,90,80,70,58,55,50,50,45,40|0,45,48,50,65,85,102,115,120,125,120,115,105,85,65,50,45,45,0|" +
                "0,42,45,67,95,112,125,133,135,135,138,133,125,115,92,67,45,45,0|0,0,60,90,110,125,135,140,140,140,140,140,135,125,110,90,60,0,0|" +
                "0,0,0,100,120,130,135,135,138,138,138,138,135,132,120,100,0,0,0|0,0,0,0,125,130,133,133,135,135,135,133,135,130,123,0,0,0,0|" +
                "0,0,0,0,0,125,130,130,130,130,130,130,130,125,0,0,0,0,0|0,0,0,0,0,0,128,130,127,127,130,130,125,0,0,0,0,0,0|" +
                "0,0,0,0,0,0,0,0,123,125,123,0,0,0,0,0,0,0,0"

        /** Figma 955:10662 / 957:11099 ("Guardian/Home · Bahaya" and "Keluarga butuh konfirmasi", "!" in the dots). */
        private const val ALERT_DOTS =
            "0,0,0,0,0,0,0,0,0,35,0,0,0,0,0,0,0,0,0|0,0,0,0,0,0,0,39,39,39,39,35,0,0,0,0,0,0,0|" +
                "0,0,0,0,35,39,43,39,43,51,43,43,39,39,39,0,0,0,0|31,35,35,39,43,39,43,47,59,90,59,43,47,43,39,39,35,31,35|" +
                "31,35,39,39,43,47,47,47,94,122,94,51,47,43,43,43,39,39,35|35,39,43,43,47,47,51,51,122,137,118,51,47,51,47,43,43,39,35|" +
                "39,39,43,47,51,55,51,55,137,141,133,59,55,51,47,47,43,39,35|39,43,47,47,51,55,59,63,145,145,141,63,55,55,51,47,43,43,39|" +
                "39,43,47,51,51,55,59,71,145,149,149,71,63,59,55,51,47,43,43|39,43,47,51,59,63,63,71,149,149,149,71,63,59,55,51,47,47,43|" +
                "39,47,51,55,59,63,67,67,149,153,149,67,63,59,55,51,51,47,43|39,47,51,55,59,63,67,71,145,153,145,67,63,59,55,51,51,47,43|" +
                "39,43,51,55,59,63,67,67,125,149,125,67,63,59,55,51,51,47,43|39,43,47,51,55,55,59,63,94,129,94,67,63,59,55,51,47,47,43|" +
                "0,43,47,51,51,55,59,63,63,90,63,59,63,59,55,51,47,43,0|0,43,43,47,51,55,59,59,86,122,86,59,55,51,51,47,43,39,0|" +
                "0,0,43,47,51,55,51,59,137,141,141,59,55,51,47,47,43,0,0|0,0,43,43,43,47,51,63,137,137,137,59,47,51,47,43,43,0,0|" +
                "0,0,0,39,43,47,47,47,98,122,98,51,47,43,43,39,0,0,0|0,0,0,0,43,39,43,43,43,43,47,43,43,43,39,0,0,0,0|" +
                "0,0,0,0,0,0,43,39,43,43,39,43,39,0,0,0,0,0,0|0,0,0,0,0,0,0,0,39,39,39,0,0,0,0,0,0,0,0"

        /** Figma 480:5596 (shield "off", a power symbol in the dots). */
        private const val OFF_DOTS =
            "0,0,0,0,0,0,0,0,0,35,0,0,0,0,0,0,0,0,0|0,0,0,0,0,0,0,40,37,38,40,40,0,0,0,0,0,0,0|" +
                "0,0,0,0,0,40,40,40,42,45,40,40,40,38,0,0,0,0,0|35,35,38,38,40,45,43,45,45,45,45,45,45,45,40,37,35,35,32|" +
                "35,35,40,40,45,45,47,50,47,47,50,50,45,45,45,40,40,35,35|38,40,40,43,47,47,50,50,53,88,50,50,50,47,48,40,40,37,37|" +
                "37,40,42,45,47,85,125,55,85,130,85,55,125,85,50,47,45,43,40|35,45,47,47,105,138,143,58,115,145,118,58,143,135,108,47,45,45,37|" +
                "43,45,47,105,138,140,143,60,135,145,135,60,145,142,140,108,45,45,40|42,48,80,137,140,142,145,63,143,147,143,63,145,142,140,140,80,48,40|" +
                "42,45,120,140,142,145,115,67,145,153,145,67,115,145,140,140,120,45,42|45,55,133,138,145,135,65,67,135,155,138,67,65,135,143,138,135,55,45|" +
                "45,70,138,140,142,105,65,67,115,153,113,67,65,105,140,140,135,73,45|42,77,135,140,140,97,60,68,70,123,70,70,63,97,140,140,135,77,42|" +
                "42,67,133,140,140,110,60,63,65,67,65,63,60,113,140,140,135,68,40|0,45,127,135,135,135,57,60,65,65,63,60,57,135,138,138,127,45,0|" +
                "0,42,108,135,135,135,122,60,55,55,58,60,125,135,135,133,107,45,0|0,0,60,130,135,135,140,135,118,108,120,135,137,135,135,130,60,0,0|" +
                "0,0,0,88,130,132,135,135,138,138,138,138,135,132,130,90,0,0,0|0,0,0,0,85,125,133,133,135,135,135,133,135,125,85,0,0,0,0|" +
                "0,0,0,0,0,55,102,122,127,130,127,122,102,55,0,0,0,0,0|0,0,0,0,0,0,40,40,55,63,55,40,40,0,0,0,0,0,0|" +
                "0,0,0,0,0,0,0,0,38,38,40,0,0,0,0,0,0,0,0"

        private val onDots = decode(ON_DOTS)
        private val alertDots = decode(ALERT_DOTS)

        val on = ShieldPalette(hex(0x1A73D9), hex(0x4FB4F2), hex(0x0F55B0), hex(0x1E6CB0), onDots)

        /** Figma "Guardian/Home" 435:20469 (teal). */
        val teal = ShieldPalette(hex(0x058C99), hex(0x3ED6D2), hex(0x05737C), hex(0x0D8F93), onDots)

        /** A family site waits (orange, crimson): "!" in the dots instead of the person. */
        val orange = ShieldPalette(hex(0xFF8C00), hex(0xFFD27A), hex(0xE07800), hex(0xC46700), alertDots)

        /** Figma "Pribadi/Home · Waspada" 955:10394, "· Bahaya" 955:10492, "Guardian/Home · Bahaya" 955:10658. */
        val amber = ShieldPalette(hex(0xD9801A), hex(0xF2A64F), hex(0xB0650F), hex(0xB06C1E), onDots)
        val red = ShieldPalette(hex(0xD91A26), hex(0xF24F5A), hex(0xB00F1A), hex(0xB01E28), onDots)

        /** Figma "Guardian/Home/blocked" 1382:3248: the red core, "!" in the dots. */
        val redAlert = ShieldPalette(red.glow, red.coreTop, red.coreBottom, red.coreStroke, alertDots)
        val crimson = ShieldPalette(hex(0xFF0011), hex(0xFF7A83), hex(0xE0000F), hex(0xC4000D), alertDots)

        val off = ShieldPalette(hex(0x54667D), hex(0xB4BFCC), hex(0x56677B), hex(0x55677D), decode(OFF_DOTS))

        fun palette(tint: HalftoneShieldTint): ShieldPalette = when (tint) {
            HalftoneShieldTint.BLUE -> on
            HalftoneShieldTint.TEAL -> teal
            HalftoneShieldTint.ORANGE -> orange
            HalftoneShieldTint.AMBER -> amber
            HalftoneShieldTint.RED -> red
            HalftoneShieldTint.CRIMSON -> crimson
            HalftoneShieldTint.RED_ALERT -> redAlert
        }
    }
}
