package com.shoo.app.support

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalContext
import com.shoo.app.components.LocalAppLanguage
import org.json.JSONObject
import java.util.IllegalFormatException

/**
 * Lookup in the String Catalogs for a given in-app language (iOS `L10n` + SwiftUI `Text("literal")`).
 *
 * The key is the English source text, exactly as in Swift (`Text("Recent activity")` → `t("Recent activity")`).
 * Two catalogs are copied into the APK at build time (app/build.gradle.kts `copyStringCatalogs`):
 * `ios/ShooApp/Resources/Localizable.xcstrings` (all copy) and `android/app/src/main/l10n/android.xcstrings`
 * (Android-only copy, e.g. Firefox instead of Safari); an entry in the Android one wins.
 *
 * Like iOS: a key without a value for the language reads as the key itself; `variations.plural` picks
 * `zero` / `one` / `other` by the first integer argument; Swift format specifiers (`%@`, `%lld`, `%1$@`) are
 * turned into Java ones before formatting. A string without arguments is returned as it stands.
 */
object L10n {
    /** Asset paths, in order: a later catalog wins. */
    val catalogAssets = listOf("l10n/Localizable.xcstrings", "l10n/android.xcstrings")

    /** One localization of one key. */
    sealed class Value {
        data class Plain(val text: String) : Value()
        /** CLDR category ("zero", "one", "other", …) → text. */
        data class Plural(val forms: Map<String, String>) : Value()
    }

    @Volatile
    private var entries: Map<String, Map<String, Value>>? = null

    /** Reads the catalogs from assets once. `t()` does it on first use; the app also calls it on start. */
    fun install(context: Context) {
        if (entries != null) return
        synchronized(this) {
            if (entries != null) return
            val assets = context.applicationContext.assets
            // Android-only copy may be split per feature (android-<feature>.xcstrings); all of them win over iOS.
            val extra = (assets.list("l10n") ?: emptyArray())
                .filter { it.startsWith("android") && it.endsWith(".xcstrings") && "l10n/$it" !in catalogAssets }
                .sorted().map { "l10n/$it" }
            val texts = (catalogAssets + extra).mapNotNull { path ->
                runCatching { assets.open(path).bufferedReader(Charsets.UTF_8).use { it.readText() } }.getOrNull()
            }
            entries = merge(texts)
        }
    }

    /** For tests and previews: use these catalog JSON texts (later wins). */
    fun load(catalogJsons: List<String>) {
        synchronized(this) { entries = merge(catalogJsons) }
    }

    val isInstalled: Boolean get() = entries != null

    private fun merge(texts: List<String>): Map<String, Map<String, Value>> {
        val merged = HashMap<String, Map<String, Value>>()
        for (text in texts) {
            val parsed = runCatching { parse(text) }.getOrNull() ?: continue
            merged.putAll(parsed)
        }
        return merged
    }

    /** `.xcstrings` JSON → key → language → value. Entries without a usable value for a language leave it out. */
    fun parse(json: String): Map<String, Map<String, Value>> {
        val strings = JSONObject(json).optJSONObject("strings") ?: return emptyMap()
        val result = HashMap<String, Map<String, Value>>(strings.length() * 2)
        for (key in strings.keys()) {
            val entry = strings.optJSONObject(key) ?: continue
            val localizations = entry.optJSONObject("localizations") ?: continue
            val values = HashMap<String, Value>()
            for (language in localizations.keys()) {
                val localization = localizations.optJSONObject(language) ?: continue
                parseValue(localization)?.let { values[language] = it }
            }
            if (values.isNotEmpty()) result[key] = values
        }
        return result
    }

    private fun parseValue(localization: JSONObject): Value? {
        localization.optJSONObject("stringUnit")?.let { unit ->
            if (unit.has("value")) return Value.Plain(unit.optString("value"))
        }
        val plural = localization.optJSONObject("variations")?.optJSONObject("plural") ?: return null
        val forms = HashMap<String, String>()
        for (category in plural.keys()) {
            val unit = plural.optJSONObject(category)?.optJSONObject("stringUnit") ?: continue
            if (unit.has("value")) forms[category] = unit.optString("value")
        }
        return if (forms.isEmpty()) null else Value.Plural(forms)
    }

    /** The text for `key` in `language`, formatted with `args` (Swift interpolation order). */
    fun string(key: String, language: AppLanguage, vararg args: Any): String {
        val value = entries?.get(key)?.get(language.code)
        val template = when (value) {
            null -> key
            is Value.Plain -> value.text
            is Value.Plural -> pluralForm(value.forms, firstInteger(args), language)
        }
        return format(template, args)
    }

    /** Swift `String(format:)` with the template's Swift specifiers. No arguments: the text as it stands. */
    fun format(template: String, args: Array<out Any>): String {
        if (args.isEmpty()) return template
        return try {
            String.format(java.util.Locale.ROOT, convertFormat(template), *args)
        } catch (_: IllegalFormatException) {
            template
        }
    }

    /** CLDR categories the two languages use: English one/other, Indonesian other only. `zero` when given. */
    fun pluralForm(forms: Map<String, String>, count: Long?, language: AppLanguage): String {
        val other = forms["other"] ?: forms.values.first()
        if (count == null) return other
        if (count == 0L) forms["zero"]?.let { return it }
        if (count == 1L && language == AppLanguage.ENGLISH) forms["one"]?.let { return it }
        return other
    }

    private fun firstInteger(args: Array<out Any>): Long? = args.firstNotNullOfOrNull { arg ->
        when (arg) {
            is Int -> arg.toLong()
            is Long -> arg
            is Short -> arg.toLong()
            is Byte -> arg.toLong()
            else -> null
        }
    }

    private val specifier = Regex("""%(\d+\$)?([-+ 0#]*)(\d*)(\.\d+)?(hh|h|ll|l|q|z|t|j)?([@dDiuUxXoOfFeEgGcsS%])""")

    /**
     * Swift → Java: `%@` → `%s`, `%lld` / `%ld` / `%d` / `%u` → `%d`, `%1$@` → `%1$s`, `%%` stays. Flags, width and
     * precision are kept (`%.1f`).
     */
    fun convertFormat(swift: String): String = specifier.replace(swift) { match ->
        val position = match.groupValues[1]
        val flags = match.groupValues[2]
        val width = match.groupValues[3]
        val precision = match.groupValues[4]
        val conversion = match.groupValues[6]
        val java = when (conversion) {
            "%" -> return@replace "%%"
            "@", "s", "S" -> "s"
            "d", "D", "i", "u", "U" -> "d"
            "O" -> "o"
            "F" -> "f"
            "c" -> "c"
            else -> conversion
        }
        "%$position$flags$width$precision$java"
    }
}

/** `Text("key")` in the in-app language (`LocalAppLanguage`). Swift interpolation: `t("%@ opened a risky page", name)`. */
@Composable
@ReadOnlyComposable
fun t(key: String, vararg args: Any): String {
    if (!L10n.isInstalled) L10n.install(LocalContext.current)
    return L10n.string(key, LocalAppLanguage.current, *args)
}
