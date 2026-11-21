package com.shoo.app.support

import android.os.Build
import java.util.TimeZone

/**
 * PF-01 member detail ("Pixel 8 · Android 15"): the model name and the major OS version only, sent with
 * `PATCH /devices/me` and shown to the guardian. Nothing that identifies this one device.
 * iOS: a table of iPhone identifiers → marketing names; Android reports its model name itself.
 */
object DeviceInfo {
    /** "Pixel 8", "Galaxy S24" (`Build.MODEL`), or "Android" when it has nothing the backend accepts. */
    val modelName: String
        get() = modelName(model = Build.MODEL, manufacturer = Build.MANUFACTURER)

    /** "15". */
    val osMajorVersion: String
        get() = osMajorVersion(Build.VERSION.RELEASE)

    /**
     * The phone's IANA zone ("Asia/Makassar") for quiet hours and the weekly summary, or null when it does not fit
     * the backend rule (it then keeps its last zone, WIB by default).
     */
    val timeZone: String?
        get() = timeZone(TimeZone.getDefault().id)

    private val zoneRule = Regex("[A-Za-z_]+(/[A-Za-z0-9_+\\-]+){0,2}")

    fun timeZone(identifier: String): String? =
        if (identifier.length <= 40 && zoneRule.matches(identifier)) identifier else null

    /**
     * Pure, so tests cover it. Only letters, digits, spaces and parentheses (backend rule); a model that already
     * names its maker ("Pixel 8") is kept as is, a code name ("SM-S918B") gets the maker in front.
     */
    fun modelName(model: String?, manufacturer: String?): String {
        val clean = sanitize(model)
        if (clean.isEmpty()) return "Android"
        val maker = sanitize(manufacturer).replaceFirstChar { it.uppercase() }
        val named = if (maker.isEmpty() || clean.startsWith(maker, ignoreCase = true) || clean.startsWith("Pixel")) {
            clean
        } else {
            "$maker $clean"
        }
        return named.take(40).trim()
    }

    /** "15" from "15", "14" from "14.0.1". */
    fun osMajorVersion(release: String?): String =
        release?.substringBefore('.')?.filter(Char::isDigit)?.ifEmpty { null } ?: "0"

    private fun sanitize(text: String?): String =
        (text ?: "").map { if (it.isLetterOrDigit() && it.code < 128 || it == '(' || it == ')') it else ' ' }
            .joinToString("")
            .split(' ')
            .filter { it.isNotEmpty() }
            .joinToString(" ")
}
