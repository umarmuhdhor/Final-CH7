package com.shoo.app.features.profile

import android.icu.text.DisplayContext
import android.icu.text.MeasureFormat
import android.icu.text.RelativeDateTimeFormatter
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import android.icu.util.ULocale
import android.os.Build
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.dp
import com.shoo.app.R
import com.shoo.app.app.AppSettings
import com.shoo.app.app.LocalAppEnvironment
import com.shoo.app.app.ProfilePage
import com.shoo.app.app.Route
import com.shoo.app.components.AppTheme
import com.shoo.app.components.AvatarView
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.ShieldPulseLoader
import com.shoo.app.components.hex
import com.shoo.app.components.shooEaseInOut
import com.shoo.app.components.shooShadow
import com.shoo.app.components.shooSnappy
import com.shoo.app.data.ExtensionStatus
import com.shoo.app.data.FamilyMember
import com.shoo.app.data.LinkedAccountSettings
import com.shoo.app.data.ShooRepository
import com.shoo.app.features.detail.privacyCover
import com.shoo.app.features.pairing.InviteSheet
import com.shoo.app.features.shield.TurnOffExtensionSheet
import com.shoo.app.features.shield.TurnOnExtensionSheet
import com.shoo.app.support.AppLanguage
import com.shoo.app.support.L10n
import com.shoo.app.support.NotificationPermission
import com.shoo.app.support.t
import java.time.Duration
import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlin.math.abs
import kotlinx.coroutines.launch

/**
 * Profile (PF-01), pushed from the avatar button on either tab. Figma "Profile/Pribadi" (Guardian, Family mode off),
 * "Profile/Guardian" (Family mode on) and the Protected profile ("Bu Maria").
 */
@Composable
fun ProfileView(
    repository: ShooRepository,
    settings: AppSettings,
    notifications: NotificationPermission? = null,
    modifier: Modifier = Modifier,
) {
    val env = LocalAppEnvironment.current
    val language = LocalAppLanguage.current
    val reduceMotion = LocalReduceMotion.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val model = remember(repository, settings) {
        ProfileModel(repository, settings, notifications, linked = LinkedAccountSettings(env.appGroupDefaults))
    }
    var extensionStatus by remember { mutableStateOf<ExtensionStatus>(ExtensionStatus.Off(null)) }
    var isTurnOnPresented by remember { mutableStateOf(false) }
    /** Figma "Sheet · Matikan Shoo" (1681:5372): how to switch Shoo off, from the active extension row. */
    var isTurnOffPresented by remember { mutableStateOf(false) }
    var isInvitePresented by remember { mutableStateOf(false) }
    var isDeleteConfirming by remember { mutableStateOf(false) }
    var remindingId by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(model) {
        // Disconnect / delete hand the app back to onboarding: clear navigation first.
        model.onSessionEnd = { env.returnToOnboardingAfterDelete() }
        model.onForgetDevice = { env.forgetDeletedDevice(it) }
        model.load()
    }
    val isActive = rememberSceneActive()
    LaunchedEffect(isActive, model) {
        if (!isActive) return@LaunchedEffect
        extensionStatus = env.extensionStatus()
        model.refreshNotifications()
        model.linked.refresh()
        // Back from the background: a member may have left or been disconnected meanwhile. Only once loaded, so this
        // never races the first load above.
        if (model.state == ProfileModel.State.LOADED) model.load()
    }
    // A push while Profile is open (a member joined, left or was disconnected): the list follows without leaving the
    // page, like Home and Activity (A-12).
    OnChange(env.pushesWhileOpen) { _, _ ->
        if (model.state == ProfileModel.State.LOADED) model.load()
    }

    // Names and the family list stay out of the recent-apps snapshot (D-alief-A36).
    DeleteAccountSheet(
        model = model, isPresented = isDeleteConfirming, onIsPresentedChange = { isDeleteConfirming = it },
        modifier = modifier.privacyCover(),
    ) {
        ProfileScreen(title = "Profile", onBack = { env.router.pop() }) {
            when (model.state) {
                ProfileModel.State.LOADING -> ShieldPulseLoader(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 300.dp),
                )
                ProfileModel.State.FAILED -> {
                    // Figma "Profile/Pribadi · Gagal memuat profil" (1681:6986): the card takes the profile card's
                    // place (370 × 344, r 20); the settings below still work.
                    val shape = RoundedCornerShape(20.dp)
                    ProfileLoadFailed(
                        failure = model.loadFailure,
                        retry = { model.load() },
                        modifier = Modifier
                            .padding(horizontal = 16.dp)
                            .padding(top = 16.dp)
                            // Figma: #1A264D at 6 %, y 4, blur 16.
                            .shooShadow(hex(0x1A264D, 0.06f), radius = 8.dp, y = 4.dp, shape = shape)
                            .background(ProfileStyle.card, shape)
                            .heightIn(min = 344.dp),
                    )
                    ProtectionSection(model, extensionStatus, onTurnOn = { isTurnOnPresented = true }, onTurnOff = { isTurnOffPresented = true })
                    AccountSection(model)
                    PreferencesSection(model)
                    DeleteButton(model) { isDeleteConfirming = true }
                }
                ProfileModel.State.LOADED -> {
                    ProfileHeader(model, onInvite = { isInvitePresented = true })
                    if (model.showsGuardianCard) {
                        GuardianModeCard(
                            onBecomeGuardian = { env.requestFamilyMode() },
                            onDismiss = { model.dismissGuardianCard() },
                        )
                    }
                    if (model.variant == ProfileModel.Variant.GUARDIAN) {
                        FamilySection(
                            model = model,
                            remindingId = remindingId,
                            onInvite = { isInvitePresented = true },
                            onRemind = { member ->
                                remindingId = member.deviceId
                                val message = model.remind(member)
                                // A problem shows as an alert, which TalkBack reads; only "sent" is announced.
                                if (model.actionError == null) view.announce(message.string(language))
                                remindingId = null
                            },
                        )
                    }
                    if (model.variant == ProfileModel.Variant.PROTECTED) GuardianSection(model)
                    ProtectionSection(model, extensionStatus, onTurnOn = { isTurnOnPresented = true }, onTurnOff = { isTurnOffPresented = true })
                    AccountSection(model)
                    PreferencesSection(model)
                    DeleteButton(model) { isDeleteConfirming = true }
                }
            }
        }
    }

    ProfileSheet(
        isPresented = isTurnOnPresented,
        onDismissRequest = { isTurnOnPresented = false },
        onDismissed = { scope.launch { extensionStatus = env.extensionStatus() } },
    ) {
        TurnOnExtensionSheet(onDismiss = { isTurnOnPresented = false })
    }
    ProfileSheet(
        isPresented = isTurnOffPresented,
        onDismissRequest = { isTurnOffPresented = false },
        onDismissed = { scope.launch { extensionStatus = env.extensionStatus() } },
    ) {
        TurnOffExtensionSheet(onDismiss = { isTurnOffPresented = false })
    }
    ProfileSheet(
        isPresented = isInvitePresented,
        onDismissRequest = { isInvitePresented = false },
        onDismissed = { scope.launch { model.load() } },
    ) {
        InviteSheet(repository = env.repository, onDone = { isInvitePresented = false })
    }
    ProfileActionErrorAlert(model.actionError) { model.actionError = null }
}

@Composable
private fun ProfileHeader(model: ProfileModel, onInvite: () -> Unit) {
    val env = LocalAppEnvironment.current
    val language = LocalAppLanguage.current
    val isProtected = model.variant == ProfileModel.Variant.PROTECTED
    val guardian = model.profile?.guardian
    ProfileHeaderCard(
        banner = R.drawable.profile_banner,
        name = model.profile?.name ?: "",
        handle = model.handle(language),
        stats = model.stats(language),
        avatarShadow = if (isProtected) ProfileAvatarShadow.GLOW else ProfileAvatarShadow.NONE,
        // Figma 455:10289: the pill's ring ends 20 pt above the avatar's bottom (its 44 pt tap frame 18.5).
        badgeBottom = if (isProtected) (-18.5).dp else 5.dp,
        avatar = {
            Box {
                AvatarView(id = model.profile?.avatarId ?: "", size = 88.dp)
                if (isProtected && guardian != null) {
                    GuardianBadge(
                        avatarId = guardian.avatarId,
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .offset(x = 16.dp, y = 4.dp),
                    )
                }
            }
        },
        badge = {
            if (isProtected) {
                if (guardian != null) {
                    ConnectedPillButton(
                        onClick = { env.router.show(Route.ProfilePage(ProfilePage.CONNECTION)) },
                        onClickLabel = t("Shows your linked account"),
                        testTag = "profile.connectedPill",
                        // Figma 455:10289: the pill ends 21.4 pt from the card's edge, 9.4 inside the 12 pt row inset.
                        modifier = Modifier.offset(x = 2.4.dp),
                    ) {
                        ConnectedPillGlyph()
                        Spacer(Modifier.width(5.5.dp))
                        Text(t("Connected"))
                    }
                }
            } else {
                ProfilePillButton(
                    onClick = onInvite,
                    padding = ProfilePillButtonDefaults.invitePadding,
                    testTag = "profile.invite",
                ) {
                    QRGlyph()
                    Spacer(Modifier.width(8.dp))
                    Text(t("Share invite"))
                }
            }
        },
    )
}

@Composable
private fun DeleteButton(model: ProfileModel, onClick: () -> Unit) {
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        // Figma "Hapus Akun" (title case here, unlike the Kelola profil row): SF Pro Rounded 17.
        // Figma: the text starts 28 pt under the last card; the 44 pt tap area adds 11 above its 22 pt line.
        Box(
            Modifier
                .padding(top = 17.dp)
                .heightIn(min = 44.dp)
                .widthIn(min = 44.dp)
                .plainClickable(enabled = !model.isWorking, onClick = onClick)
                .semantics { testTag = "profile.delete" },
            contentAlignment = Alignment.Center,
        ) {
            Text(t("Delete Account"), style = profileBody(), color = ProfileStyle.red)
        }
    }
}

// MARK: Sections

/** Protected sections sit 15 pt apart (Figma "Profile/Pribadi" of the protected user), others 28. */
private fun sectionTop(model: ProfileModel) = if (model.variant == ProfileModel.Variant.PROTECTED) 15.dp else 28.dp

/** Title to card: 12 on the Protected profile (Figma 455:10275), 10 elsewhere (1115:14392). */
private fun sectionSpacing(model: ProfileModel) = if (model.variant == ProfileModel.Variant.PROTECTED) 12.dp else 10.dp

/** Protected: "Terhubung", the guardian who gets the warnings. */
@Composable
private fun GuardianSection(model: ProfileModel) {
    val env = LocalAppEnvironment.current
    val guardian = model.profile?.guardian ?: return
    ProfileSection(title = "Connected", spacing = 24.dp) {
        Row(
            Modifier
                .fillMaxWidth()
                .plainClickable(onClickLabel = t("Shows your linked account")) {
                    env.router.show(Route.ProfilePage(ProfilePage.CONNECTION))
                }
                .semantics { testTag = "profile.guardianRow" }
                .heightIn(min = 55.dp)
                .padding(horizontal = 17.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            AvatarView(id = guardian.avatarId, size = 33.dp)
            Text(guardian.name, style = profileBody(), color = ProfileStyle.ink, modifier = Modifier.weight(1f))
            ProfileRowChevron()
        }
    }
}

/** The grey 14 pt chevron at the end of a row (`Image(systemName: "chevron.right")`). */
@Composable
internal fun ProfileRowChevron() {
    Box(Modifier.clearAndSetSemantics { }) {
        SfSymbol("chevron.right", 14f, ProfileStyle.chevron)
    }
}

/**
 * Pribadi and Protected: "Perlindungan" with the add-on status (the switch lives in Firefox).
 * Android: "Ekstensi Safari" is the Shoo add-on in Firefox for Android.
 */
@Composable
private fun ProtectionSection(
    model: ProfileModel,
    extensionStatus: ExtensionStatus,
    onTurnOn: () -> Unit,
    onTurnOff: () -> Unit,
) {
    if (model.variant == ProfileModel.Variant.GUARDIAN) return
    // Figma: 32 pt under the profile card, 28 under the "Mode Guardian" card, 15 on the Protected profile.
    val top = if (model.variant == ProfileModel.Variant.PROTECTED) {
        if (model.profile?.guardian != null) sectionTop(model) else 28.dp
    } else {
        if (model.showsGuardianCard) 28.dp else 32.dp
    }
    val active = extensionStatus.isActive
    val isProtected = model.variant == ProfileModel.Variant.PROTECTED
    ProfileSection(title = "Protection", top = top, spacing = sectionSpacing(model)) {
        ProfileRow(
            symbol = ProfileStyle.extensionSymbol,
            title = t("Shoo add-on in Firefox"),
            // Pribadi (1115:14424): a green dot and "Terhubung" in green. Protected (455:10275): "Aktif" in grey.
            // No chevron either way; while on, the row opens "Matikan Shoo".
            accessory = if (active) {
                if (isProtected) {
                    ProfileRowAccessory.Value(t("Active"), chevron = false)
                } else {
                    ProfileRowAccessory.Status(t("Connected"), dot = ProfileStyle.green, color = ProfileStyle.greenText)
                }
            } else {
                ProfileRowAccessory.Value(t("Off"), color = ProfileStyle.red)
            },
            modifier = Modifier
                .plainClickable(
                    onClickLabel = if (active) t("Shows how to switch Shoo off in Firefox") else t("Shows how to switch Shoo on in Firefox"),
                ) { if (active) onTurnOff() else onTurnOn() }
                .semantics { testTag = if (active) "profile.extension.active" else "profile.extension.off" },
        )
    }
}

@Composable
private fun FamilySection(
    model: ProfileModel,
    remindingId: String?,
    onInvite: () -> Unit,
    onRemind: suspend (FamilyMember) -> Unit,
) {
    val reduceMotion = LocalReduceMotion.current
    // Members on screen when the list first showed don't fade in; later arrivals do.
    val initialIds = remember { model.members.map { it.deviceId }.toSet() }
    // Figma: 32 pt under the profile card (416:10447, 480:5353).
    // Someone joins or is disconnected: rows fade, the card eases to its new height. Reduce Motion: the list snaps.
    ProfileSection(
        title = "People you protect",
        top = 32.dp,
        modifier = if (reduceMotion) Modifier else Modifier.animateContentSize(shooSnappy(0.25)),
    ) {
        when {
            model.membersFailed -> {
                // Figma "Profile/Guardian · Gagal memuat" (1681:7088): the same card inside the section.
                ProfileLoadFailed(identifier = "profile.members.retry", failure = model.membersLoadFailure, retry = { model.load() })
            }
            // The list is still on its way: the invite card would flash before the members replace it.
            !model.membersLoaded -> ShieldPulseLoader(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 120.dp),
            )
            model.members.isEmpty() -> FamilyEmptyCard(onInvite = onInvite)
            else -> model.members.forEachIndexed { index, member ->
                key(member.deviceId) {
                    val visible = remember {
                        MutableTransitionState(member.deviceId in initialIds || reduceMotion).apply { targetState = true }
                    }
                    AnimatedVisibility(visibleState = visible, enter = fadeIn(shooSnappy(0.25)), exit = fadeOut()) {
                        Column {
                            if (index > 0) ProfileDivider(leading = 73.dp)
                            MemberRow(member, isWorking = remindingId == member.deviceId, onRemind = onRemind)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MemberRow(member: FamilyMember, isWorking: Boolean, onRemind: suspend (FamilyMember) -> Unit) {
    val env = LocalAppEnvironment.current
    val language = LocalAppLanguage.current
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 72.dp)
            .padding(horizontal = 17.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier
                .weight(1f)
                .plainClickable(onClickLabel = t("Shows this person's protection")) {
                    env.router.show(Route.Member(member.deviceId))
                }
                .semantics(mergeDescendants = true) { testTag = "profile.member.${member.deviceId}" },
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Figma: a member whose extension is off has a half-faded avatar.
            AvatarView(id = member.avatarId, modifier = Modifier.alpha(if (member.extensionActive) 1f else 0.5f))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(member.name, style = profileBody(), color = ProfileStyle.nameInk)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier
                            .size(7.dp)
                            .background(if (member.extensionActive) ProfileStyle.green else ProfileStyle.offDot, CircleShape),
                    )
                    Text(
                        MemberText.status(member, now = Instant.now(), language = language),
                        style = profileCaption(),
                        color = ProfileStyle.secondary,
                    )
                }
            }
            val seen = member.lastSeenAt
            if (member.extensionActive && seen != null) {
                Text(MemberText.ago(seen, language = language), style = profileCaption(), color = ProfileStyle.secondary)
            }
        }
        if (!member.extensionActive) {
            RemindButton(member = member, isWorking = isWorking, action = { onRemind(member) })
        }
    }
}

@Composable
private fun AccountSection(model: ProfileModel) {
    val language = LocalAppLanguage.current
    ProfileSection(title = "Account", top = sectionTop(model), spacing = sectionSpacing(model)) {
        if (model.variant == ProfileModel.Variant.PROTECTED) {
            // Figma: Kelola profil first, then Terhubung.
            NavRow(symbol = "person.fill", title = t("Manage profile"), page = ProfilePage.EDIT_PROFILE, id = "profile.manage")
            ProfileDivider()
            NavRow(symbol = ProfileStyle.switchSymbol, title = t(model.connectionRowTitle), page = ProfilePage.CONNECTION, id = "profile.connection")
        } else {
            NavRow(
                symbol = ProfileStyle.switchSymbol, title = t("Account mode"),
                value = t(if (model.variant == ProfileModel.Variant.GUARDIAN) "Guardian" else "Personal"),
                page = ProfilePage.MODE, id = "profile.mode",
            )
            ProfileDivider()
            NavRow(symbol = "person.fill", title = t("Manage profile"), page = ProfilePage.EDIT_PROFILE, id = "profile.manage")
        }
        ProfileDivider()
        NavRow(symbol = "bell.fill", title = t("Notifications"), page = ProfilePage.NOTIFICATIONS, id = "profile.notifications")
        ProfileDivider()
        NavRow(symbol = "globe", title = t("Language"), value = language.shortName, page = ProfilePage.LANGUAGE, id = "profile.language")
    }
}

@Composable
private fun PreferencesSection(model: ProfileModel) {
    val env = LocalAppEnvironment.current
    val themeTitle = when (env.settings.theme) {
        AppTheme.LIGHT -> "Light"
        AppTheme.DARK -> "Dark"
        AppTheme.SYSTEM -> "Automatic"
    }
    ProfileSection(title = "Preferences", top = sectionTop(model), spacing = sectionSpacing(model)) {
        NavRow(symbol = "circle.lefthalf.filled", title = t("Theme"), value = t(themeTitle), page = ProfilePage.THEME, id = "profile.theme")
        ProfileDivider()
        NavRow(
            symbol = "Aa", title = t("Accessibility"), value = t(env.settings.textSize.title),
            page = ProfilePage.ACCESSIBILITY, id = "profile.accessibility",
        )
        ProfileDivider()
        NavRow(symbol = "text.magnifyingglass", title = t("About Shoo"), page = ProfilePage.ABOUT, id = "profile.about")
    }
}

@Composable
private fun ColumnScope.NavRow(symbol: String, title: String, page: ProfilePage, id: String, value: String? = null) {
    val env = LocalAppEnvironment.current
    ProfileRow(
        symbol = symbol,
        title = title,
        accessory = value?.let { ProfileRowAccessory.Value(it) } ?: ProfileRowAccessory.Chevron,
        modifier = Modifier
            .plainClickable { env.router.show(Route.ProfilePage(page)) }
            .semantics { testTag = id },
    )
}

/** "Ingatkan" pill; "Sent" (disabled) for 6 hours after a reminder. */
@Composable
fun RemindButton(member: FamilyMember, isWorking: Boolean, action: suspend () -> Unit, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    val feedback = rememberSensoryFeedback()
    val sent = MemberText.recentlyReminded(member)
    OnChange(sent) { was, now -> if (!was && now) feedback(ProfileHaptic.SUCCESS) }
    val label = if (sent) t("Reminder sent to %@", member.name) else t("Remind %@", member.name)
    val hint = if (sent) null else t(remindHintKey(member))
    ProfilePillButton(
        onClick = { scope.launch { action() } },
        tint = if (sent) ProfileStyle.secondary else ProfileStyle.link,
        large = true,
        enabled = !(sent || isWorking),
        testTag = "profile.remind.${member.deviceId}",
        modifier = modifier.semantics { contentDescription = label + (hint?.let { ". $it" } ?: "") },
    ) {
        // Remind → (spinner) → Sent: a 0.2 s cross-fade, already gentle enough for Reduce Motion.
        Crossfade(targetState = isWorking to sent, animationSpec = shooEaseInOut(0.2), label = "remind") { (working, isSent) ->
            if (working) {
                Box(Modifier.width(62.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(Modifier.size(20.dp), color = ProfileStyle.link, strokeWidth = 2.dp)
                }
            } else {
                Text(t(if (isSent) "Sent" else "Remind"))
            }
        }
    }
}

/** The member's browser: Shoo's Safari extension on an iPhone or iPad, the Firefox add-on on Android. */
internal fun FamilyMember.usesFirefox(): Boolean {
    val model = deviceModel ?: return false
    return !model.startsWith("iPhone") && !model.startsWith("iPad")
}

/** "Sends a notification to turn on Shoo in Safari" or the Firefox one, by the member's phone. */
internal fun remindHintKey(member: FamilyMember): String =
    if (member.usesFirefox()) "Sends a notification to turn on Shoo in Firefox" else "Sends a notification to turn on Shoo in Safari"

/** Text built from a member (rows and the member detail). */
object MemberText {
    /** "iPhone" / "iPad" / "Android", or null without a model. */
    internal fun deviceKind(member: FamilyMember): String? = member.deviceModel?.let {
        when {
            it.startsWith("iPad") -> "iPad"
            it.startsWith("iPhone") -> "iPhone"
            else -> "Android"
        }
    }

    /** The browser Shoo runs in on the member's phone. Unknown phone: Safari, as iOS says. */
    internal fun browser(member: FamilyMember): String = if (member.usesFirefox()) "Firefox" else "Safari"

    /** "Active · iPhone · Safari" / "Active · Android · Firefox" / "Extension off for 2 days". */
    fun status(member: FamilyMember, now: Instant, language: AppLanguage): String {
        if (member.extensionActive) {
            return listOfNotNull(L10n.string("Active", language), deviceKind(member), browser(member)).joinToString(" · ")
        }
        val seen = member.lastSeenAt ?: return L10n.string("Extension off", language)
        return L10n.string("Extension off for %@", language, duration(seen, now, language))
    }

    /**
     * "2 mnt lalu". Under a second ago, or ahead of this phone's clock (a normal gap between two phones): "baru saja",
     * never "in 0s" (A-08). iOS `RelativeDateTimeFormatter`, `.abbreviated`.
     */
    fun ago(date: Instant, now: Instant = Instant.now(), language: AppLanguage): String {
        if (Duration.between(date, now).toMillis() < 1000) return L10n.string("just now", language)
        val past = if (date.isBefore(now)) date else now
        val formatter = RelativeDateTimeFormatter.getInstance(
            ULocale.forLanguageTag(language.code), null, RelativeDateTimeFormatter.Style.SHORT, DisplayContext.CAPITALIZATION_NONE,
        )
        val seconds = ChronoUnit.SECONDS.between(now, past)
        val magnitude = abs(seconds)
        val (value, unit) = when {
            magnitude < 60 -> seconds to 0
            magnitude < 3_600 -> seconds / 60 to 1
            magnitude < 86_400 -> seconds / 3_600 to 2
            magnitude < 7 * 86_400 -> seconds / 86_400 to 3
            magnitude < 30 * 86_400 -> seconds / (7 * 86_400) to 4
            magnitude < 365 * 86_400 -> seconds / (30 * 86_400) to 5
            else -> seconds / (365 * 86_400) to 6
        }
        val relativeUnit = when (unit) {
            0 -> RelativeDateTimeFormatter.RelativeUnit.SECONDS
            1 -> RelativeDateTimeFormatter.RelativeUnit.MINUTES
            2 -> RelativeDateTimeFormatter.RelativeUnit.HOURS
            3 -> RelativeDateTimeFormatter.RelativeUnit.DAYS
            4 -> RelativeDateTimeFormatter.RelativeUnit.WEEKS
            5 -> RelativeDateTimeFormatter.RelativeUnit.MONTHS
            else -> RelativeDateTimeFormatter.RelativeUnit.YEARS
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val icuUnit = when (unit) {
                0 -> RelativeDateTimeFormatter.RelativeDateTimeUnit.SECOND
                1 -> RelativeDateTimeFormatter.RelativeDateTimeUnit.MINUTE
                2 -> RelativeDateTimeFormatter.RelativeDateTimeUnit.HOUR
                3 -> RelativeDateTimeFormatter.RelativeDateTimeUnit.DAY
                4 -> RelativeDateTimeFormatter.RelativeDateTimeUnit.WEEK
                5 -> RelativeDateTimeFormatter.RelativeDateTimeUnit.MONTH
                else -> RelativeDateTimeFormatter.RelativeDateTimeUnit.YEAR
            }
            // Numeric, like Foundation's default `.numeric` style ("1 day ago", not "yesterday").
            formatter.formatNumeric(value.toDouble(), icuUnit)
        } else {
            formatter.format(abs(value).toDouble(), RelativeDateTimeFormatter.Direction.LAST, relativeUnit)
        }
    }

    /** "2 days" / "2 hari": the largest whole unit of days, hours or minutes (iOS `DateComponentsFormatter`, `.full`). */
    fun duration(start: Instant, end: Instant, language: AppLanguage): String {
        val seconds = maxOf(0L, ChronoUnit.SECONDS.between(start, if (end.isAfter(start)) end else start))
        val format = MeasureFormat.getInstance(ULocale.forLanguageTag(language.code), MeasureFormat.FormatWidth.WIDE)
        val measure = when {
            seconds >= 86_400 -> Measure(seconds / 86_400, MeasureUnit.DAY)
            seconds >= 3_600 -> Measure(seconds / 3_600, MeasureUnit.HOUR)
            else -> Measure(seconds / 60, MeasureUnit.MINUTE)
        }
        return format.format(measure)
    }

    fun recentlyReminded(member: FamilyMember, now: Instant = Instant.now()): Boolean {
        val last = member.remindedAt ?: return false
        return Duration.between(last, now).seconds < 6 * 3600
    }
}

/** "Indonesia" / "English" on the Language row (Figma). */
val AppLanguage.shortName: String
    get() = when (this) {
        AppLanguage.ENGLISH -> "English"
        AppLanguage.INDONESIAN -> "Indonesia"
    }
