package com.shoo.app.features.profile

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.LinearGradientShader
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.Shader
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.shoo.app.R
import com.shoo.app.components.AvatarRing
import com.shoo.app.components.AvatarView
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.dynamicColor
import com.shoo.app.components.figmaCardShadow
import com.shoo.app.components.hex
import com.shoo.app.components.pressScale
import com.shoo.app.components.shooEaseOut
import com.shoo.app.components.stateEntrance
import com.shoo.app.data.LoadFailure
import com.shoo.app.support.t
import kotlinx.coroutines.launch

// PF-01 cards from the updated Figma: the Protected "Terhubung" pill, the Pribadi "Mode Guardian" card and the
// Guardian "Belum ada yang Anda lindungi" card. Values are the Figma ones.

/** SwiftUI `LinearGradient` with unit start / end points: the shader is built for the size it fills. */
internal fun unitGradient(
    colors: List<Color>,
    start: Offset,
    end: Offset,
    stops: List<Float>? = null,
): Brush = object : ShaderBrush() {
    override fun createShader(size: Size): Shader = LinearGradientShader(
        from = Offset(size.width * start.x, size.height * start.y),
        to = Offset(size.width * end.x, size.height * end.y),
        colors = colors,
        colorStops = stops,
    )
}

// MARK: Terhubung pill (Protected)

/** Orange capsule on the Protected profile card (Figma "Bagikan Undangan" → "Terhubung"). Swift `ConnectedPillButtonStyle`. */
object ConnectedPillButtonDefaults {
    /** Figma's transform stretches the gradient to 2.67 × the pill (x scale 0.374): only its orange-to-salmon start shows. */
    val gradient: Brush = unitGradient(
        colors = listOf(hex(0xF5B94D), hex(0xFC9C7F), hex(0xFD8F7F), hex(0xFF6F5B)),
        stops = listOf(0f, 0.37f, 0.68f, 0.99f),
        start = Offset(0f, 0.5f),
        end = Offset(1f / 0.37387f, 0.5f),
    )
}

/**
 * Figma 455:10289, 138.6 × 41: 5 / 15 inside a 3.5 pt white ring that counts in the layout, "Terhubung" in SF Pro
 * Rounded 17 on a 140 % line. The `content` row gets the white text style.
 */
@Composable
fun ConnectedPillButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    onClickLabel: String? = null,
    testTag: String? = null,
    content: @Composable RowScope.() -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val reduceMotion = LocalReduceMotion.current
    val alpha by animateFloatAsState(if (pressed) 0.7f else 1f, shooEaseOut(0.15), label = "connectedAlpha")
    // Reduce Motion: the dim alone.
    val scale by animateFloatAsState(if (pressed && !reduceMotion) 0.97f else 1f, shooEaseOut(0.15), label = "connectedScale")
    val tag = testTag
    Box(
        modifier
            .heightIn(min = 44.dp)
            .clickable(interaction, indication = null, onClickLabel = onClickLabel, role = Role.Button, onClick = onClick)
            .then(if (tag != null) Modifier.semantics { this.testTag = tag } else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            Modifier
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                    this.alpha = alpha
                }
                .background(ConnectedPillButtonDefaults.gradient, CapsuleShape)
                .border(3.5.dp, ProfileStyle.card, CapsuleShape)
                .padding(horizontal = 18.5.dp, vertical = 8.5.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CompositionLocalProvider(LocalTextStyle provides profileValue(), LocalContentColor provides Color.White) {
                content()
            }
        }
    }
}

/** Figma's glyph (455:10401), exported from the design: a phone beside a stack. Swift `ConnectedPillButtonStyle.glyph`. */
@Composable
fun ConnectedPillGlyph(modifier: Modifier = Modifier) {
    Box(modifier.size(width = 19.dp, height = 18.dp).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        Image(
            painter = painterResource(R.drawable.profile_connected_glyph),
            contentDescription = null,
            colorFilter = ColorFilter.tint(LocalContentColor.current),
            modifier = Modifier.size(width = (44f / 3f).dp, height = (47f / 3f).dp),
        )
    }
}

/** The guardian's avatar at the avatar's lower right (Figma "Avatar/S", 42 pt, white ring). */
@Composable
fun GuardianBadge(avatarId: String, modifier: Modifier = Modifier) {
    AvatarView(id = avatarId, modifier = modifier, size = 42.dp, ring = AvatarRing(color = ProfileStyle.card, width = 2.5.dp))
}

// MARK: Mode Guardian (Pribadi)

/** Figma "CTA Jadi Guardian" (1205:6288): invites a Pribadi user to protect their family. X hides it for good. */
@Composable
fun GuardianModeCard(onBecomeGuardian: () -> Unit, onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    ModeOfferCard(
        eyebrow = "GUARDIAN MODE",
        title = "Protect the people closest to you",
        message = "Help check suspicious sites your family opens.",
        action = "Become a Guardian",
        identifier = "profile.guardianCard",
        onAction = onBecomeGuardian,
        onDismiss = onDismiss,
        modifier = modifier
            .padding(horizontal = ProfileStyle.margin)
            .padding(top = 32.dp),
    )
}

/**
 * Figma "Mode Terawasi" (Home Pribadi 1253:8803, Guardian Home 1279:9544): connect to a guardian, who then
 * double-checks risky sites. On Home Pribadi X hides it for good; the Guardian Home one has no X.
 * `action`: a catalog key, "Connect" on Home Pribadi, "Become supervised" on the empty Guardian Home.
 */
@Composable
fun BecomeSupervisedCard(
    action: String = "Connect",
    onConnect: () -> Unit,
    onDismiss: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    ModeOfferCard(
        eyebrow = "SUPERVISED MODE",
        title = "Not sure?",
        message = "Connect so someone you love can double-check for you",
        action = action,
        identifier = "home.becomeSupervised",
        onAction = onConnect,
        onDismiss = onDismiss,
        modifier = modifier,
    )
}

/** Colours of the card both offers share. */
object ModeOfferCardDefaults {
    val fill: Brush
        @Composable get() = Brush.horizontalGradient(listOf(dynamicColor(0xF3F8FF, 0x16222E), dynamicColor(0xE2F8F5, 0x12302E)))
    val eyebrowInk: Color @Composable get() = dynamicColor(0x0D8F93, 0x4FD1D1, 0x08686B, 0x7FE3E3)

    /** Figma "Tombol / Jadi Guardian" (1115:14386): #446EB4 at the top to #214889 three quarters down. */
    val button: Brush = unitGradient(
        colors = listOf(hex(0x446EB4), hex(0x214889)),
        start = Offset(0.5f, -0.05f),
        end = Offset(0.5f, 0.75f),
    )
}

/**
 * The card both offers share: eyebrow, title, two lines, a dark pill, the teal glass shield on the right.
 * `eyebrow`, `title`, `message`, `action`: catalog keys.
 */
@Composable
fun ModeOfferCard(
    eyebrow: String,
    title: String,
    message: String,
    action: String,
    identifier: String,
    onAction: () -> Unit,
    onDismiss: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(24.dp)
    val card = ProfileStyle.card
    // iOS `.frame(minHeight: 205)` centres the content when it is shorter.
    Box(
        modifier
            .fillMaxWidth()
            .figmaCardShadow(shape)
            .background(ModeOfferCardDefaults.fill, shape)
            .clip(shape)
            .border(1.dp, card.copy(alpha = card.alpha * 0.9f), shape)
            .heightIn(min = 205.dp)
            .semantics { testTag = identifier },
        contentAlignment = Alignment.CenterStart,
    ) {
        Box(Modifier.fillMaxWidth()) {
            Image(
                painter = painterResource(R.drawable.guardian_shield),
                contentDescription = null,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 19.5.dp)
                    .size(width = 145.dp, height = 169.dp),
            )

            // Figma 1115:14373: eyebrow, title 7 under it, body 5 under the title, the button 16 under the body.
            Column(Modifier.padding(start = 20.dp, top = 22.dp, bottom = 19.dp)) {
                Text(
                    t(eyebrow),
                    style = profileFont(11f, FontWeight.SemiBold, rounded = true, tracking = 0.06f, lineHeight = 13f),
                    color = ModeOfferCardDefaults.eyebrowInk,
                )
                // One line in Figma; may reach under the shield's glow rather than wrap early.
                Text(
                    t(title),
                    style = profileFont(20f, FontWeight.SemiBold, tracking = -0.45f, lineHeight = 25f),
                    color = ProfileStyle.nameInk,
                    modifier = Modifier
                        .padding(top = 7.dp)
                        .width(230.dp)
                        .semantics { heading() },
                )
                Text(
                    t(message),
                    style = profileFont(16f, rounded = true, tracking = -0.31f, lineHeight = 21f),
                    color = ProfileStyle.secondary,
                    modifier = Modifier
                        .padding(top = 5.dp)
                        .widthIn(max = 206.dp),
                )
                Spacer(Modifier.height(13.dp))
                Box(
                    Modifier
                        .heightIn(min = 44.dp)
                        .plainClickable(onClick = onAction)
                        .semantics { testTag = "$identifier.action" },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        t(action),
                        style = profileFont(17f, FontWeight.SemiBold, lineHeight = 22f),
                        color = Color.White,
                        modifier = Modifier
                            .background(ModeOfferCardDefaults.button, CapsuleShape)
                            .heightIn(min = 38.dp)
                            .padding(horizontal = 18.dp)
                            .wrapCenteredVertically(),
                    )
                }
            }

            if (onDismiss != null) {
                val closeLabel = t("Close")
                Box(
                    Modifier
                        .align(Alignment.TopEnd)
                        .padding(top = 4.dp, end = 4.dp)
                        .size(44.dp)
                        .plainClickable(onClick = onDismiss)
                        .semantics {
                            contentDescription = closeLabel
                            testTag = "$identifier.close"
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier
                            .size(28.dp)
                            .background(card.copy(alpha = card.alpha * 0.75f), CircleShape)
                            .border(1.dp, card, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        // iOS: `xmark` at 10 pt bold.
                        SfSymbol("xmark", 10f, ProfileStyle.secondary)
                    }
                }
            }
        }
    }
}

/** Centres a one-line text inside the min height it was given (SwiftUI centres the label in `.frame(minHeight:)`). */
private fun Modifier.wrapCenteredVertically(): Modifier = this.layout { measurable, constraints ->
    val placeable = measurable.measure(constraints.copy(minHeight = 0))
    val height = maxOf(placeable.height, constraints.minHeight)
    layout(placeable.width, height) {
        placeable.place(0, (height - placeable.height) / 2)
    }
}

// MARK: Nobody protected yet (Guardian)

/** Figma "Orang yang dilindungi · Kosong": three slots, the middle one a teal plus. */
@Composable
fun FamilyEmptyCard(onInvite: () -> Unit, modifier: Modifier = Modifier) {
    val teal = dynamicColor(0x0FB3B5, 0x3FD3D4)
    val tealFill = dynamicColor(0xE6F9F8, 0x123332)
    val density = LocalDensity.current
    // Figma "Button" (1115:14537): #68CDFA at the top to #136CB7 three quarters down.
    val button = remember {
        unitGradient(listOf(hex(0x68CDFA), hex(0x136CB7)), start = Offset(0.5f, -0.05f), end = Offset(0.5f, 0.75f))
    }
    val labelShadow = with(density) {
        Shadow(Color.Black.copy(alpha = 0.2f), Offset(0f, 4.dp.toPx()), ((2.dp.toPx() - 0.5f) / 0.57735f).coerceAtLeast(0f))
    }
    Column(
        modifier
            .fillMaxWidth()
            // Figma: slot 27 pt and button 25 pt from the card's edges; ProfileCard already adds 5.
            .padding(start = 24.dp, end = 24.dp, top = 22.dp, bottom = 20.dp)
            .semantics { testTag = "profile.members.empty" },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // Figma "Slot Kosong" is 64 pt tall with the circles centred.
        Row(
            Modifier
                .height(64.dp)
                .clearAndSetSemantics { },
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            EmptySlot()
            Canvas(Modifier.size(60.dp)) {
                val line = 1.5.dp.toPx()
                drawCircle(tealFill)
                drawCircle(
                    teal,
                    radius = size.minDimension / 2 - line / 2,
                    style = Stroke(line, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx()))),
                )
                // Figma "Plus": 16 pt, 2 pt teal stroke.
                val s = 1.dp.toPx()
                val origin = Offset(center.x - 8 * s, center.y - 8 * s)
                val stroke = 2.dp.toPx()
                drawLine(teal, origin + Offset(8 * s, 1 * s), origin + Offset(8 * s, 15 * s), stroke, StrokeCap.Round)
                drawLine(teal, origin + Offset(1 * s, 8 * s), origin + Offset(15 * s, 8 * s), stroke, StrokeCap.Round)
            }
            EmptySlot()
        }
        // Figma 1115:14533: SF Pro Display Semibold 17, then SF Pro Rounded 17 at 140 %.
        Text(
            t("No one protected yet"),
            style = profileFont(17f, FontWeight.SemiBold, lineHeight = 22f),
            color = ProfileStyle.nameInk,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 14.dp),
        )
        Text(
            t("Send an invite to your family. Once they join, their status shows up here."),
            style = profileValue(),
            color = ProfileStyle.secondary,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .padding(top = 6.dp)
                .widthIn(max = 280.dp),
        )
        Box(
            Modifier
                .padding(top = 18.dp)
                .plainClickable(onClick = onInvite)
                .semantics { testTag = "profile.members.invite" }
                .heightIn(min = 46.dp)
                .background(button, CapsuleShape)
                .border(1.5.dp, hex(0x0098D7), CapsuleShape)
                .padding(horizontal = 20.dp, vertical = 12.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                t("Invite family"),
                style = profileFont(17f, FontWeight.SemiBold, lineHeight = 22f).copy(shadow = labelShadow),
                color = Color.White,
            )
        }
    }
}

@Composable
private fun EmptySlot() {
    val background = ProfileStyle.background
    val slotStroke = dynamicColor(0xC5CFDA, 0x4B5361)
    val slotPerson = dynamicColor(0xCDD5DF, 0x5B6470)
    Canvas(Modifier.size(48.dp)) {
        val line = 1.5.dp.toPx()
        drawCircle(background)
        drawCircle(
            slotStroke,
            radius = size.minDimension / 2 - line / 2,
            style = Stroke(line, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx()))),
        )
        val side = 20.dp.toPx()
        drawPath(slotPersonPath(side, Offset(center.x - side / 2, center.y - side / 2)), slotPerson)
    }
}

/** Figma "Ikon Orang" (1115:14523), 20 pt: an 8.4 pt head over a 15.2 × 8.8 body (radius 7.6 on top, 1.6 below). */
private fun slotPersonPath(side: Float, origin: Offset): Path {
    val s = side / 20f
    return Path().apply {
        addOval(Rect(Offset(origin.x + 5.8f * s, origin.y + 0.8f * s), Size(8.4f * s, 8.4f * s)))
        addRoundRect(
            RoundRect(
                rect = Rect(Offset(origin.x + 2.4f * s, origin.y + 11.2f * s), Size(15.2f * s, 8.8f * s)),
                topLeft = CornerRadius(7.6f * s),
                topRight = CornerRadius(7.6f * s),
                bottomRight = CornerRadius(1.6f * s),
                bottomLeft = CornerRadius(1.6f * s),
            ),
        )
    }
}

// MARK: Couldn't load

/**
 * Figma "Card · Gagal memuat" (Profile/Pribadi 1681:6986, the Guardian family list 1681:7088): the red circular arrow
 * (#E5483B), "Profil belum bisa dimuat" (Semibold 20 / 26), the line (Rounded 17 / 22, #6A717E), then a 56 pt
 * outlined "Coba Lagi" 40 below. The rest of Profile stays usable. The symbol bounces once on arrival and again after
 * a failed try; the button shows a spinner while it retries.
 * `failure`: only a failure to reach the server asks to check the connection (A-03).
 */
@Composable
fun ProfileLoadFailed(
    identifier: String = "profile.retry",
    failure: LoadFailure = LoadFailure.CONNECTION,
    retry: suspend () -> Unit,
    modifier: Modifier = Modifier,
) {
    val reduceMotion = LocalReduceMotion.current
    var isRetrying by remember { mutableStateOf(false) }
    var nudge by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val feedback = rememberSensoryFeedback()
    val red = hex(0xE5483B)
    // Figma "Gradient/Primary Button" stroke: #136CB7 to #68CDFA.
    val stroke = remember { Brush.horizontalGradient(listOf(hex(0x136CB7), hex(0x68CDFA))) }
    LaunchedEffect(Unit) { nudge += 1 }
    OnChange(nudge) { _, now -> if (now == 1) feedback(ProfileHaptic.ERROR) }
    val title = t("Couldn't load the profile")
    val message = t(failure.message(connection = "Check your internet connection, then try again."))

    Column(
        modifier
            .fillMaxWidth()
            .padding(horizontal = 32.dp, vertical = 24.dp)
            .stateEntrance(),
        // Centred in a taller frame, like SwiftUI's `.frame(minHeight:)` on Profile.
        verticalArrangement = Arrangement.spacedBy(40.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(
            Modifier.clearAndSetSemantics { contentDescription = "$title. $message" },
            verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(Modifier.size(50.dp), contentAlignment = Alignment.Center) {
                // iOS: SF Pro Rounded Bold 34.3.
                SfSymbol(
                    "exclamationmark.arrow.circlepath", 34.3f, red,
                    modifier = Modifier.profileBounce(nudge, enabled = !reduceMotion),
                )
            }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    title,
                    style = profileFont(20f, FontWeight.SemiBold, lineHeight = 26f),
                    color = hex(0x151617),
                    textAlign = TextAlign.Center,
                )
                Text(
                    message,
                    style = profileFont(17f, rounded = true, lineHeight = 22f),
                    color = ProfileStyle.secondary,
                    textAlign = TextAlign.Center,
                )
            }
        }
        val interaction = remember { MutableInteractionSource() }
        val labelAlpha by animateFloatAsState(if (isRetrying) 0f else 1f, shooEaseOut(0.15), label = "retryLabel")
        Box(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 56.dp)
                .pressScale(interaction)
                .background(ProfileStyle.card, CapsuleShape)
                .border(1.dp, stroke, CapsuleShape)
                .clip(CapsuleShape)
                .clickable(interaction, indication = null, enabled = !isRetrying, role = Role.Button) {
                    if (isRetrying) return@clickable
                    scope.launch {
                        isRetrying = true
                        try {
                            retry()
                        } finally {
                            isRetrying = false
                            nudge += 1
                        }
                    }
                }
                .semantics { testTag = identifier },
            contentAlignment = Alignment.Center,
        ) {
            Text(
                t("Try Again"),
                style = profileFont(17f, FontWeight.SemiBold),
                color = ProfileStyle.link,
                modifier = Modifier.graphicsLayer { alpha = labelAlpha },
            )
            // The spinner fades in and out under the same `.easeOut(0.15)`.
            androidx.compose.animation.AnimatedVisibility(isRetrying, enter = fadeIn(shooEaseOut(0.15)), exit = fadeOut(shooEaseOut(0.15))) {
                CircularProgressIndicator(Modifier.size(16.dp), color = ProfileStyle.link, strokeWidth = 2.dp)
            }
        }
    }
}
