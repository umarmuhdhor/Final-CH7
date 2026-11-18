package com.shoo.app.features.detail

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import android.os.SystemClock
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.figmaButtonShadow
import com.shoo.app.components.figmaCardShadow
import com.shoo.app.components.figmaTextStyle
import com.shoo.app.components.shooEaseInOut
import com.shoo.app.components.shooEaseOut
import com.shoo.app.components.shooSnappy
import com.shoo.app.components.textScale
import com.shoo.app.data.Verdict
import com.shoo.app.features.activity.activityFont
import com.shoo.app.support.Formatters
import com.shoo.app.support.t
import java.time.Instant
import java.time.ZoneId
import java.util.Date

/** iOS `sensoryFeedback`: the system haptics (not the "Getar" setting, which is for warnings). */
internal object DetailHaptics {
    fun success(view: View) {
        view.performHapticFeedback(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY,
        )
    }

    fun error(view: View) {
        view.performHapticFeedback(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS,
        )
    }
}

/**
 * Figma "Footer" of Detail (416:9255 / 416:9362 / 480:5768): the guardian's question with Aman / Bahaya (GD-07,
 * warning and blocked alike), or the card saying who verified it. "Ubah" on either verdict brings the buttons back; a
 * new choice replaces the old one. No confirmation dialog.
 */
object DetailFooter {
    /** Catalog key of why the last verdict was not saved. */
    fun message(failure: DetailModel.VerdictError): String = when (failure) {
        DetailModel.VerdictError.CONNECTION -> "Couldn't save. Check your connection and try again."
        DetailModel.VerdictError.NOT_ALLOWED -> "You're no longer this person's guardian, so you can't mark this site."
        DetailModel.VerdictError.TOO_MANY -> "Too many changes in a minute. Wait a moment, then try again."
        DetailModel.VerdictError.LOCKED -> "This site stays safe until Shoo's weekly review. You can change it after that."
    }

    /** Space above the question (or the verified card). Figma: 28 pt. */
    const val topPadding = 28f
    /** Height of the transparent-to-solid fade at the footer's top edge. Shorter than `topPadding`, so the fade ends
     * 4 pt above the content (U-17). */
    const val fadeHeight = 24f
}

/**
 * `failure`: why the last verdict was not saved (BH-27); null when it was, or none was sent.
 * `ownerName`: the person who opened the site, when it isn't the viewer (the note under a safe verdict).
 * `isBlocked`: blocked sites ask "Apakah situs ini berbahaya?", warnings "Apakah situs ini benar penipuan?".
 * `changing` / `onChangingChange`: "Ubah" pressed: the buttons are back. Owned by Detail, so it survives the footer
 * moving between the bottom and the page (U-07); without them the footer keeps its own.
 *
 * Its bottom padding is iOS's: 34 pt from the screen's bottom edge, the navigation bar counted (`max(0, 34 − inset)`).
 * Pinned at the bottom, the caller puts it above the navigation bar and fills the bar's area in `DetailStyle.footer`.
 */
@Composable
fun DetailFooter(
    verdict: Verdict?,
    viewerDeviceId: String?,
    canValidate: Boolean,
    failure: DetailModel.VerdictError?,
    ownerName: String?,
    isBlocked: Boolean = false,
    changing: Boolean? = null,
    onChangingChange: ((Boolean) -> Unit)? = null,
    onDecide: (Verdict.Value) -> Unit,
    modifier: Modifier = Modifier,
) {
    val language = LocalAppLanguage.current
    val reduceMotion = LocalReduceMotion.current
    val view = LocalView.current
    val density = LocalDensity.current
    var ownChanging by remember { mutableStateOf(false) }
    val isChanging = if (changing != null && onChangingChange != null) changing else ownChanging
    val setChanging: (Boolean) -> Unit = { value ->
        if (changing != null && onChangingChange != null) onChangingChange(value) else ownChanging = value
    }
    // #493: a verdict this build can't read counts as none: no "Verified safe" card, and a guardian gets the buttons
    // to decide again (an upsert).
    val shownVerdict = verdict?.known
    val showsButtons = canValidate && (shownVerdict == null || isChanging)
    val lockedUntil = shownVerdict?.let { VerdictLock.lockedUntil(it, Instant.now()) }

    // A saved choice from the server closes "Ubah" (iOS `onChange`: not on the first look, so moving the footer keeps it).
    val lastVerdict = remember { arrayOf(verdict) }
    LaunchedEffect(verdict) {
        if (verdict != lastVerdict[0]) {
            lastVerdict[0] = verdict
            setChanging(false)
        }
    }
    // "Couldn't save" is felt too, not only read.
    LaunchedEffect(failure != null) { if (failure != null) DetailHaptics.error(view) }

    // The navigation bar's inset, read from the window, never from this footer's own place (iOS QA 2026-11-10 #1).
    val navigationInset = with(density) { WindowInsets.navigationBars.getBottom(density).toDp() }
    // Safe / Danger saved: the buttons hand over to the verified card and its note with a short ease. Keyed on the
    // verdict only, like iOS `.animation(_, value: verdict?.value)`: "Ubah" swaps at once. The window covers the
    // frame after, where the LaunchedEffect above closes "Ubah" (iOS: the same transaction).
    val verdictValue = verdict?.value
    val lastValue = remember { arrayOf(verdictValue) }
    val animateUntil = remember { longArrayOf(0L) }
    if (lastValue[0] != verdictValue) {
        lastValue[0] = verdictValue
        animateUntil[0] = SystemClock.uptimeMillis() + 400
    }
    val animates = SystemClock.uptimeMillis() < animateUntil[0]
    // What the outgoing face still draws while it fades.
    val lastShown = remember { arrayOf(shownVerdict) }
    if (shownVerdict != null) lastShown[0] = shownVerdict
    val lastFailure = remember { arrayOf(failure) }
    if (failure != null) lastFailure[0] = failure
    val face: Any? = if (showsButtons) "buttons" else shownVerdict?.value

    Column(
        modifier
            .fillMaxWidth()
            // U-17: the fade lives only in the empty space above the question (`fadeHeight` < `topPadding`), so the
            // question and buttons always sit on a solid band.
            .drawBehind {
                val fade = DetailFooter.fadeHeight.dp.toPx()
                drawRect(
                    Brush.verticalGradient(listOf(DetailStyle.footer.copy(alpha = 0f), DetailStyle.footer), startY = 0f, endY = fade),
                    size = Size(size.width, fade),
                )
                drawRect(DetailStyle.footer, topLeft = Offset(0f, fade), size = Size(size.width, size.height - fade))
            }
            .padding(horizontal = 24.dp)
            .padding(top = DetailFooter.topPadding.dp, bottom = max(0.dp, 34.dp - navigationInset)),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        AnimatedContent(
            targetState = face,
            transitionSpec = {
                if (animates) {
                    fadeIn(verdictSpec(reduceMotion)) togetherWith fadeOut(verdictSpec(reduceMotion)) using
                        SizeTransform(clip = false) { _, _ -> verdictSpec(reduceMotion) }
                } else {
                    EnterTransition.None togetherWith ExitTransition.None using SizeTransform(clip = false) { _, _ -> snap() }
                }
            },
            label = "verdictFace",
        ) { target ->
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (target == "buttons") {
                    Text(
                        t(if (isBlocked) "Is this site dangerous?" else "Is this site really a scam?"),
                        // Figma "Pertanyaan": SF Pro Rounded 17, 140 %.
                        style = figmaTextStyle(17f, rounded = true, lineHeight = 23.8f),
                        color = DetailStyle.secondary,
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .fillMaxWidth()
                            .tagged("detail.verdictQuestion"),
                    )
                    VerdictButtons(verdict, onDecide)
                } else if (target != null) {
                    val card = shownVerdict ?: lastShown[0]
                    if (card != null) {
                        VerifiedCard(
                            verdict = card,
                            viewerDeviceId = viewerDeviceId,
                            // Either verdict can be changed (R4: Safe ⇄ NotSafe, an upsert), so a mis-tapped Danger can be
                            // undone. An "Aman" waits for the weekly AI review (VerdictLock); "Bahaya" can always change.
                            canChange = canValidate && lockedUntil == null,
                            onChange = { setChanging(true) },
                        )
                        // #369: "Aman" vouches for this link on both phones: no block, card or sheet while it stands.
                        if (card.value == Verdict.Value.SAFE && ownerName != null) {
                            Text(
                                t("Shoo no longer blocks or warns %@ on this link.", ownerName),
                                // Figma: centred, 140 % line height.
                                style = figmaTextStyle(13f, rounded = true, lineHeight = 18.2f),
                                color = DetailStyle.secondary,
                                textAlign = TextAlign.Center,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    // iOS `.opacity.combined(with: .offset(y: 4))`: the face's fade plus a 4 pt rise.
                                    .animateEnterExit(
                                        enter = if (reduceMotion || !animates) EnterTransition.None
                                        else slideInVertically(verdictSpec(false)) { with(density) { 4.dp.roundToPx() } },
                                        exit = if (reduceMotion || !animates) ExitTransition.None
                                        else slideOutVertically(verdictSpec(false)) { with(density) { 4.dp.roundToPx() } },
                                    ),
                            )
                        }
                        if (canValidate && lockedUntil != null) {
                            val day = Formatters.dateFormatter("EEEEdMMMM", language, ZoneId.systemDefault()).format(Date.from(lockedUntil))
                            FooterLabel(
                                text = t("You can change this after Shoo's weekly review, %@.", day),
                                symbol = "lock.fill",
                                style = figmaTextStyle(13f, rounded = true),
                                color = DetailStyle.secondary,
                                modifier = Modifier.tagged("detail.verdictLocked"),
                            )
                        }
                    }
                }
            }
        }
        AnimatedVisibility(
            visible = failure != null,
            enter = if (animates) fadeIn(verdictSpec(reduceMotion)) + expandVertically(verdictSpec(reduceMotion)) else EnterTransition.None,
            exit = if (animates) fadeOut(verdictSpec(reduceMotion)) + shrinkVertically(verdictSpec(reduceMotion)) else ExitTransition.None,
        ) {
            val shown = failure ?: lastFailure[0]
            if (shown != null) {
                FooterLabel(
                    text = t(DetailFooter.message(shown)),
                    symbol = "exclamationmark.triangle.fill",
                    style = activityFont(13f),
                    color = DetailStyle.title,
                    modifier = Modifier.tagged("detail.verdictError"),
                )
            }
        }
    }
}

/** The verdict hand-over: iOS `reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.25)`. */
private fun <T> verdictSpec(reduceMotion: Boolean): FiniteAnimationSpec<T> =
    if (reduceMotion) shooEaseInOut(0.2) else shooSnappy(0.25)

/** SwiftUI `Label` centred under the card: the symbol, then the text. */
@Composable
private fun FooterLabel(
    text: String,
    symbol: String,
    style: androidx.compose.ui.text.TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SfSymbol(symbol, pointSize = 13f, tint = color)
        Text(text, style = style, color = color, textAlign = TextAlign.Center)
    }
}

/** Side by side; stacked at accessibility sizes so the words never wrap per letter. */
@Composable
private fun VerdictButtons(verdict: Verdict?, onDecide: (Verdict.Value) -> Unit) {
    val hint = t("Applies right away. You can change it later.")
    val stacked = textScale() >= 1.6f
    val safe: @Composable (Modifier) -> Unit = { m ->
        VerdictButton(
            kind = Verdict.Value.SAFE,
            selected = verdict?.value == Verdict.Value.SAFE,
            title = t("Safe"),
            symbol = "checkmark.circle.fill",
            hint = hint,
            identifier = "detail.verdict.safe",
            onTap = { onDecide(Verdict.Value.SAFE) },
            modifier = m,
        )
    }
    val danger: @Composable (Modifier) -> Unit = { m ->
        VerdictButton(
            kind = Verdict.Value.NOT_SAFE,
            selected = verdict?.value == Verdict.Value.NOT_SAFE,
            title = t("Danger"),
            symbol = "exclamationmark.circle.fill",
            hint = hint,
            identifier = "detail.verdict.notSafe",
            onTap = { onDecide(Verdict.Value.NOT_SAFE) },
            modifier = m,
        )
    }
    if (stacked) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            safe(Modifier.fillMaxWidth())
            danger(Modifier.fillMaxWidth())
        }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            safe(Modifier.weight(1f))
            danger(Modifier.weight(1f))
        }
    }
}

/** Aman: white capsule, dark text. Bahaya: red gradient with a darker rim, white text. 56 pt high. */
@Composable
private fun VerdictButton(
    kind: Verdict.Value,
    selected: Boolean,
    title: String,
    symbol: String,
    hint: String,
    identifier: String,
    onTap: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val reduceMotion = LocalReduceMotion.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed && !reduceMotion) 0.97f else 1f, shooEaseOut(0.15), label = "verdictPress")
    val isSafe = kind == Verdict.Value.SAFE
    val ink = if (isSafe) DetailStyle.title else Color.White
    val background = if (isSafe) {
        Modifier
            .drawBehind {
                // Figma: #E3E3E3 spread 1 (a 1 pt ring outside the capsule) over the spread −3 drop shadow.
                val ring = (if (selected) 2 else 1).dp.toPx()
                drawRoundRect(
                    if (selected) DetailStyle.title else DetailStyle.safeStroke,
                    topLeft = Offset(-ring, -ring),
                    size = Size(size.width + 2 * ring, size.height + 2 * ring),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius((size.height + 2 * ring) / 2),
                )
            }
            .figmaButtonShadow()
            .background(Color.White, CapsuleShape)
    } else {
        Modifier
            .background(Brush.verticalGradient(listOf(DetailStyle.dangerBottom, DetailStyle.dangerTop)), CapsuleShape)
            .border(if (selected) 3.dp else 1.5.dp, DetailStyle.dangerTop, CapsuleShape)
    }
    Row(
        modifier
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
            }
            .then(background)
            .clickable(interactionSource = interaction, indication = null, role = Role.Button, onClick = onTap)
            .semantics {
                this.selected = selected
                testTag = identifier
                // iOS `.accessibilityHint`: TalkBack reads it as the action ("Double-tap to …").
                onClick(label = hint) { onTap(); true }
            }
            .heightIn(min = 56.dp)
            .padding(horizontal = 12.dp),
        // Figma: 8 pt between icon and word.
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SfSymbol(symbol, pointSize = 17f, tint = ink)
        Text(
            title,
            style = activityFont(17f, FontWeight.SemiBold, tracking = -0.2125f),
            color = ink,
            maxLines = 2,
            textAlign = TextAlign.Center,
        )
    }
}

/** Figma "Catatan": "Diverifikasi sebagai penipuan" / "Diverifikasi aman", "oleh Adhella · Baru saja". */
@Composable
private fun VerifiedCard(verdict: Verdict, viewerDeviceId: String?, canChange: Boolean, onChange: () -> Unit) {
    val language = LocalAppLanguage.current
    val isScam = verdict.value == Verdict.Value.NOT_SAFE
    val shape = RoundedCornerShape(20.dp)
    val title = t(if (isScam) "Verified as a scam" else "Verified safe")
    val byline = VerdictNote.byline(verdict, viewerDeviceId, language = language)
    Row(
        Modifier
            .fillMaxWidth()
            .figmaCardShadow(shape)
            .background(Color.White, shape)
            .border(1.dp, Color.White.copy(alpha = 0.9f), shape)
            .padding(start = 14.dp, end = 16.dp, top = 14.dp, bottom = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Figma "Verified Note": the same check for both, red on pink or green on mint.
        Box(
            Modifier
                .size(40.dp)
                .background(if (isScam) DetailStyle.scamIconFill else DetailStyle.safeIconFill, CircleShape)
                .clearAndSetSemantics { },
            contentAlignment = Alignment.Center,
        ) {
            SfSymbol("checkmark.circle.fill", pointSize = 20f, tint = if (isScam) DetailStyle.scamIcon else DetailStyle.safeIcon)
        }
        Column(
            Modifier
                .weight(1f)
                .clearAndSetSemantics {
                    contentDescription = "$title, $byline"
                    testTag = "detail.verdictNote"
                },
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(title, style = activityFont(16f, FontWeight.Medium, tracking = -0.16f), color = DetailStyle.title)
            Text(byline, style = activityFont(13f, rounded = true), color = DetailStyle.secondary)
        }
        if (canChange) {
            val label = t("Change")
            val changeHint = t("Shows the Safe and Danger buttons again")
            Box(
                Modifier
                    .sizeIn(minWidth = 44.dp, minHeight = 44.dp)
                    .clickable(role = Role.Button, onClick = onChange)
                    .semantics {
                        testTag = "detail.verdictChange"
                        onClick(label = changeHint) { onChange(); true }
                    },
                contentAlignment = Alignment.Center,
            ) {
                Text(label, style = activityFont(15f, FontWeight.Medium, tracking = -0.15f), color = DetailStyle.change)
            }
        }
    }
}
