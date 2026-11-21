package com.shoo.app.features.pairing

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.shoo.app.R
import com.shoo.app.app.InviteNotice
import com.shoo.app.app.Router
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.LocalIsDarkTheme
import com.shoo.app.components.SystemColors
import com.shoo.app.components.SystemTextStyle
import com.shoo.app.components.labelColor
import com.shoo.app.components.shooShadow
import com.shoo.app.components.systemTextStyle
import com.shoo.app.features.onboarding.OnboardingTheme
import com.shoo.app.features.onboarding.onboardingPress
import com.shoo.app.support.t

/**
 * PR-03: what Home says about an invite link opened after onboarding (Figma "Flow · Protected buka link undangan",
 * "Notif undangan"). A card at the top of Home; nothing joins until the Hubungkan tap (T11).
 */
@Composable
fun InviteNoticeBanner(notice: InviteNotice, router: Router, modifier: Modifier = Modifier) {
    val title = when (notice) {
        InviteNotice.Invited -> t("You've got a family invite")
        InviteNotice.HasMembers -> t("You can't join another family yet")
        is InviteNotice.AlreadyProtected -> t("You're already protected by %@", notice.guardian)
    }
    val message = when (notice) {
        InviteNotice.Invited -> t("Join as Protected so your guardian can help check suspicious sites.")
        InviteNotice.HasMembers -> t("You still protect someone. Disconnect them in Profile first, then open the link again.")
        is InviteNotice.AlreadyProtected -> t("Only %@ can disconnect you. This invite won't be used.", notice.guardian)
    }
    val shape = RoundedCornerShape(26.dp)
    // Near solid, so the text keeps its contrast over the blue hero (Figma "Notif undangan": white 97 %).
    val cardColor = (if (LocalIsDarkTheme.current) Color.Black else Color.White).copy(alpha = 0.97f)
    Column(
        modifier
            .padding(horizontal = 16.dp)
            .fillMaxWidth()
            .shooShadow(Color.Black.copy(alpha = 0.18f), radius = 24.dp, y = 10.dp, shape = shape)
            .background(cardColor, shape)
            .semantics { testTag = "invite.notice" }
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            Image(
                painter = painterResource(R.drawable.shoo_logo),
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(10.dp)),
            )
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    title,
                    style = systemTextStyle(SystemTextStyle.HEADLINE),
                    color = labelColor,
                    modifier = Modifier.semantics { heading() },
                )
                Text(message, style = systemTextStyle(SystemTextStyle.SUBHEADLINE), color = SystemColors.secondary)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            when (notice) {
                InviteNotice.Invited -> {
                    NoticeButton("Not now", "invite.notice.later", primary = false) { router.dismissInviteNotice() }
                    NoticeButton("View", "invite.notice.view", primary = true) { router.acceptInvite() }
                }
                InviteNotice.HasMembers -> {
                    NoticeButton("Close", "invite.notice.close", primary = false) { router.dismissInviteNotice() }
                    NoticeButton("Open Profile", "invite.notice.profile", primary = true) { router.openProfileFromInviteNotice() }
                }
                is InviteNotice.AlreadyProtected ->
                    NoticeButton("OK", "invite.notice.ok", primary = true) { router.dismissInviteNotice() }
            }
        }
    }
}

/**
 * Primary: the app's navy pill (`OnboardingTheme.buttonGradient`), 44 pt tall to fit the card. Secondary: the system
 * tertiary fill with the label colour. `title`: catalog key.
 */
@Composable
private fun RowScope.NoticeButton(title: String, identifier: String, primary: Boolean, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    // iOS `Color(.tertiarySystemFill)`.
    val tertiaryFill = if (LocalIsDarkTheme.current) Color(0x3D767680) else Color(0x1F767680)
    Box(
        Modifier
            .weight(1f)
            .heightIn(min = 44.dp)
            .onboardingPress(interaction)
            .background(
                if (primary) OnboardingTheme.buttonGradient else Brush.verticalGradient(listOf(tertiaryFill, tertiaryFill)),
                CapsuleShape,
            )
            .clickable(interactionSource = interaction, indication = null, role = Role.Button, onClick = onClick)
            .semantics { testTag = identifier },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            t(title),
            style = systemTextStyle(SystemTextStyle.BODY, FontWeight.SemiBold),
            color = if (primary) OnboardingTheme.onButton else labelColor,
        )
    }
}

