package com.shoo.app.features.pairing

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.shoo.app.app.DeepLink
import com.shoo.app.data.APIErrorCode
import com.shoo.app.data.ApiRepository
import com.shoo.app.data.FamilyCode
import com.shoo.app.data.FamilyMember
import com.shoo.app.data.RepositoryError
import com.shoo.app.data.ShooRepository
import com.shoo.app.support.AppLanguage
import com.shoo.app.support.L10n
import com.shoo.app.support.Log
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.time.Duration.Companion.seconds

/**
 * GD-04: the guardian's family code (6 digits, valid 30 min, the same one while more than 5 min is left), the people
 * connected (x/3), and removing one. Main thread only, like Swift's `@MainActor`.
 *
 * `clearDeliveredPushes` (Android): iOS calls `DeliveredPushes.clear()` itself; here the screen hands in
 * `{ DeliveredPushes.clear(context) }`, since the model has no context.
 */
class FamilyCodeModel(
    private val repository: ShooRepository,
    private val now: () -> Instant = Instant::now,
    throttle: RefreshThrottle? = null,
    private val clearDeliveredPushes: () -> Unit = {},
) {
    sealed interface CodeState {
        data object Loading : CodeState
        data class Ready(val code: FamilyCode) : CodeState

        /** `503 code_unavailable` or no connection: "Try again". */
        data object Unavailable : CodeState

        /** 3 people connected: no code is asked for. */
        data object Full : CodeState
    }

    private val throttle: RefreshThrottle = throttle ?: RefreshThrottle.shared

    var codeState: CodeState by mutableStateOf(CodeState.Loading)
        private set
    var secondsLeft: Int by mutableIntStateOf(0)
        private set

    /** Seconds until "Refresh code" works again; 0 = now. */
    var replaceWait: Int by mutableIntStateOf(this.throttle.wait(now()))
        private set
    var members: List<FamilyMember> by mutableStateOf(emptyList())
        private set
    var membersFailed: Boolean by mutableStateOf(false)
        private set
    var removingId: String? by mutableStateOf(null)
        private set

    /** "Copied" on the button, for the code on screen only. */
    var copied: Boolean by mutableStateOf(false)
        private set

    /** Remove failed (catalog key); shown as an alert. */
    var actionError: String? by mutableStateOf(null)

    /** Local end of the current code (see `codeLifetime`). */
    private var expiry: Instant? = null
    private var ticks = 0

    /** Bumped by `remove`: a members answer asked for before it is out of date. */
    private var membersVersion = 0
    private var isLoadingMembers = false

    /** Code requests can overlap (the countdown's, the members refresh's, "Refresh code"), and an older answer may hold
     * the code a refresh just killed (fase 27k, F-A10). An answer changes the screen only when no newer one has, and no
     * newer request is still on its way. */
    private var codeRequests = 0
    private val codeRequestsInFlight = mutableSetOf<Int>()
    private var appliedCodeRequest = 0
    private var replacesInFlight = 0

    val isFull: Boolean get() = members.size >= maxMembers

    val code: FamilyCode? get() = (codeState as? CodeState.Ready)?.code

    /** The code's invite link, only when it is one of ours for this very code: the QR and the copied text never send
     * anyone elsewhere, whatever the server answers. */
    val inviteURL: String? get() = code?.let { checkedInviteURL(it) }

    /** Runs while the screen is open (`LaunchedEffect`): first code, then the countdown and new codes. */
    suspend fun run(sleep: suspend (kotlin.time.Duration) -> Unit = { delay(it) }) = coroutineScope {
        // Members first: a full family asks for no code (D-alief-C09).
        loadMembers()
        refreshCode()
        var membersRefresh: Job? = null
        try {
            while (isActive) {
                sleep(1.seconds)
                ticks += 1
                // Beside the countdown, so a slow answer never freezes it.
                if (ticks % membersInterval == 0 && !isLoadingMembers) {
                    membersRefresh = launch { loadMembers() }
                }
                if (tick()) refreshCode()
            }
        } finally {
            membersRefresh?.cancel()
        }
    }

    suspend fun loadMembers() {
        isLoadingMembers = true
        val version = membersVersion
        try {
            val fresh = repository.familyMembers()
            if (version != membersVersion) return
            members = fresh
            membersFailed = false
            if (isFull) {
                codeState = CodeState.Full
            } else if (codeState == CodeState.Full) {
                refreshCode()
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            Log.ui.error("Family members failed", error)
            membersFailed = true
        } finally {
            isLoadingMembers = false
        }
    }

    /** "Refresh code" works unless it was used in the last minute (or there is no code). */
    val canReplace: Boolean get() = code == null || replaceWait == 0

    /** "0:59": how long until "Refresh code" works again. */
    val replaceUnlocksIn: String get() = minuteSecond(replaceWait)

    /** Asks for the guardian's code. `replace` ("Refresh code") always gets a new one, and the old one stops working on
     * the server; otherwise the server hands back the active code. */
    suspend fun refreshCode(replace: Boolean = false) {
        if (isFull) {
            codeState = CodeState.Full
            return
        }
        // Waiting after the last refresh: the code on screen keeps working.
        if (replace) {
            replaceWait = throttle.wait(now())
            if (!canReplace) return
            throttle.record(now())
            replaceWait = throttle.wait(now())
        }
        // "Refresh code" on its way brings the new code; an ordinary request now could only bring back the old one.
        if (!replace && replacesInFlight > 0) return
        if (code == null) codeState = CodeState.Loading
        codeRequests += 1
        val request = codeRequests
        codeRequestsInFlight.add(request)
        if (replace) replacesInFlight += 1
        try {
            val fresh = repository.createFamilyCode(refresh = replace)
            // Screen closed meanwhile: the code is never shown. A newer request counts instead of this one.
            if (!currentCoroutineContext().isActive || !isNewestCodeAnswer(request)) return
            appliedCodeRequest = request
            val start = now()
            val validFor = Duration.between(start, fresh.expiresAt).toMillis() / 1000.0
            val lifetime = codeLifetime.toDouble()
            expiry = start.plusMillis(((if (validFor in 1.0..lifetime) validFor else lifetime) * 1000).toLong())
            // Members may have filled up while this was asked for.
            if (isFull) {
                codeState = CodeState.Full
                return
            }
            if (fresh.code != code?.code) copied = false
            codeState = CodeState.Ready(fresh)
            tick()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            if (!isNewestCodeAnswer(request)) return
            appliedCodeRequest = request
            Log.ui.error("Family code failed", error)
            // A code with time left stays on screen (rate_limited, no connection): it still works.
            if (code != null && !tick() && secondsLeft > 0) return
            expiry = null
            codeState = if (isFull) CodeState.Full else CodeState.Unavailable
            secondsLeft = 0
        } finally {
            codeRequestsInFlight.remove(request)
            if (replace) replacesInFlight -= 1
        }
    }

    private fun isNewestCodeAnswer(request: Int): Boolean =
        request > appliedCodeRequest && codeRequestsInFlight.none { it > request }

    /** "29:59": what is left of the code on screen. */
    val timeLeft: String get() = minuteSecond(secondsLeft)

    /** Updates the countdown; `true` when the code just ran out. */
    fun tick(): Boolean {
        replaceWait = throttle.wait(now())
        val end = expiry
        if (codeState !is CodeState.Ready || end == null) return false
        val left = Duration.between(now(), end).toMillis() / 1000.0
        // A clock set back never shows more than the code's lifetime.
        secondsLeft = min(codeLifetime.toInt(), max(0, ceil(left).toInt()))
        return secondsLeft == 0
    }

    suspend fun remove(member: FamilyMember) {
        if (removingId != null) return
        removingId = member.deviceId
        try {
            try {
                repository.removeMember(member.deviceId)
            } catch (error: CancellationException) {
                throw error
            } catch (error: RepositoryError.Api) {
                // Already gone (they left, or an earlier answer got lost).
                if (error.code != APIErrorCode.notFound) {
                    Log.ui.error("Remove member failed", error)
                    actionError = "Couldn't remove. Check your connection and try again."
                    return
                }
            } catch (error: Throwable) {
                Log.ui.error("Remove member failed", error)
                actionError = "Couldn't remove. Check your connection and try again."
                return
            }
            membersVersion += 1
            members = members.filter { it.deviceId != member.deviceId }
            // Their notifications go too; one call can't pick a person's, so the shade is cleared (C18).
            clearDeliveredPushes()
            if (codeState == CodeState.Full) refreshCode()
        } finally {
            removingId = null
        }
    }

    /** "Copy invite link": the text people paste into WhatsApp. `pasteboard`: the system clipboard by default
     * (`SystemPasteboard`, installed by the screens and the app). */
    fun copyInvite(language: AppLanguage, pasteboard: PasteboardWriting? = SystemPasteboard.shared): Boolean {
        val code = code ?: return false
        if (inviteURL == null || pasteboard == null) return false
        copy(inviteText(code, language), code.expiresAt, pasteboard, now())
        copied = true
        return true
    }

    companion object {
        /** Longest a code lives (contracts/api.md), in seconds. Must equal `CODE_TTL_SECONDS` on the backend. */
        val codeLifetime: Long = ApiRepository.codeLifetimeSeconds

        /** After "Refresh code", the button waits this long (issue #227). */
        const val replaceCooldown = 60

        /** Members are re-read this often, so someone joining shows up while the code is on screen. */
        const val membersInterval = 5

        /** iOS `FamilyShieldModel.maxMembers` (Shield feature), kept here so Pairing builds on its own. */
        private const val maxMembers = 3

        fun checkedInviteURL(code: FamilyCode): String? =
            if (DeepLink.from(code.inviteUrl) == DeepLink.Join(code.code)) code.inviteUrl else null

        /** "482 193": two groups of three, easier to read out and type than six loose digits. */
        fun display(code: String): String =
            if (code.length == DeepLink.codeLength) "${code.take(3)} ${code.takeLast(3)}" else code

        fun inviteText(code: FamilyCode, language: AppLanguage): String = L10n.string(
            "Join my family on Shoo so I can help keep you safe from scam sites. Open %@ or enter code %@ in Shoo.",
            language,
            code.inviteUrl,
            code.code,
        )

        /** This device only, gone when the code expires (SECURITY §3 P8). */
        fun copy(text: String, expiry: Instant, pasteboard: PasteboardWriting, now: Instant) {
            val lifetime = min(max(Duration.between(now, expiry).toMillis(), 1_000L), codeLifetime * 1000)
            pasteboard.setText(text, now.plusMillis(lifetime))
        }

        private fun minuteSecond(seconds: Int): String = "%d:%02d".format(seconds / 60, seconds % 60)
    }
}

/** When "Refresh code" was last used on this device, in memory only. Home, Profile and onboarding each have their own
 * `FamilyCodeModel`; they share this, so the wait is per device (issue #227). */
class RefreshThrottle {
    private var lastAt: Instant? = null

    fun record(now: Instant) {
        lastAt = now
    }

    /** Seconds left of the wait. A clock set back since the last refresh ends it. */
    fun wait(now: Instant): Int {
        val last = lastAt ?: return 0
        if (now.isBefore(last)) return 0
        val left = FamilyCodeModel.replaceCooldown - Duration.between(last, now).toMillis() / 1000.0
        return max(0, ceil(left).toInt())
    }

    companion object {
        val shared = RefreshThrottle()
    }
}

/** iOS `PasteboardWriting`: where "Copy invite link" writes, with the time the copy must be gone by. */
fun interface PasteboardWriting {
    fun setText(text: String, expiresAt: Instant)
}

/**
 * The system clipboard. Android has no expiring clip (iOS `.expirationDate`): the clip is cleared at `expiresAt` if
 * it is still ours and the app still runs. iOS `.localOnly` has no Android counterpart (no shared clipboard to leave).
 */
class ClipboardPasteboard(context: Context) : PasteboardWriting {
    private val clipboard: ClipboardManager? = context.applicationContext.getSystemService(ClipboardManager::class.java)
    private val handler = Handler(Looper.getMainLooper())

    override fun setText(text: String, expiresAt: Instant) {
        val clipboard = clipboard ?: return
        clipboard.setPrimaryClip(ClipData.newPlainText("Shoo", text))
        val delay = Duration.between(Instant.now(), expiresAt).toMillis().coerceAtLeast(0)
        handler.postDelayed({
            val current = try {
                clipboard.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text?.toString()
            } catch (_: Exception) {
                null
            }
            if (current != text) return@postDelayed
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                clipboard.clearPrimaryClip()
            } else {
                clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
            }
        }, delay)
    }
}

/** The default clipboard for `copyInvite` (iOS `UIPasteboard.general`). Installed with the app context by the Pairing
 * screens; the app may install it at start too (`SystemPasteboard.install(this)` in `ShooApp.onCreate`). */
object SystemPasteboard {
    @Volatile
    var shared: PasteboardWriting? = null
        private set

    fun install(context: Context) {
        if (shared == null) shared = ClipboardPasteboard(context)
    }
}
