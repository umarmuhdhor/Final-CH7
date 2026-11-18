package com.shoo.app

import android.app.Application
import com.shoo.app.app.AppEnvironment
import com.shoo.app.notify.GuardianCheckJob
import com.shoo.app.support.L10n

/**
 * Owns the one `AppEnvironment` of the process (iOS: `AppDelegate.environment`). It is built by the first
 * `MainActivity`, which hands it the Debug launch extras; background work (`GuardianCheckJob`) reads the session
 * itself and never builds one.
 */
class ShooApp : Application() {
    @Volatile
    private var environment: AppEnvironment? = null

    /** The environment, if an Activity has built it in this process. */
    val environmentOrNull: AppEnvironment? get() = environment

    /** The environment, built on first use with `arguments` (Debug launch extras, see `AppEnvironment.live`). */
    fun environment(arguments: Map<String, String> = emptyMap()): AppEnvironment =
        environment ?: synchronized(this) {
            environment ?: AppEnvironment.live(this, arguments).also { environment = it }
        }

    override fun onCreate() {
        super.onCreate()
        L10n.install(this)
        // Guardian Home copies the invite link without opening a Pairing screen first.
        com.shoo.app.features.pairing.SystemPasteboard.install(this)
        GuardianCheckJob.createChannel(this)
    }
}
