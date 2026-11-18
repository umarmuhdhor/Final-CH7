package com.shoo.app.components

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import kotlin.math.PI

/**
 * SwiftUI `.spring(duration: d, bounce: b)` as a Compose spring (mass 1):
 * stiffness = (2π / d)², damping ratio = 1 − b (b ≥ 0) or 1 / (1 + b) (b < 0), the formulas SwiftUI documents.
 */
fun <T> shooSpring(duration: Double = 0.5, bounce: Double = 0.0, visibilityThreshold: T? = null): SpringSpec<T> {
    val stiffness = (2 * PI / duration).let { it * it }.toFloat()
    val damping = (if (bounce >= 0) 1 - bounce else 1 / (1 + bounce)).toFloat()
    return spring(dampingRatio = damping, stiffness = stiffness, visibilityThreshold = visibilityThreshold)
}

/** SwiftUI `.smooth(duration:)`: a spring without bounce (default 0.5 s). */
fun <T> shooSmooth(duration: Double = 0.5, visibilityThreshold: T? = null): SpringSpec<T> =
    shooSpring(duration, 0.0, visibilityThreshold)

/** SwiftUI `.snappy(duration:)`: a spring with a little bounce (0.15). */
fun <T> shooSnappy(duration: Double = 0.5, visibilityThreshold: T? = null): SpringSpec<T> =
    shooSpring(duration, 0.15, visibilityThreshold)

/** SwiftUI `.bouncy(duration:)`: bounce 0.3. */
fun <T> shooBouncy(duration: Double = 0.5, visibilityThreshold: T? = null): SpringSpec<T> =
    shooSpring(duration, 0.3, visibilityThreshold)

/** SwiftUI's curves (Core Animation's control points). */
object ShooEasing {
    val easeIn = CubicBezierEasing(0.42f, 0f, 1f, 1f)
    val easeOut = CubicBezierEasing(0f, 0f, 0.58f, 1f)
    val easeInOut = CubicBezierEasing(0.42f, 0f, 0.58f, 1f)
    val linear = LinearEasing
}

private fun millis(seconds: Double): Int = (seconds * 1000).toInt()

/** `.easeOut(duration:)` (SwiftUI default 0.35 s), optionally `.delay(_:)`. */
fun <T> shooEaseOut(duration: Double = 0.35, delay: Double = 0.0): FiniteAnimationSpec<T> =
    tween(millis(duration), millis(delay), ShooEasing.easeOut)

/** `.easeIn(duration:)`. */
fun <T> shooEaseIn(duration: Double = 0.35, delay: Double = 0.0): FiniteAnimationSpec<T> =
    tween(millis(duration), millis(delay), ShooEasing.easeIn)

/** `.easeInOut(duration:)`. */
fun <T> shooEaseInOut(duration: Double = 0.35, delay: Double = 0.0): FiniteAnimationSpec<T> =
    tween(millis(duration), millis(delay), ShooEasing.easeInOut)

/** `.linear(duration:)`. */
fun <T> shooLinear(duration: Double = 0.35, delay: Double = 0.0): FiniteAnimationSpec<T> =
    tween(millis(duration), millis(delay), LinearEasing)

/**
 * `.spring(...).delay(d)`: Compose springs have no delay, so callers `delay((d * 1000).toLong())` in the
 * `LaunchedEffect` before animating, or use `Animatable.animateTo` after a delay. This helper is that delay.
 */
suspend fun swiftDelay(seconds: Double) {
    if (seconds > 0) kotlinx.coroutines.delay((seconds * 1000).toLong())
}
