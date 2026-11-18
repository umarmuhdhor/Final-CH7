package com.shoo.app

import androidx.compose.animation.core.TweenSpec
import androidx.compose.animation.core.VectorConverter
import com.shoo.app.components.ShooEasing
import com.shoo.app.components.shooBouncy
import com.shoo.app.components.shooDefault
import com.shoo.app.components.shooEaseInOut
import com.shoo.app.components.shooEaseOut
import com.shoo.app.components.shooSmooth
import com.shoo.app.components.shooSnappy
import com.shoo.app.components.shooSpring
import com.shoo.app.components.shooSpringResponse
import com.shoo.app.components.withDelay
import kotlin.math.PI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

/** The SwiftUI curves in `components/Motion.kt`. */
class MotionTest {
    private fun stiffness(duration: Double) = ((2 * PI / duration) * (2 * PI / duration)).toFloat()

    @Test
    fun springMapsDurationAndBounce() {
        val spec = shooSpring<Float>(0.32, 0.18)
        assertEquals(stiffness(0.32), spec.stiffness, 0.01f)
        assertEquals(0.82f, spec.dampingRatio, 1e-5f)
        // Negative bounce: overdamped, 1 / (1 + b).
        assertEquals(2f, shooSpring<Float>(0.5, -0.5).dampingRatio, 1e-5f)
    }

    @Test
    fun namedSpringsMatchSwiftUI() {
        assertEquals(1f, shooSmooth<Float>().dampingRatio, 1e-5f)
        assertEquals(0.85f, shooSnappy<Float>().dampingRatio, 1e-5f)
        assertEquals(0.7f, shooBouncy<Float>().dampingRatio, 1e-5f)
        assertEquals(stiffness(0.5), shooSmooth<Float>().stiffness, 0.01f)
        assertEquals(stiffness(0.55), shooDefault<Float>().stiffness, 0.01f)
        assertEquals(1f, shooDefault<Float>().dampingRatio, 1e-5f)
        val response = shooSpringResponse<Float>(0.6, 0.65)
        assertEquals(stiffness(0.6), response.stiffness, 0.01f)
        assertEquals(0.65f, response.dampingRatio, 1e-5f)
    }

    @Test
    fun easingsUseCoreAnimationPointsAndRoundedMillis() {
        val easeOut = shooEaseOut<Float>(0.29, delay = 0.07) as TweenSpec<Float>
        assertEquals(290, easeOut.durationMillis)
        assertEquals(70, easeOut.delay)
        assertSame(ShooEasing.easeOut, easeOut.easing)
        assertEquals(350, (shooEaseInOut<Float>() as TweenSpec<Float>).durationMillis)
        assertEquals(0.5f, ShooEasing.easeInOut.transform(0.5f), 1e-3f)
    }

    @Test
    fun withDelayHoldsTheStartThenRuns() {
        val plain = shooEaseOut<Float>(0.2).vectorize(Float.VectorConverter)
        val delayed = shooEaseOut<Float>(0.2).withDelay(0.1).vectorize(Float.VectorConverter)
        val from = Float.VectorConverter.convertToVector(0f)
        val to = Float.VectorConverter.convertToVector(1f)
        val still = Float.VectorConverter.convertToVector(0f)
        assertEquals(
            plain.getDurationNanos(from, to, still) + 100_000_000L,
            delayed.getDurationNanos(from, to, still),
        )
        assertEquals(0f, delayed.getValueFromNanos(50_000_000L, from, to, still).value, 0f)
        assertEquals(
            plain.getValueFromNanos(100_000_000L, from, to, still).value,
            delayed.getValueFromNanos(200_000_000L, from, to, still).value,
            1e-6f,
        )
    }
}
