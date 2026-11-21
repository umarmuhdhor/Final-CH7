package com.shoo.app.support

import java.util.Locale

/**
 * In-app language (PF-01). Changes the app only; the Firefox add-on follows the phone language
 * (contracts/app-group-keys.md "Language").
 */
enum class AppLanguage(val rawValue: String) {
    ENGLISH("en"),
    INDONESIAN("id");

    val id: String get() = rawValue

    /** Language code for `LocalizedText.text(for:)` and `PATCH /devices/me {language}`. */
    val code: String get() = rawValue

    val locale: Locale get() = Locale.forLanguageTag(rawValue)

    /** Shown in its own language so people can always find theirs. */
    val nativeName: String
        get() = when (this) {
            ENGLISH -> "English"
            INDONESIAN -> "Bahasa Indonesia"
        }

    companion object {
        /** Fresh install: Bahasa Indonesia, whatever the phone language is. Profile changes it (`settings.language`). */
        val defaultLanguage: AppLanguage = INDONESIAN

        /** iOS `AppLanguage(locale:)`: "id…" is Indonesian, anything else English; `null` is the default. */
        fun fromCode(code: String?): AppLanguage = when {
            code == null -> defaultLanguage
            code.lowercase(Locale.ROOT).let { it == "id" || it.startsWith("id-") || it.startsWith("id_") || it == "in" } -> INDONESIAN
            else -> ENGLISH
        }

        fun fromLocale(locale: Locale): AppLanguage =
            if (locale.language == "id" || locale.language == "in") INDONESIAN else ENGLISH
    }
}
