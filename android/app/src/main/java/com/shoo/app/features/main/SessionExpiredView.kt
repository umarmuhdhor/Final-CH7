package com.shoo.app.features.main

import android.os.Build
import android.view.HapticFeedbackConstants
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import com.shoo.app.app.LocalAppEnvironment
import com.shoo.app.components.HalftoneShield
import com.shoo.app.components.HalftoneShieldSize
import com.shoo.app.components.StateHeroPage
import com.shoo.app.components.StateInfoList
import com.shoo.app.components.StateInfoRow
import com.shoo.app.features.onboarding.OnboardingCapsuleButton

/**
 * The server no longer knows this phone (401), or its token didn't come along from a backup. MVP answer (SECURITY
 * T3, P1): say so plainly and start onboarding again. Figma "Sesi berakhir" (1665:2991): the switched-off shield on the
 * blue hero, "Tidak terhubung", the line, "iPhone ini belum terlindungi" (Android: "this phone") and "Siapkan lagi".
 */
@Composable
fun SessionExpiredView(modifier: Modifier = Modifier) {
    val env = LocalAppEnvironment.current
    val view = LocalView.current
    // Felt as well as read: something needs the person's attention (iOS `.sensoryFeedback(.warning)`).
    LaunchedEffect(Unit) {
        view.performHapticFeedback(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS,
        )
    }
    StateHeroPage(
        title = "Session expired",
        message = "This phone isn't connected to Shoo anymore. Set it up again to stay protected.",
        modifier = modifier,
        chip = "Not connected",
        titleIdentifier = "sessionExpired",
        shield = {
            // Figma "Shield Kaca Halftone · Mati": 210 × 230, the top 110 pt down the frame.
            HalftoneShield(
                modifier = Modifier
                    .requiredSize(HalftoneShieldSize)
                    .offset(y = (-38).dp)
                    .graphicsLayer {
                        scaleX = 1.25f
                        scaleY = 1.25f
                    },
                isOn = false,
            )
        },
        content = {
            StateInfoList(rows = listOf(StateInfoRow("exclamationmark.shield.fill", "This phone isn't protected yet")))
        },
        footer = {
            OnboardingCapsuleButton(title = "Set up again", onClick = env::restartOnboarding, identifier = "sessionExpired.restart")
        },
    )
}
