package com.shoo.app.features.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.shoo.app.app.LocalAppEnvironment
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.SystemTextStyle
import com.shoo.app.components.dynamicColor
import com.shoo.app.components.shooEaseInOut
import com.shoo.app.components.shooSmooth
import com.shoo.app.components.systemTextStyle
import com.shoo.app.support.t
import kotlinx.coroutines.launch

/** ON-01 … ON-05 until the device is registered and onboarding is finished; then `RootView` shows the tabs. */
@Composable
fun OnboardingFlow(modifier: Modifier = Modifier) {
    val env = LocalAppEnvironment.current
    val model = remember(env) { OnboardingModel(env) }
    // iOS: Debug launch arguments (`-debug.onboardingStep`, `-debug.demo`) are not read here.
    LaunchedEffect(model) {
        if (model.step == OnboardingStep.DONE) env.finishOnboarding()
    }
    OnboardingStepView(model = model, modifier = modifier)
}

/** iOS `Color(.systemBackground)`. */
private val systemBackground: Color
    @Composable get() = dynamicColor(0xFFFFFF, 0x000000)

@Composable
private fun OnboardingStepView(model: OnboardingModel, modifier: Modifier = Modifier) {
    val reduceMotion = LocalReduceMotion.current
    // Outside the animated content: a step's work (notifications, registration) outlives its screen.
    val scope = rememberCoroutineScope()
    AnimatedContent(
        targetState = model.step,
        modifier = modifier.fillMaxSize(),
        transitionSpec = {
            if (reduceMotion) {
                fadeIn(shooEaseInOut(0.2)) togetherWith fadeOut(shooEaseInOut(0.2))
            } else {
                val back = model.movedBack
                (slideInHorizontally(shooSmooth<IntOffset>()) { if (back) -it else it } + fadeIn(shooSmooth())) togetherWith
                    (slideOutHorizontally(shooSmooth<IntOffset>()) { if (back) it else -it } + fadeOut(shooSmooth()))
            }
        },
        label = "onboardingStep",
    ) { step ->
        when (step) {
            OnboardingStep.SPLASH -> SplashView(model = model)
            OnboardingStep.NAME -> NameView(model = model)
            OnboardingStep.TURN_ON_EXTENSION -> OnboardingExtensionStep(model = model, runTask = { task -> scope.launch { task() } })
            OnboardingStep.SAFARI_DEFAULT -> SafariDefaultView(onBack = model::goBack, onContinue = model::continueFromSafariDefault)
            OnboardingStep.EXTENSION_ON -> ExtensionOnView(onContinue = { scope.launch { model.requestNotifications() } })
            OnboardingStep.DONE -> Box(Modifier.fillMaxSize().background(systemBackground))
        }
    }
}

/**
 * ON-04 inside onboarding: the consent checkbox (only while the question is unanswered) gates the button, and the
 * first tap registers the device.
 */
@Composable
private fun OnboardingExtensionStep(model: OnboardingModel, runTask: (suspend () -> Unit) -> Unit) {
    TurnOnExtensionView(
        refreshStatus = { model.refreshExtensionStatus() },
        onBack = if (model.canGoBackFromExtension) model::goBack else null,
        onSkipCheck = { runTask { model.skipExtensionCheck() } },
        consent = OnboardingExtensionConsent(
            isChecked = model.consentChecked,
            onIsCheckedChange = { model.consentChecked = it },
            showsCheckbox = model.showsConsentCheckbox,
            isWorking = model.isWorking,
            failed = model.registrationFailed,
            prepare = { model.activateExtension() },
        ),
    )
}

/** Bottom call-to-action shared by the older onboarding screens: full width, at least 50 pt, grows with text. `title`: catalog key. */
@Composable
fun OnboardingPrimaryButton(title: String, isWorking: Boolean = false, action: () -> Unit, modifier: Modifier = Modifier) {
    Button(
        onClick = action,
        modifier = modifier.fillMaxWidth().heightIn(min = 50.dp),
        shape = RoundedCornerShape(14.dp),
        colors = ButtonDefaults.buttonColors(containerColor = dynamicColor(0x007AFF, 0x0A84FF), contentColor = Color.White),
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(t(title), style = systemTextStyle(SystemTextStyle.HEADLINE), modifier = Modifier.alpha(if (isWorking) 0f else 1f))
            if (isWorking) CircularProgressIndicator(modifier = Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
        }
    }
}

/** Large symbol + title + one short sentence (persona: parents 45–65, PRD §3). `title`, `message`: catalog keys. */
@Composable
fun OnboardingHeader(systemImage: String, title: String, message: String, modifier: Modifier = Modifier) {
    val tint = dynamicColor(0x007AFF, 0x0A84FF)
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.clearAndSetSemantics { }) { SfSymbol(systemImage, pointSize = 72f, tint = tint) }
        Text(
            t(title),
            style = systemTextStyle(SystemTextStyle.TITLE, FontWeight.Bold).copy(textAlign = TextAlign.Center),
            modifier = Modifier.semantics { heading() },
        )
        Text(
            t(message),
            style = systemTextStyle(SystemTextStyle.TITLE3).copy(
                color = dynamicColor(0x3C3C43, 0xEBEBF5).copy(alpha = 0.6f),
                textAlign = TextAlign.Center,
            ),
        )
    }
}

/** Scrollable content with the button pinned at the bottom, so nothing clips at large text sizes. */
@Composable
fun OnboardingPage(
    content: @Composable ColumnScope.() -> Unit,
    footer: @Composable ColumnScope.() -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxSize().statusBarsPadding()) {
        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(24.dp)
                .fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            content = content,
        )
        // iOS `.background(.bar)`.
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(dynamicColor(0xF9F9F9, 0x1C1C1E).copy(alpha = 0.94f))
                .navigationBarsPadding()
                .padding(horizontal = 24.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            content = footer,
        )
    }
}
