package com.shoo.app.features.shield

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.shoo.app.app.AppSettings
import com.shoo.app.data.APIErrorCode
import com.shoo.app.data.DeviceProfile
import com.shoo.app.data.ExtensionStatus
import com.shoo.app.data.FamilyMember
import com.shoo.app.data.LoadFailure
import com.shoo.app.data.RepositoryError
import com.shoo.app.data.ScamCase
import com.shoo.app.data.ScanOwnerFilter
import com.shoo.app.data.ScanPage
import com.shoo.app.data.ScanResult
import com.shoo.app.data.ScanStatus
import com.shoo.app.data.ShooRepository
import com.shoo.app.data.Verdict
import com.shoo.app.support.Log
import com.shoo.app.support.isCancellation
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import java.time.Instant

/**
 * Guardian Home (GD-01/GD-03, Figma HOME page). `PERSONAL` (Family mode off, "Pribadi/Home"): extension
 * status, how the last day went and recent sites, from `GET /scans?owner=me`. `FAMILY` ("Guardian/Home"):
 * the people looked after, the newest site that still waits for a verdict, and the family's recent sites,
 * from `GET /scans?owner=family`.
 *
 * Android: `extensionStatus` has no default (iOS `ExtensionStatus.load()` needs a Context here); pass
 * `AppEnvironment.extensionStatus`.
 */
class GuardianHomeModel(
    private val repository: ShooRepository,
    private val settings: AppSettings,
    val scope: Scope = Scope.FAMILY,
    extensionStatus: suspend () -> ExtensionStatus,
    private val now: () -> Instant = Instant::now,
    /** `GET /devices/me`. The app passes `AppEnvironment.foregroundProfile`, shared with the foreground sync (OPT-06). */
    profile: (suspend () -> DeviceProfile)? = null,
    /** Told after every verdict the server confirmed (`AppEnvironment.verdictSaves`, K8). */
    private val onVerdictSaved: () -> Unit = {},
) {
    enum class Scope { PERSONAL, FAMILY }

    enum class State { LOADING, LOADED, FAILED }

    /**
     * Which Home is shown (contracts: 30–79 warning, ≥ 80 blocked). Family: the pending scan's `status`.
     * Personal: the worst undecided site of the last 24 h.
     */
    enum class Level { NORMAL, WARNING, DANGER }

    companion object {
        /** A pending site gets a card for this long after it was detected. */
        const val pendingWindowSeconds: Long = 24 * 60 * 60

        /**
         * Statuses whose card shows Danger / Safe. Product decision: warning too.
         * contracts/api.md still allows verdicts on `blocked` only (`verdict_not_allowed`) — raised with the lead.
         * `UNKNOWN` (#493): its card looks like a warning, so it gets the buttons too; the server decides.
         */
        val verdictStatuses: Set<ScanStatus> = setOf(ScanStatus.WARNING, ScanStatus.BLOCKED, ScanStatus.UNKNOWN)

        /** Enough for 14 days of a family of 4; stops a runaway cursor. */
        const val maxPages = 10
        const val recentCount = 3
    }

    var state by mutableStateOf(State.LOADING)
        private set
    var extensionStatus by mutableStateOf<ExtensionStatus>(ExtensionStatus.Off(null))
        private set

    /**
     * `false` until the first read of the extension's status: Pribadi's hero stays neutral instead of guessing
     * "You're not protected yet" (A-06, fase 28a K3; `ShieldModel.extensionChecked`).
     */
    var extensionChecked by mutableStateOf(false)
        private set

    /**
     * A refresh after a successful load failed: the screen keeps what it shows and says it may be old
     * (D-alief-A12, A-01, fase 28a K1). The next successful load clears it.
     */
    var refreshFailed by mutableStateOf(false)
        private set

    /** Why the first load failed (`state == FAILED`): picks the sentence under "Couldn't load" (A-03). */
    var loadFailure by mutableStateOf(LoadFailure.CONNECTION)
        private set
    var profile by mutableStateOf<DeviceProfile?>(null)
        private set
    var members by mutableStateOf<List<FamilyMember>>(emptyList())
        private set
    var scans by mutableStateOf<List<ScanResult>>(emptyList())
        private set

    /** The card under the personal activity; empty hides it. */
    var scamCases by mutableStateOf<List<ScamCase>>(emptyList())
        private set

    /** Personal: the family list answered (it only decides the "Mode Terawasi" card). */
    var personalMembersKnown by mutableStateOf(false)
        private set
    var isSubmittingVerdict by mutableStateOf(false)
        private set

    /**
     * The site whose verdict could not be saved ("Couldn't save"), and the one the server refused
     * (`verdict_not_allowed`). Per site: after a refresh another site's card takes the place, and it must not show
     * the old card's error or retry its verdict.
     */
    private var verdictFailedScanId by mutableStateOf<String?>(null)
    private var verdictNotAllowedScanId by mutableStateOf<String?>(null)

    /** "Couldn't save" on the card shown now. */
    val verdictFailed: Boolean
        get() = verdictFailedScanId != null && verdictFailedScanId == pendingScan?.id

    /** "Can't be marked yet" on the card shown now. */
    val verdictNotAllowed: Boolean
        get() = verdictNotAllowedScanId != null && verdictNotAllowedScanId == pendingScan?.id

    /** Counts Home verdicts the server confirmed: drives the success haptic and the card's hand-over animation. */
    var verdictSaves by mutableIntStateOf(0)
        private set

    private val readExtensionStatus = extensionStatus
    private val loadProfile: suspend () -> DeviceProfile = profile ?: { repository.me() }
    private var generation = 0

    /** Bumped by every verdict the server confirmed, like Detail's `verdictEpoch` (fase 27 K7). */
    private var verdictEpoch = 0

    /**
     * Verdicts confirmed on Home by scan id, with the epoch they were saved in. A refresh that started
     * before one of them read an older list; the verdict is put back on it.
     */
    private var savedVerdicts: Map<String, Pair<Int, Verdict>> = emptyMap()

    // MARK: Derived

    /** Newest family member's scan from the last 24 h with no verdict, unless its card was closed. */
    val pendingScan: ScanResult?
        get() {
            if (scope != Scope.FAMILY) return null
            val since = now().minusSeconds(pendingWindowSeconds)
            val dismissed = settings.dismissedHomeScanIds.toSet()
            val ownId = profile?.deviceId
            return scans.firstOrNull { scan ->
                // #493: a verdict this build can't read counts as none, so the site keeps its card.
                scan.verdict?.known == null &&
                    scan.ownerDeviceId != ownId &&
                    scan.detectedAt >= since &&
                    scan.id !in dismissed
            }
        }

    val level: Level
        get() = when (scope) {
            Scope.FAMILY -> when (pendingScan?.status) {
                null -> Level.NORMAL
                ScanStatus.WARNING -> Level.WARNING
                ScanStatus.BLOCKED -> Level.DANGER
                // #493: a status this build does not know is shown as a warning, never as normal.
                ScanStatus.UNKNOWN -> Level.WARNING
            }
            Scope.PERSONAL -> personalLevel
        }

    private val personalLevel: Level
        get() {
            val since = now().minusSeconds(pendingWindowSeconds)
            val open = scans.filter { it.verdict?.known == null && it.detectedAt >= since }
            if (open.any { it.status == ScanStatus.BLOCKED }) return Level.DANGER
            return if (open.isEmpty()) Level.NORMAL else Level.WARNING
        }

    val canDecide: Boolean
        get() {
            val scan = pendingScan ?: return false
            return scan.status in verdictStatuses
        }

    /** Family Home lists the members' sites only, like Family Activity (GD-05). */
    val recent: List<ScanResult>
        get() {
            val ownId = profile?.deviceId
            val shown = if (scope == Scope.FAMILY) scans.filter { it.ownerDeviceId != ownId } else scans
            return shown.take(recentCount)
        }

    /** At most 3 people are shown (PRD GD-03). */
    val shownMembers: List<FamilyMember>
        get() = members.take(FamilyShieldModel.maxMembers)

    /**
     * The avatar of a scan's owner: the guardian's own scans use their own avatar, a member's scans the
     * member's. null when the owner is not known (yet): the view draws the neutral person.
     */
    fun avatarId(forOwner: String): String? {
        val profile = profile
        if (profile != null && profile.deviceId == forOwner) return profile.avatarId
        return members.firstOrNull { it.deviceId == forOwner }?.avatarId
    }

    /** Family Home with no one to look after: the invite takes the sheet. */
    val hasNoFamily: Boolean
        get() = scope == Scope.FAMILY && state == State.LOADED && members.isEmpty()

    /**
     * Pribadi with nobody to look after ("Pribadi/Home kalau belum setting guardian or protected" 1382:10567): the
     * "Mode Terawasi" card, until it is closed. Unknown members (their call failed) hide it.
     */
    val showsSupervisedCard: Boolean
        get() = scope == Scope.PERSONAL && state == State.LOADED && personalMembersKnown && members.isEmpty() &&
            !settings.supervisedCardDismissed

    // MARK: Actions

    /**
     * On appear, on foreground, on pull to refresh. Overlapping calls: only the newest one is applied,
     * and a failed refresh keeps what is already on screen.
     */
    suspend fun refresh() {
        generation += 1
        val request = generation
        val epoch = verdictEpoch
        extensionStatus = readExtensionStatus()
        extensionChecked = true
        if (request != generation) return
        try {
            val (loadedProfile, loadedScans, loadedMembers) = coroutineScope {
                val me = async { loadProfile() }
                val family = async { if (scope == Scope.FAMILY) repository.familyMembers() else emptyList() }
                val firstPage = async {
                    repository.scans(
                        owner = if (scope == Scope.FAMILY) ScanOwnerFilter.Family else ScanOwnerFilter.Me,
                        status = null,
                        cursor = null,
                    )
                }
                // Family's paging tells the members' rows from the guardian's own: it needs the profile after page 1.
                val p = me.await()
                val s = allScans(firstPage.await(), p.deviceId)
                Triple(p, s, family.await())
            }
            if (request != generation) return
            profile = loadedProfile
            // Personal reads the family on its own, after the screen (`refreshPersonalMembers`).
            if (scope == Scope.FAMILY) members = loadedMembers
            scans = merged(loadedScans, epoch)
            state = State.LOADED
            refreshFailed = false
        } catch (error: Throwable) {
            if (error.isCancellation) throw error
            if (request != generation) return
            Log.ui.error("Guardian Home load failed", error)
            // A failed refresh keeps what is on screen, with the "Couldn't refresh" notice (D-alief-A12).
            if (state == State.LOADED) {
                refreshFailed = true
            } else {
                loadFailure = LoadFailure.from(error)
                state = State.FAILED
            }
            return
        }
        if (scope == Scope.PERSONAL) {
            refreshPersonalMembers(request)
            refreshScamCases(request)
        }
    }

    /** Personal Home only needs to know whether anyone is looked after; a failure never fails the screen. */
    private suspend fun refreshPersonalMembers(request: Int) {
        val loaded = try {
            repository.familyMembers()
        } catch (error: Throwable) {
            if (error.isCancellation) throw error
            return
        }
        if (request != generation) return
        members = loaded
        personalMembersKnown = true
    }

    /** X on the "Mode Terawasi" card: gone for good on this phone. */
    fun dismissSupervisedCard() {
        settings.supervisedCardDismissed = true
    }

    /** A bonus on Home: loaded after the screen, never fails it, and a failed call keeps the card on screen. */
    private suspend fun refreshScamCases(request: Int) {
        val cases = try {
            repository.latestScams()
        } catch (error: Throwable) {
            if (error.isCancellation) throw error
            return
        }
        if (request != generation) return
        scamCases = cases
    }

    /** "Try again" on the error card: the card stays (its button spins) until the answer is in. */
    suspend fun retry() {
        refresh()
    }

    /** The last Safe / Dangerous tapped on the card: "Try again" under "Couldn't save" sends it again. */
    var lastDecision by mutableStateOf<Verdict.Value?>(null)
        private set

    /** The reasons sent with the last "Safe" (SafeReasonSheet), so "Try again" sends them again. */
    private var lastNotes: String? = null

    /** The site the last answer was for, so "Try again" never lands on the next card. */
    private var lastScanId: String? = null

    /** "Try again" on "Couldn't save" (Figma 1665:3183). */
    suspend fun retryDecision() {
        val decision = lastDecision ?: return
        decide(decision, notes = lastNotes, scanId = lastScanId)
    }

    /** X on the card: hidden on this phone, the next pending site (if any) takes its place. */
    fun dismissPending() {
        val scan = pendingScan ?: return
        verdictFailedScanId = null
        verdictNotAllowedScanId = null
        settings.dismissHomeScan(scan.id)
    }

    /**
     * GD-07 from Home: applies at once, no confirmation. On success the card moves on to the next site.
     * `notes`: why (the "Aman" reason sheet). `scanId`: the site the answer was given for (the sheet keeps it, so a
     * card that moved on while the sheet was open never gets the answer); null is the card shown now.
     * `true` when the sheet can close: saved, the scan is gone, or this viewer may not decide (the card says so).
     */
    suspend fun decide(value: Verdict.Value, notes: String? = null, scanId: String? = null): Boolean {
        val target = if (scanId != null) scans.firstOrNull { it.id == scanId } else pendingScan
        val scan = target ?: return scanId != null
        if (scan.status !in verdictStatuses || isSubmittingVerdict) return false
        isSubmittingVerdict = true
        lastDecision = value
        lastNotes = notes
        lastScanId = scan.id
        verdictFailedScanId = null
        verdictNotAllowedScanId = null
        try {
            val verdict = repository.setVerdict(scanId = scan.id, value = value, notes = notes)
            // Only the decided scan (K7): the server applies it per link (contracts/api.md, #241), and other
            // rows of that link get it from the next refresh. A refresh running now may have replaced `scans`.
            verdictEpoch += 1
            savedVerdicts = savedVerdicts + (scan.id to (verdictEpoch to verdict))
            scans = scans.map { if (it.id == scan.id) it.copy(verdict = verdict) else it }
            verdictSaves += 1
            onVerdictSaved()
            return true
        } catch (error: Throwable) {
            if (error.isCancellation) throw error
            val code = (error as? RepositoryError.Api)?.code
            when (code) {
                APIErrorCode.verdictNotAllowed -> {
                    verdictNotAllowedScanId = scan.id
                    return true
                }
                APIErrorCode.verdictLocked -> {
                    // #476: the link already has a safe verdict (another device, or Detail) that stays until the weekly
                    // review. The card is stale: reload, so the site shows as decided and the next one takes its place.
                    refresh()
                    return true
                }
                APIErrorCode.notFound -> {
                    // BH-27: the scan was deleted (14 days, a disconnect): no verdict can ever be saved on it, so the
                    // card moves on to the next site, as Detail shows "This item is gone".
                    scans = scans.filter { it.id != scan.id }
                    return true
                }
                else -> {
                    Log.ui.error("Home verdict failed", error)
                    verdictFailedScanId = scan.id
                    return false
                }
            }
        } finally {
            isSubmittingVerdict = false
        }
    }

    /**
     * A list read when the epoch was `epoch`: verdicts saved after that are newer than the list, so they
     * win for their scan. Older ones are in the list already (the server had them) and are forgotten.
     */
    private fun merged(loaded: List<ScanResult>, readAt: Int): List<ScanResult> {
        savedVerdicts = savedVerdicts.filter { it.value.first > readAt }
        if (savedVerdicts.isEmpty()) return loaded
        return loaded.map { scan ->
            val saved = savedVerdicts[scan.id] ?: return@map scan
            scan.copy(verdict = saved.second)
        }
    }

    /**
     * Pages arrive newest first. Home needs only the last day (the hero, the pending card) and the list's rows: it
     * stops once a page reaches past the window with enough rows. Family counts the members' rows only, the ones
     * `recent` lists (OPT-02, fase 28i K11); before, it read every page.
     */
    private suspend fun allScans(firstPage: ScanPage, ownDeviceId: String): List<ScanResult> {
        val owner = if (scope == Scope.FAMILY) ScanOwnerFilter.Family else ScanOwnerFilter.Me
        val since = now().minusSeconds(pendingWindowSeconds)
        val items = mutableListOf<ScanResult>()
        var page = firstPage
        for (read in 1..maxPages) {
            items += page.items
            val next = page.nextCursor
            if (next == null || read >= maxPages) break
            val listed = if (scope == Scope.FAMILY) items.count { it.ownerDeviceId != ownDeviceId } else items.size
            val oldest = page.items.lastOrNull()
            if (oldest != null && oldest.detectedAt < since && listed >= recentCount) break
            page = repository.scans(owner = owner, status = null, cursor = next)
        }
        return items
    }
}
