package com.shoo.app.features.profile

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import com.shoo.app.R
import com.shoo.app.components.AvatarCatalog
import com.shoo.app.components.AvatarView
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.dynamicColor
import com.shoo.app.components.hex
import com.shoo.app.components.pressScale
import com.shoo.app.components.readableRed
import com.shoo.app.components.shooEaseInOut
import com.shoo.app.components.shooEaseOut
import com.shoo.app.components.shooShadow
import com.shoo.app.components.shooSpring
import com.shoo.app.features.onboarding.NameRule
import com.shoo.app.support.t
import kotlinx.coroutines.launch

// Figma "Pengaturan/Kelola profil · Sheet ubah avatar" (1286:12383), "· Sheet ubah nama" (1286:12451) and
// "Profile/Pribadi · Konfirmasi hapus akun" (1115:14173). Values are the Figma ones.

/** "Ubah avatar" link and the focused name field's ring and cursor (#3866ED). */
internal val ProfileStyle.accent: Color @Composable get() = dynamicColor(0x3866ED, 0x7D9BFF, 0x1F47C4, 0xA9BDFF)

/** Name field fill (#F3F6F8). */
internal val ProfileStyle.fieldFill: Color @Composable get() = dynamicColor(0xF3F6F8, 0x2A303A, 0xE2E7EE, 0x3A414D)

/** Sheet grabber (#D9DFE6). */
internal val ProfileStyle.sheetGrabber: Color @Composable get() = dynamicColor(0xD9DFE6, 0x4A515C)

/** "Batal" in the delete alert (#ECECF0). */
internal val ProfileStyle.alertCancelFill: Color @Composable get() = dynamicColor(0xECECF0, 0x2A303A, 0xD6D6DD, 0x3A414D)

// MARK: Sheet parts

/** Grabber, title + subtitle and the round close button of a Kelola profil sheet. `title`, `subtitle`: localized. */
@Composable
fun ProfileSheetHeader(title: String, subtitle: String, onClose: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .size(width = 36.dp, height = 5.dp)
                .background(ProfileStyle.sheetGrabber, CapsuleShape)
                .clearAndSetSemantics { },
        )
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    title,
                    style = profileFont(28f, FontWeight.SemiBold, lineHeight = 34f),
                    color = ProfileStyle.ink,
                    modifier = Modifier.semantics { heading() },
                )
                Text(subtitle, style = profileBody(), color = ProfileStyle.secondary)
            }
            val closeLabel = t("Close")
            // The 44 pt tap area around Figma's 30 pt button (`.padding(-7)`).
            Box(
                Modifier
                    .outset(7.dp)
                    .size(44.dp)
                    .plainClickable(onClick = onClose)
                    .semantics {
                        contentDescription = closeLabel
                        testTag = "profile.sheet.close"
                    },
                contentAlignment = Alignment.Center,
            ) {
                Image(painterResource(R.drawable.profile_sheet_close), contentDescription = null, modifier = Modifier.size(30.dp))
            }
        }
    }
}

/**
 * Figma "Button" in the Kelola profil sheets: dark blue capsule, a white compass and "Simpan" (54 pt). Swift
 * `ProfileSaveButtonStyle`. The `content` row gets the label style and colour.
 */
@Composable
fun ProfileSaveButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    testTag: String? = null,
    content: @Composable RowScope.() -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val reduceMotion = LocalReduceMotion.current
    val alpha by animateFloatAsState(if (pressed) 0.85f else 1f, shooEaseOut(0.15), label = "saveAlpha")
    // Reduce Motion: the dim alone.
    val scale by animateFloatAsState(if (pressed && !reduceMotion) 0.97f else 1f, shooEaseOut(0.15), label = "saveScale")
    val density = LocalDensity.current
    // Figma: black 20 %, y 4, blur 4 under the label.
    val labelShadow = with(density) {
        Shadow(Color.Black.copy(alpha = if (enabled) 0.2f else 0f), Offset(0f, 4.dp.toPx()), ((2.dp.toPx() - 0.5f) / 0.57735f).coerceAtLeast(0f))
    }
    val ink = if (enabled) Color.White else ProfileStyle.secondary
    val tag = testTag
    Row(
        modifier
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
                this.alpha = alpha
            }
            .fillMaxWidth()
            .heightIn(min = 54.dp)
            .then(
                if (enabled) {
                    Modifier
                        .background(ModeOfferCardDefaults.button, CapsuleShape)
                        .border(1.5.dp, hex(0x191D2F), CapsuleShape)
                } else {
                    Modifier.background(ProfileStyle.disabledFill, CapsuleShape)
                },
            )
            .clip(CapsuleShape)
            .clickable(interaction, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .then(if (tag != null) Modifier.semantics { this.testTag = tag } else Modifier)
            .padding(vertical = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // The export keeps the glyph's shadow, so it is 26 × 28 around a 22 pt frame.
        Box(
            Modifier
                .size(22.dp)
                .alpha(if (enabled) 1f else 0f)
                .clearAndSetSemantics { },
            contentAlignment = Alignment.Center,
        ) {
            Image(
                painterResource(R.drawable.profile_save_icon),
                contentDescription = null,
                modifier = Modifier
                    .outset(2.dp, 3.dp)
                    .offset(y = 3.dp)
                    .size(width = 26.dp, height = 28.dp),
            )
        }
        CompositionLocalProvider(
            LocalTextStyle provides profileFont(17f, FontWeight.SemiBold, lineHeight = 22f).copy(shadow = labelShadow),
            LocalContentColor provides ink,
        ) {
            content()
        }
    }
}

/** "Save" ↔ spinner: a 0.2 s cross-fade like "Remind", gentle enough for Reduce Motion. Only the label. */
@Composable
private fun SaveLabel(isWorking: Boolean) {
    Crossfade(targetState = isWorking, animationSpec = shooEaseInOut(0.2), label = "saveLabel") { working ->
        if (working) {
            CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
        } else {
            Text(t("Save"))
        }
    }
}

/** The sheet chrome: 8 pt above the grabber, 24 at the sides, 40 under the button (Figma's 40 includes the home
 * indicator's 34; the sheet adds the navigation bar). Sized to its content in a `ProfileSheet` (r 32, card colour). */
private fun Modifier.profileSheetChrome(): Modifier = this
    .padding(horizontal = 24.dp)
    .padding(top = 8.dp, bottom = 6.dp)

/**
 * iOS `.sheet(isPresented:)` with `.presentationCornerRadius` and `.presentationBackground`: a `ModalBottomSheet` that
 * slides in when `isPresented` turns true and slides out when it turns false. A swipe, a tap on the dim or Back calls
 * `onDismissRequest` (iOS: the binding turns false); `onDismissed` runs once it is gone either way (iOS `onDismiss:`).
 * `canDismiss` false: no swipe or tap closes it (iOS `.interactiveDismissDisabled`).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ProfileSheet(
    isPresented: Boolean,
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    canDismiss: Boolean = true,
    onDismissed: () -> Unit = {},
    containerColor: Color = ProfileStyle.card,
    cornerRadius: Dp = 32.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    val canDismissNow by rememberUpdatedState(canDismiss)
    val presentedNow by rememberUpdatedState(isPresented)
    val dismissed by rememberUpdatedState(onDismissed)
    val state = rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        // A closing asked for by the screen itself always goes through.
        confirmValueChange = { it != SheetValue.Hidden || canDismissNow || !presentedNow },
    )
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(isPresented) {
        if (isPresented) {
            shown = true
        } else if (shown) {
            try {
                state.hide()
            } finally {
                shown = false
                dismissed()
            }
        }
    }
    if (shown) {
        ModalBottomSheet(
            onDismissRequest = {
                if (canDismissNow) {
                    onDismissRequest()
                }
            },
            modifier = modifier,
            sheetState = state,
            shape = RoundedCornerShape(topStart = cornerRadius, topEnd = cornerRadius),
            containerColor = containerColor,
            dragHandle = null,
            content = content,
        )
    }
}

// MARK: Ubah avatar

/**
 * The four ON-02 memoji in 66 pt tiles; the chosen one has a gradient ring and a check. "Simpan" saves.
 * `onDismiss`: iOS `@Environment(\.dismiss)`.
 */
@Composable
fun AvatarPickerSheet(
    current: String,
    isWorking: Boolean,
    onSave: (String) -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var selected by remember { mutableStateOf(current) }
    // Figma tiles: Ungu, Pink, Oranye, Biru (avatar_01, 03, 02, 04).
    val order = remember { listOf("avatar_01", "avatar_03", "avatar_02", "avatar_04").filter(AvatarCatalog.memojiIds::contains) }
    Column(
        modifier
            .fillMaxWidth()
            .profileSheetChrome(),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        ProfileSheetHeader(title = t("Change avatar"), subtitle = t("Pick a character."), onClose = onDismiss)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            order.forEachIndexed { index, id ->
                val label = t("Avatar %lld", index + 1)
                val isSelected = id == selected
                Box(
                    Modifier
                        .size(66.dp)
                        .clip(androidx.compose.foundation.shape.CircleShape)
                        .clickable(role = Role.Button) { selected = id }
                        .semantics {
                            contentDescription = label
                            this.selected = isSelected
                            testTag = "avatar.$id"
                        },
                ) { AvatarTile(id, isSelected) }
            }
        }
        ProfileSaveButton(
            onClick = { if (selected == current) onDismiss() else onSave(selected) },
            enabled = !isWorking,
            testTag = "profile.avatar.save",
        ) { SaveLabel(isWorking) }
    }
}

/** Figma "Tile": a 58 pt avatar in a 66 pt tile; ring and check on the chosen one. */
@Composable
private fun BoxScope.AvatarTile(id: String, isSelected: Boolean) {
    AvatarView(id = id, size = 58.dp, modifier = Modifier.align(Alignment.Center))
    if (isSelected) {
        Image(painterResource(R.drawable.profile_avatar_ring), contentDescription = null, modifier = Modifier.size(66.dp))
        Image(
            painterResource(R.drawable.profile_avatar_check),
            contentDescription = null,
            modifier = Modifier
                .offset(x = 44.dp, y = 44.dp)
                .size(22.dp),
        )
    }
}

// MARK: Ubah nama

/**
 * Name field with a clear button and a character counter; the onboarding rule (1–20 characters).
 * `subtitle`: localized. `onDismiss`: iOS `@Environment(\.dismiss)`.
 */
@Composable
fun NameSheet(model: ProfileModel, subtitle: String, onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    val language = LocalAppLanguage.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val focus = remember { FocusRequester() }
    var isFocused by remember { mutableStateOf(false) }
    val problem = model.nameProblem
    val saveDisabled = model.nameDraft == model.profile?.name || problem != null || model.isWorking
    val savedText = t("Name saved")

    fun save() {
        if (saveDisabled) return
        scope.launch {
            if (model.saveName()) {
                view.announce(savedText)
                onDismiss()
            }
        }
    }

    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    OnChange(model.nameError) { _, message -> if (message != null) view.announce(message.string(language)) }

    Column(
        modifier
            .fillMaxWidth()
            .profileSheetChrome(),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        ProfileSheetHeader(title = t("Change name"), subtitle = subtitle, onClose = onDismiss)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            // Figma "Text field (fokus)": #F3F6F8, r 16, 56 pt, a 1.5 pt #3866ED ring while focused.
            val shape = RoundedCornerShape(16.dp)
            val accent = ProfileStyle.accent
            val nameLabel = t("Name")
            val hint = t("1 to 20 characters")
            val clearLabel = t("Clear name")
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 56.dp)
                    .background(ProfileStyle.fieldFill, shape)
                    .border(1.5.dp, if (isFocused) accent else Color.Transparent, shape)
                    .clip(shape)
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                        runCatching { focus.requestFocus() }
                    }
                    .padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // The label is the sheet's own title word, so Voice Access "Tap Name" works (WCAG 2.5.3).
                BasicTextField(
                    value = model.nameDraft,
                    onValueChange = { model.nameDraft = it },
                    singleLine = true,
                    textStyle = profileBody().copy(color = ProfileStyle.ink),
                    cursorBrush = SolidColor(accent),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { save() }),
                    modifier = Modifier
                        .weight(1f)
                        .focusRequester(focus)
                        .onFocusChanged { isFocused = it.isFocused }
                        .semantics {
                            contentDescription = "$nameLabel. $hint"
                            testTag = "profile.name"
                        },
                )
                if (model.nameDraft.isNotEmpty()) {
                    Box(
                        Modifier
                            .outset(start = 0.dp, top = 13.dp, end = 13.dp, bottom = 13.dp)
                            .size(44.dp)
                            .plainClickable { model.nameDraft = "" }
                            .semantics { contentDescription = clearLabel },
                        contentAlignment = Alignment.Center,
                    ) {
                        Image(painterResource(R.drawable.profile_field_clear), contentDescription = null, modifier = Modifier.size(18.dp))
                    }
                }
            }
            val message: String? = when (problem) {
                NameRule.Problem.Empty -> t("Enter a name.")
                NameRule.Problem.TooLong -> t("Use 20 characters or fewer.")
                null -> model.nameError?.text()
            }
            val length = NameRule.length(model.nameDraft)
            val counterLabel = t("%lld of %lld characters", length, NameRule.maxLength)
            Row(Modifier.fillMaxWidth().padding(end = 4.dp), verticalAlignment = Alignment.Top) {
                if (message != null) {
                    Text(
                        message,
                        style = profileCaption(),
                        color = readableRed,
                        modifier = Modifier
                            .weight(1f, fill = false)
                            .semantics { testTag = "profile.error" },
                    )
                    Spacer(Modifier.width(8.dp))
                }
                Spacer(Modifier.weight(1f))
                Text(
                    "$length/${NameRule.maxLength}",
                    style = profileCaption(),
                    color = if (problem == NameRule.Problem.TooLong) readableRed else ProfileStyle.secondary,
                    modifier = Modifier.clearAndSetSemantics { contentDescription = counterLabel },
                )
            }
        }
        ProfileSaveButton(onClick = { save() }, enabled = !saveDisabled, testTag = "profile.saveName") {
            SaveLabel(model.isWorking)
        }
    }
}

// MARK: Hapus akun

/**
 * "Hapus akun?" alert over `content` (Profile and Kelola profil). Swift `.deleteAccountSheet(model:isPresented:)`.
 * Figma "Alert/Hapus akun" (1115:14268): a 320 pt card over a #0A0F1F 38 % dim, "Batal" and a red "Hapus".
 */
@Composable
fun DeleteAccountSheet(
    model: ProfileModel,
    isPresented: Boolean,
    onIsPresentedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val language = LocalAppLanguage.current
    val scope = rememberCoroutineScope()
    BackHandler(enabled = isPresented) { if (!model.isWorking) onIsPresentedChange(false) }
    Box(modifier.fillMaxSize()) {
        // The screen under the dim is out of reach, so TalkBack skips it too.
        Box(Modifier.fillMaxSize().then(if (isPresented) Modifier.clearAndSetSemantics { } else Modifier)) { content() }
        AnimatedVisibility(
            visible = isPresented,
            enter = fadeIn(shooEaseOut(0.2)),
            exit = fadeOut(shooEaseOut(0.2)),
        ) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(hex(0x0A0F1F, 0.38f))
                        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { }
                        .clearAndSetSemantics { },
                )
                val shape = RoundedCornerShape(32.dp)
                val card = ProfileStyle.card
                Column(
                    Modifier
                        .padding(horizontal = 24.dp)
                        .widthIn(max = 320.dp)
                        // Figma: black 18 %, y 12, blur 40.
                        .shooShadow(Color.Black.copy(alpha = 0.18f), radius = 20.dp, y = 12.dp, shape = shape)
                        .background(card.copy(alpha = card.alpha * 0.96f), shape)
                        .padding(start = 18.dp, end = 18.dp, top = 26.dp, bottom = 18.dp)
                        .semantics { testTag = "profile.deleteAlert" },
                    verticalArrangement = Arrangement.spacedBy(18.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            t("Delete account?"),
                            style = profileFont(17f, FontWeight.SemiBold, lineHeight = 22f),
                            color = ProfileStyle.ink,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.semantics { heading() },
                        )
                        Text(
                            model.deleteMessage(language),
                            style = profileValue(),
                            color = ProfileStyle.secondary,
                            textAlign = TextAlign.Center,
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        AlertButton(
                            fill = ProfileStyle.alertCancelFill,
                            enabled = !model.isWorking,
                            testTag = "profile.confirm.cancel",
                            onClick = { onIsPresentedChange(false) },
                            modifier = Modifier.weight(1f),
                        ) { Text(t("Cancel"), color = ProfileStyle.ink) }
                        AlertButton(
                            fill = ProfileStyle.red,
                            enabled = !model.isWorking,
                            testTag = "profile.delete.confirm",
                            onClick = { scope.launch { if (model.deleteMyData()) onIsPresentedChange(false) } },
                            modifier = Modifier.weight(1f),
                        ) {
                            Crossfade(targetState = model.isWorking, animationSpec = shooEaseInOut(0.2), label = "deleteLabel") { working ->
                                if (working) {
                                    CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
                                } else {
                                    Text(t("Delete"), color = Color.White)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/** Figma "Tombol/Batal", "Tombol/Hapus": 50 pt, r 24, SF Pro Display Semibold 17. */
@Composable
private fun AlertButton(
    fill: Color,
    enabled: Boolean,
    testTag: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    label: @Composable () -> Unit,
) {
    val shape = RoundedCornerShape(24.dp)
    Box(
        modifier
            .heightIn(min = 50.dp)
            .background(fill, shape)
            .clip(shape)
            .plainClickable(enabled = enabled, onClick = onClick)
            .semantics { this.testTag = testTag }
            .padding(vertical = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        CompositionLocalProvider(LocalTextStyle provides profileFont(17f, FontWeight.SemiBold, lineHeight = 22f)) {
            label()
        }
    }
}

/** Failures of a page's action (save, switch, delete), as an alert with OK. iOS `.alert(Text(…)) { Button("OK") }`. */
@Composable
internal fun ProfileActionErrorAlert(error: LocalizationValue?, onDismiss: () -> Unit) {
    if (error == null) return
    val message = error.text()
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = { TextButton(onClick = onDismiss) { Text(t("OK")) } },
        title = { Text(message, style = profileFont(17f, FontWeight.SemiBold, lineHeight = 22f), textAlign = TextAlign.Center) },
        containerColor = ProfileStyle.card,
        titleContentColor = ProfileStyle.ink,
    )
}

// MARK: Android helpers shared by the Profile files

/** SwiftUI `.padding(-x)`: draws the content at its size but takes `x` less room on each side. */
internal fun Modifier.outset(all: Dp): Modifier = outset(all, all, all, all)

internal fun Modifier.outset(horizontal: Dp, vertical: Dp): Modifier = outset(horizontal, vertical, horizontal, vertical)

internal fun Modifier.outset(start: Dp, top: Dp, end: Dp, bottom: Dp): Modifier = layout { measurable, constraints ->
    val s = start.roundToPx()
    val t = top.roundToPx()
    val e = end.roundToPx()
    val b = bottom.roundToPx()
    val placeable = measurable.measure(
        constraints.copy(
            maxWidth = if (constraints.hasBoundedWidth) constraints.maxWidth + s + e else constraints.maxWidth,
            maxHeight = if (constraints.hasBoundedHeight) constraints.maxHeight + t + b else constraints.maxHeight,
        ),
    )
    val width = (placeable.width - s - e).coerceAtLeast(0)
    val height = (placeable.height - t - b).coerceAtLeast(0)
    layout(width, height) { placeable.place(-s, -t) }
}

/** `.buttonStyle(.plain)`: no ripple, the label dims while pressed. */
internal fun Modifier.plainClickable(
    enabled: Boolean = true,
    onClickLabel: String? = null,
    role: Role? = Role.Button,
    onClick: () -> Unit,
): Modifier = composed {
    val interaction = remember { MutableInteractionSource() }
    this
        .pressScale(interaction, scale = 1f, pressedAlpha = 0.6f)
        .clickable(interaction, indication = null, enabled = enabled, onClickLabel = onClickLabel, role = role, onClick = onClick)
}

/** `.sensoryFeedback(.success / .error / .selection)`. */
internal enum class ProfileHaptic { SUCCESS, ERROR, SELECTION }

internal fun View.profileHaptic(kind: ProfileHaptic) {
    val constant = when (kind) {
        ProfileHaptic.SUCCESS -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY
        ProfileHaptic.ERROR -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS
        ProfileHaptic.SELECTION -> HapticFeedbackConstants.CLOCK_TICK
    }
    performHapticFeedback(constant)
}

@Composable
internal fun rememberSensoryFeedback(): (ProfileHaptic) -> Unit {
    val view = LocalView.current
    return remember(view) { { kind: ProfileHaptic -> view.profileHaptic(kind) } }
}

/** `AccessibilityNotification.Announcement(…).post()`: TalkBack reads `text`. */
@Suppress("DEPRECATION")
internal fun View.announce(text: String) {
    announceForAccessibility(text)
}

/** SwiftUI `.onChange(of: value) { old, new in … }`: not on the first composition, only when `value` changes. */
@Composable
internal fun <T> OnChange(value: T, action: suspend (old: T, new: T) -> Unit) {
    val previous = remember { arrayOfNulls<Any?>(1).also { it[0] = value } }
    LaunchedEffect(value) {
        @Suppress("UNCHECKED_CAST")
        val old = previous[0] as T
        if (old == value) return@LaunchedEffect
        previous[0] = value
        action(old, value)
    }
}

/** `scenePhase == .active`: the app is in the foreground (Activity resumed). */
@Composable
internal fun rememberSceneActive(): Boolean {
    val owner = LocalLifecycleOwner.current
    val state by owner.lifecycle.currentStateAsState()
    return state.isAtLeast(Lifecycle.State.RESUMED)
}

/** `.symbolEffect(.bounce, options: .nonRepeating, value: trigger)`: scale up and back once per change. */
internal fun Modifier.profileBounce(trigger: Int, enabled: Boolean): Modifier = composed {
    val scale = remember { Animatable(1f) }
    LaunchedEffect(trigger, enabled) {
        if (!enabled || trigger == 0) return@LaunchedEffect
        scale.animateTo(1.18f, shooEaseOut(0.12))
        scale.animateTo(1f, shooSpring(0.3, 0.4))
    }
    graphicsLayer {
        scaleX = scale.value
        scaleY = scale.value
    }
}
