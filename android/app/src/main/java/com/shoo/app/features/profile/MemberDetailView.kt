package com.shoo.app.features.profile

import android.icu.util.TimeZone
import android.icu.util.ULocale
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import com.shoo.app.R
import com.shoo.app.app.LocalAppEnvironment
import com.shoo.app.app.Route
import com.shoo.app.components.AvatarView
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.ShieldPulseLoader
import com.shoo.app.components.StateMessage
import com.shoo.app.components.hex
import com.shoo.app.components.pressScale
import com.shoo.app.components.shooEaseInOut
import com.shoo.app.components.shooEaseOut
import com.shoo.app.data.FamilyMember
import com.shoo.app.data.ScanResult
import com.shoo.app.data.ShooRepository
import com.shoo.app.features.detail.privacyCover
import com.shoo.app.features.onboarding.OnboardingCapsuleButton
import com.shoo.app.support.AppLanguage
import com.shoo.app.support.DeliveredPushes
import com.shoo.app.support.Formatters
import com.shoo.app.support.L10n
import com.shoo.app.support.t
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.util.Date
import kotlinx.coroutines.launch

/** Figma "Guardian/Detail Orang Dilindungi" (PF-01): a protected member as their guardian sees them. */
@Composable
fun MemberDetailView(deviceId: String, repository: ShooRepository, modifier: Modifier = Modifier) {
    val env = LocalAppEnvironment.current
    val language = LocalAppLanguage.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val model = remember(deviceId, repository) {
        MemberDetailModel(deviceId, repository, onDisconnected = { DeliveredPushes.clear(context.applicationContext) })
    }
    var isDisconnectConfirming by remember { mutableStateOf(false) }

    LaunchedEffect(model) { model.load() }
    // A push while this screen is open (new scan, verdict, member change): reload, as Guardian Home does (A-12).
    OnChange(env.pushesWhileOpen) { _, count -> model.pushesWhileOpenChanged(count) }

    Box(modifier.fillMaxSize().privacyCover()) {
        ProfileScreen(title = "Protected person", onBack = { env.router.pop() }, titleSize = 17f) {
            when (model.state) {
                MemberDetailModel.State.LOADING -> ShieldPulseLoader(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 300.dp),
                )
                // Figma "Gagal memuat" (1681:6968).
                MemberDetailModel.State.FAILED -> StateMessage(
                    systemImage = "exclamationmark.arrow.circlepath",
                    tint = hex(0xE5483B),
                    tileFill = Color.White,
                    title = "Data can't be viewed yet",
                    message = t(model.loadFailure.message(connection = "Check your internet connection, then try again.")),
                    modifier = Modifier
                        .padding(horizontal = ProfileStyle.margin)
                        .padding(top = 90.dp)
                        .semantics { testTag = "member.failed" },
                )
                // Figma "Sudah tidak terhubung" (1681:6955).
                MemberDetailModel.State.GONE -> StateMessage(
                    systemImage = "person.2.fill",
                    symbolSize = 27f,
                    tint = hex(0x6A717E),
                    tileFill = Color.White,
                    title = "No longer connected",
                    message = t("This person has disconnected. You no longer get warnings from them."),
                    modifier = Modifier
                        .padding(horizontal = ProfileStyle.margin)
                        .padding(top = 90.dp)
                        .semantics { testTag = "member.gone" },
                )
                MemberDetailModel.State.LOADED -> model.member?.let { member ->
                    MemberLoaded(model, member, onDisconnect = { isDisconnectConfirming = true })
                }
            }
        }
        // iOS `.safeAreaInset(edge: .bottom)`: Figma: 306 wide (48 in from each side), its foot 84 above the frame's.
        AnimatedVisibility(
            visible = model.state == MemberDetailModel.State.FAILED || model.state == MemberDetailModel.State.GONE,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter),
        ) {
            OnboardingCapsuleButton(
                title = "Back",
                onClick = { env.router.pop() },
                identifier = "member.back",
                modifier = Modifier
                    .navigationBarsPadding()
                    .padding(horizontal = 48.dp)
                    .padding(bottom = 48.dp),
            )
        }
    }

    ProfileSheet(
        isPresented = isDisconnectConfirming,
        onDismissRequest = { isDisconnectConfirming = false },
        canDismiss = !model.isWorking,
    ) {
        val member = model.member
        if (member != null) {
            ProfileConfirmSheet(
                title = t("Disconnect from %@?", member.name),
                message = t(
                    "You will no longer get warnings from %@'s activity. To connect again, %@ needs to enter a new invite code.",
                    member.name, member.name,
                ),
                confirmTitle = t("Disconnect"),
                confirmIdentifier = "member.disconnect.confirm",
                isWorking = model.isWorking,
                onConfirm = {
                    scope.launch {
                        if (!model.disconnect()) return@launch
                        env.familyChanges += 1
                        isDisconnectConfirming = false
                        env.router.pop()
                    }
                },
                onCancel = { isDisconnectConfirming = false },
            ) {
                AvatarView(id = member.avatarId, size = 64.dp)
            }
        }
    }
    ProfileActionErrorAlert(model.actionError) { model.actionError = null }
}

@Composable
private fun MemberLoaded(model: MemberDetailModel, member: FamilyMember, onDisconnect: () -> Unit) {
    val env = LocalAppEnvironment.current
    val language = LocalAppLanguage.current
    val scope = rememberCoroutineScope()
    val offBanner: (@Composable () -> Unit)? = if (member.extensionActive) null else {
        { OffBanner(model, member) }
    }

    ProfileHeaderCard(
        banner = R.drawable.member_banner,
        bannerHeight = 112.dp,
        badgeBottom = (-1).dp,
        name = member.name,
        handle = memberHandle(member, language),
        stats = memberStats(model, member, language),
        attachment = offBanner,
        avatar = {
            Box(Modifier.size(88.dp), contentAlignment = Alignment.Center) {
                AvatarView(id = member.avatarId, size = 86.dp)
            }
        },
        badge = { StatusPill(active = member.extensionActive) },
    )

    // Figma: 32 pt under the profile card.
    ProfileSection(title = "Protection", top = 32.dp) {
        ProfileRow(
            symbol = ProfileStyle.extensionSymbol,
            title = t(memberExtensionTitleKey(member)),
            accessory = if (member.extensionActive) {
                ProfileRowAccessory.Value(t("Active"), color = ProfileStyle.greenText, chevron = false)
            } else {
                ProfileRowAccessory.Value(t("Off"), color = ProfileStyle.red, chevron = false)
            },
            modifier = Modifier.semantics(mergeDescendants = true) { },
        )
        memberDeviceText(member)?.let { device ->
            ProfileDivider()
            ProfileRow(
                symbol = "person.fill", title = t("Device"),
                accessory = ProfileRowAccessory.Value(device, chevron = false),
                modifier = Modifier.semantics(mergeDescendants = true) { },
            )
        }
        member.connectedAt?.let { since ->
            ProfileDivider()
            ProfileRow(
                symbol = "globe", title = t("Connected since"),
                accessory = ProfileRowAccessory.Value(
                    Formatters.dateFormatter("yMMMd", language, ZoneId.systemDefault()).format(Date.from(since)),
                    chevron = false,
                ),
                modifier = Modifier.semantics(mergeDescendants = true) { },
            )
        }
        member.notify?.let { notify ->
            ProfileDivider()
            ProfileToggleRow(
                symbol = "bell.fill", title = t("Notify me"), subtitle = t("When they open a dangerous site"),
                isOn = notify,
                onChange = { on -> scope.launch { model.setNotify(on) } },
                modifier = Modifier.semantics { testTag = "member.notify" },
            )
        }
    }

    ProfileSection(
        title = "Latest activity",
        trailing = {
            // Keeps the 44 pt tap area without pushing the card down (Figma: card 32 pt under the title).
            Box(
                Modifier
                    .outset(0.dp, 12.dp)
                    .heightIn(min = 44.dp)
                    .plainClickable { env.router.show(Route.MemberActivity(member.deviceId)) }
                    .semantics { testTag = "member.seeAll" },
                contentAlignment = Alignment.Center,
            ) {
                Text(t("View all"), style = profileFont(15f, FontWeight.Medium, tracking = -0.15f), color = ProfileStyle.link)
            }
        },
    ) {
        if (model.recent.isEmpty()) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 58.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    t(if (model.recentFailed) "Couldn't load activity" else "No activity yet"),
                    style = profileFont(15f),
                    color = ProfileStyle.secondary,
                )
            }
        } else {
            model.recent.forEachIndexed { index, scan ->
                if (index > 0) ProfileDivider()
                ActivityRow(
                    scan,
                    modifier = Modifier
                        .plainClickable { env.router.show(Route.Detail(scan.id)) }
                        .semantics { testTag = "member.scan.${scan.id}" },
                )
            }
        }
    }

    Column(
        Modifier
            .padding(horizontal = ProfileStyle.margin)
            .padding(top = 28.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        ProfileCard {
            ProfileRow(
                symbol = "xmark", title = t("Disconnect"), titleColor = ProfileStyle.red, titleWeight = FontWeight.Medium,
                iconTint = ProfileStyle.red, iconFill = ProfileStyle.redIconFill,
                modifier = Modifier
                    .plainClickable(enabled = !model.isWorking, onClick = onDisconnect)
                    .semantics { testTag = "member.disconnect" },
            )
        }
        // `.lineSpacing(3)`: 13 pt text on a ~19 pt line.
        Text(
            t("You stop getting warnings from %@'s activity. %@ will be told.", member.name, member.name),
            style = profileFont(13f, rounded = true, lineHeight = 19f),
            color = ProfileStyle.secondary,
            modifier = Modifier.padding(horizontal = 16.dp),
        )
    }
}

/**
 * Figma "Pesan ekstensi mati" (1681:6718) and "Pengingat terkirim" (1681:6837): orange with **Ingatkan** while the
 * extension is off, green once a reminder went out. The swap cross-fades; the check bounces in.
 */
@Composable
private fun OffBanner(model: MemberDetailModel, member: FamilyMember) {
    val language = LocalAppLanguage.current
    val reduceMotion = LocalReduceMotion.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val feedback = rememberSensoryFeedback()
    val sent = MemberText.recentlyReminded(member)
    OnChange(sent) { was, now -> if (!was && now) feedback(ProfileHaptic.SUCCESS) }
    var checkBounce by remember { mutableStateOf(0) }
    OnChange(sent) { was, now -> if (!was && now) checkBounce += 1 }

    val ease = shooEaseInOut<Color>(0.25)
    val fill by animateColorAsState(if (sent) hex(0xEBF8ED, 0.9f) else hex(0xF8F2EB, 0.9f), ease, label = "offFill")
    val line by animateColorAsState(if (sent) hex(0x1CEF1C, 0.35f) else hex(0xEF871C, 0.35f), ease, label = "offLine")
    val tile by animateColorAsState(if (sent) hex(0x34C759, 0.14f) else hex(0xEF871C, 0.12f), ease, label = "offTile")
    val title = t(if (sent) "Reminder sent" else memberExtensionOffKey(member))
    val message = if (sent) t("%@ will get a notification.", member.name) else t("%@ isn't protected yet.", member.name)

    Box(
        Modifier
            .fillMaxWidth()
            .background(fill)
            .semantics { testTag = if (sent) "member.reminded" else "member.off" },
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(line),
        )
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 72.dp)
                .padding(horizontal = 16.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier
                    .size(40.dp)
                    .background(tile, RoundedCornerShape(8.dp))
                    .clearAndSetSemantics { },
                contentAlignment = Alignment.Center,
            ) {
                // iOS: `.contentTransition(.symbolEffect(.replace))`; Reduce Motion: a fade.
                Crossfade(targetState = sent, animationSpec = shooEaseInOut(0.25), label = "offSymbol") { isSent ->
                    SfSymbol(
                        if (isSent) "checkmark" else "exclamationmark.triangle.fill",
                        21.67f,
                        if (isSent) hex(0x269E4A) else hex(0xEF871C),
                        modifier = if (isSent) Modifier.profileBounce(checkBounce, enabled = !reduceMotion) else Modifier,
                    )
                }
            }
            Column(
                Modifier
                    .weight(1f)
                    .clearAndSetSemantics { contentDescription = "$title. $message" },
            ) {
                Text(title, style = profileFont(16f, FontWeight.SemiBold, tracking = -0.31f), color = hex(0x151617))
                Text(message, style = profileFont(13f, rounded = true), color = hex(0x6A717E))
            }
            AnimatedVisibility(visible = !sent, enter = fadeIn(shooEaseInOut(0.25)), exit = fadeOut(shooEaseInOut(0.25))) {
                val interaction = remember { MutableInteractionSource() }
                val label = t("Remind %@", member.name)
                val hint = t(remindHintKey(member))
                val labelAlpha by animateFloatAsState(if (model.isReminding) 0f else 1f, shooEaseOut(0.15), label = "remindLabel")
                Box(
                    Modifier
                        .heightIn(min = 44.dp)
                        .widthIn(min = 44.dp)
                        .pressScale(interaction)
                        .clickable(
                            interaction, indication = null, enabled = !model.isReminding,
                            onClickLabel = hint, role = Role.Button,
                        ) {
                            scope.launch {
                                // A problem shows as an alert, which TalkBack reads; only "sent" is announced.
                                val result = model.remind()
                                if (result != null && model.actionError == null) view.announce(result.string(language))
                            }
                        }
                        .semantics {
                            contentDescription = label
                            testTag = "profile.remind.${member.deviceId}"
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        t("Remind"),
                        style = profileFont(15f, FontWeight.SemiBold, tracking = -0.23f),
                        color = hex(0x136CB7),
                        modifier = Modifier.graphicsLayer { alpha = labelAlpha },
                    )
                    if (model.isReminding) {
                        CircularProgressIndicator(Modifier.size(16.dp), color = ProfileStyle.link, strokeWidth = 2.dp)
                    }
                }
            }
        }
    }
}

@Composable
private fun ActivityRow(scan: ScanResult, modifier: Modifier = Modifier) {
    val language = LocalAppLanguage.current
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 63.dp)
            .padding(horizontal = 17.dp, vertical = 11.dp)
            .semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ProfileIcon(symbol = "globe")
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            // U-05 (K8): cut in the middle, so the end of the domain (its public suffix, which a scammer cannot make
            // read as the bank's) always shows, not only the start they picked.
            MiddleTruncatedText(scan.domain, style = profileFont(17f, tracking = -0.17f), color = ProfileStyle.ink)
            Text(memberActivityWhen(scan.detectedAt, language = language), style = profileFont(13f, rounded = true), color = ProfileStyle.secondary)
        }
        ProfileScanChip(status = scan.status)
    }
}

/** One line, cut in the middle with "…" when too wide (iOS `.truncationMode(.middle)`; Compose 1.7 has no middle ellipsis). */
@Composable
private fun MiddleTruncatedText(text: String, style: TextStyle, color: Color, modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val maxWidth = constraints.maxWidth
        val shown = remember(text, style, maxWidth) {
            fun fits(candidate: String): Boolean =
                measurer.measure(candidate, style, maxLines = 1, softWrap = false, constraints = Constraints()).size.width <= maxWidth
            if (!constraints.hasBoundedWidth || fits(text)) {
                text
            } else {
                var low = 0
                var high = text.length
                while (low < high) {
                    val mid = (low + high + 1) / 2
                    val head = (mid + 1) / 2
                    val candidate = text.take(head) + "…" + text.takeLast(mid - head)
                    if (fits(candidate)) low = mid else high = mid - 1
                }
                val head = (low + 1) / 2
                text.take(head) + "…" + text.takeLast(low - head)
            }
        }
        Text(
            shown,
            style = style,
            color = color,
            maxLines = 1,
            overflow = TextOverflow.Clip,
            softWrap = false,
            modifier = Modifier.semantics { contentDescription = text },
        )
    }
}

@Composable
private fun StatusPill(active: Boolean) {
    Row(
        Modifier
            .background(if (active) ProfileStyle.greenPill else ProfileStyle.iconFill, CircleShape)
            // Figma "Status": 7 / 12 leading / 14 trailing.
            .padding(start = 12.dp, end = 14.dp, top = 7.dp, bottom = 7.dp)
            .semantics(mergeDescendants = true) { testTag = if (active) "member.status.on" else "member.status.off" },
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(8.dp)
                .background(if (active) ProfileStyle.green else ProfileStyle.offDot, CircleShape),
        )
        Text(
            t(if (active) "Protection on" else "Protection off"),
            style = profileFont(14f, FontWeight.Medium, tracking = -0.14f),
            color = if (active) ProfileStyle.greenText else ProfileStyle.secondary,
        )
    }
}

// MARK: Text

/** The member's "Safari extension" row: the Firefox add-on on an Android member's phone. */
private fun memberExtensionTitleKey(member: FamilyMember): String =
    if (member.usesFirefox()) "Shoo add-on in Firefox" else "Safari extension"

private fun memberExtensionOffKey(member: FamilyMember): String =
    if (member.usesFirefox()) "Firefox add-on off" else "Safari extension off"

/** "iPhone · Safari · aktif 2 mnt lalu" / "Android · Firefox · aktif 2 mnt lalu". */
private fun memberHandle(member: FamilyMember, language: AppLanguage): String {
    val parts = listOfNotNull(MemberText.deviceKind(member), MemberText.browser(member)).toMutableList()
    member.lastSeenAt?.let { seen ->
        parts += L10n.string("active %@", language, MemberText.ago(seen, language = language))
    }
    return parts.joinToString(" · ")
}

private fun memberStats(model: MemberDetailModel, member: FamilyMember, language: AppLanguage): List<ProfileStat> {
    val stats = member.stats ?: return emptyList()
    val format = NumberFormat.getIntegerInstance(language.locale)
    val number = { n: Int -> format.format(n.toLong()) }
    return listOf(
        ProfileStat(value = model.daysProtected?.let(number) ?: "–", label = "Days under protection"),
        ProfileStat(value = number(stats.blocked), label = "Blocked"),
        ProfileStat(value = number(stats.warnings), label = "Warnings"),
    )
}

/** "iPhone 15 · iOS 26" / "Pixel 8 · Android 15". */
private fun memberDeviceText(member: FamilyMember): String? {
    val model = member.deviceModel ?: return null
    val os = when {
        model.startsWith("iPad") -> "iPadOS"
        model.startsWith("iPhone") -> "iOS"
        else -> "Android"
    }
    return member.osVersion?.let { "$model · $os $it" } ?: model
}

/** "Hari ini · 10.42 WIB" / "25 Okt · 19.08 WIB". Swift `MemberDetailView.when(_:now:language:timeZone:)`. */
internal fun memberActivityWhen(
    date: Instant,
    now: Instant = Instant.now(),
    language: AppLanguage,
    zone: ZoneId = ZoneId.systemDefault(),
): String {
    val time = Formatters.dateFormatter("jm", language, zone).format(Date.from(date))
    val icuZone = TimeZone.getTimeZone(zone.id)
    val daylight = icuZone.inDaylightTime(Date.from(date))
    // iOS `TimeZone.abbreviation(for:)` ("GMT+7", "EST"); Indonesian zones by their usual names.
    val abbreviation = icuZone.getDisplayName(daylight, TimeZone.SHORT, ULocale.US)
    val zoneText = abbreviation?.takeIf { it.isNotEmpty() }?.let { " ${zoneName(it)}" } ?: ""
    val day = if (date.atZone(zone).toLocalDate() == now.atZone(zone).toLocalDate()) {
        L10n.string("Today", language)
    } else {
        Formatters.dateFormatter("MMMd", language, zone).format(Date.from(date))
    }
    return "$day · $time$zoneText"
}

/** Indonesian zones by their usual names (GMT+7 → WIB). */
private fun zoneName(abbreviation: String): String = when (abbreviation) {
    "GMT+7", "GMT+07:00" -> "WIB"
    "GMT+8", "GMT+08:00" -> "WITA"
    "GMT+9", "GMT+09:00" -> "WIT"
    else -> abbreviation
}
