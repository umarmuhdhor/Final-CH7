package com.shoo.app.features.profile

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.shoo.app.app.AppSettings
import com.shoo.app.app.InMemoryPreferences
import com.shoo.app.data.APIErrorCode
import com.shoo.app.data.DeviceProfile
import com.shoo.app.data.DeviceUpdate
import com.shoo.app.data.FamilyMember
import com.shoo.app.data.LinkedAccountSettings
import com.shoo.app.data.LoadFailure
import com.shoo.app.data.NotificationSettings
import com.shoo.app.data.NotificationSettingsUpdate
import com.shoo.app.data.RepositoryError
import com.shoo.app.data.ShooRepository
import com.shoo.app.data.UserMode
import com.shoo.app.features.onboarding.NameRule
import com.shoo.app.support.AppLanguage
import com.shoo.app.support.Formatters
import com.shoo.app.support.L10n
import com.shoo.app.support.Log
import com.shoo.app.support.NotificationAuthorization
import com.shoo.app.support.NotificationPermission
import com.shoo.app.support.isCancellation
import com.shoo.app.support.t
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Date
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Swift `String.LocalizationValue`: a catalog key with its interpolated values, looked up in the in-app language
 * when shown (`text()` in composition, `string(language)` outside).
 */
class LocalizationValue(val key: String, vararg val args: Any) {
    fun string(language: AppLanguage): String = L10n.string(key, language, *args)

    override fun equals(other: Any?): Boolean =
        other is LocalizationValue && other.key == key && other.args.contentEquals(args)

    override fun hashCode(): Int = 31 * key.hashCode() + args.contentHashCode()

    override fun toString(): String = key
}

/** `Text(verbatim: L10n.string(value, language:))` in composition. */
@Composable
fun LocalizationValue.text(): String = t(key, *args)

/**
 * Profile (PF-01) for both modes: name, language, the guardian link (Protected) or the family (Guardian).
 * Figma has three variants: Pribadi (Guardian, Family mode off), Guardian (Family mode on), Protected.
 */
class ProfileModel(
    private val repository: ShooRepository,
    private val settings: AppSettings,
    private val notifications: NotificationPermission? = null,
    linked: LinkedAccountSettings? = null,
    private val now: () -> Instant = Instant::now,
) {
    enum class State { LOADING, LOADED, FAILED }

    enum class Variant {
        /** Guardian with Family mode off: protects only themself. */
        PERSONAL,
        /** Guardian with Family mode on. */
        GUARDIAN,
        PROTECTED,
    }

    var state by mutableStateOf(State.LOADING)
        private set
    var profile by mutableStateOf<DeviceProfile?>(null)
        private set
    /** Guardian only: the people connected (x/3). */
    var members by mutableStateOf<List<FamilyMember>>(emptyList())
        private set
    /** The family list could not be read; the rest of Profile still works. */
    var membersFailed by mutableStateOf(false)
        private set
    /** The last family list read in this Profile session worked, so `members` is the family (PF-01, #494). */
    var membersLoaded by mutableStateOf(false)
        private set
    /** Why the profile (`state == FAILED`) or the family list (`membersFailed`) could not be read (A-03). */
    var loadFailure by mutableStateOf(LoadFailure.CONNECTION)
        private set
    var membersLoadFailure by mutableStateOf(LoadFailure.CONNECTION)
        private set
    var isWorking by mutableStateOf(false)
        private set
    /** Counts the name and avatar saves the server confirmed, so the view gives a success haptic. */
    var profileSaves by mutableIntStateOf(0)
        private set
    /** Why the name was not saved; cleared as soon as the name is edited. */
    var nameError by mutableStateOf<LocalizationValue?>(null)
        private set
    /** Disconnect / delete / language failures, shown as an alert. */
    var actionError by mutableStateOf<LocalizationValue?>(null)

    private var _nameDraft by mutableStateOf("")
    var nameDraft: String
        get() = _nameDraft
        set(value) {
            val old = _nameDraft
            _nameDraft = value
            if (value != old) nameError = null
        }

    /** The running language sync; a newer choice cancels it. Swift `languageTask`. */
    var languageTask: Job? = null
        private set

    /** Runs the language sync, which outlives the page like Swift's unstructured `Task`. */
    private val scope = MainScope()

    /** "Hapus akun" sheet: who loses what. */
    fun deleteMessage(language: AppLanguage): String {
        // Figma 1115:14271 "Hapus akun?".
        var text = L10n.string(
            "Everything in this app, including your profile, history and family links, is deleted for good and can't be recovered.",
            language,
        )
        when (variant) {
            Variant.GUARDIAN, Variant.PERSONAL -> {
                if (!membersLoaded) {
                    // #494: the list did not load, so the count is unknown. Say it without one; delete stays allowed.
                    text += " " + L10n.string("Anyone you protect will be disconnected.", language)
                } else if (members.isNotEmpty()) {
                    text += " " + L10n.string("%lld people you protect will be disconnected.", language, members.size)
                }
            }
            Variant.PROTECTED -> {
                profile?.guardian?.let { guardian ->
                    text += " " + L10n.string("%@ will no longer get your warnings.", language, guardian.name)
                }
            }
        }
        return text
    }

    /** Called right before disconnect or delete hands the app back to onboarding (close the sheet, clear pushed screens). */
    var onSessionEnd: () -> Unit = {}

    /**
     * Android: iOS calls the static `AppEnvironment.forgetDeletedDevice(linked:)`; here it is an `AppEnvironment` method
     * (it also clears the App Group counters), so the view sets this to `env::forgetDeletedDevice`.
     */
    var onForgetDevice: (LinkedAccountSettings) -> Unit = { it.clear() }

    /** "Notifikasi" row: Aktif / Mati. */
    var notificationStatus by mutableStateOf<NotificationAuthorization?>(null)
        private set

    /** Protected "Akun Tertaut", "Link terblokir" and the "Situs diperiksa" counter (App Group, proposed keys). */
    val linked: LinkedAccountSettings = linked ?: LinkedAccountSettings(InMemoryPreferences())

    /** The last notification update that changed each key: a failed update puts back only the keys no newer update has
     * changed since (fase 27i, K11). Counted, not compared by value: off → on → off is three writers. */
    private val notificationWriters = mutableMapOf<NotificationSettingsUpdate.Key, Int>()
    private var notificationUpdates = 0
    /** Switch saves still waiting for the server; a profile read that answers meanwhile can be older than the screen. */
    private var notificationSavesInFlight = 0

    val variant: Variant
        get() = when (settings.mode) {
            UserMode.PROTECTED -> Variant.PROTECTED
            else -> if (settings.familyModeOn) Variant.GUARDIAN else Variant.PERSONAL
        }

    /** "Mode akun": Pribadi ↔ Guardian is Family mode (members stay connected, D Q5). */
    fun setFamilyMode(on: Boolean) {
        if (settings.mode != UserMode.GUARDIAN) return
        settings.familyModeOn = on
    }

    // MARK: Stats

    /** Calendar days since `date`, counting today (registered today = 1). */
    fun days(since: Instant, zone: ZoneId = ZoneId.systemDefault()): Int {
        val start = since.atZone(zone).toLocalDate()
        val today = now().atZone(zone).toLocalDate()
        return maxOf(1, ChronoUnit.DAYS.between(start, today).toInt() + 1)
    }

    /**
     * Pribadi and Protected: days protected, blocked, sites checked ("—" until the extension counts them).
     * Guardian (Figma 1115:14611): days since the earliest member still connected, the members' blocked and warning
     * totals. Empty when the server sends no stats, or a guardian protects nobody yet (the strip is hidden).
     */
    fun stats(language: AppLanguage): List<ProfileStat> {
        val format = NumberFormat.getIntegerInstance(language.locale)
        val number = { n: Int -> format.format(n.toLong()) }
        return when (variant) {
            Variant.PERSONAL, Variant.PROTECTED -> {
                val stats = profile?.stats ?: return emptyList()
                listOf(
                    ProfileStat(value = number(days(stats.since)), label = "Days protected"),
                    ProfileStat(value = number(stats.blocked), label = "Blocked"),
                    ProfileStat(value = linked.checkedCount?.let(number) ?: "—", label = "Checked"),
                )
            }
            Variant.GUARDIAN -> {
                if (membersFailed || members.isEmpty() || !members.all { it.stats != null }) return emptyList()
                val since = members.mapNotNull { it.connectedAt }.minOrNull()
                listOf(
                    ProfileStat(value = since?.let { number(days(it)) } ?: number(0), label = "Days protecting"),
                    ProfileStat(value = number(members.sumOf { it.stats?.blocked ?: 0 }), label = "Blocked"),
                    ProfileStat(value = number(members.sumOf { it.stats?.warnings ?: 0 }), label = "Warnings"),
                )
            }
        }
    }

    /** "@adhella": the name in lower case without spaces (Kelola profil "Username"). */
    val username: String
        get() = "@" + (profile?.name ?: "").lowercase().filterNot { it.isWhitespace() }

    /** "Mode Pribadi" / "Mode Guardian" (Figma 1115:14409 "Handle"). Protected has none (Figma). */
    fun handle(language: AppLanguage): String = when (variant) {
        Variant.PROTECTED -> ""
        Variant.PERSONAL -> L10n.string("Personal mode", language)
        Variant.GUARDIAN -> L10n.string("Guardian mode", language)
    }

    /** Kelola profil "Status" (Figma 1278:12092 "Pengguna pengawas"). A catalog key. */
    val statusTitle: String
        get() = when (variant) {
            Variant.GUARDIAN -> "Guardian user"
            Variant.PERSONAL -> "Personal user"
            Variant.PROTECTED -> "Protected user"
        }

    // MARK: Notifications

    suspend fun refreshNotifications() {
        notificationStatus = notifications?.status()
    }

    /** "Notifikasi": asks in the app the first time; `true` when only Settings can change it now. */
    suspend fun notificationsTapped(): Boolean {
        val notifications = notifications ?: return true
        return when (notifications.status()) {
            NotificationAuthorization.NOT_DETERMINED -> {
                notificationStatus = notifications.request()
                false
            }
            NotificationAuthorization.DENIED, NotificationAuthorization.AUTHORIZED -> true
        }
    }

    val showsFamilyCode: Boolean get() = settings.mode == UserMode.GUARDIAN

    /** "Aktif sejak 20 Juni" (Protected Kelola profil): when this device registered. */
    fun activeSince(language: AppLanguage): String? {
        val since = profile?.stats?.since ?: return null
        val date = Formatters.dateFormatter("MMMMd", language, ZoneId.systemDefault()).format(Date.from(since))
        return L10n.string("Active since %@", language, date)
    }

    // MARK: Mode Guardian card (Pribadi)

    val showsGuardianCard: Boolean get() = variant == Variant.PERSONAL && !settings.guardianCardDismissed

    /** "Menjadi Guardian": Family mode on, so Profile turns into the Guardian layout. */
    fun becomeGuardian() = setFamilyMode(true)

    fun dismissGuardianCard() {
        settings.guardianCardDismissed = true
    }

    /** Same rule as ON-02. */
    val nameProblem: NameRule.Problem?
        get() = NameRule.problem(nameDraft)

    suspend fun load() {
        val savesBefore = notificationUpdates
        try {
            var me = repository.me()
            // A switch flipped while this read was out: the read may be from before its save. Keep the switches on
            // screen; the next read catches up.
            val shown = profile?.notifications
            if ((notificationUpdates != savesBefore || notificationSavesInFlight > 0) && shown != null) {
                me = me.copy(notifications = shown)
            }
            // Keep a name the user is still editing.
            if (nameDraft.isEmpty() || nameDraft == profile?.name) nameDraft = me.name
            profile = me
            state = State.LOADED
            // The server missed the last language change (offline then): send it again.
            if (me.language != settings.language.code) chooseLanguage(settings.language, force = true)
        } catch (error: Exception) {
            if (error.isCancellation) throw error
            Log.ui.error("Profile load failed", error)
            if (state != State.LOADED) {
                loadFailure = LoadFailure.from(error)
                state = State.FAILED
            }
            return
        }
        if (settings.mode != UserMode.GUARDIAN) return
        try {
            members = repository.familyMembers()
            membersFailed = false
            membersLoaded = true
        } catch (error: Exception) {
            if (error.isCancellation) throw error
            Log.ui.error("Profile members failed", error)
            membersLoadFailure = LoadFailure.from(error)
            membersFailed = true
            membersLoaded = false
        }
    }

    /** "Try again": shows the spinner while it retries. */
    suspend fun retry() {
        state = State.LOADING
        load()
    }

    /** Saves the edited name; `false` when it breaks the rule or the server says no (old name stays). */
    suspend fun saveName(): Boolean {
        val trimmed = NameRule.validate(nameDraft).getOrNull()
        if (trimmed == null || isWorking) return false
        nameError = null
        isWorking = true
        try {
            repository.updateMe(DeviceUpdate(name = trimmed))
            profile = profile?.copy(name = trimmed)
            nameDraft = trimmed
            profileSaves += 1
            return true
        } catch (error: Exception) {
            if (error.isCancellation) throw error
            Log.ui.error("Name save failed", error)
            nameError = LocalizationValue("Couldn't save. Check your connection and try again.")
            return false
        } finally {
            isWorking = false
        }
    }

    /** The app switches at once; the server learns it for localized pushes (D-alief-05). Only the newest choice is sent. */
    fun chooseLanguage(language: AppLanguage, force: Boolean = false) {
        if (!force && language == settings.language) return
        settings.language = language
        languageTask?.cancel()
        languageTask = scope.launch {
            try {
                repository.updateMe(DeviceUpdate(language = language.code))
                if (!isActive) return@launch
                profile = profile?.copy(language = language.code)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (!isActive) return@launch
                // The app keeps the choice; `load()` sends it again next time.
                Log.ui.error("Language save failed", error)
                actionError = LocalizationValue("Couldn't save. Check your connection and try again.")
            }
        }
    }

    /** "Ingatkan" (PF-01 proposed): a message to announce, or the "sent" one. Marks the member as reminded. */
    suspend fun remind(member: FamilyMember): LocalizationValue {
        val result = MemberActions.remind(member, repository)
        if (result == null) {
            val at = now()
            members = members.map { if (it.deviceId == member.deviceId) it.copy(remindedAt = at) else it }
        }
        // Shown as an alert too: the announcement alone reaches only TalkBack.
        if (result != null) actionError = result
        return result ?: LocalizationValue("Reminder sent to %@", member.name)
    }

    // MARK: Pengaturan/Notifikasi

    /** What the notification page shows: the server's settings, or its defaults before the first load. */
    val notificationSettings: NotificationSettings
        get() = profile?.notifications ?: NotificationSettings.defaults

    /** Changes at once; the server decides which pushes go out, so a failed save goes back and says so. */
    suspend fun updateNotifications(update: NotificationSettingsUpdate) {
        if (profile == null) return
        val before = notificationSettings
        val after = before.applying(update)
        // Start = end is "all day" on the server, which the sheet never offers (fase 27i, F-N6).
        if ((update.quietStart != null || update.quietEnd != null) && !canSaveQuietHours(after.quietStart, after.quietEnd)) {
            Log.ui.error("Quiet hours with the same start and end not sent")
            return
        }
        notificationUpdates += 1
        val token = notificationUpdates
        for (key in update.keys) notificationWriters[key] = token
        profile = profile?.copy(notifications = after)
        notificationSavesInFlight += 1
        try {
            repository.updateMe(DeviceUpdate(notifications = update))
        } catch (error: Exception) {
            if (error.isCancellation) throw error
            Log.ui.error("Notification settings save failed", error)
            // Only this update's keys go back, on top of what is on screen now: a switch that saved meanwhile stays.
            val owned = update.keys.filter { notificationWriters[it] == token }.toSet()
            val reverted = notificationSettings.reverting(owned, before)
            profile = profile?.copy(notifications = reverted)
            actionError = LocalizationValue("Couldn't save. Check your connection and try again.")
        } finally {
            notificationSavesInFlight -= 1
        }
    }

    // MARK: Kelola profil

    /** "Ubah foto": one of the onboarding avatars. `false` (old avatar stays) when the server says no. */
    suspend fun chooseAvatar(avatarId: String): Boolean {
        if (avatarId == profile?.avatarId || isWorking) return avatarId == profile?.avatarId
        isWorking = true
        try {
            repository.updateMe(DeviceUpdate(avatarId = avatarId))
            profile = profile?.copy(avatarId = avatarId)
            profileSaves += 1
            return true
        } catch (error: Exception) {
            if (error.isCancellation) throw error
            Log.ui.error("Avatar save failed", error)
            actionError = LocalizationValue("Couldn't save. Check your connection and try again.")
            return false
        } finally {
            isWorking = false
        }
    }

    /** Protected's Account row (BH-29): the page says "Not connected to a guardian yet" when no Guardian is linked,
     * so the row must not read "Connected" then. A catalog key. */
    val connectionRowTitle: String get() = if (hasNoGuardian) "Not connected" else "Connected"

    /**
     * "Punya kode undangan?": a guardian who protects nobody (the server turns this phone into a protected one), or a
     * protected person whose guardian is gone, who joins with the code as they are (QA 2026-11-10 #4).
     */
    val canJoinAnotherFamily: Boolean
        get() = when (settings.mode) {
            UserMode.GUARDIAN -> members.isEmpty() && !membersFailed
            UserMode.PROTECTED -> hasNoGuardian
            null -> false
        }

    /** Protected with nobody looking after them: Profile offers Connect again. */
    val hasNoGuardian: Boolean
        get() = settings.mode == UserMode.PROTECTED && state == State.LOADED && profile?.guardian == null

    /** SECURITY §3 P3: gone on the server first, then a fresh install here (onboarding from the start). */
    suspend fun deleteMyData(): Boolean {
        if (isWorking) return false
        isWorking = true
        try {
            try {
                repository.deleteMe()
            } catch (error: Exception) {
                if (error.isCancellation) throw error
                val code = (error as? RepositoryError.Api)?.code
                // Already deleted (an earlier answer got lost): same end state.
                if (code != APIErrorCode.notFound && code != APIErrorCode.unauthorized) {
                    Log.ui.error("Delete data failed", error)
                    actionError = LocalizationValue("Couldn't delete your data. Check your connection and try again.")
                    return false
                }
            }
            // `ApiRepository.deleteMe` has already cleared the Keystore token and App Group session keys.
            onForgetDevice(linked)
            onSessionEnd()
            settings.reset()
            return true
        } finally {
            isWorking = false
        }
    }

    companion object {
        /** "Jam tenang" Save: a window, not "all day" (the server reads start = end as the whole day). */
        fun canSaveQuietHours(start: String, end: String): Boolean = start != end
    }
}
