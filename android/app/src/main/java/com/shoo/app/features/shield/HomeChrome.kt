package com.shoo.app.features.shield

import androidx.annotation.DrawableRes
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.StartOffset
import androidx.compose.animation.core.StartOffsetType
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredHeight
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.ImageShader
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.constrainHeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.offset
import com.shoo.app.R
import com.shoo.app.components.AvatarRing
import com.shoo.app.components.AvatarView
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.HalftoneShield
import com.shoo.app.components.HalftoneShieldSize
import com.shoo.app.components.HalftoneShieldTint
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.components.LocalReduceGlass
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.ScanBadge
import com.shoo.app.components.ShooEasing
import com.shoo.app.components.SiteIcon
import com.shoo.app.components.SoftPulse
import com.shoo.app.components.dynamicColor
import com.shoo.app.components.figmaCardShadow
import com.shoo.app.components.hex
import com.shoo.app.components.shooEaseOut
import com.shoo.app.components.shooShadow
import com.shoo.app.components.textScale
import com.shoo.app.data.ScanResult
import com.shoo.app.data.ScanStatus
import com.shoo.app.features.detail.ScoreGauge
import com.shoo.app.features.detail.ScoreGaugeSize
import com.shoo.app.features.onboarding.OnboardingTheme
import com.shoo.app.features.onboarding.onboardingFont
import com.shoo.app.support.AppLanguage
import com.shoo.app.support.Formatters
import com.shoo.app.support.t
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min

/**
 * Colours from the Figma HOME page (Pribadi/Home 435:20058, Guardian/Home 435:20373, protected/Home 441:3800).
 * Light only, like the onboarding screens.
 */
object HomeTheme {
    val background = hex(0xF9FBFC)
    val fade = hex(0xF3F6F8)
    val heroDark = hex(0x1E78BE)
    val heroLight = hex(0x68CDFA)
    val heroGlow = hex(0x8FE9EC)
    val navy = hex(0x191D2F)
    val ink = hex(0x151617)
    /** Figma #6A717E is 4.6:1 on white. */
    val secondaryInk = hex(0x6A717E)
    val bodyInk = hex(0x3A3D42)
    val tileIcon = hex(0xE5483B)
    val tileIconBackground = hex(0xF3F6F8)
    val rowStroke = hex(0xE2E8F0)
    val divider = hex(0xE3E6E7)
    /** Figma "Cara Kerja" step dividers. */
    val stepDivider = hex(0xEEF1F5)
    /** Figma recent-row second line ("Hari ini · 10.42 WIB"), 7.6:1 on white. */
    val rowSubtitle = hex(0x564C51)
    /** Figma "Bagikan", step numbers and "Lihat Semua ▶". */
    val action = hex(0x186FB9)
    val actionFill = hex(0xEEF4FB)
    val quietFill = hex(0xE6E8EC)
    /** Figma #D67D00 is 2.9:1 on its chip; darkened to 4.6:1 for 13 pt text. */
    val warningText = hex(0xA85A00)
    val warningFill = hex(0xFFF8EF)
    val warningStroke = hex(0xFFE1B6)
    val dangerText = hex(0xBB1616)
    val dangerFill = hex(0xFFF4F4)
    val dangerStroke = hex(0xFFCDCD)
    val success = hex(0x34C759)
    val successText = hex(0x1B7F3A)
    val offline = hex(0x8E939C)
    /** Figma "Kartu/Scam Terbaru" icon circle, State/Danger/Background. */
    val scamIconFill = hex(0xFDECEA)
    /** Figma "Aktif" under a family member: Labels/Secondary, #3C3C43 at 60 %. */
    val memberStatus = hex(0x3C3C43, 0.6f)
    /** Figma "icon/switch" stroke and the "Lihat Semua" glass button text. */
    val glassInk = hex(0x1A1A1A)
}

// MARK: - Hero

/** The hero looks of the Figma HOME page. */
enum class HomeHeroStyle {
    /** Blue: own Home (Pribadi, protected). */
    BLUE,
    /** Teal: the family is protected, or a family site waits. */
    TEAL,
    /** Blue with a teal glow: nobody in the family yet (435:20630). */
    EMPTY,
    /** Orange: own Home after a warning (Pribadi/Home · Waspada 955:10369). */
    AMBER,
    /** Red: own Home after a block (Pribadi/Home · Bahaya 955:10467). */
    RED,
    /** Deep red: a blocked family site waits (Guardian/Home · Bahaya 955:10565). */
    CRIMSON;

    /**
     * The Figma "Gradient-classic-2 lighter" frame (402 × 450, rectangle and two 134-blur ellipses): the blurred
     * shapes are rotated paths that can't be redrawn one to one.
     */
    @get:DrawableRes
    val gradientImage: Int
        get() = when (this) {
            BLUE -> R.drawable.hero_gradient_blue
            TEAL -> R.drawable.hero_gradient_teal
            EMPTY -> R.drawable.hero_gradient_empty
            AMBER -> R.drawable.hero_gradient_amber
            RED -> R.drawable.hero_gradient_red
            CRIMSON -> R.drawable.hero_gradient_crimson
        }

    /** Blue and empty were exported without the film grain; the others carry it in the image. */
    val needsGrain: Boolean
        get() = when (this) {
            BLUE, EMPTY -> true
            TEAL, AMBER, RED, CRIMSON -> false
        }

    /** Figma "Ellipse 1", the colour at the top of the frame; fills the overscroll above it. */
    val topColor: Color
        get() = when (this) {
            BLUE -> hex(0x1D82D0)
            TEAL -> hex(0x00B3BE)
            EMPTY -> hex(0x1E78BE)
            AMBER -> hex(0xD07A1E)
            RED -> hex(0xD01E28)
            CRIMSON -> hex(0xBE0812)
        }
}

/** Where each Figma HOME frame puts the hero parts, in points from the top of the 402 × 874 frame. */
data class HomeHeroLayout(
    /** Top of the glass shield ("Kaca"). */
    val shieldTop: Float = 124f,
    /** "Shield Kaca Halftone" is 210 wide (1.25 × the onboarding shield); "Shield G" 213. */
    val shieldScale: Float = 1.25f,
    /** Top of the headline's text box. */
    val titleTop: Float = 290f,
    /** From the bottom of the last line of text to the top of the status strip (or the sheet). */
    val bottomGap: Float = 49f,
    val showsRings: Boolean = true,
    /** The background runs on under the strip (or the sheet), to the end of the Figma "box" fade. */
    val backgroundOverhang: Float = 72f,
    /** Where the frame puts the gradient and the "box" fade, when they don't follow the sheet. */
    val backdrop: HeroBackdrop? = null,
) {
    /** The headline's text box ends here on the frame (`titleTop` + one 34 pt line). */
    val titleBottom: Float get() = titleTop + 34f

    companion object {
        /** Pribadi/Home 435:20058 / 1382:10567: the gradient at y −7.08, the "box" fade 323…443, the sheet at 372. */
        val personal = HomeHeroLayout(backdrop = HeroBackdrop(boxTop = 323f))
        /** Guardian/Home 435:20373: no strip, the white sheet starts at y 374; the "box" fade ends at 443. */
        val family = HomeHeroLayout(shieldTop = 130f, titleTop = 309f, bottomGap = 32.67f, backgroundOverhang = 69f)
        /** Guardian/Home/warning 1382:2599 and /blocked 1382:10314: Kaca 130 wide at y 126. */
        val familyPending = HomeHeroLayout(shieldTop = 126f, titleTop = 309f, bottomGap = 32.67f, backgroundOverhang = 69f)
        /** Guardian/Home · Belum ada orang 1382:10466: no rings, a line under the headline; sheet at 377, fade to 436. */
        val familyEmpty = HomeHeroLayout(
            shieldTop = 104f, shieldScale = 1.25f * 133f / 130f, titleTop = 284f, bottomGap = 34f,
            showsRings = false, backgroundOverhang = 59f,
        )

        // The ring centre is 204 pt from the top of the frame; the hero itself starts under the navigation bar
        // room, 115 pt down on the 402 × 874 screen.
        internal const val ringCenter = 204f
        const val heroTop = 115.3f
        /** Kaca top above the shield's centre at scale 1. */
        internal const val kacaRise = 61.3f
        /** SwiftUI's text box for 28 pt starts 1.4 pt above Figma's (34 pt lines) for the same glyphs. */
        internal const val titleBoxShift = 1.4f
    }
}

/** Figma "Gradient-classic-2 lighter" and "box" in points from the top of the 402 × 874 frame. */
data class HeroBackdrop(
    /** Top and height of the "box" fade into the page (#F3F6F8, clear to solid). */
    val boxTop: Float,
    /** Top of the 450 pt gradient. */
    val imageTop: Float = -7.08f,
    val boxHeight: Float = 120f,
)

/**
 * Rings, glass shield, headline (and an optional line or link under it). `accessory` sits under the text, still
 * on the hero (Protected: "Terhubung dengan …"). `title` / `subtitle`: catalog keys.
 *
 * The background reaches up 400 dp above the hero (status bar, overscroll) and down under the strip; put the
 * hero in a scroll container that doesn't clip it at the screen top.
 */
@Composable
fun HomeHero(
    style: HomeHeroStyle,
    title: String,
    titleIdentifier: String,
    modifier: Modifier = Modifier,
    titleColor: Color = Color.White,
    subtitle: String? = null,
    shieldOn: Boolean = true,
    shieldTint: HalftoneShieldTint = HalftoneShieldTint.BLUE,
    layout: HomeHeroLayout = HomeHeroLayout.personal,
    /** null: `layout.bottomGap`. */
    bottomPadding: Dp? = null,
    accessory: @Composable ColumnScope.() -> Unit = {},
) {
    val ringCenter = HomeHeroLayout.ringCenter
    Box(modifier.fillMaxWidth()) {
        // Reaches up under the status bar and the overscroll, and down under the strip.
        val backdrop = layout.backdrop
        if (backdrop != null) {
            AnchoredHeroBackground(
                style = style,
                backdrop = backdrop,
                modifier = Modifier
                    .matchParentSize()
                    .placedFree(top = (backdrop.imageTop - HomeHeroLayout.heroTop - AnchoredHeroBackgroundOverscroll).dp),
            )
        } else {
            HeroBackground(
                style = style,
                modifier = Modifier.matchParentSize().extendedBy(top = 400.dp, bottom = layout.backgroundOverhang.dp),
            )
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .swiftPadding(bottom = bottomPadding ?: (layout.bottomGap - 0.6f).dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                modifier = Modifier
                    .swiftPadding(top = (ringCenter - 118f - HomeHeroLayout.heroTop).dp)
                    .fillMaxWidth()
                    .height(236.dp),
                contentAlignment = Alignment.Center,
            ) {
                if (layout.showsRings) HeroPulse()
                HalftoneShield(
                    modifier = Modifier
                        .offset(y = (layout.shieldTop - (ringCenter - HomeHeroLayout.kacaRise * layout.shieldScale)).dp)
                        .graphicsLayer {
                            scaleX = layout.shieldScale
                            scaleY = layout.shieldScale
                        },
                    isOn = shieldOn,
                    tint = shieldTint,
                )
            }

            Column(
                modifier = Modifier
                    .swiftPadding(top = (layout.titleTop - HomeHeroLayout.titleBoxShift - (ringCenter + 118f)).dp)
                    .padding(horizontal = 24.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                // A new headline in an animated update cross-fades (e.g. "You're protected!").
                Crossfade(targetState = title, label = "homeHeroTitle") { key ->
                    // Figma "Title 1/Emphasized".
                    Text(
                        text = t(key),
                        style = onboardingFont(28f, weight = FontWeight.Bold, tracking = -0.56f),
                        color = titleColor,
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .semantics { heading() }
                            .testTag(titleIdentifier),
                    )
                }
                if (subtitle != null) {
                    // Figma "Sub" (1382:10498): SF Pro Rounded 17, 140 % lines, 4 under the headline.
                    Text(
                        text = t(subtitle),
                        style = onboardingFont(17f, rounded = true, lineHeight = 23.8f),
                        color = titleColor,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.swiftPadding(top = (-3).dp),
                    )
                }
            }
            accessory()
        }
    }
}

/** Room above the frame for the status bar and the overscroll. */
private const val AnchoredHeroBackgroundOverscroll = 400f

/**
 * The hero background at fixed frame positions (`HeroBackdrop`): the top colour above, the gradient, the page
 * colour under it where the "box" runs on, and the box fade over both.
 */
@Composable
private fun AnchoredHeroBackground(style: HomeHeroStyle, backdrop: HeroBackdrop, modifier: Modifier = Modifier) {
    val overscroll = AnchoredHeroBackgroundOverscroll
    val boxTop = backdrop.boxTop - backdrop.imageTop
    val below = max(0f, boxTop + backdrop.boxHeight - 450f)
    Box(modifier.clearAndSetSemantics { }) {
        Column(Modifier.fillMaxWidth()) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(overscroll.dp)
                    .background(style.topColor),
            )
            HeroGradientImage(style, Modifier.fillMaxWidth().height(450.dp))
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(below.dp)
                    .background(HomeTheme.background),
            )
        }
        Box(
            Modifier
                .padding(top = (overscroll + boxTop).dp)
                .fillMaxWidth()
                .height(backdrop.boxHeight.dp)
                .background(Brush.verticalGradient(listOf(HomeTheme.fade.copy(alpha = 0f), HomeTheme.fade))),
        )
    }
}

/** The 450 pt gradient image, stretched to the width, with the film grain where the export has none. */
@Composable
private fun HeroGradientImage(style: HomeHeroStyle, modifier: Modifier = Modifier) {
    Image(
        painter = painterResource(style.gradientImage),
        contentDescription = null,
        contentScale = ContentScale.FillBounds,
        modifier = if (style.needsGrain) modifier.heroGrain() else modifier,
    )
}

/** "HeroTexture" tiled (1 image pixel = 1 dp, like the 1× iOS asset), multiplied at 35 %. */
@Composable
private fun Modifier.heroGrain(): Modifier {
    val texture = ImageBitmap.imageResource(R.drawable.hero_texture)
    val brush = remember(texture) { ShaderBrush(ImageShader(texture, TileMode.Repeated, TileMode.Repeated)) }
    return drawWithContent {
        drawContent()
        scale(density, density, pivot = Offset.Zero) {
            drawRect(
                brush = brush,
                size = Size(size.width / density, size.height / density),
                alpha = 0.35f,
                blendMode = BlendMode.Multiply,
            )
        }
    }
}

/**
 * Figma "Latar Shield": three dashed rings (236 / 300 / 368 pt, 2 on 6 off) over soft white discs that grow out of
 * the shield and fade. 368 wide in a 236 pt tall frame; the rings overflow it like on iOS.
 */
@Composable
fun HeroPulse(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .requiredWidth(368.dp)
            .requiredHeight(236.dp)
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.requiredSize(368.dp), contentAlignment = Alignment.Center) {
            // 9 s per disc, so a new one every 3 s: at the loader's 4 s the big Home hero felt hurried.
            SoftPulse(smallest = 120.dp, largest = 368.dp, peak = 0.2f, period = 9.0)
            Canvas(Modifier.requiredSize(368.dp)) {
                ring(368f, 0.16f, 1f)
                ring(300f, 0.28f, 1.2f)
                ring(236f, 0.45f, 1.5f)
            }
        }
    }
}

/** Figma strokes are inside the ellipse. */
private fun androidx.compose.ui.graphics.drawscope.DrawScope.ring(diameter: Float, opacity: Float, width: Float) {
    val strokePx = width.dp.toPx()
    drawCircle(
        color = Color.White.copy(alpha = opacity),
        radius = diameter.dp.toPx() / 2 - strokePx / 2,
        center = center,
        style = Stroke(
            width = strokePx,
            cap = StrokeCap.Butt,
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(2.dp.toPx(), 6.dp.toPx())),
        ),
    )
}

/**
 * Figma "Gradient-classic-2 lighter" (y −7…443 of the frame) with its film grain, then the "box" fade (the last
 * 120 pt) into the page. Above the image the top colour carries on, as tall as the caller makes this view.
 */
@Composable
fun HeroBackground(style: HomeHeroStyle, modifier: Modifier = Modifier) {
    Column(modifier.clipToBounds().clearAndSetSemantics { }) {
        Box(
            Modifier
                .fillMaxWidth()
                .weight(1f)
                .background(style.topColor),
        )
        Box(Modifier.fillMaxWidth().height(450.dp)) {
            HeroGradientImage(style, Modifier.matchParentSize())
            Box(
                Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .height(120.dp)
                    .background(Brush.verticalGradient(listOf(HomeTheme.fade.copy(alpha = 0f), HomeTheme.fade))),
            )
        }
    }
}

// MARK: - Top bar

/** An inline navigation bar's height: Home has none, so its page keeps this room (`HomeHeroLayout.heroTop`). */
val HomeTopBarHeight = 54.dp

/**
 * Figma "Top Bar" (435:20380): ⇆ and the profile circle, 50 pt each, 24 pt in from the sides, right under the status
 * bar. Drawn over the page; place as an overlay of the scroll view starting at the status bar's bottom edge.
 * `avatarId`: the user's picked avatar; null draws the neutral person. `onSwitch` null: no ⇆ (protected/Home).
 */
@Composable
fun HomeTopBar(
    avatarId: String?,
    onSwitch: (() -> Unit)?,
    onProfile: () -> Unit,
    modifier: Modifier = Modifier,
    isFamilyShown: Boolean = false,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp)
            .height(50.dp),
        verticalAlignment = Alignment.Top,
    ) {
        if (onSwitch != null) {
            HomeSwitchButton(isFamilyShown = isFamilyShown, action = onSwitch)
        }
        Spacer(Modifier.weight(1f).widthIn(min = 16.dp))
        ProfileAvatarButton(avatarId = avatarId, action = onProfile)
    }
}

/** The ⇆ glass circle on its own (the top bar's left button). */
@Composable
private fun HomeSwitchButton(isFamilyShown: Boolean, action: () -> Unit) {
    val label = t("Family mode")
    val value = t(if (isFamilyShown) "On" else "Off")
    val hint = t("Switches between your own Shield and your family's")
    Box(
        modifier = Modifier
            .size(50.dp)
            .homeGlassCircle()
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                role = Role.Switch,
                onClickLabel = hint,
                onClick = action,
            )
            .semantics {
                contentDescription = label
                stateDescription = value
                role = Role.Switch
            }
            .testTag("familyModeToggle"),
        contentAlignment = Alignment.Center,
    ) {
        // Figma "icon/switch" (435:20383): the exported 18 pt vector, #1A1A1A 1.65 pt strokes.
        Icon(
            painter = painterResource(R.drawable.home_switch),
            contentDescription = null,
            tint = HomeTheme.glassInk,
            modifier = Modifier.size(18.dp),
        )
    }
}

/**
 * Frosted circle; a solid circle with "Kurangi efek kaca". Figma "Liquid Glass - Regular - Small" reads as light
 * frost on every hero (about 57 % light grey over the hero colour), so the frost is a plain fill.
 */
@Composable
private fun Modifier.homeGlassCircle(): Modifier =
    if (LocalReduceGlass.current) {
        background(Color.White, CircleShape)
    } else {
        background(Color(0.9f, 0.9f, 0.9f, 0.57f), CircleShape)
            .border(1.dp, Color.White.copy(alpha = 0.45f), CircleShape)
    }

/** Top-right 50 pt circle with the user's picked avatar and a 2 pt white rim; opens Profile (PF-01). */
@Composable
private fun ProfileAvatarButton(avatarId: String?, action: () -> Unit) {
    val label = t("Profile")
    AvatarView(
        id = avatarId ?: "",
        size = 50.dp,
        ring = AvatarRing(width = 2.dp),
        modifier = Modifier
            .shooShadow(HomeTheme.heroDark.copy(alpha = 0.18f), radius = 6.dp, y = 4.dp, shape = CircleShape)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                role = Role.Button,
                onClick = action,
            )
            .semantics { contentDescription = label }
            .testTag("profileButton"),
    )
}

// MARK: - Sheet

/** The white Figma "Status" / "Konten" sheet over the bottom of the hero: 22 pt corners all round. */
fun Modifier.homeSheet(): Modifier = this
    .fillMaxWidth()
    .background(Color.White, RoundedCornerShape(22.dp))

/** Figma "Update card": white, 20 pt corners, a hairline of light and a very soft shadow. */
fun Modifier.homeCard(cornerRadius: Dp = 20.dp): Modifier {
    val shape = RoundedCornerShape(cornerRadius)
    return this
        .figmaCardShadow(shape)
        .background(Color.White, shape)
        // iOS strokes on the edge (half outside); Compose borders sit inside.
        .border(1.dp, Color.White.copy(alpha = 0.9f), shape)
}

/** Gradient hairline that fades out at both ends (Figma Line 13 / 14). */
@Composable
fun FadingDivider(modifier: Modifier = Modifier, axis: Orientation = Orientation.Horizontal) {
    val stops = listOf(HomeTheme.divider.copy(alpha = 0f), HomeTheme.divider, HomeTheme.divider.copy(alpha = 0f))
    if (axis == Orientation.Horizontal) {
        Box(
            modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(Brush.horizontalGradient(stops))
                .clearAndSetSemantics { },
        )
    } else {
        Box(
            modifier
                .fillMaxHeight()
                .width(1.dp)
                .background(Brush.verticalGradient(stops))
                .clearAndSetSemantics { },
        )
    }
}

/** "Aktivitas Terakhir", "Orang yang dilindungi", "Cara Kerja": SF Pro Rounded 17, -1 %, 22 pt lines. `title`: catalog key. */
@Composable
fun HomeSectionTitle(title: String, modifier: Modifier = Modifier) {
    Text(
        text = t(title),
        style = onboardingFont(17f, rounded = true, tracking = -0.17f, lineHeight = 22f),
        color = OnboardingTheme.bodyInk,
        modifier = modifier
            .fillMaxWidth()
            .semantics { heading() },
    )
}

// MARK: - Risk gauge

/** The Detail "Scam Score Gauge" (370 × 237) fitted to the width it gets. */
@Composable
fun FittedScoreGauge(
    scan: ScanResult,
    modifier: Modifier = Modifier,
    maxWidth: Dp = ScoreGaugeSize.width,
    /** Figma's Home cards keep the full 237 pt gauge frame whatever the status. */
    reservesBlockedHeight: Boolean = false,
) {
    val height = if (scan.status == ScanStatus.BLOCKED || reservesBlockedHeight) 237f else 219f
    val label = t("Risk score")
    val value = Formatters.percent(scan.score, LocalAppLanguage.current)
    BoxWithConstraints(
        modifier = modifier
            .widthIn(max = maxWidth)
            .fillMaxWidth()
            .aspectRatio(ScoreGaugeSize.width.value / height)
            .clearAndSetSemantics {
                contentDescription = label
                stateDescription = value
            },
    ) {
        val scale = this.maxWidth / ScoreGaugeSize.width
        ScoreGauge(
            score = scan.score,
            status = scan.status,
            modifier = Modifier
                .wrapContentSize(Alignment.TopStart, unbounded = true)
                .requiredSize(ScoreGaugeSize)
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                    transformOrigin = TransformOrigin(0f, 0f)
                },
        )
    }
}

/**
 * Figma "Frame 1618872237": the white 70 % risk panel (338 × 211) with the alert shield, "Situs Mencurigakan!" /
 * "Situs Berbahaya!" and the bar with the score. Guardian/Home draws a second panel inset in it (`layered`).
 * `isDanger`: red "Situs Berbahaya!" (blocked, or marked not safe); otherwise orange "Situs Mencurigakan!".
 */
@Composable
fun HomeRiskPanel(scan: ScanResult, isDanger: Boolean, modifier: Modifier = Modifier, layered: Boolean = false) {
    val titleTop = 129.5f
    // Figma "Kaca": orange 71.6 pt wide 27.1 under the panel's top; red 67.8 at 28.5 on protected/Home 1115:17294.
    // Guardian's blocked frame is the warning card scaled to 97 %, so it keeps the orange numbers.
    val (kacaWidth, kacaTop) = if (isDanger && !layered) 67.83f to 28.46f else 71.6f to 27.1f
    Box(modifier.fillMaxWidth().semantics(mergeDescendants = true) { }) {
        Box(
            Modifier
                .matchParentSize()
                .background(Color.White.copy(alpha = 0.7f), RoundedCornerShape(22.9.dp)),
        )
        if (layered) {
            Box(
                Modifier
                    .matchParentSize()
                    .padding(start = 4.9.dp, top = 3.1.dp, end = 4.9.dp, bottom = 3.dp)
                    .background(Color.White.copy(alpha = 0.7f), RoundedCornerShape(22.3.dp)),
            )
        }
        // The Home shield at Figma's size: "Kaca" `kacaWidth` wide (104 pt at scale 1), its top `kacaTop` down.
        Box(Modifier.matchParentSize(), contentAlignment = Alignment.TopCenter) {
            val scale = kacaWidth / 104f
            val size = HalftoneShieldSize
            Box(
                modifier = Modifier
                    .padding(top = (kacaTop - (size.height.value * scale / 2 - 61.3f * scale)).dp)
                    .requiredSize(size.width * scale, size.height * scale)
                    .clearAndSetSemantics { },
                contentAlignment = Alignment.Center,
            ) {
                HalftoneShield(
                    modifier = Modifier
                        .requiredSize(size)
                        .graphicsLayer {
                            scaleX = scale
                            scaleY = scale
                        },
                    tint = if (isDanger) HalftoneShieldTint.RED_ALERT else HalftoneShieldTint.ORANGE,
                )
            }
        }
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            // Figma: SF Pro Display Semibold 28, +2 %, 34 pt lines, #191D2F.
            // iOS: `.minimumScaleFactor(0.7)` has no Compose counterpart; the title wraps instead.
            Text(
                text = t(if (isDanger) "Dangerous site!" else "Suspicious site!"),
                style = onboardingFont(28f, weight = FontWeight.SemiBold, tracking = 0.56f, lineHeight = 34f),
                color = HomeTheme.navy,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .padding(horizontal = 16.dp)
                    .padding(top = titleTop.dp),
            )
            HomeRiskBar(
                scan = scan,
                modifier = Modifier.padding(top = 6.7.dp, bottom = 6.8.dp),
            )
        }
    }
}

/**
 * Figma "Bar" (1382:10996): one capsule per reason, by weight and scaled to the score, 1.5 pt apart; a 2 pt tick at
 * the score; the hatched grey track for the rest. 153 pt, the score 8 pt beside it.
 */
@Composable
fun HomeRiskBar(scan: ScanResult, modifier: Modifier = Modifier) {
    val width = 153f
    val gap = 1.5f
    val tickWidth = 2f
    val colors = listOf(hex(0xFF9500), hex(0xF87541), hex(0xE5483B))
    val tick = hex(0xE5483B)
    // Segment widths: the weights, heaviest first, sharing the score's part of the bar.
    val score = min(max(scan.score, 0), 100) / 100f
    val weights = scan.signals.map { max(it.weight, 0).toFloat() }.filter { it > 0f }.sortedDescending()
    val parts = if (weights.isEmpty()) listOf(1f) else weights
    val total = parts.sum()
    val usable = width - (parts.size + 1) * gap - tickWidth
    val segments = parts.map { usable * score * it / total }
    val label = t("Risk score")
    val value = "${scan.score}/100"

    Row(
        modifier = modifier
            // Figma "Frame 1618872328" sits 4.5 pt left of the panel's centre.
            .padding(end = 9.dp)
            .clearAndSetSemantics {
                contentDescription = label
                stateDescription = value
            },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            modifier = Modifier
                .width(width.dp)
                .height(18.dp),
            horizontalArrangement = Arrangement.spacedBy(gap.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            segments.forEachIndexed { index, segment ->
                HatchedBar(
                    fill = colors[min(index, colors.size - 1)],
                    hatch = Color.White.copy(alpha = 0.3f),
                    modifier = Modifier
                        .width(segment.dp)
                        .shooShadow(tick.copy(alpha = 0.35f), radius = 2.dp, y = 1.5.dp, shape = CapsuleShape),
                )
            }
            Box(
                Modifier
                    .width(tickWidth.dp)
                    .height(16.dp)
                    .background(tick, RoundedCornerShape(0.6.dp)),
            )
            HatchedBar(fill = hex(0xE9ECF1), hatch = hex(0xCFD5DD), modifier = Modifier.weight(1f))
        }
        // Figma: SF Pro Display Semibold 15, +2 %, in a 34 pt line.
        Box(Modifier.heightIn(min = 34.dp), contentAlignment = Alignment.Center) {
            Text(
                text = value,
                style = onboardingFont(15f, weight = FontWeight.SemiBold, tracking = 0.3f),
                color = HomeTheme.navy,
                maxLines = 1,
                softWrap = false,
            )
        }
    }
}

/** 10 pt capsule with 0.6 pt 45° hatching every 2.48 pt (Figma "Hatch"). */
@Composable
private fun HatchedBar(fill: Color, hatch: Color, modifier: Modifier = Modifier) {
    Canvas(
        modifier
            .height(10.dp)
            .clip(CapsuleShape),
    ) {
        drawRect(fill)
        val path = Path()
        val step = 2.48.dp.toPx()
        var x = -size.height
        while (x < size.width + size.height) {
            path.moveTo(x, size.height)
            path.lineTo(x + size.height, 0f)
            x += step
        }
        drawPath(path, hatch, style = Stroke(width = 0.6.dp.toPx()))
    }
}

// MARK: - Supervised mode

/** iOS `dynamicTypeSize.isAccessibilitySize` (AX1 and up: body ≥ 28 pt, 1.6 × the default). */
@Composable
private fun isAccessibilitySize(): Boolean = textScale() >= 1.6f

/**
 * Figma "CTA Jadi Guardian" with the "MODE TERAWASI" copy (Pribadi 1382:10600, protected/Home 1382:2393): asks to
 * connect so someone close can check sites again. 354 × 205, 24 pt corners; the teal shield (exported from Figma,
 * 145 × 177 at 209, 19) is clipped by the card. X hides it on this phone.
 */
@Composable
fun SupervisedModeCard(onConnect: () -> Unit, onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    val accessibilitySize = isAccessibilitySize()
    val shape = RoundedCornerShape(24.dp)
    val fill = Brush.horizontalGradient(listOf(hex(0xF3F8FF), hex(0xE2F8F5)))
    Box(
        modifier = modifier
            .figmaCardShadow(shape)
            .clip(shape)
            .background(fill)
            .border(1.dp, Color.White.copy(alpha = 0.9f), shape)
            .fillMaxWidth()
            .heightIn(min = 205.dp)
            .testTag("home.supervised"),
    ) {
        if (!accessibilitySize) {
            Image(
                painter = painterResource(R.drawable.home_supervised_shield),
                contentDescription = null,
                contentScale = ContentScale.FillBounds,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 19.dp)
                    .size(145.dp, 177.dp),
            )
        }
        Column(
            modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 22.dp),
            horizontalAlignment = Alignment.Start,
        ) {
            // Figma: SF Pro Rounded Semibold 11, 13 pt lines, 0.06 tracking, #0D8F93.
            Text(
                text = t("SUPERVISED MODE"),
                style = onboardingFont(11f, weight = FontWeight.SemiBold, rounded = true, tracking = 0.06f, lineHeight = 13f),
                color = hex(0x0D8F93),
                modifier = Modifier.padding(top = 22.dp),
            )
            // SF Pro Display Semibold 20, 25 pt lines, -0.45, #151617.
            Text(
                text = t("Not sure?"),
                style = onboardingFont(20f, weight = FontWeight.SemiBold, tracking = -0.45f, lineHeight = 25f),
                color = HomeTheme.ink,
                modifier = Modifier
                    .padding(top = 7.dp)
                    .semantics { heading() },
            )
            // SF Pro Rounded 16, 21 pt lines, -0.31, #6A717E, 206 wide.
            Text(
                text = t("Connect so someone you love can check it again"),
                style = onboardingFont(16f, rounded = true, tracking = -0.31f, lineHeight = 21f),
                color = OnboardingTheme.bodyInk,
                modifier = Modifier
                    .padding(top = 5.dp)
                    .then(if (accessibilitySize) Modifier.fillMaxWidth() else Modifier.widthIn(max = 206.dp)),
            )
            // SF Pro Display Semibold 17, 22 pt line; 38 pt capsule, 18 pt sides. The touch area still reaches 44.
            Box(
                modifier = Modifier
                    .padding(top = 10.dp)
                    .expandedTouch(3.dp)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        role = Role.Button,
                        onClick = onConnect,
                    )
                    .padding(3.dp)
                    .drawBehind {
                        // Figma "Tombol / Jadi Guardian": #214889 three quarters down, #446EB4 just above the top.
                        drawRoundRect(
                            brush = Brush.linearGradient(
                                colors = listOf(hex(0x214889), hex(0x446EB4)),
                                start = Offset(size.width / 2, size.height * 0.75f),
                                end = Offset(size.width / 2, -0.05f * size.height),
                            ),
                            cornerRadius = CornerRadius(size.height / 2, size.height / 2),
                        )
                    }
                    .heightIn(min = 38.dp)
                    .padding(horizontal = 18.dp)
                    .testTag("home.supervised.connect"),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = t("Connect"),
                    style = onboardingFont(17f, weight = FontWeight.SemiBold, lineHeight = 22f),
                    color = Color.White,
                )
            }
        }

        // Figma "Tutup": 28 pt, white 75 % with a white ring, a 9 pt × in 1.6 pt #6A717E strokes; 12 from the corner.
        val closeLabel = t("Close")
        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 4.dp, end = 4.dp)
                .size(44.dp)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    role = Role.Button,
                    onClick = onDismiss,
                )
                .semantics { contentDescription = closeLabel }
                .testTag("home.supervised.close"),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                Modifier
                    .size(28.dp)
                    .background(Color.White.copy(alpha = 0.75f), CircleShape)
                    .border(1.dp, Color.White, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Canvas(Modifier.size(9.dp)) {
                    val stroke = Stroke(width = 1.6.dp.toPx(), cap = StrokeCap.Round)
                    val path = Path().apply {
                        moveTo(0f, 0f); lineTo(size.width, size.height)
                        moveTo(size.width, 0f); lineTo(0f, size.height)
                    }
                    drawPath(path, HomeTheme.secondaryInk, style = stroke)
                }
            }
        }
    }
}

// MARK: - Recent activity

/**
 * Figma "Empty State · Aktivitas" (Pribadi/Home · Empty Aktivitas 1883:11955): the 128 pt shield, then "Belum ada
 * aktivitas" (SF Pro Rounded Semibold 17, 22 pt lines, #191D2F) and the hint in 13 (18 pt lines, #6A717E) at most 197
 * wide, 2 apart; 20 above, 24 below, 32 at the sides. Straight on the white sheet, no card of its own.
 *
 * Motion: the shield springs in and the copy follows 0.12 s / 0.2 s later, 6 pt up; then the shield floats 4 pt
 * (2.4 s each way) while a hairline ring ripples out of it every 2.6 s. Reduce Motion keeps only a plain fade.
 */
@Composable
private fun RecentActivityEmptyState(modifier: Modifier = Modifier) {
    val reduceMotion = LocalReduceMotion.current
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }

    // SwiftUI `.spring(response: 0.5, dampingFraction: 0.72)`.
    val appear = if (reduceMotion) {
        shooEaseOut<Float>(0.2)
    } else {
        spring<Float>(dampingRatio = 0.72f, stiffness = ((2 * PI / 0.5) * (2 * PI / 0.5)).toFloat())
    }
    val shieldScale by animateFloatAsState(if (shown || reduceMotion) 1f else 0.85f, appear, label = "emptyScale")
    val shieldAlpha by animateFloatAsState(if (shown) 1f else 0f, appear, label = "emptyAlpha")

    var floatY = 0f
    var ripple = 0f
    if (!reduceMotion) {
        val loops = rememberInfiniteTransition(label = "emptyLoops")
        val floating by loops.animateFloat(
            initialValue = 0f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(
                animation = tween(2400, easing = ShooEasing.easeInOut),
                repeatMode = RepeatMode.Reverse,
                initialStartOffset = StartOffset(500, StartOffsetType.Delay),
            ),
            label = "emptyFloat",
        )
        val rippling by loops.animateFloat(
            initialValue = 0f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(
                animation = tween(2600, easing = ShooEasing.easeOut),
                repeatMode = RepeatMode.Restart,
                initialStartOffset = StartOffset(500, StartOffsetType.Delay),
            ),
            label = "emptyRipple",
        )
        floatY = floating
        ripple = rippling
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 32.dp)
            .padding(top = 20.dp, bottom = 24.dp)
            // One TalkBack stop, and the caller's tag lands on one element.
            .semantics(mergeDescendants = true) { },
        verticalArrangement = Arrangement.spacedBy(2.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .size(128.dp)
                .graphicsLayer {
                    scaleX = shieldScale
                    scaleY = shieldScale
                    alpha = shieldAlpha
                }
                .clearAndSetSemantics { },
            contentAlignment = Alignment.Center,
        ) {
            Box(
                Modifier
                    .size(88.dp)
                    .graphicsLayer {
                        val s = 1f + 0.45f * ripple
                        scaleX = s
                        scaleY = s
                        alpha = 0.7f * (1f - ripple)
                    }
                    .border(1.dp, hex(0xC9D2DE), CircleShape),
            )
            Image(
                painter = painterResource(R.drawable.home_empty_shield),
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .size(128.dp)
                    .offset(y = (-4f * floatY).dp),
            )
        }
        Column(
            verticalArrangement = Arrangement.spacedBy(2.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = t("No activity yet"),
                style = onboardingFont(17f, weight = FontWeight.SemiBold, rounded = true, tracking = -0.43f, lineHeight = 22f),
                color = HomeTheme.navy,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .riseIn(shown, reduceMotion, 0.12)
                    .semantics { heading() },
            )
            Text(
                text = t("When a suspicious site shows up, you'll see it here."),
                style = onboardingFont(13f, rounded = true, tracking = -0.08f, lineHeight = 18f),
                color = OnboardingTheme.bodyInk,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .widthIn(max = 197.dp)
                    .riseIn(shown, reduceMotion, 0.2),
            )
        }
    }
}

/** Fades a line in and lifts it 6 pt, `delay` after the shield; under Reduce Motion only the fade. */
@Composable
private fun Modifier.riseIn(shown: Boolean, still: Boolean, delay: Double): Modifier {
    val spec = if (still) shooEaseOut<Float>(0.2) else shooEaseOut<Float>(0.35, delay)
    val alpha by animateFloatAsState(if (shown) 1f else 0f, spec, label = "riseAlpha")
    val lift by animateFloatAsState(if (shown || still) 0f else 6f, spec, label = "riseOffset")
    return graphicsLayer {
        this.alpha = alpha
        translationY = lift * density
    }
}

/** Where "See all" sits: beside the title (own Home) or under the cards as a glass button (family Home). */
enum class SeeAllPlacement { HEADER, BELOW }

/**
 * Figma "Aktivitas Terakhir": the title, then the cards. Family Home adds whose site it was (`showsOwner`).
 * `hasSitesAbove`: the only sites are already on Home above the list (Protected's blocked card): no "nothing yet"
 * message, but "See all" still leads to Activity.
 */
@Composable
fun RecentActivity(
    scans: List<ScanResult>,
    language: AppLanguage,
    onOpen: (ScanResult) -> Unit,
    onSeeAll: () -> Unit,
    modifier: Modifier = Modifier,
    showsOwner: Boolean = false,
    hasSitesAbove: Boolean = false,
    seeAllPlacement: SeeAllPlacement = SeeAllPlacement.HEADER,
) {
    val hasSeeAll = scans.isNotEmpty() || hasSitesAbove
    val hint = t("Opens the details")
    Column(modifier, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        RecentActivityHeader(showsSeeAll = hasSeeAll && seeAllPlacement == SeeAllPlacement.HEADER, onSeeAll = onSeeAll)
        if (scans.isEmpty() && hasSitesAbove) {
            // Nothing: the sites are above.
        } else if (scans.isEmpty()) {
            RecentActivityEmptyState(Modifier.testTag("shield.nothingBlocked"))
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                for (scan in scans) {
                    RecentRow(
                        scan = scan,
                        showsOwner = showsOwner,
                        language = language,
                        modifier = Modifier
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                                role = Role.Button,
                                onClickLabel = hint,
                                onClick = { onOpen(scan) },
                            )
                            .testTag("home.recent.${scan.id}"),
                    )
                }
                if (seeAllPlacement == SeeAllPlacement.BELOW) {
                    GlassSeeAllButton(action = onSeeAll)
                }
            }
        }
    }
}

/**
 * Figma "Aktivitas Terakhir" / "Lihat Semua" (1253:8664, 1253:8665): SF Pro Rounded 17, -1 %, 22 pt lines;
 * the title grey regular, the link blue bold.
 */
@Composable
private fun RecentActivityHeader(showsSeeAll: Boolean, onSeeAll: () -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(
            text = t("Recent activity"),
            style = onboardingFont(17f, rounded = true, tracking = -0.17f, lineHeight = 22f),
            color = OnboardingTheme.bodyInk,
            modifier = Modifier
                .weight(1f)
                .semantics { heading() },
        )
        if (showsSeeAll) {
            // A 22 pt line in Figma; the touch area still reaches 44.
            Text(
                text = t("See all"),
                style = onboardingFont(17f, weight = FontWeight.Bold, rounded = true, tracking = -0.17f, lineHeight = 22f),
                color = dynamicColor(0x175CD3, dark = 0x5EAAF0),
                modifier = Modifier
                    .expandedTouch(12.dp)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        role = Role.Button,
                        onClick = onSeeAll,
                    )
                    .padding(12.dp)
                    .testTag("home.seeAll"),
            )
        }
    }
}

/**
 * Figma "Button - Liquid Glass - Text" (1382:2644): 130 × 50 capsule, 20 × 16 padding, SF Pro Medium 17 (-1 %,
 * 18 pt line), #1A1A1A, centred under the cards. iOS 26 glass → a frosted white capsule.
 */
@Composable
private fun GlassSeeAllButton(action: () -> Unit) {
    val reduceGlass = LocalReduceGlass.current
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Box(
            modifier = Modifier
                .then(
                    if (reduceGlass) {
                        Modifier.background(Color.White, CapsuleShape)
                    } else {
                        Modifier
                            .shooShadow(Color.Black.copy(alpha = 0.08f), radius = 12.dp, y = 4.dp, shape = CapsuleShape)
                            .background(Color.White.copy(alpha = 0.82f), CapsuleShape)
                            .border(1.dp, Color.White.copy(alpha = 0.5f), CapsuleShape)
                    },
                )
                .clip(CapsuleShape)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    role = Role.Button,
                    onClick = action,
                )
                .widthIn(min = 130.dp)
                .heightIn(min = 50.dp)
                .padding(horizontal = 20.dp, vertical = 16.dp)
                .testTag("home.seeAll"),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = t("See all"),
                style = onboardingFont(17f, weight = FontWeight.Medium, tracking = -0.17f, lineHeight = 18f),
                color = HomeTheme.glassInk,
            )
        }
    }
}

/**
 * Figma "Update card" (1128:18725): 48 pt icon, the site in SF Pro Rounded 17 and the time in 13 under it, the chip
 * top right; 82 pt tall.
 */
@Composable
private fun RecentRow(scan: ScanResult, showsOwner: Boolean, language: AppLanguage, modifier: Modifier = Modifier) {
    val accessibilitySize = isAccessibilitySize()
    val badge = ScanBadge.from(scan)
    // Beside the site name these would squeeze it to a few letters ("Penipuan terverifikasi"). At accessibility sizes
    // every chip would, so there it always goes under.
    val badgeGoesBelow = accessibilitySize || badge == ScanBadge.VERIFIED_SCAM || badge == ScanBadge.MARKED_SAFE
    // Figma: "Hari ini · 10.42 WIB" on your own Home, "Syahnaz · Hari ini, 10.42" on the family's.
    val subtitle = if (showsOwner) {
        "${scan.ownerName} · ${Formatters.dayAndTime(scan.detectedAt, language, compact = true)}"
    } else {
        Formatters.dayAndTime(scan.detectedAt, language)
    }

    Row(
        modifier = modifier
            .homeCard()
            .padding(17.dp)
            .semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        SiteIcon(url = scan.faviconUrl?.toString())
        Column(
            modifier = Modifier
                // Figma "stack": 42 pt of text centred on the 48 pt icon.
                .padding(top = 3.dp)
                .weight(1f),
        ) {
            // Figma: a 24 pt row holding the 22 pt line, then the 18 pt line.
            // iOS: truncates in the middle; Compose 1.7 only ends with the ellipsis.
            Text(
                text = scan.domain,
                style = onboardingFont(17f, rounded = true, tracking = -0.17f, lineHeight = 22f),
                color = HomeTheme.navy,
                maxLines = if (accessibilitySize) 3 else 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(vertical = 1.dp),
            )
            Text(
                text = subtitle,
                style = onboardingFont(13f, rounded = true, tracking = -0.08f, lineHeight = 18f),
                color = HomeTheme.rowSubtitle,
                maxLines = if (accessibilitySize) 4 else 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (badgeGoesBelow) {
                HomeStatusChip(badge = badge, modifier = Modifier.padding(top = 8.dp))
            }
        }
        if (!badgeGoesBelow) {
            HomeStatusChip(badge = badge, modifier = Modifier.padding(start = 4.dp))
        }
    }
}

/**
 * Figma chip: pale fill, thin border, coloured text. Words always there, never colour only.
 * `large`: the "Status Badge" on protected/Home (14 pt semibold, 18 pt icon, 13.3 × 10 padding).
 */
@Composable
fun HomeStatusChip(badge: ScanBadge, modifier: Modifier = Modifier, large: Boolean = false) {
    val accessibilitySize = isAccessibilitySize()
    val (text, fill, stroke) = when (badge) {
        ScanBadge.WARNING -> Triple(HomeTheme.warningText, HomeTheme.warningFill, HomeTheme.warningStroke)
        ScanBadge.BLOCKED, ScanBadge.VERIFIED_SCAM -> Triple(HomeTheme.dangerText, HomeTheme.dangerFill, HomeTheme.dangerStroke)
        ScanBadge.MARKED_SAFE -> Triple(hex(0x1B6E35), hex(0xEFFAF2), hex(0xC4EBCF))
    }
    val title = when (badge) {
        ScanBadge.WARNING -> "Caution"
        ScanBadge.BLOCKED -> "Blocked"
        ScanBadge.VERIFIED_SCAM -> "Verified scam"
        ScanBadge.MARKED_SAFE -> "Marked safe"
    }
    // Figma "Button" (1128:18733): the exported 16 pt alert icon, 4 gap, SF Pro Rounded 13 (120 %, -0.04),
    // 8 × 6 padding, 0.75 inside stroke, 28 pt tall.
    Row(
        modifier = modifier
            .background(fill, CapsuleShape)
            .border(if (large) 1.24.dp else 0.75.dp, stroke, CapsuleShape)
            .padding(horizontal = if (large) 13.3.dp else 8.dp, vertical = if (large) 10.dp else 6.dp),
        horizontalArrangement = Arrangement.spacedBy(if (large) 6.6.dp else 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            painter = painterResource(R.drawable.home_alert_circle),
            contentDescription = null,
            tint = text,
            modifier = Modifier.size(if (large) 18.2.dp else 16.dp),
        )
        // At the usual sizes the chip keeps its own width; at accessibility sizes it wraps instead (U-03).
        Text(
            text = t(title),
            style = onboardingFont(
                if (large) 14f else 13f,
                weight = if (large) FontWeight.SemiBold else FontWeight.Normal,
                rounded = !large,
                tracking = -0.04f,
                lineHeight = if (large) 18.2f else 15.6f,
            ),
            color = text,
            maxLines = if (accessibilitySize) 2 else 1,
            softWrap = accessibilitySize,
        )
    }
}

// MARK: - Layout helpers (SwiftUI behaviours Compose lacks)

/**
 * SwiftUI `.padding(.top / .bottom, x)` that may be negative: the view is placed `top` lower and reports its height
 * plus both paddings (never below 0).
 */
private fun Modifier.swiftPadding(top: Dp = 0.dp, bottom: Dp = 0.dp): Modifier = layout { measurable, constraints ->
    val t = top.roundToPx()
    val b = bottom.roundToPx()
    val placeable = measurable.measure(constraints.offset(vertical = -(t + b)))
    val height = constraints.constrainHeight((placeable.height + t + b).coerceAtLeast(0))
    layout(placeable.width, height) { placeable.place(0, t) }
}

/**
 * SwiftUI `.background { … .padding(.top, -top).padding(.bottom, -bottom) }`: with `matchParentSize`, the view is
 * `top + bottom` taller than its parent and starts `top` above it, without changing the parent's size.
 */
private fun Modifier.extendedBy(top: Dp, bottom: Dp): Modifier = layout { measurable, constraints ->
    val t = top.roundToPx()
    val b = bottom.roundToPx()
    val height = constraints.maxHeight + t + b
    val placeable = measurable.measure(Constraints.fixed(constraints.maxWidth, height.coerceAtLeast(0)))
    layout(constraints.maxWidth, constraints.maxHeight) { placeable.place(0, -t) }
}

/**
 * SwiftUI `.background(alignment: .top) { fixedHeightView.padding(.top, top) }`: with `matchParentSize`, the view
 * keeps its own height and is drawn `top` below the parent's top (negative: above), not changing the parent's size.
 */
private fun Modifier.placedFree(top: Dp): Modifier = layout { measurable, constraints ->
    val placeable = measurable.measure(
        Constraints(minWidth = constraints.maxWidth, maxWidth = constraints.maxWidth, minHeight = 0, maxHeight = Constraints.Infinity),
    )
    layout(constraints.maxWidth, constraints.maxHeight) { placeable.place(0, top.roundToPx()) }
}

/** `.contentShape(Rectangle().inset(by: -d))`: the touch area reaches `d` past the view without moving it. Use as `.expandedTouch(d).clickable{}.padding(d)`. */
private fun Modifier.expandedTouch(d: Dp): Modifier = layout { measurable, constraints ->
    val px = d.roundToPx()
    val placeable = measurable.measure(constraints.offset(horizontal = 2 * px, vertical = 2 * px))
    layout(
        (placeable.width - 2 * px).coerceAtLeast(0),
        (placeable.height - 2 * px).coerceAtLeast(0),
    ) { placeable.place(-px, -px) }
}
