package com.shoo.app.features.detail

import androidx.annotation.DrawableRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.shoo.app.R
import com.shoo.app.components.AvatarRing
import com.shoo.app.components.AvatarView
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.HalftoneShield
import com.shoo.app.components.HalftoneShieldSize
import com.shoo.app.components.HalftoneShieldTint
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.SoftPulse
import com.shoo.app.components.figmaCardShadow
import com.shoo.app.components.figmaTextStyle
import com.shoo.app.components.shooShadow
import com.shoo.app.data.ScanResult
import com.shoo.app.data.ScanStatus
import com.shoo.app.data.Verdict
import com.shoo.app.features.activity.activityFont
import com.shoo.app.features.onboarding.OnboardingBackButton
import com.shoo.app.features.shield.HomeTheme
import com.shoo.app.support.t
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The two looks of the Detail hero (Figma "Detail Aktivitas Guardian REVISI PRU" 1252:9850 and "Detail Aktivitas Ortu
 * REVISI PRU" 1211:19924): red for a blocked or confirmed scam, orange for a warning or a site a guardian marked safe.
 */
enum class DetailLook {
    DANGER,
    CAUTION;

    /** Figma "Hero BG": 402 × 360 picture with the rings in it. */
    @get:DrawableRes
    val heroImage: Int
        get() = when (this) {
            DANGER -> R.drawable.detail_hero_red
            CAUTION -> R.drawable.detail_hero_amber
        }

    /** The top row of the picture, carried on above it when the page is pulled down. */
    val topColor: Color
        get() = when (this) {
            DANGER -> DetailStyle.hex(0xFF8A80)
            CAUTION -> DetailStyle.hex(0xFFBD6B)
        }

    val shieldTint: HalftoneShieldTint
        get() = when (this) {
            DANGER -> HalftoneShieldTint.RED
            CAUTION -> HalftoneShieldTint.ORANGE
        }

    /** The link pill: pink with a white rim (danger), white with a grey rim (caution). */
    val pillFill: Color get() = if (this == DANGER) DetailStyle.hex(0xFFF4F2) else Color.White
    val pillStroke: Color get() = if (this == DANGER) Color.White else DetailStyle.hex(0xE2E8F0)
    val pillText: Color get() = if (this == DANGER) DetailStyle.hex(0xB42318) else DetailStyle.ink

    companion object {
        /** iOS `DetailLook(scan:)`. */
        fun from(scan: ScanResult): DetailLook = when (scan.verdict?.value) {
            Verdict.Value.NOT_SAFE -> DANGER
            Verdict.Value.SAFE -> CAUTION
            // #493: an unknown verdict shows the detection status; an unknown status the warning look.
            else -> if (scan.status == ScanStatus.BLOCKED) DANGER else CAUTION
        }
    }
}

/** Where the Figma frames put the hero parts, in points from the top of the 402 pt wide frame. */
object DetailHeroLayout {
    const val width = 402f
    const val imageHeight = 360f
    /** "Sheet": white, 32 pt corners, from y 284. */
    const val sheetTop = 284f
    /** Link pill: 34 pt high at y 266, half on the hero, half on the sheet. */
    const val pillTop = 266f
    /** Back: 50 × 50 at (20, 48). */
    const val backTop = 48f
    /** Big "Shield Kaca Halftone": the 130 × 150 Kaca at (136, 86), i.e. 1.25 × `HalftoneShield`. */
    const val shieldScale = 1.25f
    val shieldKacaCenter = Offset(201f, 161f)
    /** "Guardian Virellia": 148.29 pt circle at (121, 84). */
    const val avatarSize = 148.29f
    val avatarCenter = Offset(121f + 148.29f / 2, 84f + 148.29f / 2)
    /** The small shield on the avatar's lower right: Kaca 53.13 × 61.3 at (223.35, 179). */
    const val badgeScale = 53.13f / 104f
    val badgeKacaCenter = Offset(223.35f + 53.13f / 2, 179f + 61.3f / 2)
    /** `HalftoneShield`'s Kaca centre sits 0.33 pt above the middle of its 220 × 176 frame. */
    const val kacaRise = 0.33f
}

/**
 * Rings, the shield (or the deciding guardian's avatar with a small shield) and the back button.
 * `guardianAvatarId`: the guardian who decided, on the protected person's own Detail (Figma "Guardian Virellia").
 */
@Composable
fun DetailHero(look: DetailLook, guardianAvatarId: String? = null, onBack: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .height(DetailHeroLayout.sheetTop.dp),
    ) {
        // Laid out on the 402 pt Figma frame and kept in the middle of wider or narrower screens.
        Box(
            Modifier
                .fillMaxWidth()
                .wrapContentWidth(Alignment.CenterHorizontally, unbounded = true)
                .width(DetailHeroLayout.width.dp)
                .height(DetailHeroLayout.sheetTop.dp)
                .clearAndSetSemantics { },
        ) {
            if (guardianAvatarId != null) {
                val side = DetailHeroLayout.avatarSize
                AvatarView(
                    id = guardianAvatarId,
                    size = side.dp,
                    modifier = Modifier
                        .offset((DetailHeroLayout.avatarCenter.x - side / 2).dp, (DetailHeroLayout.avatarCenter.y - side / 2).dp)
                        // Figma: #0D7380 25 %, y 11.7, blur 31.2.
                        .shooShadow(DetailStyle.hex(0x0D7380).copy(alpha = 0.25f), radius = 15.6.dp, y = 11.7.dp, shape = CircleShape),
                )
                HeroShield(look, DetailHeroLayout.badgeScale, DetailHeroLayout.badgeKacaCenter)
            } else {
                HeroShield(look, DetailHeroLayout.shieldScale, DetailHeroLayout.shieldKacaCenter)
            }
        }
        OnboardingBackButton(
            action = onBack,
            modifier = Modifier.padding(start = 20.dp, top = DetailHeroLayout.backTop.dp),
            identifier = "detail.back",
        )
    }
}

/** `HalftoneShield` scaled by `scale`, its frame centred on `kacaCenter` (iOS `.scaleEffect(_:).position(_:)`). */
@Composable
private fun HeroShield(look: DetailLook, scale: Float, kacaCenter: Offset) {
    val width = HalftoneShieldSize.width.value
    val height = HalftoneShieldSize.height.value
    Box(
        Modifier
            .offset((kacaCenter.x - width / 2).dp, (kacaCenter.y + DetailHeroLayout.kacaRise * scale - height / 2).dp)
            .size(HalftoneShieldSize)
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
            },
    ) {
        HalftoneShield(tint = look.shieldTint)
    }
}

/**
 * "bca-verifikasi.site/login": 17 pt in a 34 pt capsule with a 1 pt outside rim. Cut at the tail, not the middle
 * (BH-13): the text starts with the scan's `domain` (`DetailView.shownLink`), so a long path is what gets cut, never
 * the domain.
 */
@Composable
fun DetailLinkPill(look: DetailLook, text: String, modifier: Modifier = Modifier) {
    Box(
        modifier
            .padding(horizontal = 24.dp)
            .drawBehind {
                val rim = 1.dp.toPx()
                drawRoundRect(
                    look.pillStroke,
                    topLeft = Offset(-rim, -rim),
                    size = Size(size.width + 2 * rim, size.height + 2 * rim),
                    cornerRadius = CornerRadius((size.height + 2 * rim) / 2),
                )
            }
            .background(look.pillFill, CapsuleShape)
            .heightIn(min = 34.dp)
            .padding(horizontal = 10.dp, vertical = 6.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            style = figmaTextStyle(17f, lineHeight = 22f),
            color = look.pillText,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/**
 * Figma "Bar" under "92/100": one hatched segment per reason (by weight), a tick at the score, then the grey track.
 * 153 pt wide, 1.5 pt apart.
 */
object RiskScoreBar {
    /** The weights scaled so they add up to the score: the tick sits at the score, the track shows the rest. */
    fun scaled(score: Int, weights: List<Int>): List<Int> {
        val total = weights.sumOf { max(it, 0) }
        if (total <= 0) return emptyList()
        val target = min(max(score, 0), 100).toDouble()
        return weights.map { (max(it, 0).toDouble() * target / total).roundToInt() }
    }
}

@Composable
fun RiskScoreBar(score: Int, weights: List<Int>, modifier: Modifier = Modifier) {
    Box(modifier.width(153.dp).height(18.dp), contentAlignment = Alignment.Center) {
        ContributionBar(
            weights = RiskScoreBar.scaled(score, weights),
            style = ContributionBar.Style.score,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** "Status situs" chip: Diblokir (red), Waspada (orange), Blokir Dibuka / Ditandai aman (blue). */
object DetailStatusChip {
    enum class Kind { BLOCKED, WARNING, UNBLOCKED, MARKED_SAFE }
}

@Composable
fun DetailStatusChip(kind: DetailStatusChip.Kind, modifier: Modifier = Modifier) {
    val title = when (kind) {
        DetailStatusChip.Kind.BLOCKED -> "Blocked"
        DetailStatusChip.Kind.WARNING -> "detail.status.warning"
        DetailStatusChip.Kind.UNBLOCKED -> "detail.status.unblocked"
        DetailStatusChip.Kind.MARKED_SAFE -> "Marked safe"
    }
    val (fill, stroke, text) = when (kind) {
        DetailStatusChip.Kind.BLOCKED -> Triple(HomeTheme.dangerFill, HomeTheme.dangerStroke, HomeTheme.dangerText)
        // Figma #D67D00 is 2.9:1 on its chip; the darker Home warning text keeps 4.5:1.
        DetailStatusChip.Kind.WARNING -> Triple(DetailStyle.hex(0xFFF8EF), DetailStyle.hex(0xFFE0B8), HomeTheme.warningText)
        DetailStatusChip.Kind.UNBLOCKED, DetailStatusChip.Kind.MARKED_SAFE ->
            Triple(DetailStyle.hex(0xDEF4FF), DetailStyle.hex(0x94DBFE), HomeTheme.action)
    }
    Box(
        modifier
            .background(fill, CapsuleShape)
            .border(1.dp, stroke, CapsuleShape)
            .heightIn(min = 33.dp)
            .padding(horizontal = 16.dp, vertical = 6.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            t(title),
            style = figmaTextStyle(15f, rounded = true, lineHeight = 21f),
            color = text,
            maxLines = 1,
            softWrap = false,
        )
    }
}

/** "Syahnaz" with their avatar, under "Profil yang mengakses" (Figma "Profil Dilindungi", 42 pt). */
@Composable
fun DetailOwnerChip(name: String, avatarId: String?, modifier: Modifier = Modifier) {
    Row(
        modifier
            .figmaCardShadow(CapsuleShape)
            .background(DetailStyle.hex(0xE7EFF8), CapsuleShape)
            .border(1.dp, DetailStyle.hex(0xAAD2FF), CapsuleShape)
            .heightIn(min = 42.dp)
            .padding(start = 8.dp, end = 16.dp, top = 8.dp, bottom = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // null (family list not loaded or failed): the neutral person.
        AvatarView(id = avatarId ?: "", size = 24.dp, ring = AvatarRing(color = Color.White.copy(alpha = 0.5f)))
        Text(
            name,
            style = figmaTextStyle(16f, FontWeight.SemiBold, rounded = true, tracking = -0.31f, lineHeight = 21f),
            color = DetailStyle.title,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/**
 * Figma "Hero BG" brought to life: the rings in the picture breathe around their centre and soft white discs grow out
 * of the shield and fade (the Home hero's `SoftPulse`), both on a 4 s beat. Reduce Motion keeps the still picture.
 */
object DetailHeroBackground {
    /** Centre of the rings in the 402 × 360 picture (inner ring x 72–330, y 41–300). */
    const val ringCenterY = 170f
    const val period = 4.0
    /** The rings grow by this much at the top of a breath: kept subtle on a warning screen. */
    const val breathScale = 0.012f
}

@Composable
fun DetailHeroBackground(look: DetailLook, modifier: Modifier = Modifier) {
    val reduceMotion = LocalReduceMotion.current
    val height = DetailHeroLayout.imageHeight
    var time by remember { mutableDoubleStateOf(0.0) }
    LaunchedEffect(reduceMotion) {
        if (reduceMotion) {
            time = 0.0
            return@LaunchedEffect
        }
        while (true) withFrameNanos { time = it / 1_000_000_000.0 }
    }
    Box(
        modifier
            .fillMaxWidth()
            .height(height.dp)
            // Its top colour carries on above the picture when the page is pulled down (iOS rubber band).
            .drawBehind {
                val extra = 400.dp.toPx()
                drawRect(look.topColor, topLeft = Offset(0f, -extra), size = Size(size.width, extra))
            }
            .clearAndSetSemantics { },
    ) {
        Box(Modifier.fillMaxSize().clipToBounds()) {
            Image(
                painter = painterResource(look.heroImage),
                contentDescription = null,
                contentScale = ContentScale.FillBounds,
                modifier = Modifier
                    .fillMaxSize()
                    .graphicsLayer {
                        val breath = ((1 - cos(time * 2 * PI / DetailHeroBackground.period)) / 2).toFloat()
                        val scale = 1 + DetailHeroBackground.breathScale * breath
                        scaleX = scale
                        scaleY = scale
                        transformOrigin = TransformOrigin(0.5f, DetailHeroBackground.ringCenterY / height)
                    },
            )
            if (!reduceMotion) {
                SoftPulse(
                    smallest = 140.dp,
                    largest = 420.dp,
                    peak = 0.1f,
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .offset(y = (DetailHeroBackground.ringCenterY - 210f).dp)
                        .wrapContentSize(Alignment.Center, unbounded = true),
                )
            }
        }
    }
}

