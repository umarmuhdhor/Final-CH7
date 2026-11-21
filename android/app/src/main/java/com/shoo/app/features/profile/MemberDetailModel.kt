package com.shoo.app.features.profile

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.shoo.app.data.APIErrorCode
import com.shoo.app.data.FamilyMember
import com.shoo.app.data.LoadFailure
import com.shoo.app.data.RepositoryError
import com.shoo.app.data.ScanOwnerFilter
import com.shoo.app.data.ScanResult
import com.shoo.app.data.ShooRepository
import com.shoo.app.support.Log
import com.shoo.app.support.isCancellation
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** Calls shared by Profile's family list and the member detail. */
object MemberActions {
    /** `POST /family/members/{id}/remind`: null when sent, else what to tell the guardian. */
    suspend fun remind(member: FamilyMember, repository: ShooRepository): LocalizationValue? {
        try {
            repository.remindMember(member.deviceId)
            return null
        } catch (error: Exception) {
            if (error.isCancellation) throw error
            return when ((error as? RepositoryError)?.apiCode) {
                APIErrorCode.pushUnavailable -> LocalizationValue("%@ hasn't turned on notifications", member.name)
                APIErrorCode.remindTooSoon -> LocalizationValue("You already reminded %@ recently", member.name)
                else -> {
                    Log.ui.error("Remind failed", error)
                    LocalizationValue("Couldn't send. Check your connection and try again.")
                }
            }
        }
    }
}

/**
 * "Guardian/Detail Orang Dilindungi" (PF-01): one protected member, read from `GET /family/members`, with their three
 * newest scans, "Kabari saya" and "Putuskan koneksi".
 */
class MemberDetailModel(
    val deviceId: String,
    private val repository: ShooRepository,
    private val now: () -> Instant = Instant::now,
    /** After a disconnect: the member's notifications leave the shade (P13). iOS default `DeliveredPushes.clear()`;
     * Android needs a Context, so the view passes `{ DeliveredPushes.clear(context) }`. */
    private val onDisconnected: () -> Unit = {},
) {
    enum class State {
        LOADING,
        LOADED,
        /** Not (or no longer) one of my members. */
        GONE,
        FAILED,
    }

    var state by mutableStateOf(State.LOADING)
        private set
    var member by mutableStateOf<FamilyMember?>(null)
        private set
    /** Why the member could not be read (`state == FAILED`): picks the sentence under the title (A-03). */
    var loadFailure by mutableStateOf(LoadFailure.CONNECTION)
        private set
    /** Newest first, at most 3 ("Aktivitas terbaru"). */
    var recent by mutableStateOf<List<ScanResult>>(emptyList())
        private set
    var recentFailed by mutableStateOf(false)
        private set
    var isWorking by mutableStateOf(false)
        private set
    var isReminding by mutableStateOf(false)
        private set
    /** Shown as an alert. */
    var actionError by mutableStateOf<LocalizationValue?>(null)

    private var generation = 0

    /** Overlapping calls (the first load and a push reload, A-12): only the newest one is applied. */
    suspend fun load() {
        generation += 1
        val request = generation
        try {
            val members = repository.familyMembers()
            if (request != generation) return
            var found = members.firstOrNull { it.deviceId == deviceId }
            if (found == null) {
                state = State.GONE
                return
            }
            // "Kabari saya" on its way: the switch stays where the guardian put it, not the server's old value.
            val notify = member?.notify
            if (isSavingNotify && notify != null) found = found.copy(notify = notify)
            member = found
            state = State.LOADED
        } catch (error: Exception) {
            if (error.isCancellation) throw error
            if (request != generation) return
            Log.ui.error("Member load failed", error)
            if (state != State.LOADED) {
                loadFailure = LoadFailure.from(error)
                state = State.FAILED
            }
            return
        }
        try {
            val page = repository.scans(owner = ScanOwnerFilter.Device(deviceId), status = null, cursor = null)
            if (request != generation) return
            recent = page.items.take(3)
            recentFailed = false
        } catch (error: Exception) {
            if (error.isCancellation) throw error
            if (request != generation) return
            Log.ui.error("Member activity failed", error)
            recentFailed = true
        }
    }

    /**
     * A push arrived while this screen is open: `AppEnvironment.pushesWhileOpen` went up to `count` (A-12). Reload
     * once, so the page under the banner tells the same story as Guardian Home does. The same count again does nothing.
     */
    suspend fun pushesWhileOpenChanged(count: Int) {
        if (count == handledPushes) return
        handledPushes = count
        load()
    }

    /** The `pushesWhileOpen` value this screen last reloaded for. */
    private var handledPushes = 0

    /** Calendar days since the link was made, counting today. */
    val daysProtected: Int?
        get() {
            val since = member?.connectedAt ?: return null
            val zone = ZoneId.systemDefault()
            val days = ChronoUnit.DAYS.between(since.atZone(zone).toLocalDate(), now().atZone(zone).toLocalDate()).toInt()
            return maxOf(1, days + 1)
        }

    /**
     * "Kabari saya": optimistic, back to the old value when the server says no.
     * BH-30: one change at a time. A tap while one is on its way is ignored (the switch snaps back), so two answers
     * arriving in any order cannot leave the switch on a value the server never had.
     */
    suspend fun setNotify(on: Boolean) {
        val old = member?.notify
        if (isSavingNotify || old == null || old == on) return
        isSavingNotify = true
        member = member?.copy(notify = on)
        try {
            repository.setMemberNotify(deviceId, on)
        } catch (error: Exception) {
            if (error.isCancellation) {
                member = member?.copy(notify = old)
                throw error
            }
            Log.ui.error("Notify change failed", error)
            member = member?.copy(notify = old)
            actionError = LocalizationValue("Couldn't save. Check your connection and try again.")
        } finally {
            isSavingNotify = false
        }
    }

    private var isSavingNotify = false

    /**
     * The message to announce after "Ingatkan". A problem also goes to `actionError`: the announcement alone reaches
     * only TalkBack, so a sighted guardian saw the button come back with no word why.
     */
    suspend fun remind(): LocalizationValue? {
        val member = member ?: return null
        if (isReminding) return null
        isReminding = true
        try {
            val problem = MemberActions.remind(member, repository)
            if (problem != null) {
                actionError = problem
                return problem
            }
            this.member = this.member?.copy(remindedAt = now())
            return LocalizationValue("Reminder sent to %@", member.name)
        } finally {
            isReminding = false
        }
    }

    /** `DELETE /family/members/{id}`; `true` when the member is gone (also when it already was). */
    suspend fun disconnect(): Boolean {
        if (isWorking) return false
        isWorking = true
        try {
            try {
                repository.removeMember(deviceId)
            } catch (error: Exception) {
                if (error.isCancellation) throw error
                // Already removed (an earlier answer got lost): same end state.
                if ((error as? RepositoryError)?.apiCode != APIErrorCode.notFound) {
                    Log.ui.error("Disconnect member failed", error)
                    actionError = LocalizationValue("Couldn't disconnect. Check your connection and try again.")
                    return false
                }
            }
            // Their notifications go too; one call can't pick a person's, so the shade is cleared (C18).
            onDisconnected()
            return true
        } finally {
            isWorking = false
        }
    }
}
