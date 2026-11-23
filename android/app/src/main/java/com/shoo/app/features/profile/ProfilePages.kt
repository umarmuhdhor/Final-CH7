package com.shoo.app.features.profile

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.annotation.DrawableRes
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TimeInput
import androidx.compose.material3.TimePickerDefaults
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.intl.LocaleList
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.shoo.app.BuildConfig
import com.shoo.app.R
import com.shoo.app.app.AppConfig
import com.shoo.app.app.DataConsent
import com.shoo.app.app.LocalAppEnvironment
import com.shoo.app.app.ProfilePage
import com.shoo.app.app.Route
import com.shoo.app.components.AppTheme
import com.shoo.app.components.AvatarRing
import com.shoo.app.components.AvatarView
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.ShieldPulseLoader
import com.shoo.app.components.StateMotion
import com.shoo.app.components.TextSizeLevel
import com.shoo.app.components.dynamicColor
import com.shoo.app.components.figmaTextStyle
import com.shoo.app.components.hex
import com.shoo.app.components.readableRed
import com.shoo.app.components.shooEaseInOut
import com.shoo.app.components.shooEaseOut
import com.shoo.app.components.shooShadow
import com.shoo.app.components.shooSnappy
import com.shoo.app.data.FamilyMember
import com.shoo.app.data.GuardianInfo
import com.shoo.app.data.LinkedAccountSettings
import com.shoo.app.data.NotificationSettingsUpdate
import com.shoo.app.features.detail.privacyCover
import com.shoo.app.features.onboarding.NameRule
import com.shoo.app.features.onboarding.OnboardingCapsuleButton
import com.shoo.app.features.pairing.ConnectModel
import com.shoo.app.features.pairing.ConnectView
import com.shoo.app.support.AppLanguage
import com.shoo.app.support.Formatters
import com.shoo.app.support.L10n
import com.shoo.app.support.NotificationAuthorization
import com.shoo.app.support.t
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.Date
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlinx.coroutines.launch

/** Profile's sub-screens (PF-01, Figma "Pengaturan/…"), in the same style as Profile. */
@Composable
fun ProfilePageView(page: ProfilePage, modifier: Modifier = Modifier) {
    val env = LocalAppEnvironment.current
    val feedback = rememberSensoryFeedback()
    val model = remember(env.repository) {
        ProfileModel(env.repository, env.settings, env.notifications, linked = LinkedAccountSettings(env.appGroupDefaults)).also {
            it.onSessionEnd = { env.returnToOnboardingAfterDelete() }
            it.onForgetDevice = { linked -> env.forgetDeletedDevice(linked) }
        }
    }
    LaunchedEffect(model, page) {
        if (page in setOf(ProfilePage.MODE, ProfilePage.EDIT_PROFILE, ProfilePage.CONNECTION, ProfilePage.NOTIFICATIONS, ProfilePage.LANGUAGE)) {
            model.load()
        }
    }
    // A new name or avatar saved (the Kelola profil sheets close on success).
    OnChange(model.profileSaves) { _, _ -> feedback(ProfileHaptic.SUCCESS) }
    // Member and Guardian names: covered in the recent-apps snapshot, as on Profile (BH-33, SECURITY §3 P13).
    Box(modifier.fillMaxSize().privacyCover()) {
        when (page) {
            ProfilePage.MODE -> ModePage(model)
            ProfilePage.EDIT_PROFILE -> ManageProfilePage(model)
            ProfilePage.CONNECTION -> ConnectionPage(model)
            ProfilePage.NOTIFICATIONS -> NotificationsPage(model)
            ProfilePage.LANGUAGE -> LanguagePage(model)
            ProfilePage.THEME -> ThemePage()
            ProfilePage.ACCESSIBILITY -> AccessibilityPage()
            ProfilePage.ABOUT -> AboutPage()
            ProfilePage.LICENSES -> LicensesPage()
        }
    }
}

// MARK: Shared pieces

/** Figma "Radio": a 24 pt ring, filled blue with a white dot when chosen. Ring ↔ fill: a 0.2 s cross-fade. */
@Composable
fun ProfileRadio(isOn: Boolean, modifier: Modifier = Modifier) {
    val link = ProfileStyle.link
    val ring = ProfileStyle.radioOff
    Crossfade(
        targetState = isOn,
        animationSpec = shooEaseInOut(0.2),
        label = "radio",
        modifier = modifier
            .size(24.dp)
            .clearAndSetSemantics { },
    ) { on ->
        Canvas(Modifier.size(24.dp)) {
            if (on) {
                drawCircle(link)
                drawCircle(Color.White, radius = 4.5.dp.toPx())
            } else {
                val line = 1.5.dp.toPx()
                drawCircle(ring, radius = size.minDimension / 2 - line / 2, style = Stroke(line))
            }
        }
    }
}

/**
 * A choice in a Profile list eases into its chosen look and taps once (pattern: the onboarding avatars).
 * Reduce Motion: a 0.2 s ease. `movesLayout`: the choice changes its size, so Reduce Motion snaps it instead.
 * Swift `ProfileSelectionMotion`: the animation spec, plus the selection haptic below.
 */
private fun <T> selectionSpec(reduceMotion: Boolean, movesLayout: Boolean = false): AnimationSpec<T> =
    if (reduceMotion) (if (movesLayout) snap() else shooEaseInOut(0.2)) else shooSnappy(0.2)

@Composable
private fun SelectionHaptic(isSelected: Boolean) {
    val feedback = rememberSensoryFeedback()
    OnChange(isSelected) { _, now -> if (now) feedback(ProfileHaptic.SELECTION) }
}

/** A 64 pt row with a title, a grey subtitle and a radio (Figma "Pengaturan/Bahasa"). */
@Composable
private fun RadioRow(
    title: AnnotatedString,
    subtitle: String?,
    isSelected: Boolean,
    action: () -> Unit,
    modifier: Modifier = Modifier,
) {
    SelectionHaptic(isSelected)
    Row(
        modifier
            .fillMaxWidth()
            .plainClickable(onClick = action)
            .semantics(mergeDescendants = true) { selected = isSelected }
            .heightIn(min = 64.dp)
            .padding(horizontal = 17.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = profileFont(17f, tracking = -0.17f), color = ProfileStyle.ink)
            if (subtitle != null) Text(subtitle, style = profileFont(13f), color = ProfileStyle.secondary)
        }
        ProfileRadio(isOn = isSelected)
    }
}

/** Grey label above a value, with a chevron (Figma "Info pribadi" rows, 1278:12077: 62 pt, 10 pt padding). */
@Composable
private fun LabeledRow(label: String, value: String, modifier: Modifier = Modifier, showsChevron: Boolean = true) {
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 62.dp)
            .padding(horizontal = 17.dp, vertical = 10.dp)
            .semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(label, style = profileCaption(), color = ProfileStyle.secondary)
            Text(value, style = profileBody(), color = ProfileStyle.ink)
        }
        if (showsChevron) ProfileRowChevron()
    }
}

/** Grey note under a card. `.lineSpacing(3)`: 13 pt text on a ~18.5 pt line. */
@Composable
private fun PageNote(
    text: String,
    modifier: Modifier = Modifier,
    center: Boolean = false,
    horizontalPadding: Dp = ProfileStyle.margin + 16.dp,
) {
    Text(
        text,
        style = profileFont(13f, lineHeight = 18.5f),
        color = ProfileStyle.secondary,
        textAlign = if (center) TextAlign.Center else TextAlign.Start,
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = horizontalPadding)
            .padding(top = 10.dp),
    )
}

/** `ProfileToggleRow` that can be disabled (iOS `.disabled(_:)` dims the switch). Foundation's row has no `enabled`. */
@Composable
private fun ProfileToggleRowEnabled(
    symbol: String?,
    title: String,
    isOn: Boolean,
    onChange: (Boolean) -> Unit,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    style: ProfileToggleRowStyle = ProfileToggleRowStyle.PROFILE,
) {
    if (enabled) {
        ProfileToggleRow(symbol, title, isOn, onChange, modifier, subtitle, style)
        return
    }
    val minHeight = if (style == ProfileToggleRowStyle.SETTINGS) (if (symbol == null) 55.dp else 60.dp) else 58.dp
    val green = ProfileStyle.green
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
            if (subtitle != null) Text(subtitle, style = profileCaption(), color = ProfileStyle.secondary)
        }
        Switch(
            checked = isOn,
            onCheckedChange = null,
            enabled = false,
            colors = SwitchDefaults.colors(
                disabledCheckedThumbColor = Color.White,
                disabledCheckedTrackColor = green.copy(alpha = 0.5f),
                disabledCheckedBorderColor = Color.Transparent,
                disabledUncheckedThumbColor = Color.White,
                disabledUncheckedTrackColor = hex(0x787880, 0.08f),
                disabledUncheckedBorderColor = Color.Transparent,
            ),
        )
    }
}

// MARK: Mode akun

/**
 * Pribadi ↔ Guardian (Family mode); members stay connected. "Punya kode undangan?" joins another family as protected
 * (only without members). Protected devices get "Terhubung" instead.
 */
@Composable
private fun ModePage(model: ProfileModel) {
    val env = LocalAppEnvironment.current
    val language = LocalAppLanguage.current
    val reduceMotion = LocalReduceMotion.current
    val view = LocalView.current
    var selected by remember { mutableStateOf<ProfileModel.Variant?>(null) }
    var isJoinPresented by remember { mutableStateOf(false) }
    var isJoinLocked by remember { mutableStateOf(false) }

    // A protected phone without a guardian works like Pribadi (QA 2026-11-10 #4: no card was marked). It can't become
    // a Guardian: the device mode never changes on the server.
    fun current(): ProfileModel.Variant =
        if (model.variant == ProfileModel.Variant.PROTECTED) ProfileModel.Variant.PERSONAL else model.variant
    val isProtected = model.variant == ProfileModel.Variant.PROTECTED
    val choice = selected ?: current()
    // A guardian who still protects someone, or a protected person with a guardian, can't join another family. Only
    // once the profile and family have loaded: no lock without the server's answer (the join answers then).
    val isLocked = model.state == ProfileModel.State.LOADED && !model.membersFailed && !model.canJoinAnotherFamily
    val lockAlpha by animateFloatAsState(if (isLocked) 0.45f else 1f, StateMotion.enter(reduceMotion), label = "lock")

    ProfileScreen(title = "Account mode", onBack = { env.router.pop() }) {
        Text(
            t("Choose how you use Shoo. You can switch at any time."),
            style = profileFont(15f, lineHeight = 21f),
            color = ProfileStyle.secondary,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = ProfileStyle.margin + 16.dp)
                .padding(bottom = 8.dp),
        )

        Column(
            Modifier
                .padding(horizontal = ProfileStyle.margin)
                .padding(top = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            ModeCard(
                title = t("Personal"), subtitle = t("Protect yourself"),
                features = listOf(t("Scam sites blocked automatically"), t("A warning on risky sites"), t("Your own activity history")),
                isCurrent = current() == ProfileModel.Variant.PERSONAL,
                isSelected = choice == ProfileModel.Variant.PERSONAL,
                icon = {
                    Box(
                        Modifier
                            .size(44.dp)
                            .background(ModeCardColor.iconFill, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        SfSymbol("person.fill", 18f, ProfileStyle.link)
                    }
                },
                action = { selected = ProfileModel.Variant.PERSONAL },
                modifier = Modifier.semantics { testTag = "mode.personal" },
            )
            ModeCard(
                title = t("Guardian"), subtitle = t("Protect the people close to you"),
                features = listOf(t("Everything in Personal"), t("Look after up to 3 people"), t("Confirm warnings for them")),
                isCurrent = current() == ProfileModel.Variant.GUARDIAN,
                isSelected = choice == ProfileModel.Variant.GUARDIAN,
                enabled = !isProtected,
                icon = { AvatarStack(members = model.members) },
                action = { selected = ProfileModel.Variant.GUARDIAN },
                modifier = Modifier
                    .alpha(if (isProtected) 0.45f else 1f)
                    .semantics { testTag = "mode.guardian" },
            )
        }

        // Figma "Mode akun · Terkunci" (1619:7207): the row fades and says why right under it.
        ProfileCard(
            Modifier
                .padding(horizontal = ProfileStyle.margin)
                .padding(top = 28.dp)
                .alpha(lockAlpha),
        ) {
            ProfileRow(
                symbol = ProfileStyle.extensionSymbol, title = t("Have an invite code?"),
                subtitle = t("Connect your account to a family guardian"),
                modifier = Modifier
                    .plainClickable(enabled = !isLocked) {
                        // Already protected: a plain join with the code (POST /family/join), as on Home.
                        if (isProtected) env.router.showConnect() else isJoinPresented = true
                    }
                    .semantics { testTag = "mode.joinFamily" },
            )
        }
        // iOS: `.transition(.opacity)`, but only the card above carries the animation: the note appears at once.
        if (isLocked) {
            PageNote(
                if (isProtected) {
                    t("Only your guardian can disconnect you. Ask them first, then join another family.")
                } else {
                    t("Disconnect the people you protect first. Then you can join another family.")
                },
                horizontalPadding = ProfileStyle.margin,
                modifier = Modifier.semantics { testTag = "mode.locked" },
            )
        }

        if (choice != current()) {
            val switchedGuardian = t("Switched to Guardian")
            val switchedPersonal = t("Switched to Personal")
            Box(
                Modifier
                    .padding(horizontal = ProfileStyle.margin)
                    .padding(top = 28.dp)
                    .fillMaxWidth()
                    .heightIn(min = 52.dp)
                    .background(ProfileStyle.primaryFill, CapsuleShape)
                    .plainClickable {
                        val target = choice
                        if (target == ProfileModel.Variant.GUARDIAN) env.requestFamilyMode() else model.setFamilyMode(false)
                        selected = null
                        // The first Guardian switch only opens "To be guardian": nothing switched yet, nothing to say.
                        if (current() != target) return@plainClickable
                        view.announce(if (target == ProfileModel.Variant.GUARDIAN) switchedGuardian else switchedPersonal)
                    }
                    .semantics { testTag = "mode.switch" },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    t(if (choice == ProfileModel.Variant.GUARDIAN) "Switch to Guardian" else "Switch to Personal"),
                    style = profileFont(17f, FontWeight.SemiBold, tracking = -0.17f),
                    color = ProfileStyle.primaryText,
                )
            }
        }
        if (!isLocked) {
            PageNote(
                t("Your protection stays on. You can switch back to Personal at any time."),
                center = true,
                modifier = Modifier.padding(top = if (choice != current()) 0.dp else 18.dp),
            )
        }
    }

    ProfileSheet(
        isPresented = isJoinPresented,
        onDismissRequest = { isJoinPresented = false },
        canDismiss = !isJoinLocked,
        containerColor = ProfileStyle.background,
        cornerRadius = 24.dp,
    ) {
        JoinAnotherFamilySheet(
            name = model.profile?.name ?: "",
            onDismiss = { isJoinPresented = false },
            onInteractiveDismissDisabledChange = { isJoinLocked = it },
        )
    }
}

private object ModeCardColor {
    val iconFill: Color @Composable get() = dynamicColor(0xEEF4FB, 0x1C2A3B)
    val selectedFill: Color @Composable get() = dynamicColor(0xF3F8FE, 0x16263A)
    val selectedDivider: Color @Composable get() = dynamicColor(0xD6E6F7, 0x27405E)
}

/** Figma "Mode Pribadi" / "Mode Guardian": icon, title (+ "Saat ini"), subtitle, radio, three features. */
@Composable
private fun ModeCard(
    title: String,
    subtitle: String,
    features: List<String>,
    isCurrent: Boolean,
    isSelected: Boolean,
    icon: @Composable () -> Unit,
    action: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val reduceMotion = LocalReduceMotion.current
    SelectionHaptic(isSelected)
    val shape = RoundedCornerShape(24.dp)
    val fill by animateColorAsState(if (isSelected) ModeCardColor.selectedFill else ProfileStyle.card, selectionSpec(reduceMotion), label = "modeFill")
    val stroke by animateColorAsState(if (isSelected) ProfileStyle.link else ProfileStyle.card, selectionSpec(reduceMotion), label = "modeStroke")
    val divider by animateColorAsState(if (isSelected) ModeCardColor.selectedDivider else ProfileStyle.divider, selectionSpec(reduceMotion), label = "modeDivider")
    val check by animateColorAsState(if (isSelected) ProfileStyle.link else ProfileStyle.chevron, selectionSpec(reduceMotion), label = "modeCheck")
    val strokeWidth by animateDpAsState(if (isSelected) 1.5.dp else 1.dp, selectionSpec(reduceMotion), label = "modeStrokeWidth")
    Column(
        modifier
            .fillMaxWidth()
            .background(fill, shape)
            .border(strokeWidth, stroke, shape)
            .plainClickable(enabled = enabled, onClick = action)
            .semantics(mergeDescendants = true) { selected = isSelected }
            .padding(19.dp),
        verticalArrangement = Arrangement.spacedBy(15.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            icon()
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(title, style = profileFont(19f, FontWeight.SemiBold, tracking = -0.38f), color = ProfileStyle.nameInk)
                    if (isCurrent) {
                        Text(
                            t("Current"),
                            style = profileFont(12f, FontWeight.Medium),
                            color = dynamicColor(0x3A3D42, 0xD5D9E0),
                            modifier = Modifier
                                .background(dynamicColor(0xE6E8EC, 0x2E343E), CapsuleShape)
                                .padding(horizontal = 8.dp, vertical = 2.dp),
                        )
                    }
                }
                Text(subtitle, style = profileFont(14f), color = ProfileStyle.secondary)
            }
            ProfileRadio(isOn = isSelected)
        }
        Box(
            Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(divider),
        )
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            features.forEach { feature ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.clearAndSetSemantics { }) { SfSymbol("checkmark.circle.fill", 13f, check) }
                    Text(feature, style = profileFont(15f), color = ProfileStyle.ink)
                }
            }
        }
    }
}

/** Three overlapping avatars: the members', or three neutral person placeholders without any. */
@Composable
private fun AvatarStack(members: List<FamilyMember>) {
    // "" is no avatar: `AvatarView` draws the neutral person.
    val ids = if (members.isEmpty()) listOf("", "", "") else members.take(3).map { it.avatarId }
    Box(
        Modifier
            .width(64.dp)
            .clearAndSetSemantics { },
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy((-10).dp)) {
            ids.forEach { id -> AvatarView(id = id, size = 28.dp, ring = AvatarRing(color = ProfileStyle.card, width = 1.5.dp)) }
        }
    }
}

/**
 * "Punya kode undangan?", Home Pribadi "Mode Terawasi" and an invite link (PR-03): the Connect screen, joining as
 * protected (a new device on the server). An empty `name` is read from the server first. A link's code is filled in,
 * so the only step left is the Hubungkan tap (T11); "Nanti saja" then closes it.
 *
 * The content of a sheet; the caller presents it (full height). Android only:
 * - `onDismiss`: iOS `@Environment(\.dismiss)`; null closes `router.isJoinFamilyPresented` (MainTabView's sheet).
 * - `onInteractiveDismissDisabledChange`: iOS `.interactiveDismissDisabled(…)`; the presenter blocks swipe and Back
 *   while it is true (joining, or joined: the old device is gone).
 */
@Composable
fun JoinAnotherFamilySheet(
    name: String,
    onDismiss: (() -> Unit)? = null,
    onInteractiveDismissDisabledChange: (Boolean) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val env = LocalAppEnvironment.current
    val dismiss: () -> Unit = onDismiss ?: { env.router.isJoinFamilyPresented = false }
    var model by remember { mutableStateOf<ConnectModel?>(null) }
    var cameFromLink by remember { mutableStateOf(false) }
    val currentName by rememberUpdatedState(name)

    LaunchedEffect(Unit) {
        if (model != null) return@LaunchedEffect
        val code = env.router.takePendingJoinCode()
        cameFromLink = code != null
        model = ConnectModel(
            repository = env.repository,
            code = code,
            join = { joinCode ->
                val joinName = currentName.ifEmpty { env.repository.me().name }
                env.becomeProtected(code = joinCode, name = joinName)
            },
        )
    }
    // A second link while this is open: the new code replaces the old one.
    OnChange(env.router.pendingJoinCode) { _, code ->
        if (code == null) return@OnChange
        val pending = env.router.takePendingJoinCode() ?: return@OnChange
        cameFromLink = true
        model?.prefill(pending)
    }
    val current = model
    // Once joined the old device is gone: no swipe back to a screen that no longer exists. While joining too: swiped
    // away, the join went on unseen and `onFinish` never closed the Guardian screens of a now Protected phone.
    val locked = current != null && (current.state is ConnectModel.State.Joined || current.state == ConnectModel.State.Joining)
    LaunchedEffect(locked) { onInteractiveDismissDisabledChange(locked) }
    BackHandler(enabled = locked) { }

    if (current != null) {
        ConnectView(
            model = current,
            onBack = dismiss,
            onSkip = if (cameFromLink) dismiss else null,
            onFinish = {
                dismiss()
                env.router.reset()
            },
            modifier = modifier.fillMaxSize(),
        )
    } else {
        Box(
            modifier
                .fillMaxSize()
                .background(ProfileStyle.background),
        )
    }
}

// MARK: Kelola profil

@Composable
private fun ManageProfilePage(model: ProfileModel) {
    if (model.variant == ProfileModel.Variant.PROTECTED) {
        ProtectedManageProfilePage(model)
    } else {
        GuardianManageProfilePage(model)
    }
}

/**
 * Figma "Pengaturan/Kelola profil" (416:12854): avatar with an edit badge, "Ubah avatar", Info pribadi (name, status),
 * the people this guardian protects, and "Hapus akun". No phone number row.
 */
@Composable
private fun GuardianManageProfilePage(model: ProfileModel) {
    val env = LocalAppEnvironment.current
    val scope = rememberCoroutineScope()
    var isAvatarPickerPresented by remember { mutableStateOf(false) }
    var isNamePresented by remember { mutableStateOf(false) }
    var isDeleteConfirming by remember { mutableStateOf(false) }

    DeleteAccountSheet(model = model, isPresented = isDeleteConfirming, onIsPresentedChange = { isDeleteConfirming = it }) {
        ProfileScreen(title = "Manage profile", onBack = { env.router.pop() }) {
            Column(
                Modifier
                    .fillMaxWidth()
                    // Figma: the avatar 20 pt under the back button.
                    .padding(top = 4.dp),
                verticalArrangement = Arrangement.spacedBy(1.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                // Figma "Avatar" (104 pt: a 100 pt photo in a 2 pt white ring, card shadow) and "Badge edit avatar".
                // "Ubah avatar" right under it does the same for TalkBack.
                Box(
                    Modifier
                        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                            isAvatarPickerPresented = true
                        }
                        .clearAndSetSemantics { },
                ) {
                    Box(
                        Modifier
                            .shooShadow(ProfileStyle.cardShadow, radius = 8.dp, y = 6.dp, shape = CircleShape)
                            .background(ProfileStyle.card, CircleShape)
                            .padding(2.dp),
                    ) {
                        AvatarView(
                            id = model.profile?.avatarId ?: "", size = 100.dp,
                            ring = AvatarRing(color = ProfileStyle.card, width = 2.5.dp),
                        )
                    }
                    Image(
                        painterResource(R.drawable.profile_edit_badge),
                        contentDescription = null,
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .offset(x = 2.dp, y = (-2).dp)
                            .size(32.dp),
                    )
                }
                Box(
                    Modifier
                        .heightIn(min = 44.dp)
                        .plainClickable { isAvatarPickerPresented = true }
                        .semantics { testTag = "profile.changePhoto" },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(t("Change avatar"), style = profileBody(), color = ProfileStyle.accent)
                }
            }

            // Figma: 20 pt under "Ubah avatar"; its 44 pt tap area already adds 11.
            ProfileSection(title = "Personal info", top = 9.dp) {
                LabeledRow(
                    label = t("Display name"),
                    value = model.profile?.name ?: "",
                    modifier = Modifier
                        .plainClickable {
                            model.nameDraft = model.profile?.name ?: ""
                            isNamePresented = true
                        }
                        .semantics { testTag = "profile.displayName" },
                )
                ProfileDivider(leading = 17.dp)
                LabeledRow(
                    label = t("Status"),
                    value = t(model.statusTitle),
                    showsChevron = false,
                    modifier = Modifier.semantics { testTag = "profile.status" },
                )
            }

            if (model.variant == ProfileModel.Variant.GUARDIAN && model.members.isNotEmpty()) {
                ProfileSection(title = "Connected with", top = 32.dp) {
                    model.members.forEachIndexed { index, member ->
                        if (index > 0) ProfileDivider()
                        ConnectedRow(member)
                    }
                }
            }

            ProfileSection(title = "Account", top = 32.dp) {
                DeleteAccountRow(model) { isDeleteConfirming = true }
            }
        }
    }

    ProfileSheet(isPresented = isAvatarPickerPresented, onDismissRequest = { isAvatarPickerPresented = false }) {
        AvatarPickerSheet(
            current = model.profile?.avatarId ?: "",
            isWorking = model.isWorking,
            onSave = { id -> scope.launch { if (model.chooseAvatar(id)) isAvatarPickerPresented = false } },
            onDismiss = { isAvatarPickerPresented = false },
        )
    }
    ProfileSheet(isPresented = isNamePresented, onDismissRequest = { isNamePresented = false }) {
        // Figma "Nama ini terlihat di app Virellia.": the one person this guardian protects, else the family.
        val only = model.members.singleOrNull()
        val subtitle = if (model.variant == ProfileModel.Variant.GUARDIAN && only != null) {
            t("This name shows in %@'s app.", only.name)
        } else {
            t("Your family sees this name.")
        }
        NameSheet(model = model, subtitle = subtitle, onDismiss = { isNamePresented = false })
    }
    ProfileActionErrorAlert(model.actionError) { model.actionError = null }
}

@Composable
private fun DeleteAccountRow(model: ProfileModel, onClick: () -> Unit) {
    ProfileRow(
        symbol = "xmark", title = t("Delete account"),
        subtitle = t("All data and history will be deleted for good"),
        titleColor = ProfileStyle.red,
        iconTint = ProfileStyle.red, iconFill = ProfileStyle.redIconFill,
        style = ProfileToggleRowStyle.SETTINGS,
        modifier = Modifier
            .plainClickable(enabled = !model.isWorking, onClick = onClick)
            .semantics { testTag = "profile.manage.delete" },
    )
}

/** Figma "Terhubung · Virellia" (1278:12105): avatar, name, "dilindungi sejak 12 Okt 2026", chevron. */
@Composable
private fun ConnectedRow(member: FamilyMember) {
    val env = LocalAppEnvironment.current
    val language = LocalAppLanguage.current
    Row(
        Modifier
            .fillMaxWidth()
            .plainClickable(onClickLabel = t("Shows this person's protection")) { env.router.show(Route.Member(member.deviceId)) }
            .semantics(mergeDescendants = true) { testTag = "profile.connected.${member.deviceId}" }
            .heightIn(min = 66.dp)
            .padding(horizontal = 17.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AvatarView(id = member.avatarId, size = 36.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(member.name, style = profileBody(), color = ProfileStyle.ink)
            member.connectedAt?.let { since ->
                val date = Formatters.dateFormatter("yMMMd", language, ZoneId.systemDefault()).format(Date.from(since))
                Text(t("Protected since %@", date), style = profileCaption(), color = ProfileStyle.secondary)
            }
        }
        ProfileRowChevron()
    }
}

/**
 * Figma "Pengaturan/Kelola profil" of the protected user: avatar, "Aktif sejak", the name edited in place, and
 * "Hapus akun" low on the page.
 */
@Composable
private fun ProtectedManageProfilePage(model: ProfileModel) {
    val env = LocalAppEnvironment.current
    val language = LocalAppLanguage.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val focusManager = LocalFocusManager.current
    val focus = remember { FocusRequester() }
    var isNameFocused by remember { mutableStateOf(false) }
    var isDeleteConfirming by remember { mutableStateOf(false) }
    val savedText = t("Name saved")

    fun save() {
        if (model.nameDraft == model.profile?.name) return
        scope.launch {
            if (model.saveName()) {
                focusManager.clearFocus()
                view.announce(savedText)
            }
        }
    }

    // Leaving the field keeps a valid edit, like Done does.
    OnChange(isNameFocused) { _, focused ->
        if (!focused && model.nameDraft != model.profile?.name && model.nameProblem == null) save()
    }
    OnChange(model.nameError) { _, message -> if (message != null) view.announce(message.string(language)) }

    DeleteAccountSheet(model = model, isPresented = isDeleteConfirming, onIsPresentedChange = { isDeleteConfirming = it }) {
        ProfileScreen(title = "Manage profile", onBack = { env.router.pop() }) {
            Box(
                Modifier
                    .align(Alignment.CenterHorizontally)
                    .padding(top = 4.dp)
                    // Figma "Avatar": #1A1C2E 12 %, y 6, blur 16.
                    .shooShadow(ProfileStyle.cardShadow, radius = 8.dp, y = 6.dp, shape = CircleShape)
                    .background(ProfileStyle.card, CircleShape)
                    .padding(4.5.dp)
                    .clearAndSetSemantics { },
            ) {
                AvatarView(id = model.profile?.avatarId ?: "", size = 95.dp)
            }

            model.activeSince(language)?.let { since ->
                val card = ProfileStyle.card
                Row(
                    Modifier
                        .align(Alignment.CenterHorizontally)
                        .padding(top = 12.dp)
                        // Figma 242 × 39: 5.2 / 20.7 inside, plus its 1.3 pt ring.
                        .border(1.3.dp, card.copy(alpha = card.alpha * 0.9f), CapsuleShape)
                        .padding(horizontal = 22.dp, vertical = 6.5.dp)
                        .semantics(mergeDescendants = true) { testTag = "profile.activeSince" },
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.clearAndSetSemantics { }) { SfSymbol("shield.fill", 22f, ProfileStyle.secondary) }
                    Text(since, style = profileFont(22f, FontWeight.Medium, tracking = -0.22f), color = ProfileStyle.secondary)
                }
            }

            ProfileSection(title = "Personal info", top = 72.dp) {
                val nameLabel = t("Name")
                val hint = t("1 to 20 characters")
                val editLabel = t("Edit name")
                Row(
                    Modifier
                        .fillMaxWidth()
                        // Figma "Row/Adhella": 62 pt, the label and name 10 pt from its edges.
                        .heightIn(min = 62.dp)
                        .padding(horizontal = 17.dp, vertical = 9.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(nameLabel, style = profileCaption(), color = ProfileStyle.secondary, modifier = Modifier.clearAndSetSemantics { })
                        // Same word as the label, so Voice Access "Tap Name" works (WCAG 2.5.3).
                        BasicTextField(
                            value = model.nameDraft,
                            onValueChange = { model.nameDraft = it },
                            singleLine = true,
                            textStyle = profileBody().copy(color = ProfileStyle.ink),
                            cursorBrush = SolidColor(ProfileStyle.link),
                            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
                            keyboardActions = KeyboardActions(onDone = { save() }),
                            modifier = Modifier
                                .fillMaxWidth()
                                .focusRequester(focus)
                                .onFocusChanged { isNameFocused = it.isFocused }
                                .semantics {
                                    contentDescription = "$nameLabel. $hint"
                                    testTag = "profile.name"
                                },
                        )
                    }
                    Box(
                        Modifier
                            .outset(start = 0.dp, top = 0.dp, end = 14.dp, bottom = 0.dp)
                            .size(44.dp)
                            .plainClickable { runCatching { focus.requestFocus() } }
                            .semantics { contentDescription = editLabel },
                        contentAlignment = Alignment.Center,
                    ) {
                        SfSymbol("pencil", 14f, ProfileStyle.chevron)
                    }
                }
                ProfileDivider(leading = 17.dp)
            }

            // Before the profile arrives the field is empty on purpose: no "Enter a name." for a name not read yet.
            val message: String? = if (model.state != ProfileModel.State.LOADED) {
                null
            } else {
                when (model.nameProblem) {
                    NameRule.Problem.Empty -> t("Enter a name.")
                    NameRule.Problem.TooLong -> t("Use 20 characters or fewer.")
                    null -> model.nameError?.text()
                }
            }
            if (message != null) {
                Text(
                    message,
                    style = profileFont(13f),
                    color = readableRed,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = ProfileStyle.margin + 16.dp)
                        .padding(top = 10.dp)
                        .semantics { testTag = "profile.error" },
                )
            }

            ProfileCard(
                Modifier
                    .padding(horizontal = ProfileStyle.margin)
                    // Figma keeps "Hapus akun" near the bottom of the screen: its card starts at y 738.
                    .padding(top = 293.dp),
            ) {
                DeleteAccountRow(model) { isDeleteConfirming = true }
            }
        }
    }
    ProfileActionErrorAlert(model.actionError) { model.actionError = null }
}

// MARK: Akun Tertaut (Protected)

/**
 * Figma "Pengaturan/Mode akun" of the protected user ("Akun Tertaut"): who this phone is linked to, what the guardian
 * gets, and "Putuskan koneksi" locked — only the guardian can disconnect.
 */
@Composable
private fun ConnectionPage(model: ProfileModel) {
    val env = LocalAppEnvironment.current
    LaunchedEffect(Unit) { model.linked.refresh() }
    val guardian = model.profile?.guardian
    val showsConnect = guardian == null && model.state == ProfileModel.State.LOADED
    Box(Modifier.fillMaxSize()) {
        ProfileScreen(title = "Linked account", onBack = { env.router.pop() }) {
            when {
                guardian != null -> LinkedContent(model, guardian)
                model.state == ProfileModel.State.LOADED -> NotLinkedContent(model)
                // Offline or a server error: say so and offer a retry instead of a spinner that never ends.
                model.state == ProfileModel.State.FAILED ->
                    ProfileLoadFailed(failure = model.loadFailure, retry = { model.retry() }, modifier = Modifier.padding(top = 24.dp))
                else -> ShieldPulseLoader(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 200.dp),
                )
            }
            // iOS `.safeAreaInset(edge: .bottom)` also makes room for the button under the content.
            if (showsConnect) Spacer(Modifier.navigationBarsPadding().height(64.dp))
        }
        // Figma 2023:11179: the way back sits at the foot of the screen, like "Kembali" on member detail.
        if (showsConnect) {
            OnboardingCapsuleButton(
                title = "Enter the invite code",
                onClick = { env.router.showConnect() },
                identifier = "profile.guardian.connect",
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .navigationBarsPadding()
                    .padding(horizontal = ProfileStyle.margin)
                    .padding(bottom = 8.dp),
            )
        }
    }
}

/**
 * QA 2026-11-10 #6: the guardian disconnected this phone or deleted their account. Figma "Akun Tertaut · Belum
 * terhubung ke Guardian" (2023:11179): the linked layout with the guardian's seat empty, how to connect again, and that
 * Shoo keeps protecting in the meantime.
 */
@Composable
private fun ColumnScope.NotLinkedContent(model: ProfileModel) {
    Text(
        t("This account isn't linked to a guardian yet."),
        style = profileValue(),
        color = ProfileStyle.secondary,
        textAlign = TextAlign.Center,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 40.dp)
            .padding(top = 24.dp)
            .semantics {
                heading()
                testTag = "profile.guardian.none"
            },
    )

    Row(
        Modifier
            .align(Alignment.CenterHorizontally)
            .padding(top = 38.dp)
            .clearAndSetSemantics { },
        horizontalArrangement = Arrangement.spacedBy(17.dp),
        verticalAlignment = Alignment.Top,
    ) {
        LinkPerson(name = t("You")) { YouAvatar(model) }
        LinkDots(muted = true, modifier = Modifier.padding(top = 54.dp))
        LinkPerson(name = "Guardian", nameColor = ProfileStyle.secondary) {
            val stroke = ProfileStyle.chevron
            Box(
                Modifier
                    .size(92.dp)
                    .background(ProfileStyle.iconFill, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Canvas(Modifier.size(92.dp)) {
                    val line = 2.dp.toPx()
                    drawCircle(
                        stroke,
                        radius = size.minDimension / 2 - line / 2,
                        style = Stroke(line, pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 6.dp.toPx()))),
                    )
                }
                SfSymbol("person.crop.circle", 34f, ProfileStyle.secondary.copy(alpha = 0.7f))
            }
        }
    }

    ProfileSection(title = "How to connect", top = 24.dp, modifier = Modifier.semantics { testTag = "profile.guardian.steps" }) {
        ConnectStep(1, t("Ask your guardian to open Shoo"), t("On your guardian's phone"))
        ProfileDivider()
        ConnectStep(2, t("Your guardian taps Invite family"), t("A QR code and an invite code appear"))
        ProfileDivider()
        ConnectStep(3, t("Scan the QR or enter the code"), t("Tap the button below"))
    }

    Text(
        t("Shoo keeps protecting you in the meantime. Scam sites stay blocked on this phone."),
        style = profileFont(15f, lineHeight = 21f),
        color = ProfileStyle.secondary,
        textAlign = TextAlign.Center,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 40.dp)
            .padding(top = 20.dp),
    )
}

@Composable
private fun YouAvatar(model: ProfileModel) {
    Box(
        Modifier
            .shooShadow(hex(0x1F78BF, 0.18f), radius = 11.dp, y = 7.dp, shape = CircleShape)
            .background(ProfileStyle.card, CircleShape)
            .padding(3.66.dp),
    ) {
        AvatarView(id = model.profile?.avatarId ?: "", size = 84.dp)
    }
}

@Composable
private fun ColumnScope.LinkedContent(model: ProfileModel, guardian: GuardianInfo) {
    val linked = model.linked
    val linkedLabel = t("Linked with %@", guardian.name)

    // Figma 455:9520: SF Pro Rounded 17, line height 140 %.
    Text(
        t("This account is linked to another account."),
        style = profileValue(),
        color = ProfileStyle.secondary,
        textAlign = TextAlign.Center,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 40.dp)
            .padding(top = 24.dp),
    )

    Row(
        Modifier
            .align(Alignment.CenterHorizontally)
            .padding(top = 38.dp)
            .clearAndSetSemantics {
                contentDescription = linkedLabel
                testTag = "profile.guardian"
            },
        horizontalArrangement = Arrangement.spacedBy(17.dp),
        verticalAlignment = Alignment.Top,
    ) {
        LinkPerson(name = t("You")) { YouAvatar(model) }
        // Figma 1618872250: the dots start 53.8 pt under the avatars' top.
        LinkDots(modifier = Modifier.padding(top = 54.dp))
        LinkPerson(name = guardian.name) {
            Box(
                Modifier
                    .shooShadow(hex(0x1A1C2E, 0.12f), radius = 7.dp, y = 5.dp, shape = CircleShape)
                    .background(ProfileStyle.card, CircleShape)
                    .padding(3.5.dp),
            ) {
                AvatarView(id = guardian.avatarId, size = 85.dp)
            }
        }
    }

    ProfileCard(
        Modifier
            .padding(horizontal = ProfileStyle.margin)
            // Figma: the card starts at y 340, 27 pt under the names.
            .padding(top = 25.dp),
    ) {
        if (LinkedAccountSettings.switchesAreLive) {
            ProfileToggleRow(
                symbol = "paperplane.fill", title = t("Send links automatically"),
                isOn = linked.autoSendLinks, onChange = { linked.autoSendLinks = it },
                modifier = Modifier.semantics { testTag = "linked.autoSend" },
            )
            ProfileDivider()
            ProfileToggleRowEnabled(
                symbol = "clock", title = t("Share caution history"),
                isOn = linked.shareWarnings, onChange = { linked.shareWarnings = it },
                enabled = linked.autoSendLinks,
                modifier = Modifier
                    .alpha(if (linked.autoSendLinks) 1f else 0.45f)
                    .semantics { testTag = "linked.shareWarnings" },
            )
        } else {
            // Today the extension sends every check to the guardian, so both read on and can't change.
            ProfileToggleRowEnabled(
                symbol = "paperplane.fill", title = t("Send links automatically"), subtitle = t("Coming soon"),
                isOn = true, onChange = {}, enabled = false,
                modifier = Modifier.semantics { testTag = "linked.autoSend" },
            )
            ProfileDivider()
            ProfileToggleRowEnabled(
                symbol = "clock", title = t("Share caution history"), subtitle = t("Coming soon"),
                isOn = true, onChange = {}, enabled = false,
                modifier = Modifier.semantics { testTag = "linked.shareWarnings" },
            )
        }
    }

    val rest = t("can always see the blocked history")
    Text(
        buildAnnotatedString {
            withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(guardian.name) }
            append(" ")
            append(rest)
        },
        // `.lineSpacing(6)`: 15 pt text on a ~24 pt line.
        style = profileFont(15f, lineHeight = 24f),
        color = ProfileStyle.secondary,
        textAlign = TextAlign.Center,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 28.dp)
            .padding(top = 9.dp),
    )

    ProfileCard(
        Modifier
            .padding(horizontal = ProfileStyle.margin)
            // Figma keeps the row near the bottom of the screen: its card starts at y 736.
            .padding(top = 226.dp),
    ) {
        ProfileRow(
            symbol = "lock.fill", title = t("Disconnect"),
            subtitle = t("Must use %@'s account", guardian.name),
            accessory = ProfileRowAccessory.None, titleColor = ProfileStyle.secondary,
            iconTint = dynamicColor(0x727272, 0x9EA6B4), iconFill = dynamicColor(0xEDEDED, 0x2A303A),
            modifier = Modifier.semantics(mergeDescendants = true) { testTag = "profile.disconnect.locked" },
        )
    }
}

@Composable
private fun LinkPerson(name: String, nameColor: Color = ProfileStyle.ink, avatar: @Composable () -> Unit) {
    Column(
        Modifier.width(92.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        avatar()
        // Figma "You" / "Adhella": SF Pro Display Semibold 17, line height 22.
        // iOS `.minimumScaleFactor(0.7)`: Compose has no shrink-to-fit; long names end in "…".
        Text(
            name,
            style = profileFont(17f, FontWeight.SemiBold, lineHeight = 22f),
            color = nameColor,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/**
 * The five blue dots between the two avatars, largest in the middle (Figma "Frame 1618872250"). A soft pulse runs from
 * "You" to the guardian, so the link reads as live. Reduce Motion keeps the Figma frame still. `muted`: grey and still,
 * no guardian on the other end yet (Figma 2023:11179).
 */
@Composable
private fun LinkDots(modifier: Modifier = Modifier, muted: Boolean = false) {
    val reduceMotion = LocalReduceMotion.current
    val animates = !reduceMotion && !muted
    val time by produceState(0.0, animates) {
        if (!animates) return@produceState
        while (true) withFrameMillis { value = System.currentTimeMillis() / 1000.0 }
    }
    val chevron = ProfileStyle.chevron
    // One pass takes 1.4 s, then the dots rest for 0.6 s.
    val cycle = time % (LINK_DOTS_PASS + LINK_DOTS_REST)
    val phase = if (animates && cycle < LINK_DOTS_PASS) cycle / LINK_DOTS_PASS else null
    Row(
        modifier
            .height(14.dp)
            .clearAndSetSemantics { },
        horizontalArrangement = Arrangement.spacedBy(9.5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        LINK_DOTS.forEachIndexed { index, (size, opacity) ->
            val lift = phase?.let { linkDotLift(index, it) } ?: 0.0
            val color = if (muted) {
                chevron.copy(alpha = chevron.alpha * opacity.toFloat())
            } else {
                hex(0x0088FF, (opacity + (1 - opacity) * lift).toFloat())
            }
            Box(
                Modifier
                    .size(size.dp)
                    .graphicsLayer {
                        val s = (1 + 0.3 * lift).toFloat()
                        scaleX = s
                        scaleY = s
                    }
                    .background(color, CircleShape),
            )
        }
    }
}

private val LINK_DOTS = listOf(9.16f to 0.56, 11f to 0.77, 14f to 1.0, 11f to 0.77, 9.16f to 0.56)
private const val LINK_DOTS_PASS = 1.4
private const val LINK_DOTS_REST = 0.6

/** 0…1: how close the pulse is to this dot (a smooth bump about 1.5 dots wide). */
private fun linkDotLift(index: Int, phase: Double): Double {
    val centre = -1 + phase * (LINK_DOTS.size + 1)
    val distance = abs(index - centre)
    if (distance >= 1.5) return 0.0
    return 0.5 * (1 + cos(PI * distance / 1.5))
}

/** One numbered step of "Cara menghubungkan" (Figma 2023:11179): a blue number in a round tile, title and hint. */
@Composable
private fun ConnectStep(number: Int, title: String, subtitle: String) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 17.dp, vertical = 12.dp)
            .semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(36.dp)
                .background(dynamicColor(0xDEECFB, 0x1E3A55), CircleShape)
                .clearAndSetSemantics { },
            contentAlignment = Alignment.Center,
        ) {
            Text("$number", style = profileFont(17f, FontWeight.SemiBold), color = ProfileStyle.link)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = profileBody(), color = ProfileStyle.ink)
            Text(subtitle, style = profileFont(15f), color = ProfileStyle.secondary)
        }
    }
}

// MARK: Notifikasi

/**
 * The switches live on the server, which decides which notifications go out. The Android permission comes first:
 * with notifications off for Shoo, the page says so and links to the fix.
 */
@Composable
private fun NotificationsPage(model: ProfileModel) {
    val env = LocalAppEnvironment.current
    val language = LocalAppLanguage.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var isQuietTimePresented by remember { mutableStateOf(false) }
    val settings = model.notificationSettings
    val isActive = rememberSceneActive()
    LaunchedEffect(isActive) {
        if (isActive) model.refreshNotifications()
    }

    fun update(change: NotificationSettingsUpdate) {
        scope.launch { model.updateNotifications(change) }
    }

    val status = model.notificationStatus
    val showsPermission = status != null && status != NotificationAuthorization.AUTHORIZED

    ProfileScreen(title = "Notifications", onBack = { env.router.pop() }) {
        if (showsPermission) {
            ProfileCard(
                Modifier
                    .padding(horizontal = ProfileStyle.margin)
                    .padding(top = 4.dp),
            ) {
                ProfileRow(
                    symbol = "bell.slash.fill", title = t("Notifications are off"),
                    subtitle = t(
                        if (status == NotificationAuthorization.NOT_DETERMINED) "Allow Shoo to send you alerts" else "Turn them on in Android Settings",
                    ),
                    accessory = ProfileRowAccessory.Value(t("Turn on"), color = ProfileStyle.link),
                    iconTint = ProfileStyle.red, iconFill = ProfileStyle.redIconFill,
                    modifier = Modifier
                        .plainClickable {
                            scope.launch {
                                // First time: the system prompt here. After a yes or a no only Settings can change it.
                                if (model.notificationsTapped()) {
                                    openNotificationSettings(context)
                                } else {
                                    env.registerForPushIfAllowed()
                                }
                            }
                        }
                        .semantics { testTag = "notifications.permission" },
                )
            }
        }

        // The switches show the server's settings: until they are read (or when the read failed) they would show the
        // defaults, and a tap would be dropped without a word (`updateNotifications` needs the profile).
        if (model.profile != null) {
            // Figma: the first title sits 24 pt under the back button; the header leaves 16.
            ProfileSection(title = "Warnings", top = if (showsPermission) 28.dp else 8.dp) {
                ProfileToggleRow(
                    symbol = "bell.fill", title = t("Dangerous sites"), subtitle = t("When you open a high-risk site"),
                    style = ProfileToggleRowStyle.SETTINGS,
                    isOn = settings.warning, onChange = { update(NotificationSettingsUpdate(warning = it)) },
                    modifier = Modifier.semantics { testTag = "notifications.warning" },
                )
                ProfileDivider()
                ProfileToggleRow(
                    symbol = "network.badge.shield.half.filled", title = t("Blocked sites"), subtitle = t("Every time Shoo blocks a site"),
                    style = ProfileToggleRowStyle.SETTINGS,
                    isOn = settings.blocked, onChange = { update(NotificationSettingsUpdate(blocked = it)) },
                    modifier = Modifier.semantics { testTag = "notifications.blocked" },
                )
            }

            if (model.variant == ProfileModel.Variant.GUARDIAN) {
                ProfileSection(title = "Family · Guardian mode") {
                    ProfileToggleRow(
                        symbol = "person.fill", title = t("Activity of people you protect"), subtitle = t("When they open a dangerous site"),
                        style = ProfileToggleRowStyle.SETTINGS,
                        isOn = settings.family, onChange = { update(NotificationSettingsUpdate(family = it)) },
                        modifier = Modifier.semantics { testTag = "notifications.family" },
                    )
                    ProfileDivider()
                    ProfileToggleRow(
                        symbol = ProfileStyle.extensionSymbol, title = t("Protection off"), subtitle = t("When their extension is off"),
                        style = ProfileToggleRowStyle.SETTINGS,
                        isOn = settings.protectionOff, onChange = { update(NotificationSettingsUpdate(protectionOff = it)) },
                        modifier = Modifier.semantics { testTag = "notifications.protectionOff" },
                    )
                }
            }

            if (model.variant == ProfileModel.Variant.PROTECTED) {
                // Figma: Protected has no summary or quiet hours, and a switch for its guardian's checks. Hidden until
                // the server sends that notification (#183).
                if (LinkedAccountSettings.switchesAreLive) {
                    val linked = model.linked
                    ProfileSection(title = "Connected account") {
                        ProfileToggleRow(
                            symbol = "lock.fill", title = t("Blocked link"), subtitle = t("When the linked account verifies a link"),
                            style = ProfileToggleRowStyle.SETTINGS,
                            isOn = linked.notifyLinkVerified, onChange = { linked.notifyLinkVerified = it },
                            modifier = Modifier.semantics { testTag = "notifications.linkVerified" },
                        )
                    }
                }
            } else {
                ProfileSection(title = "Summary") {
                    ProfileToggleRow(
                        symbol = "globe", title = t("Weekly summary"),
                        subtitle = t("Every Monday, %@", quietClock("08:00", language)),
                        style = ProfileToggleRowStyle.SETTINGS,
                        isOn = settings.weeklySummary, onChange = { update(NotificationSettingsUpdate(weeklySummary = it)) },
                        modifier = Modifier.semantics { testTag = "notifications.summary" },
                    )
                }

                ProfileSection(title = "Quiet hours") {
                    ProfileToggleRow(
                        symbol = null, title = t("Quiet hours"),
                        style = ProfileToggleRowStyle.SETTINGS,
                        isOn = settings.quietHours, onChange = { update(NotificationSettingsUpdate(quietHours = it)) },
                        modifier = Modifier.semantics { testTag = "notifications.quietHours" },
                    )
                    ProfileDivider(leading = 17.dp)
                    ProfileRow(
                        symbol = null, title = t("Time"),
                        accessory = ProfileRowAccessory.Value(
                            "${quietClock(settings.quietStart, language)} – ${quietClock(settings.quietEnd, language)}",
                        ),
                        minHeight = 44.dp,
                        modifier = Modifier
                            .plainClickable(enabled = settings.quietHours) { isQuietTimePresented = true }
                            .alpha(if (settings.quietHours) 1f else 0.5f)
                            .semantics { testTag = "notifications.quietTime" },
                    )
                }
                PageNote(t("Blocked-site alerts still come during quiet hours."))
            }
        } else if (model.state == ProfileModel.State.FAILED) {
            ProfileLoadFailed(failure = model.loadFailure, retry = { model.retry() }, modifier = Modifier.padding(top = 24.dp))
        } else {
            ShieldPulseLoader(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 200.dp),
            )
        }
    }

    ProfileSheet(
        isPresented = isQuietTimePresented,
        onDismissRequest = { isQuietTimePresented = false },
        containerColor = ProfileStyle.background,
        cornerRadius = 24.dp,
    ) {
        QuietHoursSheet(
            start = settings.quietStart,
            end = settings.quietEnd,
            onSave = { start, end -> update(NotificationSettingsUpdate(quietStart = start, quietEnd = end)) },
            onDismiss = { isQuietTimePresented = false },
        )
    }
    ProfileActionErrorAlert(model.actionError) { model.actionError = null }
}

/** iOS `UIApplication.openNotificationSettingsURLString`: Shoo's notification settings. */
private fun openNotificationSettings(context: Context) {
    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    try {
        context.startActivity(intent)
    } catch (_: ActivityNotFoundException) {
        runCatching {
            context.startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }
}

/** "22:00" → "22.00" in Indonesian, "22:00" in English. Swift `NotificationsPage.clock(_:language:)`. */
internal fun quietClock(value: String, language: AppLanguage): String {
    val minutes = quietMinutes(value) ?: return value
    return Formatters.dateFormatter("HHmm", language, ZoneOffset.UTC).format(Date(minutes * 60_000L))
}

/** "22:00" as minutes after midnight, or null when it is not a 24-hour time. Swift `QuietHoursSheet.date(_:)`. */
internal fun quietMinutes(clock: String): Int? {
    val parts = clock.split(":").mapNotNull { it.toIntOrNull() }
    if (parts.size != 2 || parts[0] !in 0 until 24 || parts[1] !in 0 until 60) return null
    return parts[0] * 60 + parts[1]
}

/** Minutes after midnight as "HH:MM". Swift `QuietHoursSheet.clock(_:)`. */
internal fun quietClockValue(minutes: Int): String {
    val m = ((minutes % (24 * 60)) + 24 * 60) % (24 * 60)
    return "%02d:%02d".format(m / 60, m % 60)
}

/**
 * "Waktu": start and end of the quiet window, 24-hour. iOS: a medium sheet with a Form of two compact time pickers and
 * Cancel / Save in the bar. Android: the same rows; a tap opens Material's time input under the row.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun QuietHoursSheet(start: String, end: String, onSave: (String, String) -> Unit, onDismiss: () -> Unit) {
    val language = LocalAppLanguage.current
    var startMinutes by remember { mutableIntStateOf(quietMinutes(start) ?: (22 * 60)) }
    var endMinutes by remember { mutableIntStateOf(quietMinutes(end) ?: (6 * 60)) }
    var editing by remember { mutableStateOf<Int?>(null) }
    val canSave = ProfileModel.canSaveQuietHours(quietClockValue(startMinutes), quietClockValue(endMinutes))

    Column(
        Modifier
            .fillMaxWidth()
            .padding(bottom = 24.dp),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 56.dp)
                .padding(horizontal = 8.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                t("Quiet hours"),
                style = profileFont(17f, FontWeight.SemiBold, lineHeight = 22f),
                color = ProfileStyle.ink,
                modifier = Modifier.semantics { heading() },
            )
            Box(
                Modifier
                    .align(Alignment.CenterStart)
                    .heightIn(min = 44.dp)
                    .plainClickable(onClick = onDismiss)
                    .padding(horizontal = 12.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(t("Cancel"), style = profileFont(17f), color = ProfileStyle.link)
            }
            Box(
                Modifier
                    .align(Alignment.CenterEnd)
                    .heightIn(min = 44.dp)
                    .plainClickable(enabled = canSave) {
                        onSave(quietClockValue(startMinutes), quietClockValue(endMinutes))
                        onDismiss()
                    }
                    .semantics { testTag = "quiet.save" }
                    .padding(horizontal = 12.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    t("Save"),
                    style = profileFont(17f, FontWeight.SemiBold),
                    color = if (canSave) ProfileStyle.link else ProfileStyle.chevron,
                )
            }
        }
        ProfileCard(
            Modifier
                .padding(horizontal = 16.dp)
                .padding(top = 8.dp),
        ) {
            QuietTimeRow(
                label = t("Starts"), minutes = startMinutes, language = language, isEditing = editing == 0,
                onTap = { editing = if (editing == 0) null else 0 },
                onChange = { startMinutes = it },
                testTag = "quiet.start",
            )
            ProfileDivider(leading = 17.dp)
            QuietTimeRow(
                label = t("Ends"), minutes = endMinutes, language = language, isEditing = editing == 1,
                onTap = { editing = if (editing == 1) null else 1 },
                onChange = { endMinutes = it },
                testTag = "quiet.end",
            )
        }
        // Start = end would silence warnings all day (fase 27i, F-N6).
        if (!canSave) {
            Text(
                t("Start and end can't be the same time."),
                style = profileFont(13f),
                color = ProfileStyle.secondary,
                modifier = Modifier
                    .padding(horizontal = 32.dp)
                    .padding(top = 8.dp)
                    .semantics { testTag = "quiet.sameTime" },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun QuietTimeRow(
    label: String,
    minutes: Int,
    language: AppLanguage,
    isEditing: Boolean,
    onTap: () -> Unit,
    onChange: (Int) -> Unit,
    testTag: String,
) {
    Column {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 52.dp)
                .padding(horizontal = 17.dp, vertical = 6.dp)
                .semantics { this.testTag = testTag },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(label, style = profileBody(), color = ProfileStyle.ink, modifier = Modifier.weight(1f))
            Text(
                quietClock(quietClockValue(minutes), language),
                style = profileFont(17f),
                color = if (isEditing) ProfileStyle.link else ProfileStyle.ink,
                modifier = Modifier
                    .background(ProfileStyle.iconFill, RoundedCornerShape(8.dp))
                    .plainClickable(onClickLabel = label, onClick = onTap)
                    .padding(horizontal = 11.dp, vertical = 6.dp),
            )
        }
        // iOS: the compact DatePicker opens the system's wheel popover; here the picker unfolds in place.
        // Reduce Motion: a plain fade.
        val reduceMotion = LocalReduceMotion.current
        AnimatedVisibility(
            visible = isEditing,
            enter = if (reduceMotion) fadeIn(shooEaseOut(0.2)) else fadeIn() + expandVertically(),
            exit = if (reduceMotion) fadeOut(shooEaseOut(0.2)) else fadeOut() + shrinkVertically(),
        ) {
            key(isEditing) {
                val state = rememberTimePickerState(initialHour = minutes / 60, initialMinute = minutes % 60, is24Hour = true)
                LaunchedEffect(state.hour, state.minute) { onChange(state.hour * 60 + state.minute) }
                Box(
                    Modifier
                        .fillMaxWidth()
                        .padding(vertical = 8.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    TimeInput(state = state, colors = TimePickerDefaults.colors())
                }
            }
        }
    }
}

// MARK: Bahasa

@Composable
private fun LanguagePage(model: ProfileModel) {
    val env = LocalAppEnvironment.current
    ProfileScreen(title = "Language", onBack = { env.router.pop() }) {
        // Figma: the first title sits 24 pt under the back button; the header leaves 16.
        ProfileSection(title = "App language", top = 8.dp) {
            // Figma lists Bahasa Indonesia first.
            listOf(AppLanguage.INDONESIAN, AppLanguage.ENGLISH).forEachIndexed { index, language ->
                if (index > 0) ProfileDivider(leading = 17.dp)
                RadioRow(
                    // The language's own name, read by TalkBack in that language.
                    title = AnnotatedString(language.nativeName, SpanStyle(localeList = LocaleList(language.code))),
                    subtitle = t(if (language == AppLanguage.INDONESIAN) "Indonesian" else "English (language)"),
                    isSelected = env.settings.language == language,
                    action = { model.chooseLanguage(language) },
                    modifier = Modifier.semantics { testTag = "language.${language.code}" },
                )
            }
        }
        PageNote(t("Notifications use this language too. Warnings in Firefox follow your phone's language."))
    }
    // A save the server missed says so here, where it was chosen.
    ProfileActionErrorAlert(model.actionError) { model.actionError = null }
}

// MARK: Tema

@Composable
private fun ThemePage() {
    val env = LocalAppEnvironment.current
    val settings = env.settings
    ProfileScreen(title = "Theme", onBack = { env.router.pop() }) {
        ProfileSection(title = "Appearance", top = 8.dp) {
            // Figma "Pilihan Tema": three columns spread edge to edge, 20 / 16 inside the card.
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 17.dp, vertical = 16.dp),
                verticalAlignment = Alignment.Top,
            ) {
                ThemeOption(R.drawable.theme_preview_light, t("Light"), settings.theme == AppTheme.LIGHT, "theme.light") {
                    settings.theme = AppTheme.LIGHT
                }
                Spacer(Modifier.weight(1f).widthIn(min = 8.dp))
                ThemeOption(R.drawable.theme_preview_dark, t("Dark"), settings.theme == AppTheme.DARK, "theme.dark") {
                    settings.theme = AppTheme.DARK
                }
                Spacer(Modifier.weight(1f).widthIn(min = 8.dp))
                ThemeOption(R.drawable.theme_preview_system, t("Automatic"), settings.theme == AppTheme.SYSTEM, "theme.system") {
                    settings.theme = AppTheme.SYSTEM
                }
            }
        }
        PageNote(t("Automatic follows light or dark mode on your phone."))

        ProfileSection(title = "Effects", top = 24.dp) {
            ProfileToggleRow(
                symbol = "circle.lefthalf.filled", title = t("Reduce glass effects"),
                subtitle = t("Solid card backgrounds that also save battery"),
                style = ProfileToggleRowStyle.SETTINGS,
                isOn = settings.reduceGlass, onChange = { settings.reduceGlass = it },
                modifier = Modifier.semantics { testTag = "theme.reduceGlass" },
            )
        }
    }
}

/** One phone preview, its name and a radio (Figma "Terang" / "Gelap" / "Otomatis"). */
@Composable
private fun ThemeOption(@DrawableRes image: Int, title: String, isSelected: Boolean, testTag: String, action: () -> Unit) {
    val reduceMotion = LocalReduceMotion.current
    SelectionHaptic(isSelected)
    // Figma: the chosen preview sits in a 2 pt blue ring 3 pt out (94 × 160); the others keep only the 3 pt inset
    // (90 × 156), so their name and radio sit 4 pt higher. The move eases, or snaps with Reduce Motion.
    val inset by animateDpAsState(if (isSelected) 5.dp else 3.dp, selectionSpec(reduceMotion, movesLayout = true), label = "themeInset")
    // The ring still fades with Reduce Motion, when the 4 pt move snaps.
    val ringAlpha by animateFloatAsState(if (isSelected) 1f else 0f, shooEaseInOut(0.2), label = "themeRing")
    val link = ProfileStyle.link
    Column(
        Modifier
            .plainClickable(onClick = action)
            .semantics(mergeDescendants = true) {
                selected = isSelected
                this.testTag = testTag
            },
        verticalArrangement = Arrangement.spacedBy(10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box {
            Image(
                painterResource(image),
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .padding(inset)
                    .size(width = 84.dp, height = 150.dp),
            )
            Box(
                Modifier
                    .matchParentSize()
                    .border(2.dp, link.copy(alpha = ringAlpha), RoundedCornerShape(21.dp)),
            )
        }
        Text(
            title,
            style = profileFont(15f, if (isSelected) FontWeight.Medium else FontWeight.Normal, tracking = -0.15f),
            color = ProfileStyle.ink,
        )
        ProfileRadio(isOn = isSelected)
    }
}

// MARK: Aksesibilitas

@Composable
private fun AccessibilityPage() {
    val env = LocalAppEnvironment.current
    val language = LocalAppLanguage.current
    val settings = env.settings
    ProfileScreen(title = "Accessibility", onBack = { env.router.pop() }) {
        ProfileSection(title = "Text size", top = 8.dp) {
            Column(
                Modifier
                    // Figma: 18 inside the card's 1 pt border; ProfileCard already adds 5 above and below.
                    .padding(horizontal = 19.dp, vertical = 14.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                // Figma "Pratinjau": a sample Activity row at the chosen size.
                Row(
                    Modifier
                        .fillMaxWidth()
                        .background(ProfileStyle.background, RoundedCornerShape(16.dp))
                        .padding(14.dp)
                        .clearAndSetSemantics { },
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        Modifier
                            .size(40.dp)
                            .background(ProfileStyle.card, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        SfSymbol("globe", 18f, ProfileStyle.ink)
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text("bca-verifikasi.site", style = profileFont(20f, tracking = -0.2f), color = ProfileStyle.ink)
                        Text(t("Today · %@", sampleTime(language)), style = profileFont(15f, rounded = true), color = ProfileStyle.secondary)
                    }
                }
                TextSizeSlider(level = settings.textSize, onLevelChange = { settings.textSize = it })
                Text(
                    t(settings.textSize.title),
                    style = profileFont(15f, FontWeight.Medium, tracking = -0.15f),
                    color = ProfileStyle.ink,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clearAndSetSemantics { },
                )
            }
        }

        ProfileSection(title = "Display") {
            ProfileToggleRow(
                symbol = "Aa", title = t("Bold text"), style = ProfileToggleRowStyle.SETTINGS,
                isOn = settings.boldText, onChange = { settings.boldText = it },
                modifier = Modifier.semantics { testTag = "accessibility.bold" },
            )
            ProfileDivider()
            ProfileToggleRow(
                symbol = "circle.lefthalf.filled", title = t("High contrast"), style = ProfileToggleRowStyle.SETTINGS,
                isOn = settings.highContrast, onChange = { settings.highContrast = it },
                modifier = Modifier.semantics { testTag = "accessibility.contrast" },
            )
            ProfileDivider()
            ProfileToggleRow(
                symbol = ProfileStyle.extensionSymbol, title = t("Reduce motion"),
                subtitle = t("Turns off gauge and card-swipe animations"), style = ProfileToggleRowStyle.SETTINGS,
                isOn = settings.reduceMotion, onChange = { settings.reduceMotion = it },
                modifier = Modifier.semantics { testTag = "accessibility.reduceMotion" },
            )
        }

        ProfileSection(title = "When there is a warning") {
            ProfileToggleRow(
                symbol = "bell.fill", title = t("Vibrate"), style = ProfileToggleRowStyle.SETTINGS,
                isOn = settings.haptics, onChange = { settings.haptics = it },
                modifier = Modifier.semantics { testTag = "accessibility.haptics" },
            )
            ProfileDivider()
            ProfileToggleRow(
                symbol = "person.fill", title = t("Read warnings aloud"),
                subtitle = t("The score and reasons are read with TalkBack"), style = ProfileToggleRowStyle.SETTINGS,
                isOn = settings.readAloud, onChange = { settings.readAloud = it },
                modifier = Modifier.semantics { testTag = "accessibility.readAloud" },
            )
        }
    }
}

/** "10.42" / "10:42". */
private fun sampleTime(language: AppLanguage): String =
    Formatters.dateFormatter("HHmm", language, ZoneOffset.UTC).format(Date((10 * 3600 + 42 * 60) * 1000L))

/** Five stops from a small "A" to a large "A" (Figma "Slider"). TalkBack: swipe up or down (adjustable). */
@Composable
private fun TextSizeSlider(level: TextSizeLevel, onLevelChange: (TextSizeLevel) -> Unit) {
    val reduceMotion = LocalReduceMotion.current
    val feedback = rememberSensoryFeedback()
    val levels = TextSizeLevel.entries
    val currentLevel by rememberUpdatedState(level)
    val change by rememberUpdatedState(onLevelChange)
    OnChange(level) { _, _ -> feedback(ProfileHaptic.SELECTION) }
    // The thumb and the blue rail glide to the next stop; Reduce Motion: they jump.
    val position by animateFloatAsState(
        level.rawValue.toFloat(),
        if (reduceMotion) snap() else shooSnappy(0.2),
        label = "textSize",
    )
    // The stop dots turn blue or grey under the same glide.
    val dotFill = levels.map { stop ->
        animateFloatAsState(
            if (stop.rawValue <= level.rawValue) 1f else 0f,
            if (reduceMotion) snap() else shooSnappy(0.2),
            label = "textSizeDot",
        )
    }
    val sizeLabel = t("Text size")
    val valueLabel = t(level.title)
    val rail = ProfileStyle.sliderRail
    val link = ProfileStyle.link
    val chevron = ProfileStyle.chevron

    Row(
        Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                contentDescription = sizeLabel
                stateDescription = valueLabel
                progressBarRangeInfo = ProgressBarRangeInfo(level.rawValue.toFloat(), 0f..(levels.size - 1).toFloat(), steps = levels.size - 2)
                setProgress { target ->
                    val new = TextSizeLevel.fromRaw(target.roundToInt().coerceIn(0, levels.size - 1))
                    if (new != currentLevel) change(new)
                    true
                }
                testTag = "accessibility.textSize"
            },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("A", style = figmaTextStyle(13f, FontWeight.Medium), color = ProfileStyle.secondary, modifier = Modifier.clearAndSetSemantics { })
        BoxWithConstraints(
            Modifier
                .weight(1f)
                .height(28.dp),
        ) {
            val widthPx = constraints.maxWidth.toFloat()
            Canvas(
                Modifier
                    .fillMaxSize()
                    .pointerInput(levels.size) {
                        // Figma "Track" 268: the rail runs from its left edge to 6 pt short of its right edge.
                        val trailing = 6.dp.toPx()
                        val step = (size.width - trailing) / (levels.size - 1)
                        fun select(x: Float) {
                            val index = (x / step).roundToInt().coerceIn(0, levels.size - 1)
                            val new = TextSizeLevel.fromRaw(index)
                            if (new != currentLevel) change(new)
                        }
                        awaitEachGesture {
                            val down = awaitFirstDown()
                            select(down.position.x)
                            while (true) {
                                val event = awaitPointerEvent()
                                val pointer = event.changes.firstOrNull { it.id == down.id } ?: break
                                if (!pointer.pressed) break
                                select(pointer.position.x)
                                pointer.consume()
                            }
                        }
                    },
            ) {
                val trailing = 6.dp.toPx()
                val step = (widthPx - trailing) / (levels.size - 1)
                val y = size.height / 2
                val railHeight = 4.dp.toPx()
                drawRoundRect(
                    rail,
                    topLeft = Offset(0f, y - railHeight / 2),
                    size = Size(widthPx - trailing, railHeight),
                    cornerRadius = CornerRadius(railHeight / 2),
                )
                drawRoundRect(
                    link,
                    topLeft = Offset(0f, y - railHeight / 2),
                    size = Size(step * position, railHeight),
                    cornerRadius = CornerRadius(railHeight / 2),
                )
                levels.forEach { stop ->
                    drawCircle(
                        lerp(chevron, link, dotFill[stop.rawValue].value),
                        radius = 4.dp.toPx(),
                        center = Offset(step * stop.rawValue, y),
                    )
                }
            }
            // The white thumb with its shadow (black 18 %, y 2, blur 6).
            val thumbX = with(androidx.compose.ui.platform.LocalDensity.current) {
                (((widthPx - 6.dp.toPx()) / (levels.size - 1)) * position).toDp()
            }
            Box(
                Modifier
                    .offset(x = thumbX - 14.dp)
                    .size(28.dp)
                    .shooShadow(Color.Black.copy(alpha = 0.18f), radius = 3.dp, y = 2.dp, shape = CircleShape)
                    .background(Color.White, CircleShape),
            )
        }
        Text("A", style = figmaTextStyle(22f, FontWeight.Medium), color = ProfileStyle.ink, modifier = Modifier.clearAndSetSemantics { })
    }
}

// MARK: Tentang Shoo

@Composable
private fun AboutPage() {
    val env = LocalAppEnvironment.current
    val language = LocalAppLanguage.current
    val context = LocalContext.current
    val version = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"
    val shareMessage = t("Shoo blocks scam sites on your phone. Try it:")

    ProfileScreen(title = "About Shoo", onBack = { env.router.pop() }) {
        Column(
            Modifier
                .fillMaxWidth()
                // Figma: the icon starts 28 pt under the back button; the header leaves 16.
                .padding(top = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Image(
                painterResource(R.drawable.about_app_icon),
                contentDescription = null,
                modifier = Modifier.size(88.dp),
            )
            Text(
                "Shoo",
                style = profileFont(28f, FontWeight.Bold, tracking = -0.56f),
                color = ProfileStyle.nameInk,
                modifier = Modifier
                    .padding(top = 16.dp)
                    .semantics { heading() },
            )
            // Figma sets it on a 20 pt line.
            Text(
                t("Version %@", version),
                style = profileFont(13f, rounded = true),
                color = ProfileStyle.secondary,
                modifier = Modifier
                    .padding(top = 3.dp)
                    .padding(vertical = 2.dp),
            )
            Text(
                t("Protect yourself and your family from scam sites."),
                style = profileFont(15f, tracking = -0.15f),
                color = ProfileStyle.secondary,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .padding(top = 10.dp)
                    .padding(horizontal = ProfileStyle.margin),
            )
        }

        // Apple 5.1.1(ii), 5.1.2(i): the online check can be taken back at any time. It lives here, next to the
        // privacy policy that explains it.
        ProfileCard(
            Modifier
                .padding(horizontal = ProfileStyle.margin)
                .padding(top = 32.dp),
        ) {
            ProfileToggleRow(
                symbol = null,
                title = t("Online check"),
                subtitle = t("Sends pages to Shoo's server and suspicious-page summaries to DeepSeek"),
                style = ProfileToggleRowStyle.SETTINGS,
                isOn = env.settings.dataConsent == DataConsent.GRANTED,
                onChange = { env.setDataConsent(if (it) DataConsent.GRANTED else DataConsent.DECLINED) },
                modifier = Modifier.semantics { testTag = "about.onlineCheck" },
            )
        }

        ProfileCard(
            Modifier
                .padding(horizontal = ProfileStyle.margin)
                .padding(top = 20.dp),
        ) {
            LinkRow(t("Privacy policy"), id = "about.privacy") { openUrl(context, AppConfig.legalPage("privacy", language)) }
            ProfileDivider(leading = 17.dp)
            LinkRow(t("Terms of use"), id = "about.terms") { openUrl(context, AppConfig.legalPage("terms", language)) }
            ProfileDivider(leading = 17.dp)
            LinkRow(t("Third-party licenses"), id = "about.licenses") { env.router.show(Route.ProfilePage(ProfilePage.LICENSES)) }
        }

        ProfileCard(
            Modifier
                .padding(horizontal = ProfileStyle.margin)
                .padding(top = 20.dp),
        ) {
            // iOS: the App Store review page, or the system review prompt before the app is listed.
            LinkRow(t("Rate on Google Play"), id = "about.rate") { rateOnPlay(context) }
            ProfileDivider(leading = 17.dp)
            // iOS `ShareLink`: the system share sheet with the message and the link.
            ProfileRow(
                symbol = null, title = t("Share Shoo"), minHeight = 44.dp,
                modifier = Modifier
                    .plainClickable { shareApp(context, shareMessage, AppConfig.shareURL) }
                    .semantics { testTag = "about.share" },
            )
            ProfileDivider(leading = 17.dp)
            LinkRow(t("Contact us"), value = AppConfig.supportEmail, id = "about.contact") {
                openUrl(context, "mailto:${AppConfig.supportEmail}", action = Intent.ACTION_SENDTO)
            }
        }

        // Figma sets it on a 20 pt line.
        Text(
            t("© 2026 Shoo · Made in Indonesia"),
            style = profileFont(13f, rounded = true),
            color = ProfileStyle.secondary,
            modifier = Modifier
                .align(Alignment.CenterHorizontally)
                .padding(top = 28.dp)
                .padding(vertical = 2.dp),
        )
    }
}

/** Figma "Tentang Shoo": 44 pt text rows. */
@Composable
private fun LinkRow(title: String, id: String, value: String? = null, action: () -> Unit) {
    ProfileRow(
        symbol = null, title = title,
        accessory = value?.let { ProfileRowAccessory.Value(it) } ?: ProfileRowAccessory.Chevron,
        minHeight = 44.dp,
        modifier = Modifier
            .plainClickable(onClick = action)
            .semantics { testTag = id },
    )
}

private fun openUrl(context: Context, url: String, action: String = Intent.ACTION_VIEW) {
    runCatching { context.startActivity(Intent(action, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

/** Play Store listing (iOS: App Store review page). Debug builds open the release listing. */
private fun rateOnPlay(context: Context) {
    val id = context.packageName.removeSuffix(".debug")
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$id")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (_: ActivityNotFoundException) {
        openUrl(context, "https://play.google.com/store/apps/details?id=$id")
    }
}

private fun shareApp(context: Context, message: String, url: String) {
    val send = Intent(Intent.ACTION_SEND)
        .setType("text/plain")
        .putExtra(Intent.EXTRA_TEXT, "$message $url")
    runCatching { context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

/**
 * "Lisensi pihak ketiga". iOS: no third-party code at all. Android: the open-source libraries the app is built with and
 * the Inter typeface (licence text in assets/licenses).
 */
@Composable
private fun LicensesPage() {
    val env = LocalAppEnvironment.current
    val context = LocalContext.current
    val interLicense = remember {
        runCatching { context.assets.open("licenses/Inter-OFL.txt").bufferedReader().use { it.readText() } }.getOrNull()
    }
    ProfileScreen(title = "Third-party licenses", onBack = { env.router.pop() }) {
        ProfileCard(Modifier.padding(horizontal = ProfileStyle.margin)) {
            Text(
                t("Shoo for Android is built with these open-source libraries and the Inter typeface. Each is used under the license shown."),
                style = profileFont(15f, lineHeight = 21f),
                color = ProfileStyle.ink,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(17.dp),
            )
        }
        ProfileCard(
            Modifier
                .padding(horizontal = ProfileStyle.margin)
                .padding(top = 20.dp),
        ) {
            ANDROID_LICENSES.forEachIndexed { index, (name, license) ->
                if (index > 0) ProfileDivider(leading = 17.dp)
                ProfileRow(symbol = null, title = name, subtitle = license, accessory = ProfileRowAccessory.None, minHeight = 44.dp)
            }
            ProfileDivider(leading = 17.dp)
            LinkRow(t("Read the Apache License 2.0"), id = "licenses.apache") {
                openUrl(context, "https://www.apache.org/licenses/LICENSE-2.0")
            }
        }
        if (interLicense != null) {
            ProfileSection(title = "Inter", top = 28.dp) {
                Text(
                    interLicense,
                    style = profileFont(13f, lineHeight = 18f),
                    color = ProfileStyle.secondary,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(17.dp),
                )
            }
        }
    }
}

/** What the APK ships (app/build.gradle.kts dependencies) and the licence of each. Names are not translated. */
private val ANDROID_LICENSES = listOf(
    "Inter" to "SIL Open Font License 1.1",
    "AndroidX, Jetpack Compose, Material 3" to "Apache License 2.0",
    "Material Symbols" to "Apache License 2.0",
    "CameraX" to "Apache License 2.0",
    "Kotlin, kotlinx.coroutines" to "Apache License 2.0",
    "ZXing" to "Apache License 2.0",
)
