package com.shoo.app.features.shield

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.shoo.app.data.ExtensionStatus
import com.shoo.app.data.GuardianInfo
import com.shoo.app.data.LoadFailure
import com.shoo.app.data.ScamCase
import com.shoo.app.data.ScanOwnerFilter
import com.shoo.app.data.ScanResult
import com.shoo.app.data.ShooRepository
import com.shoo.app.support.Log
import com.shoo.app.support.isCancellation
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import java.time.Instant

/**
 * Protected Home (PR-04, Figma "protected/Home" 1115:17162 … 1373:12752): extension status, the guardian, the
 * newest risky site of the last 24 h with what the guardian decided, and recent activity. All from
 * `GET /scans?owner=me`.
 *
 * Android: `extensionStatus` has no default (iOS `ExtensionStatus.load()` needs a Context here); pass
 * `AppEnvironment.extensionStatus`.
 */
class ShieldModel(
    private val repository: ShooRepository,
    extensionStatus: suspend () -> ExtensionStatus,
    private val now: () -> Instant = Instant::now,
) {
    enum class State { LOADING, LOADED, FAILED }

    var state by mutableStateOf(State.LOADING)
        private set
    var extensionStatus by mutableStateOf<ExtensionStatus>(ExtensionStatus.Off(null))
        private set

    /**
     * `false` until the first read of the extension's status: the hero says "Checking Shoo…" instead of a guess
     * (Figma "protected/Home · Mengecek ekstensi" 1681:5275).
     */
    var extensionChecked by mutableStateOf(false)
        private set

    /**
     * A refresh after a successful load failed: the screen keeps what it shows and says it may be old
     * (D-alief-A12, A-01, fase 28b K4). The next successful load clears it.
     */
    var refreshFailed by mutableStateOf(false)
        private set

    /** Why the first load failed (`state == FAILED`): picks the sentence under "Couldn't load" (A-03). */
    var loadFailure by mutableStateOf(LoadFailure.CONNECTION)
        private set

    /** `GET /devices/me` → `guardian`; null when not (or no longer) connected. */
    var guardian by mutableStateOf<GuardianInfo?>(null)
        private set

    /** The picked avatar for the profile circle top right. */
    var profileAvatarId by mutableStateOf<String?>(null)
        private set

    /** This device's scans of the last 24 h, and at least enough older ones to fill the list; newest first. */
    var scans by mutableStateOf<List<ScanResult>>(emptyList())
        private set

    /** The card under the activity; empty hides it. */
    var scamCases by mutableStateOf<List<ScamCase>>(emptyList())
        private set

    private val readExtensionStatus = extensionStatus
    private var generation = 0

    /** The `pushesWhileOpen` value this screen last reloaded for. */
    private var handledPushes = 0

    companion object {
        /** The big card shows a site for this long after it was seen. */
        const val cardWindowSeconds: Long = 24 * 60 * 60

        /** Enough for 14 days of one person; stops a runaway cursor. */
        const val maxPages = 10
        const val recentCount = 3
    }

    // MARK: Derived

    /** Newest scan among the loaded ones (every scan is a warning or a block). */
    val lastScan: ScanResult?
        get() = scans.maxByOrNull { it.detectedAt }

    /**
     * The big card: the newest warning or blocked site of the last 24 h, decided or not (protected/Home/blocked
     * 1115:17294, /warning 1363:12167, approved 1373:13100, 1373:12376 …).
     */
    val cardScan: ScanResult?
        get() {
            val scan = lastScan ?: return null
            return if (scan.detectedAt >= now().minusSeconds(cardWindowSeconds)) scan else null
        }

    /** The site in the big card is not listed again; the next site takes its row. */
    val recent: List<ScanResult>
        get() {
            val card = cardScan?.id
            return scans.asSequence().filter { it.id != card }.take(recentCount).toList()
        }

    /** On appear and every time the app comes back to the foreground. Overlapping calls: only the newest one is applied. */
    suspend fun refresh() {
        generation += 1
        val request = generation
        // Local (App Group + the browser's answer): never waits for the network.
        extensionStatus = readExtensionStatus()
        extensionChecked = true
        if (request != generation) return
        try {
            val (me, loaded) = coroutineScope {
                val profile = async { repository.me() }
                val all = async { allScans() }
                profile.await() to all.await()
            }
            if (request != generation) return
            guardian = me.guardian
            profileAvatarId = me.avatarId
            scans = loaded.sortedByDescending { it.detectedAt }
            state = State.LOADED
            refreshFailed = false
        } catch (error: Throwable) {
            if (error.isCancellation) throw error
            if (request != generation) return
            Log.ui.error("Shield load failed", error)
            // A failed foreground refresh keeps what is on screen, with the "Couldn't refresh" notice (D-alief-A12).
            if (state == State.LOADED) {
                refreshFailed = true
            } else {
                loadFailure = LoadFailure.from(error)
                state = State.FAILED
            }
            return
        }
        refreshScamCases(request)
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

    /**
     * A push arrived while this screen is open: `AppEnvironment.pushesWhileOpen` went up to `count` (A-12).
     * Reload once, so the page under the banner tells the same story as Guardian Home does. The same count
     * again (the view redrawn) does nothing.
     */
    suspend fun pushesWhileOpenChanged(count: Int) {
        if (count == handledPushes) return
        handledPushes = count
        refresh()
    }

    /** "Try again" on the error card: the card stays (its button spins) until the answer is in. */
    suspend fun retry() {
        refresh()
    }

    /**
     * Pages arrive newest first: stop once a page reaches past the card's window and the list
     * (plus the card's site) has its rows.
     */
    private suspend fun allScans(): List<ScanResult> {
        val since = now().minusSeconds(cardWindowSeconds)
        val items = mutableListOf<ScanResult>()
        var cursor: String? = null
        for (read in 0 until maxPages) {
            val page = repository.scans(owner = ScanOwnerFilter.Me, status = null, cursor = cursor)
            items += page.items
            val next = page.nextCursor ?: break
            val oldest = page.items.lastOrNull()
            if (oldest != null && oldest.detectedAt < since && items.size > recentCount) break
            cursor = next
        }
        return items
    }
}
