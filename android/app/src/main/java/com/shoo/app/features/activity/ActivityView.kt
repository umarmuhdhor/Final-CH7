package com.shoo.app.features.activity

import android.os.Build
import android.view.HapticFeedbackConstants
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.dismiss
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.shoo.app.app.LocalAppEnvironment
import com.shoo.app.components.AvatarView
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.components.LocalIsDarkTheme
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.ScanBadge
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.ShieldPulseLoader
import com.shoo.app.components.SiteIcon
import com.shoo.app.components.StateMotion
import com.shoo.app.components.SystemColors
import com.shoo.app.components.figmaCardShadow
import com.shoo.app.components.hex
import com.shoo.app.components.pressScale
import com.shoo.app.components.scaled
import com.shoo.app.components.sfSymbol
import com.shoo.app.components.shooEaseInOut
import com.shoo.app.components.shooEaseOut
import com.shoo.app.components.shooShadow
import com.shoo.app.components.shooSpring
import com.shoo.app.components.textScale
import com.shoo.app.data.CheckStats
import com.shoo.app.data.ExtensionStatus
import com.shoo.app.data.FamilyMember
import com.shoo.app.data.ScanOwnerFilter
import com.shoo.app.data.ScanResult
import com.shoo.app.data.ScanStatus
import com.shoo.app.data.ShooRepository
import com.shoo.app.data.Verdict
import com.shoo.app.features.onboarding.LocalPresentedInSheet
import com.shoo.app.features.onboarding.OnboardingBackButton
import com.shoo.app.features.onboarding.OnboardingTheme
import com.shoo.app.features.shield.TurnOnExtensionSheet
import com.shoo.app.support.AppLanguage
import com.shoo.app.support.Formatters
import com.shoo.app.support.L10n
import com.shoo.app.support.t
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import java.net.URI
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.roundToInt

/**
 * Activity (PR-05; GD-05 in Family mode with `owner = Family`), Figma "Aktivitas – Profil Pribadi / Guardian": title,
 * segments, rows grouped by day, endless scroll, pull to refresh. Tap → Detail. Family mode adds the person picker top
 * right (Figma "Switch Mode" + "Picker").
 *
 * `onBack`: set when pushed (a member's activity from Member detail): the page draws its own back button. Null on the
 * Activity tab's root. It comes after `modifier` so the Swift trailing closure stays a Kotlin trailing lambda.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivityView(
    repository: ShooRepository,
    owner: ScanOwnerFilter,
    ownDeviceId: String? = null,
    verdictSaves: () -> Int = { 0 },
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
) {
    val env = LocalAppEnvironment.current
    val language = LocalAppLanguage.current
    val reduceMotion = LocalReduceMotion.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val model = remember(repository, owner) {
        ActivityModel(repository = repository, owner = owner, ownDeviceId = ownDeviceId, verdictSaves = verdictSaves)
    }
    var isPickerOpen by remember { mutableStateOf(false) }
    // For the empty states: null until read, so Off never flashes before the answer.
    var extensionStatus by remember { mutableStateOf<ExtensionStatus?>(null) }
    var checkStats by remember { mutableStateOf(CheckStats()) }
    var isTurnOnPresented by remember { mutableStateOf(false) }
    var isRefreshing by remember { mutableStateOf(false) }
    var rootOffset by remember { mutableStateOf(Offset.Zero) }
    var pickerButton by remember { mutableStateOf<Rect?>(null) }

    /** The extension's state and counters for the empty states; cheap, read on every appearance. */
    suspend fun readExtension() {
        extensionStatus = env.extensionStatus()
        checkStats = CheckStats.current(env.appGroupDefaults)
    }

    fun setPicker(open: Boolean) {
        isPickerOpen = open
    }

    // First appearance, and coming back after a failed load. Back from Detail or from the other tab: reload once if a
    // verdict was saved meanwhile (K8).
    LaunchedEffect(model) {
        if (model.state != ActivityModel.State.LOADED) model.retry() else model.refreshIfVerdictsChanged()
    }
    LaunchedEffect(Unit) { readExtension() }

    OnChange(model.refreshFailed) { failed ->
        if (!failed) return@OnChange
        @Suppress("DEPRECATION")
        view.announceForAccessibility(L10n.string("Couldn't refresh. Pull down to try again.", language))
    }
    // A push while this screen is open (new scan, verdict, member change): reload, as Guardian Home does (A-12).
    OnChange(env.pushesWhileOpen) { count -> scope.launch { model.pushesWhileOpenChanged(count) } }
    // A tapped push opens Detail here: the "Turn on" sheet must not stay over it.
    OnChange(env.router.screenSheetsClosed) { isTurnOnPresented = false }
    // The sheet went (dismissed or closed by the router): read the add-on again (Swift `onDismiss`).
    OnChange(isTurnOnPresented) { presented -> if (!presented) scope.launch { readExtension() } }
    // Back from the background: new scans arrived meanwhile, and only pushes that land while Shoo is open reload this
    // list (A-12). As Home does.
    OnResume {
        if (model.state == ActivityModel.State.LOADED) scope.launch { model.refresh() }
    }
    BackHandler(enabled = isPickerOpen) { setPicker(false) }

    // Loader → list: a 0.2 s cross-fade, gentle enough for Reduce Motion (`LoaderReplacementFade`). iOS runs it each
    // time the rows appear (after the loader, the message or the empty state); a new Animatable per appearance starts
    // at 0 in that same frame, so the rows never flash in first.
    val rowsShown = model.state == ActivityModel.State.LOADED && model.items.isNotEmpty()
    val rowsAppearances = remember { intArrayOf(0) }
    val lastRowsShown = remember { booleanArrayOf(false) }
    if (rowsShown != lastRowsShown[0]) {
        lastRowsShown[0] = rowsShown
        if (rowsShown) rowsAppearances[0] += 1
    }
    val rowsAppearance = rowsAppearances[0]
    val rowsAlpha = remember(rowsAppearance) { Animatable(0f) }
    LaunchedEffect(rowsAppearance) { rowsAlpha.animateTo(1f, shooEaseOut(0.2)) }

    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val navBottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    val stateFade = tween<Float>(200, easing = com.shoo.app.components.ShooEasing.easeOut)

    Box(
        modifier
            .fillMaxSize()
            .onGloballyPositioned { rootOffset = it.positionInWindow() }
            // App switcher snapshot must not hold scam URLs or names (D-alief-A36).
            .privacyCover(),
    ) {
        ActivityBackground()
        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = {
                scope.launch {
                    isRefreshing = true
                    try {
                        model.refresh()
                        readExtension()
                    } finally {
                        isRefreshing = false
                    }
                }
            },
            modifier = Modifier.fillMaxSize(),
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(
                    start = ActivityStyle.margin,
                    end = ActivityStyle.margin,
                    top = statusTop,
                    bottom = 24.dp + navBottom,
                ),
            ) {
                item(key = "header") {
                    ActivityHeader(
                        model = model,
                        onBack = onBack,
                        openPicker = { setPicker(true) },
                        onPickerButton = { pickerButton = it },
                    )
                }
                item(key = "segments") {
                    ActivitySegments(
                        selection = model.filter,
                        family = model.isFamily,
                        modifier = Modifier.padding(top = 24.dp),
                    ) { filter -> scope.launch { model.select(filter) } }
                }
                item(key = "contentTop") { Spacer(Modifier.height(32.dp)) }

                when {
                    model.state == ActivityModel.State.LOADING -> item(key = "loading") {
                        ShieldPulseLoader(
                            Modifier
                                .animateItem(fadeInSpec = stateFade, placementSpec = null, fadeOutSpec = stateFade)
                                .fillMaxWidth()
                                .heightIn(min = 200.dp),
                        )
                    }
                    model.state == ActivityModel.State.FAILED -> item(key = "failed") {
                        ActivityMessage(
                            systemImage = "wifi.exclamationmark",
                            title = "Couldn't load activity",
                            message = t(model.loadFailure.message("Check your connection and try again.")),
                            modifier = Modifier.animateItem(fadeInSpec = stateFade, placementSpec = null, fadeOutSpec = stateFade),
                        ) {
                            ActivityCapsuleButton(title = "Try again", identifier = "activity.retry") {
                                scope.launch { model.retry() }
                            }
                        }
                    }
                    model.items.isEmpty() -> item(key = "empty") {
                        // Only this phone's own list is about this phone's add-on: Family Activity and a member's
                        // Activity list other people's scans, so no "Protection is off" and no "sites checked" pill.
                        val kind = ActivityEmptyKind.of(model.filter, family = !model.isOwnList, extensionStatus = extensionStatus)
                        ActivityEmptyState(
                            kind = kind,
                            pill = if (model.isOwnList) ActivityEmptyText.pill(kind, checkStats, language = language) else null,
                            offSince = ActivityEmptyText.offSince(extensionStatus?.lastSeen, language = language),
                            modifier = Modifier
                                .animateItem(fadeInSpec = stateFade, placementSpec = null, fadeOutSpec = stateFade)
                                .semantics { testTag = "activity.empty" },
                        ) { isTurnOnPresented = true }
                    }
                    else -> {
                        val rowsLayer = Modifier.graphicsLayer { alpha = rowsAlpha.value }
                        item(key = "refreshFailed") {
                            // The rows below move down / up with the banner (iOS `.animation(StateMotion.enter, value:)`
                            // on the whole list), so the item's height follows the same curve.
                            AnimatedVisibility(
                                visible = model.refreshFailed,
                                enter = StateMotion.enterTransition(reduceMotion, fromBottom = false) +
                                    expandVertically(stateSizeSpec(reduceMotion), expandFrom = Alignment.Top, clip = false),
                                exit = StateMotion.exitTransition(reduceMotion, toBottom = false) +
                                    shrinkVertically(stateSizeSpec(reduceMotion), shrinkTowards = Alignment.Top, clip = false),
                            ) {
                                RefreshFailedNotice(
                                    modifier = Modifier
                                        .padding(bottom = 12.dp)
                                        .semantics { testTag = "activity.refreshFailed" },
                                ) { model.refresh() }
                            }
                        }
                        val days = model.days
                        val lastId = model.items.lastOrNull()?.id
                        days.forEachIndexed { index, day ->
                            item(key = "day-${day.id.toEpochMilli()}") {
                                // LazyVStack spacing 12, then the header's own 12 above (none on the first) and 4 below.
                                Text(
                                    dayTitle(day.id, model.isFamily),
                                    style = activityFont(17f, FontWeight.Medium, tracking = -0.17f),
                                    color = ActivityStyle.secondary,
                                    modifier = rowsLayer
                                        .padding(top = if (index == 0) 0.dp else 24.dp, bottom = 4.dp)
                                        .semantics { heading() },
                                )
                            }
                            day.items.forEach { scan ->
                                item(key = scan.id) {
                                    val interaction = remember { MutableInteractionSource() }
                                    ActivityRow(
                                        scan = scan,
                                        language = language,
                                        owner = if (model.isFamily) {
                                            ActivityRow.Owner(scan.ownerName, model.avatarId(scan.ownerDeviceId))
                                        } else {
                                            null
                                        },
                                        note = model.note(scan),
                                        ownList = model.isOwnList,
                                        modifier = rowsLayer
                                            .padding(top = 12.dp)
                                            .pressScale(interaction, scale = 1f)
                                            .clickable(interactionSource = interaction, indication = null, role = Role.Button) {
                                                env.router.showDetail(scan.id)
                                            }
                                            .semantics { testTag = "activity.row.${scan.id}" },
                                    )
                                    if (scan.id == lastId) {
                                        LaunchedEffect(scan.id) { scope.launch { model.loadMore() } }
                                    }
                                }
                            }
                        }
                        if (model.isLoadingMore) {
                            item(key = "loadingMore") {
                                val loading = t("Loading")
                                Box(
                                    Modifier
                                        .padding(top = 12.dp)
                                        .fillMaxWidth()
                                        .heightIn(min = 44.dp)
                                        .semantics { contentDescription = loading },
                                    contentAlignment = Alignment.Center,
                                ) {
                                    CircularProgressIndicator(Modifier.size(20.dp), color = SystemColors.gray, strokeWidth = 2.dp)
                                }
                            }
                        } else if (model.loadMoreFailed) {
                            item(key = "loadMoreRetry") {
                                Row(
                                    Modifier
                                        .padding(top = 12.dp)
                                        .fillMaxWidth()
                                        .heightIn(min = 44.dp)
                                        .clickable(role = Role.Button, indication = null, interactionSource = remember { MutableInteractionSource() }) {
                                            scope.launch { model.loadMore() }
                                        }
                                        .semantics { testTag = "activity.loadMoreRetry" },
                                    horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    SfSymbol("arrow.clockwise", pointSize = 15f, tint = ActivityStyle.ink)
                                    Text(t("Couldn't load more. Try again"), style = activityFont(15f, FontWeight.Medium), color = ActivityStyle.ink)
                                }
                            }
                        }
                    }
                }
            }
        }

        // The person menu over the button (Swift `overlayPreferenceValue` + anchor).
        if (isPickerOpen) {
            // Tap anywhere else closes the menu.
            Box(
                Modifier
                    .fillMaxSize()
                    .clearAndSetSemantics { }
                    .pointerInput(Unit) { detectTapGestures { setPicker(false) } },
            )
        }
        val button = pickerButton
        if (button != null) {
            val density = LocalDensity.current
            AnimatedVisibility(
                visible = isPickerOpen,
                enter = if (reduceMotion) {
                    EnterTransition.None
                } else {
                    scaleIn(shooSpring(0.3, 0.15), initialScale = 0.6f, transformOrigin = TransformOrigin(1f, 0f)) +
                        fadeIn(shooSpring(0.3, 0.15))
                },
                exit = if (reduceMotion) {
                    ExitTransition.None
                } else {
                    scaleOut(shooSpring(0.3, 0.15), targetScale = 0.6f, transformOrigin = TransformOrigin(1f, 0f)) +
                        fadeOut(shooSpring(0.3, 0.15))
                },
                modifier = Modifier.offset {
                    val width = with(density) { ActivityPersonMenuWidth.toPx() }
                    IntOffset((button.right - rootOffset.x - width).roundToInt(), (button.top - rootOffset.y).roundToInt())
                },
            ) {
                ActivityPersonMenu(
                    people = model.people,
                    selection = model.person,
                    select = { person ->
                        setPicker(false)
                        scope.launch { model.select(person) }
                    },
                ) { setPicker(false) }
            }
        }
    }

    if (isTurnOnPresented) {
        ModalBottomSheet(
            onDismissRequest = { isTurnOnPresented = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = OnboardingTheme.background,
            dragHandle = null,
        ) {
            CompositionLocalProvider(LocalPresentedInSheet provides true) {
                TurnOnExtensionSheet(onDismiss = { isTurnOnPresented = false })
            }
        }
    }
}

/** "Hari ini" (own list) / "Hari Ini" (Family mode), as in the two Figma frames; else "25 Oktober". */
@Composable
private fun dayTitle(day: Instant, family: Boolean): String {
    val zone = ZoneId.systemDefault()
    if (day.atZone(zone).toLocalDate() == LocalDate.now(zone)) {
        return t(if (family) "activity.todayFamily" else "Today")
    }
    return Formatters.day(day, LocalAppLanguage.current)
}

// MARK: Header

@Composable
private fun ActivityHeader(
    model: ActivityModel,
    onBack: (() -> Unit)?,
    openPicker: () -> Unit,
    onPickerButton: (Rect) -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            // Figma: the title's top is 2 pt under the status bar, the 50 pt picker button 7 pt above it.
            .negativeTopPadding(7.dp)
            .heightIn(min = 50.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) {
            OnboardingBackButton(action = onBack, identifier = "activity.back")
        }
        Text(
            t("Activity"),
            style = activityFont(27f, FontWeight.Medium, tracking = -0.27f),
            color = ActivityStyle.title,
            modifier = Modifier
                .weight(1f)
                .semantics { heading() },
        )
        if (model.isFamily && model.people.isNotEmpty()) {
            ActivityPersonButton(
                people = model.people,
                selected = model.selectedMember,
                modifier = Modifier.onGloballyPositioned { coordinates ->
                    val position = coordinates.positionInWindow()
                    onPickerButton(Rect(position, Size(coordinates.size.width.toFloat(), coordinates.size.height.toFloat())))
                },
                open = openPicker,
            )
        }
    }
}

/** Swift `.padding(.top, -x)`: the view draws `x` higher and takes `x` less room. */
private fun Modifier.negativeTopPadding(amount: Dp): Modifier = layout { measurable, constraints ->
    val placeable = measurable.measure(constraints)
    val shift = amount.roundToPx()
    layout(placeable.width, (placeable.height - shift).coerceAtLeast(0)) { placeable.place(0, -shift) }
}

/** Dark capsule "Try again" of the error card. `title`: catalog key. */
@Composable
private fun ActivityCapsuleButton(title: String, identifier: String, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    Box(
        Modifier
            .heightIn(min = 44.dp)
            .background(ActivityStyle.ink, CapsuleShape)
            .clickable(interactionSource = interaction, indication = null, role = Role.Button, onClick = onClick)
            .semantics { testTag = identifier }
            .padding(horizontal = 20.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(t(title), style = activityFont(15f, FontWeight.SemiBold, tracking = -0.15f), color = Color.White)
    }
}

// MARK: Segments

/**
 * "Semua / Waspada / Diblokir" (own) or "… / Bahaya" (Family): Figma "Segmented Control" (iOS 26 style). Selected
 * segment is white; TalkBack hears "selected".
 * U-12: a filter word never breaks in the middle. Three equal segments while the longest word fits a third; else each
 * as wide as its word plus an equal share of what is left; and when the words no longer fit side by side, one segment
 * per line.
 */
@Composable
fun ActivitySegments(
    selection: ActivityFilter,
    family: Boolean,
    modifier: Modifier = Modifier,
    select: (ActivityFilter) -> Unit,
) {
    val reduceMotion = LocalReduceMotion.current
    val measurer = rememberTextMeasurer()
    val semibold = activityFont(13.33f, FontWeight.SemiBold, tracking = -0.08f)
    val medium = activityFont(13.33f, FontWeight.Medium, tracking = -0.08f)
    val filters = ActivityFilter.entries
    val titles = filters.map { t(it.title(family)) }
    val filterLabel = t("Filter")
    val density = LocalDensity.current
    // Set by a tap on another segment; the thumb's next move uses the spring.
    val tapped = remember { booleanArrayOf(false) }
    val tap: (ActivityFilter) -> Unit = { filter ->
        if (filter != selection) tapped[0] = true
        select(filter)
    }

    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .semantics { contentDescription = filterLabel },
    ) {
        val gap = 4.dp
        val padding = 2.dp
        val available = maxWidth - padding * 2 - gap * (filters.size - 1)
        // The semibold word sets the width, so selecting a segment never changes which layout fits.
        val ideal = titles.map { title ->
            with(density) { measurer.measure(title, semibold, softWrap = false, maxLines = 1).size.width.toDp() } + 12.dp
        }
        val fits = ideal.fold(0.dp) { sum, w -> sum + w } <= available
        if (fits) {
            val equal = available / filters.size
            val widths = if (ideal.all { it <= equal }) {
                ideal.map { equal }
            } else {
                val share = ((available - ideal.fold(0.dp) { s, w -> s + w }) / filters.size).coerceAtLeast(0.dp)
                ideal.map { it + share }
            }
            val selectedIndex = filters.indexOf(selection)
            var x = 0.dp
            val xs = widths.map { w -> x.also { x += w + gap } }
            val thumb = rememberSegmentThumb(xs[selectedIndex], widths[selectedIndex], tapped, reduceMotion)
            Box(
                Modifier
                    .fillMaxWidth()
                    .background(ActivityStyle.segmentTrack, CapsuleShape)
                    .padding(padding),
            ) {
                Box(Modifier.matchParentSize()) {
                    Box(
                        Modifier
                            .offset { IntOffset(thumb.offset.value.roundToPx(), 0) }
                            .width(thumb.length.value)
                            .fillMaxHeight()
                            .shooShadow(Color.Black.copy(alpha = 0.06f), radius = 10.dp, y = 2.dp, shape = CapsuleShape)
                            .background(Color.White, CapsuleShape),
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                    filters.forEachIndexed { index, filter ->
                        Segment(
                            title = titles[index],
                            style = if (filter == selection) semibold else medium,
                            isSelected = filter == selection,
                            identifier = "filter.${filter.rawValue}",
                            modifier = Modifier.width(widths[index]),
                        ) { tap(filter) }
                    }
                }
            }
        } else {
            // One segment per line, each on its own track (one capsule around three lines would round off the ends).
            // The tracks, the thumb and the words are three layers so the thumb slides between lines like iOS's
            // matchedGeometryEffect.
            val tops = remember { mutableStateListOf(*Array(filters.size) { 0.dp }) }
            val heights = remember { mutableStateListOf(*Array(filters.size) { 0.dp }) }
            val selectedIndex = filters.indexOf(selection)
            val thumb = rememberSegmentThumb(tops[selectedIndex], heights[selectedIndex], tapped, reduceMotion)
            // Until the lines are measured (the first frame) each line draws its own track and thumb.
            val measured = heights.all { it > 0.dp }
            Box(Modifier.fillMaxWidth()) {
                if (measured) {
                    Column(Modifier.matchParentSize(), verticalArrangement = Arrangement.spacedBy(gap)) {
                        filters.indices.forEach { index ->
                            Box(Modifier.fillMaxWidth().height(heights[index]).background(ActivityStyle.segmentTrack, CapsuleShape))
                        }
                    }
                    Box(
                        Modifier
                            .offset { IntOffset(0, thumb.offset.value.roundToPx()) }
                            .fillMaxWidth()
                            .height(thumb.length.value)
                            .shooShadow(Color.Black.copy(alpha = 0.06f), radius = 10.dp, y = 2.dp, shape = CapsuleShape)
                            .background(Color.White, CapsuleShape),
                    )
                }
                Column(verticalArrangement = Arrangement.spacedBy(gap)) {
                    filters.forEachIndexed { index, filter ->
                        val isSelected = filter == selection
                        val ownBackground = when {
                            measured -> Modifier
                            isSelected -> Modifier
                                .background(ActivityStyle.segmentTrack, CapsuleShape)
                                .shooShadow(Color.Black.copy(alpha = 0.06f), radius = 10.dp, y = 2.dp, shape = CapsuleShape)
                                .background(Color.White, CapsuleShape)
                            else -> Modifier.background(ActivityStyle.segmentTrack, CapsuleShape)
                        }
                        Segment(
                            title = titles[index],
                            style = if (isSelected) semibold else medium,
                            isSelected = isSelected,
                            identifier = "filter.${filter.rawValue}",
                            modifier = Modifier
                                .fillMaxWidth()
                                .onPlaced {
                                    with(density) {
                                        val top = it.positionInParent().y.toDp()
                                        val height = it.size.height.toDp()
                                        if (tops[index] != top) tops[index] = top
                                        if (heights[index] != height) heights[index] = height
                                    }
                                }
                                .then(ownBackground),
                        ) { tap(filter) }
                    }
                }
            }
        }
    }
}

/** The selected segment's capsule: where it starts along the row (or down the stack) and how long it is. */
private class SegmentThumb(offset: Dp, length: Dp) {
    val offset = Animatable(offset, Dp.VectorConverter)
    val length = Animatable(length, Dp.VectorConverter)
}

/**
 * iOS: `withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.1)) { select(filter) }`. Only a tap
 * moves the thumb with the spring; a new layout or a filter set by the model puts it in place at once.
 */
@Composable
private fun rememberSegmentThumb(offset: Dp, length: Dp, tapped: BooleanArray, reduceMotion: Boolean): SegmentThumb {
    val thumb = remember { SegmentThumb(offset, length) }
    LaunchedEffect(offset, length) {
        val animate = tapped[0] && !reduceMotion
        tapped[0] = false
        if (animate) {
            coroutineScope {
                launch { thumb.offset.animateTo(offset, shooSpring(0.3, 0.1)) }
                launch { thumb.length.animateTo(length, shooSpring(0.3, 0.1)) }
            }
        } else {
            thumb.offset.snapTo(offset)
            thumb.length.snapTo(length)
        }
    }
    return thumb
}

/** `StateMotion.enter` for a height: the rows under a state banner move on the banner's curve. */
private fun <T> stateSizeSpec(reduceMotion: Boolean): FiniteAnimationSpec<T> =
    if (reduceMotion) shooEaseOut(0.2) else shooSpring(0.32, 0.18)

@Composable
private fun Segment(
    title: String,
    style: TextStyle,
    isSelected: Boolean,
    identifier: String,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .heightIn(min = 28.dp)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClick)
            .semantics {
                role = Role.Button
                selected = isSelected
                testTag = identifier
            }
            .padding(horizontal = 6.dp),
        contentAlignment = Alignment.Center,
    ) {
        // No line limit: if a word ever lacks room it wraps, never "…".
        Text(title, style = style, color = Color.Black, textAlign = TextAlign.Center)
    }
}

// MARK: Person picker

/**
 * Family mode's top-right glass button: everyone's stacked avatars, or the picked member's avatar + name, and a
 * chevron (Figma "Switch Mode").
 */
@Composable
fun ActivityPersonButton(
    people: List<FamilyMember>,
    selected: FamilyMember?,
    modifier: Modifier = Modifier,
    open: () -> Unit,
) {
    val label = t("Person")
    val value = selected?.name ?: t("Everyone")
    val hint = t("Shows whose activity to see")
    Row(
        modifier
            .heightIn(min = 50.dp)
            .activityGlass(CapsuleShape)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, role = Role.Button, onClick = open)
            .clearAndSetSemantics {
                contentDescription = "$label, $hint"
                stateDescription = value
                role = Role.Button
                testTag = "activity.personPicker"
            }
            .padding(horizontal = 18.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (selected != null) {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                AvatarView(id = selected.avatarId, size = 24.dp, ring = ActivityStyle.avatarRing)
                Text(
                    selected.name,
                    style = activityFont(15f, tracking = -0.15f),
                    color = ActivityStyle.ink,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        } else {
            ActivityAvatarStack(people)
        }
        SfSymbol("chevron.down", pointSize = 17f, tint = ActivityStyle.ink)
    }
}

/** Swift `ActivityPersonMenu.width`. */
val ActivityPersonMenuWidth: Dp = 250.dp

/** Figma "Picker": glass menu with "Semua" (stacked avatars) and one row per member, single choice, no checkmark.
 * Rows are 40 pt as in Figma. */
@Composable
fun ActivityPersonMenu(
    people: List<FamilyMember>,
    selection: ActivityPerson,
    select: (ActivityPerson) -> Unit,
    modifier: Modifier = Modifier,
    close: () -> Unit,
) {
    val shape = RoundedCornerShape(34.dp)
    Column(
        modifier
            .width(ActivityPersonMenuWidth)
            // Figma "Picker" glass: black 25 %, y 8, blur 48.
            .shooShadow(Color.Black.copy(alpha = 0.25f), radius = 24.dp, y = 8.dp, shape = shape)
            .activityGlass(shape)
            .semantics {
                testTag = "activity.personMenu"
                // Swift `.accessibilityAction(.escape, close)`.
                dismiss {
                    close()
                    true
                }
            }
            .padding(vertical = 10.dp),
    ) {
        PersonMenuItem(t("All"), ActivityPerson.Everyone == selection, "person.everyone", { select(ActivityPerson.Everyone) }) {
            ActivityAvatarStack(people)
        }
        people.forEach { member ->
            val person = ActivityPerson.Device(member.deviceId)
            PersonMenuItem(member.name, person == selection, "person.${member.deviceId}", { select(person) }) {
                AvatarView(id = member.avatarId, size = 24.dp, ring = ActivityStyle.avatarRing)
            }
        }
    }
}

@Composable
private fun PersonMenuItem(
    title: String,
    isSelected: Boolean,
    identifier: String,
    onClick: () -> Unit,
    avatar: @Composable () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 40.dp)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, role = Role.Button, onClick = onClick)
            .semantics {
                selected = isSelected
                testTag = identifier
            }
            .padding(start = 22.dp, end = 24.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            title,
            style = activityFont(17f, tracking = -0.43f),
            color = ActivityStyle.menuText,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        avatar()
    }
}

// MARK: Row

/** Swift `ActivityRow`'s nested type and static helpers (the composable of the same name draws the row). */
object ActivityRow {
    data class Owner(val name: String, val avatarId: String?)

    /**
     * Host and path only: query strings and fragments can carry personal data or tokens, and the link is visible to
     * anyone looking at the screen (SECURITY §3 P9). Detail shows the full link. Family cards (GD-03) use this.
     */
    fun displayLink(url: String): String {
        val uri = try {
            URI(url)
        } catch (_: Exception) {
            return url
        }
        val host = uri.host ?: ""
        val path = uri.path ?: ""
        return if (path.isEmpty() || path == "/") host else host + path
    }

    /** The row title (BH-25): the scan's `domain` first, then the path when it is not the root. Percent-encoded
     * (BH-36). No query or fragment (SECURITY §3 P9). */
    fun pageTitle(url: String, domain: String): String {
        val parts = titleParts(url, domain)
        return parts.first + parts.second
    }

    /** The row title split in two (U-05, K8): the scan's `domain`, drawn whole or cut in the middle, and the path
     * after it (empty for the root), the only part cut at its tail. */
    fun titleParts(url: String, domain: String): Pair<String, String> {
        val path = try {
            URI(url).rawPath ?: ""
        } catch (_: Exception) {
            ""
        }
        return domain to (if (path == "/") "" else path)
    }
}

/**
 * One Activity card: favicon circle, domain, (member avatar + name |) time, badge top right (Figma "Update card",
 * 354 × 82, r 20). `owner`: Family Activity only. `note`: own list only. `ownList`: Figma 450:8443 badges.
 */
@Composable
fun ActivityRow(
    scan: ScanResult,
    language: AppLanguage,
    owner: ActivityRow.Owner? = null,
    note: ActivityNote? = null,
    ownList: Boolean = false,
    modifier: Modifier = Modifier,
) {
    // iOS `dynamicTypeSize.isAccessibilitySize` (AX1 = body 28 / 17).
    val accessibilitySize = textScale() >= 1.6f
    val shape = RoundedCornerShape(20.dp)
    val time = Formatters.time(scan.detectedAt, language)
    val statusTitle = t(if (ownList) ScanBadge.from(scan.status).activityTitle else ScanBadge.from(scan).activityTitle)
    val label = buildString {
        append(ActivityRow.pageTitle(scan.url, scan.domain))
        append(", ")
        append(statusTitle)
        append(", ")
        append(listOfNotNull(owner?.name, time).joinToString(", "))
        if (note != null) append(". ").append(note.text(language).text)
    }
    Column(
        modifier
            .fillMaxWidth()
            .figmaCardShadow(shape)
            .background(Color.White, shape)
            .border(1.dp, Color.White.copy(alpha = 0.9f), shape)
            // One stop: site, status, (who), when.
            .clearAndSetSemantics { contentDescription = label }
            .padding(horizontal = 17.dp)
            .padding(top = 17.dp, bottom = if (note == null) 17.dp else if (note.isTwoLine) 17.dp else 11.dp),
        verticalArrangement = Arrangement.spacedBy(if (note?.isTwoLine == true) 16.dp else 8.dp),
    ) {
        if (accessibilitySize) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                StatusBadge(scan, ownList)
                RowSite(scan, owner, time, ownList, badge = false, accessibilitySize = true)
            }
        } else {
            RowSite(scan, owner, time, ownList, badge = true, accessibilitySize = false)
        }
        if (note != null) ActivityNoteView(note, language)
    }
}

/** The own list keeps the detection status on the badge and puts the guardian's verdict in the note below (Figma
 * 450:8443); Family lists still show the verdict. */
@Composable
private fun StatusBadge(scan: ScanResult, ownList: Boolean) {
    when {
        ownList && scan.status == ScanStatus.BLOCKED -> ActivityBlockedPill(markedSafe = scan.verdict?.value == Verdict.Value.SAFE)
        ownList -> ActivityBadge(ScanBadge.WARNING)
        else -> ActivityBadge(ScanBadge.from(scan))
    }
}

/**
 * Icon + page title + subline. The badge shares its width with the domain line only, so "name | time" runs on under it
 * (QA 2026-11-10 #14).
 */
@Composable
private fun RowSite(
    scan: ScanResult,
    owner: ActivityRow.Owner?,
    time: String,
    ownList: Boolean,
    badge: Boolean,
    accessibilitySize: Boolean,
) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SiteIcon(scan.faviconUrl)
        // Figma "stack": 2 pt between domain and the "avatar name | time" line, none above a bare time.
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(if (owner == null) 0.dp else 2.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.Top) {
                Box(Modifier.weight(1f).heightIn(min = 24.dp), contentAlignment = Alignment.CenterStart) {
                    RowTitle(scan, accessibilitySize)
                }
                if (badge) StatusBadge(scan, ownList)
            }
            Box(Modifier.heightIn(min = 20.dp), contentAlignment = Alignment.CenterStart) {
                RowSubline(owner, time)
            }
        }
    }
}

/**
 * U-05 (K8): the start of the domain is free text the scammer picks; its end holds the public suffix, which no fake can
 * make read as the bank's own. So the domain is never cut at its tail: whole, or cut in the middle. The path only gets
 * the room the whole domain leaves (at least `pathRoom`), cut at its tail; with less, the row shows the domain alone.
 * iOS: a three-line domain at accessibility sizes is cut at its tail here (Compose has no multi-line middle cut).
 */
@Composable
private fun RowTitle(scan: ScanResult, accessibilitySize: Boolean) {
    val (domain, path) = ActivityRow.titleParts(scan.url, scan.domain)
    val style = activityFont(17f, tracking = -0.17f)
    val color = ActivityStyle.ink
    when {
        accessibilitySize && path.isEmpty() ->
            Text(domain, style = style, color = color, maxLines = 3, overflow = TextOverflow.Ellipsis)
        accessibilitySize -> Column {
            Text(domain, style = style, color = color, maxLines = 3, overflow = TextOverflow.Ellipsis)
            Text(path, style = style, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        else -> {
            val measurer = rememberTextMeasurer()
            val pathRoom = scaled(24f)
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                val maxPx = constraints.maxWidth
                val domainWidth = measurer.measure(domain, style, softWrap = false, maxLines = 1).size.width
                val roomPx = with(LocalDensity.current) { pathRoom.roundToPx() }
                if (path.isNotEmpty() && domainWidth + roomPx <= maxPx) {
                    Row {
                        Text(domain, style = style, color = color, maxLines = 1, softWrap = false)
                        Text(path, style = style, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis, softWrap = false)
                    }
                } else {
                    Text(
                        middleTruncated(domain, style, maxPx, measurer),
                        style = style,
                        color = color,
                        maxLines = 1,
                        softWrap = false,
                    )
                }
            }
        }
    }
}

/** `.truncationMode(.middle)` on one line: the most characters that fit, half from each end around "…". */
private fun middleTruncated(text: String, style: TextStyle, maxWidthPx: Int, measurer: TextMeasurer): String {
    fun width(s: String) = measurer.measure(s, style, softWrap = false, maxLines = 1).size.width
    if (width(text) <= maxWidthPx) return text
    fun candidate(keep: Int): String {
        val head = (keep + 1) / 2
        val tail = keep / 2
        return text.take(head) + "…" + text.takeLast(tail)
    }
    var low = 0
    var high = text.length - 1
    while (low < high) {
        val mid = (low + high + 1) / 2
        if (width(candidate(mid)) <= maxWidthPx) low = mid else high = mid - 1
    }
    return candidate(low)
}

@Composable
private fun RowSubline(owner: ActivityRow.Owner?, time: String) {
    if (owner != null) {
        // "Name | time" on one line as in Figma; the name is cut first, the time only when even that is not enough.
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            AvatarView(id = owner.avatarId ?: "", size = 16.dp, ring = ActivityStyle.avatarRing)
            Text(
                owner.name,
                style = activityFont(13f, FontWeight.Medium, rounded = true),
                color = ActivityStyle.secondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false),
            )
            Text("|", style = activityFont(13f, rounded = true), color = ActivityStyle.separator, softWrap = false)
            Text(time, style = activityFont(13f, rounded = true), color = ActivityStyle.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    } else {
        Text(time, style = activityFont(13f, rounded = true), color = ActivityStyle.time, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

// MARK: Messages

/**
 * Empty / error state in the Figma card look: grey icon circle, title, message, optional button.
 * `title`: catalog key. `message`: already localized.
 */
@Composable
fun ActivityMessage(
    systemImage: String,
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    action: (@Composable () -> Unit)? = null,
) {
    val shape = RoundedCornerShape(20.dp)
    val titleText = t(title)
    Column(
        modifier
            .fillMaxWidth()
            .background(Color.White, shape)
            .border(1.dp, Color.White.copy(alpha = 0.9f), shape)
            .padding(horizontal = 24.dp, vertical = 32.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .size(48.dp)
                .background(ActivityStyle.iconFill, CircleShape)
                .border(1.dp, ActivityStyle.iconStroke, CircleShape)
                .clearAndSetSemantics { },
            contentAlignment = Alignment.Center,
        ) {
            SfSymbol(systemImage, pointSize = 20f, tint = ActivityStyle.secondary)
        }
        // One TalkBack stop, and the caller's identifier lands on one element.
        Column(
            Modifier.clearAndSetSemantics {
                contentDescription = "$titleText. $message"
                heading()
            },
            verticalArrangement = Arrangement.spacedBy(4.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(titleText, style = activityFont(17f, FontWeight.SemiBold, tracking = -0.17f), color = ActivityStyle.ink, textAlign = TextAlign.Center)
            Text(message, style = activityFont(15f, tracking = -0.15f), color = ActivityStyle.secondary, textAlign = TextAlign.Center)
        }
        action?.invoke()
    }
}

/**
 * Figma "Aktivitas · Gagal memperbarui" (1681:6347): over the rows the list still shows, an 80 pt grey tile with the
 * circular "!", "Gagal memperbarui" and "Menampilkan data terakhir. **Coba Lagi**". The tile's symbol nudges when it
 * arrives and spins in place of itself while the retry runs. Guardian Home shows the same notice (D-alief-A12, K1).
 * `retry` comes last so the Swift trailing closure stays a trailing lambda.
 */
@Composable
fun RefreshFailedNotice(
    retryIdentifier: String = "activity.refreshRetry",
    modifier: Modifier = Modifier,
    retry: suspend () -> Unit,
) {
    val reduceMotion = LocalReduceMotion.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val currentRetry by rememberUpdatedState(retry)
    var isRunning by remember { mutableStateOf(false) }
    var nudge by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        nudge += 1
        // The error tap, only when it first shows.
        view.performHapticFeedback(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS,
        )
    }
    val grey = hex(0x6A717E)
    Column(
        modifier
            .fillMaxWidth()
            .padding(bottom = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .size(80.dp)
                .background(hex(0xF3F6F8), RoundedCornerShape(16.dp))
                .clearAndSetSemantics { },
            contentAlignment = Alignment.Center,
        ) {
            if (isRunning) {
                // `ProgressView().controlSize(.large)`.
                CircularProgressIndicator(Modifier.size(37.dp), color = grey, strokeWidth = 3.dp)
            } else {
                androidx.compose.material3.Icon(
                    imageVector = sfSymbol("exclamationmark.arrow.circlepath"),
                    contentDescription = null,
                    tint = grey,
                    modifier = Modifier
                        .size((43f * 1.4f).dp)
                        .wiggleOnce(nudge, enabled = !reduceMotion),
                )
            }
        }
        Text(
            t("Couldn't refresh"),
            style = activityFont(17f, FontWeight.SemiBold, tracking = -0.43f),
            color = hex(0x151617),
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 14.dp),
        )
        val lead = t("Showing the last data. ")
        val action = t("Try again")
        val interaction = remember { MutableInteractionSource() }
        Box(
            Modifier
                .heightIn(min = 30.dp)
                .pressScale(interaction)
                .clickable(interactionSource = interaction, indication = null, enabled = !isRunning, role = Role.Button) {
                    if (isRunning) return@clickable
                    scope.launch {
                        isRunning = true
                        try {
                            currentRetry()
                        } finally {
                            isRunning = false
                            nudge += 1
                        }
                    }
                }
                .semantics { testTag = retryIdentifier },
            contentAlignment = Alignment.Center,
        ) {
            Text(
                buildAnnotatedString {
                    append(lead)
                    withStyle(SpanStyle(color = hex(0x136CB7), fontWeight = FontWeight.SemiBold)) { append(action) }
                },
                style = activityFont(13f, tracking = -0.08f),
                color = grey,
                textAlign = TextAlign.Center,
            )
        }
    }
}

/** `.symbolEffect(.wiggle, options: .nonRepeating, value:)`: a short rotation wiggle each time `trigger` changes. */
private fun Modifier.wiggleOnce(trigger: Int, enabled: Boolean): Modifier = composed {
    val rotation = remember { Animatable(0f) }
    LaunchedEffect(trigger, enabled) {
        if (!enabled || trigger == 0) return@LaunchedEffect
        for (angle in floatArrayOf(-12f, 10f, -8f, 6f, 0f)) rotation.animateTo(angle, shooEaseInOut(0.08))
    }
    graphicsLayer { rotationZ = rotation.value }
}

// MARK: Helpers shared with Pairing

/** SwiftUI `.onChange(of:)`: `action` runs when `value` changes, never for the first value. */
@Composable
internal fun <T> OnChange(value: T, action: (T) -> Unit) {
    val previous = remember { arrayOf<Any?>(value) }
    val currentAction by rememberUpdatedState(action)
    LaunchedEffect(value) {
        if (previous[0] != value) {
            previous[0] = value
            currentAction(value)
        }
    }
}

/** `.onChange(of: scenePhase)` to `.active`: runs each time the screen comes back to the foreground, not the first time. */
@Composable
internal fun OnResume(action: () -> Unit) {
    val owner = LocalLifecycleOwner.current
    val currentAction by rememberUpdatedState(action)
    DisposableEffect(owner) {
        var first = true
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                if (first) first = false else currentAction()
            }
        }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer) }
    }
}

/**
 * iOS `.privacyCover()`: hides the screen while the app is not in front, so the recent-apps snapshot never holds the
 * scam URL or a member's name (SECURITY §3 P9, P13). A solid page with the shield on it.
 * iOS: Android may take the recents snapshot just before ON_PAUSE lands; the cover is drawn as soon as it does.
 */
internal fun Modifier.privacyCover(): Modifier = composed {
    val owner = LocalLifecycleOwner.current
    var active by remember { mutableStateOf(owner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) }
    DisposableEffect(owner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> active = true
                Lifecycle.Event.ON_PAUSE -> active = false
                else -> Unit
            }
        }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer) }
    }
    val background = if (LocalIsDarkTheme.current) Color.Black else Color.White
    val tint = SystemColors.secondary
    val painter = rememberVectorPainter(sfSymbol("shield.lefthalf.filled"))
    val iconSize = with(LocalDensity.current) { (56f * 1.4f).dp.toPx() }
    drawWithContent {
        drawContent()
        if (!active) {
            drawRect(background)
            translate((size.width - iconSize) / 2f, (size.height - iconSize) / 2f) {
                with(painter) { draw(Size(iconSize, iconSize), colorFilter = ColorFilter.tint(tint)) }
            }
        }
    }
}
