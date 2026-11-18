package com.shoo.app.app

import android.app.Activity
import android.provider.Settings
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import com.shoo.app.components.LocalIsDarkTheme
import com.shoo.app.components.ShooAppearance
import com.shoo.app.components.shooEaseOut
import com.shoo.app.features.main.MainTabView
import com.shoo.app.features.main.SessionExpiredView
import com.shoo.app.features.onboarding.DataConsentView
import com.shoo.app.features.onboarding.LaunchSplash
import com.shoo.app.features.onboarding.OnboardingFlow

/** Which top-level screen shows; changing it cross-fades (onboarding → tabs, → "Session expired"). */
private enum class Phase { SESSION_EXPIRED, DATA_CONSENT, MAIN, ONBOARDING }

/**
 * Onboarding until it is finished, then the two tabs, under the launch splash (ON-01). Applies the in-app language,
 * theme and accessibility choices (PF-01) to everything below, and provides [LocalAppEnvironment].
 *
 * iOS `.onOpenURL` and the `scenePhase == .active` hook live in `MainActivity` (`onNewIntent`, `onResume`).
 * iOS: a Debug component gallery (`debug.gallery`) can replace everything; not ported.
 */
@Composable
fun RootView(env: AppEnvironment) {
    val settings = env.settings
    val phase = when {
        env.sessionExpired -> Phase.SESSION_EXPIRED
        env.needsDataConsent -> Phase.DATA_CONSENT
        settings.onboardingCompleted && settings.mode != null -> Phase.MAIN
        else -> Phase.ONBOARDING
    }
    val context = LocalContext.current
    // The phone's "Remove animations" (iOS Reduce Motion), read once per composition of the root.
    val systemReduceMotion = remember(context) {
        try {
            Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
        } catch (_: Exception) {
            false
        }
    }
    val reducesMotion = settings.reduceMotion || systemReduceMotion || env.reducesMotionForUITests

    CompositionLocalProvider(LocalAppEnvironment provides env) {
        ShooAppearance(
            theme = settings.theme,
            textSize = settings.textSize,
            boldText = settings.boldText,
            highContrast = settings.highContrast,
            reduceMotion = reducesMotion,
            // iOS also counts the system's Reduce Transparency; Android has no such setting.
            reduceGlass = settings.reduceGlass,
            language = settings.language,
        ) {
            SystemBarsFollowTheme()
            // Fades in under the splash's own `.easeOut` fade-out (`LaunchSplash.play()`), so the two cross-fade.
            val contentAlpha by animateFloatAsState(
                if (env.launchSplash == LaunchSplashPhase.SHOWING) 0f else 1f,
                shooEaseOut(if (reducesMotion) 0.2 else 0.3),
                label = "launchContent",
            )
            Box(Modifier.fillMaxSize()) {
                // A cross-fade instead of a hard cut between top-level screens. At launch the phase doesn't change, so
                // the splash's own fade below is the only one. ON-01: the screen is built and routed under the launch
                // splash; transparent while the splash shows, then the two cross-fade.
                Crossfade(
                    targetState = phase,
                    modifier = Modifier
                        .fillMaxSize()
                        .graphicsLayer { alpha = contentAlpha },
                    animationSpec = shooEaseOut(if (reducesMotion) 0.2 else 0.3),
                    label = "RootPhase",
                ) { shown ->
                    when (shown) {
                        Phase.SESSION_EXPIRED -> SessionExpiredView()
                        Phase.DATA_CONSENT -> DataConsentView(onBack = null) { granted ->
                            env.setDataConsent(if (granted) DataConsent.GRANTED else DataConsent.DECLINED)
                        }
                        Phase.MAIN -> MainTabView()
                        Phase.ONBOARDING -> OnboardingFlow()
                    }
                }
                LaunchSplash()
            }
        }
    }
}

/** iOS sets the status bar style from the theme; Android: light or dark status and navigation bar icons. */
@Composable
private fun SystemBarsFollowTheme() {
    val dark = LocalIsDarkTheme.current
    val view = LocalView.current
    if (view.isInEditMode) return
    SideEffect {
        val window = (view.context as? Activity)?.window ?: return@SideEffect
        val controller = WindowCompat.getInsetsController(window, view)
        controller.isAppearanceLightStatusBars = !dark
        controller.isAppearanceLightNavigationBars = !dark
    }
}

