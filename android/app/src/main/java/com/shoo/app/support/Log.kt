package com.shoo.app.support

import com.shoo.app.BuildConfig

/**
 * Thin wrapper around `android.util.Log` (iOS `AppLogger` over `os.Logger`, SECURITY §3 P6).
 * The event name is public; every value passed with it is private: written only in Debug builds (iOS redacts
 * `.private` values in release logs). Never log tokens, `Authorization` headers or page content, not even as a value.
 */
class AppLogger(private val category: String) {
    private val tag = "Shoo.$category"

    fun debug(event: String) = write(DEBUG, event, null)

    fun debug(event: String, value: String) = write(DEBUG, event, value)

    fun info(event: String) = write(INFO, event, null)

    fun info(event: String, value: String) = write(INFO, event, value)

    fun error(event: String) = write(ERROR, event, null)

    fun error(event: String, value: String) = write(ERROR, event, value)

    fun error(event: String, error: Throwable) = write(ERROR, event, error.toString())

    private fun write(level: Int, event: String, value: String?) {
        val text = if (value != null && BuildConfig.DEBUG) "$event: $value" else event
        // JVM unit tests run against a stub android.jar whose Log throws: logging never breaks the caller.
        try {
            when (level) {
                DEBUG -> android.util.Log.d(tag, text)
                INFO -> android.util.Log.i(tag, text)
                else -> android.util.Log.e(tag, text)
            }
        } catch (_: RuntimeException) {
        }
    }

    private companion object {
        const val DEBUG = 0
        const val INFO = 1
        const val ERROR = 2
    }
}

/** Loggers per area. Use these instead of `println`. */
object Log {
    val app = AppLogger("app")
    val data = AppLogger("data")
    val ui = AppLogger("ui")
    /** Page copy rendering (DT-04): stage names only, never the page or its address. */
    val replica = AppLogger("replica")
}
