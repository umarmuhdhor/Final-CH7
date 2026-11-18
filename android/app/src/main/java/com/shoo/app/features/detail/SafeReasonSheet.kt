package com.shoo.app.features.detail

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.LightOnly
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.hex
import com.shoo.app.features.activity.activityFont
import com.shoo.app.support.t
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Why the Guardian overrides Shoo with "Aman" (GD-07). Shoo flagged the site; the Guardian says it is fine.
 * The ids are stable English slugs so Team AI can learn from them (layer 5, #241); the chip text is localized.
 */
enum class SafeReason(val rawValue: String) {
    OFFICIAL_SITE("official_site"),
    KNOWN_SITE("known_site"),
    USED_BEFORE("used_before"),
    TRUSTED_SENDER("trusted_sender"),
    OTHER("other");

    val id: String get() = rawValue

    /** Catalog key of the chip. */
    val label: String
        get() = when (this) {
            OFFICIAL_SITE -> "Official site"
            KNOWN_SITE -> "I know this site"
            USED_BEFORE -> "Used it before, no problems"
            TRUSTED_SENDER -> "Sent by someone I trust"
            OTHER -> "Other"
        }
}

/**
 * The `notes` of `POST /verdicts` for a safe override. The contract has only free text (280 characters,
 * contracts/api.md "Verdicts"), so the reasons go first on their own line, then the Guardian's note:
 *
 *     reasons: official_site, used_before
 *     Ini situs resmi bank saya.
 */
object SafeReasonNotes {
    /** The Guardian's own text (Figma counter "90/200"). With every reason picked the whole stays under 280. */
    const val maxNoteLength = 200

    fun compose(reasons: Set<SafeReason>, note: String): String {
        val ids = SafeReason.entries.filter { it in reasons }.map { it.rawValue }
        val line = "reasons: " + ids.joinToString(", ")
        val text = prefix(note.trim(), maxNoteLength)
        return if (text.isEmpty()) line else line + "\n" + text
    }

    /** At most `count` characters (code points), never half a surrogate pair. */
    internal fun prefix(text: String, count: Int): String {
        if (text.codePointCount(0, text.length) <= count) return text
        return text.substring(0, text.offsetByCodePoints(0, count))
    }

    internal fun length(text: String): Int = text.codePointCount(0, text.length)
}

/** Green mirror of the Figma red "Tandai Bahaya" sheet. White on `buttonTop` is 4.6:1. */
object SafeReasonStyle {
    val chipFill = DetailStyle.safeIconFill
    val chipStroke = DetailStyle.safeIcon
    val chipText = DetailStyle.hex(0x1A7F37)
    val chipIdleStroke = DetailStyle.hex(0xE3E7ED)
    val focus = DetailStyle.hex(0x3866ED)
    val buttonTop = DetailStyle.hex(0x1A7F37)
    val buttonBottom = DetailStyle.hex(0x2DA44E)
    val errorIcon = DetailStyle.hex(0xC81414)
}

/** A save that is running finishes even when the sheet or the screen goes (iOS `Task { }`). */
private val safeReasonTasks = MainScope()

/**
 * Figma "Sheet · Tandai bahaya" (1668:11234, states 1668:10768 / 1668:11093 / 1668:11261), turned around for "Aman":
 * the Guardian picks at least one reason and may add a note before the site counts as safe.
 * X or a swipe down closes it and drops the input. A failed save keeps the sheet and the input.
 *
 * `onSubmit` sends the verdict; `true` once the server saved it (the sheet then closes).
 * The content of the sheet: the caller shows it in a `ModalBottomSheet` (white, 32 dp top corners, `dragHandle = null`:
 * this draws iOS's grabber itself), sized to its content, or uses `SafeReasonSheetPresenter`, which does all of that and
 * also refuses a swipe down while saving (iOS `.interactiveDismissDisabled`).
 * `onDismiss` is iOS's environment `dismiss` (X, and after a save): the caller stops showing the sheet.
 * `onSavingChange` (Android only): told when a save starts and ends, for the caller's sheet state.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SafeReasonSheet(
    onSubmit: suspend (String) -> Boolean,
    onDismiss: () -> Unit = {},
    onSavingChange: (Boolean) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val reduceMotion = LocalReduceMotion.current
    val view = LocalView.current
    val haptics = LocalHapticFeedback.current
    val focusManager = LocalFocusManager.current
    var reasons by remember { mutableStateOf(emptySet<SafeReason>()) }
    var note by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    var noteFocused by remember { mutableStateOf(false) }
    val currentSubmit by rememberUpdatedState(onSubmit)
    val currentDismiss by rememberUpdatedState(onDismiss)
    val currentSavingChange by rememberUpdatedState(onSavingChange)
    val submitRequester = remember { BringIntoViewRequester() }
    val canSubmit = reasons.isNotEmpty() && !isSaving

    fun submit() {
        if (!canSubmit) return
        focusManager.clearFocus()
        isSaving = true
        currentSavingChange(true)
        val notes = SafeReasonNotes.compose(reasons, note)
        safeReasonTasks.launch {
            val saved = currentSubmit(notes)
            isSaving = false
            currentSavingChange(false)
            if (saved) {
                currentDismiss()
            } else {
                if (!failed) DetailHaptics.error(view)
                failed = true
            }
        }
    }

    // U-11: "Mark Safe" sat under the keyboard while typing: once the keyboard has settled, scroll it into view.
    val imeBottom = WindowInsets.ime.getBottom(LocalDensity.current)
    LaunchedEffect(noteFocused, imeBottom) {
        if (!noteFocused || imeBottom == 0) return@LaunchedEffect
        delay(100)
        submitRequester.bringIntoView()
    }

    LightOnly {
        Box(modifier.fillMaxWidth()) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .semantics { testTag = "safeReason.sheet" }
                    .padding(start = 24.dp, end = 24.dp, top = 24.dp, bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Header(isSaving = isSaving, onClose = { currentDismiss() })
                Text(
                    t("Why is it safe?"),
                    style = activityFont(17f, FontWeight.SemiBold),
                    color = DetailStyle.title,
                    modifier = Modifier.semantics { heading() },
                )
                // Figma "Chips alasan": wrapping row, 8 pt apart both ways.
                FlowLayout(spacing = 8.dp) {
                    for (reason in SafeReason.entries) {
                        val selected = reason in reasons
                        ReasonChip(reason, selected) {
                            reasons = if (selected) reasons - reason else reasons + reason
                            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        }
                    }
                }
                Text(
                    t("Note (optional)"),
                    style = activityFont(17f, FontWeight.SemiBold),
                    color = DetailStyle.title,
                    modifier = Modifier
                        .padding(top = 4.dp)
                        .semantics { heading() },
                )
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    NoteField(note, noteFocused, onNoteChange = { note = SafeReasonNotes.prefix(it, SafeReasonNotes.maxNoteLength) }) {
                        noteFocused = it
                    }
                    val count = SafeReasonNotes.length(note)
                    val counterLabel = t("%lld of %lld characters", count, SafeReasonNotes.maxNoteLength)
                    Row(verticalAlignment = Alignment.Top) {
                        Text(
                            t("Don't write a PIN, OTP or account number."),
                            style = activityFont(13f, rounded = true),
                            color = DetailStyle.secondary,
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            "$count/${SafeReasonNotes.maxNoteLength}",
                            style = activityFont(13f, rounded = true).copy(fontFeatureSettings = "tnum"),
                            color = DetailStyle.secondary,
                            modifier = Modifier
                                .padding(start = 12.dp)
                                .clearAndSetSemantics { contentDescription = counterLabel },
                        )
                    }
                }
                AnimatedVisibility(
                    visible = failed,
                    enter = if (reduceMotion) fadeIn() else fadeIn() + slideInVertically { 12 },
                    exit = fadeOut(),
                ) {
                    ErrorBanner()
                }
                SubmitButton(
                    failed = failed,
                    isSaving = isSaving,
                    hasReasons = reasons.isNotEmpty(),
                    enabled = canSubmit,
                    onTap = { submit() },
                    modifier = Modifier
                        .padding(top = 4.dp)
                        .bringIntoViewRequester(submitRequester),
                )
            }
            // iOS `.presentationDragIndicator(.visible)`: 36 × 5 at 5 pt from the top.
            Box(
                Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 5.dp)
                    .size(36.dp, 5.dp)
                    .background(hex(0x3C3C43, 0.3f), CapsuleShape)
                    .clearAndSetSemantics { },
            )
        }
    }
}

/**
 * Shows `SafeReasonSheet` the way iOS's `.sheet` does: a `ModalBottomSheet` sized to its content, 32 dp corners, white,
 * no swipe-down while a save runs. `onDismiss`: the sheet is gone (X, swipe down, back, or saved).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SafeReasonSheetPresenter(onSubmit: suspend (String) -> Boolean, onDismiss: () -> Unit) {
    var saving by remember { mutableStateOf(false) }
    val savingNow by rememberUpdatedState(saving)
    val currentDismiss by rememberUpdatedState(onDismiss)
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        confirmValueChange = { it != SheetValue.Hidden || !savingNow },
    )
    ModalBottomSheet(
        onDismissRequest = { if (!saving) currentDismiss() },
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp),
        containerColor = Color.White,
        contentColor = DetailStyle.title,
        tonalElevation = 0.dp,
        dragHandle = null,
    ) {
        SafeReasonSheet(
            onSubmit = onSubmit,
            onDismiss = { scope.launch { sheetState.hide() }.invokeOnCompletion { currentDismiss() } },
            onSavingChange = { saving = it },
        )
    }
}

@Composable
private fun Header(isSaving: Boolean, onClose: () -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                t("Mark as safe"),
                style = activityFont(28f, FontWeight.SemiBold),
                color = DetailStyle.title,
                modifier = Modifier.semantics { heading() },
            )
            Text(
                t("Shoo flagged this site. Tell us why it's safe. It helps Shoo block fewer good sites."),
                style = activityFont(16f, rounded = true, tracking = -0.31f),
                color = DetailStyle.secondary,
            )
        }
        val label = t("Close")
        Box(
            Modifier
                .offset(x = 7.dp, y = (-7).dp)
                .size(44.dp)
                .clickable(enabled = !isSaving, role = Role.Button, onClick = onClose)
                .semantics {
                    contentDescription = label
                    testTag = "safeReason.close"
                },
            contentAlignment = Alignment.Center,
        ) {
            Box(
                Modifier
                    .size(30.dp)
                    .background(DetailStyle.greyBadgeFill, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                SfSymbol("xmark", pointSize = 13f, tint = DetailStyle.secondary)
            }
        }
    }
}

@Composable
private fun ReasonChip(reason: SafeReason, selected: Boolean, onToggle: () -> Unit) {
    Box(
        Modifier
            .background(if (selected) SafeReasonStyle.chipFill else Color.White, CapsuleShape)
            .border(
                if (selected) 1.5.dp else 1.dp,
                if (selected) SafeReasonStyle.chipStroke else SafeReasonStyle.chipIdleStroke,
                CapsuleShape,
            )
            .clickable(role = Role.Checkbox, onClick = onToggle)
            .semantics {
                this.selected = selected
                testTag = "safeReason.chip.${reason.rawValue}"
            }
            .padding(horizontal = 14.dp, vertical = 9.dp),
    ) {
        Text(
            t(reason.label),
            style = activityFont(16f, rounded = true, tracking = -0.31f),
            color = if (selected) SafeReasonStyle.chipText else DetailStyle.title,
        )
    }
}

@Composable
private fun NoteField(note: String, focused: Boolean, onNoteChange: (String) -> Unit, onFocus: (Boolean) -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    val label = t("Note (optional)")
    val placeholder = t("e.g. This is my bank's real site, I checked the address.")
    val focusRequester = remember { FocusRequester() }
    val style = activityFont(16f, rounded = true, tracking = -0.31f)
    BasicTextField(
        value = note,
        onValueChange = onNoteChange,
        textStyle = style.copy(color = DetailStyle.title),
        cursorBrush = SolidColor(SafeReasonStyle.focus),
        minLines = 3,
        maxLines = 3,
        modifier = Modifier
            .fillMaxWidth()
            .focusRequester(focusRequester)
            .onFocusChanged { onFocus(it.isFocused) }
            .semantics {
                contentDescription = label
                testTag = "safeReason.note"
            },
        decorationBox = { inner ->
            // Figma: grey and borderless while empty and idle, white with a blue rim while typing.
            Box(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 96.dp)
                    .background(if (focused) Color.White else DetailStyle.cardFill, shape)
                    .border(1.5.dp, if (focused) SafeReasonStyle.focus else Color.Transparent, shape)
                    .padding(horizontal = 16.dp, vertical = 14.dp),
            ) {
                if (note.isEmpty()) {
                    Text(placeholder, style = style, color = DetailStyle.secondary.copy(alpha = 0.8f))
                }
                inner()
            }
        },
    )
}

/** Figma 1668:11261 "Gagal menyimpan": the input stays, the button becomes "Coba lagi". */
@Composable
private fun ErrorBanner() {
    val shape = RoundedCornerShape(14.dp)
    val title = t("Couldn't save")
    val line = t("Check your connection. Your note isn't lost.")
    Row(
        Modifier
            .fillMaxWidth()
            .background(Color.White, shape)
            .border(1.dp, SafeReasonStyle.chipIdleStroke, shape)
            .clearAndSetSemantics {
                contentDescription = "$title, $line"
                testTag = "safeReason.error"
            }
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(32.dp)
                .background(DetailStyle.scamIconFill, RoundedCornerShape(8.dp)),
            contentAlignment = Alignment.Center,
        ) {
            SfSymbol("exclamationmark.arrow.circlepath", pointSize = 15f, tint = SafeReasonStyle.errorIcon)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = activityFont(15f, FontWeight.SemiBold), color = DetailStyle.ink)
            Text(line, style = activityFont(13f, rounded = true), color = DetailStyle.secondary)
        }
    }
}

@Composable
private fun SubmitButton(
    failed: Boolean,
    isSaving: Boolean,
    hasReasons: Boolean,
    enabled: Boolean,
    onTap: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val title = t(if (failed) "Try again" else "Mark Safe")
    val hint = if (hasReasons) null else t("Pick at least one reason first")
    Row(
        modifier
            .fillMaxWidth()
            // Figma: the button fades until at least one reason is picked.
            .graphicsLayer { alpha = if (hasReasons) 1f else 0.35f }
            .background(Brush.verticalGradient(listOf(SafeReasonStyle.buttonBottom, SafeReasonStyle.buttonTop)), CapsuleShape)
            .border(1.5.dp, SafeReasonStyle.buttonTop, CapsuleShape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onTap)
            .semantics {
                testTag = "safeReason.submit"
                if (hint != null) onClick(label = hint) { onTap(); true }
            }
            .heightIn(min = 56.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (isSaving) {
            CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
        } else {
            SfSymbol(if (failed) "arrow.clockwise" else "checkmark.circle.fill", pointSize = 17f, tint = Color.White)
        }
        Text(title, style = activityFont(17f, FontWeight.SemiBold), color = Color.White, textAlign = TextAlign.Center)
    }
}

/** Left-aligned wrapping row (Figma auto layout "WRAP"), `spacing` apart both ways. */
@Composable
fun FlowLayout(modifier: Modifier = Modifier, spacing: Dp = 8.dp, content: @Composable () -> Unit) {
    Layout(content = content, modifier = modifier) { measurables, constraints ->
        val gap = spacing.roundToPx()
        val width = constraints.maxWidth
        val placeables = measurables.map { it.measure(Constraints(maxWidth = width)) }
        val rows = ArrayList<MutableList<Int>>()
        val rowHeights = ArrayList<Int>()
        var rowWidth = 0
        for ((index, placeable) in placeables.withIndex()) {
            val row = rows.lastOrNull()
            val next = if (row == null || row.isEmpty()) placeable.width else rowWidth + gap + placeable.width
            if (row != null && row.isNotEmpty() && next > width) {
                rows.add(mutableListOf(index))
                rowHeights.add(placeable.height)
                rowWidth = placeable.width
            } else if (row == null) {
                rows.add(mutableListOf(index))
                rowHeights.add(placeable.height)
                rowWidth = placeable.width
            } else {
                row.add(index)
                rowHeights[rowHeights.lastIndex] = maxOf(rowHeights.last(), placeable.height)
                rowWidth = next
            }
        }
        val height = rowHeights.sum() + gap * maxOf(0, rows.size - 1)
        val layoutWidth = if (constraints.hasBoundedWidth) width else (rows.maxOfOrNull { r -> r.sumOf { placeables[it].width } + gap * (r.size - 1) } ?: 0)
        layout(layoutWidth, height.coerceIn(constraints.minHeight, constraints.maxHeight)) {
            var y = 0
            for ((rowIndex, row) in rows.withIndex()) {
                var x = 0
                for (index in row) {
                    placeables[index].place(x, y)
                    x += placeables[index].width + gap
                }
                y += rowHeights[rowIndex] + gap
            }
        }
    }
}
