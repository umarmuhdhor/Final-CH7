package com.shoo.app.features.onboarding

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.shoo.app.data.ExtensionStatus
import com.shoo.app.data.FIREFOX_PACKAGE
import com.shoo.app.support.Log

/**
 * ON-04 instructions. iOS: the Safari extension's switch in Settings. Android (PORTING.md): the Shoo add-on in
 * Firefox for Android: install Firefox, add the add-on, then link it with the one-time code (`AddonBridge`).
 */
object ExtensionSetup {
    enum class Step {
        /** Firefox is there: the button shows the code and opens Firefox. iOS `tapTurnOn`. */
        TAP_TURN_ON,
        /** Firefox is missing: the button opens the Play Store. iOS `openSettingsModern` / `openSettingsLegacy`. */
        INSTALL_FIREFOX,
        /** Add the Shoo add-on and open its settings. iOS `switchOn`. */
        SWITCH_ON,
        /** Enter the code, then come back. iOS `comeBack`. */
        COME_BACK,
    }

    /** Figma "Aktifkan Ekstensi": three steps. The first one depends on whether Firefox is installed. */
    fun steps(firefoxInstalled: Boolean): List<Step> =
        listOf(if (firefoxInstalled) Step.TAP_TURN_ON else Step.INSTALL_FIREFOX, Step.SWITCH_ON, Step.COME_BACK)

    fun steps(context: Context): List<Step> = steps(ExtensionStatus.isFirefoxInstalled(context))

    /**
     * "Turn on" (PRD ON-04). iOS opens Safari's extension settings. Android has no link into Firefox's add-on settings:
     * Firefox when it is installed, else its Play Store page.
     */
    fun openSettings(context: Context) {
        if (ExtensionStatus.isFirefoxInstalled(context)) openFirefox(context) else installFirefox(context)
    }

    /** iOS "Open Safari": here Firefox, where the add-on runs. */
    fun openSafari(context: Context) = openFirefox(context)

    /** Opens Firefox (its own start page), or its Play Store page when it is missing. */
    fun openFirefox(context: Context) {
        val launch = context.packageManager.getLaunchIntentForPackage(FIREFOX_PACKAGE)
        if (launch == null) {
            installFirefox(context)
            return
        }
        start(context, launch)
    }

    /** Firefox's Play Store page (the store app, or the web page without it). */
    fun installFirefox(context: Context) {
        val store = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$FIREFOX_PACKAGE"))
        if (start(context, store)) return
        start(context, Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$FIREFOX_PACKAGE")))
    }

    internal fun start(context: Context, intent: Intent): Boolean = try {
        if (context !is android.app.Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        true
    } catch (error: ActivityNotFoundException) {
        Log.app.error("Opening an app failed", error)
        false
    } catch (error: SecurityException) {
        Log.app.error("Opening an app failed", error)
        false
    }
}

/** Catalog key of the step's instruction. */
val ExtensionSetup.Step.text: String
    get() = when (this) {
        ExtensionSetup.Step.TAP_TURN_ON -> "Tap the button below to show your code and open Firefox."
        ExtensionSetup.Step.INSTALL_FIREFOX -> "Tap the button below to get Firefox from the Play Store."
        ExtensionSetup.Step.SWITCH_ON -> "In Firefox, add the Shoo add-on, then open its settings."
        ExtensionSetup.Step.COME_BACK -> "Enter the code from Shoo, then come back to get protected."
    }

val ExtensionSetup.Step.systemImage: String
    get() = when (this) {
        ExtensionSetup.Step.TAP_TURN_ON -> "hand.tap.fill"
        ExtensionSetup.Step.INSTALL_FIREFOX -> "gearshape.fill"
        ExtensionSetup.Step.SWITCH_ON -> "switch.2"
        ExtensionSetup.Step.COME_BACK -> "arrow.uturn.backward.circle.fill"
    }

/** What is wrong, said once, with what to do about it (#135). Catalog key; Firefox wording. */
val ExtensionStatus.NextStep.message: String
    get() = when (this) {
        ExtensionStatus.NextStep.SWITCH_ON -> "Firefox isn't installed yet. Install it, then add the Shoo add-on to stay safe."
        ExtensionStatus.NextStep.ALLOW_EVERY_WEBSITE ->
            "Shoo can't check every website yet. In Firefox, open Extensions › Shoo and allow it on all sites."
        ExtensionStatus.NextStep.SWITCH_ON_THEN_OPEN_A_WEBSITE ->
            "Shoo isn't linked to Firefox yet. Add the Shoo add-on in Firefox, then enter the code from Shoo in its settings."
        ExtensionStatus.NextStep.OPEN_A_WEBSITE -> "Almost done. Open any website in Firefox so Shoo can check in."
    }

/** The main button opens the browser (Firefox) only when the add-on is known to be on; otherwise setup comes first. */
val ExtensionStatus.NextStep.opensSafariFirst: Boolean
    get() = when (this) {
        ExtensionStatus.NextStep.ALLOW_EVERY_WEBSITE, ExtensionStatus.NextStep.OPEN_A_WEBSITE -> true
        ExtensionStatus.NextStep.SWITCH_ON, ExtensionStatus.NextStep.SWITCH_ON_THEN_OPEN_A_WEBSITE -> false
    }

/** Whether a second, smaller button is worth showing. */
val ExtensionStatus.NextStep.hasSecondAction: Boolean
    get() = this != ExtensionStatus.NextStep.SWITCH_ON

// MARK: Scene phase

/**
 * iOS `@Environment(\.scenePhase)`: `isActive` while the Activity is resumed; `activations` counts every return to
 * the foreground, so `LaunchedEffect(phase)` runs again each time the user is back (iOS `.task(id: scenePhase)`).
 */
internal data class OnboardingScenePhase(val isActive: Boolean, val activations: Int)

@Composable
internal fun rememberOnboardingScenePhase(): OnboardingScenePhase {
    val owner = LocalLifecycleOwner.current
    var active by remember(owner) { mutableStateOf(false) }
    var activations by remember(owner) { mutableIntStateOf(0) }
    DisposableEffect(owner) {
        // Added observers are brought up to the current state, so a resumed Activity sends ON_RESUME at once.
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> {
                    active = true
                    activations += 1
                }
                Lifecycle.Event.ON_PAUSE -> active = false
                else -> Unit
            }
        }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer) }
    }
    return OnboardingScenePhase(active, activations)
}
