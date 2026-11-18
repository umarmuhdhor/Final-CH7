package com.shoo.app.features.shield

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.shoo.app.app.AppTab
import com.shoo.app.app.LocalAppEnvironment
import com.shoo.app.components.AvatarView
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.components.LocalReduceGlass
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.ShooEasing
import com.shoo.app.components.SiteIcon
import com.shoo.app.components.SkeletonActivity
import com.shoo.app.components.StateMotion
import com.shoo.app.components.StateNoticeCard
import com.shoo.app.components.hex
import com.shoo.app.components.loaderReplacementFade
import com.shoo.app.components.shooEaseInOut
import com.shoo.app.components.shooEaseOut
import com.shoo.app.components.shooSmooth
import com.shoo.app.components.stateEntrance
import com.shoo.app.data.ExtensionStatus
import com.shoo.app.data.GuardianInfo
import com.shoo.app.data.ScanResult
import com.shoo.app.data.ScanStatus
import com.shoo.app.data.ShooRepository
import com.shoo.app.data.Verdict
import com.shoo.app.features.activity.RefreshFailedNotice
import com.shoo.app.features.onboarding.onboardingFont
import com.shoo.app.support.AppLanguage
import com.shoo.app.support.Formatters
import com.shoo.app.support.L10n
import com.shoo.app.support.t
import kotlinx.coroutines.launch

/**
 * Protected Home (PR-04, Figma "protected/Home"): the blue hero with "Terhubung dengan …" under the headline, then on
 * the page the newest risky site of the last day with what the guardian decided, recent activity and the latest scams.
 * Frames: nothing today 1115:17162; blocked 1115:17294; warning 1363:12167; marked dangerous 1373:13100 / 1382:2227;
 * marked safe 1373:12376 / 1373:12752; no guardian yet 1382:2393 (the "Mode Terawasi" card instead of the pill).
 */
@Composable
fun ProtectedShieldView(
    repository: ShooRepository,
    extensionStatus: suspend () -> ExtensionStatus,
    modifier: Modifier = Modifier,
) {
    val env = LocalAppEnvironment.current
    val language = LocalAppLanguage.current
    val reduceMotion = LocalReduceMotion.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val model = remember(repository) { ShieldModel(repository = repository, extensionStatus = extensionStatus) }
    /** The hero is scrolled out from under the status bar: the top scrim takes over as its backdrop. */
    var isHeroHidden by remember { mutableStateOf(false) }

    val isLoaded = model.state == ShieldModel.State.LOADED
    /** Loaded and nobody looks after this phone: no pill, the "Mode Terawasi" card (1382:2393). */
    val hasNoGuardian = isLoaded && model.guardian == null
    val showsSupervisedCard = hasNoGuardian && !env.settings.supervisedCardDismissed

    Box(modifier) {
        ShieldHomeFrame(
            isHeroHidden = isHeroHidden,
            onRefresh = { model.refresh() },
            // Figma "Top Bar" 1115:17282: the profile circle only, right under the status bar.
            topBar = {
                HomeTopBar(
                    avatarId = model.profileAvatarId ?: env.session?.avatarId,
                    onSwitch = null,
                    onProfile = { env.router.openProfile() },
                )
            },
        ) {
            ProtectedHero(
                model = model,
                hasNoGuardian = hasNoGuardian,
                onTurnOn = { env.router.isTurnOnPresented = true },
                modifier = Modifier.onShieldHeroHidden { isHeroHidden = it },
            )
            // Figma "Status": the page itself rounds up over the hero; one 354 pt column, 24 from the edges.
            Column(
                Modifier
                    .fillMaxWidth()
                    .background(HomeTheme.background, RoundedCornerShape(22.dp))
                    .padding(horizontal = 24.dp)
                    .padding(bottom = 32.dp),
            ) {
                when (model.state) {
                    ShieldModel.State.LOADING -> {
                        // The rows that are coming, sweeping while they load.
                        val loading = t("Loading")
                        SkeletonActivity(
                            rows = 4,
                            animating = true,
                            modifier = Modifier
                                .padding(top = 32.dp)
                                .clearAndSetSemantics { contentDescription = loading },
                        )
                    }
                    ShieldModel.State.FAILED -> {
                        // Figma "protected/Home · Gagal memuat" (1665:3122): the card 28 under the sheet's top,
                        // "Aktivitas Terakhir" 22 under it, then four grey rows.
                        Column(Modifier.padding(top = 28.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
                            StateNoticeCard(
                                title = "Couldn't load",
                                message = t(model.loadFailure.message(connection = "Check your connection.")),
                                actionTitle = "Try again",
                                action = { model.retry() },
                                modifier = Modifier
                                    .testTag("shield.loadError")
                                    .stateEntrance(),
                            )
                            SkeletonActivity(rows = 4)
                        }
                    }
                    ShieldModel.State.LOADED -> ProtectedLoaded(
                        model = model,
                        showsSupervisedCard = showsSupervisedCard,
                        language = language,
                        modifier = Modifier.loaderReplacementFade(),
                    )
                }
            }
        }
    }

    // MARK: Effects

    ShieldOnChange(model.refreshFailed) { _, failed ->
        if (failed) view.shieldAnnounce(L10n.string("Couldn't refresh. Pull down to try again.", language))
    }
    // Coming back from Firefox can flip Off → Active: say it (not on the first load). Only off → on taps.
    ShieldOnChange(model.extensionStatus.isActive) { _, isActive ->
        if (model.state != ShieldModel.State.LOADED) return@ShieldOnChange
        if (isActive) view.shieldHaptic(ShieldHaptic.SUCCESS)
        view.shieldAnnounce(L10n.string(if (isActive) "You're protected!" else "You're not protected yet", language))
    }
    // A push while this screen is open (new scan, verdict, member change): reload, as Guardian Home does (A-12).
    ShieldOnChange(env.pushesWhileOpen) { _, count ->
        scope.launch { model.pushesWhileOpenChanged(count) }
    }
    // Back from Connect (PR-01): show the new guardian.
    ShieldOnChange(env.router.isConnectPresented) { _, isPresented ->
        if (!isPresented) scope.launch { model.refresh() }
    }
    // Status comes from the add-on link and Firefox: re-read whenever the app is back in front.
    val sceneActive = rememberShieldSceneActive()
    LaunchedEffect(sceneActive) {
        if (sceneActive) model.refresh()
    }
    ShieldTurnOnSheet(onDismissed = { scope.launch { model.refresh() } })
    // A failed load is felt too, not only read; a failed page that loads after "Try again" taps once.
    ShieldOnChange(model.state) { old, now ->
        if (now == ShieldModel.State.FAILED) view.shieldHaptic(ShieldHaptic.ERROR)
        if (old == ShieldModel.State.FAILED && now == ShieldModel.State.LOADED) view.shieldHaptic(ShieldHaptic.SUCCESS)
    }
}

// MARK: Hero

/** What the hero says: still reading the extension, the page failed, or the status itself. */
private enum class HeroPhase { CHECKING, FAILED, STATUS }

/** Everything the hero's accessory shows, so a change cross-fades (iOS `.animation(value: heroPhase)`). */
private data class HeroAccessory(
    val phase: HeroPhase,
    val showsNextStep: Boolean,
    val showsPill: Boolean,
    val isActive: Boolean,
    val guardianName: String?,
)

@Composable
private fun ProtectedHero(
    model: ShieldModel,
    hasNoGuardian: Boolean,
    onTurnOn: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val reduceMotion = LocalReduceMotion.current
    val isLoaded = model.state == ShieldModel.State.LOADED
    val isActive = model.extensionStatus.isActive
    val phase = when {
        !model.extensionChecked -> HeroPhase.CHECKING
        model.state == ShieldModel.State.FAILED -> HeroPhase.FAILED
        else -> HeroPhase.STATUS
    }
    val showsPill = (isLoaded && model.guardian != null) || phase != HeroPhase.STATUS
    // Figma "box": 349…469 with nothing today, 362…482 over the card; 1382:2393 (no pill) moves the gradient
    // up to y −31 and stretches the fade to 141 pt from 317.
    val layout = if (hasNoGuardian) {
        HomeHeroLayout.personal.copy(backdrop = HeroBackdrop(boxTop = 317.08f, imageTop = -31f, boxHeight = 141f))
    } else {
        HomeHeroLayout.personal.copy(backdrop = HeroBackdrop(boxTop = if (model.cardScan == null) 349f else 362f))
    }
    // The sheet starts at 403 under the pill (24.4 below it) and at 379 without one.
    val bottom: Dp = if (showsPill) 24.38.dp else (379f - layout.titleBottom).dp
    val showsNextStep = phase == HeroPhase.STATUS && model.extensionStatus.nextStep != null
    val title = when (phase) {
        HeroPhase.CHECKING -> "Checking Shoo…"
        HeroPhase.FAILED -> "Status not available yet"
        HeroPhase.STATUS -> if (isActive) "You're protected!" else "You're not protected yet"
    }
    val identifier = when (phase) {
        HeroPhase.CHECKING -> "shield.status.checking"
        HeroPhase.FAILED -> "shield.status.unavailable"
        HeroPhase.STATUS -> if (isActive) "shield.status.active" else "shield.status.off"
    }
    val accessory = HeroAccessory(phase, showsNextStep, showsPill, isActive, model.guardian?.name)

    HomeHero(
        style = HomeHeroStyle.BLUE,
        title = title,
        titleIdentifier = identifier,
        shieldOn = isActive || phase == HeroPhase.CHECKING,
        layout = layout,
        bottomPadding = if (showsNextStep) 20.dp else bottom,
        modifier = modifier,
    ) {
        // "Checking Shoo…" → protected / not protected, and "Status not available yet" ↔ loaded: the pill cross-fades.
        Crossfade(
            targetState = accessory,
            animationSpec = if (reduceMotion) shooEaseInOut<Float>(0.2) else shooSmooth<Float>(0.35),
            label = "protectedHeroAccessory",
        ) { shown ->
            Column(
                Modifier.padding(top = if (shown.showsNextStep) 4.dp else if (shown.showsPill) 13.dp else 0.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                when (shown.phase) {
                    // Figma 1681:5275: a blue dot that breathes while the add-on's state is read.
                    HeroPhase.CHECKING -> HeroStatusPill(
                        text = t("Checking the Firefox add-on"),
                        dot = hex(0x1A73D9),
                        pulses = true,
                        modifier = Modifier.testTag("shield.checking"),
                    )
                    // Figma 1665:3122: grey dot, nothing to report yet.
                    HeroPhase.FAILED -> HeroStatusPill(
                        text = t("Connection not read yet"),
                        dot = HomeTheme.offline,
                        modifier = Modifier.testTag("shield.unavailable"),
                    )
                    HeroPhase.STATUS -> {
                        if (shown.showsNextStep) {
                            HeroTurnOnLink(title = if (shown.isActive) "Finish setup" else "Turn on now", identifier = "shield.turnOn", onClick = onTurnOn)
                        }
                        val name = shown.guardianName
                        if (shown.showsPill && name != null) ConnectedPill(name)
                    }
                }
            }
        }
    }
}

/** "Turn on now" / "Finish setup" under the headline: white, underlined, 44 pt tall. Shared with Pribadi's hero. */
@Composable
internal fun HeroTurnOnLink(title: String, identifier: String, onClick: () -> Unit) {
    val hint = t("Shows how to switch Shoo on in Firefox")
    Box(
        Modifier
            .heightIn(min = 44.dp)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                role = Role.Button,
                onClickLabel = hint,
                onClick = onClick,
            )
            .testTag(identifier),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = t(title),
            style = onboardingFont(15f, FontWeight.Medium).copy(textDecoration = TextDecoration.Underline),
            color = Color.White,
        )
    }
}

// MARK: The page

/**
 * Figma's gaps per frame: the card 24 under the sheet's top; then 38 to "Aktivitas Terakhir" and 32 to the scams
 * (1115:17294). Nothing today: the list 32 under the top, the scams 58 under it (1115:17162). No guardian: the
 * "Mode Terawasi" card 29 under the site card, the list 16 under it, the scams 29 (1382:2393); without a site
 * card it sits 31 under the top with 37 to the list and the scams, as on Pribadi (1382:10567).
 */
@Composable
private fun ProtectedLoaded(
    model: ShieldModel,
    showsSupervisedCard: Boolean,
    language: AppLanguage,
    modifier: Modifier = Modifier,
) {
    val env = LocalAppEnvironment.current
    val reduceMotion = LocalReduceMotion.current
    val card = model.cardScan
    val cta = showsSupervisedCard
    val (top, list, scams) = when {
        card != null && cta -> Triple(24, 16, 29)
        card != null -> Triple(24, 38, 32)
        cta -> Triple(31, 37, 37)
        else -> Triple(32, 0, 58)
    }
    Column(modifier.fillMaxWidth()) {
        Spacer(Modifier.height(top.dp))
        // A-01 (fase 28b K4, D-alief-A12): what is shown stays, the pill included, and this says it may be old.
        // The same notice as Activity's and Guardian Home's. Only the notice animates.
        AnimatedVisibility(
            visible = model.refreshFailed,
            enter = StateMotion.enterTransition(reduceMotion, fromBottom = false),
            exit = StateMotion.exitTransition(reduceMotion, toBottom = false),
        ) {
            RefreshFailedNotice(
                retryIdentifier = "shield.refreshRetry",
                retry = { model.refresh() },
                modifier = Modifier
                    .testTag("shield.refreshFailed")
                    .padding(bottom = 24.dp),
            )
        }
        if (card != null) {
            ProtectedSiteCard(
                scan = card,
                guardian = model.guardian,
                language = language,
                onOpen = { env.router.showDetail(card.id) },
                modifier = Modifier.padding(bottom = (if (cta) 29 else list).dp),
            )
        }
        AnimatedVisibility(visible = cta, enter = fadeIn(shooEaseOut<Float>(0.2)), exit = fadeOut(shooEaseOut<Float>(0.2))) {
            SupervisedModeCard(
                onConnect = { env.router.isConnectPresented = true },
                onDismiss = { env.settings.supervisedCardDismissed = true },
                modifier = Modifier.padding(bottom = (if (card == null) list else 16).dp),
            )
        }
        RecentActivity(
            scans = model.recent,
            language = language,
            hasSitesAbove = card != null,
            onOpen = { env.router.showDetail(it.id) },
            onSeeAll = { env.router.selectedTab = AppTab.ACTIVITY },
        )
        if (model.scamCases.isNotEmpty()) {
            LatestScamsCard(cases = model.scamCases, modifier = Modifier.padding(top = scams.dp))
        }
    }
}

// MARK: - Guardian

/**
 * The glass capsule under the hero's headline (Figma "Card Perlindungan"): a dot and a line. `pulses`: the dot
 * breathes while something is being checked. `text`: already translated.
 */
@Composable
fun HeroStatusPill(text: String, dot: Color, pulses: Boolean = false, modifier: Modifier = Modifier) {
    val reduceGlass = LocalReduceGlass.current
    val reduceMotion = LocalReduceMotion.current
    val breathing = if (pulses && !reduceMotion) {
        val transition = rememberInfiniteTransition(label = "pillDot")
        val value by transition.animateFloat(
            initialValue = 0f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(tween(800, easing = ShooEasing.easeInOut), RepeatMode.Reverse),
            label = "pillDotBreath",
        )
        value
    } else {
        0f
    }
    Row(
        modifier
            .heightIn(min = 42.62.dp)
            .background(Color.White.copy(alpha = if (reduceGlass) 1f else 0.28f), CircleShape)
            .border(1.06.dp, Color.White.copy(alpha = 0.9f), RoundedCornerShape(50))
            .padding(horizontal = 16.98.dp, vertical = 8.dp)
            .semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(8.88.dp)
                .graphicsLayer {
                    alpha = 1f - 0.65f * breathing
                    val s = 1f - 0.2f * breathing
                    scaleX = s
                    scaleY = s
                }
                .background(dot, CircleShape)
                .clearAndSetSemantics { },
        )
        Text(
            text = text,
            style = onboardingFont(13f, tracking = -0.13f),
            color = HomeTheme.glassInk,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/**
 * Figma "Card Perlindungan" (1373:13094): a 42.6 pt glass capsule, white 28 % with a 1 pt white 90 % ring;
 * a green 8.9 pt dot, 4 pt, "Terhubung dengan Virellia" in SF Pro Display 13 (-1 %, #1A1A1A); 17 pt sides.
 */
@Composable
private fun ConnectedPill(name: String) {
    HeroStatusPill(text = t("Connected with %@", name), dot = HomeTheme.success, modifier = Modifier.testTag("shield.guardian"))
}

// MARK: - The site card

/** The localized `key` (one `%@`) with `name` in semibold: Swift `Text("\(Text(name).fontWeight(.semibold)) …")`. */
@Composable
internal fun boldNameText(key: String, name: String): AnnotatedString {
    val template = t(key)
    val parts = template.split("%@", limit = 2)
    return buildAnnotatedString {
        append(parts[0])
        if (parts.size > 1) {
            withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(name) }
            append(parts[1])
        }
    }
}

/**
 * Figma "Frame 1618872233" (1115:17294): #EDEDED 50 %, 20 pt corners, 354 wide. The site and when with a ↗ to the
 * details; the risk panel (red "Situs Berbahaya!" when blocked or marked dangerous, else orange "Situs
 * Mencurigakan!"); then who checks it: "Virellia akan mengecek kembali", or what they decided with a red ! or a
 * blue ✓ on their avatar. A warm or red glow at the foot; marked dangerous blushes the whole card.
 */
@Composable
private fun ProtectedSiteCard(
    scan: ScanResult,
    guardian: GuardianInfo?,
    language: AppLanguage,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val reduceMotion = LocalReduceMotion.current
    /** #493: a verdict this build can't read counts as none, so the card follows the detection status, never "safe". */
    val decision: Verdict.Value? = scan.verdict?.known?.value
    val isDanger = decision == Verdict.Value.NOT_SAFE || (decision == null && scan.status == ScanStatus.BLOCKED)
    /** Who the line under the panel names: who decided, else the guardian who will. */
    val checker: String? = scan.verdict?.byName ?: guardian?.name
    /** The checker's avatar: the guardian's, unless someone else decided (then the neutral person). */
    val checkerAvatarId: String? = when {
        guardian == null -> null
        scan.verdict != null && scan.verdict.byDeviceId != guardian.deviceId -> null
        else -> guardian.avatarId
    }
    val hint = t("Opens the details")
    val shape = RoundedCornerShape(20.dp)

    Column(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .drawBehind {
                // #EDEDED 50 % with Figma "Rectangle 9652": a red or warm glow from 63.5 pt above the foot (clear) to
                // 14.5 under it (full), at 20 %; marked dangerous, the whole card blushes instead.
                drawRect(hex(0xEDEDED, 0.5f))
                if (decision == Verdict.Value.NOT_SAFE) {
                    drawRect(blushBrush(offsetY = 0f, density = density), alpha = 0.2f)
                } else {
                    val colors = if (isDanger) listOf(hex(0xF28D83, 0f), hex(0xF26153)) else listOf(hex(0xFB9E20, 0f), hex(0xFB9E20))
                    drawRect(
                        Brush.verticalGradient(colors, startY = size.height - 63.5.dp.toPx(), endY = size.height + 14.5.dp.toPx()),
                        alpha = 0.2f,
                    )
                }
            }
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                role = Role.Button,
                onClickLabel = hint,
                onClick = onOpen,
            )
            .semantics(mergeDescendants = true) { }
            .testTag("shield.lastBlocked")
            .padding(bottom = 13.79.dp),
    ) {
        ProtectedSiteHeader(scan = scan, language = language, blushed = decision == Verdict.Value.NOT_SAFE)
        HomeRiskPanel(scan = scan, isDanger = isDanger, modifier = Modifier.padding(start = 8.dp, end = 8.dp, top = 12.dp))
        if (checker != null) {
            // The guardian's answer arrives while the card is up: badge and line ease over instead of jumping.
            Crossfade(
                targetState = decision,
                animationSpec = if (reduceMotion) shooEaseInOut<Float>(0.2) else shooSmooth<Float>(0.3),
                label = "protectedDecision",
                modifier = Modifier.padding(start = 8.dp, end = 8.dp, top = 12.dp),
            ) { shown ->
                ProtectedSiteFooter(name = checker, decision = shown, avatarId = checkerAvatarId)
            }
        }
    }
}

/**
 * Figma "Rectangle 9652" on the marked-dangerous frames (1373:13100): #F28D83 20 % at 4.6 pt to #F26153 at 173.6 pt
 * from the card's top. `offsetY`: where the drawing view starts below the card's top, in px.
 */
private fun blushBrush(offsetY: Float, density: Float): Brush = Brush.verticalGradient(
    listOf(hex(0xF28D83, 0.2f), hex(0xF26153)),
    startY = 4.6f * density - offsetY,
    endY = 173.6f * density - offsetY,
)

/**
 * Figma "Frame 1618872182": the 48 pt icon 17 / 14 in, the site (SF Pro Rounded 17, 22 pt line) and when (13,
 * 18 pt) 3 under its top; "Status Badge" 40 pt white (its #FFCDCD ring is hidden), 20 from the top and 14 from
 * the right.
 */
@Composable
private fun ProtectedSiteHeader(scan: ScanResult, language: AppLanguage, blushed: Boolean) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(start = 17.dp, end = 14.dp, top = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        SiteIcon(url = scan.faviconUrl)
        Column(
            Modifier
                .padding(top = 3.dp)
                .weight(1f),
        ) {
            // iOS: truncates in the middle; Compose only ends with the ellipsis.
            Text(
                text = scan.domain,
                style = onboardingFont(17f, rounded = true, tracking = -0.17f, lineHeight = 22f),
                color = HomeTheme.navy,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(vertical = 1.dp),
            )
            Text(
                text = Formatters.dayAndTime(scan.detectedAt, language),
                style = onboardingFont(13f, rounded = true, tracking = -0.08f, lineHeight = 18f),
                color = HomeTheme.rowSubtitle,
            )
        }
        // SF Symbol arrow.up.right semibold 14.58, #1A1A1A, on a white 40 pt circle; the blush (20 pt down the card).
        Box(
            Modifier
                .padding(top = 6.dp)
                .size(40.dp)
                .clip(CircleShape)
                .background(Color.White)
                .clearAndSetSemantics { },
            contentAlignment = Alignment.Center,
        ) {
            SfSymbol("arrow.up.right", pointSize = 14.58f, tint = HomeTheme.glassInk)
            if (blushed) {
                Box(
                    Modifier
                        .matchParentSize()
                        .drawBehind { drawRect(blushBrush(offsetY = 20.dp.toPx(), density = density), alpha = 0.2f) },
                )
            }
        }
    }
}

/**
 * Figma "Frame 1618872238": white 70 %, 20.9 pt corners, 16 / 17 padding; the 29.2 pt avatar, 6.3 pt, then
 * the line in SF Pro Display 17 (#3A3D42), the name semibold.
 */
@Composable
private fun ProtectedSiteFooter(name: String, decision: Verdict.Value?, avatarId: String?) {
    val line = when (decision) {
        // `UNKNOWN` never gets here (`decision` maps it to null); listed for the exhaustive when.
        null, Verdict.Value.UNKNOWN -> boldNameText("%@ will check it again", name)
        Verdict.Value.NOT_SAFE -> boldNameText("%@ marked it dangerous", name)
        Verdict.Value.SAFE -> boldNameText("%@ marked it safe", name)
    }
    Row(
        Modifier
            .fillMaxWidth()
            .background(Color.White.copy(alpha = 0.7f), RoundedCornerShape(20.86.dp))
            .padding(horizontal = 17.dp, vertical = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(6.26.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CheckerAvatar(decision = decision, avatarId = avatarId)
        Text(
            text = line,
            style = onboardingFont(17f),
            color = HomeTheme.bodyInk,
            modifier = Modifier.weight(1f),
        )
    }
}

/**
 * Figma "Avatar/S" with "Group 36523": a red ! (11.6 pt, #E5483B) or a blue ✓ (11 pt, #2E90FA) with a white ring,
 * 18.3 / 19 from the avatar's corner.
 */
@Composable
private fun CheckerAvatar(decision: Verdict.Value?, avatarId: String?) {
    val notSafe = decision == Verdict.Value.NOT_SAFE
    Box(
        Modifier.padding(
            end = if (decision == null) 0.dp else 0.65.dp,
            bottom = if (decision == null) 0.dp else if (notSafe) 1.34.dp else 0.79.dp,
        ),
    ) {
        AvatarView(id = avatarId ?: "", size = 29.21.dp)
        if (decision != null) {
            val badge = if (notSafe) 11.55.dp else 11.dp
            Box(
                Modifier
                    .offset(x = 18.31.dp - 0.96.dp, y = 19.dp - 0.96.dp)
                    .size(badge + 1.92.dp)
                    .background(Color.White, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    Modifier
                        .size(badge)
                        .background(hex(if (notSafe) 0xE5483B else 0x2E90FA), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    SfSymbol(
                        if (notSafe) "exclamationmark" else "checkmark",
                        pointSize = if (notSafe) 5.43f else 5.17f,
                        tint = Color.White,
                    )
                }
            }
        }
    }
}
