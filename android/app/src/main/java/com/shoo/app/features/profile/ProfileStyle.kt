package com.shoo.app.features.profile

import androidx.annotation.DrawableRes
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.animateFloatAsState
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
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.dynamicColor
import com.shoo.app.components.figmaCardShadow
import com.shoo.app.components.figmaTextStyle
import com.shoo.app.components.hex
import com.shoo.app.components.scaled
import com.shoo.app.components.shooEaseInOut
import com.shoo.app.components.shooEaseOut
import com.shoo.app.components.shooShadow
import com.shoo.app.data.ScanStatus
import com.shoo.app.support.t

/**
 * Figma "Profile/Pribadi", "Profile/Guardian", "Guardian/Detail Orang Dilindungi" (PF-01): colours,
 * type and the building blocks every Profile screen shares. Values are the Figma ones.
 * Light values are Figma's; dark and Increase Contrast values are ours (Figma has light only).
 */
object ProfileStyle {
    val background: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xF5F8FC, 0x0E1116)
    val topWash: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xDCECFB, 0x132639)
    /** Cards, the back button, pills. */
    val card: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xFFFFFF, 0x1B1F26)
    /** Figma "Profil Card", "Back" and member "Avatar" drop shadow (#1A1C2E 12%, y 6, blur 16). */
    val cardShadow: Color = hex(0x1A1C2E, 0.12f)
    /** Figma "Profile" avatar on the own profile card (#1F78BF 18%, y 7.68, blur 23). */
    val avatarGlow: Color = hex(0x1F78BF, 0.18f)
    val ink: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x191D2F, 0xF2F4F8, 0x000000, 0xFFFFFF)
    val nameInk: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x151617, 0xF7F8FA, 0x000000, 0xFFFFFF)
    val secondary: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x6A717E, 0x9EA6B4, 0x474D58, 0xC9CED8)
    val chevron: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xC7C7CE, 0x5B616C, 0x80858F, 0x9EA6B4)
    val iconFill: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xF1F4F8, 0x2A303A, 0xE2E7EE, 0x3A414D)
    val divider: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xEEF1F5, 0x2A303A, 0xC6CDD7, 0x4B5361)
    val statsDivider: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xE3E8EF, 0x343B46, 0xB8C0CC, 0x56606E)
    val pillStroke: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xDCDFE4, 0x3A414D, 0x9AA1AC, 0x6B7380)
    val link: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x186FB9, 0x5EAAF0, 0x0E5592, 0x8CC4F6)
    val red: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xE5483B, 0xFF6B5E, 0xB3261E, 0xFF8F85)
    val redIconFill: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xFDECEA, 0x3A1F1D)
    val green: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x34C759, 0x30D158)
    val greenText: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x1B7F3A, 0x4CD97B, 0x0F5F27, 0x7BE8A0)
    val greenPill: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xE8F8EE, 0x153322)
    val offDot: Color = hex(0x8E8E93)
    val grabber: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xD6DAE1, 0x4A515C)
    /** The radio's ring (Figma "Radio" #C7C7CE) and the Mode akun card's selected border. */
    val radioOff: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xC7C7CE, 0x5B616C, 0x80858F, 0x9EA6B4)
    /** Aksesibilitas text-size slider rail (Figma "Rail"). */
    val sliderRail: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xE6E8EC, 0x343B46, 0xC6CDD7, 0x4B5361)
    /** Disabled button fill (Kelola profil "Simpan nama"). */
    val disabledFill: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xB8C0CC, 0x3A414D)
    /** Primary dark capsule ("Ganti ke Guardian"): ink on light, a light capsule on dark. */
    val primaryFill: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x191D2F, 0xF2F4F8)
    val primaryText: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xFFFFFF, 0x0E1116)

    /** Screen side margin for section titles and cards; the profile card sits closer (16). */
    val margin: Dp = 24.dp

    /** `arrow.left.arrow.right` stands in for Figma's "icon/switch". */
    const val switchSymbol = "arrow.left.arrow.right"

    /** Figma's Safari extension glyph (`macwindow.stack`); Android always has the mapped Material icon. */
    const val extensionSymbol = "macwindow.stack"
}

// MARK: Type

/** Figma sizes that follow the app's text size (shared `figmaTextStyle`). Swift `.profileFont(size, weight, rounded:, tracking:)`. */
@Composable
@ReadOnlyComposable
fun profileFont(
    size: Float,
    weight: FontWeight = FontWeight.Normal,
    rounded: Boolean = false,
    tracking: Float = 0f,
    lineHeight: Float? = null,
): TextStyle = figmaTextStyle(size, weight, rounded = rounded, tracking = tracking, lineHeight = lineHeight)

/** Figma (1115:14392) row titles, section titles, "Hapus Akun": SF Pro Rounded 17, -1 %, 22 pt line. */
@Composable
@ReadOnlyComposable
fun profileBody(weight: FontWeight = FontWeight.Normal): TextStyle =
    profileFont(17f, weight, rounded = true, tracking = -0.17f, lineHeight = 22f)

/** Row values ("Pribadi", "Indonesia"), the handle, "Ingatkan": SF Pro Rounded 17 at 140 %. */
@Composable
@ReadOnlyComposable
fun profileValue(): TextStyle = profileFont(17f, rounded = true, lineHeight = 23.8f)

/** Subtitles, captions and the stats labels: SF Pro Rounded 13, -0.08, 18 pt line. */
@Composable
@ReadOnlyComposable
fun profileCaption(): TextStyle = profileFont(13f, rounded = true, tracking = -0.08f, lineHeight = 18f)

// MARK: Screen

/**
 * The grey page with the blue top wash and the round back button + centred title (Figma "Back", "Judul").
 * `title` is a catalog key. `onBack` pops the Router stack.
 * iOS: the hidden navigation bar, hidden tab bar and `SwipeBackEnabler` are the Router's / system back's job here.
 * Expects to be drawn edge to edge (content scrolls under the status bar).
 */
@Composable
fun ProfileScreen(
    title: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    /** Figma "Judul": 20 pt on Profile and Pengaturan, 17 on the member detail. */
    titleSize: Float = 20f,
    content: @Composable ColumnScope.() -> Unit,
) {
    val safeTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    // Figma puts the back button 48 pt from the top of the frame, inside the 62 pt status bar area of a
    // Dynamic Island iPhone. Other phones keep it 4 pt under the status bar.
    val headerTop = if (safeTop >= 54.dp) 48.dp else safeTop + 4.dp
    val background = ProfileStyle.background
    val topWash = ProfileStyle.topWash
    Box(
        modifier
            .fillMaxSize()
            .background(background),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(340.dp)
                .background(Brush.verticalGradient(listOf(topWash, background.copy(alpha = 0f)))),
        )
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(top = headerTop, bottom = 32.dp),
        ) {
            ProfileScreenHeader(title, titleSize, onBack)
            content()
        }
        // Content scrolling under the status bar stays readable; the band stops above the back button.
        Box(
            Modifier
                .fillMaxWidth()
                .height(minOf(safeTop, headerTop))
                .background(topWash.copy(alpha = topWash.alpha * 0.96f)),
        )
    }
}

@Composable
private fun ProfileScreenHeader(title: String, titleSize: Float, onBack: () -> Unit) {
    Box(
        Modifier
            .padding(horizontal = ProfileStyle.margin)
            .padding(bottom = 16.dp)
            .fillMaxWidth()
            .heightIn(min = 44.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            t(title),
            // Figma: SF Pro Display Semibold 20, -0.45, 25 pt line (17 / 0 / 22 on the member detail).
            style = profileFont(
                titleSize, FontWeight.SemiBold,
                tracking = if (titleSize >= 20f) -0.45f else 0f,
                lineHeight = if (titleSize >= 20f) 25f else 22f,
            ),
            color = ProfileStyle.ink,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .padding(horizontal = 60.dp)
                .semantics { heading() },
        )
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterStart) {
            val backLabel = t("Back")
            Box(
                Modifier
                    .size(44.dp)
                    .shooShadow(ProfileStyle.cardShadow, radius = 8.dp, y = 6.dp, shape = CircleShape)
                    .background(ProfileStyle.card, CircleShape)
                    .clip(CircleShape)
                    .clickable(role = Role.Button, onClick = onBack)
                    .semantics {
                        contentDescription = backLabel
                        testTag = "profile.back"
                    },
                contentAlignment = Alignment.Center,
            ) {
                SfSymbol("arrow.left", 17f, ProfileStyle.ink)
            }
        }
    }
}

// MARK: Sections and cards

/**
 * "Perlindungan", "Akun", "Preferensi": grey title (catalog key) above a card.
 * `top`: space above the title, 28 on most screens, 15 between the Protected profile's sections (Figma).
 * `spacing`: title to card, 10 under the 22 pt title line (Figma 1115:14392), 24 above the Protected
 * profile's "Terhubung" card (Figma 455:10275).
 */
@Composable
fun ProfileSection(
    title: String,
    modifier: Modifier = Modifier,
    trailing: (@Composable () -> Unit)? = null,
    top: Dp = 28.dp,
    spacing: Dp = 10.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier
            .padding(horizontal = ProfileStyle.margin)
            .padding(top = top),
        verticalArrangement = Arrangement.spacedBy(spacing),
    ) {
        Row(Modifier.fillMaxWidth()) {
            Text(
                t(title),
                style = profileBody(),
                color = ProfileStyle.secondary,
                modifier = Modifier
                    .alignByBaseline()
                    .semantics { heading() },
            )
            Spacer(Modifier.weight(1f))
            if (trailing != null) {
                Box(Modifier.alignByBaseline()) { trailing() }
            }
        }
        ProfileCard(content = content)
    }
}

/** White rounded card (r 24) with 5 pt above and below its rows. */
@Composable
fun ProfileCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(24.dp)
    val card = ProfileStyle.card
    Column(
        modifier
            .fillMaxWidth()
            .figmaCardShadow(shape)
            .background(card, shape)
            .border(1.dp, card.copy(alpha = card.alpha * 0.9f), shape)
            .clip(shape)
            .padding(vertical = 5.dp),
        content = content,
    )
}

/** 1 pt line between rows, from the text column (Figma x 89 in a 354 card) to 17 pt from the right. */
@Composable
fun ProfileDivider(modifier: Modifier = Modifier, leading: Dp = 65.dp) {
    Box(
        modifier
            .padding(start = leading, end = 17.dp)
            .fillMaxWidth()
            .height(1.dp)
            .background(ProfileStyle.divider),
    )
}

/** The 36 pt grey circle with a 16 pt symbol. `symbol == "Aa"` draws the letters (text size row). */
@Composable
fun ProfileIcon(
    symbol: String,
    modifier: Modifier = Modifier,
    tint: Color = ProfileStyle.ink,
    fill: Color = ProfileStyle.iconFill,
) {
    // @ScaledMetric(relativeTo: .body) var size = 36
    val size = scaled(36f)
    Box(
        modifier
            .size(size)
            .background(fill, CircleShape)
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        if (symbol == "Aa") {
            Text("Aa", style = profileFont(15f, FontWeight.SemiBold, rounded = true, tracking = -0.23f), color = tint)
        } else {
            // iOS: semibold rounded symbol weight; Material icons have one weight.
            SfSymbol(symbol, 16f, tint)
        }
    }
}

/** What sits at the right of a row. */
sealed class ProfileRowAccessory {
    object None : ProfileRowAccessory()
    object Chevron : ProfileRowAccessory()
    /** `color` null: `ProfileStyle.secondary`. */
    data class Value(val text: String, val color: Color? = null, val chevron: Boolean = true) : ProfileRowAccessory()
    /** Figma "Status" on Ekstensi Safari: an 8 pt dot and the word, no chevron ("● Terhubung"). */
    data class Status(val text: String, val dot: Color, val color: Color) : ProfileRowAccessory()
}

/**
 * Figma draws two kinds of rows: the Profile cards' rows (58 pt, rounded 13 pt subtitle on a 20 pt line,
 * e.g. "Kabari saya") and the Pengaturan pages' rows (60 pt, SF Pro 13 pt subtitle at 135 %).
 * Swift `ProfileToggleRow.Style`.
 */
enum class ProfileToggleRowStyle { PROFILE, SETTINGS }

/**
 * One 58 pt row: icon, title (+ optional grey subtitle), value / chevron. No icon when `symbol` is null.
 * `title` / `subtitle` are already localized (Swift `Text`). Tap handling is the caller's (`Modifier.clickable`).
 */
@Composable
fun ProfileRow(
    symbol: String?,
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    accessory: ProfileRowAccessory = ProfileRowAccessory.Chevron,
    titleColor: Color = ProfileStyle.ink,
    titleWeight: FontWeight = FontWeight.Normal,
    iconTint: Color = ProfileStyle.ink,
    iconFill: Color = ProfileStyle.iconFill,
    /** 58 for icon rows; 44 for the plain text rows of "Tentang Shoo" (Figma 455:9858). */
    minHeight: Dp = 58.dp,
    /** `SETTINGS`: the Pengaturan pages' look (12 pt padding). */
    style: ProfileToggleRowStyle = ProfileToggleRowStyle.PROFILE,
) {
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = minHeight)
            .padding(
                horizontal = 17.dp,
                vertical = if (minHeight < 58.dp || style == ProfileToggleRowStyle.SETTINGS) 12.dp else 11.dp,
            ),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (symbol != null) ProfileIcon(symbol, tint = iconTint, fill = iconFill)
        // Figma: title and subtitle 2 pt apart, both SF Pro Rounded.
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = profileBody(titleWeight), color = titleColor)
            if (subtitle != null) {
                Text(subtitle, style = profileCaption(), color = ProfileStyle.secondary)
            }
        }
        ProfileRowAccessoryView(accessory)
    }
}

@Composable
private fun ProfileRowAccessoryView(accessory: ProfileRowAccessory) {
    when (accessory) {
        ProfileRowAccessory.None -> Unit
        ProfileRowAccessory.Chevron -> ProfileChevron()
        is ProfileRowAccessory.Value -> Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                accessory.text,
                style = profileValue(),
                color = accessory.color ?: ProfileStyle.secondary,
                textAlign = TextAlign.End,
            )
            if (accessory.chevron) ProfileChevron()
        }
        is ProfileRowAccessory.Status -> Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier
                    .size(8.dp)
                    .background(accessory.dot, CircleShape),
            )
            Text(accessory.text, style = profileBody(), color = accessory.color)
        }
    }
}

@Composable
private fun ProfileChevron() {
    Box(Modifier.clearAndSetSemantics { }) {
        SfSymbol("chevron.right", 14f, ProfileStyle.chevron)
    }
}

/**
 * A row with a switch (Figma "Toggle", green #34C759). No icon when `symbol` is null.
 * iOS: the UISwitch; Android draws Material 3's switch in the iOS colours.
 */
@Composable
fun ProfileToggleRow(
    symbol: String?,
    title: String,
    isOn: Boolean,
    onChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    style: ProfileToggleRowStyle = ProfileToggleRowStyle.PROFILE,
) {
    // Figma: 60 with an icon, 55 without ("Jam tenang"); 58 on the Profile cards.
    val minHeight = if (style == ProfileToggleRowStyle.SETTINGS) (if (symbol == null) 55.dp else 60.dp) else 58.dp
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = minHeight)
            .padding(horizontal = 17.dp, vertical = if (style == ProfileToggleRowStyle.SETTINGS) 12.dp else 11.dp)
            .semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (symbol != null) ProfileIcon(symbol)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = profileBody(), color = ProfileStyle.ink)
            if (subtitle != null) {
                Text(subtitle, style = profileCaption(), color = ProfileStyle.secondary)
            }
        }
        Switch(
            checked = isOn,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = ProfileStyle.green,
                checkedBorderColor = Color.Transparent,
                uncheckedThumbColor = Color.White,
                uncheckedTrackColor = hex(0x787880, 0.16f),
                uncheckedBorderColor = Color.Transparent,
            ),
        )
    }
}

// MARK: Profile card

/** One number of the stats strip. `label` is a catalog key. */
data class ProfileStat(val value: String, val label: String) {
    val id: String get() = label
}

/** The grey strip of 2–3 numbers at the bottom of the profile card (Figma "Statistik"). */
@Composable
fun ProfileStatsStrip(stats: List<ProfileStat>, modifier: Modifier = Modifier) {
    Row(
        modifier
            .fillMaxWidth()
            .background(ProfileStyle.background, RoundedCornerShape(18.dp)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        stats.forEachIndexed { index, stat ->
            if (index > 0) {
                Box(
                    Modifier
                        .width(1.dp)
                        .height(32.dp)
                        .background(ProfileStyle.statsDivider),
                )
            }
            Column(
                Modifier
                    .weight(1f)
                    .padding(vertical = 14.dp)
                    .semantics(mergeDescendants = true) { },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    stat.value,
                    style = profileFont(20f, FontWeight.SemiBold, tracking = -0.45f, lineHeight = 25f),
                    color = ProfileStyle.nameInk,
                )
                Text(
                    t(stat.label),
                    style = profileCaption(),
                    color = ProfileStyle.secondary,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

/**
 * The avatar's drop shadow. Figma: none on the Guardian / Pribadi memoji and on the member detail; a blue glow on
 * the Protected profile ("Profile", #1F78BF 18 %, y 7.68, blur 23). Swift `ProfileHeaderCard.AvatarShadow`.
 */
enum class ProfileAvatarShadow { NONE, GLOW }

/**
 * The white card with banner, avatar, name, handle and stats (Figma "Profil Card", r 32, 12 pt inset).
 * `banner`: the banner drawable (`R.drawable.profile_banner`, `R.drawable.member_banner`).
 * `badgeBottom`: the badge's bottom edge against the avatar's: 5 pt below for "Bagikan undangan", 26 pt above
 * (−26) for the Protected "Terhubung" pill, 1 pt above (−1) for a member's "Perlindungan aktif" (Figma).
 * `attachment`: Figma "Pesan ekstensi mati" (1681:6718), a strip across the card's foot.
 */
@Composable
fun ProfileHeaderCard(
    @DrawableRes banner: Int,
    name: String,
    handle: String,
    stats: List<ProfileStat>,
    modifier: Modifier = Modifier,
    bannerHeight: Dp = 128.dp,
    avatarShadow: ProfileAvatarShadow = ProfileAvatarShadow.NONE,
    badgeBottom: Dp = 5.dp,
    attachment: (@Composable () -> Unit)? = null,
    avatar: @Composable () -> Unit,
    badge: @Composable () -> Unit = {},
) {
    val shape = RoundedCornerShape(32.dp)
    val card = ProfileStyle.card
    // Figma: 9 under the stats, 10 under the handle when the stats are hidden.
    val bottomPadding = if (stats.isEmpty()) 10.dp else 9.dp
    Column(
        modifier
            .padding(horizontal = 16.dp)
            .fillMaxWidth()
            .shooShadow(ProfileStyle.cardShadow, radius = 8.dp, y = 6.dp, shape = shape)
            .background(card, shape)
            .border(1.dp, card.copy(alpha = card.alpha * 0.9f), shape)
            .clip(shape)
            .padding(start = 12.dp, end = 12.dp, top = 12.dp, bottom = bottomPadding),
    ) {
        Image(
            painter = painterResource(banner),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .fillMaxWidth()
                .height(bannerHeight)
                .clip(RoundedCornerShape(24.dp)),
        )
        Row(
            Modifier
                .padding(horizontal = 12.dp)
                .fillMaxWidth()
                // `.padding(.top, -52)`: the avatar overlaps the banner.
                .pullUp(52.dp),
            verticalAlignment = Alignment.Bottom,
        ) {
            Box(
                Modifier
                    .shooShadow(
                        if (avatarShadow == ProfileAvatarShadow.GLOW) ProfileStyle.avatarGlow else Color.Transparent,
                        radius = 11.5.dp, y = 7.7.dp, shape = CircleShape,
                    )
                    .background(card, CircleShape)
                    .padding(4.dp)
                    .size(88.dp)
                    .clearAndSetSemantics { },
                contentAlignment = Alignment.Center,
            ) { avatar() }
            Spacer(Modifier.width(8.dp))
            Spacer(Modifier.weight(1f))
            // `.padding(.bottom, -badgeBottom)`: drawn `badgeBottom` lower than the avatar's bottom edge.
            Box(Modifier.offset(y = badgeBottom)) { badge() }
        }
        // Figma (1115:14392): SF Pro Display Bold 22 on a 28 pt line, the handle 4 pt under it.
        Column(
            Modifier
                .padding(horizontal = 12.dp)
                .padding(top = 12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                name,
                style = profileFont(22f, FontWeight.Bold, tracking = -0.26f, lineHeight = 28f),
                color = ProfileStyle.nameInk,
                modifier = Modifier.semantics { heading() },
            )
            if (handle.isNotEmpty()) {
                Text(handle, style = profileValue(), color = ProfileStyle.secondary)
            }
        }
        if (stats.isNotEmpty()) {
            // Figma: 10 under the handle; 12 under the name when there is no handle (Protected).
            ProfileStatsStrip(stats, Modifier.padding(top = if (handle.isEmpty()) 12.dp else 10.dp))
        }
        if (attachment != null) {
            // Edge to edge at the card's foot, under the stats (Figma: 12 under them).
            Box(
                Modifier
                    .padding(top = 12.dp)
                    .bleed(horizontal = 12.dp, bottom = bottomPadding),
            ) { attachment() }
        }
    }
}

/** SwiftUI `.padding(.top, -amount)`: moves the content up and takes `amount` off its height. */
private fun Modifier.pullUp(amount: Dp): Modifier = layout { measurable, constraints ->
    val px = amount.roundToPx()
    val placeable = measurable.measure(constraints)
    layout(placeable.width, (placeable.height - px).coerceAtLeast(0)) {
        placeable.place(0, -px)
    }
}

/** SwiftUI `.padding(.horizontal, -h).padding(.bottom, -b)`: grows past the parent's padding on both sides and the foot. */
private fun Modifier.bleed(horizontal: Dp, bottom: Dp): Modifier = layout { measurable, constraints ->
    val h = horizontal.roundToPx()
    val b = bottom.roundToPx()
    val wider = constraints.copy(
        minWidth = (constraints.minWidth + h * 2).coerceAtMost(constraints.maxWidth + h * 2),
        maxWidth = if (constraints.hasBoundedWidth) constraints.maxWidth + h * 2 else constraints.maxWidth,
    )
    val placeable = measurable.measure(wider)
    val width = (placeable.width - h * 2).coerceAtLeast(0)
    layout(width, (placeable.height - b).coerceAtLeast(0)) {
        placeable.place(-h, 0)
    }
}

/**
 * White capsule with a grey border ("Bagikan undangan", "Ingatkan"). Swift `ProfilePillButtonStyle` as a button
 * composable: the `content` row gets the pill's text style and colour (`LocalTextStyle`, `LocalContentColor`).
 * `large`: Figma 1115:14655 "Ingatkan", SF Pro Rounded 17 at 140 % (88 × 38); `false`: the older 14 pt pills.
 */
@Composable
fun ProfilePillButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    tint: Color = ProfileStyle.ink,
    padding: PaddingValues = ProfilePillButtonDefaults.padding,
    large: Boolean = false,
    enabled: Boolean = true,
    testTag: String? = null,
    content: @Composable RowScope.() -> Unit,
) {
    val tag = testTag
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val reduceMotion = LocalReduceMotion.current
    val alpha by animateFloatAsState(if (pressed) 0.6f else 1f, shooEaseOut(0.15), label = "pillAlpha")
    // Gives under the finger like the onboarding pill; Reduce Motion: the dim alone.
    val scale by animateFloatAsState(if (pressed && !reduceMotion) 0.97f else 1f, shooEaseOut(0.15), label = "pillScale")
    val textStyle = if (large) profileValue() else profileFont(14f, FontWeight.Medium, tracking = -0.14f)
    Box(
        modifier
            .heightIn(min = 44.dp)
            .clickable(interaction, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .then(if (tag != null) Modifier.semantics { this.testTag = tag } else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            Modifier
                .scale(scale)
                .alpha(alpha)
                .background(ProfileStyle.card, CapsuleShape)
                .border(1.dp, ProfileStyle.pillStroke, CapsuleShape)
                .padding(padding),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CompositionLocalProvider(LocalTextStyle provides textStyle, LocalContentColor provides tint) {
                content()
            }
        }
    }
}

/**
 * Figma "Ingatkan": 6 / 12 inside its 1 pt border (78 × 31). "Bagikan Undangan": 9 top and bottom, 12 leading,
 * 16 trailing inside the border (165 × 37). Figma counts the border in the layout.
 */
object ProfilePillButtonDefaults {
    val padding = PaddingValues(start = 13.dp, top = 7.dp, end = 13.dp, bottom = 7.dp)
    val invitePadding = PaddingValues(start = 13.dp, top = 10.dp, end = 17.dp, bottom = 10.dp)
}

/** Figma "QR Icon": three corner squares and four dots, 16 pt. */
@Composable
fun QRGlyph(modifier: Modifier = Modifier) {
    val ink = ProfileStyle.ink
    val density = LocalDensity.current
    Canvas(
        modifier
            .size(16.dp)
            .clearAndSetSemantics { },
    ) {
        val s = size.width / 16f
        val line = with(density) { 1.6.dp.toPx() }
        val inset = line / 2
        for (origin in listOf(Offset(0f, 0f), Offset(10f, 0f), Offset(0f, 10f))) {
            drawRoundRect(
                color = ink,
                topLeft = Offset(origin.x * s + inset, origin.y * s + inset),
                size = Size(6 * s - line, 6 * s - line),
                cornerRadius = CornerRadius(1.5f * s),
                style = Stroke(width = line),
            )
        }
        for ((x, y) in listOf(10f to 10f, 13.5f to 13.5f, 13.5f to 10f, 10f to 13.5f)) {
            drawRoundRect(
                color = ink,
                topLeft = Offset(x * s, y * s),
                size = Size(2.5f * s, 2.5f * s),
                cornerRadius = CornerRadius(0.6f * s),
            )
        }
    }
}

/** "Diblokir" / "Waspada" chip on activity rows (Figma "Button" instance). */
@Composable
fun ProfileScanChip(status: ScanStatus, modifier: Modifier = Modifier) {
    val blocked = status == ScanStatus.BLOCKED
    val blockedInk = dynamicColor(0xBB1616, 0xFF7A7A)
    val cautionInk = dynamicColor(0x9A5A00, 0xF5B04A)
    val fill = if (blocked) dynamicColor(0xFFF4F4, 0x3A1D1D) else dynamicColor(0xFFF8EF, 0x382A14)
    val stroke = if (blocked) dynamicColor(0xFFCDCD, 0x5C2A2A) else dynamicColor(0xFFE1B6, 0x5A4220)
    Row(
        modifier
            .background(fill, CapsuleShape)
            .border(0.75.dp, stroke, CapsuleShape)
            // Figma: 6 / 8 around an 11 pt line (23 pt tall).
            .padding(horizontal = 8.dp, vertical = 3.5.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Figma: an 11 pt frame holding an 8.9 pt filled "!" circle.
        Box(
            Modifier
                .size(11.dp)
                .clearAndSetSemantics { },
            contentAlignment = Alignment.Center,
        ) {
            SfSymbol("exclamationmark.circle.fill", 9.5f, if (blocked) blockedInk else hex(0xD67D00))
        }
        Text(
            t(if (blocked) "Blocked" else "Caution"),
            style = profileFont(13f, tracking = -0.16f),
            // Figma's #D67D00 is about 3:1 on its tint; this darker orange keeps the text readable (4.5:1).
            color = if (blocked) blockedInk else cautionInk,
        )
    }
}

// MARK: Confirm sheet

/**
 * Figma "Sheet": avatar with a red minus badge, title, message, a red gradient button and Cancel.
 * Used for "Putuskan koneksi" and "Hapus akun". `title` / `message` / `confirmTitle` are already localized.
 *
 * The content of a sheet: the caller shows it in a `ModalBottomSheet` with `containerColor = ProfileStyle.card`,
 * no drag handle (this draws its own grabber), sized to its content (iOS `.presentationDetents([.height(h)])`), and
 * no dismiss while `isWorking` (iOS `.interactiveDismissDisabled`). `onCancel` dismisses it.
 */
@Composable
fun ProfileConfirmSheet(
    title: String,
    message: String,
    confirmTitle: String,
    confirmIdentifier: String,
    isWorking: Boolean,
    onConfirm: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
    avatar: @Composable () -> Unit,
) {
    val card = ProfileStyle.card
    val red = ProfileStyle.red
    // Figma "Putuskan": #FF4F4F near the top to #BB1616 three quarters down (its gradient runs vertically).
    val dangerGradient = Brush.verticalGradient(0.05f to hex(0xFF4F4F), 0.75f to hex(0xBB1616))
    val density = LocalDensity.current
    // Figma: icon and label cast black 20 %, y 4, blur 4.
    val labelShadow = with(density) {
        Shadow(Color.Black.copy(alpha = 0.2f), Offset(0f, 4.dp.toPx()), ((2.dp.toPx() - 0.5f) / 0.57735f).coerceAtLeast(0f))
    }
    Column(
        modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp)
            .padding(bottom = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .padding(top = 10.dp)
                .size(width = 36.dp, height = 5.dp)
                .background(ProfileStyle.grabber, CapsuleShape),
        )
        Box(
            Modifier
                .padding(top = 22.dp)
                .clearAndSetSemantics { },
        ) {
            Box(Modifier.size(64.dp)) { avatar() }
            // Figma "Minus": 24 pt red circle, 2.5 pt white ring, a 10 × 3 white bar.
            Box(
                Modifier
                    .align(Alignment.BottomEnd)
                    .offset(x = 4.dp, y = 4.dp)
                    .size(24.dp)
                    .background(red, CircleShape)
                    .border(2.5.dp, card, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    Modifier
                        .size(width = 10.dp, height = 3.dp)
                        .background(Color.White, RoundedCornerShape(1.25.dp)),
                )
            }
        }
        Text(
            title,
            style = profileFont(22f, FontWeight.SemiBold, tracking = -0.44f),
            color = ProfileStyle.nameInk,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .padding(top = 18.dp)
                .semantics { heading() },
        )
        // `.lineSpacing(4)`: 15 pt text on a ~22 pt line.
        Text(
            message,
            style = profileFont(15f, tracking = -0.15f, lineHeight = 22f),
            color = ProfileStyle.secondary,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 8.dp),
        )
        Column(
            Modifier
                .padding(top = 24.dp)
                .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            val confirmInteraction = remember { MutableInteractionSource() }
            val confirmPressed by confirmInteraction.collectIsPressedAsState()
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 56.dp)
                    .background(dangerGradient, CapsuleShape)
                    .border(1.5.dp, hex(0xBB1616), CapsuleShape)
                    .clip(CapsuleShape)
                    .clickable(confirmInteraction, indication = null, enabled = !isWorking, role = Role.Button, onClick = onConfirm)
                    .alpha(if (confirmPressed) 0.8f else 1f)
                    .semantics { testTag = confirmIdentifier },
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Icon ↔ spinner: a 0.2 s cross-fade like "Remind".
                Crossfade(targetState = isWorking, animationSpec = shooEaseInOut(0.2), label = "confirmIcon") { working ->
                    Box(Modifier.size(22.dp), contentAlignment = Alignment.Center) {
                        if (working) {
                            CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
                        } else {
                            Box(Modifier.clearAndSetSemantics { }) {
                                SfSymbol("exclamationmark.circle.fill", 19f, Color.White)
                            }
                        }
                    }
                }
                Text(
                    confirmTitle,
                    style = profileFont(17f, FontWeight.SemiBold, tracking = -0.21f).copy(shadow = labelShadow),
                    color = Color.White,
                )
            }
            val cancelInteraction = remember { MutableInteractionSource() }
            val cancelPressed by cancelInteraction.collectIsPressedAsState()
            Box(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 56.dp)
                    .background(ProfileStyle.iconFill, CapsuleShape)
                    .clip(CapsuleShape)
                    .clickable(cancelInteraction, indication = null, enabled = !isWorking, role = Role.Button, onClick = onCancel)
                    .alpha(if (cancelPressed) 0.7f else if (isWorking) 0.5f else 1f)
                    .semantics { testTag = "profile.confirm.cancel" },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    t("Cancel"),
                    style = profileFont(17f, FontWeight.SemiBold, tracking = -0.17f),
                    color = ProfileStyle.ink,
                )
            }
        }
    }
}
