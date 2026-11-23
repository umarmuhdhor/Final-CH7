package com.shoo.app.features.shield

import android.content.Context
import android.content.Intent
import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.offset
import com.shoo.app.R
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.LightOnly
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.StateMotion
import com.shoo.app.components.hex
import com.shoo.app.components.shooEaseInOut
import com.shoo.app.components.swiftDelay
import com.shoo.app.data.FIREFOX_PACKAGE
import com.shoo.app.features.onboarding.OnboardingCapsuleButton
import com.shoo.app.features.onboarding.onboardingFont
import com.shoo.app.support.Log
import com.shoo.app.support.t

/** Figma: the warning in #D97805, the step numbers on #1E376B. */
private val TurnOffWarning = hex(0xD97805)
private val TurnOffStepFill = hex(0x1E376B)

/** `ProfileStyle.sheetGrabber` (light; the sheet is light only). */
private val TurnOffGrabber = hex(0xD9DFE6)

/**
 * Android (PORTING.md): how to switch the Shoo add-on off in Firefox for Android. Firefox has no way to open its
 * add-on page from another app, so both steps are kept (iOS before 26.2 had the same two: the path, then the switch).
 */
private val TurnOffSteps = listOf(
    "In Firefox, open the menu ⋮ › Extensions › Manage extensions.",
    "Tap Shoo and switch it off.",
)

/**
 * "Matikan Shoo" (GD-01, Figma "Sheet · Matikan Shoo" 1681:5372): how to switch Shoo off in Firefox. Only a guide;
 * Shoo never switches itself off, and Home shows "not protected" once the add-on is off. Opened from the active
 * "Safari extension" (Android: Firefox add-on) row in Profile.
 *
 * The content of a sheet: present it in a `ModalBottomSheet` with `containerColor = Color.White`, `dragHandle = null`
 * (this draws its own grabber), top corners 32 dp (iOS `.presentationCornerRadius(32)`), sized to its content
 * (iOS `.presentationDetents([.height(h)])`). `onDismiss` (iOS `@Environment(\.dismiss)`): the X closes it.
 */
@Composable
fun TurnOffExtensionSheet(onDismiss: () -> Unit = {}, modifier: Modifier = Modifier) {
    val reduceMotion = LocalReduceMotion.current
    val view = LocalView.current
    val context = LocalContext.current
    val navBottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    var wiggle by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        // `.sensoryFeedback(.warning, trigger: shown)` and the triangle's one wiggle as the sheet settles.
        view.shieldHaptic(ShieldHaptic.WARNING)
        wiggle += 1
    }

    LightOnly {
        Column(
            modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(top = 8.dp, bottom = 6.dp + navBottom),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Box(
                Modifier
                    .align(Alignment.CenterHorizontally)
                    .size(width = 36.dp, height = 5.dp)
                    .background(TurnOffGrabber, CapsuleShape)
                    .clearAndSetSemantics { },
            )
            Row(verticalAlignment = Alignment.Top) {
                Text(
                    text = t("Switch off Shoo"),
                    style = onboardingFont(28f, FontWeight.SemiBold, tracking = 0.56f, lineHeight = 34f),
                    color = HomeTheme.navy,
                    modifier = Modifier
                        .weight(1f)
                        .semantics { heading() },
                )
                val close = t("Close")
                Image(
                    painter = painterResource(R.drawable.profile_sheet_close),
                    contentDescription = null,
                    modifier = Modifier
                        // A 44 pt button around the 30 pt image, laid out as the image (`.padding(-7)`).
                        .touchOutset(7.dp)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            role = Role.Button,
                            onClick = onDismiss,
                        )
                        .semantics { contentDescription = close }
                        .testTag("turnOff.close")
                        .padding(7.dp)
                        .size(30.dp),
                )
            }
            // Figma "Peringatan": the triangle (SF Pro Semibold 17) and SF Pro Rounded 16 / 22, 8 apart.
            Row(
                Modifier
                    .semantics(mergeDescendants = true) { }
                    .testTag("turnOff.warning"),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.Top,
            ) {
                Box(Modifier.heightIn(min = 22.dp).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
                    SfSymbol(
                        "exclamationmark.triangle.fill",
                        pointSize = 17f,
                        tint = TurnOffWarning,
                        modifier = Modifier.wiggleOnce(wiggle, enabled = !reduceMotion),
                    )
                }
                Text(
                    text = t("Shoo off means protection stops. Your family won't get warnings anymore."),
                    style = onboardingFont(16f, rounded = true, lineHeight = 22f),
                    color = TurnOffWarning,
                    modifier = Modifier.weight(1f),
                )
            }
            TurnOffSteps.forEachIndexed { index, step ->
                TurnOffStepRow(number = index + 1, text = t(step), reduceMotion = reduceMotion)
            }
            OnboardingCapsuleButton(
                title = "Open Firefox",
                onClick = { openFirefox(context) },
                identifier = "turnOff.openSettings",
                modifier = Modifier.padding(top = 20.dp),
            )
        }
    }
}

/** One numbered step; the steps arrive one after the other as the sheet settles. */
@Composable
private fun TurnOffStepRow(number: Int, text: String, reduceMotion: Boolean) {
    val progress = remember { Animatable(0f) }
    val rise = with(LocalDensity.current) { 8.dp.toPx() }
    LaunchedEffect(Unit) {
        swiftDelay(0.08 * number)
        progress.animateTo(1f, StateMotion.enter(reduceMotion))
    }
    Row(
        Modifier
            .graphicsLayer {
                alpha = progress.value.coerceIn(0f, 1f)
                translationY = if (reduceMotion) 0f else (1f - progress.value) * rise
            }
            .semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(
            Modifier
                .size(32.dp)
                .background(TurnOffStepFill, CircleShape)
                .clearAndSetSemantics { },
            contentAlignment = Alignment.Center,
        ) {
            Text(text = "$number", style = onboardingFont(17f, FontWeight.SemiBold), color = androidx.compose.ui.graphics.Color.White)
        }
        Box(
            Modifier
                .weight(1f)
                .heightIn(min = 32.dp),
            contentAlignment = Alignment.CenterStart,
        ) {
            Text(text = text, style = onboardingFont(17f, rounded = true, lineHeight = 22f), color = HomeTheme.ink)
        }
    }
}

/** `.symbolEffect(.wiggle, options: .nonRepeating, value:)`: a short rotation, once per `trigger`. */
@Composable
private fun Modifier.wiggleOnce(trigger: Int, enabled: Boolean): Modifier {
    val rotation = remember { Animatable(0f) }
    LaunchedEffect(trigger, enabled) {
        if (!enabled || trigger == 0) return@LaunchedEffect
        for (angle in floatArrayOf(-12f, 10f, -8f, 6f, 0f)) rotation.animateTo(angle, shooEaseInOut(0.08))
    }
    return graphicsLayer { rotationZ = rotation.value }
}

/** `.contentShape(Rectangle().inset(by: -d))` with `.padding(-d)`: the child is `2 d` larger than the space it takes. */
private fun Modifier.touchOutset(d: Dp): Modifier = layout { measurable, constraints ->
    val px = d.roundToPx()
    val placeable = measurable.measure(constraints.offset(horizontal = 2 * px, vertical = 2 * px))
    layout((placeable.width - 2 * px).coerceAtLeast(0), (placeable.height - 2 * px).coerceAtLeast(0)) {
        placeable.place(-px, -px)
    }
}

/**
 * "Open Firefox" (iOS "Open Safari settings"): Firefox for Android, where the add-on is switched off. Without Firefox
 * there is nothing to switch off (`ExtensionStatus` is Off already).
 */
private fun openFirefox(context: Context) {
    val intent = context.packageManager.getLaunchIntentForPackage(FIREFOX_PACKAGE)
    if (intent == null) {
        Log.ui.error("Opening Firefox failed", "not installed")
        return
    }
    try {
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (error: Exception) {
        Log.ui.error("Opening Firefox failed", error)
    }
}
