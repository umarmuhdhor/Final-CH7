package com.shoo.app.app

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import com.shoo.app.components.AppTheme
import com.shoo.app.components.TextSizeLevel
import com.shoo.app.data.UserMode
import com.shoo.app.support.AppLanguage
import kotlin.properties.ReadWriteProperty
import kotlin.reflect.KProperty
import org.json.JSONArray

/**
 * Apple 5.1.1(ii), 5.1.2(i): the person's answer to the online check. It covers `/analyze`: page text sent to Shoo's
 * server, and the summary of a suspicious page sent to DeepSeek. Until they answer, nothing goes.
 */
enum class DataConsent(val rawValue: String) {
    GRANTED("granted"),
    DECLINED("declined");

    companion object {
        fun from(raw: String?): DataConsent? = entries.firstOrNull { it.rawValue == raw }
    }
}

/**
 * App-only preferences (not shared with the extension). Persisted in the app's own `SharedPreferences`; the App
 * Group prefs hold only the contract keys (SECURITY §3 P4). Every field is Compose state: screens that read it
 * recompose when it changes (iOS `@Observable`).
 *
 * Debug launch extras override the stored values once at start (see `AppEnvironment.live`).
 */
class AppSettings(private val defaults: SharedPreferences) {
    constructor(context: Context) : this(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE))

    object Keys {
        const val language = "settings.language"
        const val mode = "settings.mode"
        const val onboardingCompleted = "settings.onboardingCompleted"
        const val familyModeOn = "settings.familyModeOn"
        const val onboardingConnectPassed = "settings.onboardingConnectPassed"
        const val dataConsent = "settings.dataConsent"
        const val inviteRegistrationPending = "settings.inviteRegistrationPending"
        /** Before the text size slider: "Teks besar" on/off. Read once to pick the slider's start. */
        const val largeText = "settings.largeText"
        const val theme = "settings.theme"
        const val textSize = "settings.textSize"
        const val boldText = "settings.boldText"
        const val highContrast = "settings.highContrast"
        const val reduceMotion = "settings.reduceMotion"
        const val reduceGlass = "settings.reduceGlass"
        const val haptics = "settings.haptics"
        const val readAloud = "settings.readAloud"
        const val demoMode = "settings.demoMode"

        const val dismissedHomeScanIds = "settings.dismissedHomeScanIds"
        const val guardianCardDismissed = "settings.guardianCardDismissed"
        const val supervisedCardDismissed = "settings.supervisedCardDismissed"
        const val guardianIntroSeen = "settings.guardianIntroSeen"

        val all = listOf(
            language, mode, onboardingCompleted, familyModeOn, onboardingConnectPassed, dataConsent,
            inviteRegistrationPending, largeText,
            theme, textSize, boldText, highContrast, reduceMotion, reduceGlass, haptics, readAloud,
            dismissedHomeScanIds, guardianCardDismissed, supervisedCardDismissed, guardianIntroSeen, demoMode,
        )
    }

    /** A Compose-observed value written to `defaults` on every set (Swift `didSet`). */
    private inner class Stored<T>(initial: T, private val write: (SharedPreferences.Editor, T) -> Unit) :
        ReadWriteProperty<Any?, T> {
        private val state: MutableState<T> = mutableStateOf(initial)

        override fun getValue(thisRef: Any?, property: KProperty<*>): T = state.value

        override fun setValue(thisRef: Any?, property: KProperty<*>, value: T) {
            state.value = value
            val editor = defaults.edit()
            write(editor, value)
            editor.apply()
        }
    }

    private fun bool(key: String, initial: Boolean) = Stored(initial) { e, v: Boolean -> e.putBoolean(key, v) }

    var language: AppLanguage by Stored(
        AppLanguage.entries.firstOrNull { it.rawValue == defaults.getString(Keys.language, null) } ?: AppLanguage.defaultLanguage,
    ) { e, v -> e.putString(Keys.language, v.rawValue) }

    /** Chosen once in ON-03, never changes (`chooseMode`). Also written to the App Group (`device.mode`) by the session. */
    var mode: UserMode? by Stored(UserMode.from(defaults.getString(Keys.mode, null))) { e, v ->
        if (v == null) e.remove(Keys.mode) else e.putString(Keys.mode, v.rawValue)
    }
        private set

    var onboardingCompleted: Boolean by bool(Keys.onboardingCompleted, defaults.getBoolean(Keys.onboardingCompleted, false))

    /** Protected passed the Connect step of onboarding (resume point after a relaunch). */
    var onboardingConnectPassed: Boolean by bool(Keys.onboardingConnectPassed, defaults.getBoolean(Keys.onboardingConnectPassed, false))

    /**
     * Fase 27d (K6): onboarding registered this device for an invite join that has not succeeded yet. While set, Back
     * or "Not now" on Connect deletes the device again (a Protected mode is for good on the server), and an
     * `already_connected` answer means an earlier join went through. Cleared by a join, a cancel, or at launch when no
     * mode was saved (the app died during `POST /devices`).
     */
    var inviteRegistrationPending: Boolean by bool(Keys.inviteRegistrationPending, defaults.getBoolean(Keys.inviteRegistrationPending, false))

    /** null = not asked yet. Change it through `AppEnvironment.setDataConsent`, which also tells the session. */
    var dataConsent: DataConsent? by Stored(DataConsent.from(defaults.getString(Keys.dataConsent, null))) { e, v ->
        if (v == null) e.remove(Keys.dataConsent) else e.putString(Keys.dataConsent, v.rawValue)
    }

    /** GD-02: the guardian's last Family mode toggle. */
    var familyModeOn: Boolean by bool(Keys.familyModeOn, defaults.getBoolean(Keys.familyModeOn, false))

    // PF-01 Tema and Aksesibilitas. Applied to every screen by `ShooAppearance` (RootView).

    var theme: AppTheme by Stored(AppTheme.fromRaw(defaults.getString(Keys.theme, null))) { e, v -> e.putString(Keys.theme, v.rawValue) }

    var textSize: TextSizeLevel by Stored(
        if (defaults.contains(Keys.textSize)) {
            TextSizeLevel.fromRaw(defaults.getInt(Keys.textSize, TextSizeLevel.STANDARD.rawValue))
        } else {
            // The old "Teks besar" switch meant at least xLarge.
            if (defaults.getBoolean(Keys.largeText, false)) TextSizeLevel.LARGE else TextSizeLevel.STANDARD
        },
    ) { e, v -> e.putInt(Keys.textSize, v.rawValue) }

    var boldText: Boolean by bool(Keys.boldText, defaults.getBoolean(Keys.boldText, false))

    var highContrast: Boolean by bool(Keys.highContrast, defaults.getBoolean(Keys.highContrast, false))

    /** "Kurangi gerakan": no animated transitions in Shoo (the phone's "Remove animations" also counts). */
    var reduceMotion: Boolean by bool(Keys.reduceMotion, defaults.getBoolean(Keys.reduceMotion, false))

    /** "Kurangi efek kaca": solid backgrounds instead of glass. */
    var reduceGlass: Boolean by bool(Keys.reduceGlass, defaults.getBoolean(Keys.reduceGlass, false))

    /** "Getar": a warning haptic when a warning reaches you in the app. */
    var haptics: Boolean by bool(Keys.haptics, defaults.getBoolean(Keys.haptics, true))

    /** "Bacakan peringatan": TalkBack reads the score and reasons when a warning opens. */
    var readAloud: Boolean by bool(Keys.readAloud, defaults.getBoolean(Keys.readAloud, false))

    /** GD-01: scans whose Home card the guardian closed with X. Ids only, newest last, at most 50. */
    var dismissedHomeScanIds: List<String> by Stored(readIds(defaults.getString(Keys.dismissedHomeScanIds, null))) { e, v ->
        e.putString(Keys.dismissedHomeScanIds, JSONArray(v).toString())
    }
        private set

    /** PF-01 Pribadi: the "Mode Guardian" card was closed with X (never shown again on this phone). */
    var guardianCardDismissed: Boolean by bool(Keys.guardianCardDismissed, defaults.getBoolean(Keys.guardianCardDismissed, false))

    /** Home's "Mode Terawasi" card (Pribadi without family, protected without a guardian) was closed with X. */
    var supervisedCardDismissed: Boolean by bool(Keys.supervisedCardDismissed, defaults.getBoolean(Keys.supervisedCardDismissed, false))

    /** Figma "To be guardian" was passed with "Mulai" once; Family mode then turns on without it. */
    var guardianIntroSeen: Boolean by bool(Keys.guardianIntroSeen, defaults.getBoolean(Keys.guardianIntroSeen, false))

    /** "Try the demo": sample data on this phone, no device on the server. Read at launch (`AppEnvironment.live`). */
    var demoMode: Boolean by bool(Keys.demoMode, defaults.getBoolean(Keys.demoMode, false))
        private set

    /** Hides a scan's Home card for good. Old ids drop off; a scan older than 24 h has no card anyway. */
    fun dismissHomeScan(scanId: String) {
        if (scanId in dismissedHomeScanIds) return
        dismissedHomeScanIds = (dismissedHomeScanIds + scanId).takeLast(50)
    }

    /** A Guardian with a family, straight to the tabs. Fixtures only, so the data question has nothing to ask. */
    fun enterDemo() {
        demoMode = true
        mode = UserMode.GUARDIAN
        familyModeOn = true
        guardianIntroSeen = true
        dataConsent = DataConsent.GRANTED
        onboardingCompleted = true
    }

    /** Saves the ON-03 choice. Returns `false` and changes nothing when a mode is already saved. */
    fun chooseMode(mode: UserMode): Boolean {
        if (this.mode != null) return false
        this.mode = mode
        return true
    }

    /** PF-01 "Punya kode undangan?": this phone now protected by another guardian (a new device on the server; the
     * mode itself never changes on a device). Family mode belongs to guardians. */
    fun becameProtected() {
        mode = UserMode.PROTECTED
        familyModeOn = false
        onboardingConnectPassed = true
    }

    /** Fase 27d (K6): the device from a failed invite join was deleted on the server. Onboarding starts over from the
     * name: the mode and Connect progress go. The language and the consent answer were the person's own choices, so
     * they stay (unlike `reset()`). */
    fun forgetInviteRegistration() {
        mode = null
        onboardingConnectPassed = false
        inviteRegistrationPending = false
    }

    /** Back to a fresh install (used by "Delete my data" and by tests). */
    fun reset() {
        clear(defaults)
        // The setters below write their defaults back, as Swift's `didSet` does.
        language = AppLanguage.defaultLanguage
        mode = null
        onboardingCompleted = false
        familyModeOn = false
        onboardingConnectPassed = false
        dataConsent = null
        inviteRegistrationPending = false
        theme = AppTheme.SYSTEM
        textSize = TextSizeLevel.STANDARD
        boldText = false
        highContrast = false
        reduceMotion = false
        reduceGlass = false
        haptics = true
        readAloud = false
        demoMode = false
        dismissedHomeScanIds = emptyList()
        guardianCardDismissed = false
        supervisedCardDismissed = false
        guardianIntroSeen = false
    }

    companion object {
        const val PREFS = "shoo.settings"

        /** Removes every stored preference (fresh install), e.g. `-UITestReset YES` before launch. */
        fun clear(defaults: SharedPreferences) {
            val editor = defaults.edit()
            for (key in Keys.all) editor.remove(key)
            editor.apply()
        }

        private fun readIds(text: String?): List<String> = try {
            val array = JSONArray(text ?: return emptyList())
            (0 until array.length()).mapNotNull { array.optString(it).takeIf(String::isNotEmpty) }
        } catch (_: Exception) {
            emptyList()
        }
    }
}

/**
 * `SharedPreferences` in memory: previews, the demo's throwaway settings and JVM tests (iOS: a `UserDefaults` suite
 * with a random name).
 */
class InMemoryPreferences : SharedPreferences {
    private val values = linkedMapOf<String, Any?>()
    private val listeners = mutableSetOf<SharedPreferences.OnSharedPreferenceChangeListener>()

    @Synchronized override fun getAll(): MutableMap<String, *> = LinkedHashMap(values)

    @Synchronized override fun getString(key: String, defValue: String?): String? = values[key] as? String ?: defValue

    @Suppress("UNCHECKED_CAST")
    @Synchronized
    override fun getStringSet(key: String, defValues: MutableSet<String>?): MutableSet<String>? =
        (values[key] as? Set<String>)?.toMutableSet() ?: defValues

    @Synchronized override fun getInt(key: String, defValue: Int): Int = values[key] as? Int ?: defValue

    @Synchronized override fun getLong(key: String, defValue: Long): Long = values[key] as? Long ?: defValue

    @Synchronized override fun getFloat(key: String, defValue: Float): Float = values[key] as? Float ?: defValue

    @Synchronized override fun getBoolean(key: String, defValue: Boolean): Boolean = values[key] as? Boolean ?: defValue

    @Synchronized override fun contains(key: String): Boolean = values.containsKey(key)

    override fun edit(): SharedPreferences.Editor = Editor()

    override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener) {
        synchronized(this) { listeners.add(listener) }
    }

    override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener) {
        synchronized(this) { listeners.remove(listener) }
    }

    private inner class Editor : SharedPreferences.Editor {
        private val changes = linkedMapOf<String, Any?>()
        private var clearFirst = false

        private fun change(key: String, value: Any?): SharedPreferences.Editor {
            changes[key] = value
            return this
        }

        override fun putString(key: String, value: String?): SharedPreferences.Editor = change(key, value)

        override fun putStringSet(key: String, values: MutableSet<String>?): SharedPreferences.Editor = change(key, values?.toSet())

        override fun putInt(key: String, value: Int): SharedPreferences.Editor = change(key, value)

        override fun putLong(key: String, value: Long): SharedPreferences.Editor = change(key, value)

        override fun putFloat(key: String, value: Float): SharedPreferences.Editor = change(key, value)

        override fun putBoolean(key: String, value: Boolean): SharedPreferences.Editor = change(key, value)

        override fun remove(key: String): SharedPreferences.Editor = change(key, null)

        override fun clear(): SharedPreferences.Editor {
            clearFirst = true
            return this
        }

        override fun commit(): Boolean {
            synchronized(this@InMemoryPreferences) {
                if (clearFirst) values.clear()
                for ((key, value) in changes) {
                    if (value == null) values.remove(key) else values[key] = value
                }
            }
            return true
        }

        override fun apply() {
            commit()
        }
    }
}
