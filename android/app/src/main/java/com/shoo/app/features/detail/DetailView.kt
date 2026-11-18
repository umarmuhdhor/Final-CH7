package com.shoo.app.features.detail

import android.icu.text.RelativeDateTimeFormatter
import android.icu.util.ULocale
import android.net.Uri
import android.view.View
import android.view.ViewGroup
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.shoo.app.BuildConfig
import com.shoo.app.R
import com.shoo.app.app.LocalAppEnvironment
import com.shoo.app.components.LightOnly
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.ShieldPulseLoader
import com.shoo.app.components.ShooEasing
import com.shoo.app.components.StateChipTone
import com.shoo.app.components.StateHeroBackground
import com.shoo.app.components.StateHeroPage
import com.shoo.app.components.StateInfoList
import com.shoo.app.components.StateInfoRow
import com.shoo.app.components.WarningFeedback
import com.shoo.app.components.figmaTextStyle
import com.shoo.app.components.hex
import com.shoo.app.components.loaderReplacementFade
import com.shoo.app.components.textScale
import com.shoo.app.data.DeviceProfile
import com.shoo.app.data.MockRepository
import com.shoo.app.data.ScanResult
import com.shoo.app.data.ScanStatus
import com.shoo.app.data.ShooRepository
import com.shoo.app.data.UserMode
import com.shoo.app.data.Verdict
import com.shoo.app.features.activity.ActivityStyle
import com.shoo.app.features.activity.activityFont
import com.shoo.app.features.onboarding.OnboardingBackButton
import com.shoo.app.features.onboarding.OnboardingCapsuleButton
import com.shoo.app.features.onboarding.OnboardingHeaderBackground
import com.shoo.app.support.AppLanguage
import com.shoo.app.support.Formatters
import com.shoo.app.support.L10n
import com.shoo.app.support.Log
import com.shoo.app.support.t
import java.time.Instant
import java.time.ZoneId
import java.util.Date
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** A verdict being sent finishes even when Detail closes (iOS `Task { }`), so `AppEnvironment.verdictSaves` still counts it. */
private val detailTasks = MainScope()

/** Swift's static members of `DetailView`. */
object DetailView {
    fun statusKind(scan: ScanResult): DetailStatusChip.Kind = when (scan.verdict?.value) {
        Verdict.Value.NOT_SAFE -> DetailStatusChip.Kind.BLOCKED
        Verdict.Value.SAFE -> if (scan.status == ScanStatus.BLOCKED) DetailStatusChip.Kind.UNBLOCKED else DetailStatusChip.Kind.MARKED_SAFE
        // #493: an unknown verdict shows the detection status; an unknown status shows as a warning.
        else -> if (scan.status == ScanStatus.BLOCKED) DetailStatusChip.Kind.BLOCKED else DetailStatusChip.Kind.WARNING
    }

    /** "Situs Berbahaya!", "Situs Mencurigakan!", "Situs Sudah Ditandai Blokir!", "Anda Menandai ini Aman",
     * "Virellia Menandai ini Aman". */
    fun title(scan: ScanResult, viewer: DeviceProfile?, language: AppLanguage): String {
        val byViewer = scan.verdict?.byDeviceId == viewer?.deviceId
        return when (scan.verdict?.value) {
            Verdict.Value.SAFE ->
                if (byViewer) {
                    L10n.string("detail.title.youMarkedSafe", language)
                } else {
                    L10n.string("%@ marked this safe", language, scan.verdict?.byName ?: "")
                }
            Verdict.Value.NOT_SAFE ->
                if (viewer?.mode == UserMode.GUARDIAN) {
                    L10n.string("detail.title.markedBlocked", language)
                } else {
                    L10n.string("detail.title.dangerous", language)
                }
            // #493: an unknown verdict or status never reads safer than "Situs Mencurigakan!".
            else ->
                if (scan.status == ScanStatus.BLOCKED) {
                    L10n.string("detail.title.dangerous", language)
                } else {
                    L10n.string("detail.title.suspicious", language)
                }
        }
    }

    /**
     * Figma shows "bca-verifikasi.site/login"; the full link is what "Copy link" copies. The scan's `domain` (the
     * registrable domain; the full host on a shared platform such as `sites.google.com`, #495), then the path (BH-13):
     * a deceiving subdomain is left out and the domain is never the part the pill cuts (#382). The path stays
     * percent-encoded (BH-36), as in Activity: bidi or invisible characters cannot reorder it.
     */
    fun shownLink(url: String, domain: String): String {
        val path = runCatching { Uri.parse(url).encodedPath }.getOrNull() ?: ""
        return if (path.isEmpty() || path == "/") domain else domain + path
    }

    /** Up to 3 MB of device-written text, locked and read off the main thread. Closing Detail cancels it: null means
     * no render (fase 22 C14). */
    suspend fun prepare(html: String): Pair<String?, ReplicaMeta?> = withContext(Dispatchers.Default) {
        if (!isActive) return@withContext null to null
        val locked = ReplicaHTML.locked(html)
        if (locked == null || !isActive) return@withContext null to null
        locked to ReplicaMeta.read(html)
    }
}

/** Debug: marks for the fixture page `FixtureScreenshotLoader` draws (390 pt wide, three fields from y 120), so
 * previews and the UI gate show both spotlight variants. */
object FixtureMarks {
    const val pageWidth = 390f

    fun marks(scanId: String): List<ReplicaMark> {
        if (scanId != "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03") return emptyList()
        return listOf(
            ReplicaMark("asks_pin", Rect(20f, 120f, 20f + 350f, 120f + 52f)),
            ReplicaMark("unreasonable_request", Rect(20f, 210f, 20f + 350f, 210f + 52f)),
            ReplicaMark("unreasonable_request", Rect(20f, 300f, 20f + 350f, 300f + 52f)),
        )
    }
}

/** What Detail keeps besides the model: the pictures (memory only, SECURITY §3 P9) and the layout readings. */
private class DetailScreenState {
    /** The page image of an old build, in memory only, shared by every card. */
    var screenshot by mutableStateOf<ImageBitmap?>(null)
    var screenshotLoading by mutableStateOf(false)
    /** fase 18b: the page copy, drawn once; it comes before the screenshot (old builds) and the placeholder. */
    var pageCopy by mutableStateOf<PageCopy?>(null)
    var copyState by mutableStateOf(PageCopyState.NONE)
    /** "Try again" bumps it, so the whole first load (read-aloud, waiting for the copy) runs again. */
    var loadAttempt by mutableIntStateOf(0)
    /** The link pill grows with the text size; the title keeps clear of it (dp). */
    var pillHeight by mutableFloatStateOf(34f)
    /** "Aman" on a site Shoo flagged asks why first (SafeReasonSheet); "Bahaya" still applies at once. */
    var askingSafeReason by mutableStateOf(false)
    /** U-07: what decides whether the guardian's footer stays pinned (`footerInPage`). */
    var footerRoom by mutableStateOf(FooterRoom())
    /** The footer's current height, for the room under the page while it is pinned (dp). */
    var footerHeight by mutableFloatStateOf(0f)
    /** "Ubah" on the footer, kept here so moving the footer (`footerRoom`) never drops it. */
    var changingVerdict by mutableStateOf(false)

    var pageCoordinates: LayoutCoordinates? = null
    var titleCoordinates: LayoutCoordinates? = null

    /** The title's lower edge in the page's own coordinates, so scrolling never changes it. */
    fun updateTitleBottom(density: Density) {
        val page = pageCoordinates ?: return
        val title = titleCoordinates ?: return
        if (!page.isAttached || !title.isAttached) return
        val bottom = page.localBoundingBoxOf(title, clipBounds = false).bottom / density.density
        if (footerRoom.titleBottom != bottom) footerRoom = footerRoom.copy(titleBottom = bottom)
    }
}

/**
 * Detail for one scan, the same screen in every mode (PRD §8.4 DT-01..06, GD-07 buttons). Figma "Guardian/Detail
 * Aktivitas" (416:9255), "… Setelah Validasi" (416:9362), "… Waspada" (416:9469), "… Ditandai Aman" (480:5768). The
 * viewer's own scan has no owner chip and reads `labelSimple` when Protected.
 *
 * Drawn edge to edge and light only. The tab bar is hidden by `MainTabView` while Detail is pushed (iOS
 * `.toolbar(.hidden, for: .tabBar)`); the system back gesture pops it there.
 */
@Composable
fun DetailView(
    scanId: String,
    repository: ShooRepository,
    onVerdictSaved: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val env = LocalAppEnvironment.current
    val language = LocalAppLanguage.current
    val view = LocalView.current
    val context = LocalContext.current
    val savedCallback by rememberUpdatedState(onVerdictSaved)
    val model = remember(scanId, repository) {
        DetailModel(scanId, repository, onVerdictSaved = { savedCallback() })
    }
    val screen = remember(model) { DetailScreenState() }
    val scope = rememberCoroutineScope()
    val isMock = BuildConfig.DEBUG && env.repository is MockRepository
    val replicaLoader = LocalReplicaLoader.current
    val screenshotLoader = LocalScreenshotLoader.current
    val pageLoader: ReplicaLoading = if (isMock) remember { FixtureReplicaLoader() } else replicaLoader
    val loader: ScreenshotLoading = if (isMock) remember { FixtureScreenshotLoader() } else screenshotLoader
    // iOS `ReplicaSnapshot.keyWindow`: the hidden web view goes into this window's root view.
    val host = view.rootView as? ViewGroup
    val onBack: () -> Unit = { env.router.pop() }

    /** "92%, Blocked, Verified scam by you": the level is never only a colour. */
    fun headerValue(scan: ScanResult): String {
        val parts = mutableListOf(Formatters.percent(scan.score, language))
        model.badge?.let { parts.add(L10n.string(it.title, language)) }
        model.verdictNote(language)?.let { parts.add(it) }
        return parts.joinToString(", ")
    }

    /** "Bacakan peringatan" (Pengaturan/Aksesibilitas): score and reasons of a warning, once loaded. */
    fun readAloud() {
        val scan = model.scan ?: return
        val reasons = model.evidence(language).map { it.spokenLine(language) }
        WarningFeedback.readAloud(view, env.settings.readAloud, (listOf(headerValue(scan)) + reasons).joinToString(". "))
    }

    /** TalkBack hears the result of a tap: the new note, or that it was rolled back. */
    fun announce(outcome: DetailModel.VerdictOutcome) {
        val text = when (outcome) {
            DetailModel.VerdictOutcome.SAVED -> model.verdictNote(language)
            // A-02: after `verdict_locked` the screen shows the server's safe verdict; say why, not "connection".
            DetailModel.VerdictOutcome.ROLLED_BACK ->
                if (model.verdictError == DetailModel.VerdictError.LOCKED) {
                    L10n.string("This site stays safe until Shoo's weekly review. You can change it after that.", language)
                } else {
                    L10n.string("Couldn't save. Check your connection and try again.", language)
                }
            DetailModel.VerdictOutcome.GONE -> L10n.string("This item is gone", language)
            DetailModel.VerdictOutcome.IGNORED -> null
        }
        if (text != null) view.announce(text)
    }

    /** One load per link. A failed link may only have expired: the model asks for a fresh one once. */
    suspend fun loadScreenshot() {
        screen.screenshot = null
        val url = model.scan?.screenshotUrl ?: return
        screen.screenshotLoading = true
        try {
            val data = loader.imageData(url)
            screen.screenshot = withContext(Dispatchers.Default) { ScreenshotDecoder.image(data) }
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (_: Throwable) {
            Log.ui.error("Screenshot load failed")
            // A new link restarts the screenshot effect; otherwise the cards show no photo.
            model.refreshScreenshotLink()
        } finally {
            screen.screenshotLoading = false
        }
    }

    /**
     * fase 18b: fetch, lock, draw once, keep the picture. A failed link may only have expired: the model asks for a
     * fresh one once. 429 says "Try again later" without a new link. A copy that can't be shown falls back to the
     * screenshot of an old build, then to the placeholder.
     */
    suspend fun loadPageCopy() {
        screen.pageCopy = null
        val url = model.scan?.pageReplicaUrl
        if (url == null) {
            screen.copyState = PageCopyState.NONE
            return
        }
        // Marks of an earlier picture would land on the wrong part of the next one (or of the screenshot).
        model.marks = emptyList()
        model.pageCSSWidth = null
        screen.copyState = PageCopyState.LOADING
        // Signal ids of the reason cards that point at the page: each may get its own crop (DT-04).
        val wantedCrops = model.evidence(language).filter { it.kind.isOnPage }.map { it.signalId }
        try {
            val html = pageLoader.html(url)
            val (locked, meta) = DetailView.prepare(html)
            val copy = if (locked != null && host != null) ReplicaSnapshot.render(locked, meta, wantedCrops, host) else null
            if (copy == null) {
                if (!currentCoroutineContext().isActive) return
                screen.copyState = PageCopyState.UNAVAILABLE
                loadScreenshot()
                return
            }
            screen.pageCopy = copy
            model.marks = copy.marks
            model.pageCSSWidth = copy.cssWidth
            screen.copyState = PageCopyState.SHOWN
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (error: Throwable) {
            if (error is ReplicaLoadException && error.error == ReplicaLoadError.RATE_LIMITED) {
                screen.copyState = PageCopyState.RATE_LIMITED
                return
            }
            Log.ui.error("Page copy load failed")
            // A new link restarts the page copy effect.
            if (model.refreshReplicaLink()) return
            // Cancelled while asking: the effect for the next link owns the state now.
            if (!currentCoroutineContext().isActive) return
            screen.copyState = PageCopyState.UNAVAILABLE
            loadScreenshot()
        }
    }

    LaunchedEffect(model.scanId, screen.loadAttempt) {
        if (isMock) {
            model.marks = FixtureMarks.marks(model.scanId)
            model.pageCSSWidth = FixtureMarks.pageWidth
        }
        model.load()
        // Left before the load ended: nothing is read out and nobody waits for the copy.
        if (!isActive) return@LaunchedEffect
        readAloud()
        model.waitForCopy()
    }
    // A push while Detail is open (the guardian's verdict, the scan deleted) or the return to the foreground: the page
    // follows without leaving it, like Home and Activity (A-12).
    LaunchedEffect(model) {
        snapshotFlow { env.pushesWhileOpen }.drop(1).collect { scope.launch { model.refresh() } }
    }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle, model) {
        var wasPaused = false
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_PAUSE -> wasPaused = true
                Lifecycle.Event.ON_RESUME -> if (wasPaused) {
                    wasPaused = false
                    scope.launch { model.refresh() }
                }
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    val replicaUrl = model.scan?.pageReplicaUrl
    LaunchedEffect(replicaUrl) { loadPageCopy() }
    val screenshotUrl = model.scan?.screenshotUrl
    LaunchedEffect(screenshotUrl) {
        // With a copy the screenshot is only the fallback; a refreshed screenshot link after that fallback must still load.
        if (model.scan?.pageReplicaUrl == null || screen.copyState == PageCopyState.UNAVAILABLE) loadScreenshot()
    }
    LaunchedEffect(model.state) {
        if (model.state == DetailModel.LoadState.FAILED) DetailHaptics.error(view)
    }
    LaunchedEffect(model.verdictSaves) {
        if (model.verdictSaves > 0) DetailHaptics.success(view)
    }
    // A new text size can shrink the footer again: decide afresh.
    val textSize = textScale()
    LaunchedEffect(textSize) { screen.footerRoom = screen.footerRoom.copy(footer = 0f) }

    LightOnly {
        Box(
            modifier
                .fillMaxSize()
                .privacyCover(),
        ) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(DetailStyle.background),
            ) {
                OnboardingHeaderBackground(height = 300.dp)
            }
            // Loader → Detail (or "gone" / "couldn't load"): a 0.2 s cross-fade, gentle enough for Reduce Motion.
            Crossfade(
                targetState = model.state,
                animationSpec = tween(200, easing = ShooEasing.easeOut),
                label = "detailState",
            ) { state ->
                when (state) {
                    DetailModel.LoadState.LOADING -> Column(Modifier.fillMaxSize()) {
                        // Back button only: the screens that have no hero.
                        Row(
                            Modifier
                                .statusBarsPadding()
                                .padding(horizontal = ActivityStyle.margin)
                                .padding(top = 4.dp),
                        ) {
                            OnboardingBackButton(action = onBack, identifier = "detail.back")
                        }
                        ShieldPulseLoader(
                            Modifier
                                .fillMaxWidth()
                                .weight(1f),
                        )
                    }
                    // Figma "Detail Aktivitas · Sudah tidak ada" (1665:3006): the clock shield on slate, "Kedaluwarsa",
                    // the two reasons an item goes, and the way back.
                    DetailModel.LoadState.NOT_FOUND -> StateHeroPage(
                        title = "This item is gone",
                        message = "An item can disappear for one of these reasons:",
                        chip = "Expired",
                        chipTone = StateChipTone.SLATE,
                        background = StateHeroBackground.Image(R.drawable.hero_gradient_slate),
                        titleIdentifier = "detail.notFound",
                        onBack = onBack,
                        backIdentifier = "detail.back",
                        shield = {
                            Image(
                                painterResource(R.drawable.state_shield_clock),
                                contentDescription = null,
                                modifier = Modifier.size(215.dp, 230.dp),
                            )
                        },
                        content = {
                            StateInfoList(
                                rows = listOf(
                                    StateInfoRow("clock.fill", "14 days have passed"),
                                    StateInfoRow("person.2.fill", "The family link was removed"),
                                ),
                                tint = hex(0x4F6074),
                                boxed = false,
                                modifier = Modifier.padding(horizontal = 14.dp),
                            )
                        },
                        footer = {
                            OnboardingCapsuleButton("Back to Activity", onClick = onBack, identifier = "detail.backToActivity")
                        },
                    )
                    // Figma "Detail Aktivitas · Gagal memuat" (1665:3023): the "!" shield on orange, "Gangguan koneksi".
                    DetailModel.LoadState.FAILED -> StateHeroPage(
                        title = "Couldn't load this item",
                        message = "This item can't be shown right now. Check your connection, then try again!",
                        chip = "Connection problem",
                        chipTone = StateChipTone.ORANGE,
                        background = StateHeroBackground.Image(R.drawable.hero_gradient_orange),
                        titleIdentifier = "detail.failed",
                        onBack = onBack,
                        backIdentifier = "detail.back",
                        shield = {
                            Image(
                                painterResource(R.drawable.state_shield_alert),
                                contentDescription = null,
                                modifier = Modifier.size(215.dp, 230.dp),
                            )
                        },
                        footer = {
                            OnboardingCapsuleButton("Try again", onClick = { screen.loadAttempt += 1 }, identifier = "detail.retry")
                        },
                    )
                    DetailModel.LoadState.LOADED -> {
                        val scan = model.scan
                        if (scan != null) {
                            LoadedDetail(
                                model = model,
                                screen = screen,
                                scan = scan,
                                headerValue = headerValue(scan),
                                onBack = onBack,
                                onDecide = { value ->
                                    if (value == Verdict.Value.SAFE) {
                                        screen.askingSafeReason = true
                                    } else {
                                        detailTasks.launch { announce(model.setVerdict(value)) }
                                    }
                                },
                                onCopyLink = {
                                    LinkCopy.copy(scan.url, context)
                                    view.announce(L10n.string("Copied", language))
                                },
                                modifier = Modifier.loaderReplacementFade(),
                            )
                        }
                    }
                }
            }
        }
        if (screen.askingSafeReason && model.state == DetailModel.LoadState.LOADED) {
            SafeReasonSheetPresenter(
                onSubmit = { notes ->
                    val outcome = model.setVerdict(Verdict.Value.SAFE, notes)
                    announce(outcome)
                    // Only a connection problem keeps the sheet ("Coba lagi"); "not allowed" and "too many" close it
                    // and the footer says why.
                    outcome != DetailModel.VerdictOutcome.ROLLED_BACK || model.verdictError != DetailModel.VerdictError.CONNECTION
                },
                onDismiss = { screen.askingSafeReason = false },
            )
        }
    }
}

@Suppress("DEPRECATION")
private fun View.announce(text: String) = announceForAccessibility(text)

/** Someone else's scan in the guardian's view; never on the viewer's own. */
private fun ownerName(model: DetailModel, scan: ScanResult): String? =
    if (model.viewer?.mode == UserMode.GUARDIAN && !model.isOwnScan) scan.ownerName else null

@Composable
private fun LoadedDetail(
    model: DetailModel,
    screen: DetailScreenState,
    scan: ScanResult,
    headerValue: String,
    onBack: () -> Unit,
    onDecide: (Verdict.Value) -> Unit,
    onCopyLink: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val density = LocalDensity.current
    val look = DetailLook.from(scan)
    val scroll = rememberScrollState()
    val navigationBottomPx = WindowInsets.navigationBars.getBottom(density)
    val navigationBottom = with(density) { navigationBottomPx.toDp() }
    // Only the guardian answers here; the protected person reads the decision in "Status situs" (the Ortu frames of
    // 1211:19924 have no footer).
    val pinned = model.canValidate && !screen.footerRoom.footerInPage
    // Cards scrolling under the status bar stay readable once the hero has gone up.
    val shadeFrom = with(density) { (DetailHeroLayout.sheetTop - 60f).dp.toPx() }
    val shaded by remember(shadeFrom) { derivedStateOf { scroll.value > shadeFrom } }

    Box(
        modifier
            .fillMaxSize()
            .background(Color.White)
            // Where a pinned footer ends: above the navigation bar, in the page's coordinates (the page starts at the
            // top of this box).
            .onSizeChanged { size ->
                val bottom = (size.height - navigationBottomPx) / density.density
                if (screen.footerRoom.bottom != bottom) screen.footerRoom = screen.footerRoom.copy(bottom = bottom)
            },
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(scroll),
        ) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .onGloballyPositioned {
                        screen.pageCoordinates = it
                        screen.updateTitleBottom(density)
                    },
            ) {
                // Figma "Hero BG" (402 × 360, rings in it) behind the hero and the top of the sheet.
                DetailHeroBackground(look)
                Column(Modifier.fillMaxWidth()) {
                    DetailHero(look = look, guardianAvatarId = model.deciderAvatarId, onBack = onBack)
                    DetailSheet(model, screen, scan, look, headerValue, onDecide, onCopyLink)
                }
            }
            // iOS `safeAreaInset`: the last card scrolls clear of the pinned footer and the navigation bar.
            Spacer(Modifier.height(navigationBottom + if (pinned) screen.footerHeight.dp else 0.dp))
        }
        // iOS `.ultraThinMaterial` at 90 % under the status bar; Android can't blur what lies behind, so a frosted white.
        Box(
            Modifier
                .fillMaxWidth()
                .windowInsetsTopHeight(WindowInsets.statusBars)
                .background(Color.White.copy(alpha = if (shaded) 0.9f * 0.82f else 0f)),
        )
        if (pinned) {
            Column(
                Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth(),
            ) {
                Footer(model, screen, scan, onDecide)
                // The footer's colour under the navigation bar (iOS `.ignoresSafeArea(edges: .bottom)`).
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(navigationBottom)
                        .background(DetailStyle.footer),
                )
            }
        }
    }
}

/** The guardian's question with Aman / Bahaya, or who verified it. Pinned at the bottom, or in the page under the
 * score when pinned would cover the title (`FooterRoom`). Its height is read in both places. */
@Composable
private fun Footer(model: DetailModel, screen: DetailScreenState, scan: ScanResult, onDecide: (Verdict.Value) -> Unit) {
    val density = LocalDensity.current
    DetailFooter(
        verdict = scan.verdict,
        viewerDeviceId = model.viewer?.deviceId,
        canValidate = model.canValidate,
        failure = model.verdictError,
        ownerName = ownerName(model, scan),
        isBlocked = scan.status == ScanStatus.BLOCKED,
        changing = screen.changingVerdict,
        onChangingChange = { screen.changingVerdict = it },
        onDecide = onDecide,
        modifier = Modifier.onSizeChanged {
            val height = it.height / density.density
            screen.footerHeight = height
            val measured = screen.footerRoom.measured(height)
            if (measured != screen.footerRoom) screen.footerRoom = measured
        },
    )
}

/** Figma "Sheet": white from y 284 with 32 pt corners; the link pill sits on its top edge. */
@Composable
private fun DetailSheet(
    model: DetailModel,
    screen: DetailScreenState,
    scan: ScanResult,
    look: DetailLook,
    headerValue: String,
    onDecide: (Verdict.Value) -> Unit,
    onCopyLink: () -> Unit,
) {
    val language = LocalAppLanguage.current
    val reasons = model.evidence(language)
    Box(Modifier.fillMaxWidth()) {
        Column(
            Modifier
                .fillMaxWidth()
                .background(Color.White, RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp))
                // Figma: the title starts 32 pt into the sheet (y 316), 15 pt under the 34 pt pill.
                .padding(top = maxOf(32f, screen.pillHeight / 2 - 1 + 16).dp),
        ) {
            Summary(model, screen, scan, look, headerValue)
            if (model.canValidate && screen.footerRoom.footerInPage) {
                Footer(model, screen, scan, onDecide)
            }
            // Figma: the score row ends at 500, the divider is at 516, "Alasan Terdeteksi" at 541.
            Box(
                Modifier
                    .padding(top = 16.dp, bottom = 24.dp)
                    .padding(horizontal = 24.dp)
                    .fillMaxWidth()
                    .height(1.dp)
                    .background(DetailStyle.divider),
            )
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = ActivityStyle.margin)
                    .padding(bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text(
                    t("Reasons detected"),
                    style = figmaTextStyle(20f, FontWeight.SemiBold, tracking = -0.45f, lineHeight = 25f),
                    color = DetailStyle.title,
                    modifier = Modifier.semantics { heading() },
                )
                PageCopyCaption(
                    state = if (model.isSavingCopy) PageCopyState.SAVING else screen.copyState,
                    meta = screen.pageCopy?.meta,
                    scan = scan,
                    hasScreenshot = screen.screenshot != null || screen.screenshotLoading,
                )
                for (reason in reasons) {
                    key(reason.id) {
                        val picture = cardPicture(model, screen, reason)
                        EvidenceCard(
                            reason = reason,
                            image = picture.image,
                            highlights = picture.highlights,
                            isLoadingImage = screen.screenshotLoading || screen.copyState == PageCopyState.LOADING || model.isSavingCopy,
                            pageCSSWidth = picture.cssWidth,
                            domain = scan.domain,
                            marksKnown = screen.copyState == PageCopyState.SHOWN && !model.isSavingCopy,
                        )
                    }
                }
            }
        }
        LinkPill(look, scan, onCopyLink, onHeight = { screen.pillHeight = it }, modifier = Modifier.align(Alignment.TopCenter))
    }
}

/** Verbatim: never turned into a tappable link (D-alief-A31). Copy from the long-press menu. Figma: 34 pt at y 266, i.e.
 * its middle 1 pt above the sheet's top edge. */
@Composable
private fun LinkPill(look: DetailLook, scan: ScanResult, onCopyLink: () -> Unit, onHeight: (Float) -> Unit, modifier: Modifier = Modifier) {
    val density = LocalDensity.current
    val copyLabel = t("Copy link")
    var menu by remember { mutableStateOf(false) }
    Box(
        modifier.layout { measurable, constraints ->
            val placeable = measurable.measure(constraints)
            layout(placeable.width, placeable.height) {
                placeable.place(0, -(placeable.height / 2 + 1.dp.roundToPx()))
            }
        },
    ) {
        DetailLinkPill(
            look = look,
            text = DetailView.shownLink(scan.url, scan.domain),
            modifier = Modifier
                .onSizeChanged { onHeight(it.height / density.density) }
                .pointerInput(Unit) { detectTapGestures(onLongPress = { menu = true }) }
                .semantics {
                    testTag = "detail.link"
                    customActions = listOf(CustomAccessibilityAction(copyLabel) { onCopyLink(); true })
                },
        )
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(
                text = { Text(copyLabel, style = activityFont(17f), color = DetailStyle.ink) },
                leadingIcon = { SfSymbol("doc.on.doc", pointSize = 17f, tint = DetailStyle.ink) },
                onClick = {
                    menu = false
                    onCopyLink()
                },
            )
        }
    }
}

private class CardPicture(val image: ImageBitmap?, val cssWidth: Float?, val highlights: List<Rect>)

/** What one reason card draws: its own crop when its marks are off the main picture (DT-04), else the main picture with
 * the marks that land on it. Address reasons point at nothing on the page. */
private fun cardPicture(model: DetailModel, screen: DetailScreenState, reason: Evidence): CardPicture {
    val pageImage = screen.pageCopy?.image ?: screen.screenshot
    if (!reason.kind.isOnPage) return CardPicture(pageImage, model.pageCSSWidth, emptyList())
    val crop = screen.pageCopy?.crops?.get(reason.signalId)
    if (crop != null) return CardPicture(crop.image, crop.cssWidth, crop.highlights(reason.signalId))
    return CardPicture(pageImage, model.pageCSSWidth, reason.highlights)
}

/** Title, when it was opened, then the score next to the site status (own scan) or who opened it. */
@Composable
private fun Summary(model: DetailModel, screen: DetailScreenState, scan: ScanResult, look: DetailLook, headerValue: String) {
    val language = LocalAppLanguage.current
    val density = LocalDensity.current
    // Figma 24; 22 here because the line above sits 2 pt lower to match.
    Column(verticalArrangement = Arrangement.spacedBy(22.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                DetailView.title(scan, model.viewer, language),
                // Figma 120 % (33.6 pt) is the font's own line; an exact height clipped a wrapped title at large text.
                style = activityFont(28f, FontWeight.Medium, tracking = -0.56f),
                color = DetailStyle.title,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .semantics {
                        heading()
                        testTag = "detail.title"
                    }
                    // In the page's own coordinates, so scrolling never changes it.
                    .onGloballyPositioned {
                        screen.titleCoordinates = it
                        screen.updateTitleBottom(density)
                    },
            )
            Text(
                openedText(scan.detectedAt, language),
                style = figmaTextStyle(13f, rounded = true, tracking = -0.08f, lineHeight = 18f),
                color = DetailStyle.rowSubtitle,
                textAlign = TextAlign.Center,
                modifier = Modifier.tagged("detail.time"),
            )
        }
        ScoreRow(model, scan, look, headerValue)
        // Figma 1619:6617: "Ringkasan" 24 pt under the score row, 354 pt wide at x 24.
        DetailSummaryCard.text(scan, language)?.let { text ->
            DetailSummaryCard(
                text = text,
                look = look,
                modifier = Modifier
                    .padding(top = 2.dp)
                    .padding(horizontal = 24.dp),
            )
        }
    }
}

/** Figma "Frame 1618872308": two 181 pt columns either side of a 76 pt line. The red frames put it at x 24–387 (line
 * at 205.5), the orange ones at 16–386 (line at 201). 100 pt tall in Figma; grows with the text size. */
@Composable
private fun ScoreRow(model: DetailModel, scan: ScanResult, look: DetailLook, headerValue: String) {
    val leading = if (look == DetailLook.DANGER) 24f else 16f
    val gap = if (look == DetailLook.DANGER) 0f else 3.5f
    Box(
        Modifier
            .fillMaxWidth()
            .wrapContentWidth(Alignment.CenterHorizontally, unbounded = true)
            .width(DetailHeroLayout.width.dp)
            .heightIn(min = 100.dp),
    ) {
        Row(Modifier.padding(start = leading.dp), verticalAlignment = Alignment.Top) {
            ScoreColumn(scan, headerValue, Modifier.width(181.dp))
            Box(
                Modifier
                    .padding(top = 12.dp)
                    .padding(horizontal = gap.dp)
                    .size(1.dp, 76.dp)
                    .background(DetailStyle.scoreLine),
            )
            RightColumn(model, scan, Modifier.width(181.dp))
        }
    }
}

/** "Penilaian Risiko Shoo", "92/100" and the bar (DT-01). */
@Composable
private fun ScoreColumn(scan: ScanResult, headerValue: String, modifier: Modifier = Modifier) {
    val label = t("Risk score")
    Column(
        modifier
            .padding(top = 12.dp)
            .clearAndSetSemantics {
                contentDescription = label
                stateDescription = headerValue
                testTag = "detail.header"
            },
        verticalArrangement = Arrangement.spacedBy(6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            t("detail.riskScore"),
            style = figmaTextStyle(13f, rounded = true, tracking = -0.08f, lineHeight = 18f),
            color = DetailStyle.rowSubtitle,
            textAlign = TextAlign.Center,
        )
        Text(
            "${scan.score}/100",
            style = figmaTextStyle(28f, FontWeight.SemiBold, tracking = 0.56f, lineHeight = 34f),
            color = DetailStyle.title,
            textAlign = TextAlign.Center,
        )
        RiskScoreBar(score = scan.score, weights = scan.signals.map { it.weight })
    }
}

/** Someone else's scan: "Profil yang mengakses" and their chip. Own scan: "Status situs", the chip and who decided
 * ("dikonfirmasi Virellia · 10.51", "ditandai oleh Shoo"). */
@Composable
private fun RightColumn(model: DetailModel, scan: ScanResult, modifier: Modifier = Modifier) {
    val language = LocalAppLanguage.current
    val owner = ownerName(model, scan)
    if (owner != null) {
        val spoken = t("Opened by %@", owner)
        Column(
            modifier
                .padding(top = 12.dp)
                .clearAndSetSemantics {
                    contentDescription = spoken
                    testTag = "detail.owner"
                },
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            RowLabel("detail.openedBy")
            DetailOwnerChip(name = owner, avatarId = model.ownerAvatarId)
        }
    } else {
        Column(
            modifier.padding(top = 12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            RowLabel("detail.siteStatus")
            DetailStatusChip(DetailView.statusKind(scan))
            Text(
                decidedText(scan, model.viewer, language),
                style = figmaTextStyle(13f, rounded = true, tracking = -0.08f, lineHeight = 18f),
                color = DetailStyle.rowSubtitle,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    // Figma: 16 pt in on both sides (147 pt of 181).
                    .padding(horizontal = 16.dp)
                    .tagged(if (scan.verdict == null) "detail.flagged" else "detail.verdictNote"),
            )
        }
    }
}

@Composable
private fun RowLabel(key: String) {
    Text(
        t(key),
        style = figmaTextStyle(13f, rounded = true, tracking = -0.08f, lineHeight = 18f),
        color = DetailStyle.rowSubtitle,
        textAlign = TextAlign.Center,
        modifier = Modifier.width(181.dp),
    )
}

/** "dikonfirmasi Virellia · 10.51" once a guardian decided, "ditandai oleh Shoo" before. */
private fun decidedText(scan: ScanResult, viewer: DeviceProfile?, language: AppLanguage): String {
    val verdict = scan.verdict ?: return L10n.string("detail.flaggedByShoo", language)
    val time = Formatters.dateFormatter("jm", language, ZoneId.systemDefault()).format(Date.from(verdict.decidedAt))
    return if (verdict.byDeviceId == viewer?.deviceId) {
        L10n.string("confirmed by you · %@", language, time)
    } else {
        L10n.string("confirmed by %@ · %@", language, verdict.byName, time)
    }
}

/** "Diakses hari ini · 10.42 WIB". */
private fun openedText(date: Instant, language: AppLanguage, now: Instant = Instant.now()): String {
    val zone = ZoneId.systemDefault()
    val day = date.atZone(zone).toLocalDate()
    val today = now.atZone(zone).toLocalDate()
    val dayText = if (day == today || day == today.minusDays(1)) {
        // iOS `RelativeDateTimeFormatter`, `.named`: "today" / "hari ini", "yesterday" / "kemarin".
        val formatter = RelativeDateTimeFormatter.getInstance(ULocale.forLanguageTag(language.code))
        val direction = if (day == today) RelativeDateTimeFormatter.Direction.THIS else RelativeDateTimeFormatter.Direction.LAST
        formatter.format(direction, RelativeDateTimeFormatter.AbsoluteUnit.DAY)
    } else {
        Formatters.day(date, language, now)
    }
    return L10n.string("Opened %@ · %@", language, dayText, Formatters.time(date, language))
}
