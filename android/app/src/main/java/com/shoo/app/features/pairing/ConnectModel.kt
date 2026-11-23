package com.shoo.app.features.pairing

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.shoo.app.app.DeepLink
import com.shoo.app.data.APIErrorCode
import com.shoo.app.data.GuardianInfo
import com.shoo.app.data.RepositoryError
import com.shoo.app.data.ShooRepository
import com.shoo.app.support.AppLanguage
import com.shoo.app.support.L10n
import com.shoo.app.support.Log
import kotlinx.coroutines.CancellationException
import java.time.Duration
import java.time.Instant
import kotlin.math.ceil
import kotlin.math.max

/**
 * PR-01 / PR-02 / PR-03: a protected device joins its guardian's family with the 6-digit code. A code from a link or a
 * QR only fills the field; joining always needs the Connect tap (T11). Main thread only, like Swift's `@MainActor`.
 *
 * `join` replaces `POST /family/join`, e.g. a guardian joining as protected (PF-01).
 */
class ConnectModel(
    repository: ShooRepository,
    code: String? = null,
    join: (suspend (String) -> GuardianInfo)? = null,
) {
    sealed interface State {
        data object Entering : State
        data object Joining : State

        /** PR-02: "You're protected by [name]". */
        data class Joined(val guardian: GuardianInfo) : State
    }

    /** Why the join didn't work, worded for the person holding the phone (contracts/api.md join errors). */
    enum class Problem {
        INVALID,
        EXPIRED,
        FULL,
        TOO_MANY_ATTEMPTS,
        /** `rate_limited` from `POST /devices`: too many new devices from this IP. No join was tried; the wait can be an hour. */
        SIGN_UP_LIMIT,
        ALREADY_CONNECTED,
        /** "Punya kode undangan?" while still protecting someone (PF-01). */
        HAS_MEMBERS,
        OFFLINE,
        OTHER;

        /** Catalog key. Figma "Connect with Guardian · Kode salah / Keluarga penuh / Terlalu banyak …" (1681:4712–4824). */
        val message: String
            get() = when (this) {
                INVALID -> "That code doesn't match. Check it again, or ask your Guardian for a new code."
                EXPIRED -> "That code has expired. Ask your guardian for the new code."
                FULL -> "This family already has 3 people. Ask your Guardian to remove one person first."
                TOO_MANY_ATTEMPTS -> "Too many tries. For your safety, wait a moment before trying again."
                SIGN_UP_LIMIT -> "Too many sign-ups from this network. Try again in 1 hour."
                ALREADY_CONNECTED -> "You're already connected to a guardian. Only they can disconnect you: ask them first."
                HAS_MEMBERS -> "You still protect someone. Disconnect them in Profile first."
                OFFLINE -> "No connection. Check your internet and try again."
                OTHER -> "Something went wrong. Try again."
            }

        /** The server holds every join for a while: the button counts down instead of "Connect". */
        val isWait: Boolean get() = this == TOO_MANY_ATTEMPTS || this == SIGN_UP_LIMIT

        companion object {
            fun from(error: Throwable): Problem {
                val repositoryError = error as? RepositoryError
                return when (repositoryError?.apiCode) {
                    APIErrorCode.codeInvalid -> INVALID
                    APIErrorCode.codeExpired -> EXPIRED
                    APIErrorCode.familyFull -> FULL
                    APIErrorCode.tooManyAttempts -> TOO_MANY_ATTEMPTS
                    APIErrorCode.rateLimited -> SIGN_UP_LIMIT
                    APIErrorCode.alreadyConnected -> ALREADY_CONNECTED
                    APIErrorCode.hasMembers -> HAS_MEMBERS
                    null -> if (repositoryError == RepositoryError.Network) OFFLINE else OTHER
                    else -> OTHER
                }
            }
        }
    }

    private val joinWithCode: suspend (String) -> GuardianInfo = join ?: { repository.joinFamily(it) }

    var state: State by mutableStateOf(State.Entering)
        private set
    var problem: Problem? by mutableStateOf(null)
        private set

    /** `too_many_attempts` / `rate_limited` with a `Retry-After`: no join before this time (Figma "Coba lagi dalam 04:59"). */
    var retryAt: Instant? by mutableStateOf(null)
        private set

    /** Onboarding is undoing a failed invite registration (fase 27d): no join may start meanwhile. */
    var isHeld: Boolean by mutableStateOf(false)
        private set

    private var _code by mutableStateOf("")

    /** Digits only, at most 6; editing clears the last problem. */
    var code: String
        get() = _code
        set(value) {
            val old = _code
            val digits = value.filter { it in '0'..'9' }.take(codeLength)
            _code = digits
            // A wait stays on screen while the code is edited: the server still refuses until it ends.
            if (digits != old && retryAt == null) problem = null
        }

    init {
        if (code != null) prefill(code)
    }

    val canJoin: Boolean get() = state == State.Entering && !isHeld && retryAt == null && DeepLink.isCode(code)

    /** Seconds left of the wait, rounded up; null with no wait. */
    fun secondsToWait(now: Instant = Instant.now()): Int? =
        retryAt?.let { max(0, ceil(Duration.between(now, it).toMillis() / 1000.0).toInt()) }

    /** The wait is over (the view's timer): Connect comes back and the line goes. */
    fun waitEnded(now: Instant = Instant.now()) {
        val at = retryAt ?: return
        if (now.isBefore(at)) return
        retryAt = null
        problem = null
    }

    /** "Ketik ulang kode": empties the field for a fresh try. */
    fun retype() {
        if (state != State.Entering || retryAt != null) return
        code = ""
        problem = null
    }

    /** Busy with a join or with something onboarding does on this screen: Back and "Not now" wait. */
    val isBusy: Boolean get() = state == State.Joining || isHeld

    /** From `shoo://join?code=` or a QR: fills the field, never joins (T11). */
    fun prefill(code: String) {
        if (state != State.Entering || !DeepLink.isCode(code)) return
        this.code = code
    }

    /** A scanned QR: our invite link fills the code; anything else is refused (`false`). */
    fun scanned(payload: String): Boolean {
        // An invite link is under 100 characters; anything much longer is not ours.
        if (payload.toByteArray(Charsets.UTF_8).size > 512) return false
        val link = DeepLink.from(payload.trim())
        if (link !is DeepLink.Join) return false
        prefill(link.code)
        return true
    }

    /** A failure outside `join()` that belongs on this screen (onboarding "Not now"). */
    fun report(error: Throwable) {
        show(error)
    }

    private fun show(error: Throwable, now: Instant = Instant.now()) {
        val problem = Problem.from(error)
        val seconds = (error as? RepositoryError)?.retryAfter
        if (problem.isWait && seconds != null && seconds > 0) {
            retryAt = now.plusMillis((seconds * 1000).toLong())
        }
        this.problem = problem
    }

    /** Set by onboarding around its own work on this screen (`isHeld`). */
    fun hold(held: Boolean) {
        isHeld = held
    }

    /** The server says this device has a guardian after all (a join whose answer got lost): PR-02. */
    fun showJoined(guardian: GuardianInfo) {
        problem = null
        retryAt = null
        state = State.Joined(guardian)
    }

    /** UI-gate screenshots only (`-debug.onboardingStep connected`). */
    fun showJoinedForScreenshot() {
        state = State.Joined(GuardianInfo(deviceId = "dev_nisrina", name = "Nisrina", avatarId = "avatar_04"))
    }

    suspend fun join() {
        if (!canJoin) return
        state = State.Joining
        problem = null
        try {
            // `ApiRepository` keeps `guardian.name` in the App Group for the add-on (EX-06).
            val guardian = joinWithCode(code)
            state = State.Joined(guardian)
        } catch (error: CancellationException) {
            state = State.Entering
            throw error
        } catch (error: Throwable) {
            state = State.Entering
            Log.ui.error("Join failed", error)
            show(error)
        }
    }

    companion object {
        val codeLength: Int = DeepLink.codeLength

        /**
         * The grey wait button (Figma "Coba lagi dalam 04:59", 1681:4787 / 4824), in `language`. An hour or more counts in
         * hours, so the sign-up limit's "Try again in 1 hour." and the button use one unit (U-18); 10 minutes or more in
         * minutes ("59 menit"); shorter ones as mm:ss. Every unit rounds up.
         */
        fun waitLabel(seconds: Int, language: AppLanguage): String {
            val minutes = ceil(seconds / 60.0).toInt()
            if (minutes >= 60) {
                val hours = ceil(minutes / 60.0).toInt()
                return L10n.string("Try again in %lld hours", language, hours)
            }
            if (seconds >= 600) {
                return L10n.string("Try again in %lld minutes", language, minutes)
            }
            return L10n.string("Try again in %@", language, "%02d:%02d".format(seconds / 60, seconds % 60))
        }
    }
}
