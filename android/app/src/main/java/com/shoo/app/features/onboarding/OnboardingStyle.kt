package com.shoo.app.features.onboarding

import android.os.Build
import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.shoo.app.R
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.FigmaFont
import com.shoo.app.components.LightOnly
import com.shoo.app.components.LocalReduceGlass
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.SymbolScale
import com.shoo.app.components.dynamicColor
import com.shoo.app.components.figmaTextStyle
import com.shoo.app.components.hex
import com.shoo.app.components.shooEaseInOut
import com.shoo.app.components.shooEaseOut
import com.shoo.app.components.shooShadow
import com.shoo.app.components.shooSmooth
import com.shoo.app.components.shooSpring
import com.shoo.app.components.swiftDelay
import com.shoo.app.support.t
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Colours and type from the onboarding Figma ("ONBOARDING" section, node 141:5987).
 * Light values are Figma's; dark ones are ours (PF-01 Tema), the design has light only.
 */
object OnboardingTheme {
    val background: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xF5F8FC, 0x0E1116)
    /** Cards and fields. */
    val card: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xFFFFFF, 0x1B1F26)
    val ink: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x151617, 0xF2F4F8, 0x000000, 0xFFFFFF)
    val secondaryInk: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x67696C, 0xA3A9B3, 0x45474A, 0xCDD1D8)
    /** Figma's small notes under a field ("*Nama harus terdiri dari maksimal 20 karakter"). */
    val noteInk: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x191C25, 0xF2F4F8, 0x000000, 0xFFFFFF)
    /** Figma's numbered steps ("Tekan tombol di bawah…"). */
    val stepInk: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x191D2F, 0xF2F4F8, 0x000000, 0xFFFFFF)
    /** Figma "Body" under every onboarding headline. */
    val bodyInk: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x6A717E, 0xA3A9B3, 0x4A505B, 0xCDD1D8)
    val cardStroke: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xD8DFE2, 0x343B46, 0x9AA1AC, 0x6B7380)
    val selectedStroke: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x0EA1DE, 0x3DB8EE)
    val selectedStrokeProtected: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x11D0DA, 0x3FDDE5)
    val disabledFill: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xDBE2E7, 0x2A303A)
    val placeholder: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x939393, 0x7C828C)
    val error: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xC81414, 0xFF6B6B)
    val link: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x0367B6, 0x5EAAF0)
    /** Text on the blue capsule. */
    val onButton: Color = Color.White
    /** Figma style "Gradient/Dark Button"; the design has no dark variant. */
    val buttonGradient: Brush = Brush.verticalGradient(listOf(hex(0x446EB4), hex(0x214889)))
    /** Figma frame on the chosen ON-02 avatar. */
    val avatarSelectedStroke: Color = hex(0x7DE49C)
    /** #2CBF81 → #8EE9EC, top leading to bottom trailing. */
    val avatarRing: Brush = Brush.linearGradient(
        listOf(hex(0x2CBF81), hex(0x8EE9EC)),
        start = Offset.Zero,
        end = Offset.Infinite,
    )
}

// MARK: Type

/** Figma point sizes that still follow the text size (persona: parents 45–65, PRD §3). */
@Composable
@ReadOnlyComposable
fun onboardingFont(
    size: Float,
    weight: FontWeight = FontWeight.Normal,
    rounded: Boolean = false,
    tracking: Float? = null,
    family: FigmaFont.Family = FigmaFont.Family.DISPLAY,
    lineHeight: Float? = null,
): TextStyle = figmaTextStyle(size, weight, rounded, tracking, lineHeight, family)

/** Headline 28 medium + Figma "Title 1/Regular" 120 % lines, centred (every onboarding title in Figma). Add `heading()`. */
@Composable
@ReadOnlyComposable
fun onboardingTitleStyle(): TextStyle =
    onboardingFont(28f, FontWeight.Medium, tracking = -0.56f, lineHeight = 33.6f)
        .copy(color = OnboardingTheme.ink, textAlign = TextAlign.Center)

/** Figma "Large Title/Regular" over an illustration: 34 semibold, 41 pt lines. Add `heading()`. */
@Composable
@ReadOnlyComposable
fun onboardingLargeTitleStyle(): TextStyle =
    onboardingFont(34f, FontWeight.SemiBold, tracking = -0.68f, lineHeight = 41f)
        .copy(color = OnboardingTheme.ink, textAlign = TextAlign.Center)

/** Figma "Body/Regular": 17 rounded, 22 pt lines, under a large title. */
@Composable
@ReadOnlyComposable
fun onboardingLargeBodyStyle(): TextStyle =
    onboardingFont(17f, rounded = true, tracking = -0.17f)
        .copy(color = OnboardingTheme.bodyInk, textAlign = TextAlign.Center)

/** `lineHeight`: Figma "Subhead/Regular", 140 % (23.8). */
@Composable
@ReadOnlyComposable
fun onboardingBodyStyle(lineHeight: Float = 23.8f): TextStyle =
    onboardingFont(17f, rounded = true, lineHeight = lineHeight)
        .copy(color = OnboardingTheme.bodyInk, textAlign = TextAlign.Center)

// MARK: Buttons

/**
 * `OnboardingCapsuleButtonStyle`: blue pill, 56 pt; grey when disabled ("Selanjutnya" in Figma).
 * `title` is a catalog key.
 */
@Composable
fun OnboardingCapsuleButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    identifier: String? = null,
) {
    OnboardingCapsuleButton(onClick = onClick, modifier = modifier, enabled = enabled, identifier = identifier) {
        Text(t(title), style = onboardingFont(17f, FontWeight.SemiBold).copy(textAlign = TextAlign.Center))
    }
}

/** `OnboardingCapsuleButtonStyle` around any label (the text style and colour are set for it). */
@Composable
fun OnboardingCapsuleButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    identifier: String? = null,
    content: @Composable RowScope.() -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.98f else 1f, shooEaseOut(0.15), label = "capsuleScale")
    // Figma disabled "Button": #DBE2E7 with #000 25 % text, the whole button at 75 %.
    val alpha = if (enabled) (if (pressed) 0.85f else 1f) else 0.75f
    val textColor = if (enabled) OnboardingTheme.onButton else OnboardingTheme.ink.copy(alpha = 0.25f)
    val disabledFill = OnboardingTheme.disabledFill
    Row(
        modifier = modifier
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
                this.alpha = alpha
            }
            // Figma "Button": #121112 20%, y 8, blur 18.
            .shooShadow(hex(0x121112, if (enabled) 0.2f else 0f), radius = 9.dp, y = 8.dp, shape = CapsuleShape)
            .then(
                if (enabled) {
                    Modifier.background(OnboardingTheme.buttonGradient, CapsuleShape)
                } else {
                    Modifier.background(disabledFill, CapsuleShape)
                },
            )
            // Figma "Button": inner white 20 %, y 1.
            .border(
                1.dp,
                Brush.verticalGradient(0f to Color.White.copy(alpha = if (enabled) 0.2f else 0f), 0.5f to Color.Transparent),
                CapsuleShape,
            )
            .clickable(interactionSource = interaction, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .then(if (identifier != null) Modifier.semantics { testTag = identifier } else Modifier)
            .padding(horizontal = 16.dp)
            .fillMaxWidth()
            .heightIn(min = 56.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CompositionLocalProvider(androidx.compose.material3.LocalContentColor provides textColor) {
            androidx.compose.material3.ProvideTextStyle(onboardingFont(17f, FontWeight.SemiBold).copy(color = textColor)) {
                content()
            }
        }
    }
}

/**
 * `OnboardingPressButtonStyle`: a plain button that gives under the finger like the pill (splash Next, the avatar
 * picker). Pass the `interactionSource` the `clickable` uses. Reduce Motion: it dims instead of shrinking.
 */
fun Modifier.onboardingPress(interactionSource: InteractionSource): Modifier = composed {
    val pressed by interactionSource.collectIsPressedAsState()
    val reduceMotion = LocalReduceMotion.current
    val scale by animateFloatAsState(if (pressed && !reduceMotion) 0.94f else 1f, shooEaseOut(0.15), label = "pressScale")
    val alpha by animateFloatAsState(if (pressed && reduceMotion) 0.8f else 1f, shooEaseOut(0.15), label = "pressAlpha")
    graphicsLayer {
        scaleX = scale
        scaleY = scale
        this.alpha = alpha
    }
}

/**
 * `OnboardingLinkButtonStyle`: text-only secondary action under the pill ("Lewati", "Nanti saja"; dark for
 * "Terkendala? Tonton Tutorial"). Figma's text links are SF Pro Text 15, -2 %, on a 20 pt row with a 44 pt hit area.
 * `title` is a catalog key; `color` defaults to `OnboardingTheme.link`.
 */
@Composable
fun OnboardingLinkButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    color: Color? = null,
    weight: FontWeight = FontWeight.Medium,
    family: FigmaFont.Family = FigmaFont.Family.TEXT,
    tracking: Float = -0.3f,
    identifier: String? = null,
    enabled: Boolean = true,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val ink = color ?: OnboardingTheme.link
    val extra = with(LocalDensity.current) { 12.dp.roundToPx() }
    Box(
        modifier = modifier
            .fillMaxWidth()
            // A 44 pt tall hit area that lays out as the text's own height (Figma's 20 pt row).
            .layout { measurable, constraints ->
                val placeable = measurable.measure(constraints.copy(maxHeight = androidx.compose.ui.unit.Constraints.Infinity))
                val height = (placeable.height - extra * 2).coerceAtLeast(0)
                layout(placeable.width, height) { placeable.place(0, -extra) }
            }
            .clickable(interactionSource = interaction, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .then(if (identifier != null) Modifier.semantics { testTag = identifier } else Modifier)
            .padding(vertical = 12.dp)
            .graphicsLayer { alpha = if (pressed) 0.6f else 1f },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            t(title),
            style = onboardingFont(15f, weight, tracking = tracking, family = family, lineHeight = 20f)
                .copy(color = ink, textAlign = TextAlign.Center),
        )
    }
}

// MARK: Back button and glass

/**
 * A page shown in a sheet has no status bar above it, so a back button pinned to the top sat on the sheet's rounded
 * corner (Connect from Profile, Turn on from Activity). Sheets provide `true`; the page then gets 16 pt of top room
 * (iOS `SheetTopClearance`, which measured the safe area instead).
 */
val LocalPresentedInSheet = compositionLocalOf { false }

/** `SheetTopClearance`: 16 pt of top room when the page is in a sheet. */
fun Modifier.sheetTopClearance(): Modifier = composed {
    if (LocalPresentedInSheet.current) padding(top = 16.dp) else this
}

/** Round 50 pt back button over the header gradient (Liquid Glass on iOS 26+). */
@Composable
fun OnboardingBackButton(action: () -> Unit, modifier: Modifier = Modifier, identifier: String = "onboarding.back") {
    val interaction = remember { MutableInteractionSource() }
    val label = t("Back")
    Box(
        modifier = modifier
            .size(50.dp)
            .glassCircle()
            .clickable(interactionSource = interaction, indication = null, role = Role.Button, onClick = action)
            .semantics {
                contentDescription = label
                testTag = identifier
            },
        contentAlignment = Alignment.Center,
    ) {
        // Figma sets the symbol as SF Pro Semibold 19 text ("􀄪"), which draws at the large symbol scale.
        SfSymbol("arrow.left", pointSize = 19f, tint = OnboardingTheme.ink, scale = SymbolScale.LARGE)
    }
}

/** `GlassCircle`: glass behind a round control; "Kurangi efek kaca" makes it a solid circle. */
private fun Modifier.glassCircle(): Modifier = composed {
    if (LocalReduceGlass.current) {
        background(OnboardingTheme.card, CircleShape)
    } else {
        // iOS: Liquid Glass / .ultraThinMaterial; Android can't blur what lies behind, so a frosted white.
        shooShadow(Color.Black.copy(alpha = 0.08f), radius = 12.dp, y = 4.dp, shape = CircleShape)
            .background(Color.White.copy(alpha = 0.82f), CircleShape)
            .border(0.5.dp, Color.White.copy(alpha = 0.5f), CircleShape)
    }
}

// MARK: Header

/** Blue gradient behind the title that fades into the page colour (Figma "Gradient-classic-2 lighter" + "box"). */
@Composable
fun OnboardingHeaderBackground(
    modifier: Modifier = Modifier,
    height: Dp = 252.dp,
    /** `R.drawable.onboarding_header_gradient_teal` on Figma "To be guardian". */
    image: Int = R.drawable.onboarding_header_gradient,
) {
    val page = OnboardingTheme.background
    Box(modifier = modifier.fillMaxWidth().height(height).clipToBounds()) {
        Image(
            painter = painterResource(image),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            alignment = Alignment.BottomCenter,
            modifier = Modifier.fillMaxSize(),
        )
        Box(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .height(height * 180f / 252f)
                .background(Brush.verticalGradient(listOf(page.copy(alpha = 0f), page))),
        )
    }
}

// MARK: Form page

/** The onboarding page's height between the system bars, keyboard left out (0 until measured), in dp. */
val LocalOnboardingPageHeight = compositionLocalOf { 0f }

/**
 * Name and mode screens: header gradient, back button, title, scrolling content, button pinned at the bottom.
 * `hero` is the 300 pt illustration above the title (invite, ON-04); it sits beside the back button.
 *
 * `title` / `message` are catalog keys. The Swift chained options are parameters: `headlineInset` (Figma "Frame 2"
 * side inset: 20 without a hero, 46 under one), `messageLineHeight`, `messageSpacing`, `tealHeader`, `largeHeadline`,
 * `footerEndsWithLink`. `scrollTarget`: the view to keep visible above the button (e.g. the focused field once the
 * keyboard is up; attach the same requester with `Modifier.bringIntoViewRequester`).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun OnboardingFormPage(
    title: String,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
    /** `null` where Figma has only the headline (ON-04, Safari Default). */
    message: String? = null,
    scrollTarget: BringIntoViewRequester? = null,
    headlineInset: Dp? = null,
    messageLineHeight: Float = 23.8f,
    messageSpacing: Dp? = null,
    tealHeader: Boolean = false,
    largeHeadline: Boolean = false,
    footerEndsWithLink: Boolean = false,
    hero: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
    footer: @Composable ColumnScope.() -> Unit,
) {
    LightOnly {
        val density = LocalDensity.current
        val statusTop = WindowInsets.statusBars.getTop(density)
        val navBottom = WindowInsets.navigationBars.getBottom(density)
        var footerHeightPx by remember { mutableFloatStateOf(with(density) { 92.dp.toPx() }) }
        // It only grows: the keyboard shrinks the window, and the footer must not move while the user types.
        var pageHeightPx by remember { mutableFloatStateOf(0f) }
        // U-06 (fase 28h): at large text the pinned footer can cover most of the page. Past half the page it
        // scrolls after the content instead.
        val footerScrolls = pageHeightPx > 0f && footerHeightPx > pageHeightPx / 2f
        // Figma "Footer": a lone button ends 68 pt above the screen bottom (34 over the home indicator inset);
        // a button + text link ends 40 pt above it.
        val footerBottom = if (footerEndsWithLink) 6.dp else 34.dp
        val inset = headlineInset ?: if (hero == null) 20.dp else 46.dp
        val headerImage = if (tealHeader) R.drawable.onboarding_header_gradient_teal else R.drawable.onboarding_header_gradient
        val background = OnboardingTheme.background
        val inSheet = LocalPresentedInSheet.current
        val scroll = rememberScrollState()

        LaunchedEffect(scrollTarget) {
            val target = scrollTarget ?: return@LaunchedEffect
            // Wait for the keyboard to finish moving the button up.
            delay(350)
            target.bringIntoView()
        }

        val footerStack: @Composable (Modifier) -> Unit = { extra ->
            // Figma "Footer": 16 between the button and the text link under it. Same padding pinned or scrolling,
            // so its measured height (and `footerScrolls`) does not change when it moves.
            Column(
                modifier = extra
                    .fillMaxWidth()
                    .onSizeChanged { footerHeightPx = it.height.toFloat() }
                    .navigationBarsPadding()
                    .padding(start = 24.dp, end = 24.dp, top = FOOTER_FADE, bottom = footerBottom),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                content = footer,
            )
        }

        CompositionLocalProvider(LocalOnboardingPageHeight provides with(density) { pageHeightPx.toDp().value }) {
            Box(
                modifier = modifier
                    .fillMaxSize()
                    .background(background)
                    .onSizeChanged { size ->
                        val between = size.height - statusTop - navBottom
                        if (between > pageHeightPx) pageHeightPx = between.toFloat()
                    },
            ) {
                // Figma "box": 252 pt, 345 where an illustration sits on it.
                OnboardingHeaderBackground(height = if (hero == null) 252.dp else 345.dp, image = headerImage)

                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .then(
                            // A scrolled headline fades out under the back button instead of running through it
                            // and the status bar. A hero sits beside the button by design, so it stays whole.
                            if (hero == null) {
                                Modifier
                                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                                    .drawWithContent {
                                        drawContent()
                                        val clearEnd = statusTop + 50.dp.toPx() + if (inSheet) 16.dp.toPx() else 0f
                                        drawRect(
                                            Brush.verticalGradient(
                                                0f to Color.Transparent,
                                                (clearEnd / size.height).coerceIn(0f, 1f) to Color.Transparent,
                                                ((clearEnd + 8.dp.toPx()) / size.height).coerceIn(0f, 1f) to Color.Black,
                                                1f to Color.Black,
                                            ),
                                            blendMode = BlendMode.DstIn,
                                        )
                                    }
                            } else {
                                Modifier
                            },
                        )
                        .verticalScroll(scroll)
                        .windowInsetsPadding(WindowInsets.statusBars)
                        .sheetTopClearance(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Box(contentAlignment = Alignment.TopCenter) {
                        // The hero sets its own Figma offsets (`OnboardingHeroImage(top:bottom:)`).
                        hero?.invoke()
                        // Room for the back button, pinned over the page.
                        Spacer(Modifier.height(50.dp))
                    }

                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = inset)
                            // Figma puts the headline at y 120 with the back button at y 40; the button stays under
                            // the status bar here, so only 8 pt are left to keep y 120.
                            .padding(top = if (hero == null) 8.dp else 0.dp),
                        verticalArrangement = Arrangement.spacedBy(messageSpacing ?: if (largeHeadline) 8.dp else 4.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        if (largeHeadline) {
                            Text(t(title), style = onboardingLargeTitleStyle(), modifier = Modifier.fillMaxWidth().semantics { heading() })
                            if (message != null) Text(t(message), style = onboardingLargeBodyStyle(), modifier = Modifier.fillMaxWidth())
                        } else {
                            Text(t(title), style = onboardingTitleStyle(), modifier = Modifier.fillMaxWidth().semantics { heading() })
                            if (message != null) {
                                Text(t(message), style = onboardingBodyStyle(messageLineHeight), modifier = Modifier.fillMaxWidth())
                            }
                        }
                    }

                    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp), content = content)

                    if (footerScrolls) {
                        footerStack(Modifier)
                    } else {
                        // The footer is an overlay; this keeps the last content above it.
                        Spacer(Modifier.height(16.dp + with(density) { footerHeightPx.toDp() }))
                    }
                }

                // Outside the scroll view: with the keyboard up the page scrolls and Back has to stay reachable.
                if (onBack != null) {
                    OnboardingBackButton(
                        action = onBack,
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .windowInsetsPadding(WindowInsets.statusBars)
                            .sheetTopClearance()
                            .padding(start = 24.dp),
                    )
                }

                if (!footerScrolls) {
                    // Only the 24 pt above the first row fades; behind the rows it is solid, so a tall footer
                    // never shows the steps scrolled under it through its own text (QA 2026-11-11 #7).
                    footerStack(
                        Modifier
                            .align(Alignment.BottomCenter)
                            .drawBehind {
                                val fade = FOOTER_FADE.toPx()
                                drawRect(
                                    Brush.verticalGradient(listOf(background.copy(alpha = 0f), background), startY = 0f, endY = fade),
                                    size = Size(size.width, fade),
                                )
                                drawRect(background, topLeft = Offset(0f, fade), size = Size(size.width, size.height - fade))
                            },
                    )
                }
            }
        }
    }
}

/** The footer's top padding, where the page fades out under it. */
private val FOOTER_FADE = 24.dp

/** 300 pt illustration at the top of an onboarding page (Figma "image 1"). */
@Composable
fun OnboardingHeroImage(
    image: Int,
    modifier: Modifier = Modifier,
    /** From the top safe area (62 on the 402 × 874 Figma iPhone) to the image. */
    top: Dp = 0.dp,
    /** From the image to the headline. */
    bottom: Dp = 0.dp,
) {
    val pageHeight = LocalOnboardingPageHeight.current
    // U-06 (fase 28h): 300 pt on Figma's page (874 − 62 − 34 = 778 pt between the safe areas), the same share of a
    // shorter one, never more.
    val side = if (pageHeight > 0f) min(300f, (pageHeight * 300f / 778f).roundToInt().toFloat()) else 300f
    Image(
        painter = painterResource(image),
        contentDescription = null,
        contentScale = ContentScale.Fit,
        modifier = modifier
            .padding(top = top, bottom = bottom)
            .size(side.dp),
    )
}

/** Red line under a field or the scanner, e.g. "Kode kadaluarsa…" (Figma "Kode Kadaluarsa"). `text` is localized. */
@Composable
fun OnboardingErrorLabel(text: String, modifier: Modifier = Modifier, systemImage: String = "exclamationmark.circle") {
    val color = OnboardingTheme.error
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SfSymbol(systemImage, pointSize = 15f, tint = color)
        Text(text, style = onboardingFont(15f, rounded = true).copy(color = color, textAlign = TextAlign.Center))
    }
}

// MARK: Success text motion

/** The success text rises 8 pt into place 0.15 s after the step slides in. Reduce Motion: a fade only. */
private fun Modifier.successTextEntrance(isOn: Boolean): Modifier = composed {
    val reduceMotion = LocalReduceMotion.current
    val progress = remember { Animatable(if (isOn) 0f else 1f) }
    LaunchedEffect(Unit) {
        if (isOn && progress.value < 1f) {
            swiftDelay(0.15)
            progress.animateTo(1f, shooSmooth(0.4))
        }
    }
    graphicsLayer {
        alpha = progress.value.coerceIn(0f, 1f)
        translationY = if (reduceMotion) 0f else (1f - progress.value) * 8.dp.toPx()
    }
}

/**
 * The celebrated success text (`OnboardingSuccessPage.celebrates`): the title rises 16 pt and grows from 94 % on a
 * light spring, the message follows without bounce. Reduce Motion: a 0.2 s fade at the same moment.
 */
private fun Modifier.celebrationTextEntrance(isOn: Boolean, delay: Double, bounces: Boolean): Modifier = composed {
    val reduceMotion = LocalReduceMotion.current
    val progress = remember { Animatable(if (isOn) 0f else 1f) }
    LaunchedEffect(Unit) {
        if (isOn && progress.value < 1f) {
            val spec: AnimationSpec<Float> = when {
                reduceMotion -> shooEaseInOut(0.2)
                bounces -> shooSpring(0.45, 0.25)
                else -> shooSmooth(0.45)
            }
            swiftDelay(delay)
            progress.animateTo(1f, spec)
        }
    }
    graphicsLayer {
        val p = progress.value
        alpha = p.coerceIn(0f, 1f)
        if (!reduceMotion) {
            translationY = (1f - p) * 16.dp.toPx()
            if (bounces) {
                val s = 0.94f + 0.06f * p
                scaleX = s
                scaleY = s
            }
        }
    }
}

// MARK: Celebration

/** Set by `OnboardingSuccessPage(celebrates = true)` for its hero. */
val LocalSuccessCelebration = compositionLocalOf { false }

/**
 * The hero's centre piece on a celebrated success page: it pops in, two white rings ripple out behind it and one
 * confetti burst leaves its centre. Does nothing on a page that doesn't celebrate.
 * `ringSize`: the rings' starting diameter, about the piece's visible width.
 *
 * One shot, about 1.2 s: the piece scales 0.6 → 1 on a bouncy spring from 0.1 s; when it lands (0.35 s) two rings
 * grow 0.8 → 2.2 and fade (0.8 s, the second 0.12 s later) and ~28 confetti bits fall away. Transform and opacity
 * only, so the layout is the same as without it. Reduce Motion: a 0.2 s fade, no rings or confetti.
 */
fun Modifier.successCelebrationHero(ringSize: Dp): Modifier = composed {
    val isOn = LocalSuccessCelebration.current
    val reduceMotion = LocalReduceMotion.current
    val landed = remember { Animatable(if (isOn) 0f else 1f) }
    val firstRing = remember { Animatable(0f) }
    val secondRing = remember { Animatable(0f) }
    var ringsArmed by remember { mutableStateOf(false) }
    var confettiStart by remember { mutableLongStateOf(-1L) }
    var confettiNow by remember { mutableLongStateOf(0L) }

    LaunchedEffect(Unit) {
        if (!isOn || landed.value >= 1f) return@LaunchedEffect
        if (reduceMotion) {
            landed.animateTo(1f, shooEaseInOut(0.2))
            return@LaunchedEffect
        }
        launch {
            swiftDelay(0.1)
            landed.animateTo(1f, shooSpring(0.5, 0.35))
        }
        delay(350)
        ringsArmed = true
        confettiStart = withFrameNanos { it }
        val confetti = launch {
            while (true) {
                val now = withFrameNanos { it }
                confettiNow = now
                if ((now - confettiStart) / 1e9 >= ConfettiBurst.LIFE) break
            }
        }
        // Let the rings draw once at their start before they grow.
        delay(16)
        launch { firstRing.animateTo(1f, shooEaseOut(0.8)) }
        delay(120)
        launch { secondRing.animateTo(1f, shooEaseOut(0.8)) }
        delay((ConfettiBurst.LIFE * 1000).toLong())
        confetti.cancel()
        // Burst over: drop the drawing so its frame loop stops.
        confettiStart = -1L
        ringsArmed = false
    }

    this
        // Behind the piece: the bits burst out from under its edges instead of clumping on its face.
        .drawBehind {
            if (!isOn || reduceMotion || !ringsArmed) return@drawBehind
            if (confettiStart >= 0L) {
                val time = (confettiNow - confettiStart) / 1e9
                ConfettiBurst.draw(this, time)
            }
            for (ring in listOf(firstRing.value, secondRing.value)) {
                val scale = 0.8f + (2.2f - 0.8f) * ring
                val opacity = 0.5f * (1f - ring)
                val stroke = 3.dp.toPx()
                val radius = ringSize.toPx() / 2f * scale - stroke * scale / 2f
                if (radius > 0f && opacity > 0f) {
                    drawCircle(Color.White.copy(alpha = opacity), radius = radius, center = center, style = Stroke(stroke * scale))
                }
            }
        }
        .graphicsLayer {
            val p = landed.value
            alpha = p.coerceIn(0f, 1f)
            if (!reduceMotion) {
                val s = 0.6f + 0.4f * p
                scaleX = s
                scaleY = s
            }
        }
}

/** ~28 white, teal and yellow bits thrown up from the centre that fall under gravity and fade; gone after `LIFE`. */
private object ConfettiBurst {
    const val LIFE = 0.85
    private const val GRAVITY = 1400.0

    private class Bit(val dx: Double, val dy: Double, val width: Float, val height: Float, val spin: Double, val color: Color)

    /** The same throw every time (a fixed-seed generator), so the burst looks designed, not noisy. */
    private val bits: List<Bit> = run {
        var seed: ULong = 0x5EED5100uL
        fun random(): Double {
            seed = seed * 6_364_136_223_846_793_005uL + 1_442_695_040_888_963_407uL
            return (seed shr 11).toDouble() / (1uL shl 53).toDouble()
        }
        val colors = listOf(Color.White, hex(0x5FE3D6), hex(0xFFD84A))
        (0 until 28).map { index ->
            // Up and out: −165° … −15°, 340–640 pt/s.
            val angle = (-165 + 150 * random()) * PI / 180
            val speed = 340 + 300 * random()
            val dx = cos(angle) * speed
            val dy = sin(angle) * speed
            val width = (5 + 3 * random()).toFloat()
            val height = (7 + 4 * random()).toFloat()
            val spin = (random() - 0.5) * 16
            Bit(dx, dy, width, height, spin, colors[index % colors.size])
        }
    }

    /** Draws the burst `time` seconds in, centred on the scope (the piece's centre). */
    fun draw(scope: androidx.compose.ui.graphics.drawscope.DrawScope, time: Double) = with(scope) {
        if (time < 0 || time >= LIFE) return@with
        val fade = min(1.0, (LIFE - time) / 0.3).toFloat()
        val d = density
        for (bit in bits) {
            val x = center.x + (bit.dx * time).toFloat() * d
            val y = center.y + (bit.dy * time + 0.5 * GRAVITY * time * time).toFloat() * d
            translate(x, y) {
                rotateRad((bit.spin * time).toFloat(), pivot = Offset.Zero) {
                    val w = bit.width * d
                    val h = bit.height * d
                    drawRoundRect(
                        color = bit.color.copy(alpha = bit.color.alpha * fade),
                        topLeft = Offset(-w / 2, -h / 2),
                        size = Size(w, h),
                        cornerRadius = CornerRadius(1.5f * d),
                    )
                }
            }
        }
    }
}

// MARK: Success page

/**
 * Blue success screen: illustration, white title + message, "Next" at the bottom (Figma "Berhasil Terhubung",
 * "Yeay, kamu berhasil"). Ids: `<idPrefix>.title`, `<idPrefix>.continue`. `title` / `message` are localized text.
 *
 * - `background`: each success screen has its own Figma gradient.
 * - `largeTitle`: "Berhasil Terhubung" has a 34 pt headline, "Yeay, kamu berhasil" a 28 pt one.
 * - `revealsText`: the title and message rise in a moment after the step slides in (ON-04 passed).
 * - `celebrates`: a one-shot celebration (~1.2 s): the hero's `successCelebrationHero` piece pops in with rings and
 *   confetti, the title and message come in one after the other, a heavy tap as the hero lands and a success tap
 *   with the title. "Next" works from the start. Replaces `revealsText`.
 */
@Composable
fun OnboardingSuccessPage(
    title: String,
    message: String,
    idPrefix: String,
    onContinue: () -> Unit,
    modifier: Modifier = Modifier,
    background: Int = R.drawable.success_background,
    largeTitle: Boolean = true,
    revealsText: Boolean = false,
    celebrates: Boolean = false,
    hero: @Composable () -> Unit,
) {
    val view = LocalView.current
    LaunchedEffect(Unit) {
        // The two taps of the celebration, with Reduce Motion too: the hero lands, then the title.
        if (!celebrates) return@LaunchedEffect
        delay(350)
        view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        delay(300)
        view.performHapticFeedback(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.KEYBOARD_TAP,
        )
    }
    LightOnly {
        Box(modifier = modifier.fillMaxSize()) {
            Image(
                painter = painterResource(background),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .windowInsetsPadding(WindowInsets.statusBars),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                CompositionLocalProvider(LocalSuccessCelebration provides celebrates) { hero() }

                // Figma "Frame 2": Large Title, 8, Body; or Title 1, 4, Subhead.
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 24.dp)
                        .successTextEntrance(revealsText && !celebrates),
                    verticalArrangement = Arrangement.spacedBy(if (largeTitle) 8.dp else 4.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    val titleStyle = if (largeTitle) {
                        onboardingFont(34f, FontWeight.SemiBold, tracking = -0.68f, lineHeight = 41f)
                    } else {
                        onboardingFont(28f, FontWeight.Medium, tracking = -0.56f, lineHeight = 33.6f)
                    }
                    val messageStyle = if (largeTitle) {
                        onboardingFont(17f, rounded = true, tracking = -0.17f)
                    } else {
                        onboardingFont(17f, rounded = true, lineHeight = 23.8f)
                    }
                    Text(
                        title,
                        style = titleStyle.copy(color = Color.White, textAlign = TextAlign.Center),
                        modifier = Modifier
                            .fillMaxWidth()
                            .semantics {
                                heading()
                                testTag = "$idPrefix.title"
                            }
                            .celebrationTextEntrance(celebrates, delay = 0.3, bounces = true),
                    )
                    Text(
                        message,
                        style = messageStyle.copy(color = hex(0xFAF9FB), textAlign = TextAlign.Center),
                        modifier = Modifier
                            .fillMaxWidth()
                            .celebrationTextEntrance(celebrates, delay = 0.42, bounces = false),
                    )
                }
                Spacer(Modifier.navigationBarsPadding().height(104.dp))
            }
            OnboardingCapsuleButton(
                title = "Next",
                onClick = onContinue,
                identifier = "$idPrefix.continue",
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .navigationBarsPadding()
                    .padding(horizontal = 24.dp)
                    // Figma "Footer": the button ends 68 pt above the screen bottom.
                    .padding(bottom = 34.dp),
            )
        }
    }
}
