package com.shoo.app.features.pairing

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsBottomHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shoo.app.components.AvatarView
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.ShieldPulseLoader
import com.shoo.app.components.SystemColors
import com.shoo.app.components.SystemTextStyle
import com.shoo.app.components.dynamicColor
import com.shoo.app.components.labelColor
import com.shoo.app.components.readableRed
import com.shoo.app.components.readableSecondary
import com.shoo.app.components.shooEaseOut
import com.shoo.app.components.systemTextStyle
import com.shoo.app.components.textScale
import com.shoo.app.data.FamilyMember
import com.shoo.app.data.ShooRepository
import com.shoo.app.features.activity.privacyCover
import com.shoo.app.support.DeliveredPushes
import com.shoo.app.support.L10n
import com.shoo.app.support.t
import kotlinx.coroutines.launch
import kotlin.math.min

/**
 * GD-04: QR + big 6-digit code with its 30-min countdown, "Copy invite link", and the people connected (x/3).
 * Opened from Profile and "Invite your family" (Family Shield). The content of a sheet (the caller presents it);
 * `onDismiss` is iOS `dismiss()` ("Done").
 */
@Composable
fun FamilyCodeView(repository: ShooRepository, modifier: Modifier = Modifier, onDismiss: () -> Unit = {}) {
    val context = LocalContext.current
    val view = LocalView.current
    val language = LocalAppLanguage.current
    val scope = rememberCoroutineScope()
    val model = remember(repository) {
        SystemPasteboard.install(context)
        FamilyCodeModel(repository, clearDeliveredPushes = { DeliveredPushes.clear(context.applicationContext) })
    }
    var memberToRemove by remember { mutableStateOf<FamilyMember?>(null) }
    LaunchedEffect(model) { model.run() }

    val groupedBackground = dynamicColor(0xF2F2F7, 0x000000)
    val cell = dynamicColor(0xFFFFFF, 0x1C1C1E)
    val cellShape = RoundedCornerShape(10.dp)

    Column(
        modifier
            .fillMaxSize()
            .background(groupedBackground)
            .privacyCover(),
    ) {
        // Inline navigation bar: "Family code" with "Done".
        Box(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 56.dp)
                .padding(horizontal = 16.dp),
        ) {
            Text(
                t("Family code"),
                style = systemTextStyle(SystemTextStyle.HEADLINE),
                color = labelColor,
                modifier = Modifier
                    .align(Alignment.Center)
                    .semantics { heading() },
            )
            Box(
                Modifier
                    .align(Alignment.CenterEnd)
                    .heightIn(min = 44.dp)
                    .systemButton(onClick = onDismiss)
                    .semantics { testTag = "familyCode.done" },
                contentAlignment = Alignment.Center,
            ) {
                Text(t("Done"), style = systemTextStyle(SystemTextStyle.BODY, FontWeight.SemiBold), color = SystemColors.blue)
            }
        }

        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
        ) {
            Spacer(Modifier.height(16.dp))
            // Section { codeSection }
            Box(
                Modifier
                    .fillMaxWidth()
                    .background(cell, cellShape)
                    .padding(horizontal = 16.dp, vertical = 11.dp),
            ) {
                CodeSection(model, onCopy = {
                    if (model.copyInvite(language)) {
                        @Suppress("DEPRECATION")
                        view.announceForAccessibility(L10n.string("Invite link copied", language))
                    }
                }, onRetry = { scope.launch { model.refreshCode() } })
            }

            // Members section header.
            val count = model.members.size
            val header = t("Connected %lld/%lld", count, 3)
            val headerLabel = t("Connected, %lld of %lld people", count, 3)
            Text(
                header,
                style = systemTextStyle(SystemTextStyle.FOOTNOTE),
                color = readableSecondary,
                modifier = Modifier
                    .padding(start = 16.dp, top = 24.dp, bottom = 7.dp)
                    .semantics {
                        contentDescription = headerLabel
                        testTag = "familyCode.members"
                    },
            )
            Column(
                Modifier
                    .fillMaxWidth()
                    .background(cell, cellShape),
            ) {
                var first = true
                fun divider(): Boolean = !first.also { first = false }
                if (model.members.isEmpty() && !model.membersFailed) {
                    first = false
                    ListCell { Text(t("No one connected yet"), style = systemTextStyle(SystemTextStyle.BODY), color = readableSecondary) }
                }
                model.members.forEach { member ->
                    if (divider()) CellDivider(start = 68.dp)
                    ListCell {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            AvatarView(id = member.avatarId, size = 40.dp)
                            Text(
                                member.name,
                                style = systemTextStyle(SystemTextStyle.BODY),
                                color = labelColor,
                                modifier = Modifier.weight(1f),
                            )
                            if (model.removingId == member.deviceId) {
                                CircularProgressIndicator(Modifier.size(20.dp), color = SystemColors.gray, strokeWidth = 2.dp)
                            } else {
                                val removeLabel = t("Remove %@", member.name)
                                Box(
                                    Modifier
                                        .heightIn(min = 44.dp)
                                        .systemButton { memberToRemove = member }
                                        .clearAndSetSemantics {
                                            contentDescription = removeLabel
                                            testTag = "familyCode.remove.${member.deviceId}"
                                        },
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Text(t("Remove"), style = systemTextStyle(SystemTextStyle.BODY), color = readableRed)
                                }
                            }
                        }
                    }
                }
                if (model.membersFailed) {
                    if (divider()) CellDivider(start = 16.dp)
                    ListCell(
                        Modifier.systemButton { scope.launch { model.loadMembers() } },
                    ) {
                        Text(t("Couldn't load your family. Try again"), style = systemTextStyle(SystemTextStyle.BODY), color = SystemColors.blue)
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
            Spacer(Modifier.windowInsetsBottomHeight(WindowInsets.navigationBars))
        }
    }

    // iOS `confirmationDialog`: Android's alert with the destructive choice.
    val pending = memberToRemove
    if (pending != null) {
        AlertDialog(
            onDismissRequest = { memberToRemove = null },
            title = { Text(t("Remove from your family?")) },
            text = { Text(t("%@ won't be protected by you anymore. You won't see their activity.", pending.name)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        memberToRemove = null
                        scope.launch { model.remove(pending) }
                    },
                    modifier = Modifier.semantics { testTag = "familyCode.remove.confirm" },
                ) { Text(t("Remove"), color = readableRed) }
            },
            dismissButton = { TextButton(onClick = { memberToRemove = null }) { Text(t("Cancel")) } },
        )
    }
    val error = model.actionError
    if (error != null) {
        AlertDialog(
            onDismissRequest = { model.actionError = null },
            title = { Text(t("Couldn't remove")) },
            text = { Text(t(error)) },
            confirmButton = { TextButton(onClick = { model.actionError = null }) { Text(t("OK")) } },
        )
    }
}

@Composable
private fun CodeSection(model: FamilyCodeModel, onCopy: () -> Unit, onRetry: () -> Unit) {
    when (val state = model.codeState) {
        FamilyCodeModel.CodeState.Loading -> {
            val label = t("Getting a code")
            Box(Modifier.fillMaxWidth().heightIn(min = 280.dp).clearAndSetSemantics { contentDescription = label }) {
                ShieldPulseLoader(Modifier.fillMaxWidth().heightIn(min = 280.dp))
            }
        }
        is FamilyCodeModel.CodeState.Ready -> Column(
            Modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            val code = state.code
            Text(
                t("Ask your family member to scan this code, or enter the 6 digits in Shoo."),
                style = systemTextStyle(SystemTextStyle.SUBHEADLINE),
                color = readableSecondary,
                textAlign = TextAlign.Center,
            )
            val url = model.inviteURL
            val qr = remember(url) { url?.let { QRCode.image(it) } }
            if (qr != null) {
                val qrLabel = t("QR code to join your family")
                Image(
                    bitmap = qr,
                    contentDescription = qrLabel,
                    filterQuality = FilterQuality.None,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .background(Color.White, RoundedCornerShape(16.dp))
                        .padding(12.dp)
                        .widthIn(max = 220.dp)
                        .aspectRatio(1f)
                        .semantics { testTag = "familyCode.qr" },
                )
            }
            val codeLabel = t("Code %@", code.code.toList().joinToString(" "))
            Text(
                FamilyCodeModel.display(code.code),
                style = TextStyle(
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Bold,
                    fontSize = min(48f * textScale(), 72f).sp,
                ),
                color = labelColor,
                maxLines = 1,
                modifier = Modifier.clearAndSetSemantics {
                    contentDescription = codeLabel
                    testTag = "familyCode.code"
                },
            )
            Text(
                t("Valid for %@", model.timeLeft),
                style = systemTextStyle(SystemTextStyle.SUBHEADLINE).copy(fontFeatureSettings = "tnum"),
                color = readableSecondary,
                modifier = Modifier.semantics { testTag = "familyCode.countdown" },
            )
            if (model.inviteURL != null) {
                // `.borderedProminent`: the tinted filled button.
                Row(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 44.dp)
                        .background(SystemColors.blue, RoundedCornerShape(12.dp))
                        .systemButton(onClick = onCopy)
                        .semantics { testTag = "familyCode.copy" }
                        .padding(horizontal = 14.dp, vertical = 7.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    SfSymbol(if (model.copied) "checkmark" else "doc.on.doc", pointSize = 15f, tint = Color.White)
                    Text(
                        t(if (model.copied) "Copied" else "Copy invite link"),
                        style = systemTextStyle(SystemTextStyle.BODY, FontWeight.SemiBold),
                        color = Color.White,
                    )
                }
            }
        }
        FamilyCodeModel.CodeState.Unavailable -> Column(
            Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(t("Couldn't get a code"), style = systemTextStyle(SystemTextStyle.HEADLINE), color = labelColor)
            Box(
                Modifier
                    .heightIn(min = 44.dp)
                    .systemButton(onClick = onRetry)
                    .semantics { testTag = "familyCode.retry" },
                contentAlignment = Alignment.Center,
            ) {
                Text(t("Try again"), style = systemTextStyle(SystemTextStyle.BODY), color = SystemColors.blue)
            }
        }
        FamilyCodeModel.CodeState.Full -> Text(
            t("Your family is full (3 people). Remove someone to invite another person."),
            style = systemTextStyle(SystemTextStyle.BODY),
            color = readableSecondary,
            modifier = Modifier.semantics { testTag = "familyCode.full" },
        )
    }
}

/** One inset-grouped list row: 16 pt sides, 44 pt tall at least. */
@Composable
private fun ListCell(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = 44.dp)
            .padding(horizontal = 16.dp, vertical = 6.dp),
        contentAlignment = Alignment.CenterStart,
    ) { content() }
}

@Composable
private fun CellDivider(start: androidx.compose.ui.unit.Dp) {
    HorizontalDivider(
        modifier = Modifier.padding(start = start),
        thickness = 0.5.dp,
        color = dynamicColor(0xC6C6C8, 0x38383A),
    )
}

/**
 * A UIKit system button's highlight (`.borderless`, `.borderedProminent`, toolbar "Done"): dims at once while held, fades
 * back on release. iOS: UIKit's exact highlight alpha and fade are not public; 0.3 and a 0.2 s ease-out are close.
 */
private fun Modifier.systemButton(onClick: () -> Unit): Modifier = composed {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val alpha by animateFloatAsState(if (pressed) 0.3f else 1f, if (pressed) snap<Float>() else shooEaseOut<Float>(0.2), label = "systemHighlight")
    graphicsLayer { this.alpha = alpha }
        .clickable(interactionSource = interaction, indication = null, role = Role.Button, onClick = onClick)
}
