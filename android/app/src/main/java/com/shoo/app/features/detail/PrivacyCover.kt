package com.shoo.app.features.detail

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.os.Build
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.shoo.app.components.LocalIsDarkTheme
import com.shoo.app.components.hex
import com.shoo.app.components.sfSymbol

/**
 * Hides the content while the app is not in front, so the recent-apps snapshot never holds the scam URL, the
 * owner's name or the evidence picture (SECURITY §3 P9, P13). iOS `.privacyCover()`.
 *
 * Two layers: on Android 13+ the window asks the system for no recent-apps screenshot while any covered screen is
 * on (`Activity.setRecentsScreenshotEnabled(false)`: unlike FLAG_SECURE, the person can still take screenshots, as on
 * iOS); on every version the content is drawn over (system background + shield) from `ON_PAUSE` to `ON_RESUME`.
 * iOS: the snapshot is taken after the cover is drawn; before Android 13 the system may snapshot before the next frame.
 */
fun Modifier.privacyCover(): Modifier = composed {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var active by remember { mutableStateOf(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> active = true
                Lifecycle.Event.ON_PAUSE -> active = false
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    val activity = LocalContext.current.findActivity()
    DisposableEffect(activity) {
        PrivacyCoverWindow.acquire(activity)
        onDispose { PrivacyCoverWindow.release(activity) }
    }
    val dark = LocalIsDarkTheme.current
    // `.background` and `.secondary` of the system: white / black, secondary label grey.
    val background = if (dark) Color.Black else Color.White
    val tint = if (dark) hex(0xEBEBF5, 0.6f) else hex(0x3C3C43, 0.6f)
    val painter = rememberVectorPainter(sfSymbol("shield.lefthalf.filled"))
    drawWithContent {
        drawContent()
        if (!active) {
            drawRect(background)
            // `.font(.system(size: 56))`: an SF Symbol at 56 pt is about 1.2 × 56 tall.
            val side = (56f * 1.4f).dp.toPx()
            translate(left = (size.width - side) / 2, top = (size.height - side) / 2) {
                with(painter) { draw(Size(side, side), colorFilter = ColorFilter.tint(tint)) }
            }
        }
    }
}

/** Counts the covered screens on screen, per activity, and turns the recents screenshot off while there are any. */
private object PrivacyCoverWindow {
    private val counts = HashMap<Activity, Int>()

    fun acquire(activity: Activity?) {
        if (activity == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val count = (counts[activity] ?: 0) + 1
        counts[activity] = count
        if (count == 1) activity.setRecentsScreenshotEnabled(false)
    }

    fun release(activity: Activity?) {
        if (activity == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val count = (counts[activity] ?: return) - 1
        if (count <= 0) {
            counts.remove(activity)
            activity.setRecentsScreenshotEnabled(true)
        } else {
            counts[activity] = count
        }
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

