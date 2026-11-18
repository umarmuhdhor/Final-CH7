package com.shoo.app.features.shield

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.shoo.app.app.LocalAppEnvironment
import com.shoo.app.features.onboarding.LocalPresentedInSheet
import com.shoo.app.features.onboarding.OnboardingTheme
import com.shoo.app.features.onboarding.TurnOnExtensionView
import com.shoo.app.features.onboarding.onboardingFont
import com.shoo.app.support.t

/**
 * ON-04's guide as a sheet (PR-04, GD-01, PF-01): how to turn the Shoo add-on on in Firefox for Android (install
 * Firefox, install the add-on, link it with the code; `TurnOnExtensionView` / `ExtensionSetup`, features/onboarding).
 * Closes itself once the add-on is linked and nothing is left to do (`nextStep == null`, #135).
 *
 * The content of a sheet: present it in a full-height `ModalBottomSheet` (`skipPartiallyExpanded = true`,
 * `dragHandle = null`), as `ShieldTurnOnSheet` does. `onDismiss` (iOS `@Environment(\.dismiss)`): Close and the
 * finished setup close it. iOS: a `NavigationStack` whose toolbar has "Close" on the leading side.
 */
@Composable
fun TurnOnExtensionSheet(onDismiss: () -> Unit = {}, modifier: Modifier = Modifier) {
    val env = LocalAppEnvironment.current
    val dismiss by rememberUpdatedState(onDismiss)
    val close = t("Close")
    CompositionLocalProvider(LocalPresentedInSheet provides true) {
        Box(modifier.fillMaxSize()) {
            TurnOnExtensionView(
                refreshStatus = {
                    val status = env.extensionStatus()
                    // Closes once Shoo is on and has checked in; until then the sheet says what is left (#135).
                    if (status.nextStep == null) dismiss()
                    status
                },
            )
            // The toolbar's cancellation action: "Close", 17 pt, in the tint colour.
            Box(
                Modifier
                    .align(Alignment.TopStart)
                    .padding(start = 8.dp, top = 4.dp)
                    .heightIn(min = 44.dp)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        role = Role.Button,
                        onClick = { dismiss() },
                    )
                    .padding(horizontal = 8.dp)
                    .testTag("turnOn.close"),
                contentAlignment = Alignment.Center,
            ) {
                Text(text = close, style = onboardingFont(17f), color = OnboardingTheme.link)
            }
        }
    }
}
