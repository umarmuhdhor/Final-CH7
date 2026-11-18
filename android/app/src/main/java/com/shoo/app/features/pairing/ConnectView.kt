package com.shoo.app.features.pairing

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.composed
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.shoo.app.R
import com.shoo.app.app.LocalAppEnvironment
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.FigmaFont
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.StateMotion
import com.shoo.app.components.hex
import com.shoo.app.components.sfSymbol
import com.shoo.app.components.shooEaseInOut
import com.shoo.app.components.shooEaseOut
import com.shoo.app.components.shooShadow
import com.shoo.app.components.shooSmooth
import com.shoo.app.components.shooSnappy
import com.shoo.app.components.shooSpring
import com.shoo.app.components.textScale
import com.shoo.app.data.GuardianInfo
import com.shoo.app.features.activity.OnChange
import com.shoo.app.features.onboarding.ConnectedOrbitIllustration
import com.shoo.app.features.onboarding.OnboardingCapsuleButton
import com.shoo.app.features.onboarding.OnboardingFormPage
import com.shoo.app.features.onboarding.OnboardingLinkButton
import com.shoo.app.features.onboarding.OnboardingSuccessPage
import com.shoo.app.features.onboarding.OnboardingTheme
import com.shoo.app.features.onboarding.onboardingBodyStyle
import com.shoo.app.features.onboarding.onboardingFont
import com.shoo.app.support.L10n
import com.shoo.app.support.Log
import com.shoo.app.support.t
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import kotlin.math.min

/** Swift `ConnectView.Tab`. */
enum class ConnectTab { SCAN, CODE }

/**
 * PR-01: connect to the guardian by Scan QR or Code, then PR-02 "Connected to …" (Figma "Connect with Guardian").
 * Used in onboarding (with "Not now") and from Shield / an invite link after onboarding.
 *
 * `onBack`: after onboarding (sheet): close. Inside onboarding: back to ON-03 until the mode is saved.
 * `onSkip`: continue without a guardian for now. `onFinish`: after PR-02 (last, so it can be a trailing lambda).
 */
@Composable
fun ConnectView(
    model: ConnectModel,
    onBack: (() -> Unit)? = null,
    onSkip: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
    onFinish: () -> Unit,
) {
    val reduceMotion = LocalReduceMotion.current
    val view = LocalView.current
    val guardian = (model.state as? ConnectModel.State.Joined)?.guardian
    // A success tap when PR-02 arrives.
    OnChange(guardian != null) { joined -> if (joined) confirmHaptic(view) }

    AnimatedContent(
        targetState = guardian,
        contentKey = { it != null },
        transitionSpec = {
            // PR-02: "Connected to …" settles in instead of replacing the form at once.
            if (reduceMotion) {
                fadeIn(shooEaseInOut(0.2)) togetherWith fadeOut(shooEaseInOut(0.2))
            } else {
                (fadeIn(shooSmooth(0.4)) + scaleIn(shooSmooth(0.4), initialScale = 0.97f)) togetherWith fadeOut(shooSmooth(0.4))
            }
        },
        modifier = modifier,
        label = "connect",
    ) { joined ->
        if (joined != null) {
            ProtectedByView(guardian = joined, onContinue = onFinish)
        } else {
            ConnectForm(model, onBack, onSkip)
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ConnectForm(model: ConnectModel, onBack: (() -> Unit)?, onSkip: (() -> Unit)?) {
    val reduceMotion = LocalReduceMotion.current
    val language = LocalAppLanguage.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    var tab by remember { mutableStateOf(ConnectTab.CODE) }
    var scanRefused by remember { mutableStateOf(false) }
    var codeFocused by remember { mutableStateOf(false) }
    // Bumped each time a problem shows: shakes the code boxes once and taps an error haptic.
    var problemsShown by remember { mutableIntStateOf(0) }
    // Bumped by "Ketik ulang kode": the code field takes focus again.
    var focusRequests by remember { mutableIntStateOf(0) }
    val codeField = remember { BringIntoViewRequester() }
    val problem = model.problem

    OnChange(tab) { scanRefused = false }
    OnChange(scanRefused) { refused ->
        if (refused) {
            announce(view, L10n.string("This QR isn't a Shoo invite code. Scan the QR from your Guardian's Shoo app.", language))
        }
    }
    OnChange(problem) { shown ->
        if (shown == null) return@OnChange
        problemsShown += 1
        errorHaptic(view)
        announce(view, L10n.string(shown.message, language))
    }

    OnboardingFormPage(
        title = "Connect your account",
        onBack = onBack?.let { back -> { if (!model.isBusy) back() } },
        message = "Scan the QR or enter the invite code from your Guardian.",
        scrollTarget = if (codeFocused || problem != null) codeField else null,
        headlineInset = 24.dp,
        footerEndsWithLink = onSkip != null,
        content = {
            // Figma: tabs at y 242, label at y 332.
            ConnectTabs(tab = tab, onTabChange = { tab = it }, modifier = Modifier.padding(top = 37.dp))

            AnimatedContent(
                targetState = tab,
                transitionSpec = { fadeIn(shooSnappy(0.3)) togetherWith fadeOut(shooSnappy(0.3)) },
                label = "connectTab",
            ) { shownTab ->
                when (shownTab) {
                    ConnectTab.SCAN -> Column(
                        Modifier
                            .fillMaxWidth()
                            .padding(top = 24.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        ScannerFrame {
                            QRScannerView(Modifier.fillMaxSize()) { payload ->
                                if (model.scanned(payload)) {
                                    scanRefused = false
                                    tab = ConnectTab.CODE
                                } else {
                                    scanRefused = true
                                }
                            }
                        }
                        AnimatedVisibility(
                            visible = scanRefused,
                            enter = StateMotion.enterTransition(reduceMotion, fromBottom = false),
                            exit = StateMotion.exitTransition(reduceMotion, toBottom = false),
                        ) {
                            // Figma "QR bukan kode Shoo" (1681:4972): the line, then a way to type the code instead.
                            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                ConnectProblemLabel(
                                    text = t("This QR isn't a Shoo invite code. Scan the QR from your Guardian's Shoo app."),
                                    modifier = Modifier.semantics { testTag = "connect.scanRefused" },
                                )
                                ConnectInlineLink("Just enter the code", identifier = "connect.enterCodeInstead") {
                                    tab = ConnectTab.CODE
                                    focusRequests += 1
                                }
                            }
                        }
                        if (!scanRefused) ProblemLabel(problem)
                    }
                    ConnectTab.CODE -> Column(
                        Modifier
                            .fillMaxWidth()
                            .padding(top = 39.dp),
                        // Figma "Frame 91": 32 between the label and the boxes.
                        verticalArrangement = Arrangement.spacedBy(32.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(t("Enter the invite code"), style = onboardingBodyStyle(), modifier = Modifier.fillMaxWidth())
                        Column(
                            Modifier
                                .fillMaxWidth()
                                .bringIntoViewRequester(codeField),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            CodeField(
                                code = model.code,
                                onCodeChange = { model.code = it },
                                isWrong = problem == ConnectModel.Problem.INVALID,
                                focusRequests = focusRequests,
                                onFocusChange = { codeFocused = it },
                                modifier = Modifier.shakeOnProblem(problemsShown, isEnabled = !reduceMotion),
                            )
                            ProblemLabel(problem)
                            // Figma "Kode salah" (1681:4712): "Ketik ulang kode" under the line empties the boxes.
                            // Fades in; editing the code clears it at once (no fade-out to wait for).
                            AnimatedVisibility(
                                visible = problem == ConnectModel.Problem.INVALID,
                                enter = StateMotion.enterTransition(reduceMotion, fromBottom = false),
                                exit = ExitTransition.None,
                            ) {
                                ConnectInlineLink(
                                    "Retype code",
                                    identifier = "connect.retype",
                                    modifier = Modifier.padding(top = 12.dp),
                                ) {
                                    model.retype()
                                    focusRequests += 1
                                }
                            }
                        }
                    }
                }
            }

            // fase 18 K17: said before joining, since copies are only made while connected. Part of the page, not
            // the pinned footer (QA 1110 #8, #16). While typing it would only peek out beside the button.
            CopyNote(
                Modifier
                    .padding(top = 24.dp)
                    .alpha(if (codeFocused) 0f else 1f),
                hidden = codeFocused,
            )
        },
        footer = {
            AnimatedVisibility(
                visible = tab == ConnectTab.CODE,
                enter = fadeIn(shooSnappy(0.3)),
                exit = fadeOut(shooSnappy(0.3)),
            ) {
                val kind = when {
                    problem == ConnectModel.Problem.FULL && onBack != null -> 1
                    model.retryAt != null -> 2
                    else -> 0
                }
                AnimatedContent(
                    targetState = kind,
                    transitionSpec = { fadeIn(shooEaseInOut(0.2)) togetherWith fadeOut(shooEaseInOut(0.2)) },
                    label = "connectFooter",
                ) { shownKind ->
                    when (shownKind) {
                        // Figma "Keluarga penuh" (1681:4750): nothing to retry here until the guardian makes room.
                        1 -> OnboardingCapsuleButton(
                            title = "Back",
                            onClick = { if (!model.isBusy) onBack?.invoke() },
                            identifier = "connect.back",
                        )
                        2 -> WaitButton(model)
                        else -> {
                            val joining = model.state == ConnectModel.State.Joining
                            OnboardingCapsuleButton(
                                onClick = {
                                    // QA 1110 #8: the answer shows on the whole page, not squeezed above the keyboard.
                                    focusManager.clearFocus()
                                    keyboard?.hide()
                                    scope.launch { model.join() }
                                },
                                // Stays dark while joining so the spinner is visible; taps are ignored by `join()` then.
                                enabled = model.canJoin || joining,
                                identifier = "connect.join",
                            ) {
                                Box(contentAlignment = Alignment.Center) {
                                    Text(t("Connect"), modifier = Modifier.alpha(if (joining) 0f else 1f))
                                    if (joining) {
                                        CircularProgressIndicator(
                                            Modifier.size(20.dp),
                                            color = OnboardingTheme.onButton,
                                            strokeWidth = 2.dp,
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if (onSkip != null) {
                // A join already sent finishes on the server: wait for its answer (PR-02).
                OnboardingLinkButton(title = "Not now", onClick = onSkip, enabled = !model.isBusy, identifier = "connect.skip")
            }
        },
    )
}

/** "Shoo keeps a copy of pages … for 14 days": an info circle and the line, left-aligned. */
@Composable
private fun CopyNote(modifier: Modifier, hidden: Boolean) {
    val text = t("Shoo keeps a copy of pages it blocks or warns you about for 14 days, so your Guardian can see the evidence.")
    val color = OnboardingTheme.secondaryInk
    Row(
        modifier
            .fillMaxWidth()
            .clearAndSetSemantics {
                if (!hidden) contentDescription = text
                testTag = "connect.copyNote"
            },
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(sfSymbol("info.circle"), contentDescription = null, tint = color, modifier = Modifier.padding(top = 1.dp).size((13f * 1.4f * textScale()).dp))
        Text(text, style = onboardingFont(13f, rounded = true), color = color, modifier = Modifier.weight(1f))
    }
}

/** The problem line under the code or the scanner; fades in, goes at once. */
@Composable
private fun ProblemLabel(problem: ConnectModel.Problem?) {
    val reduceMotion = LocalReduceMotion.current
    val last = remember { arrayOf(problem) }
    if (problem != null) last[0] = problem
    AnimatedVisibility(
        visible = problem != null,
        enter = if (reduceMotion) fadeIn(shooEaseOut(0.2)) else fadeIn(shooSpring(0.32, 0.18)),
        exit = ExitTransition.None,
    ) {
        val shown = problem ?: last[0] ?: return@AnimatedVisibility
        ConnectProblemLabel(
            text = t(shown.message),
            systemImage = if (shown.isWait) "clock" else if (shown == ConnectModel.Problem.EXPIRED) "clock.arrow.circlepath" else "exclamationmark.triangle.fill",
            tint = if (shown.isWait) ConnectProblemColors.waitInk else ConnectProblemColors.errorInk,
            modifier = Modifier.semantics { testTag = "connect.error" },
        )
    }
}

/** Figma "Pesan verdict" under the code (1681:4816): red #C81414 for a refusal, orange #C2610C for a wait. */
private object ConnectProblemColors {
    val errorInk = hex(0xC81414)
    val waitInk = hex(0xC2610C)
}

/** The symbol and SF Pro Rounded 13 / 18, 6 apart, left-aligned. `text`: already localized. */
@Composable
private fun ConnectProblemLabel(
    text: String,
    modifier: Modifier = Modifier,
    systemImage: String = "exclamationmark.triangle.fill",
    tint: Color = ConnectProblemColors.errorInk,
) {
    Row(
        modifier
            .fillMaxWidth()
            .clearAndSetSemantics { contentDescription = text },
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(Modifier.width(16.dp).height(18.dp), contentAlignment = Alignment.Center) {
            // `.font(.system(size: 13, weight: .semibold))`: a fixed size.
            Icon(sfSymbol(systemImage), contentDescription = null, tint = tint, modifier = Modifier.size(15.dp))
        }
        Text(
            text,
            style = onboardingFont(13f, rounded = true, tracking = -0.08f, lineHeight = 18f),
            color = tint,
            modifier = Modifier.weight(1f),
        )
    }
}

/** "Ketik ulang kode", "Masukkan kode saja": Figma #136CB7, SF Pro Semibold 17, left-aligned, 44 pt to tap. */
@Composable
private fun ConnectInlineLink(
    title: String,
    identifier: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val reduceMotion = LocalReduceMotion.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val alpha by animateFloatAsState(if (pressed) 0.6f else 1f, shooEaseOut(0.12), label = "linkAlpha")
    val scale by animateFloatAsState(if (pressed && !reduceMotion) 0.97f else 1f, shooEaseOut(0.12), label = "linkScale")
    val trim = with(LocalDensity.current) { 10.dp.roundToPx() }
    Box(
        modifier
            .fillMaxWidth()
            // 44 pt to tap, 10 pt of it above and below the row's own height (`.padding(.vertical, -10)`).
            .layout { measurable, constraints ->
                val placeable = measurable.measure(constraints.copy(minHeight = 0, maxHeight = androidx.compose.ui.unit.Constraints.Infinity))
                layout(placeable.width, (placeable.height - trim * 2).coerceAtLeast(0)) { placeable.place(0, -trim) }
            },
        contentAlignment = Alignment.CenterStart,
    ) {
        Box(
            Modifier
                .heightIn(min = 44.dp)
                .clickable(interactionSource = interaction, indication = null, role = Role.Button, onClick = onClick)
                .semantics { testTag = identifier }
                .graphicsLayer {
                    this.alpha = alpha
                    scaleX = scale
                    scaleY = scale
                    transformOrigin = TransformOrigin(0f, 0.5f)
                },
            contentAlignment = Alignment.CenterStart,
        ) {
            Text(t(title), style = onboardingFont(17f, FontWeight.SemiBold, family = FigmaFont.Family.SF_PRO), color = hex(0x136CB7))
        }
    }
}

/**
 * Figma "Terlalu banyak percobaan / pendaftaran" (1681:4787, 4824): the grey button counts down ("Coba lagi dalam
 * 04:59", or minutes when it's long) and turns back into Connect when the wait ends.
 */
@Composable
private fun WaitButton(model: ConnectModel) {
    val reduceMotion = LocalReduceMotion.current
    val language = LocalAppLanguage.current
    val view = LocalView.current
    var now by remember { mutableStateOf(Instant.now()) }
    // `TimelineView(.periodic(from: .now, by: 1))`.
    LaunchedEffect(Unit) {
        while (true) {
            now = Instant.now()
            delay(1000)
        }
    }
    val retryAt = model.retryAt
    LaunchedEffect(retryAt) {
        if (retryAt == null) return@LaunchedEffect
        delay(Duration.between(Instant.now(), retryAt).toMillis().coerceAtLeast(0))
        model.waitEnded()
        // A light tap when Connect comes back.
        if (model.retryAt == null) view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
    }
    val seconds = model.secondsToWait(now) ?: 0
    OnboardingCapsuleButton(onClick = {}, enabled = false, identifier = "connect.wait") {
        val style = LocalTextStyle.current.copy(fontFeatureSettings = "tnum")
        AnimatedContent(
            targetState = seconds,
            transitionSpec = {
                if (reduceMotion) {
                    fadeIn(shooEaseOut(0.2)) togetherWith fadeOut(shooEaseOut(0.2))
                } else {
                    // `.numericText(countsDown: true)`: the new value comes down from above.
                    (slideInVertically(shooSnappy(0.3)) { -it / 2 } + fadeIn(shooSnappy(0.3))) togetherWith
                        (slideOutVertically(shooSnappy(0.3)) { it / 2 } + fadeOut(shooSnappy(0.3)))
                }
            },
            label = "wait",
        ) { value ->
            Text(ConnectModel.waitLabel(value, language), style = style)
        }
    }
}

/** A wrong or expired code: three quick swings (±6 pt, 0.3 s) of the code boxes. Offset only, never layout. Off with
 * Reduce Motion: the error still fades in and the haptic still taps. */
private fun Modifier.shakeOnProblem(trigger: Int, isEnabled: Boolean): Modifier = composed {
    val offset = remember { Animatable(0f) }
    LaunchedEffect(trigger) {
        if (!isEnabled || trigger == 0) return@LaunchedEffect
        offset.snapTo(0f)
        offset.animateTo(6f, tween(50, easing = LinearEasing))
        offset.animateTo(-6f, tween(100, easing = LinearEasing))
        offset.animateTo(6f, tween(100, easing = LinearEasing))
        offset.animateTo(0f, tween(50, easing = LinearEasing))
    }
    graphicsLayer { translationX = offset.value * density }
}

/** "Kode | Pindai QR": capsule track with a white thumb that slides (Figma "Segmented Control"). */
@Composable
private fun ConnectTabs(tab: ConnectTab, onTabChange: (ConnectTab) -> Unit, modifier: Modifier = Modifier) {
    val tabs = listOf(ConnectTab.CODE to "Code", ConnectTab.SCAN to "Scan QR")
    val ids = mapOf(ConnectTab.CODE to "connect.tab.code", ConnectTab.SCAN to "connect.tab.scan")
    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .background(hex(0x767680, 0.12f), CapsuleShape)
            .padding(2.dp)
            .semantics { testTag = "connect.tabs" },
    ) {
        val gap = 4.dp
        val segment = (maxWidth - gap) / 2
        val index = tabs.indexOfFirst { it.first == tab }
        val thumbX by animateDpAsState(if (index == 0) 0.dp else segment + gap, shooSnappy(0.3), label = "connectThumb")
        val card = OnboardingTheme.card
        Box(Modifier.matchParentSize()) {
            Box(
                Modifier
                    .offset(x = thumbX)
                    .width(segment)
                    .fillMaxHeight()
                    // Figma: #000 6 %, y 2, blur 20.
                    .shooShadow(Color.Black.copy(alpha = 0.06f), radius = 10.dp, y = 2.dp, shape = CapsuleShape)
                    .background(card, CapsuleShape),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
            tabs.forEach { (value, title) ->
                val isSelected = value == tab
                Box(
                    Modifier
                        .width(segment)
                        .heightIn(min = 46.dp)
                        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onTabChange(value) }
                        .semantics {
                            selected = isSelected
                            testTag = ids.getValue(value)
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        t(title),
                        style = onboardingFont(
                            13.33f,
                            if (isSelected) FontWeight.SemiBold else FontWeight.Medium,
                            tracking = -0.08f,
                            family = FigmaFont.Family.SF_PRO,
                        ),
                        color = OnboardingTheme.ink,
                    )
                }
            }
        }
    }
}

/** Grey viewfinder with white corner marks around the camera (Figma "Frame 90" + "Group 1486"). */
@Composable
private fun ScannerFrame(content: @Composable () -> Unit) {
    // Figma's frame is 354 × 433, drawn before the 14-day note sat under it; 43 pt shorter it ends above the footer's
    // fade at the default text size (U-09).
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .heightIn(max = SCANNER_HEIGHT)
                .aspectRatio(354f / SCANNER_HEIGHT.value)
                .clip(RoundedCornerShape(4.dp))
                .background(Color(red = 0x77 / 255f, green = 0x75 / 255f, blue = 0x75 / 255f, alpha = 0.25f)),
        ) {
            Box(Modifier.matchParentSize()) { content() }
            Canvas(
                Modifier
                    .matchParentSize()
                    .padding(horizontal = 30.dp, vertical = 50.dp)
                    .clearAndSetSemantics { },
            ) {
                val length = 18.dp.toPx()
                val stroke = Stroke(width = 4.dp.toPx(), cap = StrokeCap.Square)
                val corners = listOf(
                    Triple(Offset(0f, 0f), length, length),
                    Triple(Offset(size.width, 0f), -length, length),
                    Triple(Offset(0f, size.height), length, -length),
                    Triple(Offset(size.width, size.height), -length, -length),
                )
                for ((corner, dx, dy) in corners) {
                    val path = androidx.compose.ui.graphics.Path().apply {
                        moveTo(corner.x, corner.y + dy)
                        lineTo(corner.x, corner.y)
                        lineTo(corner.x + dx, corner.y)
                    }
                    drawPath(path, Color.White, style = stroke)
                }
            }
        }
    }
}

private val SCANNER_HEIGHT: Dp = 390.dp

/** Six digit boxes over one number-pad field: one TalkBack element, paste still works. */
@Composable
private fun CodeField(
    code: String,
    onCodeChange: (String) -> Unit,
    /** Figma "Kode salah": every box gets the red ring. */
    isWrong: Boolean,
    /** Bumped from outside ("Ketik ulang kode", "Masukkan kode saja") to focus the field. */
    focusRequests: Int,
    onFocusChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val reduceMotion = LocalReduceMotion.current
    val density = LocalDensity.current
    val keyboard = LocalSoftwareKeyboardController.current
    val focusRequester = remember { FocusRequester() }
    var focused by remember { mutableStateOf(false) }
    val currentCode by rememberUpdatedState(code)
    val scale = textScale()
    // Grows with the text size; the boxes share the row, so six always fit a small phone.
    val digitSize = min(26f * scale, 34f)
    // Figma "row": 72 pt tall.
    val boxHeight = min(72f * scale, 96f).dp
    val label = t("6-digit code")
    val ink = OnboardingTheme.ink
    val card = OnboardingTheme.card
    val shape = RoundedCornerShape(16.dp)
    val digitStyle = TextStyle(
        // Figma uses Geist SemiBold 26, which the app doesn't bundle; the display cut is closest.
        fontFamily = FigmaFont.family(FontWeight.SemiBold, FigmaFont.displayOpticalSize),
        fontWeight = FontWeight.SemiBold,
        fontSize = with(density) { digitSize.dp.toSp() },
        color = ink,
    )

    LaunchedEffect(focusRequests) {
        if (focusRequests == 0) return@LaunchedEffect
        focusRequester.requestFocus()
        keyboard?.show()
    }
    // After the sheet / page has settled: focus set mid-animation is often ignored.
    LaunchedEffect(Unit) {
        delay(350)
        if (currentCode.isEmpty()) {
            try {
                focusRequester.requestFocus()
                keyboard?.show()
            } catch (_: IllegalStateException) {
            }
        }
    }

    Box(
        modifier
            .fillMaxWidth()
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                focusRequester.requestFocus()
                keyboard?.show()
            },
    ) {
        // No placeholder: it would show through the empty boxes. TalkBack gets the label.
        BasicTextField(
            value = TextFieldValue(code, TextRange(code.length)),
            onValueChange = { onCodeChange(it.text) },
            modifier = Modifier
                .matchParentSize()
                .focusRequester(focusRequester)
                .onFocusChanged {
                    if (focused != it.isFocused) {
                        focused = it.isFocused
                        onFocusChange(it.isFocused)
                    }
                }
                .semantics {
                    contentDescription = label
                    testTag = "connect.code"
                },
            textStyle = TextStyle(color = Color.Transparent),
            cursorBrush = SolidColor(Color.Transparent),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            singleLine = true,
        )
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 6.dp)
                .clearAndSetSemantics { },
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            val digits = code.toList()
            for (index in 0 until ConnectModel.codeLength) {
                val isActive = focused && index == min(digits.size, ConnectModel.codeLength - 1)
                val stroke by animateColorAsState(
                    if (isWrong) ConnectProblemColors.errorInk else ink.copy(alpha = if (isActive) 1f else 0.1f),
                    shooEaseOut(0.2),
                    label = "codeBox",
                )
                Box(
                    Modifier
                        .weight(1f)
                        .height(boxHeight)
                        .background(card, shape)
                        .border(1.dp, stroke, shape),
                    contentAlignment = Alignment.Center,
                ) {
                    if (index < digits.size) {
                        Text(digits[index].toString(), style = digitStyle)
                    } else if (isActive) {
                        Caret(reduceMotion)
                    }
                }
            }
        }
    }
}

@Composable
private fun Caret(reduceMotion: Boolean) {
    var visible by remember { mutableStateOf(true) }
    LaunchedEffect(reduceMotion) {
        if (reduceMotion) return@LaunchedEffect
        while (true) {
            delay(530)
            visible = !visible
        }
    }
    Box(
        Modifier
            .size(width = 2.dp, height = 26.dp)
            .alpha(if (visible) 1f else 0f)
            .background(OnboardingTheme.ink, RoundedCornerShape(1.dp)),
    )
}

/**
 * PR-02: who looks after this phone now (Figma "Berhasil Terhubung", 929:8067). `onContinue` comes last so it can be a
 * trailing lambda.
 */
@Composable
fun ProtectedByView(guardian: GuardianInfo, modifier: Modifier = Modifier, onContinue: () -> Unit) {
    val env = LocalAppEnvironment.current
    var ownAvatarId by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        try {
            ownAvatarId = env.repository.me().avatarId
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            Log.ui.error("Own avatar for PR-02 failed", error)
        }
    }
    OnboardingSuccessPage(
        title = t("Connected to %@!", guardian.name),
        message = t("You can now enjoy digital protection with your Guardian's support."),
        idPrefix = "protectedBy",
        onContinue = onContinue,
        modifier = modifier,
        background = R.drawable.connected_background,
    ) {
        ConnectedOrbitIllustration(
            guardian = guardian,
            ownAvatarId = ownAvatarId,
            // Figma: the illustration at y 46, the headline at 402 (`.padding(.top, -16).padding(.bottom, 17)`).
            modifier = Modifier
                .layout { measurable, constraints ->
                    val placeable = measurable.measure(constraints)
                    val shift = 16.dp.roundToPx()
                    layout(placeable.width, (placeable.height - shift).coerceAtLeast(0)) { placeable.place(0, -shift) }
                }
                .padding(bottom = 17.dp),
        )
    }
}

// MARK: Feedback

/** `.sensoryFeedback(.success)`. */
private fun confirmHaptic(view: View) {
    view.performHapticFeedback(
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.KEYBOARD_TAP,
    )
}

/** `.sensoryFeedback(.error)`. */
private fun errorHaptic(view: View) {
    view.performHapticFeedback(
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS,
    )
}

/** `AccessibilityNotification.Announcement(…).post()`. */
@Suppress("DEPRECATION")
private fun announce(view: View, text: String) {
    view.announceForAccessibility(text)
}

