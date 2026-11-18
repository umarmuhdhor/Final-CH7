package com.shoo.app.features.detail

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.layout
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.ShooEasing
import com.shoo.app.components.figmaCardShadow
import com.shoo.app.components.figmaTextStyle
import com.shoo.app.components.shooShadow
import com.shoo.app.features.activity.activityFont
import com.shoo.app.support.L10n
import com.shoo.app.support.t
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * What kind of signal a reason is, for "Sinyal: …" and the tag on the photo (Figma "Formulir sensitif",
 * "Logo tiruan"). Ids from contracts/detector-interface.md; an unknown id still gets a name.
 */
enum class SignalKind {
    SENSITIVE_FORM,
    COPIED_LOGO,
    LOOKALIKE_DOMAIN,
    BRAND_IN_ADDRESS,
    CHEAP_ENDING,
    SUSPICIOUS_LINK,
    NEW_DOMAIN,
    URGENT_WORDING,
    UNUSUAL_REQUEST,
    HOAX,
    KNOWN_SCAM,
    OTHER;

    /** Catalog key of the kind's name. */
    val title: String
        get() = when (this) {
            SENSITIVE_FORM -> "signal.sensitiveForm"
            COPIED_LOGO -> "signal.copiedLogo"
            LOOKALIKE_DOMAIN -> "signal.lookalikeDomain"
            BRAND_IN_ADDRESS -> "signal.brandInAddress"
            CHEAP_ENDING -> "signal.cheapEnding"
            SUSPICIOUS_LINK -> "signal.suspiciousLink"
            NEW_DOMAIN -> "signal.newDomain"
            URGENT_WORDING -> "signal.urgentWording"
            UNUSUAL_REQUEST -> "signal.unusualRequest"
            HOAX -> "signal.hoax"
            KNOWN_SCAM -> "signal.knownScam"
            OTHER -> "signal.other"
        }

    /** Only these point at something on the page; the rest show the photo plain (Figma "Tanpa highlight"). */
    val isOnPage: Boolean
        get() = when (this) {
            SENSITIVE_FORM, COPIED_LOGO, URGENT_WORDING, UNUSUAL_REQUEST, HOAX -> true
            else -> false
        }

    companion object {
        /** iOS `SignalKind(signalId:)`. */
        fun from(signalId: String): SignalKind = when {
            signalId.startsWith("asks_") -> SENSITIVE_FORM
            signalId == "brand_logo_offsite" -> COPIED_LOGO
            signalId == "lookalike_domain" -> LOOKALIKE_DOMAIN
            signalId == "brand_plus_keyword" -> BRAND_IN_ADDRESS
            signalId == "cheap_tld" -> CHEAP_ENDING
            signalId == "suspicious_link" -> SUSPICIOUS_LINK
            signalId == "new_domain" -> NEW_DOMAIN
            signalId == "urgent_language" -> URGENT_WORDING
            signalId == "unreasonable_request" -> UNUSUAL_REQUEST
            signalId == "hoax_claim" -> HOAX
            signalId == "db_match" -> KNOWN_SCAM
            else -> OTHER
        }
    }
}

// MARK: Contribution bar

/**
 * Figma "Progres Risiko": one segment per reason up to this card, a tick at the running total, then the hatched
 * rest. Widths follow the weights; the total never passes 100 % (`score = min(100, Σ)`).
 */
object ContributionBar {
    /** Spacing and hatching of the two Figma bars (dp). */
    data class Style(
        val gap: Float,
        val tickWidth: Float,
        val tickRadius: Float,
        val hatchPitch: Float,
        val hatchWidth: Float,
        val shadowRadius: Float,
        val shadowY: Float,
    ) {
        companion object {
            /** The evidence card's bar: 3 pt apart, 2.5 pt tick, hatching every 5 pt. */
            val card = Style(gap = 3f, tickWidth = 2.5f, tickRadius = 1.25f, hatchPitch = 5f, hatchWidth = 1.2f, shadowRadius = 4f, shadowY = 3f)
            /** The "Penilaian Risiko Shoo" bar (1252:2047): 1.5 pt apart, 2 pt tick, 0.6 pt hatching every 2.48 pt,
             * shadow blur 4 at y 1.5. */
            val score = Style(gap = 1.5f, tickWidth = 2f, tickRadius = 0.625f, hatchPitch = 2.48f, hatchWidth = 0.6f, shadowRadius = 2f, shadowY = 1.5f)
        }
    }

    /** Fractions of the bar per segment, capped so their sum is at most 1. */
    fun fractions(weights: List<Int>): List<Double> {
        var left = 100.0
        return weights.map { weight ->
            val part = min(max(weight, 0).toDouble(), left)
            left -= part
            part / 100
        }
    }
}

/** `weights`: this card's reason and every heavier one before it, in order. 10 dp tall; the tick overhangs it. */
@Composable
fun ContributionBar(weights: List<Int>, style: ContributionBar.Style = ContributionBar.Style.card, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.height(10.dp).clearAndSetSemantics { }) {
        val fractions = ContributionBar.fractions(weights)
        val gaps = (fractions.size + 1) * style.gap + style.tickWidth
        val usable = max(0f, maxWidth.value - gaps)
        Row(
            Modifier
                .fillMaxWidth()
                .wrapContentHeight(Alignment.Top, unbounded = true)
                .height(16.dp)
                .offset(y = (-3).dp),
            horizontalArrangement = Arrangement.spacedBy(style.gap.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            fractions.forEachIndexed { index, fraction ->
                HatchedCapsule(
                    fill = DetailStyle.segments[min(index, DetailStyle.segments.size - 1)],
                    hatch = Color.White.copy(alpha = 0.3f),
                    pitch = style.hatchPitch,
                    lineWidth = style.hatchWidth,
                    modifier = Modifier
                        .width((usable * fraction).toFloat().dp)
                        .shooShadow(
                            DetailStyle.barTick.copy(alpha = 0.35f),
                            radius = style.shadowRadius.dp,
                            y = style.shadowY.dp,
                            shape = CapsuleShape,
                        ),
                )
            }
            Box(
                Modifier
                    .width(style.tickWidth.dp)
                    .height(16.dp)
                    .background(DetailStyle.barTick, RoundedCornerShape(style.tickRadius.dp)),
            )
            HatchedCapsule(
                fill = DetailStyle.barTrack,
                hatch = DetailStyle.barTrackHatch,
                pitch = style.hatchPitch,
                lineWidth = style.hatchWidth,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

/** 10 pt capsule with 45° hatching (Figma "Hatch"). */
@Composable
private fun HatchedCapsule(fill: Color, hatch: Color, modifier: Modifier = Modifier, pitch: Float = 5f, lineWidth: Float = 1.2f) {
    Box(
        modifier
            .height(10.dp)
            .clip(CapsuleShape)
            .background(fill)
            .drawBehind {
                val step = pitch.dp.toPx()
                // Figma draws each line over half the bar height ("M 0 10 L 4.96 0", every 2.48).
                val run = if (pitch == 5f) size.height else step * 2
                var x = -run
                while (x < size.width + run) {
                    drawLine(hatch, Offset(x, size.height), Offset(x + run, 0f), strokeWidth = lineWidth.dp.toPx())
                    x += step
                }
            },
    )
}

// MARK: Loading page

private object PageScan {
    const val period = 2.4
    const val bandHeight = 46f
    const val travel = 196f
    val bar = DetailStyle.hex(0xDDE6F1)
    val line = DetailStyle.hex(0x1A73D9)
    val band = DetailStyle.hex(0x4FB4F2)
    /** Blocks of the empty page: x, y, width, height. */
    val blocks = listOf(
        Rect(16f, 22f, 16f + 120f, 22f + 12f),
        Rect(16f, 44f, 16f + 238f, 44f + 70f),
        Rect(16f, 126f, 16f + 200f, 126f + 9f),
        Rect(16f, 142f, 16f + 226f, 142f + 9f),
        Rect(16f, 158f, 16f + 170f, 158f + 9f),
        Rect(16f, 174f, 16f + 214f, 174f + 9f),
    )
}

/** While the page loads: an empty page that a blue line scans down and up (2.4 s). Reduce Motion keeps the empty
 * page without the line. */
@Composable
private fun PageScanPlaceholder(pageWidth: Float, topInset: Float) {
    val reduceMotion = LocalReduceMotion.current
    var time by remember { mutableDoubleStateOf(0.0) }
    LaunchedEffect(reduceMotion) {
        if (reduceMotion) return@LaunchedEffect
        while (true) withFrameNanos { time = it / 1_000_000_000.0 }
    }
    val label = t("Loading")
    Box(
        Modifier
            .fillMaxSize()
            .clearAndSetSemantics { contentDescription = label },
        contentAlignment = Alignment.TopCenter,
    ) {
        Canvas(
            Modifier
                .offset(y = topInset.dp)
                .size(pageWidth.dp, EvidencePhoto.height.dp),
        ) {
            clipRect {
                drawRoundRect(Color.White, cornerRadius = CornerRadius(10.8.dp.toPx()))
                for (block in PageScan.blocks) {
                    drawRoundRect(
                        PageScan.bar,
                        topLeft = Offset(block.left.dp.toPx(), block.top.dp.toPx()),
                        size = Size(block.width.dp.toPx(), block.height.dp.toPx()),
                        cornerRadius = CornerRadius(4.dp.toPx()),
                    )
                }
                if (!reduceMotion) {
                    val turn = (time % PageScan.period) / PageScan.period
                    val top = (abs(sin(turn * PI)) * PageScan.travel - PageScan.bandHeight).toFloat().dp.toPx()
                    val bandHeight = PageScan.bandHeight.dp.toPx()
                    drawRect(
                        Brush.verticalGradient(
                            listOf(PageScan.band.copy(alpha = 0f), PageScan.band.copy(alpha = 0.38f)),
                            startY = top,
                            endY = top + bandHeight,
                        ),
                        topLeft = Offset(0f, top),
                        size = Size(size.width, bandHeight),
                    )
                    drawRect(PageScan.line, topLeft = Offset(0f, top + bandHeight - 2.dp.toPx()), size = Size(size.width, 2.dp.toPx()))
                }
            }
        }
    }
}

// MARK: Photo

/**
 * Figma "Bukti" (416:10831): the page on a pale panel. One area on the page gets the white spotlight with a tag
 * ("Spotlight (default)"); several areas get yellow outlines with numbers ("Spotlight + kuning"); none shows the
 * photo plain ("Tanpa highlight"). Red stays for risk status only.
 */
object EvidencePhoto {
    const val height = 212f
    /** "Halaman": 270 pt wide, 10 pt from the top, 10.8 pt corners. */
    const val pageWidth = 270f
    const val pageInset = 10f
    /** Room kept above and below an area: its outline, the glow and the tag over its top edge. */
    const val areaMargin = 30f

    data class Layout(val origin: Offset, val scale: Float, val pageHeight: Float, val pageWidth: Float)

    /**
     * Where the page sits, how big it is and how far it scrolls so the first area is in view. An area taller than the
     * panel shrinks the page until it fits whole, outline and tag included (never cut off). Image size in its own
     * units (only its aspect counts unless `cssWidth` is null), everything else in dp.
     */
    fun layout(imageSize: Size, cssWidth: Float?, highlights: List<Rect>, panelWidth: Float): Layout {
        val fullScale = pageWidth / max(cssWidth ?: imageSize.width, 1f)
        val room = height - 2 * areaMargin
        // The outline sits 4 pt outside the area on each side, at every size.
        val fit = highlights.firstOrNull()?.let { min(1f, max(room - 8f, 1f) / max(it.height * fullScale, 1f)) } ?: 1f
        val width = pageWidth * fit
        val pageHeight = imageSize.height * width / max(imageSize.width, 1f)
        val scale = fullScale * fit
        val maxShift = max(0f, pageHeight + pageInset - height)
        // The area sits a little below the middle, leaving the tag above it room.
        val target = height / 2 + Spotlight.tagHeight / 2
        val shift = highlights.firstOrNull()?.let { min(max(0f, it.center.y * scale + pageInset - target), maxShift) } ?: 0f
        return Layout(Offset((panelWidth - width) / 2, pageInset - shift), scale, pageHeight, width)
    }
}

/**
 * `image`: the page (the page copy's picture, or an old build's screenshot). `highlights`: areas to light up, in page
 * CSS px; empty = plain photo. `pageCSSWidth`: width of the page in CSS px, when it differs from the image's width.
 */
@Composable
fun EvidencePhoto(
    image: ImageBitmap?,
    highlights: List<Rect> = emptyList(),
    pageCSSWidth: Float? = null,
    tag: String? = null,
    isLoading: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val panel = RoundedCornerShape(12.dp)
    Box(
        modifier
            .fillMaxWidth()
            .height(EvidencePhoto.height.dp)
            .clip(panel)
            .background(DetailStyle.photoFill)
            .border(1.dp, DetailStyle.photoStroke, panel),
    ) {
        // Scan placeholder → the page copy: a 0.2 s cross-fade, gentle enough for Reduce Motion.
        Crossfade(
            targetState = image != null,
            animationSpec = tween(200, easing = ShooEasing.easeOut),
            label = "evidencePhoto",
        ) { hasImage ->
            if (hasImage && image != null) {
                EvidencePage(image, highlights, pageCSSWidth, tag)
            } else if (isLoading) {
                PageScanPlaceholder(EvidencePhoto.pageWidth, EvidencePhoto.pageInset)
            } else {
                Box(Modifier.fillMaxSize())
            }
        }
    }
}

@Composable
private fun EvidencePage(image: ImageBitmap, highlights: List<Rect>, pageCSSWidth: Float?, tag: String?) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val panelWidth = maxWidth.value
        val layout = EvidencePhoto.layout(
            Size(image.width.toFloat(), image.height.toFloat()), pageCSSWidth, highlights, panelWidth,
        )
        val holes = highlights.map { rect ->
            Rect(
                left = layout.origin.x + rect.left * layout.scale - 4f,
                top = layout.origin.y + rect.top * layout.scale - 4f,
                right = layout.origin.x + rect.right * layout.scale + 4f,
                bottom = layout.origin.y + rect.bottom * layout.scale + 4f,
            )
        }
        val pageShape = RoundedCornerShape(10.8.dp)
        Image(
            bitmap = image,
            contentDescription = null,
            contentScale = ContentScale.FillBounds,
            modifier = Modifier
                .offset(layout.origin.x.dp, layout.origin.y.dp)
                .wrapContentSize(Alignment.TopStart, unbounded = true)
                .size(layout.pageWidth.dp, layout.pageHeight.dp)
                .shooShadow(DetailStyle.pageShadow.copy(alpha = 0.08f), radius = 7.5.dp, y = 4.3.dp, shape = pageShape)
                .clip(pageShape),
        )
        if (holes.isNotEmpty()) {
            Spotlight(holes = holes, size = Size(panelWidth, maxHeight.value), tag = if (holes.size == 1) tag else null)
        }
    }
}

// MARK: Spotlight

/**
 * Dim everything but the holes (#0B1A2E at 50 %). One hole: red outline, soft white glow, white tag at its top
 * right. Several: yellow outlines (#FFD60A) with a numbered dot at each top left. `holes` and `size` in dp.
 */
object Spotlight {
    /** The tag's capsule: 13 pt text with 3 pt above and below. */
    const val tagHeight = 22f
}

@Composable
fun Spotlight(holes: List<Rect>, size: Size, tag: String?, modifier: Modifier = Modifier) {
    val numbered = holes.size > 1
    // Figma "Highlight" (1252:2138): #E5483B, 2 pt, with a white 55 % glow (blur 8).
    val outline = if (numbered) DetailStyle.marker else DetailStyle.barTick
    val glow = if (numbered) DetailStyle.marker.copy(alpha = 0.5f) else Color.White.copy(alpha = 0.55f)
    Box(modifier.fillMaxSize().clearAndSetSemantics { }) {
        Canvas(Modifier.fillMaxSize()) {
            val corner = 8.dp.toPx()
            val dim = Path().apply {
                fillType = PathFillType.EvenOdd
                // Past the edges, so no undimmed strip shows at a rounded edge; the card clips it to its panel.
                addRect(Rect(-size.width.dp.toPx(), -size.height.dp.toPx(), 2 * size.width.dp.toPx(), 2 * size.height.dp.toPx()))
                for (hole in holes) {
                    addRoundRect(
                        RoundRect(
                            hole.left.dp.toPx(), hole.top.dp.toPx(), hole.right.dp.toPx(), hole.bottom.dp.toPx(),
                            CornerRadius(corner),
                        ),
                    )
                }
            }
            drawPath(dim, DetailStyle.spotlight.copy(alpha = 0.5f))
            drawIntoCanvas { canvas ->
                val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                    style = android.graphics.Paint.Style.STROKE
                    strokeWidth = 2.dp.toPx()
                    color = outline.toArgb()
                    setShadowLayer(((4.dp.toPx() - 0.5f) / 0.57735f).coerceAtLeast(0.01f), 0f, 0f, glow.toArgb())
                }
                for (hole in holes) {
                    canvas.nativeCanvas.drawRoundRect(
                        hole.left.dp.toPx(), hole.top.dp.toPx(), hole.right.dp.toPx(), hole.bottom.dp.toPx(),
                        corner, corner, paint,
                    )
                }
            }
        }
        if (numbered) {
            holes.forEachIndexed { index, hole ->
                Box(
                    Modifier
                        .offset((hole.left - 9f).dp, (hole.top - 9f).dp)
                        .size(18.dp)
                        .background(DetailStyle.marker, CircleShape)
                        .border(1.5.dp, Color.White, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("${index + 1}", style = activityFont(10f, FontWeight.SemiBold), color = DetailStyle.title, maxLines = 1)
                }
            }
        }
        val first = holes.firstOrNull()
        if (tag != null && first != null) {
            // Right edge 7.7 pt past the outline (Figma); the tag sits wholly above the outline so it never covers
            // what is marked (Figma let it overlap by half, which hid the first line of text).
            Text(
                tag,
                style = activityFont(13f, FontWeight.SemiBold),
                color = DetailStyle.title,
                maxLines = 1,
                softWrap = false,
                modifier = Modifier
                    .layout { measurable, _ ->
                        val placeable = measurable.measure(Constraints())
                        layout(0, 0) {
                            placeable.place(
                                x = (first.right + 7.7f).dp.roundToPx() - placeable.width,
                                y = (first.top - Spotlight.tagHeight - 3f).dp.roundToPx(),
                            )
                        }
                    }
                    .shooShadow(DetailStyle.pageShadow.copy(alpha = 0.15f), radius = 1.5.dp, y = 1.dp, shape = CapsuleShape)
                    .background(Color.White, CapsuleShape)
                    .padding(horizontal = 7.dp, vertical = 3.dp),
            )
        }
    }
}

// MARK: Carousel

/**
 * DT-04: a reason with several marks (an unusual request in many places, say): one photo per mark, swiped sideways,
 * each centred on its own mark with the single-area spotlight. Dots under the photo say how many.
 */
object EvidenceCarousel {
    /** `page` kept inside `0 until count` (0 when there are no marks). */
    fun clampedPage(page: Int, count: Int): Int = min(max(page, 0), max(count - 1, 0))

    /** "Screenshot of the page, 1 of 3". */
    fun spoken(index: Int, count: Int, language: com.shoo.app.support.AppLanguage): String {
        val photo = L10n.string("Screenshot of the page", language)
        return L10n.string("%@, %lld of %lld", language, photo, index + 1, count)
    }
}

@Composable
fun EvidenceCarousel(
    image: ImageBitmap,
    highlights: List<Rect>,
    pageCSSWidth: Float? = null,
    tag: String? = null,
    modifier: Modifier = Modifier,
) {
    val language = LocalAppLanguage.current
    val count = highlights.size
    // The marks can change under the open card (the copy replaces the screenshot, "Try again", a saved copy): the
    // pager clamps its page to the new count, so it never shows a blank page with no dot lit.
    val pager = rememberPagerState { count }
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        HorizontalPager(
            state = pager,
            modifier = Modifier
                .fillMaxWidth()
                .height(EvidencePhoto.height.dp),
        ) { index ->
            val rect = highlights.getOrNull(index)
            if (rect != null) {
                val spoken = EvidenceCarousel.spoken(index, count, language)
                EvidencePhoto(
                    image = image,
                    highlights = listOf(rect),
                    pageCSSWidth = pageCSSWidth,
                    tag = tag,
                    // Keeps the panel's outline clear of the page edge.
                    modifier = Modifier
                        .padding(horizontal = 1.dp)
                        .clearAndSetSemantics {
                            contentDescription = spoken
                            role = Role.Image
                            testTag = "detail.screenshot"
                        },
                )
            }
        }
        val current = EvidenceCarousel.clampedPage(pager.currentPage, count)
        // Page dots: the current one wide and dark (Figma page-control look on a light card).
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.clearAndSetSemantics { }) {
            for (index in 0 until count) {
                val width by animateDpAsState(
                    if (index == current) 16.dp else 6.dp,
                    tween(200, easing = ShooEasing.easeOut),
                    label = "carouselDot",
                )
                Box(
                    Modifier
                        .size(width, 6.dp)
                        .background(
                            if (index == current) DetailStyle.title else DetailStyle.secondary.copy(alpha = 0.35f),
                            CapsuleShape,
                        ),
                )
            }
        }
    }
}

// MARK: Unmarked

/**
 * DT-04: an on-page reason Shoo can't point at on the copy of the page (its field or text isn't shown, e.g. a form
 * inside a hidden login box). Same panel as `AddressEvidence`, with one line instead of an unmarked photo.
 */
@Composable
fun UnmarkedEvidence(kind: SignalKind, modifier: Modifier = Modifier) {
    val panel = RoundedCornerShape(12.dp)
    val text = t("Shoo can't point to this on the page: it may be hidden")
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = AddressEvidence.height.dp)
            .clip(panel)
            .background(DetailStyle.photoFill)
            .border(1.dp, DetailStyle.photoStroke, panel)
            .clearAndSetSemantics { contentDescription = text }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SfSymbol("eye.slash", pointSize = 15f, tint = DetailStyle.secondary)
        Text(text, style = activityFont(15f), color = DetailStyle.secondary, textAlign = TextAlign.Center)
    }
}

// MARK: Card

object EvidenceCard {
    /** On-page reason, page copy shown, and no mark for it: a photo would point at nothing. */
    fun showsUnmarkedNote(kind: SignalKind, highlights: List<Rect>, hasImage: Boolean, marksKnown: Boolean): Boolean =
        kind.isOnPage && marksKnown && hasImage && highlights.isEmpty()
}

/**
 * Figma "Evidence Card" (1252:2114, REVISI PRU): photo, reason, "Sinyal: …" on a pale card.
 * `highlights`: where this reason sits on `image`, in page CSS px; null = the reason's own marks.
 * `domain`: the scan's `domain` (registrable domain, or the full host on a shared platform, #495): a reason about the
 * address shows it instead of the page (DT-04).
 * `marksKnown`: the page copy is on screen with its marks: an on-page reason with no mark there points at nothing
 * visible (a field inside a hidden login box, say), so the card says so instead of showing an unmarked page.
 */
@Composable
fun EvidenceCard(
    reason: Evidence,
    image: ImageBitmap?,
    highlights: List<Rect>? = null,
    isLoadingImage: Boolean,
    pageCSSWidth: Float? = null,
    domain: String? = null,
    marksKnown: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val language = LocalAppLanguage.current
    val shape = RoundedCornerShape(16.dp)
    val kindTitle = L10n.string(reason.kind.title, language)
    Column(
        modifier
            .fillMaxWidth()
            .figmaCardShadow(shape)
            .background(DetailStyle.cardFill, shape)
            .border(1.dp, Color.White.copy(alpha = 0.9f), shape)
            .padding(start = 12.dp, end = 12.dp, top = 12.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (reason.kind.isAddress && domain != null) {
            AddressEvidence(
                domain = domain,
                kind = reason.kind,
                reasonText = reason.text,
                host = reason.host,
                modifier = Modifier.tagged("detail.address.${reason.index}"),
            )
        } else if (EvidenceCard.showsUnmarkedNote(reason.kind, highlights ?: reason.highlights, image != null, marksKnown)) {
            UnmarkedEvidence(reason.kind, Modifier.tagged("detail.unmarked.${reason.index}"))
        } else if (image != null || isLoadingImage) {
            // Not tappable: the card already shows the part that matters, with its marks (no full screen view).
            // Several marks: one photo per mark in a carousel, each centred on its own mark, so none is cut.
            val marks = if (reason.kind.isOnPage) highlights ?: reason.highlights else emptyList()
            if (marks.size > 1 && image != null) {
                EvidenceCarousel(
                    image = image,
                    highlights = marks,
                    pageCSSWidth = pageCSSWidth,
                    tag = kindTitle,
                    modifier = Modifier.tagged("detail.carousel.${reason.index}"),
                )
            } else {
                val label = t("Screenshot of the page")
                EvidencePhoto(
                    image = image,
                    highlights = marks,
                    pageCSSWidth = pageCSSWidth,
                    tag = kindTitle,
                    isLoading = isLoadingImage,
                    modifier = Modifier.clearAndSetSemantics {
                        contentDescription = label
                        role = Role.Image
                        testTag = "detail.screenshot"
                    },
                )
            }
        }
        // Figma "Keterangan": the reason, then "Sinyal: …", 4 pt apart and 4 pt in.
        val spoken = reason.spokenLine(language)
        val signalLabel = t("Signal:")
        Column(
            Modifier
                .padding(horizontal = 4.dp)
                .clearAndSetSemantics {
                    contentDescription = spoken
                    testTag = "detail.evidence.${reason.index}"
                },
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                reason.text,
                style = figmaTextStyle(17f, FontWeight.SemiBold, lineHeight = 22f),
                color = DetailStyle.title,
            )
            Text(
                buildAnnotatedString {
                    withStyle(SpanStyle(color = DetailStyle.secondary)) { append(signalLabel) }
                    append(" ")
                    withStyle(SpanStyle(color = DetailStyle.title)) { append(kindTitle) }
                },
                style = figmaTextStyle(17f, rounded = true, lineHeight = 23.8f),
            )
        }
    }
}

/** A test tag only, keeping the element's own semantics (iOS `.accessibilityIdentifier`). */
internal fun Modifier.tagged(tag: String): Modifier = semantics { testTag = tag }
