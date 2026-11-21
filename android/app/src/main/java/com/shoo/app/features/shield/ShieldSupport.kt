package com.shoo.app.features.shield

import android.app.Activity
import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.shoo.app.app.LocalAppEnvironment
import com.shoo.app.components.LocalIsDarkTheme
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.StateMotion
import com.shoo.app.components.hex
import com.shoo.app.components.shooEaseOut
import com.shoo.app.components.shooSpring
import kotlinx.coroutines.launch

// Android stand-ins for the SwiftUI pieces the Shield screens share: scenePhase, `.onChange`, `.privacyCover()`,
// `.sensoryFeedback`, VoiceOver announcements, the Home scroll view with its scrim and top bar, and the "Turn on" sheet.

/** iOS `scenePhase == .active`: the Activity is resumed (MainActivity's `onResume`). */
@Suppress("DEPRECATION")
@Composable
internal fun rememberShieldSceneActive(): Boolean {
    val owner = androidx.compose.ui.platform.LocalLifecycleOwner.current
    var active by remember(owner) { mutableStateOf(owner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) }
    DisposableEffect(owner) {
        val observer = LifecycleEventObserver { _, _ ->
            active = owner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
        }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer) }
    }
    return active
}

/** SwiftUI `.onChange(of: value) { old, new in … }`: not called for the first value. */
@Composable
internal fun <T> ShieldOnChange(value: T, action: (old: T, new: T) -> Unit) {
    val current by rememberUpdatedState(action)
    var previous by remember { mutableStateOf(value) }
    LaunchedEffect(value) {
        val old = previous
        previous = value
        if (old != value) current(old, value)
    }
}

/**
 * True only in the composition where `key` changed. SwiftUI's `.animation(_, value: key)` animates just the update
 * that changed `key`; specs picked with this are read by Compose when their target changes, in that same pass.
 */
@Composable
internal fun <T> changedNow(key: T): Boolean {
    val last = remember { arrayOf<Any?>(key) }
    val changed = last[0] != key
    SideEffect { last[0] = key }
    return changed
}

/**
 * A number that follows `target`: eased with `spec` when one is given (the change is part of an animated SwiftUI
 * update), at once otherwise.
 */
@Composable
internal fun animatedOrSnapped(target: Float, spec: FiniteAnimationSpec<Float>?): Float {
    val value = remember { Animatable(target) }
    LaunchedEffect(target) {
        if (spec != null) value.animateTo(target, spec) else value.snapTo(target)
    }
    return if (spec == null && !value.isRunning) target else value.value
}

/**
 * A state notice (refresh failed) inserted with an animation that also covers the page around it (Guardian Home's
 * `.animation(StateMotion.enter, value: refreshFailed)` on the whole page): the rows under it glide down instead of
 * jumping, so the slot's height follows, unclipped, while the notice itself rises and fades (`StateMotion`).
 */
internal fun stateNoticeEnter(reduceMotion: Boolean): EnterTransition =
    StateMotion.enterTransition(reduceMotion, fromBottom = false) +
        expandVertically(stateSizeSpec(reduceMotion), expandFrom = Alignment.Top, clip = false)

internal fun stateNoticeExit(reduceMotion: Boolean): ExitTransition =
    StateMotion.exitTransition(reduceMotion, toBottom = false) +
        shrinkVertically(stateSizeSpec(reduceMotion), shrinkTowards = Alignment.Top, clip = false)

/** `StateMotion.enter` for sizes. */
internal fun stateSizeSpec(reduceMotion: Boolean): FiniteAnimationSpec<IntSize> =
    if (reduceMotion) shooEaseOut<IntSize>(0.2) else shooSpring<IntSize>(0.32, 0.18)

/**
 * A card closed inside `withAnimation(.easeOut(duration: 0.2))` with `.transition(.opacity)`: it fades where it is
 * while what follows moves up.
 */
internal val dismissExit: ExitTransition =
    androidx.compose.animation.fadeOut(shooEaseOut(0.2)) +
        shrinkVertically(shooEaseOut(0.2), shrinkTowards = Alignment.Top, clip = false)

/** `.sensoryFeedback(.success / .error / .warning)`. */
internal enum class ShieldHaptic { SUCCESS, ERROR, WARNING }

internal fun View.shieldHaptic(kind: ShieldHaptic) {
    val constant = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        when (kind) {
            ShieldHaptic.SUCCESS -> HapticFeedbackConstants.CONFIRM
            ShieldHaptic.ERROR, ShieldHaptic.WARNING -> HapticFeedbackConstants.REJECT
        }
    } else {
        when (kind) {
            ShieldHaptic.SUCCESS -> HapticFeedbackConstants.VIRTUAL_KEY
            ShieldHaptic.ERROR, ShieldHaptic.WARNING -> HapticFeedbackConstants.LONG_PRESS
        }
    }
    performHapticFeedback(constant)
}

/** `AccessibilityNotification.Announcement(text).post()`. */
@Suppress("DEPRECATION")
internal fun View.shieldAnnounce(text: String) {
    announceForAccessibility(text)
}

/**
 * Detail's `.privacyCover()` (SECURITY §3 P9, P13), here for the Shield screens; put it last in a full-screen Box.
 * While the app is not in front the page is covered, so the recents thumbnail never holds a scam URL or a name.
 * Android 13+ also turns the recents screenshot off while the page is up (the system takes it at pause, before
 * Compose can draw the cover).
 */
@Composable
internal fun BoxScope.ShieldPrivacyCoverBox() {
    val view = LocalView.current
    DisposableEffect(view) {
        val activity = view.context as? Activity
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) activity?.setRecentsScreenshotEnabled(false)
        onDispose {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) activity?.setRecentsScreenshotEnabled(true)
        }
    }
    val active = rememberShieldSceneActive()
    if (active) return
    val dark = LocalIsDarkTheme.current
    Box(
        Modifier
            .matchParentSize()
            .background(if (dark) Color.Black else Color.White)
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        SfSymbol("shield.lefthalf.filled", pointSize = 56f, tint = if (dark) hex(0xEBEBF5, 0.6f) else hex(0x3C3C43, 0.6f))
    }
}

/** Reports whether the view's bottom edge is above `threshold` from the window top (`frame(in: .global).maxY < 140`). */
internal fun Modifier.onShieldHeroHidden(threshold: Dp = 140.dp, onChange: (Boolean) -> Unit): Modifier = composed {
    val density = LocalDensity.current
    val limit = with(density) { threshold.toPx() }
    val report by rememberUpdatedState(onChange)
    onGloballyPositioned { coordinates ->
        val bottom = coordinates.positionInWindow().y + coordinates.size.height
        report(bottom < limit)
    }
}

/**
 * The Home scroll view (GuardianHomeView, ProtectedShieldView): the page starts under the status bar plus the room of
 * the (hidden) navigation bar, pull to refresh, the top scrim once the hero is scrolled away, the top bar over it all,
 * and the privacy cover. `content` is light only (iOS `.environment(\.colorScheme, .light)` on the page).
 *
 * iOS: the refresh control sits in the scroll content and pulls the page down; Material's indicator floats over it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ShieldHomeFrame(
    isHeroHidden: Boolean,
    onRefresh: suspend () -> Unit,
    topBar: @Composable () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    val pullState = rememberPullToRefreshState()
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val navBottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    val scrim = if (LocalIsDarkTheme.current) HomeTheme.navy else HomeTheme.background
    val scrimAlpha by animateFloatAsState(if (isHeroHidden) 1f else 0f, shooEaseOut(0.2), label = "homeScrim")

    Box(
        Modifier
            .fillMaxSize()
            .background(HomeTheme.background),
    ) {
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = {
                if (!refreshing) {
                    scope.launch {
                        refreshing = true
                        try {
                            onRefresh()
                        } finally {
                            refreshing = false
                        }
                    }
                }
            },
            state = pullState,
            modifier = Modifier.fillMaxSize(),
            indicator = {
                PullToRefreshDefaults.Indicator(
                    state = pullState,
                    isRefreshing = refreshing,
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .padding(top = statusTop + HomeTopBarHeight),
                )
            },
        ) {
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    // No navigation bar (see HomeTopBar): the page starts where the bar's bottom edge would be.
                    .padding(top = statusTop + HomeTopBarHeight, bottom = navBottom),
            ) {
                CompositionLocalProvider(LocalIsDarkTheme provides false) {
                    content()
                }
            }
        }
        // Once the hero is gone, a scrim keeps the status bar readable over the page: light behind dark text,
        // navy behind white text (dark appearance).
        Box(
            Modifier
                .fillMaxWidth()
                .height(statusTop + 110.dp)
                .graphicsLayer { alpha = scrimAlpha }
                .background(Brush.verticalGradient(listOf(scrim, scrim.copy(alpha = 0.85f), scrim.copy(alpha = 0f))))
                .clearAndSetSemantics { },
        )
        Box(Modifier.padding(top = statusTop)) {
            topBar()
        }
        // App switcher snapshot must not hold scam URLs or names (D-alief-A36).
        ShieldPrivacyCoverBox()
    }
}

/**
 * The "Turn on" sheet (PR-04, GD-01) bound to `Router.isTurnOnPresented`; `onDismiss` of the iOS `.sheet` tells
 * the router (`sheetDismissed`) and the screen (`onDismissed`, a refresh).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ShieldTurnOnSheet(onDismissed: () -> Unit) {
    val router = LocalAppEnvironment.current.router
    val presented = router.isTurnOnPresented
    ShieldOnChange(presented) { old, new ->
        if (old && !new) {
            router.sheetDismissed()
            onDismissed()
        }
    }
    if (!presented) return
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    ModalBottomSheet(
        onDismissRequest = { router.isTurnOnPresented = false },
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp),
        containerColor = Color.White,
        dragHandle = null,
    ) {
        TurnOnExtensionSheet(
            onDismiss = {
                scope.launch { sheetState.hide() }.invokeOnCompletion { router.isTurnOnPresented = false }
            },
        )
    }
}
