package com.shoo.app.features.onboarding

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.shoo.app.app.AppEnvironment
import com.shoo.app.app.DataConsent
import com.shoo.app.components.AvatarCatalog
import com.shoo.app.data.ExtensionStatus
import com.shoo.app.data.RepositoryError
import com.shoo.app.data.UserMode
import com.shoo.app.support.Log
import com.shoo.app.support.NotificationAuthorization
import kotlinx.coroutines.CancellationException

/**
 * ON-02: a name is 1–20 characters after trimming spaces. Characters are counted as the server and the database
 * count them (code points, `char_length`), so "👨‍👩‍👧" is 5 (BH-26): a name the app accepts must never come back as a
 * 422 that no retry can fix.
 */
object NameRule {
    /** Swift `enum Problem: Error`. A `Throwable`, so `validate` can return a Kotlin `Result` like Swift's. */
    sealed class Problem : Exception() {
        data object Empty : Problem()

        data object TooLong : Problem()
    }

    const val maxLength = 20

    /** Characters as the server counts them (backend `codePoints`). */
    fun length(name: String): Int = name.codePointCount(0, name.length)

    /** The trimmed name (`Result.success`), or why it is not allowed (`Result.failure` with a [Problem]). */
    fun validate(raw: String): Result<String> {
        // Control and bidi characters: the server refuses them (backend `displayName`), and a bidi override could
        // disguise a name in push text. Dropped here, so the name is sent without them.
        val cleaned = buildString {
            raw.codePoints().forEach { if (!isUnsafe(it)) appendCodePoint(it) }
        }
        val trimmed = cleaned.trim()
        // Zero-width characters would show as a blank name in "Hi, …" and the family list.
        val invisible = trimmed.codePoints().allMatch { cp ->
            Character.isWhitespace(cp) || Character.isSpaceChar(cp) ||
                Character.getType(cp).let { it == Character.FORMAT.toInt() || it == Character.CONTROL.toInt() }
        }
        if (invisible) return Result.failure(Problem.Empty)
        if (length(trimmed) > maxLength) return Result.failure(Problem.TooLong)
        return Result.success(trimmed)
    }

    /** The problem with `raw`, or null when it is a valid name. */
    fun problem(raw: String): Problem? = validate(raw).exceptionOrNull() as? Problem

    /** Backend `UNSAFE_TEXT`: `\p{Cc}`, U+200E, U+200F, U+202A–U+202E, U+2066–U+2069. */
    private fun isUnsafe(cp: Int): Boolean = when (cp) {
        0x200E, 0x200F, in 0x202A..0x202E, in 0x2066..0x2069 -> true
        else -> Character.getType(cp) == Character.CONTROL.toInt()
    }
}

/**
 * Onboarding screens in order (Figma "Flow" 1205:4696). Everyone starts as Pribadi (a Guardian with Family mode
 * off), also from an invite link (PR-03): the link's code waits in the router, and the join sheet opens with it once
 * onboarding is done (`AppEnvironment.finishOnboarding`).
 */
enum class OnboardingStep {
    /** ON-01 */
    SPLASH,
    /** ON-02 */
    NAME,
    /** ON-04, with the online check question (`DataConsent`) as a checkbox (Figma 1328:13421). */
    TURN_ON_EXTENSION,
    /** ON-04 passed (Figma "Jadikan Safari Default"). Android: make Firefox the default, Shoo only runs there. */
    SAFARI_DEFAULT,
    /** "Yeay, you're better protected!" Its Next asks for notifications (ON-05 has no screen of its own). */
    EXTENSION_ON,
    DONE,
}

/**
 * State of the whole onboarding flow (ON-01 … ON-05). The device registers on the first tap on ON-04, so until then
 * Back reaches the name. After that there is no way back to it, also not after a relaunch.
 */
class OnboardingModel(private val environment: AppEnvironment) {
    var step by mutableStateOf(OnboardingStep.SPLASH)
        private set
    var name by mutableStateOf("")

    /** ON-02 avatar picker. Sent as `avatarId` in `POST /devices` (#120); the response is the source of truth. */
    var selectedAvatarId by mutableStateOf(AvatarCatalog.memojiIds[0])

    private var checked by mutableStateOf(false)

    /**
     * ON-04 "Saya setuju halaman dicek secara online." Its Turn on stays off until it is ticked (Figma). Once this
     * screen saved the yes (`keepsConsentCheckbox`), the box is the saved answer: unticking it takes the consent back
     * (online checks off), ticking it again gives it again.
     */
    var consentChecked: Boolean
        get() = checked
        set(value) {
            val old = checked
            checked = value
            if (!keepsConsentCheckbox || value == old) return
            environment.setDataConsent(if (value) DataConsent.GRANTED else DataConsent.DECLINED)
        }

    /** The ON-04 checkbox answered the question on this screen: it stays visible after the answer is saved. */
    var keepsConsentCheckbox by mutableStateOf(false)
        private set

    /** The last step change was a Back tap, so the screens slide the other way. */
    var movedBack by mutableStateOf(false)
        private set

    /** The avatar from `POST /devices` (the pick, or random if the server did not keep it). */
    var avatarId by mutableStateOf<String?>(null)
        private set
    var isWorking by mutableStateOf(false)
        private set
    var registrationFailed by mutableStateOf(false)
        private set

    init {
        val settings = environment.settings
        // Left by an older build that registered invite joins during onboarding: nothing uses it any more.
        if (settings.inviteRegistrationPending) settings.inviteRegistrationPending = false
        // Registered earlier but onboarding not finished (app closed in between): Home shows what is still off.
        // An older build's Protected registration carries on at ON-04: Protected has no Home reminder (F-A14).
        step = when {
            settings.mode == null -> OnboardingStep.SPLASH
            settings.mode == UserMode.PROTECTED && !settings.onboardingCompleted -> OnboardingStep.TURN_ON_EXTENSION
            else -> OnboardingStep.DONE
        }
        checked = settings.dataConsent == DataConsent.GRANTED
    }

    val mode: UserMode? get() = environment.settings.mode

    val nameProblem: NameRule.Problem? get() = NameRule.problem(name)

    val canSubmitName: Boolean get() = nameProblem == null

    fun skipSplash() {
        if (step != OnboardingStep.SPLASH) return
        movedBack = false
        step = OnboardingStep.NAME
    }

    /** ON-02 Next: ON-04. An invite link's code stays in the router for after onboarding (PR-03). */
    fun submitName() {
        if (step != OnboardingStep.NAME || !canSubmitName || isWorking) return
        movedBack = false
        registrationFailed = false
        step = OnboardingStep.TURN_ON_EXTENSION
    }

    /** Back follows Figma: every step has one, except where it would undo a saved registration. */
    fun goBack() {
        if (isWorking) return
        step = when {
            step == OnboardingStep.NAME && mode == null -> OnboardingStep.SPLASH
            step == OnboardingStep.TURN_ON_EXTENSION && mode == null -> OnboardingStep.NAME
            step == OnboardingStep.SAFARI_DEFAULT -> OnboardingStep.TURN_ON_EXTENSION
            else -> return
        }
        movedBack = true
        registrationFailed = false
    }

    /** ON-04 shows Back until the device is registered (its name can no longer change here). */
    val canGoBackFromExtension: Boolean get() = mode == null

    /** Saves the device (`POST /devices`) as Pribadi, once. */
    suspend fun ensureRegistered() {
        if (mode != null) return
        val trimmed = NameRule.validate(name).getOrNull() ?: throw RepositoryError.Network
        avatarId = environment.register(name = trimmed, mode = UserMode.GUARDIAN, avatarId = selectedAvatarId).avatarId
        environment.settings.familyModeOn = false
    }

    /** ON-04 asks the question only when nothing answered it before (an earlier install's answer). Once ticked here it
     * stays on screen. */
    val showsConsentCheckbox: Boolean
        get() = environment.settings.dataConsent == null || keepsConsentCheckbox

    /** ON-04's buttons: on once the question is answered, here or before. */
    val canTurnOn: Boolean get() = !showsConsentCheckbox || consentChecked

    /**
     * ON-04 Turn on / Next: saves the ticked consent, then registers. A failure shows on the screen and the tap can be
     * repeated. `true` once Firefox may open.
     */
    suspend fun activateExtension(): Boolean {
        if (step != OnboardingStep.TURN_ON_EXTENSION || !canTurnOn || isWorking) return false
        // Only an unanswered question gets the checkbox's yes: a "no" given earlier is never overwritten.
        if (environment.settings.dataConsent == null) {
            environment.setDataConsent(DataConsent.GRANTED)
            keepsConsentCheckbox = true
        }
        if (mode != null) return true
        isWorking = true
        registrationFailed = false
        return try {
            ensureRegistered()
            true
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            Log.app.error("Registration failed", error)
            registrationFailed = true
            false
        } finally {
            isWorking = false
        }
    }

    /**
     * Called on appear and every time the app comes back to the foreground (ON-04). Moves on only once the device is
     * registered and the Shoo add-on is linked in Firefox (#135). After Back it stays, or Back would bounce straight
     * forward again; the screen then offers Next.
     */
    suspend fun refreshExtensionStatus(): ExtensionStatus? {
        if (step != OnboardingStep.TURN_ON_EXTENSION) return null
        val status = environment.extensionStatus()
        // The step may have moved on (Back) while Firefox was asked.
        if (step != OnboardingStep.TURN_ON_EXTENSION || status.nextStep != null || movedBack || mode == null || !canTurnOn) {
            return status
        }
        step = OnboardingStep.SAFARI_DEFAULT
        return status
    }

    /**
     * "Continue without checking", or Next after Back from Firefox Default, or when Shoo was already on before the
     * first tap.
     */
    suspend fun skipExtensionCheck() {
        if (!activateExtension()) return
        movedBack = false
        step = OnboardingStep.SAFARI_DEFAULT
    }

    /** Nothing can read the default browser for another app, so this trusts the user. */
    fun continueFromSafariDefault() {
        if (step != OnboardingStep.SAFARI_DEFAULT) return
        movedBack = false
        step = OnboardingStep.EXTENSION_ON
    }

    /**
     * ON-05, from Next on the success screen: asks once (Android 13+ `POST_NOTIFICATIONS`); whatever the answer,
     * onboarding ends (a Guardian who said no gets the Home reminder).
     */
    suspend fun requestNotifications() {
        if (step != OnboardingStep.EXTENSION_ON || isWorking) return
        isWorking = true
        try {
            if (environment.notifications.status() == NotificationAuthorization.NOT_DETERMINED) {
                environment.notifications.request()
            }
            environment.registerForPushIfAllowed()
            finish()
        } finally {
            isWorking = false
        }
    }

    /** UI-gate screenshots only: shows a step with sample data. */
    fun showForScreenshot(step: OnboardingStep) {
        // The name step starts empty, as in Figma "Atur Nama · kosong".
        name = if (step == OnboardingStep.NAME) "" else "Rina"
        // Figma's ON-04 has the checkbox; the mock has answered the question already.
        keepsConsentCheckbox = step == OnboardingStep.TURN_ON_EXTENSION
        avatarId = "avatar_05"
        movedBack = false
        this.step = step
    }

    /** The sample family (debug only since the Figma splash has no demo link). */
    fun startDemo() {
        environment.startDemo()
        step = OnboardingStep.DONE
    }

    private fun finish() {
        environment.finishOnboarding()
        step = OnboardingStep.DONE
    }
}
