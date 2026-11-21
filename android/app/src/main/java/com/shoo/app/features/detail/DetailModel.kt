package com.shoo.app.features.detail

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.shoo.app.components.ScanBadge
import com.shoo.app.data.APIErrorCode
import com.shoo.app.data.DeviceProfile
import com.shoo.app.data.RepositoryError
import com.shoo.app.data.ScanResult
import com.shoo.app.data.ShooRepository
import com.shoo.app.data.UserMode
import com.shoo.app.data.Verdict
import com.shoo.app.support.AppLanguage
import com.shoo.app.support.Log
import java.time.Duration as JavaDuration
import java.time.Instant
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

/**
 * State of the Detail screen (DT-01..06, GD-07). Every source opens it by scan id: Activity, the Shield card, and push.
 * Main thread only (Compose state).
 */
class DetailModel(
    val scanId: String,
    private val repository: ShooRepository,
    private val now: () -> Instant = { Instant.now() },
    private val sleep: suspend (Duration) -> Unit = { delay(it) },
    /** Told after every verdict the server confirmed (`AppEnvironment.verdictSaves`, K8). */
    private val onVerdictSaved: () -> Unit = {},
) {
    enum class LoadState {
        LOADING,
        LOADED,
        /** Deleted (14-day retention), disconnected, or never ours: `GET /scans/{id}` answers 404. */
        NOT_FOUND,
        FAILED,
    }

    /** What `setVerdict` did, so the view announces and gives haptics only for real results. */
    enum class VerdictOutcome {
        /** Not allowed here, or another verdict is still being sent. */
        IGNORED,
        SAVED,
        /** The server said no; the previous verdict is back. */
        ROLLED_BACK,
        /** The scan no longer exists (retention, disconnect, deleted data). */
        GONE,
    }

    /** Why the last verdict was not saved (BH-27), so the footer says what happened. */
    enum class VerdictError {
        /** Offline, timeout, a server error: try again. */
        CONNECTION,
        /** `verdict_not_allowed` (403): this viewer is no longer the owner's Guardian. */
        NOT_ALLOWED,
        /** `rate_limited` (429): more than 60 verdicts a minute. */
        TOO_MANY,
        /** `verdict_locked` (409, #476): the link is marked safe until Shoo's weekly review. */
        LOCKED,
    }

    var state by mutableStateOf(LoadState.LOADING)
        private set
    var scan by mutableStateOf<ScanResult?>(null)
        private set
    /** The device looking at the scan (`GET /devices/me`). */
    var viewer by mutableStateOf<DeviceProfile?>(null)
        private set
    var isSubmittingVerdict by mutableStateOf(false)
        private set
    var verdictError by mutableStateOf<VerdictError?>(null)
        private set
    val verdictFailed: Boolean get() = verdictError != null
    /** Counts verdicts the server confirmed (drives the success haptic). */
    var verdictSaves by mutableIntStateOf(0)
        private set
    /** Waiting for the page copy of a scan that just came in (`awaitsCopy`). */
    var isSavingCopy by mutableStateOf(false)
        private set
    /** Areas per signal on the page copy (`shoo-replica` meta `marks`, #176). Empty until the copy is shown. */
    var marks by mutableStateOf<List<ReplicaMark>>(emptyList())
    /** Width of the copied page in CSS px (the meta's viewport), so marks land on the image. */
    var pageCSSWidth by mutableStateOf<Float?>(null)
    /** The owner's avatar for the chip, from the family list (best effort). */
    var ownerAvatarId by mutableStateOf<String?>(null)
        private set

    private var verdictEpoch = 0
    /** One fresh screenshot link per load; a second failure shows "isn't available". */
    private var screenshotLinkRefreshed = false
    /** One fresh page copy link per load, like the screenshot. */
    private var replicaLinkRefreshed = false

    companion object {
        /** fase 18b: a push can open Detail before the Worker stored the page copy (`waitUntil`). Within this many
         * seconds of the scan, the screen waits for it instead of saying "no copy". */
        const val copyWindowSeconds = 60L
        /** Ask again 3 s after the load, then once more at 15 s; never a third time. */
        val copyRetryDelays: List<Duration> = listOf(3.seconds, 12.seconds)

        private fun isNotFound(error: Throwable): Boolean =
            error is RepositoryError.Api && error.code == APIErrorCode.notFound
    }

    // MARK: Derived

    /** DT-02: Warning / Blocked / Verified scam / Marked safe. */
    val badge: ScanBadge? get() = scan?.let { ScanBadge.from(it) }

    val isOwnScan: Boolean
        get() {
            val scan = scan ?: return false
            val viewer = viewer ?: return false
            return scan.ownerDeviceId == viewer.deviceId
        }

    /** DT-05 / GD-07: only a Guardian, on warning and blocked items alike (Figma 416:9469, #190). The repository only
     * returns the guardian's own scans and their protected members'. */
    val canValidate: Boolean get() = viewer?.mode == UserMode.GUARDIAN && scan != null

    /** The guardian's avatar for the hero, on the protected person's own scan once that guardian decided (Figma
     * "Guardian Virellia", 1211:19925 / 1252:2473). null: the hero shows the big shield. */
    val deciderAvatarId: String?
        get() {
            if (!isOwnScan) return null
            val verdict = scan?.verdict ?: return null
            val guardian = viewer?.guardian ?: return null
            return if (verdict.byDeviceId == guardian.deviceId) guardian.avatarId else null
        }

    /** DT-03: the owner's name is for the guardian's family view, never for Protected. */
    fun showsOwner(familyModeOn: Boolean): Boolean {
        if (viewer?.mode != UserMode.GUARDIAN || scan == null) return false
        return familyModeOn || !isOwnScan
    }

    /** DT-04: 1–3 signals, heaviest first, in the viewer's wording. */
    fun evidence(language: AppLanguage): List<Evidence> {
        val scan = scan ?: return emptyList()
        val mode = viewer?.mode ?: return emptyList()
        return Evidence.top(scan.signals, mode, language, marks)
    }

    /** DT-06: "Verified scam by Adhella" / "Marked safe by you". */
    fun verdictNote(language: AppLanguage): String? {
        val verdict = scan?.verdict ?: return null
        return VerdictNote.text(verdict, viewer?.deviceId, language)
    }

    /** No copy and no screenshot yet, on a scan from the last minute (the device clock decides, so a scan "from the
     * future" does not count). */
    val awaitsCopy: Boolean
        get() {
            val scan = scan ?: return false
            if (scan.pageReplicaUrl != null || scan.screenshotUrl != null) return false
            val age = JavaDuration.between(scan.detectedAt, now()).seconds
            return age in 0..copyWindowSeconds
        }

    // MARK: Actions

    /** A push or the return to the foreground while Detail shows: reads the scan again (a verdict, a deleted scan) but
     * keeps the links of the page copy and screenshot on screen, so the copy is not loaded again (each read hands out
     * new short-lived links, contracts/api.md). */
    suspend fun refresh() {
        if (state != LoadState.LOADED) return
        load(keepingMedia = true)
    }

    suspend fun load() = load(keepingMedia = false)

    private suspend fun load(keepingMedia: Boolean) {
        if (scan == null) state = LoadState.LOADING
        if (!keepingMedia) {
            screenshotLinkRefreshed = false
            replicaLinkRefreshed = false
        }
        val epoch = verdictEpoch
        try {
            val (fetchedScan, loadedViewer) = coroutineScope {
                val fetchedScan = async { repository.scan(scanId) }
                val fetchedViewer = async { repository.me() }
                fetchedScan.await() to fetchedViewer.await()
            }
            var loadedScan = fetchedScan
            val current = scan
            // A verdict tapped while this load was in flight is newer than the snapshot.
            if ((isSubmittingVerdict || epoch != verdictEpoch) && current != null && current.id == loadedScan.id) {
                loadedScan = loadedScan.copy(verdict = current.verdict)
            }
            if (keepingMedia && current != null && current.id == loadedScan.id) {
                current.pageReplicaUrl?.let { loadedScan = loadedScan.copy(pageReplicaUrl = it) }
                current.screenshotUrl?.let { loadedScan = loadedScan.copy(screenshotUrl = it) }
            }
            scan = loadedScan
            viewer = loadedViewer
            state = LoadState.LOADED
            loadOwnerAvatar()
        } catch (cancel: CancellationException) {
            // Leaving the screen cancels the load.
            throw cancel
        } catch (error: Throwable) {
            if (isNotFound(error)) {
                scan = null
                state = LoadState.NOT_FOUND
                return
            }
            if (!currentCoroutineContext().isActive) return
            Log.ui.error("Detail load failed", error)
            if (scan == null) state = LoadState.FAILED
        }
    }

    /** Someone else's scan in the guardian's view: their avatar for the chip. Without it the chip shows the neutral
     * person. */
    private suspend fun loadOwnerAvatar() {
        if (viewer?.mode != UserMode.GUARDIAN || isOwnScan || ownerAvatarId != null) return
        val owner = scan?.ownerDeviceId ?: return
        ownerAvatarId = try {
            repository.familyMembers().firstOrNull { it.deviceId == owner }?.avatarId
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (_: Throwable) {
            null
        }
    }

    /** After `load()`: while `awaitsCopy`, asks for the scan again (`copyRetryDelays`) and takes only `pageReplicaUrl`
     * from the answer, so a verdict being sent is never overwritten. */
    suspend fun waitForCopy() {
        if (!awaitsCopy) return
        isSavingCopy = true
        try {
            for (wait in copyRetryDelays) {
                sleep(wait)
                val current = scan ?: return
                if (current.pageReplicaUrl != null) return
                try {
                    val fresh = repository.scan(scanId)
                    val link = fresh.pageReplicaUrl
                    val now = scan
                    if (link != null && now != null && now.id == current.id && now.pageReplicaUrl == null) {
                        scan = now.copy(pageReplicaUrl = link)
                        return
                    }
                } catch (cancel: CancellationException) {
                    throw cancel
                } catch (error: Throwable) {
                    if (isNotFound(error)) {
                        scan = null
                        state = LoadState.NOT_FOUND
                        return
                    }
                    // Offline for a moment: the second try may still bring it.
                }
            }
        } finally {
            isSavingCopy = false
        }
    }

    /** The screenshot link failed. It may only have expired (valid 1 h), so ask for the scan once more: that brings a
     * fresh link, or a 404 when the scan is really gone (contracts/api.md, D-alief-C04). `true` when a new link came
     * back. */
    suspend fun refreshScreenshotLink(): Boolean {
        if (screenshotLinkRefreshed) return false
        screenshotLinkRefreshed = true
        val fresh = refreshLink({ it.screenshotUrl }, { scan, link -> scan.copy(screenshotUrl = link) })
        if (fresh == null) screenshotLinkRefreshed = false
        return fresh ?: false
    }

    /** Same for the page copy link (`GET /replicas/:id`, valid 1 h). Not after a 429 (the view decides). */
    suspend fun refreshReplicaLink(): Boolean {
        if (replicaLinkRefreshed) return false
        replicaLinkRefreshed = true
        val fresh = refreshLink({ it.pageReplicaUrl }, { scan, link -> scan.copy(pageReplicaUrl = link) })
        if (fresh == null) replicaLinkRefreshed = false
        return fresh ?: false
    }

    /** `true` when a new link came back, `false` when not, null when cancelled (try again next time). */
    private suspend fun refreshLink(link: (ScanResult) -> String?, withLink: (ScanResult, String) -> ScanResult): Boolean? {
        val current = scan ?: return false
        try {
            val fresh = repository.scan(scanId)
            // A `load()` that finished meanwhile already brought the newest link.
            val url = link(fresh) ?: return false
            val now = scan ?: return false
            if (url == link(current) || link(now) != link(current)) return false
            scan = withLink(now, url)
            return true
        } catch (_: CancellationException) {
            // iOS returns nil here; the caller checks that it is still active before going on.
            return null
        } catch (error: Throwable) {
            if (isNotFound(error)) {
                scan = null
                state = LoadState.NOT_FOUND
            }
            return false
        }
    }

    /** GD-07: applies at once, no confirmation. Optimistic; rolled back if the server says no.
     * `notes`: why the Guardian decided (the "Aman" reason sheet), sent as `POST /verdicts` `notes`. */
    suspend fun setVerdict(value: Verdict.Value, notes: String? = null): VerdictOutcome {
        val viewer = viewer
        val previous = scan
        if (!canValidate || isSubmittingVerdict || viewer == null || previous == null) return VerdictOutcome.IGNORED
        isSubmittingVerdict = true
        verdictEpoch += 1
        verdictError = null
        scan = previous.copy(verdict = Verdict(value = value, byDeviceId = viewer.deviceId, byName = viewer.name, decidedAt = now()))
        try {
            val verdict = repository.setVerdict(previous.id, value, notes)
            scan = scan?.copy(verdict = verdict)
            verdictSaves += 1
            onVerdictSaved()
            return VerdictOutcome.SAVED
        } catch (cancel: CancellationException) {
            scan = scan?.copy(verdict = previous.verdict)
            throw cancel
        } catch (error: Throwable) {
            if (isNotFound(error)) {
                scan = null
                state = LoadState.NOT_FOUND
                return VerdictOutcome.GONE
            }
            val code = (error as? RepositoryError)?.apiCode
            if (code == APIErrorCode.verdictLocked) {
                // #476 (A-02, K5): the server already holds a safe verdict on this link that stays until the weekly
                // review (an "Aman" whose answer was lost, or another device). Show the server's verdict, not the
                // rollback, so the badge, buttons and footer agree. Never guess `safe` from the 409 alone. The message
                // is set once the reload is done, so it never sits over the rolled-back buttons.
                scan = scan?.copy(verdict = previous.verdict)
                try {
                    val fresh = repository.scan(previous.id)
                    val now = scan ?: return VerdictOutcome.GONE
                    if (now.id == fresh.id) scan = now.copy(verdict = fresh.verdict)
                } catch (cancel: CancellationException) {
                    throw cancel
                } catch (reload: Throwable) {
                    if (isNotFound(reload)) {
                        scan = null
                        state = LoadState.NOT_FOUND
                        return VerdictOutcome.GONE
                    }
                    // Offline: the rollback and the locked message stay; reopening Detail reloads.
                    Log.ui.error("Detail reload after a locked verdict failed", reload)
                }
                verdictError = VerdictError.LOCKED
                return VerdictOutcome.ROLLED_BACK
            }
            Log.ui.error("Verdict failed", error)
            scan = scan?.copy(verdict = previous.verdict)
            verdictError = when (code) {
                APIErrorCode.verdictNotAllowed -> VerdictError.NOT_ALLOWED
                APIErrorCode.rateLimited -> VerdictError.TOO_MANY
                else -> VerdictError.CONNECTION
            }
            return VerdictOutcome.ROLLED_BACK
        } finally {
            isSubmittingVerdict = false
        }
    }
}
