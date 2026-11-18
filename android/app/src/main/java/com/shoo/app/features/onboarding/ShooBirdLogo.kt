package com.shoo.app.features.onboarding

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.shoo.app.R
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.hex
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/**
 * ON-01 logo in motion, after the Rive "Shoo Bird" state machine with its Look layer off: the shield breathes, the
 * bird blinks twice and the sparkle twinkles. The first blink and twinkle come early so they land inside the 1.9 s
 * splash; after that they loop like the Rive layers. Reduce Motion keeps the still logo.
 */
@Composable
fun ShooBirdLogo(modifier: Modifier = Modifier) {
    val reduceMotion = LocalReduceMotion.current
    var time by remember { mutableDoubleStateOf(0.0) }
    LaunchedEffect(reduceMotion) {
        if (reduceMotion) {
            time = 0.0
            return@LaunchedEffect
        }
        val start = withFrameNanos { it }
        while (true) {
            val now = withFrameNanos { it }
            time = (now - start) / 1e9
        }
    }

    Box(
        modifier = modifier
            .size(ShooBirdLogoMetrics.WIDTH.dp, ShooBirdLogoMetrics.HEIGHT.dp)
            .graphicsLayer {
                val breath = breath(time)
                scaleX = breath
                scaleY = breath
            },
    ) {
        Image(
            painter = painterResource(R.drawable.shoo_logo),
            contentDescription = null,
            contentScale = ContentScale.FillBounds,
            modifier = Modifier.fillMaxSize(),
        )
        Canvas(modifier = Modifier.fillMaxSize()) {
            val blink = blink(time).toFloat()
            if (blink > 0f) {
                drawPath(eyeSlit(EYE_LEFT), hex(0x212121), alpha = blink)
                drawPath(eyeSlit(EYE_RIGHT), hex(0x48505B), alpha = blink)
            }
            // Where the app icon has its sparkle, on the top right of the shield rim.
            val twinkle = twinkle(time).toFloat()
            translate(129.dp.toPx(), 30.dp.toPx()) {
                rotate(degrees = 45f * twinkle, pivot = Offset.Zero) {
                    val s = 0.75f + 0.4f * twinkle
                    scale(s, s, pivot = Offset.Zero) {
                        drawSparkle(alpha = 0.8f + 0.2f * twinkle)
                    }
                }
            }
        }
    }
}

/** `ShooLogo` is 408 × 456 px at @3x. */
object ShooBirdLogoMetrics {
    const val WIDTH = 136f
    const val HEIGHT = 152f
}

/** Rive "Breathe": a slow 2 % swell, 3 s each. */
private fun breath(time: Double): Float = (1 + 0.02 * (1 - cos(2 * PI * time / 3)) / 2).toFloat()

/** Rive "Blink": two quick blinks close together, then a pause (4.2 s loop). 1 is eyes shut. */
private fun blink(time: Double): Double {
    val phase = time % 4.2
    val half = 0.08
    return listOf(0.75, 1.0).maxOf { max(0.0, 1 - abs(phase - it) / half) }
}

/** Rive "Sparkle": two twinkles, then a pause (5 s loop). 1 is the brightest point. */
private fun twinkle(time: Double): Double {
    val phase = time % 5
    val length = 0.6
    return listOf(0.3, 1.25).maxOf { start ->
        val local = phase - start
        if (local in 0.0..length) sin(PI * local / length) else 0.0
    }
}

/** The white slits in the bird's mask, traced in the 408 × 456 px of `ShooLogo@3x`. Filled with the mask colour they close the eye. */
private val EYE_LEFT = listOf(204f to 205f, 271f to 232f, 280f to 276f, 272f to 277f, 258f to 246f)
private val EYE_RIGHT = listOf(341f to 222f, 341f to 236f, 331f to 243f, 327f to 287f, 323f to 287f, 322f to 238f)

private fun DrawScope.eyeSlit(points: List<Pair<Float, Float>>): Path {
    val sx = size.width / 408f
    val sy = size.height / 456f
    return Path().apply {
        points.forEachIndexed { index, (x, y) ->
            if (index == 0) moveTo(x * sx, y * sy) else lineTo(x * sx, y * sy)
        }
        close()
    }
}

/** Four-point star with a thin waist, like the sparkle on the app icon: 30 × 28, centred on the origin, with a white 80 % glow (radius 4). */
private fun DrawScope.drawSparkle(alpha: Float) {
    val w = 30.dp.toPx()
    val h = 28.dp.toPx()
    val path = Path().apply {
        moveTo(0f, -h / 2)
        quadraticBezierTo(0f, 0f, w / 2, 0f)
        quadraticBezierTo(0f, 0f, 0f, h / 2)
        quadraticBezierTo(0f, 0f, -w / 2, 0f)
        quadraticBezierTo(0f, 0f, 0f, -h / 2)
        close()
    }
    drawIntoCanvas { canvas ->
        val paint = androidx.compose.ui.graphics.Paint()
        val framework = paint.asFrameworkPaint()
        framework.isAntiAlias = true
        framework.color = Color.White.copy(alpha = alpha).toArgb()
        // SwiftUI `.shadow(color: .white.opacity(0.8), radius: 4)`; Skia radius from sigma 4.
        framework.setShadowLayer((4.dp.toPx() - 0.5f) / 0.57735f, 0f, 0f, Color.White.copy(alpha = 0.8f * alpha).toArgb())
        canvas.drawPath(path, paint)
    }
}
