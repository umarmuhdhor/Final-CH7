package com.shoo.app.features.onboarding

import android.os.Build
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
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
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.shoo.app.R
import com.shoo.app.components.AvatarView
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.FigmaFont
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.figmaTextStyleFixed
import com.shoo.app.components.hex
import com.shoo.app.components.shooShadow
import com.shoo.app.data.GuardianInfo
import com.shoo.app.support.t
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

/**
 * Figma "Ilustrasi / Keluarga" (871:19612), built in Compose so its text follows the app language.
 * Sample content, nothing here is the user's family. Coordinates are Figma's on the 402 pt frame.
 */
@Composable
fun FamilyCardIllustration(modifier: Modifier = Modifier) {
    // Figma's status bar and home area are not part of the page: the hero starts under the safe area.
    val safeAreaTop = 62f
    Box(modifier = modifier.size(402.dp, (460f - safeAreaTop + 14f).dp).clearAndSetSemantics { }) {
        // The 402 × 460 Figma frame, bottom-aligned: its top overflows the hero like on iOS.
        Box(
            modifier = Modifier
                .wrapContentSize(Alignment.BottomStart, unbounded = true)
                .size(402.dp, 460.dp),
        ) {
            BlurredEllipse(hex(0x51DEDC, 0.5f), 170.dp, 150.dp, blur = 30.dp, modifier = Modifier.centeredAt(155.dp, 325.dp))
            BlurredEllipse(hex(0x2E90FA, 0.55f), 190.dp, 190.dp, blur = 40.dp, modifier = Modifier.centeredAt(331.dp, 185.dp))
            // Figma "Ketebalan kaca": the edge of the glass under the card.
            Box(
                modifier = Modifier
                    .centeredAt(196.1.dp, 269.6.dp)
                    .size(266.4.dp, 249.2.dp)
                    .graphicsLayer { rotationZ = -4f }
                    .background(
                        Brush.verticalGradient(
                            0f to hex(0xE6FCF9, 0.85f),
                            0.96f to hex(0xE6FCF9, 0.85f),
                            1f to hex(0xA6EEEE, 0.9f),
                        ),
                        RoundedCornerShape(26.dp),
                    ),
            )
            FamilyCard(
                Modifier
                    .centeredAt(194.6.dp, 263.6.dp)
                    .graphicsLayer { rotationZ = -4f },
            )
            // Figma export of "Perisai 3D", its shadow baked in.
            Image(
                painter = painterResource(R.drawable.family_shield),
                contentDescription = null,
                modifier = Modifier.centeredAt(287.dp, 376.dp),
            )
        }
    }
}

@Composable
private fun FamilyCard(modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(26.dp)
    val ink = hex(0x191D2F)
    Column(
        modifier = modifier
            .width(266.4.dp)
            // iOS: .ultraThinMaterial over white 20 %; Android can't blur what lies behind.
            .background(Color.White.copy(alpha = 0.5f), shape)
            .border(
                1.35.dp,
                Brush.linearGradient(listOf(Color.White.copy(alpha = 0.95f), Color.White.copy(alpha = 0.25f)), Offset.Zero, Offset.Infinite),
                shape,
            )
            .padding(start = 12.6.dp, end = 12.6.dp, bottom = 12.6.dp, top = 14.4.dp),
        verticalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Row(
            modifier = Modifier.padding(start = 1.8.dp, end = 1.8.dp, bottom = 1.8.dp),
            horizontalArrangement = Arrangement.spacedBy(7.2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(t("Family"), style = fixedFont(15.3f, FontWeight.SemiBold).copy(color = ink))
            Text(
                t("2 of 3"),
                style = fixedFont(10.8f, family = FigmaFont.Family.SF_PRO).copy(color = OnboardingTheme.bodyInk),
                modifier = Modifier
                    .background(Color.White.copy(alpha = 0.55f), CapsuleShape)
                    .border(0.9.dp, Color.White.copy(alpha = 0.9f), CapsuleShape)
                    .padding(horizontal = 8.1.dp, vertical = 2.7.dp),
            )
        }

        FamilyRow("avatar_01", "Mom", "Site blocked · 92%", hex(0xE5483B), FontWeight.SemiBold) {
            SfSymbol("chevron.right", pointSize = 14f, tint = hex(0x9AA1AE))
        }
        FamilyRow("avatar_02", "Dad", "Nothing suspicious", OnboardingTheme.bodyInk, FontWeight.Normal) {
            Box(
                modifier = Modifier.size(19.8.dp).background(hex(0x34C759), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                SfSymbol("checkmark", pointSize = 10f, tint = Color.White)
            }
        }

        val inviteShape = RoundedCornerShape(16.dp)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color.White.copy(alpha = 0.22f), inviteShape)
                .drawBehind {
                    val width = 1.35.dp.toPx()
                    drawRoundRect(
                        color = Color.White.copy(alpha = 0.95f),
                        topLeft = Offset(width / 2, width / 2),
                        size = Size(size.width - width, size.height - width),
                        cornerRadius = CornerRadius(16.dp.toPx() - width / 2),
                        style = Stroke(width, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx()))),
                    )
                }
                .padding(start = 9.dp, end = 12.6.dp, top = 10.8.dp, bottom = 10.8.dp),
            horizontalArrangement = Arrangement.spacedBy(10.8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(28.8.dp)
                    .shooShadow(hex(0x186FB9, 0.18f), radius = 3.6.dp, y = 2.7.dp, shape = CircleShape)
                    .background(Color.White.copy(alpha = 0.85f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                SfSymbol("plus", pointSize = 13f, tint = hex(0x186FB9))
            }
            Text(
                t("Invite your family"),
                style = fixedFont(14.4f, FontWeight.SemiBold, tracking = -0.28f, family = FigmaFont.Family.SF_PRO)
                    .copy(color = hex(0x186FB9)),
            )
            Spacer(Modifier.weight(1f))
        }
    }
}

/** One member in the Figma card: 36 pt avatar, name, status, and an end mark. `name` / `status` are catalog keys. */
@Composable
private fun FamilyRow(
    avatarId: String,
    name: String,
    status: String,
    statusColor: Color,
    statusWeight: FontWeight,
    mark: @Composable () -> Unit,
) {
    val shape = RoundedCornerShape(16.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .shooShadow(hex(0x0B4C8C, 0.1f), radius = 7.2.dp, y = 5.4.dp, shape = shape)
            .background(Color.White.copy(alpha = 0.78f), shape)
            .border(
                0.9.dp,
                Brush.linearGradient(listOf(Color.White, Color.White.copy(alpha = 0.5f)), Offset.Zero, Offset.Infinite),
                shape,
            )
            .padding(start = 9.dp, end = 12.6.dp, top = 9.dp, bottom = 9.dp),
        horizontalArrangement = Arrangement.spacedBy(10.8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AvatarView(id = avatarId, size = 36.dp)
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(0.9.dp)) {
            Text(t(name), style = fixedFont(15.3f, FontWeight.SemiBold).copy(color = hex(0x191D2F)))
            // iOS: .minimumScaleFactor(0.8); here the line ends in an ellipsis instead.
            Text(
                t(status),
                style = fixedFont(11.7f, statusWeight, tracking = -0.07f, family = FigmaFont.Family.SF_PRO).copy(color = statusColor),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        mark()
    }
}

/**
 * Figma "Ilustrasi / Orbit" (929:8614) in motion: the two avatars circle the shield and pass in front of
 * and behind it, each with its chip at the ends of the orbit. With Reduce Motion it is the still frame.
 * `ownAvatarId`: null until `GET /devices/me` answered (the generic avatar shows).
 */
@Composable
fun ConnectedOrbitIllustration(guardian: GuardianInfo, ownAvatarId: String?, modifier: Modifier = Modifier) {
    val reduceMotion = LocalReduceMotion.current
    var turn by remember { mutableDoubleStateOf(0.0) }
    LaunchedEffect(reduceMotion) {
        if (reduceMotion) {
            turn = 0.0
            return@LaunchedEffect
        }
        val start = withFrameNanos { it }
        while (true) {
            val now = withFrameNanos { it }
            turn = (now - start) / 1e9 / Orbit.PERIOD * 2 * PI
        }
    }

    Box(modifier = modifier.size(Orbit.WIDTH.dp, Orbit.HEIGHT.dp).clearAndSetSemantics { }) {
        // Glow
        BlurredEllipse(hex(0x51DEDC, 0.34f), 178.dp, 144.dp, blur = 24.dp, modifier = Modifier.centeredAt(53.dp, 241.dp))
        BlurredEllipse(hex(0x94DBFE, 0.33f), 178.dp, 161.dp, blur = 24.dp, modifier = Modifier.centeredAt(287.dp, 152.dp))
        // Rings
        Canvas(modifier = Modifier.size(Orbit.WIDTH.dp, Orbit.HEIGHT.dp)) {
            val c = Offset(Orbit.CENTER_X.dp.toPx(), Orbit.CENTER_Y.dp.toPx())
            rotate(degrees = (Orbit.TILT * 180 / PI).toFloat(), pivot = c) {
                val outer = Size(293.2.dp.toPx(), 127.1.dp.toPx())
                val outerWidth = 1.27.dp.toPx()
                drawOval(
                    color = Color.White.copy(alpha = 0.22f * 0.47f),
                    topLeft = Offset(c.x - outer.width / 2 + outerWidth / 2, c.y - outer.height / 2 + outerWidth / 2),
                    size = Size(outer.width - outerWidth, outer.height - outerWidth),
                    style = Stroke(outerWidth),
                )
                val inner = Size(254.25.dp.toPx(), 98.3.dp.toPx())
                val innerWidth = 2.12.dp.toPx()
                val left = c.x - inner.width / 2
                drawOval(
                    brush = Brush.horizontalGradient(
                        listOf(hex(0x8FE9EC), Color.White.copy(alpha = 0.95f)),
                        startX = left,
                        endX = left + inner.width,
                    ),
                    topLeft = Offset(left + innerWidth / 2, c.y - inner.height / 2 + innerWidth / 2),
                    size = Size(inner.width - innerWidth, inner.height - innerWidth),
                    alpha = 0.19f,
                    style = Stroke(innerWidth),
                )
            }
        }
        Riders(turn = turn, front = false, guardian = guardian, ownAvatarId = ownAvatarId)
        // Shield: Figma export of "Perisai 3D"; its baked shadow reaches lower, so the picture centre is 13.6 down.
        Image(
            painter = painterResource(R.drawable.orbit_shield),
            contentDescription = null,
            modifier = Modifier.centeredAt(Orbit.SHIELD_X.dp, (Orbit.SHIELD_Y + 13.6f).dp),
        )
        Box(
            modifier = Modifier
                .centeredAt(203.6.dp, 201.6.dp)
                .size(27.dp)
                .shooShadow(hex(0x1B7F3A, 0.4f), radius = 6.8.dp, y = 5.dp, shape = CircleShape)
                .background(hex(0x34C759), CircleShape)
                .border(2.5.dp, Color.White, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            SfSymbol("checkmark", pointSize = 12f, tint = Color.White)
        }
        Riders(turn = turn, front = true, guardian = guardian, ownAvatarId = ownAvatarId)
    }
}

/** Figma "Orbit": centre, half axes, and its tilt (rotation read from the node's bounding box). */
private object Orbit {
    const val WIDTH = 340.7f
    const val HEIGHT = 339f
    const val CENTER_X = 170.35f
    const val CENTER_Y = 186.45f
    const val RADIUS_X = 127.1
    const val RADIUS_Y = 49.2
    const val TILT = -14 * PI / 180
    const val SHIELD_X = 170f
    const val SHIELD_Y = 176f
    const val PERIOD = 18.0
}

/** Where each avatar starts, so the first frame is Figma's. The guardian rides slightly further out. */
private class Rider(val id: Int, val startAngle: Double, val reach: Double, val chipX: Float, val chipY: Float)

private val you = Rider(0, PI, 1.0, 20f, 56f)
private val them = Rider(1, 32.6 * PI / 180, 1.13, -3f, -60f)

@Composable
private fun Riders(turn: Double, front: Boolean, guardian: GuardianInfo, ownAvatarId: String?) {
    for (rider in listOf(you, them)) {
        val angle = rider.startAngle + turn
        // The ends of the orbit count as behind, so the first frame keeps Figma's order.
        if ((sin(angle) > 0.001) != front) continue
        val x = Orbit.RADIUS_X * rider.reach * cos(angle)
        val y = Orbit.RADIUS_Y * rider.reach * sin(angle)
        val spotX = (Orbit.CENTER_X + x * cos(Orbit.TILT) - y * sin(Orbit.TILT)).toFloat()
        val spotY = (Orbit.CENTER_Y + x * sin(Orbit.TILT) + y * cos(Orbit.TILT)).toFloat()
        val scale = (1 + 0.1 * (sin(angle) - sin(rider.startAngle))).toFloat()
        AvatarView(
            id = if (rider.id == you.id) ownAvatarId ?: "" else guardian.avatarId,
            size = 66.dp,
            modifier = Modifier
                .centeredAt(spotX.dp, spotY.dp)
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                }
                .shooShadow(hex(0x062F5C, 0.28f), radius = 9.3.dp, y = 8.5.dp, shape = CircleShape)
                .border(2.5.dp, Color.White, CircleShape),
        )
        // Only near the ends of the orbit, where nothing covers it.
        val chipAlpha = ((abs(cos(angle)) - 0.55) / 0.25).coerceIn(0.0, 1.0).toFloat()
        OrbitChip(
            isYou = rider.id == you.id,
            guardianName = guardian.name,
            modifier = Modifier
                .centeredAt((spotX + rider.chipX).dp, (spotY + rider.chipY).dp)
                .graphicsLayer { alpha = chipAlpha },
        )
    }
}

@Composable
private fun OrbitChip(isYou: Boolean, guardianName: String, modifier: Modifier = Modifier) {
    val ink = hex(0x191D2F)
    val regular = fixedFont(11f, tracking = -0.07f, family = FigmaFont.Family.SF_PRO)
    val semibold = fixedFont(11f, FontWeight.SemiBold, tracking = -0.07f, family = FigmaFont.Family.SF_PRO)
    Row(
        modifier = modifier
            .shooShadow(hex(0x062F5C, 0.16f), radius = 6.8.dp, y = 5.dp, shape = CapsuleShape)
            .background(Color.White.copy(alpha = 0.78f), CapsuleShape)
            .border(0.85.dp, Color.White.copy(alpha = 0.95f), CapsuleShape)
            .padding(start = 9.3.dp, end = 11.dp, top = 5.9.dp, bottom = 5.9.dp),
        horizontalArrangement = Arrangement.spacedBy(4.2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (isYou) {
            Text(t("You"), style = semibold.copy(color = ink))
            Text(t("· Protected"), style = regular.copy(color = OnboardingTheme.bodyInk))
        } else {
            Text(
                guardianName,
                style = semibold.copy(color = ink),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.widthIn(max = 76.dp),
            )
            Text("· Guardian", style = semibold.copy(color = hex(0x186FB9)))
        }
    }
}

// MARK: Helpers

/**
 * `FigmaFont.font(size:)` / `.font(.system(size:))`: a fixed size that does not follow the text size, as the
 * illustration's own type (iOS builds a fixed `Font`, so Dynamic Type leaves it alone).
 */
@Composable
internal fun fixedFont(
    size: Float,
    weight: FontWeight = FontWeight.Normal,
    tracking: Float? = null,
    family: FigmaFont.Family = FigmaFont.Family.DISPLAY,
): TextStyle = figmaTextStyleFixed(size, weight, tracking, null, family, scale = 1f / LocalDensity.current.fontScale)

/** SwiftUI `.position(x:y:)`: centres the view on (x, y) of its parent `Box`, at its own size. */
internal fun Modifier.centeredAt(x: Dp, y: Dp): Modifier = layout { measurable, constraints ->
    val placeable = measurable.measure(Constraints())
    val width = if (constraints.hasBoundedWidth) constraints.maxWidth else placeable.width
    val height = if (constraints.hasBoundedHeight) constraints.maxHeight else placeable.height
    layout(width, height) {
        placeable.place(x.roundToPx() - placeable.width / 2, y.roundToPx() - placeable.height / 2)
    }
}

/**
 * `Ellipse().fill(color).frame(w, h).blur(radius: r)`. API 31+ blurs for real; before that a radial fade that
 * reaches about as far as the Gaussian blur does.
 */
@Composable
internal fun BlurredEllipse(color: Color, width: Dp, height: Dp, blur: Dp, modifier: Modifier = Modifier) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        Box(
            modifier = modifier
                .size(width, height)
                .blur(blur, BlurredEdgeTreatment.Unbounded)
                .drawBehind { drawOval(color) },
        )
    } else {
        Box(
            modifier = modifier
                .size(width, height)
                .drawBehind {
                    val spread = blur.toPx() * 2
                    val w = size.width + spread * 2
                    val h = size.height + spread * 2
                    val radius = w / 2
                    scale(scaleX = 1f, scaleY = h / w, pivot = center) {
                        drawCircle(
                            brush = Brush.radialGradient(
                                0f to color,
                                (size.width / 2 - spread / 2).coerceAtLeast(0f) / radius to color,
                                1f to color.copy(alpha = 0f),
                                center = center,
                                radius = radius,
                            ),
                            radius = radius,
                            center = center,
                        )
                    }
                },
        )
    }
}
