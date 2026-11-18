package com.shoo.app.components

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.Dp
import com.shoo.app.support.t
import kotlin.math.min
import kotlin.math.pow

/** A disc fades in over this share of its life, so it never pops up behind the glass. */
private const val SOFT_PULSE_FADE_IN = 0.12

/**
 * Three soft discs that grow and fade one after the other (`period` for each, so a new one every third of it).
 * Reduce Motion keeps them still.
 */
@Composable
fun SoftPulse(
    smallest: Dp,
    largest: Dp,
    peak: Float,
    modifier: Modifier = Modifier,
    color: Color = Color.White,
    /** One disc's life in seconds. */
    period: Double = 4.0,
) {
    val reduceMotion = LocalReduceMotion.current
    var time by remember { mutableDoubleStateOf(period * 0.15) }
    LaunchedEffect(reduceMotion, period) {
        if (reduceMotion) {
            time = period * 0.15
            return@LaunchedEffect
        }
        while (true) {
            withFrameNanos { nanos -> time = nanos / 1_000_000_000.0 }
        }
    }
    Canvas(modifier.size(largest).clearAndSetSemantics { }) {
        val small = smallest.toPx()
        val large = largest.toPx()
        for (index in 0 until 3) {
            val phase = ((time / period + index / 3.0) % 1.0)
            val alpha = peak * min(phase / SOFT_PULSE_FADE_IN, 1.0) * (1 - phase).pow(1.2)
            val diameter = small + phase.toFloat() * (large - small)
            drawCircle(color.copy(alpha = (alpha.toFloat() * color.alpha).coerceIn(0f, 1f)), radius = diameter / 2)
        }
    }
}

private const val LOADER_SHIELD_SCALE = 0.46f

/**
 * Loading state for a whole area: a small `HalftoneShield` on the pulse of the Home hero.
 * Screens with the big shield already in view keep the plain spinner.
 */
@Composable
fun ShieldPulseLoader(modifier: Modifier = Modifier) {
    val label = t("Loading")
    Box(modifier.clearAndSetSemantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        SoftPulse(color = hex(0x1A73D9), smallest = Dp(50f), largest = Dp(180f), peak = 0.22f)
        Box(
            Modifier.size(HalftoneShieldSize.width * LOADER_SHIELD_SCALE, HalftoneShieldSize.height * LOADER_SHIELD_SCALE),
            contentAlignment = Alignment.Center,
        ) {
            HalftoneShield(
                Modifier
                    .requiredSize(HalftoneShieldSize)
                    .graphicsLayer {
                        scaleX = LOADER_SHIELD_SCALE
                        scaleY = LOADER_SHIELD_SCALE
                    },
            )
        }
    }
}

/**
 * What replaces `ShieldPulseLoader` fades in over 0.2 s instead of cutting in, gentle enough for Reduce Motion.
 * Started on first composition, so a heavy first render (Detail, a long Activity list) can't swallow the fade.
 */
fun Modifier.loaderReplacementFade(): Modifier = composed {
    var shown by rememberSaveable { androidx.compose.runtime.mutableStateOf(false) }
    val alpha = remember { Animatable(if (shown) 1f else 0f) }
    LaunchedEffect(Unit) {
        if (!shown) {
            alpha.animateTo(1f, shooEaseOut(0.2))
            shown = true
        }
    }
    graphicsLayer { this.alpha = alpha.value }
}
