package com.shoo.app.components

import androidx.annotation.DrawableRes
import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.shoo.app.features.onboarding.OnboardingBackButton
import com.shoo.app.features.onboarding.onboardingFont
import com.shoo.app.features.shield.HeroBackground
import com.shoo.app.features.shield.HeroPulse
import com.shoo.app.features.shield.HomeHeroStyle
import com.shoo.app.support.t

/** `StateHeroPage.ChipTone`. */
enum class StateChipTone {
    BLUE,
    RED,
    /** "Kedaluwarsa" (1665:3006): #4F6074 on itself at 10 %. */
    SLATE,
    /** "Gangguan koneksi" (1665:3023): #B85A05 on #EF871C at 14 %. */
    ORANGE;

    val ink: Color
        get() = when (this) {
            BLUE -> hex(0x136CB7)
            RED -> hex(0xBB1616)
            SLATE -> hex(0x4F6074)
            ORANGE -> hex(0xB85A05)
        }

    val fill: Color
        get() = when (this) {
            ORANGE -> hex(0xEF871C, 0.14f)
            BLUE, RED, SLATE -> ink.copy(alpha = 0.1f)
        }
}

/** The hero behind the shield: Home's blue, or a Figma export (`R.drawable.hero_gradient_slate`, `hero_gradient_orange`). */
sealed class StateHeroBackground {
    data object Blue : StateHeroBackground()
    data class Image(@DrawableRes val image: Int) : StateHeroBackground()
}

/** Figma: the rings' centre and the shield's top on the 402 × 874 frame; the sheet starts at y 380. */
private const val RING_CENTER = 225f
private const val SHEET_TOP = 380f
/** The top safe area on the 402 × 874 Figma iPhone. */
private const val SAFE_TOP = 62f

/**
 * A whole-screen state with the blue hero, a shield on the dashed rings, then a white sheet (32 pt corners) with a
 * chip, the headline, the line, optional content and the button pinned at the foot. Figma "Sesi berakhir"
 * (1665:2991), "Detail Aktivitas · Sudah tidak ada" (1665:3006) and "· Gagal memuat" (1665:3023). Motion: the shield
 * settles in, then chip, text, content and button rise in one after the other.
 *
 * `chip`, `title`, `message`: catalog keys. Drawn edge to edge: it pads itself for the status and navigation bars.
 */
@Composable
fun StateHeroPage(
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    chip: String? = null,
    chipTone: StateChipTone = StateChipTone.BLUE,
    background: StateHeroBackground = StateHeroBackground.Blue,
    titleIdentifier: String? = null,
    onBack: (() -> Unit)? = null,
    backIdentifier: String = "onboarding.back",
    shield: @Composable () -> Unit,
    content: @Composable ColumnScope.() -> Unit = {},
    footer: @Composable ColumnScope.() -> Unit = {},
) {
    LightOnly {
        val reduceMotion = LocalReduceMotion.current
        val shieldShown = remember { Animatable(0f) }
        LaunchedEffect(Unit) {
            shieldShown.animateTo(1f, if (reduceMotion) shooEaseOut<Float>(0.2) else shooSpring<Float>(0.35, 0.3))
        }

        Box(modifier.fillMaxSize().background(Color.White)) {
            // Background: fixed behind the scroll view, from the very top of the screen.
            Box(Modifier.fillMaxWidth().height((450f + SAFE_TOP).dp)) {
                when (background) {
                    is StateHeroBackground.Blue -> HeroBackground(style = HomeHeroStyle.BLUE, modifier = Modifier.fillMaxSize())
                    is StateHeroBackground.Image -> {
                        // Figma "Gradient-classic-2 lighter" (402 × 449 at y −9) with its grain, then the "box" fade to white.
                        Image(
                            painter = painterResource(background.image),
                            contentDescription = null,
                            contentScale = ContentScale.FillBounds,
                            modifier = Modifier.fillMaxSize(),
                        )
                        Box(
                            Modifier
                                .align(Alignment.BottomCenter)
                                .fillMaxWidth()
                                .height(140.dp)
                                .background(Brush.verticalGradient(listOf(Color.White.copy(alpha = 0f), Color.White))),
                        )
                    }
                }
            }

            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .windowInsetsPadding(WindowInsets.statusBars),
            ) {
                Box(
                    Modifier
                        .padding(top = (RING_CENTER - 118f - SAFE_TOP).dp)
                        .fillMaxWidth()
                        .height(236.dp)
                        .clearAndSetSemantics { },
                    contentAlignment = Alignment.Center,
                ) {
                    HeroPulse()
                    Box(
                        Modifier.graphicsLayer {
                            val p = shieldShown.value
                            val s = if (reduceMotion) 1f else 0.86f + 0.14f * p
                            scaleX = s
                            scaleY = s
                            alpha = p.coerceIn(0f, 1f)
                        },
                    ) { shield() }
                }

                StateSheet(
                    chip = chip,
                    chipTone = chipTone,
                    title = title,
                    message = message,
                    titleIdentifier = titleIdentifier,
                    content = content,
                    modifier = Modifier.padding(top = (SHEET_TOP - (RING_CENTER + 118f)).dp),
                )
                // `.contentMargins(.bottom, 104)`: room for the pinned footer.
                Spacer(Modifier.windowInsetsPadding(WindowInsets.navigationBars).height(104.dp))
            }

            if (onBack != null) {
                OnboardingBackButton(
                    action = onBack,
                    identifier = backIdentifier,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .windowInsetsPadding(WindowInsets.statusBars)
                        .padding(start = 24.dp),
                )
            }

            Column(
                Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .stateEntrance(delay = 0.24)
                    .drawBehind {
                        val fade = 24.dp.toPx()
                        drawRect(
                            Brush.verticalGradient(listOf(Color.White.copy(alpha = 0f), Color.White), startY = 0f, endY = fade),
                            size = Size(size.width, fade),
                        )
                        drawRect(Color.White, topLeft = androidx.compose.ui.geometry.Offset(0f, fade), size = Size(size.width, size.height - fade))
                    }
                    .windowInsetsPadding(WindowInsets.navigationBars)
                    .padding(start = 24.dp, end = 24.dp, top = 24.dp, bottom = 34.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) { footer() }
        }
    }
}

/** Figma "Sheet": 28 / 20 / 24 padding, 18 between the chip, the text and the content. */
@Composable
private fun StateSheet(
    chip: String?,
    chipTone: StateChipTone,
    title: String,
    message: String,
    titleIdentifier: String?,
    content: @Composable ColumnScope.() -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier
            .fillMaxWidth()
            .heightIn(min = 494.dp)
            .background(Color.White, RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp))
            .padding(start = 20.dp, end = 20.dp, top = 28.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (chip != null) {
            // Figma "Chip": the ink at 10 %, 6 / 8 padding, SF Pro Rounded Semibold 11.88 in capitals.
            val language = LocalAppLanguage.current
            Text(
                t(chip).uppercase(language.locale),
                style = onboardingFont(11.88f, FontWeight.SemiBold, rounded = true, tracking = -0.23f, lineHeight = 15.6f),
                color = chipTone.ink,
                modifier = Modifier
                    .stateEntrance(delay = 0.06)
                    .background(chipTone.fill, CapsuleShape)
                    .padding(horizontal = 8.dp, vertical = 6.dp),
            )
        }
        // Figma "Frame 2": SF Pro Display Medium 28 (120 %, −2 %), 8, SF Pro Rounded 17 (140 %) #6A717E.
        Column(
            Modifier.fillMaxWidth().stateEntrance(delay = 0.1),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                t(title),
                style = onboardingFont(28f, FontWeight.Medium, tracking = -0.56f, lineHeight = 33.6f),
                color = hex(0x151617),
                textAlign = TextAlign.Center,
                modifier = Modifier.semantics {
                    heading()
                    testTag = titleIdentifier ?: "state.title"
                },
            )
            Text(
                t(message),
                style = onboardingFont(17f, rounded = true, lineHeight = 23.8f),
                color = hex(0x6A717E),
                textAlign = TextAlign.Center,
            )
        }
        Column(Modifier.fillMaxWidth().stateEntrance(delay = 0.16)) { content() }
    }
}

/** `StateInfoList.Row`. `text`: catalog key. */
data class StateInfoRow(val systemImage: String, val text: String)

/**
 * Figma "Info" (1666:3648): #F5F8FC, 20 pt corners, 14 pt padding; rows of a 40 pt tile (the ink at 12 %, 12 pt
 * corners, the symbol bold 24) and SF Pro Rounded 17 at 70 %. `boxed`: Figma "Info" sits on #F5F8FC; Detail "Sudah
 * tidak ada" lists its rows on the sheet itself.
 */
@Composable
fun StateInfoList(
    rows: List<StateInfoRow>,
    modifier: Modifier = Modifier,
    tint: Color = hex(0x136CB7),
    boxed: Boolean = true,
) {
    Column(
        modifier
            .fillMaxWidth()
            .background(if (boxed) hex(0xF5F8FC) else Color.Transparent, RoundedCornerShape(20.dp))
            .padding(if (boxed) 14.dp else 0.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        for (row in rows) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .size(40.dp)
                        .background(tint.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
                        .clearAndSetSemantics { },
                    contentAlignment = Alignment.Center,
                ) {
                    // `.font(.system(size: 20, weight: .bold, design: .rounded))`.
                    SfSymbol(row.systemImage, pointSize = 20f, tint = tint)
                }
                Text(
                    t(row.text),
                    style = onboardingFont(17f, rounded = true, tracking = -0.17f, lineHeight = 22f),
                    color = hex(0x151617, 0.7f),
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}
