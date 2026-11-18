package com.shoo.app.features.onboarding

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.dp
import com.shoo.app.app.LaunchSplashPhase
import com.shoo.app.app.LocalAppEnvironment
import com.shoo.app.components.LightOnly
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.hex
import com.shoo.app.components.shooEaseOut
import com.shoo.app.components.shooSpringResponse
import com.shoo.app.components.swiftDelay
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlinx.coroutines.launch

/** The logo has sprung in by then (spring response 0.6 s); the band is all but settled. */
private const val HOLD = 0.8
private const val FADE = 0.3

/** Where Figma "final" has the light stop, and how long the band takes to get there. */
private const val LIGHT_STOP = 0.46f
private const val SWEEP = 1.2

/**
 * ON-01: the brand splash over the first screen of every cold launch (Figma 110:3585). The screen under it is already
 * routed (onboarding step, Home, or Detail from a push or link), so it only fades away: no wait for data, and no route
 * is lost. The two cross-fade (`RootView`); taps and TalkBack reach the screen once the splash starts to fade.
 */
@Composable
fun LaunchSplash(modifier: Modifier = Modifier) {
    val env = LocalAppEnvironment.current
    if (env.launchSplash == LaunchSplashPhase.DONE) return
    val reduceMotion = LocalReduceMotion.current
    val phase = rememberOnboardingScenePhase()
    val opacity = remember { Animatable(1f) }

    // Timed from when the app is active (resumed). Sent to the background meanwhile: the splash starts over when the
    // app is back.
    LaunchedEffect(phase.isActive) {
        if (!phase.isActive) return@LaunchedEffect
        if (env.launchSplash == LaunchSplashPhase.SHOWING) {
            swiftDelay(env.launchSplashHold ?: if (reduceMotion) 0.4 else HOLD)
        }
        env.launchSplash = LaunchSplashPhase.LEAVING
        opacity.animateTo(0f, shooEaseOut(if (reduceMotion) 0.2 else FADE))
        env.launchSplash = LaunchSplashPhase.DONE
    }

    val showing = env.launchSplash == LaunchSplashPhase.SHOWING
    LightOnly {
        BrandSplash(
            modifier = modifier
                .fillMaxSize()
                .graphicsLayer { alpha = opacity.value }
                // While it fades, taps already reach the screen.
                .then(
                    if (showing) {
                        Modifier.pointerInput(Unit) {
                            awaitPointerEventScope {
                                while (true) awaitPointerEvent().changes.forEach { it.consume() }
                            }
                        }
                    } else {
                        // TalkBack leaves the splash once it starts to go.
                        Modifier.clearAndSetSemantics { }
                    },
                ),
        )
    }
}

/**
 * Figma "Splash Screen" in motion: the light band sweeps in and settles where the frame has it, the logo springs in,
 * then breathes, blinks and twinkles (`ShooBirdLogo`). With Reduce Motion it is the still frame.
 */
@Composable
private fun BrandSplash(modifier: Modifier = Modifier) {
    val reduceMotion = LocalReduceMotion.current
    val logoIn = remember { Animatable(if (reduceMotion) 1f else 0f) }
    var progress by remember { mutableFloatStateOf(if (reduceMotion) 1f else 0f) }

    LaunchedEffect(Unit) {
        if (reduceMotion) {
            logoIn.snapTo(1f)
            progress = 1f
            return@LaunchedEffect
        }
        launch { logoIn.animateTo(1f, shooSpringResponse(0.6, 0.65)) }
        val start = withFrameNanos { it }
        while (progress < 1f) {
            val now = withFrameNanos { it }
            progress = min(((now - start) / 1e9 / SWEEP).toFloat(), 1f)
        }
    }

    BoxWithConstraints(modifier = modifier) {
        val scale = maxWidth.value / 402f
        // Ease out: the band slows down as it reaches its place.
        val eased = 1f - (1f - progress).pow(3)
        val light = -0.1f + (LIGHT_STOP + 0.1f) * eased
        Box(
            modifier = Modifier
                .fillMaxSize()
                .clearAndSetSemantics { }
                .drawBehind {
                    drawRect(
                        Brush.linearGradient(
                            0f to hex(0x46A7FF),
                            max(light, 0.001f) to hex(0xBFE0FF),
                            1f to hex(0x46A7FF),
                            start = Offset.Zero,
                            end = Offset(size.width, size.height),
                        ),
                    )
                },
        ) {
            // Figma "Ellipse 2" and "Ellipse 3": layer blur 115.
            BlurredEllipse(
                color = hex(0x1E78BE),
                width = (86 * scale).dp,
                height = (137 * scale).dp,
                blur = (57 * scale).dp,
                modifier = Modifier.centeredAt(((153 + 40 * (1 - eased)) * scale).dp, (61 * scale).dp),
            )
            BlurredEllipse(
                color = hex(0x5CC6D8),
                width = (86 * scale).dp,
                height = (137 * scale).dp,
                blur = (57 * scale).dp,
                modifier = Modifier.centeredAt(((-21 - 40 * (1 - eased)) * scale).dp, (111 * scale).dp),
            )
        }
        ShooBirdLogo(
            modifier = Modifier
                .align(Alignment.Center)
                .semantics(mergeDescendants = false) {
                    contentDescription = "Shoo"
                    testTag = "splash.logo"
                }
                .graphicsLayer {
                    val p = logoIn.value
                    val s = 0.7f + 0.3f * p
                    scaleX = s
                    scaleY = s
                    alpha = p.coerceIn(0f, 1f)
                },
        )
    }
}
