package com.shoo.app.features.main

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import androidx.compose.ui.zIndex
import com.shoo.app.app.AppEnvironment
import com.shoo.app.app.AppTab
import com.shoo.app.app.InviteNotice
import com.shoo.app.app.LaunchSplashPhase
import com.shoo.app.app.LocalAppEnvironment
import com.shoo.app.app.Route
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.LocalIsDarkTheme
import com.shoo.app.components.LocalReduceGlass
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.dynamicColor
import com.shoo.app.components.figmaTextStyle
import com.shoo.app.components.FigmaFont
import com.shoo.app.components.hex
import com.shoo.app.components.sfSymbol
import com.shoo.app.components.shooEaseInOut
import com.shoo.app.components.shooShadow
import com.shoo.app.components.shooSmooth
import com.shoo.app.components.shooSpring
import com.shoo.app.data.ScanOwnerFilter
import com.shoo.app.data.ShooRepository
import com.shoo.app.data.UserMode
import com.shoo.app.features.activity.ActivityView
import com.shoo.app.features.detail.DetailView
import com.shoo.app.features.onboarding.GuardianIntroView
import com.shoo.app.features.onboarding.LocalPresentedInSheet
import com.shoo.app.features.pairing.ConnectModel
import com.shoo.app.features.pairing.ConnectView
import com.shoo.app.features.pairing.InviteNoticeBanner
import com.shoo.app.features.profile.JoinAnotherFamilySheet
import com.shoo.app.features.profile.MemberDetailView
import com.shoo.app.features.profile.ProfilePageView
import com.shoo.app.features.profile.ProfileView
import com.shoo.app.features.shield.GuardianShieldView
import com.shoo.app.features.shield.ProtectedShieldView
import com.shoo.app.support.t
import kotlinx.coroutines.launch

/**
 * Android only: how much of the bottom the floating tab bar covers on the two tab roots (0 on pushed screens, where it
 * is hidden). iOS adds the tab bar to the safe area; a root that scrolls to the bottom pads its last row by this.
 */
val LocalTabBarInset = compositionLocalOf { 0.dp }

/** iOS 26 tab bar: a 62 pt glass capsule, 21 pt in from the sides. */
private val TabBarHeight = 60.dp
private val TabBarWidth = 190.dp
private val TabBarSide = 21.dp

/** Large sheets on iOS 26 round their top corners to about the screen's. */
private val SheetCorner = 32.dp

/**
 * Shield / Activity tabs with the profile button top right (PRD §7). Each tab keeps its own back stack
 * (`Router.shieldPath`, `activityPath`, iOS `NavigationStack(path:)`); pushed screens slide in over the root and hide
 * the tab bar. The sheets and covers of the tabs live here too: Connect (PR-01), "Become supervised" (join another
 * family), Figma "To be guardian", the invite banner (PR-03) and the demo banner.
 */
@Composable
fun MainTabView(modifier: Modifier = Modifier) {
    val env = LocalAppEnvironment.current
    val router = env.router
    val settings = env.settings
    val reduceMotion = LocalReduceMotion.current

    // PR-03: an invite link opened before or during onboarding opens its join sheet now the tabs are here.
    LaunchedEffect(Unit) { env.presentInviteAfterOnboarding() }
    // iOS: the edge swipe / Back button of a pushed screen.
    BackHandler(enabled = router.currentPath.isNotEmpty() && !router.isGuardianIntroPresented) { router.pop() }

    // A new repository (mode switch), a new device session, or the Family toggle starts fresh screen models.
    // Protected screens ignore the toggle, so it never resets them.
    val screenIdentity = mainTabIdentity(
        repository = env.repository,
        familyMode = settings.mode == UserMode.GUARDIAN && settings.familyModeOn,
        deviceId = env.session?.deviceId,
    )
    // Activity reloads on its next appearance when this changes (K8): a saved verdict, or a member disconnected.
    val verdictSaves: () -> Int = remember(env) { { env.verdictSaves + env.familyChanges } }

    // iOS TabView builds a tab the first time it is selected and keeps it.
    var visited by remember { mutableStateOf(setOf(router.selectedTab)) }
    if (router.selectedTab !in visited) visited = visited + router.selectedTab

    val tabBarShown = router.currentPath.isEmpty()

    Box(modifier = modifier.fillMaxSize()) {
        for (tab in AppTab.entries) {
            if (tab !in visited) continue
            val selected = tab == router.selectedTab
            key(tab) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .zIndex(if (selected) 1f else 0f)
                        .graphicsLayer { alpha = if (selected) 1f else 0f }
                        .then(if (selected) Modifier else Modifier.clearAndSetSemantics { }),
                ) {
                    when (tab) {
                        AppTab.SHIELD -> RouteStack(
                            path = router.shieldPath,
                            root = { key(screenIdentity) { ShieldRoot(env) } },
                            destination = { Destination(it, env, verdictSaves) },
                        )
                        AppTab.ACTIVITY -> RouteStack(
                            path = router.activityPath,
                            root = { key(screenIdentity) { ActivityRoot(env, verdictSaves) } },
                            destination = { Destination(it, env, verdictSaves) },
                        )
                    }
                }
            }
        }

        // Figma tab bar: "Shield" bolt-shield and "Activity" list circle. Pushed screens hide it.
        AnimatedVisibility(
            visible = tabBarShown,
            modifier = Modifier.align(Alignment.BottomCenter).zIndex(2f),
            enter = if (reduceMotion) fadeIn(shooEaseInOut(0.2)) else fadeIn(shooSmooth(0.35)) + slideInVertically(shooSmooth(0.35)) { it / 2 },
            exit = if (reduceMotion) fadeOut(shooEaseInOut(0.2)) else fadeOut(shooSmooth(0.25)) + slideOutVertically(shooSmooth(0.25)) { it / 2 },
        ) {
            ShooTabBar(selected = router.selectedTab, onSelect = { router.selectedTab = it })
        }

        // Sample data must never pass for a real family: on both tabs, between the top bar's two buttons.
        if (settings.demoMode && router.shieldPath.isEmpty() && router.activityPath.isEmpty()) {
            DemoBanner(onExit = env::leaveDemo, modifier = Modifier.align(Alignment.TopCenter).zIndex(3f))
        }

        // PR-03: an invite link opened after onboarding. Waits for the launch splash, like Connect below.
        val notice = router.inviteNotice
        var shownNotice by remember { mutableStateOf<InviteNotice?>(null) }
        if (notice != null && notice != shownNotice) shownNotice = notice
        AnimatedVisibility(
            visible = notice != null && env.launchSplash == LaunchSplashPhase.DONE,
            modifier = Modifier.align(Alignment.TopCenter).zIndex(4f),
            enter = if (reduceMotion) fadeIn(shooEaseInOut(0.2)) else slideInVertically(shooSmooth()) { -it } + fadeIn(shooSmooth()),
            exit = if (reduceMotion) fadeOut(shooEaseInOut(0.2)) else slideOutVertically(shooSmooth()) { -it } + fadeOut(shooSmooth()),
        ) {
            shownNotice?.let { InviteNoticeBanner(notice = it, router = router, modifier = Modifier.statusBarsPadding().padding(top = 8.dp)) }
        }

        // Figma "To be guardian" (1229:1904), iOS `.fullScreenCover`: slides up over everything.
        AnimatedVisibility(
            visible = router.isGuardianIntroPresented,
            modifier = Modifier.zIndex(5f),
            enter = if (reduceMotion) fadeIn(shooEaseInOut(0.2)) else slideInVertically(shooSmooth()) { it },
            exit = if (reduceMotion) fadeOut(shooEaseInOut(0.2)) else slideOutVertically(shooSmooth()) { it },
        ) {
            BackHandler { router.isGuardianIntroPresented = false }
            GuardianIntroView(
                onBack = { router.isGuardianIntroPresented = false },
                onStart = env::startGuardian,
                modifier = Modifier.blockTouchesBelow(),
            )
        }
    }

    // An invite link that started the app (PR-03): Connect comes up once the launch splash (ON-01) is gone.
    var connectModel by remember { mutableStateOf<ConnectModel?>(null) }
    ShooSheet(
        isPresented = router.isConnectPresented && env.launchSplash == LaunchSplashPhase.DONE,
        onDismissed = {
            router.isConnectPresented = false
            connectModel = null
        },
        dismissDisabled = connectModel?.state == ConnectModel.State.Joining,
    ) { dismiss ->
        ConnectSheet(dismiss = dismiss, onModel = { connectModel = it })
    }

    // Pribadi "Mode Terawasi" → Hubungkan (Figma 1253:8630). The sheet closes itself through the router.
    // While the join runs the sheet can't be swiped away (iOS `interactiveDismissDisabled`).
    var joinLocked by remember { mutableStateOf(false) }
    ShooSheet(
        isPresented = router.isJoinFamilyPresented,
        onDismissed = { router.isJoinFamilyPresented = false },
        dismissDisabled = joinLocked,
    ) {
        JoinAnotherFamilySheet(name = "", onInteractiveDismissDisabledChange = { joinLocked = it })
    }
}

/** iOS `MainTabView.identity(repository:familyMode:deviceId:)`. */
internal fun mainTabIdentity(repository: ShooRepository, familyMode: Boolean, deviceId: String?): String =
    "${System.identityHashCode(repository)}-$familyMode-${deviceId ?: "-"}"

/** Every Home draws its own top bar over the hero (Figma HOME: ⇆ and the profile avatar). */
@Composable
private fun ShieldRoot(env: AppEnvironment) {
    val inset = TabBarHeight + tabBarBottomGap()
    CompositionLocalProvider(LocalTabBarInset provides inset) {
        if (env.settings.mode == UserMode.PROTECTED) {
            ProtectedShieldView(repository = env.repository, extensionStatus = env.extensionStatus)
        } else {
            GuardianShieldView()
        }
    }
}

/**
 * Own scans (PR-05, guardian with Family mode off); Family mode → the members' scans, owner shown (GD-05).
 * iOS: the Activity root's toolbar (Family toggle, profile button) is hidden by ActivityView, which draws its own.
 */
@Composable
private fun ActivityRoot(env: AppEnvironment, verdictSaves: () -> Int) {
    val inset = TabBarHeight + tabBarBottomGap()
    CompositionLocalProvider(LocalTabBarInset provides inset) {
        if (env.settings.mode == UserMode.GUARDIAN && env.settings.familyModeOn) {
            ActivityView(
                repository = env.repository,
                owner = ScanOwnerFilter.Family,
                ownDeviceId = env.session?.deviceId,
                verdictSaves = verdictSaves,
            )
        } else {
            ActivityView(repository = env.repository, owner = ScanOwnerFilter.Me, verdictSaves = verdictSaves)
        }
    }
}

/** iOS `.navigationDestination(for: Route.self)`. */
@Composable
private fun Destination(route: Route, env: AppEnvironment, verdictSaves: () -> Int) {
    when (route) {
        is Route.Detail -> key(route.scanId) {
            DetailView(scanId = route.scanId, repository = env.repository, onVerdictSaved = { env.verdictSaves += 1 })
        }
        Route.Profile -> ProfileView(repository = env.repository, settings = env.settings, notifications = env.notifications)
        is Route.ProfilePage -> ProfilePageView(page = route.page)
        is Route.Member -> key(route.deviceId) {
            MemberDetailView(deviceId = route.deviceId, repository = env.repository)
        }
        is Route.MemberActivity -> key(route.deviceId) {
            ActivityView(
                repository = env.repository,
                owner = ScanOwnerFilter.Device(route.deviceId),
                verdictSaves = verdictSaves,
                onBack = { env.router.pop() },
            )
        }
    }
}

// MARK: Navigation stack

/** One screen of a tab's stack: `route` null is the root. */
private class StackItem(val key: String, val route: Route?, val leaving: Boolean)

/**
 * iOS `NavigationStack(path:)`: the root and every pushed screen stay composed (their state lives on, like UIKit's
 * stack); only the top one is drawn and reachable. A push slides in from the trailing edge over the screen under it,
 * which moves a third of the way back; a pop slides out the other way. Reduce Motion: a cross-fade.
 */
@Composable
private fun RouteStack(path: List<Route>, root: @Composable () -> Unit, destination: @Composable (Route) -> Unit) {
    val holder = rememberSaveableStateHolder()
    val entries = path.mapIndexed { index, route -> "$index:$route" to route }
    var shownEntries by remember { mutableStateOf(entries) }
    var leaving by remember { mutableStateOf(emptyList<Pair<String, Route>>()) }
    if (shownEntries != entries) {
        // Popped (or replaced) screens slide out before they go.
        val gone = shownEntries.filter { old -> entries.none { it.first == old.first } }
        leaving = (leaving + gone).filter { old -> entries.none { it.first == old.first } }.distinctBy { it.first }
        shownEntries = entries
    }
    // Screens already on the stack when it first appears (a link or a push that opened the app) don't slide in.
    val firstComposition = remember { booleanArrayOf(true) }
    val animateIn = !firstComposition[0]
    SideEffect { firstComposition[0] = false }

    val items = buildList {
        add(StackItem("root", null, leaving = false))
        entries.forEach { add(StackItem(it.first, it.second, leaving = false)) }
        leaving.forEach { add(StackItem(it.first, it.second, leaving = true)) }
    }
    val top = entries.size
    Box(Modifier.fillMaxSize()) {
        items.forEachIndexed { index, item ->
            key(item.key) {
                StackLayer(
                    // 0 = on top, 1 = right under it, more = deeper, -1 = sliding out.
                    position = if (item.leaving) -1 else top - index,
                    animateIn = animateIn && item.route != null,
                    onGone = {
                        leaving = leaving.filterNot { it.first == item.key }
                        holder.removeState(item.key)
                    },
                ) {
                    holder.SaveableStateProvider(item.key) {
                        val route = item.route
                        if (route == null) root() else destination(route)
                    }
                }
            }
        }
    }
}

@Composable
private fun StackLayer(position: Int, animateIn: Boolean, onGone: () -> Unit, content: @Composable () -> Unit) {
    val reduceMotion = LocalReduceMotion.current
    val currentOnGone by rememberUpdatedState(onGone)
    // Fraction of the width the layer is moved by.
    val target = when {
        position < 0 -> 1f
        position == 0 -> 0f
        else -> -0.3f
    }
    val slide = remember { Animatable(if (animateIn && !reduceMotion) 1f else target) }
    val fade = remember { Animatable(if (animateIn && reduceMotion) 0f else 1f) }
    // The position the layer last came to rest at (null while it slides in).
    var settledAt by remember { mutableStateOf<Int?>(if (animateIn) null else position) }
    LaunchedEffect(position, reduceMotion) {
        if (reduceMotion) {
            slide.snapTo(if (position < 0) 0f else target.coerceAtLeast(0f))
            fade.animateTo(if (position < 0) 0f else 1f, shooEaseInOut(0.2))
        } else {
            fade.snapTo(1f)
            slide.animateTo(target, shooSpring(0.45))
        }
        settledAt = position
        if (position < 0) currentOnGone()
    }
    // Under the top screen and still: not drawn, not read out. iOS keeps it in the stack the same way.
    val covered = position >= 1 && settledAt == position
    Box(
        modifier = Modifier
            .fillMaxSize()
            .graphicsLayer {
                translationX = slide.value * size.width
                alpha = if (covered) 0f else fade.value
            }
            .then(if (position == 0) Modifier else Modifier.clearAndSetSemantics { })
            .blockTouchesBelow(),
    ) {
        content()
    }
}

/** Takes every touch over its bounds, so the screen under it never gets a tap through an empty spot. */
private fun Modifier.blockTouchesBelow(): Modifier = pointerInput(Unit) {
    awaitPointerEventScope {
        while (true) awaitPointerEvent()
    }
}

// MARK: Tab bar

/** The gap under the floating tab bar: iOS keeps it 21 pt over the screen bottom (inside the home indicator's
 * area); with Android's 3-button bar it sits just above the buttons. */
@Composable
private fun tabBarBottomGap(): Dp {
    val navBottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    return if (navBottom > 34.dp) navBottom + 8.dp else max(21.dp, navBottom)
}

/**
 * iOS 26 `TabView` tab bar (Liquid Glass): a floating capsule with the two tabs; the selected one is tinted the
 * system blue on a soft pill that slides between them. "Kurangi efek kaca": solid instead of glass.
 * iOS: the glass refracts what lies behind it; Android draws a frosted fill.
 */
@Composable
private fun ShooTabBar(selected: AppTab, onSelect: (AppTab) -> Unit, modifier: Modifier = Modifier) {
    val dark = LocalIsDarkTheme.current
    val reduceGlass = LocalReduceGlass.current
    val reduceMotion = LocalReduceMotion.current
    val fill = when {
        reduceGlass -> if (dark) hex(0x1C1C1E) else Color.White
        dark -> hex(0x1C1C1E, 0.86f)
        else -> Color.White.copy(alpha = 0.86f)
    }
    val stroke = if (dark) Color.White.copy(alpha = 0.12f) else Color.White.copy(alpha = 0.7f)
    val pill = if (dark) Color.White.copy(alpha = 0.14f) else Color.Black.copy(alpha = 0.06f)
    val tabs = listOf(
        TabItem(AppTab.SHIELD, "Shield", "bolt.shield.fill"),
        TabItem(AppTab.ACTIVITY, "Activity", "list.bullet.circle.fill"),
    )
    // iOS 26 sizes the floating bar to its two tabs (≈ 189 × 60 pt on the 402 pt iPhone), centred; it does not
    // span the screen.
    Box(modifier.fillMaxWidth().padding(bottom = tabBarBottomGap()), contentAlignment = Alignment.Center) {
    BoxWithConstraints(
        modifier = Modifier
            .width(TabBarWidth)
            .height(TabBarHeight)
            .shooShadow(Color.Black.copy(alpha = if (dark) 0.4f else 0.12f), radius = 16.dp, y = 6.dp, shape = CapsuleShape)
            .background(fill, CapsuleShape)
            .border(0.5.dp, stroke, CapsuleShape)
            .padding(4.dp),
    ) {
        val itemWidth = maxWidth / tabs.size
        val index = tabs.indexOfFirst { it.tab == selected }.coerceAtLeast(0)
        val pillOffset by animateDpAsState(
            targetValue = itemWidth * index,
            animationSpec = if (reduceMotion) shooEaseInOut<Dp>(0.2) else shooSpring<Dp>(0.35, 0.2),
            label = "tabPill",
        )
        Box(
            Modifier
                .offset(x = pillOffset)
                .width(itemWidth)
                .fillMaxHeight()
                .background(pill, CapsuleShape),
        )
        Row(Modifier.fillMaxSize().selectableGroup()) {
            for (item in tabs) {
                val isSelected = item.tab == selected
                val tint = if (isSelected) dynamicColor(0x007AFF, 0x0A84FF) else dynamicColor(0x000000, 0xFFFFFF)
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .selectable(
                            selected = isSelected,
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            role = Role.Tab,
                            onClick = { onSelect(item.tab) },
                        )
                        .semantics { testTag = "tab.${item.tab.rawValue}" },
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Icon(sfSymbol(item.symbol), contentDescription = null, tint = tint, modifier = Modifier.size(24.dp))
                    Text(
                        t(item.title),
                        style = figmaTextStyle(10f, FontWeight.SemiBold, family = FigmaFont.Family.SF_PRO).copy(color = tint),
                        maxLines = 1,
                    )
                }
            }
        }
    }
    }
}

/** `title`: catalog key. */
private class TabItem(val tab: AppTab, val title: String, val symbol: String)

// MARK: Banners

/**
 * Sample data must never pass for a real family: on both tabs, between the top bar's two buttons. Pushed screens keep
 * their own top bar free. iOS `.regularMaterial` capsule; footnote text that shrinks to 70 % before it would wrap.
 */
@Composable
private fun DemoBanner(onExit: () -> Unit, modifier: Modifier = Modifier) {
    val dark = LocalIsDarkTheme.current
    val reduceGlass = LocalReduceGlass.current
    val material = when {
        reduceGlass -> if (dark) hex(0x1C1C1E) else Color.White
        dark -> hex(0x2C2C2E, 0.9f)
        else -> hex(0xF2F2F7, 0.92f)
    }
    val label = dynamicColor(0x000000, 0xFFFFFF)
    val tint = dynamicColor(0x007AFF, 0x0A84FF)
    var scale by remember { mutableFloatStateOf(1f) }
    val base = figmaTextStyle(13f, family = FigmaFont.Family.SF_PRO)
    val shrink: (TextLayoutResult) -> Unit = { layout ->
        if (layout.hasVisualOverflow && scale > 0.7f) scale = (scale - 0.05f).coerceAtLeast(0.7f)
    }
    Row(
        modifier = modifier
            .statusBarsPadding()
            .padding(top = 8.dp)
            // Stays clear of the title and the buttons on every phone width.
            .padding(horizontal = 120.dp)
            .background(material, CapsuleShape)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            t("Demo: sample data"),
            style = base.copy(color = label, fontSize = base.fontSize * scale),
            maxLines = 1,
            softWrap = false,
            overflow = TextOverflow.Clip,
            onTextLayout = shrink,
            modifier = Modifier.weight(1f, fill = false),
        )
        Text(
            t("Exit demo"),
            style = base.copy(color = tint, fontWeight = FontWeight.SemiBold, fontSize = base.fontSize * scale),
            maxLines = 1,
            softWrap = false,
            modifier = Modifier
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    role = Role.Button,
                    onClick = onExit,
                )
                .semantics { testTag = "demo.exit" },
        )
    }
}

// MARK: Sheets

/**
 * iOS `.sheet` at the large detent: a full-height sheet just under the status bar, its top corners rounded, swiped
 * down to close (unless `dismissDisabled`, iOS `.interactiveDismissDisabled`). The content gets a `dismiss` that slides
 * it away first. `isPresented` turning false from outside (the router closing sheets) slides it away too.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ShooSheet(
    isPresented: Boolean,
    onDismissed: () -> Unit,
    dismissDisabled: Boolean = false,
    content: @Composable (dismiss: () -> Unit) -> Unit,
) {
    var shown by remember { mutableStateOf(false) }
    if (isPresented && !shown) shown = true
    if (!shown) return

    val disabled by rememberUpdatedState(dismissDisabled)
    val currentOnDismissed by rememberUpdatedState(onDismissed)
    val sheetState = rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        confirmValueChange = { it != SheetValue.Hidden || !disabled },
    )
    val scope = rememberCoroutineScope()
    val finish = {
        shown = false
        currentOnDismissed()
    }
    val dismiss: () -> Unit = {
        scope.launch { sheetState.hide() }.invokeOnCompletion { finish() }
    }
    LaunchedEffect(isPresented) {
        if (isPresented) return@LaunchedEffect
        sheetState.hide()
        finish()
    }
    ModalBottomSheet(
        onDismissRequest = finish,
        modifier = Modifier.statusBarsPadding().padding(top = 10.dp),
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = SheetCorner, topEnd = SheetCorner),
        containerColor = dynamicColor(0xFFFFFF, 0x1C1C1E),
        dragHandle = null,
        contentWindowInsets = { WindowInsets(0, 0, 0, 0) },
    ) {
        CompositionLocalProvider(LocalPresentedInSheet provides true) {
            Box(Modifier.fillMaxSize()) { content(dismiss) }
        }
    }
}

/** PR-01 after onboarding (Shield "Connect", or an invite link). */
@Composable
private fun ConnectSheet(dismiss: () -> Unit, onModel: (ConnectModel) -> Unit) {
    val env = LocalAppEnvironment.current
    val model = remember { ConnectModel(repository = env.repository, code = env.router.takePendingJoinCode()) }
    LaunchedEffect(model) { onModel(model) }
    // A newer invite link while the sheet is up fills the field.
    val pending = env.router.pendingJoinCode
    LaunchedEffect(pending) {
        if (pending == null) return@LaunchedEffect
        env.router.takePendingJoinCode()?.let { model.prefill(it) }
    }
    ConnectView(model = model, onBack = dismiss, onSkip = dismiss, onFinish = dismiss)
}
