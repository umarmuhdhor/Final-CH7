package com.shoo.app.features.onboarding

import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.compose.animation.Crossfade
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.dp
import com.shoo.app.R
import com.shoo.app.components.shooSmooth

/**
 * Figma "Jadikan Safari Default". iOS: Shoo only runs in Safari. Android: the Shoo add-on only runs in Firefox, so
 * links from WhatsApp or SMS should open there. No API says which browser is another app's default, so this asks
 * instead of checking.
 */
object SafariDefaultSetup {
    /** `text`: catalog key. */
    enum class Step(val text: String) {
        TAP_OPEN("Tap the button below to open Settings."),
        /** Android's Default apps page: "Browser app" → Firefox. iOS picks the path per iOS version. */
        TAP_BROWSER_APP("Tap Browser app, then choose Firefox."),
        COME_BACK("Go back to Shoo, then tap Keep going."),
    }

    fun steps(): List<Step> = listOf(Step.TAP_OPEN, Step.TAP_BROWSER_APP, Step.COME_BACK)

    /** Android's Default apps settings (iOS 18.3+ Default Apps), or Settings when a phone has no such page. */
    fun openSettings(context: Context) {
        if (ExtensionSetup.start(context, Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS))) return
        ExtensionSetup.start(context, Intent(Settings.ACTION_SETTINGS))
    }
}

/** The button opens Settings; once the user is back it turns into "Keep going". */
@Composable
fun SafariDefaultView(onBack: () -> Unit, onContinue: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val phase = rememberOnboardingScenePhase()
    var openedSettings by remember { mutableStateOf(false) }
    var cameBack by remember { mutableStateOf(false) }
    var isVideoPresented by remember { mutableStateOf(false) }
    val steps = remember { SafariDefaultSetup.steps() }

    // iOS `.onChange(of: scenePhase)`: back in the app after Settings.
    LaunchedEffect(phase) {
        if (phase.isActive && openedSettings) cameBack = true
    }

    OnboardingFormPage(
        title = "Set Firefox as default",
        onBack = onBack,
        modifier = modifier,
        largeHeadline = true,
        footerEndsWithLink = true,
        // Figma "Frame 2": 354 wide, one line.
        headlineInset = 24.dp,
        // Figma "image 1" at y 72.5, the headline right under it at 373.
        // iOS art (Safari in Settings › Default Apps); there is no Firefox version of it yet.
        hero = { OnboardingHeroImage(image = R.drawable.safari_default_illustration, top = 10.5.dp, bottom = 0.5.dp) },
        content = {
            // Figma "stack": 16 between rows, 40 under the headline.
            Column(
                modifier = Modifier.fillMaxWidth().padding(top = 40.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                steps.forEachIndexed { index, step ->
                    OnboardingStepRow(number = index + 1, text = step.text)
                }
            }
        },
        footer = {
            // Back from Settings, "Make Firefox default" crossfades into "Keep going".
            Crossfade(targetState = cameBack, animationSpec = shooSmooth(0.3), label = "safariDefaultButton") { back ->
                if (back) {
                    OnboardingCapsuleButton(title = "Keep going", onClick = onContinue, identifier = "safariDefault.continue")
                } else {
                    OnboardingCapsuleButton(
                        title = "Make Firefox default",
                        onClick = {
                            openedSettings = true
                            SafariDefaultSetup.openSettings(context)
                        },
                        identifier = "safariDefault.open",
                    )
                }
            }
            OnboardingTutorialLink(
                action = { isVideoPresented = true },
                modifier = Modifier.semantics { testTag = "safariDefault.video" },
            )
        },
    )

    if (isVideoPresented) TutorialVideoPlayer(onDismiss = { isVideoPresented = false })
}
