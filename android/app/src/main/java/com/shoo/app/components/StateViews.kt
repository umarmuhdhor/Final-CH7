package com.shoo.app.components

import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.shoo.app.features.onboarding.onboardingFont
import com.shoo.app.features.shield.HomeSectionTitle
import com.shoo.app.support.t
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// Error, empty and loading pieces shared by the state frames of the Figma board "alief state" (section 1685:5288).
// Motion stays short (≤ 0.35 s) and turns into a plain fade with "Kurangi gerakan" / Reduce Motion.

// MARK: - Motion

object StateMotion {
    /** A state card or banner arriving. */
    fun enter(reduceMotion: Boolean): AnimationSpec<Float> =
        if (reduceMotion) shooEaseOut<Float>(0.2) else shooSpring<Float>(0.32, 0.18)

    /** Insertion for a card or banner: a short rise with the fade; only the fade with Reduce Motion. */
    fun enterTransition(reduceMotion: Boolean, fromBottom: Boolean = true): EnterTransition =
        if (reduceMotion) {
            fadeIn(shooEaseOut(0.2))
        } else {
            fadeIn(shooSpring(0.32, 0.18)) +
                slideInVertically(shooSpring(0.32, 0.18)) { if (fromBottom) it else -it } +
                scaleIn(shooSpring(0.32, 0.18), initialScale = 0.98f)
        }

    /** Removal: the same, reversed. */
    fun exitTransition(reduceMotion: Boolean, toBottom: Boolean = true): ExitTransition =
        if (reduceMotion) {
            fadeOut(shooEaseOut(0.2))
        } else {
            fadeOut(shooSpring(0.32, 0.18)) +
                slideOutVertically(shooSpring(0.32, 0.18)) { if (toBottom) it else -it } +
                scaleOut(shooSpring(0.32, 0.18), targetScale = 0.98f)
        }
}

/**
 * Rises 10 pt and fades in once, when it first appears. Reliable where a transition on a loader → content swap can
 * hard-cut on heavy screens (motion recipe 2026-11-12). Swift `.stateEntrance(delay:)`.
 */
fun Modifier.stateEntrance(delay: Double = 0.0): Modifier = composed {
    val reduceMotion = LocalReduceMotion.current
    val progress = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        swiftDelay(delay)
        progress.animateTo(1f, StateMotion.enter(reduceMotion))
    }
    val rise = with(LocalDensity.current) { 10.dp.toPx() }
    graphicsLayer {
        val p = progress.value
        alpha = p.coerceIn(0f, 1f)
        translationY = if (reduceMotion) 0f else (1f - p) * rise
    }
}

// MARK: - Press

/**
 * `PressScaleButtonStyle`: a light press, 96 % and back, for text actions inside cards. Pass the same
 * `interactionSource` to the `clickable`. Reduce Motion: it only dims.
 */
fun Modifier.pressScale(
    interactionSource: MutableInteractionSource,
    scale: Float = 0.96f,
    pressedAlpha: Float = 0.7f,
): Modifier = composed {
    val reduceMotion = LocalReduceMotion.current
    val pressed by interactionSource.collectIsPressedAsState()
    val animatedScale by animateFloatAsState(if (pressed && !reduceMotion) scale else 1f, shooEaseOut(0.12), label = "pressScale")
    val animatedAlpha by animateFloatAsState(if (pressed) pressedAlpha else 1f, shooEaseOut(0.12), label = "pressAlpha")
    graphicsLayer {
        scaleX = animatedScale
        scaleY = animatedScale
        alpha = animatedAlpha
    }
}

// MARK: - Symbol effects

/**
 * One-shot symbol effects keyed by `trigger` (`.symbolEffect(.bounce / .wiggle, options: .nonRepeating, value:)`).
 * iOS: the system effects are approximated with scale (bounce) and rotation (wiggle).
 */
private fun Modifier.symbolEffect(trigger: Int, wiggle: Boolean, enabled: Boolean): Modifier = composed {
    val scale = remember { Animatable(1f) }
    val rotation = remember { Animatable(0f) }
    LaunchedEffect(trigger, enabled) {
        if (!enabled || trigger == 0) return@LaunchedEffect
        if (wiggle) {
            for (angle in floatArrayOf(-12f, 10f, -8f, 6f, 0f)) rotation.animateTo(angle, shooEaseInOut(0.08))
        } else {
            scale.animateTo(1.18f, shooEaseOut(0.12))
            scale.animateTo(1f, shooSpring(0.3, 0.4))
        }
    }
    graphicsLayer {
        scaleX = scale.value
        scaleY = scale.value
        rotationZ = rotation.value
    }
}

// MARK: - Notice card

/** `StateNoticeCard.Tone`. */
enum class StateNoticeTone(val symbol: String) {
    /** "Gagal memuat", "Gagal menyimpan": a circular arrow with a "!". */
    ERROR("exclamationmark.arrow.circlepath"),
    /** "Belum bisa ditandai": an "i". */
    INFO("info.circle"),
}

object StateNoticeColors {
    val ink = hex(0x151617)
    val line = hex(0x6A717E)
    val actionInk = hex(0x136CB7)
    val red = hex(0xC81414)
}

/**
 * Figma "Pesan verdict" (1665:3122 "Gagal memuat", 1665:3183 "Gagal menyimpan", 1665:3387 "Belum bisa ditandai"):
 * white 90 % with a #C81414 28 % ring, a 40 pt tile (#B73C13 12 %, 8 pt corners) with the symbol in #BB1616 70 %, the
 * title (SF Pro Rounded Semibold 17) over the line (13, #6A717E), the action in #136CB7 on the right. The symbol
 * wiggles (error) or bounces (info) once when the card arrives; the action shows a spinner while it runs.
 *
 * `title`, `actionTitle`: catalog keys. `message`: already localized text.
 */
@Composable
fun StateNoticeCard(
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    tone: StateNoticeTone = StateNoticeTone.ERROR,
    actionTitle: String? = null,
    cornerRadius: Dp = 12.dp,
    action: (suspend () -> Unit)? = null,
) {
    val reduceMotion = LocalReduceMotion.current
    var isRunning by remember { mutableStateOf(false) }
    // Bumped on appear and on every finished retry: the symbol's one-shot effect.
    var nudge by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { nudge += 1 }
    val scope = rememberCoroutineScope()
    val shape = RoundedCornerShape(cornerRadius)
    val titleText = t(title)

    Row(
        modifier
            .fillMaxWidth()
            .background(Color.White.copy(alpha = 0.9f), shape)
            .border(1.dp, StateNoticeColors.red.copy(alpha = 0.28f), shape)
            .padding(start = 12.dp, end = 14.dp, top = 10.dp, bottom = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(40.dp)
                .background(hex(0xB73C13, 0.12f), RoundedCornerShape(8.dp))
                .clearAndSetSemantics { },
            contentAlignment = Alignment.Center,
        ) {
            SfSymbol(
                tone.symbol,
                pointSize = 21.67f,
                tint = hex(0xBB1616, 0.7f),
                modifier = Modifier.symbolEffect(nudge, wiggle = tone == StateNoticeTone.ERROR, enabled = !reduceMotion),
            )
        }
        Column(
            Modifier
                .weight(1f)
                .clearAndSetSemantics { contentDescription = "$titleText. $message" },
        ) {
            Text(
                titleText,
                style = onboardingFont(17f, FontWeight.SemiBold, rounded = true, tracking = -0.43f, lineHeight = 22f),
                color = StateNoticeColors.ink,
            )
            Text(
                message,
                style = onboardingFont(13f, rounded = true, tracking = -0.08f, lineHeight = 18f),
                color = StateNoticeColors.line,
            )
        }
        if (actionTitle != null && action != null) {
            val interaction = remember { MutableInteractionSource() }
            val label = t(actionTitle)
            Box(
                Modifier
                    .heightIn(min = 44.dp)
                    .pressScale(interaction)
                    .clickable(
                        interactionSource = interaction,
                        indication = null,
                        enabled = !isRunning,
                        role = Role.Button,
                    ) {
                        if (isRunning) return@clickable
                        scope.launch {
                            isRunning = true
                            try {
                                action()
                            } finally {
                                isRunning = false
                                nudge += 1
                            }
                        }
                    }
                    .semantics { testTag = "state.notice.action" },
                contentAlignment = Alignment.Center,
            ) {
                val textAlpha by animateFloatAsState(if (isRunning) 0f else 1f, shooEaseOut(0.15), label = "noticeAction")
                Text(
                    label,
                    style = onboardingFont(16.5f, FontWeight.SemiBold),
                    color = StateNoticeColors.actionInk,
                    modifier = Modifier.graphicsLayer { alpha = textAlpha },
                )
                // `ProgressView().controlSize(.small)`, faded in and out under the same `.easeOut(0.15)`.
                androidx.compose.animation.AnimatedVisibility(isRunning, enter = fadeIn(shooEaseOut(0.15)), exit = fadeOut(shooEaseOut(0.15))) {
                    CircularProgressIndicator(
                        color = StateNoticeColors.actionInk,
                        strokeWidth = 2.dp,
                        modifier = Modifier.size(16.dp),
                    )
                }
            }
        }
    }
}

// MARK: - Centred message

/**
 * A centred state: an 80 pt tile with the symbol, the title (SF Pro Semibold 20) and the line (SF Pro Rounded 17,
 * #6A717E). Figma "Kirim Undangan · Gagal mengambil kode / Keluarga penuh" (tile = the tint at 12 %) and "Detail Orang
 * Dilindungi · Sudah tidak terhubung / Gagal memuat" (white tile). Settles in with a spring; the symbol bounces once.
 *
 * `title`: catalog key. `message`: already localized. `symbolSize`: 34 for the error symbol, 27 for the people.
 * `tileFill`: null = the tint at 12 %.
 */
@Composable
fun StateMessage(
    systemImage: String,
    tint: Color,
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    symbolSize: Float = 34f,
    tileFill: Color? = null,
) {
    val reduceMotion = LocalReduceMotion.current
    val shown = remember { Animatable(0f) }
    var bounce by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        launch { shown.animateTo(1f, if (reduceMotion) shooEaseOut<Float>(0.2) else shooSpring<Float>(0.35, 0.3)) }
        bounce += 1
    }
    val titleText = t(title)
    Column(
        modifier
            .fillMaxWidth()
            .padding(top = 52.dp)
            .graphicsLayer { alpha = shown.value.coerceIn(0f, 1f) }
            .clearAndSetSemantics {
                contentDescription = "$titleText. $message"
                heading()
            },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .graphicsLayer {
                    val s = if (reduceMotion) 1f else 0.85f + 0.15f * shown.value
                    scaleX = s
                    scaleY = s
                }
                .size(80.dp)
                .background(tileFill ?: tint.copy(alpha = 0.12f), RoundedCornerShape(22.dp)),
            contentAlignment = Alignment.Center,
        ) {
            SfSymbol(
                systemImage,
                pointSize = symbolSize,
                tint = tint,
                modifier = Modifier.symbolEffect(bounce, wiggle = false, enabled = !reduceMotion),
            )
        }
        Text(
            titleText,
            style = onboardingFont(20f, FontWeight.SemiBold),
            color = hex(0x151617),
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 24.dp),
        )
        Text(
            message,
            style = onboardingFont(17f, rounded = true, lineHeight = 22f),
            color = hex(0x6A717E),
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 8.dp),
        )
    }
}

// MARK: - Skeleton

/** `Shimmer`: a soft highlight that sweeps across while something loads; still with Reduce Motion. */
fun Modifier.shimmering(active: Boolean = true): Modifier = composed {
    val reduceMotion = LocalReduceMotion.current
    if (!active || reduceMotion) return@composed this
    val transition = rememberInfiniteTransition(label = "shimmer")
    val phase by transition.animateFloat(
        initialValue = -1f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1300, easing = LinearEasing), RepeatMode.Restart),
        label = "shimmerPhase",
    )
    this
        // An offscreen layer so the sweep only lands on what the content drew (SwiftUI `.mask(content)`).
        .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
        .drawWithContent {
            drawContent()
            val bandWidth = size.width * 0.6f
            val x = phase * size.width * 1.6f
            drawRect(
                Brush.horizontalGradient(
                    listOf(Color.White.copy(alpha = 0f), Color.White.copy(alpha = 0.55f), Color.White.copy(alpha = 0f)),
                    startX = x, endX = x + bandWidth,
                ),
                topLeft = androidx.compose.ui.geometry.Offset(x, 0f),
                size = androidx.compose.ui.geometry.Size(bandWidth, size.height),
                blendMode = BlendMode.SrcAtop,
            )
        }
}

/**
 * Figma "Skeleton row" (1666:3717): #F3F6FA, 16 pt corners, 74 pt; a 44 pt disc, bars of 150 × 12 and 96 × 10, a
 * 62 × 24 chip on the right.
 */
@Composable
fun SkeletonRow(modifier: Modifier = Modifier) {
    Row(
        modifier
            .fillMaxWidth()
            .height(74.dp)
            .background(hex(0xF3F6FA), RoundedCornerShape(16.dp))
            .padding(horizontal = 16.dp)
            .clearAndSetSemantics { },
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(44.dp).background(hex(0xE2E7EE), CircleShape))
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.width(150.dp).height(12.dp).background(hex(0xE2E7EE), CapsuleShape))
            Box(Modifier.width(96.dp).height(10.dp).background(hex(0xEAEEF3), CapsuleShape))
        }
        Spacer(Modifier.weight(1f))
        Box(Modifier.width(62.dp).height(24.dp).background(hex(0xEAEEF3), CapsuleShape))
    }
}

/**
 * "Aktivitas Terakhir" with grey rows: what the list will hold once it loads.
 * `animating`: sweeps while the next try runs; still when the load has failed.
 */
@Composable
fun SkeletonActivity(modifier: Modifier = Modifier, rows: Int = 3, animating: Boolean = false) {
    Column(modifier.clearAndSetSemantics { }, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        HomeSectionTitle("Recent activity")
        Column(Modifier.shimmering(animating), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            repeat(rows) { SkeletonRow() }
        }
    }
}

/** Swift `Task.sleep` helper for previews and the gallery. */
internal suspend fun sleepSeconds(seconds: Double) = delay((seconds * 1000).toLong())
