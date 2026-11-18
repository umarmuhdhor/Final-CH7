package com.shoo.app.features.onboarding

import android.os.Handler
import android.os.Looper
import android.view.HapticFeedbackConstants
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.expandVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import com.shoo.app.R
import com.shoo.app.app.AppEnvironment
import com.shoo.app.app.LocalAppEnvironment
import com.shoo.app.bridge.AddonBridge
import com.shoo.app.components.FigmaFont
import com.shoo.app.components.HalftoneShield
import com.shoo.app.components.HalftoneShieldSize
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.dynamicColor
import com.shoo.app.components.HalftoneShieldTint
import com.shoo.app.components.hex
import com.shoo.app.components.scaled
import com.shoo.app.components.sfSymbol
import com.shoo.app.components.shooShadow
import com.shoo.app.components.shooSnappy
import com.shoo.app.data.ExtensionStatus
import com.shoo.app.support.L10n
import com.shoo.app.support.Log
import com.shoo.app.support.t
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * ON-04 inside onboarding: the online check question as a checkbox (Figma "Persetujuan · Checkbox", 1328:13421).
 * Turn on stays off until it is ticked; `prepare` saves the answer and registers the device. Without the checkbox
 * (answered before) the buttons are on (fase 27d K6). Swift `@Binding var isChecked` → `isChecked` + `onIsCheckedChange`.
 */
class OnboardingExtensionConsent(
    val isChecked: Boolean,
    val onIsCheckedChange: (Boolean) -> Unit,
    val showsCheckbox: Boolean = true,
    val isWorking: Boolean = false,
    val failed: Boolean = false,
    /** `true` once Firefox may open. */
    val prepare: suspend () -> Boolean,
)

/** A heartbeat can land a moment after the user is back: look again this many times, this far apart (#135). */
private const val RECHECK_TIMES = 10
private const val RECHECK_EVERY_MS = 2000L

/**
 * ON-04 (fallback PRD §10, Figma "Aktifkan Ekstensi"): where the add-on is, a Turn on button, a status check whenever
 * the app comes back, and a tutorial video. Reused as a sheet from PR-04 / GD-01 "Turn on".
 *
 * Android (PORTING.md): the steps describe Firefox for Android. "Turn on the extension" installs Firefox when it is
 * missing; otherwise it shows the one-time code (`AddonBridge`) above the steps and becomes "Open Firefox", where the
 * user adds the Shoo add-on and enters the code in its settings. Linking makes the status Active (`addonLinked`).
 *
 * - `refreshStatus`: re-reads the add-on status (on appear and when the user is back from Firefox).
 * - `onBack`: onboarding only, back to the name.
 * - `onSkipCheck`: onboarding only: Next once Shoo is on (after Back from Firefox Default, or linked before).
 * - `consent`: onboarding only, the consent checkbox.
 */
@Composable
fun TurnOnExtensionView(
    refreshStatus: suspend () -> ExtensionStatus? = { null },
    onBack: (() -> Unit)? = null,
    onSkipCheck: (() -> Unit)? = null,
    consent: OnboardingExtensionConsent? = null,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val env = LocalAppEnvironment.current
    val view = LocalView.current
    val language = LocalAppLanguage.current
    val reduceMotion = LocalReduceMotion.current
    val scope = rememberCoroutineScope()
    val phase = rememberOnboardingScenePhase()

    var isVideoPresented by remember { mutableStateOf(false) }
    var isDataSheetPresented by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<ExtensionStatus?>(null) }
    // Firefox or the Play Store was opened from here. Figma has no status note; it shows only once the user is back
    // and Shoo is still not on (#135).
    var leftForSettings by remember { mutableStateOf(false) }
    var cameBack by remember { mutableStateOf(false) }
    // Read again each time the user is back: installing Firefox changes the first step.
    val steps = remember(phase.activations) { ExtensionSetup.steps(context) }

    val link = remember(env) { AddonLink(env) }
    DisposableEffect(link) { onDispose { link.stop() } }

    val currentRefresh by rememberUpdatedState(refreshStatus)
    val currentSkip by rememberUpdatedState(onSkipCheck)
    val currentConsent by rememberUpdatedState(consent)

    val isChecked = consent?.let { !it.showsCheckbox || it.isChecked } ?: true
    val isWorking = consent?.isWorking ?: false
    // nil until the first read, and once Shoo is on.
    val nextStep = status?.nextStep
    // Only outside onboarding (Home "Turn on"). Onboarding always shows the Figma "Aktifkan Ekstensi" frame.
    val showsStatusNote = consent == null

    // On appear, every time the user is back from Firefox, and when the add-on just linked: read now, then a few more
    // times (no app restart needed, #135).
    LaunchedEffect(phase, link.linkedCount) {
        if (!phase.isActive) return@LaunchedEffect
        if (leftForSettings) cameBack = true
        for (attempt in 0 until RECHECK_TIMES) {
            if (attempt > 0) delay(RECHECK_EVERY_MS)
            val read = currentRefresh()
            status = read
            if (read != null && read.nextStep == null) return@LaunchedEffect
            // Onboarding keeps the Figma screen: back with the add-on linked, it moves on by itself.
            val skip = currentSkip
            if (skip != null && currentConsent != null && cameBack && read?.isActive == true) {
                skip()
                return@LaunchedEffect
            }
        }
    }

    val failed = consent?.failed ?: false
    LaunchedEffect(failed) {
        if (!failed) return@LaunchedEffect
        @Suppress("DEPRECATION")
        view.announceForAccessibility(L10n.string("Couldn't save. Check your connection and try again.", language))
    }

    /** Firefox missing: the Play Store. Else the code first (it stays on screen), then Firefox. */
    fun openSetup() {
        if (!com.shoo.app.data.ExtensionStatus.isFirefoxInstalled(context)) {
            leftForSettings = true
            ExtensionSetup.installFirefox(context)
            return
        }
        if (link.code == null) {
            link.start()
            return
        }
        leftForSettings = true
        ExtensionSetup.openFirefox(context)
    }

    fun open(safariFirst: Boolean) {
        scope.launch {
            val prepare = consent?.prepare
            if (prepare != null && !prepare()) return@launch
            if (safariFirst) {
                leftForSettings = true
                ExtensionSetup.openSafari(context)
            } else {
                openSetup()
            }
        }
    }

    OnboardingFormPage(
        title = "Turn on the extension",
        onBack = onBack,
        modifier = modifier,
        largeHeadline = true,
        footerEndsWithLink = true,
        // Figma "image 1" at y 72.5, the headline right under it at 373.
        hero = { OnboardingHeroImage(image = R.drawable.extension_illustration, top = 10.5.dp, bottom = 0.5.dp) },
        content = {
            // Figma "stack": 16 between rows, 40 under the headline.
            Column(
                modifier = Modifier.fillMaxWidth().padding(top = 40.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                // Android: the one-time code (or why there is none) sits where iOS puts the status note.
                val code = link.code
                val problem = link.problem
                AnimatedVisibility(
                    visible = code != null || problem != null,
                    enter = if (reduceMotion) fadeIn() else fadeIn() + expandVertically(),
                    exit = if (reduceMotion) fadeOut() else fadeOut() + shrinkVertically(),
                ) {
                    if (code != null) {
                        AddonCodeCard(code)
                    } else if (problem != null) {
                        StatusNote(t(problem), identifier = "extension.codeProblem")
                    }
                }
                // The reason first, above the steps, so it is seen without scrolling (#135).
                AnimatedVisibility(
                    visible = nextStep != null && showsStatusNote && code == null,
                    enter = if (reduceMotion) fadeIn() else fadeIn() + expandVertically(),
                    exit = if (reduceMotion) fadeOut() else fadeOut() + shrinkVertically(),
                ) {
                    nextStep?.let { StatusNote(t(it.message), identifier = "extension.offHint") }
                }
                // Once the add-on is known to be on, the setup steps are done; only the callout is left.
                if (!showsStatusNote || nextStep?.opensSafariFirst != true) {
                    steps.forEachIndexed { index, step ->
                        OnboardingStepRow(
                            number = index + 1,
                            text = step.text,
                            modifier = Modifier.semantics { testTag = "extension.step.${index + 1}" },
                        )
                    }
                }
                if (consent != null && consent.failed) {
                    OnboardingErrorLabel(
                        text = t("Couldn't save. Check your connection and try again."),
                        systemImage = "wifi.exclamationmark",
                        modifier = Modifier.fillMaxWidth().semantics { testTag = "extension.error" },
                    )
                }
            }
        },
        footer = {
            if (consent != null && consent.showsCheckbox) {
                // Figma: the checkbox block ends 55 above the button (this footer's rows are 16 apart, iOS 12).
                ConsentCheckbox(
                    isChecked = consent.isChecked,
                    onIsCheckedChange = consent.onIsCheckedChange,
                    onShowData = { isDataSheetPresented = true },
                    modifier = Modifier.padding(bottom = 39.dp),
                )
            }
            val currentStatus = status
            if (onSkipCheck != null && currentStatus != null && (nextStep == null || (consent != null && currentStatus.isActive))) {
                // Shoo is already on (Back from Firefox Default, or linked before): nothing left to do here.
                OnboardingCapsuleButton(onClick = onSkipCheck, enabled = isChecked, identifier = "extension.continue") {
                    WorkingLabel("Next", isWorking)
                }
            } else {
                // One main button that fits the reason (#135); the other half of the fix stays one tap away.
                val step = if (showsStatusNote) nextStep ?: ExtensionStatus.NextStep.SWITCH_ON else ExtensionStatus.NextStep.SWITCH_ON
                val opensFirefox = step.opensSafariFirst || link.code != null
                OnboardingCapsuleButton(
                    onClick = { open(safariFirst = step.opensSafariFirst) },
                    enabled = isChecked,
                    identifier = if (opensFirefox) "extension.openSafari" else "extension.turnOn",
                ) {
                    WorkingLabel(if (opensFirefox) "Open Firefox" else "Turn on the extension", isWorking)
                }
                // With the code on screen the main button already opens Firefox.
                AnimatedVisibility(
                    visible = showsStatusNote && step.hasSecondAction && link.code == null,
                    enter = fadeIn(),
                    exit = fadeOut(),
                ) {
                    OnboardingLinkButton(
                        title = if (step.opensSafariFirst) "Turn on the extension" else "Open Firefox",
                        onClick = {
                            if (step.opensSafariFirst) {
                                open(safariFirst = false)
                            } else {
                                leftForSettings = true
                                ExtensionSetup.openFirefox(context)
                            }
                        },
                        color = OnboardingTheme.ink,
                        weight = FontWeight.SemiBold,
                        enabled = isChecked,
                        identifier = if (step.opensSafariFirst) "extension.settings" else "extension.openSafariLink",
                    )
                }
                AnimatedVisibility(
                    visible = onSkipCheck != null && showsStatusNote && currentStatus?.isActive == true,
                    enter = fadeIn(),
                    exit = fadeOut(),
                ) {
                    OnboardingLinkButton(
                        title = "Continue without checking",
                        onClick = { onSkipCheck?.invoke() },
                        color = OnboardingTheme.secondaryInk,
                        weight = FontWeight.Normal,
                        enabled = isChecked,
                        identifier = "extension.skipCheck",
                    )
                }
            }
            OnboardingTutorialLink(
                action = { isVideoPresented = true },
                modifier = Modifier.semantics { testTag = "extension.video" },
            )
        },
    )

    if (isVideoPresented) TutorialVideoPlayer(onDismiss = { isVideoPresented = false })
    if (isDataSheetPresented) DataSentSheet(onDismiss = { isDataSheetPresented = false })
}

/** The capsule's title, or a spinner in its place while the device registers. `title`: catalog key. */
@Composable
private fun WorkingLabel(title: String, isWorking: Boolean) {
    Box(contentAlignment = Alignment.Center) {
        Text(t(title), textAlign = TextAlign.Center, modifier = Modifier.alpha(if (isWorking) 0f else 1f))
        if (isWorking) {
            CircularProgressIndicator(modifier = Modifier.size(20.dp), color = OnboardingTheme.onButton, strokeWidth = 2.dp)
        }
    }
}

/** iOS's status `Label` in a white card: `info.circle.fill` + the reason. `text`: localized. */
@Composable
private fun StatusNote(text: String, identifier: String, modifier: Modifier = Modifier) {
    val ink = OnboardingTheme.ink
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(OnboardingTheme.card, RoundedCornerShape(16.dp))
            .padding(14.dp)
            .semantics(mergeDescendants = true) { testTag = identifier },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.Top,
    ) {
        SfSymbol("info.circle.fill", pointSize = 15f, tint = ink)
        Text(text, style = onboardingFont(15f, rounded = true).copy(color = ink), modifier = Modifier.weight(1f))
    }
}

/**
 * Android only: the one-time code the Shoo add-on asks for in its settings (`AddonBridge`), in the status note's card.
 * The code is never logged.
 */
@Composable
private fun AddonCodeCard(code: String, modifier: Modifier = Modifier) {
    val spoken = code.toList().joinToString(" ")
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(OnboardingTheme.card, RoundedCornerShape(16.dp))
            .padding(14.dp)
            .semantics(mergeDescendants = true) { testTag = "extension.code" },
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(t("Your Firefox code"), style = onboardingFont(15f, rounded = true).copy(color = OnboardingTheme.secondaryInk))
        Text(
            code.chunked(3).joinToString(" "),
            style = onboardingFont(34f, FontWeight.SemiBold, tracking = 4f, family = FigmaFont.Family.TEXT)
                .copy(color = OnboardingTheme.ink),
            modifier = Modifier.semantics { contentDescription = spoken },
        )
        Text(
            t("Enter it in the Shoo add-on's settings within 10 minutes."),
            style = onboardingFont(15f, rounded = true).copy(color = OnboardingTheme.secondaryInk),
        )
    }
}

/**
 * Android only: runs `AddonBridge` while the code is on screen. Linking (on the bridge's thread) marks the add-on
 * Active and bumps `linkedCount` on the main thread, which re-reads the status.
 */
private class AddonLink(private val env: AppEnvironment) {
    var code by mutableStateOf<String?>(null)
        private set

    /** Catalog key of why no code shows (expired, locked, could not start). */
    var problem by mutableStateOf<String?>(null)
        private set
    var linkedCount by mutableIntStateOf(0)
        private set

    private val main = Handler(Looper.getMainLooper())
    private val bridge = AddonBridge(
        session = { env.addonSession() },
        onLinked = {
            env.addonLinked()
            main.post { linkedCount += 1 }
        },
        onClosed = { reason -> main.post { closed(reason) } },
    )

    fun start() {
        problem = null
        code = try {
            bridge.start()
        } catch (error: Exception) {
            Log.app.error("Add-on link failed", error)
            problem = "Couldn't show a code. Try again."
            null
        }
    }

    fun stop() = bridge.stop("stopped")

    private fun closed(reason: String) {
        when (reason) {
            "expired" -> {
                code = null
                problem = "The code has expired. Tap the button to get a new one."
            }
            "locked" -> {
                code = null
                problem = "Too many wrong codes. Tap the button to get a new one."
            }
            "linked" -> {
                code = null
                problem = null
            }
            // "restart" (a new code replaced it) and "stopped" (screen gone): nothing to show.
            else -> Unit
        }
    }
}

/** Figma "Persetujuan · Checkbox": a 24 pt box, the sentence, and "Lihat data yang dikirim" 2 pt under it. */
@Composable
private fun ConsentCheckbox(
    isChecked: Boolean,
    onIsCheckedChange: (Boolean) -> Unit,
    onShowData: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val boxSize = scaled(24f)
    val reduceMotion = LocalReduceMotion.current
    val view = LocalView.current
    val checkedFill = dynamicColor(0x1E6FCB, 0x3D8BE0)
    val link = dynamicColor(0x186FB9, 0x5EAAF0)
    val fill by animateColorAsState(if (isChecked) checkedFill else OnboardingTheme.card, shooSnappy(0.2), label = "consentFill")
    val stroke by animateColorAsState(if (isChecked) checkedFill else OnboardingTheme.placeholder, shooSnappy(0.2), label = "consentStroke")
    val textStyle = onboardingFont(17f, rounded = true, tracking = -0.17f)

    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .toggleable(
                    value = isChecked,
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    role = Role.Checkbox,
                    onValueChange = {
                        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                        onIsCheckedChange(it)
                    },
                )
                .semantics(mergeDescendants = true) { testTag = "extension.consent" },
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Box(
                modifier = Modifier
                    .size(boxSize)
                    .background(fill, RoundedCornerShape(6.dp))
                    .border(2.dp, stroke, RoundedCornerShape(6.dp)),
                contentAlignment = Alignment.Center,
            ) {
                // Pops in under the toggle's snappy spring; a plain fade with Reduce Motion.
                androidx.compose.animation.AnimatedVisibility(
                    visible = isChecked,
                    enter = if (reduceMotion) fadeIn() else scaleIn(shooSnappy(0.2), initialScale = 0.6f) + fadeIn(),
                    exit = if (reduceMotion) fadeOut() else scaleOut(shooSnappy(0.2), targetScale = 0.6f) + fadeOut(),
                ) {
                    // `.font(.system(size: box × 0.55, weight: .bold))`.
                    Icon(sfSymbol("checkmark"), contentDescription = null, tint = Color.White, modifier = Modifier.size(boxSize * 0.75f))
                }
            }
            Text(
                t("I agree to pages being checked online."),
                style = textStyle.copy(color = OnboardingTheme.stepInk),
                modifier = Modifier.weight(1f),
            )
        }
        // 44 pt to tap, laid out as its 22 pt line.
        val extra = with(LocalDensity.current) { 11.dp.roundToPx() }
        Text(
            t("See what is sent"),
            style = textStyle.copy(color = link),
            modifier = Modifier
                .padding(start = boxSize + 12.dp)
                .layout { measurable, constraints ->
                    val placeable = measurable.measure(constraints.copy(maxHeight = Constraints.Infinity))
                    layout(placeable.width, (placeable.height - extra * 2).coerceAtLeast(0)) { placeable.place(0, -extra) }
                }
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    role = Role.Button,
                    onClick = onShowData,
                )
                .semantics { testTag = "extension.dataSent" }
                .padding(vertical = 11.dp),
        )
    }
}

/**
 * Figma "Sheet · Data yang dikirim" (1328:13313): what leaves the phone with the online check on. A 618 pt sheet with
 * 32 pt corners and a grabber; larger text scrolls. `onDismiss`: the sheet has closed (iOS `@Environment(\.dismiss)`).
 * iOS: a `.large` detent the user can pull it up to; here it is one height.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DataSentSheet(onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val dismiss: () -> Unit = {
        scope.launch { sheetState.hide() }.invokeOnCompletion { onDismiss() }
    }
    val card = OnboardingTheme.card
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        modifier = modifier,
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp),
        containerColor = card,
        dragHandle = {
            // `.presentationDragIndicator(.visible)`: 36 × 5, 5 pt from the top.
            Box(
                Modifier
                    .padding(top = 5.dp)
                    .size(36.dp, 5.dp)
                    .background(dynamicColor(0xC7C7CC, 0x5A5A5E), CircleShape),
            )
        },
        contentWindowInsets = { WindowInsets(0, 0, 0, 0) },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .height(618.dp - 10.dp)
                .navigationBarsPadding()
                .padding(start = 24.dp, end = 24.dp, top = 15.dp, bottom = 8.dp),
        ) {
            Row(verticalAlignment = Alignment.Top) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        t("What is sent"),
                        style = onboardingFont(28f, FontWeight.SemiBold, tracking = -0.4f).copy(color = OnboardingTheme.ink),
                        modifier = Modifier.semantics { heading() },
                    )
                    Text(
                        t("When the online check is on."),
                        style = onboardingFont(17f, rounded = true, tracking = -0.17f).copy(color = OnboardingTheme.bodyInk),
                    )
                }
                Spacer(Modifier.width(12.dp))
                val close = t("Close")
                Box(
                    modifier = Modifier
                        .offset(x = 6.dp)
                        .size(44.dp)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            role = Role.Button,
                            onClick = dismiss,
                        )
                        .semantics { contentDescription = close },
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier.size(32.dp).background(OnboardingTheme.background, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        SfSymbol("xmark", pointSize = 14f, tint = OnboardingTheme.secondaryInk)
                    }
                }
            }
            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(top = 20.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                DataSentRow("doc.text.magnifyingglass", 0x1E6FCB, 0xE6F0FB, "Pages you open",
                    "Page text, form field names and the address. What you type is not sent.")
                DataSentRow("exclamationmark.shield", 0xD23B3B, 0xFDECEC, "Risky pages",
                    "The address and a copy are kept. Some of it stays after the account is deleted.")
                DataSentRow("sparkles", 0x0D8F93, 0xE2F6F4, "AI check by DeepSeek",
                    "A summary of a suspicious page is sent to DeepSeek, an AI from China.")
                DataSentRow("iphone", 0x5B616C, 0xEEF0F3, "Without the online check",
                    "Shoo checks on your phone only, with less protection.")
            }
            OnboardingCapsuleButton(
                title = "Got it",
                onClick = dismiss,
                identifier = "dataSent.done",
                modifier = Modifier.padding(top = 20.dp),
            )
        }
    }
}

/** `title`, `text`: catalog keys. */
@Composable
private fun DataSentRow(symbol: String, tint: Int, fill: Int, title: String, text: String) {
    Row(
        modifier = Modifier.semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(
            Modifier
                .size(40.dp)
                .background(hex(fill), RoundedCornerShape(10.dp))
                .clearAndSetSemantics { },
            contentAlignment = Alignment.Center,
        ) {
            SfSymbol(symbol, pointSize = 18f, tint = hex(tint))
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(t(title), style = onboardingFont(17f, FontWeight.SemiBold).copy(color = OnboardingTheme.ink))
            Text(t(text), style = onboardingFont(16f, rounded = true, tracking = -0.31f).copy(color = OnboardingTheme.bodyInk))
        }
    }
}

/**
 * Figma: "Terkendala? " regular ink + "Tonton Tutorial" semibold blue, as an `OnboardingLinkButton` (SF Pro Text 15,
 * -2 %, 20 pt row, 44 pt hit area).
 */
@Composable
fun OnboardingTutorialLink(action: () -> Unit, modifier: Modifier = Modifier) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val extra = with(LocalDensity.current) { 12.dp.roundToPx() }
    val linkColor = OnboardingTheme.link
    val text = buildAnnotatedString {
        append(t("Having trouble?"))
        append(" ")
        withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, color = linkColor)) { append(t("Watch the tutorial")) }
    }
    Box(
        modifier = modifier
            .fillMaxWidth()
            .layout { measurable, constraints ->
                val placeable = measurable.measure(constraints.copy(maxHeight = Constraints.Infinity))
                layout(placeable.width, (placeable.height - extra * 2).coerceAtLeast(0)) { placeable.place(0, -extra) }
            }
            .clickable(interactionSource = interaction, indication = null, role = Role.Button, onClick = action)
            .padding(vertical = 12.dp)
            .graphicsLayer { alpha = if (pressed) 0.6f else 1f },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            style = onboardingFont(15f, FontWeight.Normal, tracking = -0.3f, family = FigmaFont.Family.TEXT, lineHeight = 20f)
                .copy(color = OnboardingTheme.ink, textAlign = TextAlign.Center),
        )
    }
}

/** White 40 pt badge "01" + one instruction (Figma "row"). `text`: catalog key. */
@Composable
fun OnboardingStepRow(number: Int, text: String, modifier: Modifier = Modifier) {
    val badgeSize = scaled(40f)
    val stepLabel = t("Step %lld", number)
    Row(
        modifier = modifier.semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(
            modifier = Modifier
                .size(badgeSize)
                // Figma "Button": black 20%, y 2.7, blur 4.5 (its -2.7 spread is left out, like iOS).
                .shooShadow(Color.Black.copy(alpha = 0.2f), radius = 2.3.dp, y = 2.7.dp, shape = CircleShape)
                .background(OnboardingTheme.card, CircleShape)
                .semantics { contentDescription = stepLabel },
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "%02d".format(number),
                style = onboardingFont(15f, FontWeight.SemiBold, tracking = -0.19f)
                    .copy(color = dynamicColor(0x136CB7, 0x5EAAF0)),
                modifier = Modifier.clearAndSetSemantics { },
            )
        }
        Box(
            modifier = Modifier.weight(1f).heightIn(min = badgeSize),
            contentAlignment = Alignment.CenterStart,
        ) {
            // Figma: 22 pt lines, the font's own.
            Text(t(text), style = onboardingFont(17f, rounded = true, tracking = -0.17f).copy(color = OnboardingTheme.stepInk))
        }
    }
}

/** ON-04 passed (Figma "Yeay, kamu berhasil lebih terlindungi!"). */
@Composable
fun ExtensionOnView(onContinue: () -> Unit, modifier: Modifier = Modifier) {
    val shieldScale = 1.67f
    OnboardingSuccessPage(
        title = t("Yeay, you're better protected now!"),
        message = t("The extension is on and ready to help spot possible scams on the internet."),
        idPrefix = "extensionOn",
        onContinue = onContinue,
        modifier = modifier,
        largeTitle = false,
        // "Yeay": the shield pops in with rings and confetti, a heavy tap as it lands and a success tap with the title.
        celebrates = true,
    ) {
        // Figma: the teal shield, its outline 177 pt wide around y 268; the headline at y 437.
        Box(
            modifier = Modifier
                .padding(top = 59.dp, bottom = 21.dp)
                .successCelebrationHero(ringSize = 177.dp)
                .size(HalftoneShieldSize.width * shieldScale, HalftoneShieldSize.height * shieldScale),
            contentAlignment = Alignment.Center,
        ) {
            HalftoneShield(
                modifier = Modifier
                    .requiredSize(HalftoneShieldSize)
                    .graphicsLayer {
                        scaleX = shieldScale
                        scaleY = shieldScale
                    },
                tint = HalftoneShieldTint.TEAL,
            )
        }
    }
}
