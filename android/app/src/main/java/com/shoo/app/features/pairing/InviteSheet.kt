package com.shoo.app.features.pairing

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.view.HapticFeedbackConstants
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.FigmaFont
import com.shoo.app.components.LightOnly
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.components.LocalReduceGlass
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.StateMessage
import com.shoo.app.components.SystemColors
import com.shoo.app.components.SystemTextStyle
import com.shoo.app.components.dynamicColor
import com.shoo.app.components.hex
import com.shoo.app.components.shimmering
import com.shoo.app.components.shooEaseInOut
import com.shoo.app.components.shooEaseOut
import com.shoo.app.components.shooShadow
import com.shoo.app.components.shooSnappy
import com.shoo.app.components.shooSpring
import com.shoo.app.components.systemTextStyle
import com.shoo.app.data.ShooRepository
import com.shoo.app.features.activity.privacyCover
import com.shoo.app.features.onboarding.OnboardingCapsuleButton
import com.shoo.app.features.onboarding.OnboardingTheme
import com.shoo.app.features.onboarding.onboardingFont
import com.shoo.app.support.DeliveredPushes
import com.shoo.app.support.L10n
import com.shoo.app.support.t
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * GD-04 in onboarding (Figma "Kirim Undangan"): QR, the 6-digit code, "Refresh code", and a row to copy or send the
 * invite. Same code rules as `FamilyCodeView` (valid 30 min, copy expires with it). Light only, like iOS.
 *
 * The content of a sheet: the caller shows it in a `ModalBottomSheet` (iOS `.presentationDragIndicator(.visible)`:
 * keep the sheet's drag handle). `onDone`: the check mark, the Guardian is done inviting. `onDismiss`: iOS `dismiss()`
 * (the close button and "Manage family"); null = `onDone`. `onDone` comes last so it stays a trailing lambda.
 */
@Composable
fun InviteSheet(
    repository: ShooRepository,
    modifier: Modifier = Modifier,
    onDismiss: (() -> Unit)? = null,
    onDone: () -> Unit,
) {
    LightOnly { InviteSheetContent(repository, modifier, onDismiss ?: onDone, onDone) }
}

@Composable
private fun InviteSheetContent(repository: ShooRepository, modifier: Modifier, dismiss: () -> Unit, onDone: () -> Unit) {
    val context = LocalContext.current
    val view = LocalView.current
    val language = LocalAppLanguage.current
    val reduceMotion = LocalReduceMotion.current
    val scope = rememberCoroutineScope()
    val model = remember(repository) {
        SystemPasteboard.install(context)
        FamilyCodeModel(repository, clearDeliveredPushes = { DeliveredPushes.clear(context.applicationContext) })
    }
    // Bumped by each copy: "Link undangan tersalin" shows for a moment in place of "Refresh code".
    var copies by remember { mutableIntStateOf(0) }
    var showsCopiedNote by remember { mutableStateOf(false) }

    LaunchedEffect(model) { model.run() }
    LaunchedEffect(copies) {
        if (copies == 0) return@LaunchedEffect
        showsCopiedNote = true
        view.performHapticFeedback(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.KEYBOARD_TAP,
        )
        delay(2000)
        showsCopiedNote = false
    }

    val background = OnboardingTheme.background
    Column(
        modifier
            .fillMaxSize()
            .background(background)
            .privacyCover(),
    ) {
        InviteToolbar(onClose = dismiss, onDone = onDone)
        Column(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(
                Modifier
                    .widthIn(max = 400.dp)
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    // Figma: the headline 32 pt under the toolbar.
                    .padding(top = 32.dp),
                verticalArrangement = Arrangement.spacedBy(15.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    t("Scan the QR code or send the link"),
                    style = onboardingFont(27f, FontWeight.Medium, tracking = -0.27f, lineHeight = 29.7f),
                    color = OnboardingTheme.ink,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 9.dp)
                        .semantics { heading() },
                )
                // Figma: the QR card and code are 311 pt wide on a 402 pt screen.
                Column(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 25.dp),
                    verticalArrangement = Arrangement.spacedBy(15.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    CodeContent(model, showsCopiedNote, reduceMotion, onRefresh = { scope.launch { model.refreshCode(replace = true) } })
                }
            }
            Spacer(Modifier.height(16.dp))
        }
        // Figma "App Icon Row": 18 above the icons; the names end 80 pt above the screen bottom.
        AnimatedContent(
            targetState = model.codeState.kind,
            transitionSpec = {
                fadeIn(shooEaseInOut(0.25)) togetherWith fadeOut(shooEaseInOut(0.25)) using
                    SizeTransform(clip = false) { _, _ -> shooEaseInOut<IntSize>(0.25) }
            },
            modifier = Modifier
                .fillMaxWidth()
                .background(background)
                .navigationBarsPadding()
                .padding(start = 24.dp, end = 24.dp, top = 18.dp, bottom = 46.dp),
            contentAlignment = Alignment.Center,
            label = "inviteFooter",
        ) { kind ->
            when (kind) {
                0 -> InviteShareRowSkeleton()
                1 -> ShareRow(model) { action ->
                    val code = model.code ?: return@ShareRow
                    val text = FamilyCodeModel.inviteText(code, language)
                    when (action) {
                        ShareAction.COPY -> if (model.copyInvite(language)) {
                            copies += 1
                            @Suppress("DEPRECATION")
                            view.announceForAccessibility(L10n.string("Invite link copied", language))
                        }
                        ShareAction.WHATSAPP -> InviteShare.send(context, text, InviteShare.whatsAppIntent(text))
                        ShareAction.MESSAGES -> InviteShare.send(context, text, InviteShare.messagesIntent(text))
                        ShareAction.MORE -> InviteShare.shareSheet(context, text)
                    }
                }
                // Figma: the button ends 115 pt above the screen bottom, higher than the icon row.
                2 -> OnboardingCapsuleButton(
                    title = "Try again",
                    onClick = { scope.launch { model.refreshCode() } },
                    identifier = "invite.retry",
                    modifier = Modifier.padding(bottom = 34.dp),
                )
                // Profile is right under this sheet: closing it shows the family to remove someone from.
                else -> OnboardingCapsuleButton(
                    title = "Manage family",
                    onClick = dismiss,
                    identifier = "invite.manageFamily",
                    modifier = Modifier.padding(bottom = 34.dp),
                )
            }
        }
    }
}

/** Which footer and body show; their swaps cross-fade. */
private val FamilyCodeModel.CodeState.kind: Int
    get() = when (this) {
        FamilyCodeModel.CodeState.Loading -> 0
        is FamilyCodeModel.CodeState.Ready -> 1
        FamilyCodeModel.CodeState.Unavailable -> 2
        FamilyCodeModel.CodeState.Full -> 3
    }

/** Inline "Send invite" bar: a close button on the left, the check mark (done) on the right (iOS 26 toolbar). */
@Composable
private fun InviteToolbar(onClose: () -> Unit, onDone: () -> Unit) {
    val reduceGlass = LocalReduceGlass.current
    Box(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 60.dp)
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        val closeLabel = t("Close")
        Box(
            Modifier
                .align(Alignment.CenterStart)
                .size(44.dp)
                .then(
                    if (reduceGlass) {
                        Modifier.background(Color.White, CircleShape)
                    } else {
                        Modifier
                            .shooShadow(Color.Black.copy(alpha = 0.08f), radius = 12.dp, y = 4.dp, shape = CircleShape)
                            .background(Color.White.copy(alpha = 0.82f), CircleShape)
                    },
                )
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, role = Role.Button, onClick = onClose)
                .clearAndSetSemantics {
                    contentDescription = closeLabel
                    testTag = "invite.close"
                },
            contentAlignment = Alignment.Center,
        ) {
            SfSymbol("xmark", pointSize = 17f, tint = OnboardingTheme.ink)
        }
        Text(
            t("Send invite"),
            style = systemTextStyle(SystemTextStyle.HEADLINE),
            color = OnboardingTheme.ink,
            modifier = Modifier
                .align(Alignment.Center)
                .semantics { heading() },
        )
        val doneLabel = t("Done")
        // `.borderedProminent` + `.circle`: the tinted filled round button.
        Box(
            Modifier
                .align(Alignment.CenterEnd)
                .size(44.dp)
                .background(SystemColors.blue, CircleShape)
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, role = Role.Button, onClick = onDone)
                .clearAndSetSemantics {
                    contentDescription = doneLabel
                    testTag = "invite.done"
                },
            contentAlignment = Alignment.Center,
        ) {
            SfSymbol("checkmark", pointSize = 17f, tint = Color.White)
        }
    }
}

@Composable
private fun CodeContent(model: FamilyCodeModel, showsCopiedNote: Boolean, reduceMotion: Boolean, onRefresh: () -> Unit) {
    when (val state = model.codeState) {
        FamilyCodeModel.CodeState.Loading -> {
            // Figma "Kirim Undangan · Mengambil kode" (1681:5872): the QR and code as grey blocks that shimmer.
            Column(
                Modifier
                    .shimmering()
                    .clearAndSetSemantics { },
                verticalArrangement = Arrangement.spacedBy(15.dp),
            ) {
                QRCard { InviteQRSkeleton() }
                Box(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 56.dp)
                        .background(OnboardingTheme.card, RoundedCornerShape(16.dp)),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(Modifier.size(width = 112.dp, height = 14.dp).background(hex(0xE2E7EE), CapsuleShape))
                }
            }
            Text(
                t("Preparing the invite code…"),
                style = onboardingFont(17f, rounded = true),
                color = hex(0x6A717E),
                modifier = Modifier
                    .padding(top = 2.dp)
                    .semantics { testTag = "invite.loading" },
            )
        }
        is FamilyCodeModel.CodeState.Ready -> {
            val code = state.code
            QRCard {
                val url = model.inviteURL
                val qr = remember(url) { url?.let { QRCode.image(it) } }
                if (qr != null) {
                    val label = t("QR code to join your family")
                    Image(
                        bitmap = qr,
                        contentDescription = label,
                        filterQuality = FilterQuality.None,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier
                            .fillMaxSize()
                            // Figma: the code's modules span 240 pt of the 311 × 303 card.
                            .padding(horizontal = 25.dp, vertical = 21.dp)
                            .semantics { testTag = "invite.qr" },
                    )
                }
            }
            val codeLabel = t("Code %@", code.code.toList().joinToString(" "))
            Box(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 56.dp)
                    .background(OnboardingTheme.card, RoundedCornerShape(16.dp))
                    .clearAndSetSemantics {
                        contentDescription = codeLabel
                        testTag = "invite.code"
                    },
                contentAlignment = Alignment.Center,
            ) {
                // "Refresh code": the digits roll to the new code (a cross-fade with Reduce Motion). Only the code; the
                // "Valid for" countdown under it ticks every second and stays still.
                // `.numericText()` under `.snappy(0.3)`; Reduce Motion: a cross-fade under `.easeInOut(0.2)`.
                NumericText(
                    FamilyCodeModel.display(code.code),
                    // Figma "SF Pro Text Bold 20", -2 %.
                    style = onboardingFont(20f, FontWeight.Bold, tracking = -0.4f, family = FigmaFont.Family.TEXT)
                        .copy(fontFeatureSettings = "tnum"),
                    color = OnboardingTheme.ink,
                    reduceMotion = reduceMotion,
                    reduceMotionSpec = shooEaseInOut(0.2),
                )
            }
            AnimatedContent(
                targetState = showsCopiedNote,
                transitionSpec = {
                    // In: `withAnimation(StateMotion.enter)`, out: `withAnimation(.easeOut(0.25))`, for both views and the size.
                    if (targetState) {
                        val spec = if (reduceMotion) shooEaseOut<Float>(0.2) else shooSpring<Float>(0.32, 0.18)
                        (if (reduceMotion) fadeIn(spec) else fadeIn(spec) + scaleIn(spec, initialScale = 0.92f)) togetherWith
                            fadeOut(spec) using
                            SizeTransform(clip = false) { _, _ -> if (reduceMotion) shooEaseOut<IntSize>(0.2) else shooSpring<IntSize>(0.32, 0.18) }
                    } else {
                        fadeIn(shooEaseOut(0.25)) togetherWith
                            (if (reduceMotion) fadeOut(shooEaseOut(0.25)) else fadeOut(shooEaseOut(0.25)) + scaleOut(shooEaseOut(0.25), targetScale = 0.92f)) using
                            SizeTransform(clip = false) { _, _ -> shooEaseOut<IntSize>(0.25) }
                    }
                },
                contentAlignment = Alignment.Center,
                label = "copiedNote",
            ) { copied ->
                if (copied) {
                    // Figma "Link tersalin" (1681:6222): a check and the line where "Refresh code" was.
                    Row(
                        Modifier
                            .heightIn(min = 44.dp)
                            .semantics(mergeDescendants = true) { testTag = "invite.copiedNote" },
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        SfSymbol("checkmark", pointSize = 15f, tint = hex(0x34C759))
                        Text(t("Invite link copied"), style = onboardingFont(15f, FontWeight.Medium), color = hex(0x191D2F))
                    }
                } else {
                    RefreshAndCountdown(model, onRefresh)
                }
            }
        }
        // Figma "Gagal mengambil kode" (1681:5974); "Try again" is the footer button.
        FamilyCodeModel.CodeState.Unavailable -> StateMessage(
            systemImage = "exclamationmark.arrow.circlepath",
            tint = hex(0xE5483B),
            title = "Code can't be made yet",
            message = t("Check your internet connection, then try again."),
            modifier = Modifier.semantics { testTag = "invite.unavailable" },
        )
        // Figma "Keluarga penuh" (1681:6059); "Manage family" is the footer button.
        FamilyCodeModel.CodeState.Full -> StateMessage(
            systemImage = "person.2.fill",
            tint = hex(0x136CB7),
            title = "Family is full",
            message = t("A family has at most 3 people.\nRemove one to invite again."),
            symbolSize = 27f,
            modifier = Modifier.semantics { testTag = "invite.full" },
        )
    }
}

@Composable
private fun RefreshAndCountdown(model: FamilyCodeModel, onRefresh: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        val canReplace = model.canReplace
        val color = if (canReplace) InviteColors.refreshBlue else OnboardingTheme.secondaryInk
        val interaction = remember { MutableInteractionSource() }
        val pressed by interaction.collectIsPressedAsState()
        // Figma "Refresh Kode": SF Pro Display Semibold 15, no tracking (`OnboardingLinkButtonStyle`).
        Row(
            Modifier
                .heightIn(min = 44.dp)
                .clickable(interactionSource = interaction, indication = null, enabled = canReplace, role = Role.Button, onClick = onRefresh)
                .semantics(mergeDescendants = true) { testTag = "invite.refresh" }
                .graphicsLayer { alpha = if (pressed) 0.6f else 1f },
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // A new code: the old one stops working, also in links already sent. Waiting a minute after the last refresh
            // (issue #227): the code on screen keeps working.
            SfSymbol(if (canReplace) "arrow.clockwise" else "lock.fill", pointSize = 15f, tint = color)
            Text(
                if (canReplace) t("Refresh code") else t("New code in %@", model.replaceUnlocksIn),
                style = onboardingFont(15f, FontWeight.SemiBold, tracking = 0f, lineHeight = 20f).copy(fontFeatureSettings = "tnum"),
                color = color,
            )
        }
        Text(
            t("Valid for %@", model.timeLeft),
            style = onboardingFont(13f, rounded = true).copy(fontFeatureSettings = "tnum"),
            color = OnboardingTheme.secondaryInk,
            modifier = Modifier.semantics { testTag = "invite.countdown" },
        )
    }
}

/** White rounded square that holds the QR (Figma "Frame 87", 311 × 303, radius 28). Black on white in any theme. */
@Composable
private fun QRCard(content: @Composable () -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .aspectRatio(311f / 303f)
            .background(Color.White, RoundedCornerShape(28.dp)),
        contentAlignment = Alignment.Center,
    ) { content() }
}

private object InviteColors {
    val refreshBlue = Color(red = 0x03 / 255f, green = 0x67 / 255f, blue = 0xB6 / 255f)

    /** WhatsApp's brand green, so the tile is recognised at a glance. */
    val whatsAppGreen = Color(red = 0x25 / 255f, green = 0xD3 / 255f, blue = 0x66 / 255f)
}

private enum class ShareAction { COPY, WHATSAPP, MESSAGES, MORE }

@Composable
private fun ShareRow(model: FamilyCodeModel, onAction: (ShareAction) -> Unit) {
    val enabled = model.code != null && model.inviteURL != null
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        ShareTile(
            title = if (model.copied) "Copied" else "Copy",
            systemImage = if (model.copied) "checkmark" else "doc.on.doc",
            fill = null,
            enabled = enabled,
            identifier = "invite.copy",
        ) { onAction(ShareAction.COPY) }
        Spacer(Modifier.weight(1f).widthIn(min = 4.dp))
        // WhatsApp first: that is where families send the link (PR-03), without a detour through "More".
        ShareTile("WhatsApp", "phone.bubble.fill", InviteColors.whatsAppGreen, enabled, "invite.whatsapp") { onAction(ShareAction.WHATSAPP) }
        Spacer(Modifier.weight(1f).widthIn(min = 4.dp))
        ShareTile("Messages", "message.fill", SystemColors.green, enabled, "invite.messages") { onAction(ShareAction.MESSAGES) }
        Spacer(Modifier.weight(1f).widthIn(min = 4.dp))
        ShareTile("More", "square.and.arrow.up", null, enabled, "invite.more") { onAction(ShareAction.MORE) }
    }
}

/** One 66 pt round button with its name under it (Figma "App Icon Row"). `title`: catalog key. `fill` null = plain. */
@Composable
private fun ShareTile(
    title: String,
    systemImage: String,
    fill: Color?,
    enabled: Boolean,
    identifier: String,
    onClick: () -> Unit,
) {
    val reduceMotion = LocalReduceMotion.current
    val plainFill = dynamicColor(0xEDEDED, 0x2A303A)
    val label = t(title)
    Column(
        Modifier
            .width(78.dp)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .clearAndSetSemantics {
                contentDescription = label
                testTag = identifier
            },
        verticalArrangement = Arrangement.spacedBy(7.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .size(66.dp)
                .then(
                    if (fill == null) {
                        Modifier.background(plainFill, CircleShape)
                    } else {
                        // SwiftUI `Color.gradient`.
                        Modifier.background(
                            Brush.verticalGradient(listOf(lerp(fill, Color.White, 0.12f), lerp(fill, Color.Black, 0.06f))),
                            RoundedCornerShape(15.dp),
                        )
                    },
                ),
            contentAlignment = Alignment.Center,
        ) {
            // Copy → checkmark: the symbol morphs (a cross-fade with Reduce Motion).
            AnimatedContent(
                targetState = systemImage,
                transitionSpec = {
                    if (reduceMotion) {
                        fadeIn(shooEaseInOut(0.2)) togetherWith fadeOut(shooEaseInOut(0.2))
                    } else {
                        (fadeIn(shooSnappy(0.3)) + scaleIn(shooSnappy(0.3), initialScale = 0.6f)) togetherWith
                            (fadeOut(shooSnappy(0.3)) + scaleOut(shooSnappy(0.3), targetScale = 0.6f))
                    }
                },
                label = "tileSymbol",
            ) { symbol ->
                // `.font(.system(size: 25))`: a fixed size.
                androidx.compose.material3.Icon(
                    com.shoo.app.components.sfSymbol(symbol),
                    contentDescription = null,
                    tint = if (fill == null) OnboardingTheme.ink else Color.White,
                    modifier = Modifier.size(35.dp),
                )
            }
        }
        // Figma "App Name": SF Pro Regular 11, the system share sheet's label.
        Text(
            label,
            style = onboardingFont(11f, family = FigmaFont.Family.SF_PRO),
            color = OnboardingTheme.ink,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** Figma "Mengambil kode": the three finder squares and a centre block on #F5F8FC, all #E2E7EE / #EAEEF3. */
@Composable
private fun InviteQRSkeleton() {
    BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        val side = minOf(maxWidth, maxHeight) * 0.84f
        val block = side * 0.24f
        Box(
            Modifier
                .size(side)
                .background(hex(0xF5F8FC), RoundedCornerShape(14.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                Modifier
                    .fillMaxSize()
                    .padding(side * 0.07f),
                verticalArrangement = Arrangement.SpaceBetween,
            ) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Box(Modifier.size(block).background(hex(0xE2E7EE), RoundedCornerShape(14.dp)))
                    Box(Modifier.size(block).background(hex(0xE2E7EE), RoundedCornerShape(14.dp)))
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Box(Modifier.size(block).background(hex(0xE2E7EE), RoundedCornerShape(14.dp)))
                    Box(Modifier.size(block).background(hex(0xEAEEF3), RoundedCornerShape(14.dp)))
                }
            }
            Box(Modifier.size(block * 0.74f).background(hex(0xEAEEF3), RoundedCornerShape(10.dp)))
        }
    }
}

/** Figma "Skeleton bagikan": four grey tiles with a short bar under each, shimmering. */
@Composable
private fun InviteShareRowSkeleton() {
    Row(
        Modifier
            .fillMaxWidth()
            .shimmering()
            .clearAndSetSemantics { },
        verticalAlignment = Alignment.Top,
    ) {
        repeat(4) { index ->
            if (index > 0) Spacer(Modifier.weight(1f).widthIn(min = 4.dp))
            Column(
                Modifier
                    .width(78.dp)
                    .height(90.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Box(Modifier.size(66.dp).background(hex(0xE2E7EE), RoundedCornerShape(15.dp)))
                Box(Modifier.size(width = 44.dp, height = 8.dp).background(hex(0xEAEEF3), CapsuleShape))
            }
        }
    }
}

/**
 * WhatsApp and the default SMS app with the invite filled in, or the system share sheet. Nothing is sent until the
 * user taps Send there. iOS: `whatsapp://send?text=` and `sms:&body=` links.
 */
object InviteShare {
    const val whatsAppPackage = "com.whatsapp"

    /** RFC 3986 unreserved only: `&`, `=`, `+` and `?` in the text must not split the query. */
    private fun encode(text: String): String = buildString {
        for (byte in text.toByteArray(Charsets.UTF_8)) {
            val c = byte.toInt() and 0xFF
            val ch = c.toChar()
            if (ch in 'A'..'Z' || ch in 'a'..'z' || ch in '0'..'9' || ch == '-' || ch == '.' || ch == '_' || ch == '~') {
                append(ch)
            } else {
                append('%').append("%02X".format(c))
            }
        }
    }

    /** iOS `messagesURL(body:)`. */
    fun messagesURL(body: String): String = "sms:&body=${encode(body)}"

    /** iOS `whatsAppURL(text:)`. */
    fun whatsAppURL(text: String): String = "whatsapp://send?text=${encode(text)}"

    /** WhatsApp's own share target: its contact picker with the text filled in. */
    fun whatsAppIntent(text: String): Intent = Intent(Intent.ACTION_SEND)
        .setType("text/plain")
        .setPackage(whatsAppPackage)
        .putExtra(Intent.EXTRA_TEXT, text)

    /** The default SMS app with the text as the body. */
    fun messagesIntent(body: String): Intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:"))
        .putExtra("sms_body", body)

    /** Opens that app; the share sheet when it can't (WhatsApp not installed, no SMS app). */
    fun send(context: Context, text: String, intent: Intent) {
        try {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: ActivityNotFoundException) {
            shareSheet(context, text)
        } catch (_: SecurityException) {
            shareSheet(context, text)
        }
    }

    /** "More": the system share sheet for the invite text (iOS `UIActivityViewController`). */
    fun shareSheet(context: Context, text: String) {
        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
        try {
            context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: ActivityNotFoundException) {
        }
    }
}

