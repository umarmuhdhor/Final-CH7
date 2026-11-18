package com.shoo.app.features.activity

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.shoo.app.data.FamilyMember
import com.shoo.app.data.LoadFailure
import com.shoo.app.data.ScanOwnerFilter
import com.shoo.app.data.ScanPage
import com.shoo.app.data.ScanResult
import com.shoo.app.data.ScanStatus
import com.shoo.app.data.ShooRepository
import com.shoo.app.support.Log
import com.shoo.app.support.isCancellation
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import java.net.URI
import java.time.Instant
import java.time.ZoneId

/** Segments of Activity (PR-05, GD-05). */
enum class ActivityFilter(val rawValue: String) {
    ALL("all"),
    WARNING("warning"),
    BLOCKED("blocked");

    val status: ScanStatus?
        get() = when (this) {
            ALL -> null
            WARNING -> ScanStatus.WARNING
            BLOCKED -> ScanStatus.BLOCKED
        }

    /** Figma: "Semua / Waspada / Diblokir" on the own list, "Semua / Waspada / Bahaya" in Family mode. Catalog key. */
    fun title(family: Boolean): String = when (this) {
        ALL -> "All"
        WARNING -> "activity.warning"
        BLOCKED -> if (family) "Danger" else "Blocked"
    }

    companion object {
        fun from(raw: String?): ActivityFilter? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** Whose scans Family Activity shows (GD-05): every member, or one of them. */
sealed interface ActivityPerson {
    data object Everyone : ActivityPerson
    data class Device(val id: String) : ActivityPerson
}

/** One day of the list with its rows, newest first (Figma "Hari ini", "25 Oktober"). */
data class ActivityDay(
    /** Start of the day in the given time zone. */
    val id: Instant,
    val items: List<ScanResult>,
) {
    companion object {
        /** Groups a newest-first list by calendar day, keeping the order. */
        fun group(items: List<ScanResult>, zone: ZoneId = ZoneId.systemDefault()): List<ActivityDay> {
            val days = ArrayList<ActivityDay>()
            for (scan in items) {
                val day = scan.detectedAt.atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()
                val last = days.lastOrNull()
                if (last != null && last.id == day) {
                    days[days.size - 1] = ActivityDay(day, last.items + scan)
                } else {
                    days.add(ActivityDay(day, listOf(scan)))
                }
            }
            return days
        }
    }
}

/**
 * Activity list (PR-05; reused by the Guardian's GD-05 with `owner = Family`): newest first, grouped by day, filter by
 * status, endless scroll on `nextCursor`, pull to refresh. Main thread only, like Swift's `@MainActor`.
 *
 * `ownDeviceId` comes from the session; without one (mock, tests) Family Activity asks `me()` once.
 */
class ActivityModel(
    private val repository: ShooRepository,
    owner: ScanOwnerFilter,
    ownDeviceId: String? = null,
    filter: ActivityFilter = ActivityFilter.ALL,
    person: ActivityPerson = ActivityPerson.Everyone,
    /** `AppEnvironment.verdictSaves` (K8), read at every load. */
    private val verdictSaves: () -> Int = { 0 },
) {
    enum class State { LOADING, LOADED, FAILED }

    /** `Family` turns on the person picker (GD-05); `Me` is the user's own history. */
    val baseOwner: ScanOwnerFilter = owner

    var person: ActivityPerson by mutableStateOf(if (owner == ScanOwnerFilter.Family) person else ActivityPerson.Everyone)
        private set

    /** Family members for the picker; empty outside Family Activity. */
    var people: List<FamilyMember> by mutableStateOf(emptyList())
        private set
    var state: State by mutableStateOf(State.LOADING)
        private set

    /** Why the first load failed (`state == FAILED`): picks the sentence under "Couldn't load activity" (A-03). */
    var loadFailure: LoadFailure by mutableStateOf(LoadFailure.CONNECTION)
        private set
    var filter: ActivityFilter by mutableStateOf(filter)
        private set
    var items: List<ScanResult> by mutableStateOf(emptyList())
        private set
    var isLoadingMore: Boolean by mutableStateOf(false)
        private set

    /** The last pull to refresh failed; the list on screen is the previous one. */
    var refreshFailed: Boolean by mutableStateOf(false)
        private set

    /** The last next-page request failed; the list shows a Retry row. */
    var loadMoreFailed: Boolean by mutableStateOf(false)
        private set

    private var nextCursor: String? by mutableStateOf(null)

    /** The guardian's own device: Family Activity shows members only, so its rows are left out. */
    private var ownDeviceId: String? = ownDeviceId

    /** Own list only (Figma 450:8739): the Protected user's guardian, for "Virellia belum melihat website ini" under a
     * blocked row. Null for a guardian or a Protected user without one. */
    var guardianName: String? by mutableStateOf(null)
        private set

    /** Bumped when a first-page request starts and again when one is applied, so neither an older first page nor a
     * next page meant for the previous list can overwrite the newer one. */
    private var generation = 0

    /** Bumped by every `loadMore`: only the newest one clears the spinner (F-A5, K8). */
    private var loadMoreRequest = 0

    /** `verdictSaves()` when the last load started. */
    private var loadedVerdictSaves = 0

    /** The `pushesWhileOpen` value this screen last reloaded for. */
    private var handledPushes = 0

    val isFamily: Boolean get() = baseOwner == ScanOwnerFilter.Family

    /** The user's own history (PR-05), not Family Activity or one member's list. */
    val isOwnList: Boolean get() = baseOwner == ScanOwnerFilter.Me

    /** The `owner=` actually requested: the person picker narrows Family Activity. */
    val owner: ScanOwnerFilter
        get() = when (val p = person) {
            ActivityPerson.Everyone -> baseOwner
            is ActivityPerson.Device -> ScanOwnerFilter.Device(p.id)
        }

    val hasMore: Boolean get() = nextCursor != null

    /** Loaded fine and nothing matches the filter (each filter has its own empty text). */
    val isEmpty: Boolean get() = state == State.LOADED && items.isEmpty()
    val days: List<ActivityDay> get() = ActivityDay.group(items)

    /** The member picked in Family Activity, null for everyone. */
    val selectedMember: FamilyMember?
        get() {
            val p = person as? ActivityPerson.Device ?: return null
            return people.firstOrNull { it.deviceId == p.id }
        }

    /** Avatar id for a row's owner (Family Activity subline). */
    fun avatarId(deviceId: String): String? = people.firstOrNull { it.deviceId == deviceId }?.avatarId

    suspend fun load() {
        // Read at the start: a verdict saved while this load runs may be missing from it. Counted as seen only once a
        // list arrived, so a cancelled or failed reload runs again on the next appearance.
        val saves = verdictSaves()
        refreshPeople()
        refreshViewer()
        if (!currentCoroutineContext().isActive) return
        if (loadFirstPage()) loadedVerdictSaves = saves
    }

    /** Pull to refresh: keeps the current items on screen until the new first page arrives, and keeps them if it fails. */
    suspend fun refresh() {
        load()
    }

    /** On every appearance after the first load: a verdict saved since the last load is not in these rows yet, so the
     * list reloads once (F-A15, K8). */
    suspend fun refreshIfVerdictsChanged() {
        if (state != State.LOADED || verdictSaves() == loadedVerdictSaves) return
        refresh()
    }

    /** A push arrived while this screen is open: `AppEnvironment.pushesWhileOpen` went up to `count` (A-12). Reload
     * once; the same count again does nothing. */
    suspend fun pushesWhileOpenChanged(count: Int) {
        if (count == handledPushes) return
        handledPushes = count
        refresh()
    }

    /** "Try again" on the error screen: shows the spinner while it retries. */
    suspend fun retry() {
        if (items.isEmpty()) state = State.LOADING
        load()
    }

    suspend fun select(filter: ActivityFilter) {
        if (filter == this.filter && state != State.FAILED) return
        this.filter = filter
        startOver()
    }

    suspend fun select(person: ActivityPerson) {
        if (!isFamily || (person == this.person && state != State.FAILED)) return
        this.person = person
        startOver()
    }

    private suspend fun startOver() {
        items = emptyList()
        nextCursor = null
        isLoadingMore = false
        loadMoreFailed = false
        refreshFailed = false
        state = State.LOADING
        loadFirstPage()
    }

    /** Called when the last row appears, and by the Retry row. */
    suspend fun loadMore() {
        val cursor = nextCursor ?: return
        if (state != State.LOADED || isLoadingMore) return
        val request = generation
        loadMoreRequest += 1
        val ticket = loadMoreRequest
        isLoadingMore = true
        loadMoreFailed = false
        // Every way out clears the spinner (F-A5).
        try {
            val page = visiblePage(cursor, request, items.mapTo(mutableSetOf()) { site(it) }) ?: return
            items = items + page.items
            nextCursor = page.nextCursor
        } catch (error: Throwable) {
            // A newer list replaced this one: it is not a "couldn't load more".
            if (request != generation || error.isCancellation) {
                if (error is CancellationException) throw error
                return
            }
            Log.ui.error("Activity next page failed", error)
            loadMoreFailed = true
        } finally {
            if (ticket == loadMoreRequest) isLoadingMore = false
        }
    }

    /** Rows the list shows: in Family Activity (everyone) the guardian's own rows are left out (GD-05). */
    private fun isShown(scan: ScanResult): Boolean {
        val own = ownDeviceId
        if (!isFamily || person != ActivityPerson.Everyone || own == null) return true
        return scan.ownerDeviceId != own
    }

    /** One page with its hidden rows and sites already in `seen` removed. A page left empty by that is skipped while a
     * next one exists, so the list never stalls on an empty page. Null when a newer list replaced this one. */
    private suspend fun visiblePage(after: String?, request: Int, seen: MutableSet<String> = mutableSetOf()): ScanPage? {
        var cursor = after
        while (true) {
            val page = repository.scans(owner, filter.status, cursor)
            if (request != generation) return null
            val shown = page.items.filter { isShown(it) && seen.add(site(it)) }
            if (shown.isNotEmpty() || page.nextCursor == null) {
                return ScanPage(shown, page.nextCursor)
            }
            cursor = page.nextCursor
        }
    }

    /** Who is looking at the own list: their device (a verdict they made reads "you") and their guardian. Re-read on
     * every load (a guardian can connect or leave); a failure keeps the last. */
    private suspend fun refreshViewer() {
        if (!isOwnList) return
        try {
            val me = repository.me()
            ownDeviceId = me.deviceId
            guardianName = me.guardian?.name
        } catch (error: Throwable) {
            if (error is CancellationException) throw error
            Log.ui.error("Activity profile failed", error)
        }
    }

    /** Note under an own-list row: the guardian's verdict, or that they have not looked yet. */
    fun note(scan: ScanResult): ActivityNote? {
        if (!isOwnList) return null
        return ActivityNote.of(scan, guardianName, ownDeviceId)
    }

    /** Members for the picker, re-read on every load. A failure keeps the members already shown; the list still loads. */
    private suspend fun refreshPeople() {
        if (!isFamily) return
        if (ownDeviceId == null) {
            ownDeviceId = try {
                repository.me().deviceId
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                null
            }
        }
        try {
            val members = repository.familyMembers()
            people = members
            val p = person
            if (p is ActivityPerson.Device && members.none { it.deviceId == p.id }) {
                person = ActivityPerson.Everyone
            }
        } catch (error: Throwable) {
            if (error is CancellationException) throw error
            Log.ui.error("Activity people failed", error)
        }
    }

    /** `true` when this first page is now on screen. */
    private suspend fun loadFirstPage(): Boolean {
        generation += 1
        val request = generation
        try {
            val page = visiblePage(null, request) ?: return false
            generation += 1
            items = page.items
            nextCursor = page.nextCursor
            isLoadingMore = false
            loadMoreFailed = false
            refreshFailed = false
            state = State.LOADED
            return true
        } catch (error: Throwable) {
            if (error is CancellationException) throw error
            if (request != generation) return false
            Log.ui.error("Activity load failed", error)
            // A next page on its way was for the list before this load: it is dropped (`generation`).
            isLoadingMore = false
            if (state == State.LOADED) {
                refreshFailed = true
            } else {
                items = emptyList()
                nextCursor = null
                loadFailure = LoadFailure.from(error)
                state = State.FAILED
            }
            return false
        }
    }

    companion object {
        /**
         * One row per link (PR-05, #241): an owner's page (origin + path, as `verdict_link` on the backend) shows once,
         * as its newest scan. Two pages of one site are two rows (BH-25).
         */
        fun site(scan: ScanResult): String {
            val uri = try {
                URI(scan.url)
            } catch (_: Exception) {
                null
            }
            val scheme = uri?.scheme?.lowercase() ?: ""
            val host = uri?.host?.lowercase() ?: ""
            val port = uri?.port?.takeIf { it >= 0 }?.let { ":$it" } ?: ""
            val path = uri?.rawPath ?: ""
            return "${scan.ownerDeviceId}|$scheme://$host$port${path.ifEmpty { "/" }}"
        }
    }
}
