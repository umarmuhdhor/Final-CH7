package com.shoo.app.features.onboarding

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * Figma "To be guardian" (1229:1904): shown before Family mode turns on for the first time ("Menjadi Guardian" on
 * Profile, Home ⇆, Account mode). "Mulai" turns it on; Back keeps Pribadi.
 */
@Composable
fun GuardianIntroView(onBack: () -> Unit, onStart: () -> Unit, modifier: Modifier = Modifier) {
    OnboardingFormPage(
        title = "Protect the people\nclosest to you",
        message = "Protect them by double-checking what Shoo finds for the people closest to you!",
        onBack = onBack,
        modifier = modifier,
        largeHeadline = true,
        headlineInset = 45.dp,
        tealHeader = true,
        hero = { FamilyCardIllustration() },
        content = {},
        footer = {
            OnboardingCapsuleButton(title = "Get started", onClick = onStart, identifier = "guardianIntro.start")
        },
    )
}
