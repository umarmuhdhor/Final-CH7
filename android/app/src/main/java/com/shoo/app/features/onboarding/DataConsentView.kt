package com.shoo.app.features.onboarding

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.shoo.app.app.AppConfig
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.dynamicColor
import com.shoo.app.support.t

/**
 * Apple 5.1.1(ii) and 5.1.2(i): says what leaves the phone, and that a third-party AI gets some of it, and asks before
 * the first check. Shown once in onboarding, and to a device registered before the question existed. `DataConsent`
 * holds the answer; Profile changes it later.
 *
 * `onBack`: null for a registered device (there is no step to go back to). `onDecide`: `true` = "Allow online check"
 * (iOS `onAnswer(.granted)`), `false` = "Continue without it" (`.declined`); `RootView` saves it.
 */
@Composable
fun DataConsentView(onBack: (() -> Unit)?, modifier: Modifier = Modifier, onDecide: (Boolean) -> Unit) {
    val context = LocalContext.current
    val language = LocalAppLanguage.current
    OnboardingFormPage(
        title = "Before you start",
        message = "Shoo checks the pages you open in Firefox. This is what leaves your phone.",
        onBack = onBack,
        modifier = modifier,
        largeHeadline = true,
        footerEndsWithLink = true,
        content = {
            Column(
                modifier = Modifier.fillMaxWidth().padding(top = 20.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                ConsentRow(
                    "doc.text.magnifyingglass", title = "Pages you open",
                    text = "With the online check on, Shoo's server reads the page's text, form field names and address without the part after “?”. Text you type is not sent. Pages scored under 30 are not stored.",
                )
                ConsentRow(
                    "exclamationmark.shield", title = "Risky pages",
                    text = "Shoo keeps the address, a copy of the page and the flagged parts. You and your Guardian can see them. Some of this stays after you delete your account.",
                )
                ConsentRow(
                    "sparkles", title = "AI check by DeepSeek",
                    text = "With the online check on, Shoo's server may send DeepSeek, an AI company in China, a short summary of a suspicious page: site name, page title and form field names.",
                )
                OnboardingLinkButton(
                    title = "Read the privacy policy",
                    onClick = {
                        val page = AppConfig.legalPage("privacy", language)
                        ExtensionSetup.start(context, Intent(Intent.ACTION_VIEW, Uri.parse(page)))
                    },
                    weight = FontWeight.SemiBold,
                    identifier = "consent.privacy",
                )
            }
        },
        footer = {
            OnboardingCapsuleButton(title = "Allow online check", onClick = { onDecide(true) }, identifier = "consent.allow")
            OnboardingLinkButton(
                title = "Continue without it",
                onClick = { onDecide(false) },
                weight = FontWeight.SemiBold,
                identifier = "consent.decline",
            )
            Text(
                t("Without it, Shoo checks pages on your phone only and protects you less. Risky pages are still reported. You can change this in Profile."),
                style = onboardingFont(13f, rounded = true).copy(color = OnboardingTheme.secondaryInk, textAlign = TextAlign.Center),
                modifier = Modifier.fillMaxWidth(),
            )
        },
    )
}

/** `title`, `text`: catalog keys. */
@Composable
private fun ConsentRow(symbol: String, title: String, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
        // `.font(.title3)` in the app's tint (the system blue: the app sets no accent colour).
        Box(Modifier.width(28.dp).clearAndSetSemantics { }, contentAlignment = Alignment.TopCenter) {
            SfSymbol(symbol, pointSize = 20f, tint = dynamicColor(0x007AFF, 0x0A84FF))
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                t(title),
                style = onboardingFont(16f, FontWeight.SemiBold, rounded = true).copy(color = OnboardingTheme.ink),
                modifier = Modifier.semantics { heading() },
            )
            Text(t(text), style = onboardingFont(14f, rounded = true).copy(color = OnboardingTheme.secondaryInk))
        }
    }
}
