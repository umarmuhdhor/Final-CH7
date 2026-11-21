package com.shoo.app.features.shield

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.shoo.app.data.FamilyMember
import com.shoo.app.data.ScanOwnerFilter
import com.shoo.app.data.ShooRepository
import com.shoo.app.support.Log
import com.shoo.app.support.isCancellation
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

/**
 * "Not connected" only when the server says the extension is off (D-alief-15/24):
 * it never sends `false` without evidence, so an unknown state still counts as connected.
 */
val FamilyMember.isConnected: Boolean
    get() = extensionActive

/** Guardian's Family mode (GD-03): the people they look after, each with their newest risky site. */
class FamilyShieldModel(private val repository: ShooRepository) {
    enum class State { LOADING, LOADED, FAILED }

    companion object {
        /** At most 3 people are shown (PRD GD-03). */
        const val maxMembers = 3
    }

    var state by mutableStateOf(State.LOADING)
        private set
    var members by mutableStateOf<List<FamilyMember>>(emptyList())
        private set

    /** Newest scan id per member, so a card can open Detail (`lastScan` in the contract has no id). */
    private var lastScanIds by mutableStateOf<Map<String, String>>(emptyMap())

    private var generation = 0

    val isEmpty: Boolean
        get() = state == State.LOADED && members.isEmpty()

    fun lastScanId(deviceId: String): String? = lastScanIds[deviceId]

    /** On appear, on foreground, and on pull to refresh. A failed refresh keeps what is shown (D-alief-A12). */
    suspend fun refresh() {
        generation += 1
        val request = generation
        try {
            val family = repository.familyMembers().take(maxMembers)
            val ids = newestScanIds(family)
            if (request != generation) return
            members = family
            lastScanIds = ids
            state = State.LOADED
        } catch (error: Throwable) {
            if (error.isCancellation) throw error
            if (request != generation) return
            Log.ui.error("Family load failed", error)
            if (state != State.LOADED) state = State.FAILED
        }
    }

    suspend fun retry() {
        state = State.LOADING
        refresh()
    }

    private suspend fun newestScanIds(family: List<FamilyMember>): Map<String, String> = coroutineScope {
        // One member's failure only leaves that card without a link; it never hides the family.
        family.mapNotNull { member ->
            val lastScan = member.lastScan ?: return@mapNotNull null
            async<Pair<String, String?>> {
                val page = try {
                    repository.scans(owner = ScanOwnerFilter.Device(member.deviceId), status = null, cursor = null)
                } catch (error: Throwable) {
                    if (error.isCancellation) throw error
                    return@async member.deviceId to null
                }
                // The scan the card shows; the newest one if the list moved on meanwhile.
                val shown = page.items.firstOrNull { it.url == lastScan.url && it.detectedAt == lastScan.detectedAt }
                member.deviceId to (shown ?: page.items.firstOrNull())?.id
            }
        }.awaitAll().mapNotNull { (deviceId, scanId) -> scanId?.let { deviceId to it } }.toMap()
    }
}
