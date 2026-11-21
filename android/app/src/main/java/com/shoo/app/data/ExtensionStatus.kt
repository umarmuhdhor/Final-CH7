package com.shoo.app.data

import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import java.time.Duration
import java.time.Instant

/** Firefox for Android: where the Shoo add-on runs (iOS: Safari). */
const val FIREFOX_PACKAGE = "org.mozilla.firefox"

/**
 * Shoo's browser protection Active/Off (ON-04, PR-04, GD-01, PF-01). iOS: the Safari extension.
 *
 * Android (PORTING.md): the Shoo add-on in Firefox for Android. Sources, in the same `evaluate` rule as iOS:
 * - `enabled` (iOS: Safari's switch): `false` when Firefox is not installed; `true` once the add-on was linked to
 *   this session through `AddonBridge` (`AppGroup.Key.firefoxLinkedAt`); otherwise unknown.
 * - The heartbeat `AppGroup.Key.extensionLastSeenAt` and `extension.allSites`: the add-on can't write them on
 *   Android (no App Group), so they stay missing and `enabled` decides.
 */
sealed interface ExtensionStatus {
    /** `lastSeen` is null when the switch is on but no page has loaded since. Android: when the add-on was linked. */
    data class Active(override val lastSeen: Instant?) : ExtensionStatus

    data class Off(override val lastSeen: Instant?, val reason: OffReason = OffReason.NOT_SEEN) : ExtensionStatus

    /** Why Shoo is Off, so the app can say what to do (#135). */
    enum class OffReason {
        /** iOS: Safari's switch for Shoo is off. Android: Firefox is not installed. */
        SWITCHED_OFF,
        /** `extension.allSites == false`: the browser lets Shoo read only some sites (EX-01). */
        SOME_SITES_ONLY,
        /** No recent heartbeat, and the browser can't tell. Android: the add-on was never linked to this session. */
        NOT_SEEN,
    }

    /** The one thing the user still has to do, or null when Shoo is on and has checked in. */
    enum class NextStep {
        SWITCH_ON,
        ALLOW_EVERY_WEBSITE,
        /** No heartbeat and the browser can't say whether Shoo is on: both steps. */
        SWITCH_ON_THEN_OPEN_A_WEBSITE,
        /** Shoo is on: load one page so the extension reports in, with its site access. */
        OPEN_A_WEBSITE,
    }

    val lastSeen: Instant?

    val isActive: Boolean get() = this is Active

    val nextStep: NextStep?
        get() = when (this) {
            // On, but no page has run Shoo yet, so its access is still unknown (#135).
            is Active -> if (lastSeen == null) NextStep.OPEN_A_WEBSITE else null
            is Off -> when (reason) {
                OffReason.SWITCHED_OFF -> NextStep.SWITCH_ON
                OffReason.SOME_SITES_ONLY -> NextStep.ALLOW_EVERY_WEBSITE
                OffReason.NOT_SEEN -> NextStep.SWITCH_ON_THEN_OPEN_A_WEBSITE
            }
        }

    companion object {
        /**
         * Pure rule, testable without storage. `allSites` missing means unknown: counts as `true`
         * (contracts/app-group-keys.md). `enabled` missing: the heartbeat decides alone.
         */
        fun evaluate(lastSeen: Instant?, allSites: Boolean? = null, enabled: Boolean? = null, now: Instant = Instant.now()): ExtensionStatus {
            // Switched off: a heartbeat from before still sits in storage.
            if (enabled == false) return Off(lastSeen, OffReason.SWITCHED_OFF)
            // A recent heartbeat from a page Shoo may read does not mean it can protect every site.
            if (allSites == false) return Off(lastSeen, OffReason.SOME_SITES_ONLY)
            if (enabled == true) return Active(lastSeen)
            if (lastSeen == null) return Off(null, OffReason.NOT_SEEN)
            val ageSeconds = Duration.between(lastSeen, now).seconds
            // A heartbeat from the future (clock change) still counts as recent.
            return if (ageSeconds < AppGroup.extensionActiveWindowSeconds) Active(lastSeen) else Off(lastSeen, OffReason.NOT_SEEN)
        }

        /** Reads the heartbeat and the site access from storage, with the browser's own answer if known. */
        fun current(defaults: SharedPreferences, enabled: Boolean? = null, now: Instant = Instant.now()): ExtensionStatus =
            evaluate(
                lastSeen = defaults.optInstant(AppGroup.Key.extensionLastSeenAt),
                allSites = defaults.optBoolean(AppGroup.Key.extensionAllSites),
                enabled = enabled,
                now = now,
            )

        /** `current()` with the browser asked first (every screen that shows the status). */
        fun load(context: Context, now: Instant = Instant.now()): ExtensionStatus {
            val defaults = AppGroup.defaults(context)
            val linkedAt = linkedAt(defaults)
            val status = current(defaults, enabled = firefoxSwitch(context, defaults), now = now)
            // Linked: the link time stands in for the heartbeat the add-on can't write here.
            return if (status is Active && status.lastSeen == null && linkedAt != null) Active(linkedAt) else status
        }

        /** iOS `safariSwitch()`: `false` without Firefox, `true` once the add-on has this session, else null. */
        fun firefoxSwitch(context: Context, defaults: SharedPreferences = AppGroup.defaults(context)): Boolean? = when {
            !isFirefoxInstalled(context) -> false
            linkedAt(defaults) != null -> true
            else -> null
        }

        fun isFirefoxInstalled(context: Context): Boolean = try {
            context.packageManager.getPackageInfo(FIREFOX_PACKAGE, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }

        /** When the add-on last received this session; null = not linked (or the session changed since). */
        fun linkedAt(defaults: SharedPreferences): Instant? = defaults.optInstant(AppGroup.Key.firefoxLinkedAt)

        /** `AddonBridge` handed the session to the add-on. */
        fun recordLinked(defaults: SharedPreferences, now: Instant = Instant.now()) {
            defaults.edit().putLong(AppGroup.Key.firefoxLinkedAt, now.toEpochMilli()).apply()
        }
    }
}
