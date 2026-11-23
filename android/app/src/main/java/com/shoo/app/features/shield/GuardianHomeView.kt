package com.shoo.app.features.shield

import android.content.Context
import android.content.Intent
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith

import androidx.compose.foundation.ExperimentalFoundationApi
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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import com.shoo.app.R
import com.shoo.app.app.AppSettings
import com.shoo.app.app.AppTab
import com.shoo.app.app.LocalAppEnvironment
import com.shoo.app.app.ProfilePage
import com.shoo.app.app.Route
import com.shoo.app.components.AvatarView
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.HalftoneShieldTint
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.SiteIcon
import com.shoo.app.components.SkeletonActivity
import com.shoo.app.components.StateMotion
import com.shoo.app.components.StateNoticeCard
import com.shoo.app.components.StateNoticeTone
import com.shoo.app.components.figmaButtonShadow
import com.shoo.app.components.hex
import com.shoo.app.components.shooEaseInOut
import com.shoo.app.components.shooEaseOut
import com.shoo.app.components.shooSmooth
import com.shoo.app.components.shooSnappy
import com.shoo.app.components.stateEntrance
import com.shoo.app.data.DeviceProfile
import com.shoo.app.data.ExtensionStatus
import com.shoo.app.data.FamilyCode
import com.shoo.app.data.FamilyMember
import com.shoo.app.data.ScanResult
import com.shoo.app.data.ScanStatus
import com.shoo.app.data.ShooRepository
import com.shoo.app.data.UserMode
import com.shoo.app.data.Verdict
import com.shoo.app.features.activity.RefreshFailedNotice
import com.shoo.app.features.detail.Evidence
import com.shoo.app.features.detail.SafeReasonSheet
import com.shoo.app.features.onboarding.OnboardingTheme
import com.shoo.app.features.onboarding.onboardingFont
import com.shoo.app.features.pairing.FamilyCodeModel
import com.shoo.app.features.profile.BecomeSupervisedCard
import com.shoo.app.support.AppLanguage
import com.shoo.app.support.Formatters
import com.shoo.app.support.L10n
import com.shoo.app.support.Log
import com.shoo.app.support.t
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Guardian Home, both sides of the ⇆ switch (GD-01/02/03, Figma HOME page).
 * `PERSONAL` (Family mode off, "Pribadi/Home" 435:20058, Waspada 955:10369, Bahaya 955:10467): the hero says how
 * the last day went, then own recent sites and the latest scams; with nobody to look after, the "Mode Terawasi"
 * card first (1382:10567).
 * `FAMILY` ("Guardian/Home/ no recently blocked or warning" 435:20373): teal hero, the people looked after, the site
 * that waits for a verdict (warning 1382:2599, blocked 1382:10314), the family's recent sites; nobody yet → the invite
 * code and how it works (1382:10466). No status strip any more: the white sheet sits right on the hero.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GuardianHomeView(
    repository: ShooRepository,
    settings: AppSettings,
    scope: GuardianHomeModel.Scope,
    extensionStatus: suspend () -> ExtensionStatus,
    profile: (suspend () -> DeviceProfile)? = null,
    onVerdictSaved: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val env = LocalAppEnvironment.current
    val language = LocalAppLanguage.current
    val reduceMotion = LocalReduceMotion.current
    val view = LocalView.current
    val coroutines = rememberCoroutineScope()
    val model = remember(repository, settings, scope) {
        GuardianHomeModel(
            repository = repository,
            settings = settings,
            scope = scope,
            extensionStatus = extensionStatus,
            profile = profile,
            onVerdictSaved = onVerdictSaved,
        )
    }
    /** Someone joined from the invite card: the refresh that follows hands the sheet over with an animation. */
    var joinAnimates by remember { mutableStateOf(false) }
    /** The hero is scrolled out from under the status bar: the top scrim takes over as its backdrop. */
    var isHeroHidden by remember { mutableStateOf(false) }
    /** "Aman" on the pending card opens SafeReasonSheet for that site (its id, kept while the sheet is open). */
    var safeReasonScanId by remember { mutableStateOf<String?>(null) }
    val isFamily = model.scope == GuardianHomeModel.Scope.FAMILY
    // Card to card, card to members, invite to family: a soft ease; a short cross-fade with Reduce Motion. Only the
    // update that saved a verdict (`.animation(handOver, value: verdictSaves)`) or brought the family in after a
    // join (`.animation(joinAnimates ? handOver : nil, value: hasNoFamily)`); loads and refreshes stay instant.
    val handOver: FiniteAnimationSpec<Float> = if (reduceMotion) shooEaseInOut<Float>(0.2) else shooSmooth<Float>(0.3)
    val savesChanged = changedNow(model.verdictSaves)
    val familyChanged = changedNow(model.hasNoFamily)
    val pageAnimation = if (savesChanged || (joinAnimates && familyChanged)) handOver else null

    fun switchSide() {
        if (isFamily) env.settings.familyModeOn = false else env.requestFamilyMode()
        view.shieldAnnounce(
            L10n.string(
                if (isFamily) "Family mode off. Showing your Shield." else "Family mode on. Showing your family.",
                env.settings.language,
            ),
        )
    }

    /** From the bottom of the sheet to "Aktivitas Terakhir" / "Cara Kerja": 32 (435:20373), 7 (1382:2599), 22 (1382:10466). */
    val belowGap: Dp = when {
        model.state != GuardianHomeModel.State.LOADED -> 24.dp
        model.hasNoFamily -> 22.dp
        model.pendingScan != null -> 7.dp
        else -> 32.dp
    }
    val belowGapShown = animatedOrSnapped(belowGap.value, pageAnimation).dp

    Box(modifier) {
        ShieldHomeFrame(
            isHeroHidden = isHeroHidden,
            onRefresh = { model.refresh() },
            // Switch and profile right under the status bar, where the (hidden) navigation bar would be. The cached
            // avatar until `GET /devices/me` answers, so the circle never waits for the network.
            topBar = {
                HomeTopBar(
                    avatarId = model.profile?.avatarId ?: env.session?.avatarId,
                    onSwitch = { switchSide() },
                    onProfile = { env.router.openProfile() },
                    isFamilyShown = isFamily,
                )
            },
        ) {
            GuardianHero(
                model = model,
                animation = pageAnimation,
                onTurnOn = { env.router.isTurnOnPresented = true },
                modifier = Modifier.onShieldHeroHidden { isHeroHidden = it },
            )
            if (isFamily) {
                Box(Modifier.homeSheet()) {
                    GuardianSheet(
                        model = model,
                        language = language,
                        joinAnimates = joinAnimates,
                        onJoined = {
                            joinAnimates = true
                            coroutines.launch { model.refresh() }
                        },
                        onSafe = { safeReasonScanId = it },
                    )
                }
                Column(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 24.dp)
                        .padding(top = belowGapShown, bottom = 32.dp),
                    verticalArrangement = Arrangement.spacedBy(24.dp),
                ) {
                    GuardianBelow(model = model, language = language)
                }
            } else {
                // Figma "Status" 957:10957: no strip, the page itself rounds up over the hero.
                Box(
                    Modifier
                        .fillMaxWidth()
                        .background(HomeTheme.background, RoundedCornerShape(22.dp))
                        .padding(horizontal = 24.dp)
                        .padding(top = 30.dp, bottom = 32.dp),
                ) {
                    GuardianSheet(
                        model = model,
                        language = language,
                        joinAnimates = joinAnimates,
                        onJoined = {},
                        onSafe = {},
                    )
                }
            }
        }
    }

    // MARK: Effects

    val sceneActive = rememberShieldSceneActive()
    LaunchedEffect(sceneActive) {
        if (sceneActive) model.refresh()
    }
    ShieldOnChange(model.hasNoFamily) { hadNoFamily, hasNoFamily ->
        // Someone joined from the invite card: one success tap, the guardian's "connected" moment.
        if (joinAnimates && hadNoFamily && !hasNoFamily) view.shieldHaptic(ShieldHaptic.SUCCESS)
        joinAnimates = false
    }
    // Same haptic as a verdict saved on Detail (DetailView).
    ShieldOnChange(model.verdictSaves) { _, _ -> view.shieldHaptic(ShieldHaptic.SUCCESS) }
    // "Couldn't save" under Aman / Bahaya is felt too, not only read.
    ShieldOnChange(model.verdictFailed) { _, failed -> if (failed) view.shieldHaptic(ShieldHaptic.ERROR) }
    // A push while Home is open (new scan, verdict, member change): reload, not just the banner.
    ShieldOnChange(env.pushesWhileOpen) { _, _ -> coroutines.launch { model.refresh() } }
    ShieldOnChange(model.refreshFailed) { _, failed ->
        if (failed) view.shieldAnnounce(L10n.string("Couldn't refresh. Pull down to try again.", language))
    }
    ShieldOnChange(model.extensionStatus.isActive) { _, isActive ->
        if (model.state != GuardianHomeModel.State.LOADED || isFamily) return@ShieldOnChange
        view.shieldAnnounce(L10n.string(if (isActive) "You're protected!" else "You're not protected yet", language))
    }
    ShieldTurnOnSheet(onDismissed = { coroutines.launch { model.refresh() } })
    // A tapped push opens Detail on Activity: "Why is it safe?" must not stay over it.
    ShieldOnChange(env.router.screenSheetsClosed) { _, _ -> safeReasonScanId = null }

    // "Aman" overrides Shoo, so it asks why first (SafeReasonSheet, Detail). It closes once the verdict is saved.
    val reasonScanId = safeReasonScanId
    if (reasonScanId != null) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { safeReasonScanId = null },
            sheetState = sheetState,
            shape = RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp),
            containerColor = Color.White,
            dragHandle = null,
        ) {
            SafeReasonSheet(
                onSubmit = { notes ->
                    val closes = model.decide(Verdict.Value.SAFE, notes = notes, scanId = reasonScanId)
                    if (closes) safeReasonScanId = null
                    closes
                },
                onDismiss = { safeReasonScanId = null },
            )
        }
    }
}

// MARK: Hero and status

@Composable
private fun GuardianHero(
    model: GuardianHomeModel,
    animation: FiniteAnimationSpec<Float>?,
    onTurnOn: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isFamily = model.scope == GuardianHomeModel.Scope.FAMILY
    if (!isFamily) {
        // A-06 (fase 28a K3): until the browser has answered, neither "protected" nor "not protected yet".
        val isUnread = !model.extensionChecked
        val isActive = model.extensionStatus.isActive
        val isOff = !isUnread && !isActive
        // The level reads the last day's sites: while they load (or never loaded) the hero only says Shoo is
        // on, never "You're protected!" without the data behind it.
        val isChecking = isActive && model.state != GuardianHomeModel.State.LOADED
        // Shoo being off outranks what it saw while it was on.
        val level = if (isActive && !isChecking) model.level else GuardianHomeModel.Level.NORMAL
        val title = when {
            isUnread -> "Checking Shoo…"
            isOff -> "You're not protected yet"
            isChecking -> "Shoo is on"
            else -> level.title
        }
        val identifier = when {
            isUnread -> "home.status.extensionChecking"
            isOff -> "home.status.off"
            isChecking -> "home.status.checking"
            else -> level.titleIdentifier
        }
        HomeHero(
            style = level.heroStyle,
            title = title,
            titleIdentifier = identifier,
            shieldOn = !isOff,
            shieldTint = level.shieldTint,
            bottomPadding = if (isOff) 20.dp else null,
            animation = animation,
            modifier = modifier,
        ) {
            if (isOff) HeroTurnOnLink(title = "Turn on now", identifier = "home.turnOn", onClick = onTurnOn)
        }
    } else {
        // One hero for every family state (iOS: one branch each), so the hand-over can cross-fade the headline and
        // ease the shield; iOS cross-fades the whole hero, the teal backdrop being the same.
        val hero = when {
            // Figma "Guardian/Home · Gagal memuat" (1665:3038): nothing loaded, so no "Family protected!".
            model.state == GuardianHomeModel.State.FAILED ->
                FamilyHero("Status not available yet", "home.family.unavailable", null, HomeHeroLayout.family)
            // U-01 (fase 28a K2): no "Family protected!" before the family's sites are in. Pribadi's pattern and
            // strings while it loads: "Shoo is on" once the browser said so, "Checking Shoo…" before that or when it's off.
            model.state == GuardianHomeModel.State.LOADING -> FamilyHero(
                if (model.extensionChecked && model.extensionStatus.isActive) "Shoo is on" else "Checking Shoo…",
                "home.family.checking", null, HomeHeroLayout.family,
            )
            // Figma 1382:10466: the teal hero, white headline and line.
            model.hasNoFamily ->
                FamilyHero("Protect your loved ones", "home.family.empty", "No one to protect yet", HomeHeroLayout.familyEmpty)
            // Figma 1382:2599 / 1382:10314: the hero stays teal; the card below carries the colour.
            model.pendingScan != null -> FamilyHero(
                if (model.level == GuardianHomeModel.Level.DANGER) "Family under threat" else "Family needs confirmation",
                "home.family.pending", null, HomeHeroLayout.familyPending,
            )
            else -> FamilyHero("Family protected!", "home.family.protected", null, HomeHeroLayout.family)
        }
        HomeHero(
            style = HomeHeroStyle.TEAL,
            title = hero.title,
            titleIdentifier = hero.identifier,
            subtitle = hero.subtitle,
            shieldTint = HalftoneShieldTint.TEAL,
            layout = hero.layout,
            animation = animation,
            modifier = modifier,
        )
    }
}

private class FamilyHero(val title: String, val identifier: String, val subtitle: String?, val layout: HomeHeroLayout)

// MARK: Sheet

/** What the family sheet shows once loaded; a change between them hands over (fade, and 97 % scale for the card). */
private sealed interface FamilySheetContent {
    data object Invite : FamilySheetContent
    data class Pending(val scanId: String) : FamilySheetContent
    data object Members : FamilySheetContent
}

@Composable
private fun GuardianSheet(
    model: GuardianHomeModel,
    language: AppLanguage,
    joinAnimates: Boolean,
    onJoined: () -> Unit,
    onSafe: (String) -> Unit,
) {
    val env = LocalAppEnvironment.current
    val reduceMotion = LocalReduceMotion.current
    val isFamily = model.scope == GuardianHomeModel.Scope.FAMILY
    val coroutines = rememberCoroutineScope()
    when (model.state) {
        GuardianHomeModel.State.LOADING -> {
            // The rows that are coming, sweeping while they load.
            val loading = t("Loading")
            SkeletonActivity(
                rows = 3,
                animating = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 216.dp)
                    .padding(if (isFamily) 24.dp else 0.dp)
                    .clearAndSetSemantics { contentDescription = loading },
            )
        }
        GuardianHomeModel.State.FAILED -> {
            // Figma "Guardian/Home · Gagal memuat" (1665:3038): the card, "Aktivitas Terakhir", three grey rows.
            Column(
                Modifier.padding(if (isFamily) 24.dp else 0.dp),
                verticalArrangement = Arrangement.spacedBy(22.dp),
            ) {
                StateNoticeCard(
                    title = "Couldn't load",
                    message = t(model.loadFailure.message(connection = "Check your connection.")),
                    actionTitle = "Try again",
                    action = { model.retry() },
                    modifier = Modifier
                        .testTag("home.loadError")
                        .stateEntrance(),
                )
                SkeletonActivity(rows = 3)
            }
        }
        GuardianHomeModel.State.LOADED -> if (!isFamily) {
            PersonalSheet(model = model, language = language)
        } else {
            // Card to card, card to members, invite to family: a soft ease; a short cross-fade with Reduce Motion.
            // Only after a saved verdict or a join; loads and refreshes stay instant.
            var seenSaves by remember { mutableIntStateOf(model.verdictSaves) }
            val handsOver = joinAnimates || model.verdictSaves != seenSaves
            LaunchedEffect(model.verdictSaves) { seenSaves = model.verdictSaves }
            val pending = model.pendingScan
            val content: FamilySheetContent = when {
                model.hasNoFamily -> FamilySheetContent.Invite
                pending != null -> FamilySheetContent.Pending(pending.id)
                else -> FamilySheetContent.Members
            }
            AnimatedContent(
                targetState = content,
                transitionSpec = {
                    if (!handsOver) {
                        (EnterTransition.None togetherWith ExitTransition.None).using(null)
                    } else if (reduceMotion) {
                        (fadeIn(shooEaseInOut<Float>(0.2)) togetherWith fadeOut(shooEaseInOut<Float>(0.2)))
                            .using(SizeTransform(clip = false) { _, _ -> shooEaseInOut<IntSize>(0.2) })
                    } else {
                        var enter = fadeIn(shooSmooth<Float>(0.3))
                        if (targetState is FamilySheetContent.Pending) enter += scaleIn(shooSmooth<Float>(0.3), initialScale = 0.97f)
                        var exit = fadeOut(shooSmooth<Float>(0.3))
                        if (initialState is FamilySheetContent.Pending) exit += scaleOut(shooSmooth<Float>(0.3), targetScale = 0.97f)
                        (enter togetherWith exit).using(SizeTransform(clip = false) { _, _ -> shooSmooth<IntSize>(0.3) })
                    }
                },
                label = "familySheet",
            ) { shown ->
                when (shown) {
                    FamilySheetContent.Invite -> {
                        // Figma "Konten" 1382:10499: the card 16 under the sheet's top, 24 from its sides, 20 above its bottom.
                        InviteCodeCard(
                            repository = env.repository,
                            onJoined = onJoined,
                            modifier = Modifier.padding(start = 24.dp, end = 24.dp, top = 16.dp, bottom = 20.dp),
                        )
                    }
                    is FamilySheetContent.Pending -> {
                        val scan = model.scans.firstOrNull { it.id == shown.scanId }
                        if (scan != null) {
                            // A card on its way out (a verdict moved the sheet on) keeps what it showed, like SwiftUI's
                            // removal transition.
                            val now = Triple(model.canDecide, model.verdictFailed, model.verdictNotAllowed)
                            val last = remember(scan.id) { arrayOf(now) }
                            if (model.pendingScan?.id == scan.id) last[0] = now
                            val (canDecide, failed, notAllowed) = last[0]
                            PendingSiteCard(
                                scan = scan,
                                ownerAvatarId = model.avatarId(forOwner = scan.ownerDeviceId),
                                language = language,
                                canDecide = canDecide,
                                failed = failed,
                                notAllowed = notAllowed,
                                onOpen = { env.router.showDetail(scan.id) },
                                onDecide = { value ->
                                    // "Aman" overrides Shoo, so it asks why first; "Bahaya" applies at once.
                                    if (value == Verdict.Value.SAFE) {
                                        onSafe(scan.id)
                                    } else {
                                        coroutines.launch { model.decide(value, scanId = scan.id) }
                                    }
                                },
                                onRetry = { model.retryDecision() },
                            )
                        }
                    }
                    FamilySheetContent.Members -> {
                        // Figma "Status" 435:20432: the title 24 under the sheet's top, the row 8 under it, 16 above the bottom.
                        Column(
                            Modifier.padding(start = 24.dp, end = 24.dp, top = 24.dp, bottom = 16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            HomeSectionTitle("People you protect")
                            MembersRow(members = model.shownMembers) { env.router.show(Route.Member(deviceId = it.deviceId)) }
                        }
                    }
                }
            }
        }
    }
}

/** Figma 435:20058: the list, 35 pt, the scams; 1382:10567 puts the "Mode Terawasi" card first and 37 pt between the three. */
@Composable
private fun PersonalSheet(model: GuardianHomeModel, language: AppLanguage) {
    val env = LocalAppEnvironment.current
    val reduceMotion = LocalReduceMotion.current
    val showsCard = model.showsSupervisedCard
    var dismissing by remember { mutableStateOf(false) }
    val cardChanged = changedNow(showsCard)
    val dismissal: FiniteAnimationSpec<Float>? = if (dismissing && cardChanged) shooEaseOut<Float>(0.2) else null
    LaunchedEffect(showsCard) { dismissing = false }
    Column(Modifier.fillMaxWidth()) {
        AnimatedVisibility(
            visible = model.refreshFailed,
            enter = stateNoticeEnter(reduceMotion),
            exit = stateNoticeExit(reduceMotion),
        ) {
            GuardianRefreshFailedNotice(model, Modifier.padding(bottom = 24.dp))
        }
        AnimatedVisibility(visible = showsCard, enter = fadeIn(shooEaseOut<Float>(0.2)), exit = dismissExit) {
            // "Hubungkan": joining a family as protected lives in Profile › Account mode ("Have an invite code?"),
            // which checks that nobody is looked after first.
            SupervisedModeCard(
                onConnect = { env.router.show(Route.ProfilePage(ProfilePage.MODE)) },
                onDismiss = {
                    dismissing = true
                    model.dismissSupervisedCard()
                },
                modifier = Modifier.padding(top = 1.dp, bottom = 37.dp),
            )
        }
        RecentActivity(
            scans = model.recent,
            language = language,
            onOpen = { env.router.showDetail(it.id) },
            onSeeAll = { env.router.selectedTab = AppTab.ACTIVITY },
            // Figma: the title 32 under the sheet's top (the card sits 31 under it).
            modifier = Modifier.padding(top = animatedOrSnapped(if (showsCard) 0f else 3f, dismissal).dp),
        )
        if (model.scamCases.isNotEmpty()) {
            LatestScamsCard(
                cases = model.scamCases,
                modifier = Modifier.padding(top = animatedOrSnapped(if (showsCard) 37f else 35f, dismissal).dp),
            )
        }
    }
}

@Composable
private fun GuardianBelow(model: GuardianHomeModel, language: AppLanguage) {
    val env = LocalAppEnvironment.current
    val reduceMotion = LocalReduceMotion.current
    if (model.state != GuardianHomeModel.State.LOADED) return
    AnimatedVisibility(
        visible = model.refreshFailed,
        enter = stateNoticeEnter(reduceMotion),
        exit = stateNoticeExit(reduceMotion),
    ) {
        GuardianRefreshFailedNotice(model)
    }
    if (model.hasNoFamily) {
        Column {
            HowItWorks()
            // Figma "Guardian/Home · Belum ada orang" (1253:2381): 42 under How it works.
            BecomeSupervisedCard(
                action = "Become supervised",
                onConnect = { env.router.isJoinFamilyPresented = true },
                modifier = Modifier.padding(top = 42.dp),
            )
        }
    } else {
        RecentActivity(
            scans = model.recent,
            language = language,
            showsOwner = true,
            seeAllPlacement = SeeAllPlacement.BELOW,
            onOpen = { env.router.showDetail(it.id) },
            onSeeAll = { env.router.selectedTab = AppTab.ACTIVITY },
        )
    }
}

/**
 * A refresh after the first load failed: what is shown stays, and this says it may be old (D-alief-A12,
 * fase 28a K1). The same notice as Activity's.
 */
@Composable
private fun GuardianRefreshFailedNotice(model: GuardianHomeModel, modifier: Modifier = Modifier) {
    RefreshFailedNotice(
        retryIdentifier = "home.refreshRetry",
        retry = { model.refresh() },
        modifier = modifier.testTag("home.refreshFailed"),
    )
}

// MARK: - Personal: the hero per level

private val GuardianHomeModel.Level.heroStyle: HomeHeroStyle
    get() = when (this) {
        GuardianHomeModel.Level.NORMAL -> HomeHeroStyle.BLUE
        GuardianHomeModel.Level.WARNING -> HomeHeroStyle.AMBER
        GuardianHomeModel.Level.DANGER -> HomeHeroStyle.RED
    }

private val GuardianHomeModel.Level.shieldTint: HalftoneShieldTint
    get() = when (this) {
        GuardianHomeModel.Level.NORMAL -> HalftoneShieldTint.BLUE
        GuardianHomeModel.Level.WARNING -> HalftoneShieldTint.AMBER
        GuardianHomeModel.Level.DANGER -> HalftoneShieldTint.RED
    }

private val GuardianHomeModel.Level.title: String
    get() = when (this) {
        GuardianHomeModel.Level.NORMAL -> "You're protected!"
        GuardianHomeModel.Level.WARNING -> "Stay alert!"
        GuardianHomeModel.Level.DANGER -> "Danger detected!"
    }

private val GuardianHomeModel.Level.titleIdentifier: String
    get() = when (this) {
        GuardianHomeModel.Level.NORMAL -> "home.status.active"
        GuardianHomeModel.Level.WARNING -> "home.status.warning"
        GuardianHomeModel.Level.DANGER -> "home.status.danger"
    }

// MARK: - Family: the people looked after

/** Figma "Frame 1618872221": up to three people side by side, a dot for whether Shoo is on for them. */
@Composable
private fun MembersRow(members: List<FamilyMember>, onOpen: (FamilyMember) -> Unit) {
    val modifier = Modifier
        .fillMaxWidth()
        .testTag("family.header")
    if (isAccessibilityTextSize()) {
        Column(modifier) {
            members.forEachIndexed { index, member ->
                if (index > 0) FadingDivider()
                MemberCell(member = member, onOpen = { onOpen(member) })
            }
        }
    } else {
        Row(modifier, verticalAlignment = Alignment.Top) {
            members.forEachIndexed { index, member ->
                if (index > 0) {
                    // Figma Line 13 / 14: 100 pt, solid for the top half, fading out below, 9 pt under the row top;
                    // 16 pt either side.
                    Box(
                        Modifier
                            .padding(top = 9.dp, start = 16.dp, end = 16.dp)
                            .width(1.dp)
                            .height(100.dp)
                            .background(
                                Brush.verticalGradient(
                                    0f to HomeTheme.divider,
                                    0.5f to HomeTheme.divider,
                                    1f to HomeTheme.divider.copy(alpha = 0f),
                                ),
                            )
                            .clearAndSetSemantics { },
                    )
                }
                MemberCell(member = member, onOpen = { onOpen(member) }, modifier = Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun MemberCell(member: FamilyMember, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    val hint = t("Opens their activity")
    Column(
        modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                role = Role.Button,
                onClickLabel = hint,
                onClick = onOpen,
            )
            .semantics(mergeDescendants = true) { }
            .testTag("family.member.${member.deviceId}")
            .padding(vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // Figma "Avatar": 44 pt, the member's picked avatar (the name is read out below it).
        Box {
            AvatarView(id = member.avatarId, size = 44.dp)
            // Figma: 12 pt dot, 1 pt white ring outside, flush with the avatar's bottom right.
            Box(
                Modifier
                    .align(Alignment.BottomEnd)
                    .offset(x = 1.dp, y = 1.dp)
                    .size(14.dp)
                    .background(Color.White, CircleShape)
                    .padding(1.dp)
                    .background(if (member.isConnected) HomeTheme.success else HomeTheme.offline, CircleShape),
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            // Figma "Info": SF Pro Rounded 17 (-1 %, 22 pt lines) #151617, then 13 (-0.08, 18 pt) Labels/Secondary.
            Text(
                text = member.name,
                style = onboardingFont(17f, rounded = true, tracking = -0.17f, lineHeight = 22f),
                color = HomeTheme.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = t(if (member.isConnected) "Active" else "Not connected"),
                style = onboardingFont(13f, rounded = true, tracking = -0.08f, lineHeight = 18f),
                color = HomeTheme.memberStatus,
            )
        }
    }
}

// MARK: - Family: the site that waits

/**
 * Figma "Frame 1618872233" (warning 1382:3072, blocked 1382:10314): a frosted grey card with a soft glow at its
 * foot; the site and when with a ↗ to the details, the risk panel (shield, "Situs Mencurigakan!", the bar), who
 * opened it, the reason, then Aman / Bahaya. Points are from the card's top left. `ownerAvatarId` null: the owner is
 * not in the family list (yet); the neutral person is drawn.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PendingSiteCard(
    scan: ScanResult,
    ownerAvatarId: String?,
    language: AppLanguage,
    canDecide: Boolean,
    failed: Boolean,
    notAllowed: Boolean,
    onOpen: () -> Unit,
    onDecide: (Verdict.Value) -> Unit,
    onRetry: suspend () -> Unit = {},
) {
    val view = LocalView.current
    val reduceMotion = LocalReduceMotion.current
    val accessibilitySize = isAccessibilityTextSize()
    val isBlocked = scan.status == ScanStatus.BLOCKED
    val dim by animateFloatAsState(if (notAllowed) 1f else 0f, StateMotion.enter(reduceMotion), label = "pendingDim")
    val reason = Evidence.top(scan.signals, mode = UserMode.GUARDIAN, language = language, limit = 1).firstOrNull()?.text
    val hint = t("Opens the details")
    val shape = RoundedCornerShape(20.7.dp)
    // U-02 (fase 28e, K7): the notice stays at the card's foot (Figma 1665:3183), which can sit under the tab bar.
    // When it shows, the page scrolls the least it can to show it whole. TalkBack hears it too.
    val errorRequester = remember { BringIntoViewRequester() }
    LaunchedEffect(failed) {
        if (!failed) return@LaunchedEffect
        delay(32)
        errorRequester.bringIntoView()
        view.shieldAnnounce(L10n.string("Couldn't save", language) + ". " + L10n.string("Check your connection.", language))
    }

    Column(
        Modifier
            // Figma "Konten": the card 16 under the sheet's top and above its bottom, 16 from the left, 20 from the right.
            .padding(top = 16.dp, bottom = 16.dp, start = 16.dp, end = 20.dp)
            .fillMaxWidth()
            .clip(shape)
            .drawBehind {
                // #EDEDED at 50 % on the white sheet, 20.7 pt corners; Figma "Rectangle 9652": 143 pt at the foot, the
                // colour fading in downwards, the whole fill at 20 %.
                drawRect(hex(0xEDEDED, 0.5f))
                val glowHeight = 143.dp.toPx()
                val colors = if (isBlocked) listOf(hex(0xF28D83, 0f), hex(0xF26153)) else listOf(hex(0xFB9E20, 0f), hex(0xFB9E20))
                drawRect(
                    Brush.verticalGradient(colors, startY = size.height - glowHeight, endY = size.height),
                    topLeft = Offset(0f, size.height - glowHeight),
                    size = Size(size.width, glowHeight),
                    alpha = 0.2f,
                )
            }
            .animateContentSize(stateSizeSpec(reduceMotion))
            .padding(bottom = if (failed || notAllowed) 0.dp else if (canDecide) 14.7.dp else 20.dp),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    role = Role.Button,
                    onClickLabel = hint,
                    onClick = onOpen,
                )
                .semantics(mergeDescendants = true) { }
                .testTag("home.pending"),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            PendingHeader(scan = scan, language = language, lines = if (accessibilitySize) 3 else 1)
            // Figma: the panel 16.1 / 11.9 in from the card's sides, i.e. centred on the screen.
            HomeRiskPanel(
                scan = scan,
                isDanger = isBlocked,
                layered = true,
                modifier = Modifier.padding(start = 16.1.dp, end = 11.9.dp, top = 11.8.dp),
            )
            // Centred on the screen too (2.1 right of the card's centre).
            PendingOwner(scan = scan, ownerAvatarId = ownerAvatarId, language = language, modifier = Modifier.padding(start = 4.2.dp, top = 5.dp))
            if (reason != null) {
                // Figma: SF Pro Rounded 15.97, 140 % lines, #6A717E; 21 from the left, 16.8 from the right.
                Text(
                    text = reason,
                    style = onboardingFont(15.97f, rounded = true, lineHeight = 22.36f),
                    color = OnboardingTheme.bodyInk,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 21.dp, end = 16.8.dp, top = 7.5.dp),
                )
            }
        }

        if (canDecide) {
            // Figma: Aman 150.5, Bahaya 153.4, 9.7 apart. While the site can't be marked (1665:3387), both buttons go
            // grey and stop taking taps.
            val buttons = Modifier
                .padding(start = 28.3.dp, end = 24.1.dp, top = 20.dp)
                .grayscale(dim)
                .graphicsLayer { alpha = 1f - 0.5f * dim }
            if (accessibilitySize) {
                Column(buttons, verticalArrangement = Arrangement.spacedBy(9.7.dp)) {
                    DecisionButton(DecisionKind.SAFE, enabled = !notAllowed, onClick = { onDecide(Verdict.Value.SAFE) }, modifier = Modifier.testTag("home.verdict.safe"))
                    DecisionButton(DecisionKind.DANGER, enabled = !notAllowed, onClick = { onDecide(Verdict.Value.NOT_SAFE) }, modifier = Modifier.testTag("home.verdict.notSafe"))
                }
            } else {
                Row(buttons.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(9.7.dp)) {
                    DecisionButton(
                        DecisionKind.SAFE,
                        enabled = !notAllowed,
                        onClick = { onDecide(Verdict.Value.SAFE) },
                        modifier = Modifier
                            .weight(150.5f)
                            .testTag("home.verdict.safe"),
                    )
                    DecisionButton(
                        DecisionKind.DANGER,
                        enabled = !notAllowed,
                        onClick = { onDecide(Verdict.Value.NOT_SAFE) },
                        modifier = Modifier
                            .weight(153.4f)
                            .testTag("home.verdict.notSafe"),
                    )
                }
            }
        }
        // Figma "Pesan verdict" (1665:3183 / 1665:3387): the card's own foot, full width, 26 under the buttons.
        AnimatedVisibility(
            visible = failed,
            enter = StateMotion.enterTransition(reduceMotion),
            exit = StateMotion.exitTransition(reduceMotion),
            modifier = Modifier.bringIntoViewRequester(errorRequester),
        ) {
            StateNoticeCard(
                title = "Couldn't save",
                message = t("Check your connection."),
                actionTitle = "Try again",
                cornerRadius = 16.dp,
                action = onRetry,
                modifier = Modifier
                    .padding(top = 26.dp)
                    .testTag("home.verdictError"),
            )
        }
        AnimatedVisibility(
            visible = notAllowed && !failed,
            enter = StateMotion.enterTransition(reduceMotion),
            exit = StateMotion.exitTransition(reduceMotion),
        ) {
            StateNoticeCard(
                title = "Can't be marked yet",
                message = t("Open this site's details first."),
                tone = StateNoticeTone.INFO,
                actionTitle = "Open details",
                cornerRadius = 16.dp,
                action = { onOpen() },
                modifier = Modifier
                    .padding(top = 26.dp)
                    .testTag("home.verdictNotAllowed"),
            )
        }
    }
}

/**
 * Figma "Frame 1618872182": the 49.6 pt icon, the site (SF Pro Rounded 17.58) and when (13.44) beside it,
 * a white 41.4 pt circle with ↗ on the right.
 */
@Composable
private fun PendingHeader(scan: ScanResult, language: AppLanguage, lines: Int) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(start = 17.6.dp, end = 14.4.dp, top = 14.5.dp),
        horizontalArrangement = Arrangement.spacedBy(12.4.dp),
        verticalAlignment = Alignment.Top,
    ) {
        SiteIcon(url = scan.faviconUrl, size = 49.6.dp)
        Column(
            Modifier
                .padding(top = 2.9.dp)
                .weight(1f),
        ) {
            // iOS: truncates in the middle; Compose only ends with the ellipsis.
            Text(
                text = scan.domain,
                style = onboardingFont(17.58f, rounded = true, tracking = -0.18f, lineHeight = 22.7f),
                color = HomeTheme.navy,
                maxLines = lines,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(vertical = 1.dp),
            )
            Text(
                text = Formatters.dayAndTime(scan.detectedAt, language),
                style = onboardingFont(13.44f, rounded = true, tracking = -0.08f, lineHeight = 18.6f),
                color = HomeTheme.rowSubtitle,
            )
        }
        // Figma "Status Badge": SF Symbol arrow.up.right semibold 15.07, #1A1A1A, on white.
        Box(
            Modifier
                .padding(top = 6.2.dp)
                .size(41.4.dp)
                .background(Color.White, CircleShape)
                .clearAndSetSemantics { },
            contentAlignment = Alignment.Center,
        ) {
            SfSymbol("arrow.up.right", pointSize = 15.07f, tint = HomeTheme.glassInk)
        }
    }
}

/** Figma "Frame 1618872332": the person's avatar (20.5 pt) and name in capitals, SF Pro Rounded Semibold 11.88. */
@Composable
private fun PendingOwner(scan: ScanResult, ownerAvatarId: String?, language: AppLanguage, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(8.9.dp), verticalAlignment = Alignment.CenterVertically) {
        AvatarView(id = ownerAvatarId ?: "", size = 20.5.dp)
        Text(
            text = scan.ownerName.uppercase(language.locale),
            style = onboardingFont(11.88f, FontWeight.SemiBold, rounded = true, tracking = -0.23f, lineHeight = 15.6f),
            color = HomeTheme.ink,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** SwiftUI `.grayscale(amount)`: 1 draws the content without colour. */
private fun Modifier.grayscale(amount: Float): Modifier = if (amount <= 0f) {
    this
} else {
    drawWithContent {
        val saturation = 1f - amount.coerceIn(0f, 1f)
        val paint = Paint().apply { colorFilter = ColorFilter.colorMatrix(ColorMatrix().apply { setToSaturation(saturation) }) }
        // Room for the buttons' shadow outside their bounds.
        val margin = 12.dp.toPx()
        drawIntoCanvas { canvas ->
            canvas.saveLayer(Rect(-margin, -margin, size.width + margin, size.height + margin), paint)
            drawContent()
            canvas.restore()
        }
    }
}

private enum class DecisionKind { SAFE, DANGER }

/**
 * Figma "Aman" (1382:10974) and "Bahaya" (1382:10977): 38.9 pt capsules side by side, a 1 pt #E3E3E3 ring and the
 * small drop shadow; Aman white with ✓ (checkmark.circle.fill), Bahaya the red gradient with the alert icon.
 * Under the finger they give like the Detail verdict buttons: 97 %, or dim with Reduce Motion.
 */
@Composable
private fun DecisionButton(kind: DecisionKind, enabled: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val reduceMotion = LocalReduceMotion.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed && !reduceMotion) 0.97f else 1f, shooEaseOut<Float>(0.15), label = "decisionScale")
    val pressAlpha by animateFloatAsState(if (pressed && reduceMotion) 0.8f else 1f, shooEaseOut<Float>(0.15), label = "decisionAlpha")
    val hint = t("Applies right away. You can change it later.")
    val ink = if (kind == DecisionKind.SAFE) HomeTheme.navy else Color.White
    Row(
        modifier
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
                alpha = pressAlpha
            }
            .figmaButtonShadow()
            .then(
                if (kind == DecisionKind.SAFE) {
                    Modifier.background(Color.White, CapsuleShape)
                } else {
                    Modifier.background(Brush.verticalGradient(listOf(hex(0xF64747), hex(0xBB1616))), CapsuleShape)
                },
            )
            .border(0.97.dp, hex(0xE3E3E3), CapsuleShape)
            .clickable(
                interactionSource = interaction,
                indication = null,
                enabled = enabled,
                role = Role.Button,
                onClickLabel = hint,
                onClick = onClick,
            )
            .heightIn(min = 38.9.dp),
        horizontalArrangement = Arrangement.spacedBy(if (kind == DecisionKind.SAFE) 7.77.dp else 6.63.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (kind == DecisionKind.SAFE) {
            SfSymbol("checkmark.circle.fill", pointSize = 16.5f, tint = ink)
            Text(
                text = t("Safe"),
                style = onboardingFont(16.5f, FontWeight.SemiBold, lineHeight = 21.4f),
                color = ink,
                maxLines = 1,
            )
        } else {
            Icon(
                painter = painterResource(R.drawable.home_alert_circle),
                contentDescription = null,
                tint = ink,
                modifier = Modifier.size(18.2.dp),
            )
            Text(
                text = t("Danger"),
                style = onboardingFont(14.08f, FontWeight.SemiBold, lineHeight = 18.2f),
                color = ink,
                maxLines = 1,
            )
        }
    }
}

// MARK: - Family: nobody yet

/**
 * Figma "Kode Undangan" (1382:10500): QR, the code with how long it lasts; Bagikan / Salin centred under the card
 * ("Aksi" 1382:10506) (GD-04).
 */
@Composable
private fun InviteCodeCard(repository: ShooRepository, onJoined: () -> Unit, modifier: Modifier = Modifier) {
    val model = remember(repository) { FamilyCodeModel(repository) }
    LaunchedEffect(model) { model.run() }
    // Someone joined while the code was on screen: Home shows the family.
    ShieldOnChange(model.members.size) { _, count -> if (count > 0) onJoined() }
    val code = model.code
    Column(
        modifier
            .fillMaxWidth()
            .testTag("home.invite"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .homeCard()
                .padding(17.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            InviteQr(model)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                InviteCodeContent(model)
            }
        }
        if (code != null && model.inviteURL != null) {
            InviteActions(model = model, code = code)
        }
    }
}

/** Figma "QR": 110 pt, 6 pt padding, 14 pt corners, 1 pt inside stroke. Drawn on the phone, never fetched. */
@Composable
private fun InviteQr(model: FamilyCodeModel) {
    val link = model.inviteURL?.toString()
    val image = remember(link) { link?.let { inviteQrImage(it) } }
    val shape = RoundedCornerShape(14.dp)
    val label = t("QR code to join your family")
    Box(
        Modifier
            .size(110.dp)
            .background(Color.White, shape)
            .border(1.dp, HomeTheme.rowStroke, shape)
            .padding(6.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (image != null) {
            Image(
                bitmap = image,
                contentDescription = label,
                contentScale = ContentScale.Fit,
                filterQuality = FilterQuality.None,
                modifier = Modifier
                    .matchParentSize()
                    .testTag("familyCode.qr"),
            )
        } else {
            CircularProgressIndicator(
                color = HomeTheme.secondaryInk,
                strokeWidth = 2.dp,
                modifier = Modifier
                    .size(20.dp)
                    .graphicsLayer { alpha = if (model.codeState is FamilyCodeModel.CodeState.Loading) 1f else 0f },
            )
        }
    }
}

/** iOS `QRCode.image(for:)` (CoreImage, correction level M), one pixel per module; drawn without smoothing. */
private fun inviteQrImage(text: String): ImageBitmap? = try {
    val matrix = QRCodeWriter().encode(
        text,
        BarcodeFormat.QR_CODE,
        0,
        0,
        mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M, EncodeHintType.MARGIN to 0),
    )
    val width = matrix.width
    val height = matrix.height
    val pixels = IntArray(width * height) { index ->
        if (matrix.get(index % width, index / width)) android.graphics.Color.BLACK else android.graphics.Color.WHITE
    }
    android.graphics.Bitmap.createBitmap(pixels, width, height, android.graphics.Bitmap.Config.ARGB_8888).asImageBitmap()
} catch (error: Exception) {
    Log.ui.error("Invite QR failed", error)
    null
}

/** Figma "Label" / "Kode" and the other states of the code. */
@Composable
private fun InviteCodeContent(model: FamilyCodeModel) {
    val coroutines = rememberCoroutineScope()
    when (model.codeState) {
        is FamilyCodeModel.CodeState.Loading -> Text(
            text = t("Getting a code"),
            style = onboardingFont(15f),
            color = HomeTheme.secondaryInk,
        )
        is FamilyCodeModel.CodeState.Ready -> {
            val code = model.code
            // Figma "Label": SF Pro Rounded 13, -0.08, 18 pt lines, #6A717E.
            Text(
                text = t("Invite code · valid for %@", model.timeLeft),
                style = onboardingFont(13f, rounded = true, tracking = -0.08f, lineHeight = 18f).copy(fontFeatureSettings = "tnum"),
                color = OnboardingTheme.bodyInk,
                modifier = Modifier.testTag("familyCode.countdown"),
            )
            if (code != null) {
                // Figma "Kode": SF Pro Display Bold 28, -2 %, 34 pt lines, #151617.
                // iOS: `.minimumScaleFactor(0.6)` has no Compose counterpart; the code stays on one line.
                val spoken = t("Code %@", code.code.toList().joinToString(" "))
                Text(
                    text = FamilyCodeModel.display(code.code),
                    style = onboardingFont(28f, FontWeight.Bold, tracking = -0.56f, lineHeight = 34f).copy(fontFeatureSettings = "tnum"),
                    color = HomeTheme.ink,
                    maxLines = 1,
                    softWrap = false,
                    modifier = Modifier
                        .clearAndSetSemantics { contentDescription = spoken }
                        .testTag("familyCode.code"),
                )
            }
        }
        is FamilyCodeModel.CodeState.Unavailable -> {
            Text(
                text = t("Couldn't get a code"),
                style = onboardingFont(15f, FontWeight.Medium),
                color = HomeTheme.ink,
            )
            Box(
                Modifier
                    .heightIn(min = 44.dp)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        role = Role.Button,
                    ) { coroutines.launch { model.refreshCode() } }
                    .testTag("familyCode.retry"),
                contentAlignment = Alignment.CenterStart,
            ) {
                Text(text = t("Try again"), style = onboardingFont(14f, FontWeight.Medium), color = HomeTheme.action)
            }
        }
        is FamilyCodeModel.CodeState.Full -> Text(
            text = t("Your family is full (3 people). Remove someone to invite another person."),
            style = onboardingFont(15f),
            color = HomeTheme.secondaryInk,
        )
    }
}

/** Figma "Aksi": 34 pt pills 8 apart, SF Pro Rounded 17 (140 %); Bagikan #186FB9, Salin #E6E8EC. */
@Composable
private fun InviteActions(model: FamilyCodeModel, code: FamilyCode) {
    val context = LocalContext.current
    val view = LocalView.current
    val language = LocalAppLanguage.current
    val reduceMotion = LocalReduceMotion.current
    ShieldOnChange(model.copied) { _, copied -> if (copied) view.shieldHaptic(ShieldHaptic.SUCCESS) }
    // iOS: on the row, so "Share" glides aside as the pill widens instead of jumping. Here the pill's own width
    // eases (its capsule must not jump), which moves the row with it.
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .heightIn(min = 34.dp)
                .background(HomeTheme.action, CapsuleShape)
                .clip(CapsuleShape)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    role = Role.Button,
                ) { shareInvite(context, FamilyCodeModel.inviteText(code, language)) }
                .padding(horizontal = 17.dp, vertical = 5.dp)
                .testTag("family.invite"),
            contentAlignment = Alignment.Center,
        ) {
            Text(text = t("Share"), style = onboardingFont(17f, rounded = true, lineHeight = 23.8f), color = Color.White)
        }
        Box(
            Modifier
                .animateContentSize(if (reduceMotion) shooEaseInOut<IntSize>(0.2) else shooSnappy<IntSize>(0.3))
                .heightIn(min = 34.dp)
                .background(HomeTheme.quietFill, CapsuleShape)
                .clip(CapsuleShape)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    role = Role.Button,
                ) {
                    if (model.copyInvite(language)) view.shieldAnnounce(L10n.string("Invite link copied", language))
                }
                .padding(horizontal = 16.5.dp, vertical = 5.dp)
                .testTag("familyCode.copy"),
            contentAlignment = Alignment.Center,
        ) {
            // Copy → Copied cross-fades while the pill eases to its new width (pattern: InviteSheet).
            Crossfade(
                targetState = model.copied,
                animationSpec = if (reduceMotion) shooEaseInOut<Float>(0.2) else shooSnappy<Float>(0.3),
                label = "inviteCopied",
            ) { copied ->
                Text(
                    text = t(if (copied) "Copied" else "Copy"),
                    style = onboardingFont(17f, rounded = true, lineHeight = 23.8f),
                    color = HomeTheme.bodyInk,
                )
            }
        }
    }
}

/** iOS `ShareLink(item:)`: the system share sheet with the invite text. */
private fun shareInvite(context: Context, text: String) {
    val send = Intent(Intent.ACTION_SEND)
        .setType("text/plain")
        .putExtra(Intent.EXTRA_TEXT, text)
    try {
        context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (error: Exception) {
        Log.ui.error("Sharing the invite failed", error)
    }
}

/** Figma "Cara Kerja" (1382:10511): the title, 14 pt, then three numbered steps in one card. */
@Composable
private fun HowItWorks() {
    val steps = listOf(
        "Share the code or QR with your family",
        "They install Shoo and enter the code",
        "You hear about it when they open a dangerous site",
    )
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        HomeSectionTitle("How it works")
        Column(
            Modifier
                .fillMaxWidth()
                .homeCard()
                .padding(horizontal = 17.dp, vertical = 7.dp)
                .testTag("home.howItWorks"),
        ) {
            steps.forEachIndexed { index, step ->
                if (index > 0) {
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(1.dp)
                            .background(HomeTheme.stepDivider)
                            .clearAndSetSemantics { },
                    )
                }
                Row(
                    Modifier
                        .padding(vertical = 12.dp)
                        .semantics(mergeDescendants = true) { },
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // Figma "Nomor": 28 pt #EEF4FB circle, SF Pro Rounded Semibold 13 #186FB9.
                    Box(
                        Modifier
                            .size(28.dp)
                            .background(HomeTheme.actionFill, CircleShape)
                            .clearAndSetSemantics { },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = "${index + 1}",
                            style = onboardingFont(13f, FontWeight.SemiBold, rounded = true, tracking = -0.08f),
                            color = HomeTheme.action,
                        )
                    }
                    // Figma: SF Pro Rounded 17, 140 % lines, #191D2F.
                    Text(
                        text = t(step),
                        style = onboardingFont(17f, rounded = true, lineHeight = 23.8f),
                        color = HomeTheme.navy,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}
