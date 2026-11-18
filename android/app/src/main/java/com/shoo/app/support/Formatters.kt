package com.shoo.app.support

import android.icu.text.DateFormat
import android.icu.text.DisplayContext
import android.icu.text.NumberFormat
import android.icu.text.RelativeDateTimeFormatter
import android.icu.util.TimeZone
import android.icu.util.ULocale
import android.os.Build
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit
import java.util.Date
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.abs

/**
 * Text formatting shared by every screen. All functions take the language explicitly, because the in-app language
 * (PF-01) may differ from the phone's. Android's ICU is the same CLDR data iOS formats with, so the patterns and
 * words match ("2 menit yang lalu", "10.42 WIB", "21 Okt 2026").
 */
object Formatters {
    private fun uLocale(language: AppLanguage): ULocale = ULocale.forLanguageTag(language.code)

    private fun icuZone(zone: ZoneId): TimeZone = TimeZone.getTimeZone(zone.id)

    /** "2 minutes ago" / "2 menit yang lalu" (Activity, Detail DT-03). iOS `RelativeDateTimeFormatter`, `.full`, `.named`. */
    fun relative(date: Instant, language: AppLanguage, now: Instant = Instant.now()): String {
        val formatter = RelativeDateTimeFormatter.getInstance(
            uLocale(language), null, RelativeDateTimeFormatter.Style.LONG, DisplayContext.CAPITALIZATION_NONE,
        )
        val seconds = ChronoUnit.SECONDS.between(now, date) // negative: in the past
        val magnitude = abs(seconds)
        // The largest whole unit, like Foundation's formatter.
        val (value, unit) = when {
            magnitude < 60 -> seconds to RelUnit.SECOND
            magnitude < 3_600 -> seconds / 60 to RelUnit.MINUTE
            magnitude < 86_400 -> seconds / 3_600 to RelUnit.HOUR
            magnitude < 7 * 86_400 -> seconds / 86_400 to RelUnit.DAY
            magnitude < 30 * 86_400 -> seconds / (7 * 86_400) to RelUnit.WEEK
            magnitude < 365 * 86_400 -> seconds / (30 * 86_400) to RelUnit.MONTH
            else -> seconds / (365 * 86_400) to RelUnit.YEAR
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // Named forms where CLDR has them ("now", "yesterday", "last week", "kemarin").
            val icuUnit = when (unit) {
                RelUnit.SECOND -> RelativeDateTimeFormatter.RelativeDateTimeUnit.SECOND
                RelUnit.MINUTE -> RelativeDateTimeFormatter.RelativeDateTimeUnit.MINUTE
                RelUnit.HOUR -> RelativeDateTimeFormatter.RelativeDateTimeUnit.HOUR
                RelUnit.DAY -> RelativeDateTimeFormatter.RelativeDateTimeUnit.DAY
                RelUnit.WEEK -> RelativeDateTimeFormatter.RelativeDateTimeUnit.WEEK
                RelUnit.MONTH -> RelativeDateTimeFormatter.RelativeDateTimeUnit.MONTH
                RelUnit.YEAR -> RelativeDateTimeFormatter.RelativeDateTimeUnit.YEAR
            }
            return formatter.format(value.toDouble(), icuUnit)
        }
        if (value == 0L && unit == RelUnit.SECOND) {
            return formatter.format(RelativeDateTimeFormatter.Direction.PLAIN, RelativeDateTimeFormatter.AbsoluteUnit.NOW)
        }
        val relativeUnit = when (unit) {
            RelUnit.SECOND -> RelativeDateTimeFormatter.RelativeUnit.SECONDS
            RelUnit.MINUTE -> RelativeDateTimeFormatter.RelativeUnit.MINUTES
            RelUnit.HOUR -> RelativeDateTimeFormatter.RelativeUnit.HOURS
            RelUnit.DAY -> RelativeDateTimeFormatter.RelativeUnit.DAYS
            RelUnit.WEEK -> RelativeDateTimeFormatter.RelativeUnit.WEEKS
            RelUnit.MONTH -> RelativeDateTimeFormatter.RelativeUnit.MONTHS
            RelUnit.YEAR -> RelativeDateTimeFormatter.RelativeUnit.YEARS
        }
        val direction = if (value < 0) RelativeDateTimeFormatter.Direction.LAST else RelativeDateTimeFormatter.Direction.NEXT
        return formatter.format(abs(value).toDouble(), direction, relativeUnit)
    }

    private enum class RelUnit { SECOND, MINUTE, HOUR, DAY, WEEK, MONTH, YEAR }

    /** "92%" — scores are whole numbers 0–100. */
    fun percent(score: Int, language: AppLanguage): String {
        val format = NumberFormat.getPercentInstance(uLocale(language))
        format.maximumFractionDigits = 0
        format.minimumFractionDigits = 0
        return format.format(score / 100.0)
    }

    /** "Oct 21, 2026, 12:05 PM" / "21 Okt 2026, 12.05" (Detail DT-03): abbreviated date, short time. */
    fun dateTime(date: Instant, language: AppLanguage, zone: ZoneId = ZoneId.systemDefault()): String =
        dateFormatter("yMMMdjm", language, zone).format(Date.from(date))

    /**
     * "10.42 WIB" / "10:42 AM GMT+7": the hour in the language's style plus the time-zone abbreviation
     * (Activity rows, PR-05/GD-05). iOS template "jmz".
     */
    fun time(date: Instant, language: AppLanguage, zone: ZoneId = ZoneId.systemDefault()): String =
        dateFormatter("jmz", language, zone).format(Date.from(date))

    /**
     * One formatter per skeleton, language and zone. Building one costs far more than formatting, and Activity
     * formats a time for every row on every render. ICU `DateFormat` isn't thread-safe: callers format on the main
     * thread (composition); the cache hands each key one instance.
     */
    fun dateFormatter(skeleton: String, language: AppLanguage, zone: ZoneId): DateFormat {
        val key = "$skeleton|${language.code}|${zone.id}"
        return dateFormatters.getOrPut(key) {
            DateFormat.getInstanceForSkeleton(skeleton, uLocale(language)).apply { timeZone = icuZone(zone) }
        }
    }

    private val dateFormatters = ConcurrentHashMap<String, DateFormat>()

    /**
     * Activity day header: "25 Oktober" / "October 25", with the year when it isn't this year's.
     * "Today" is the caller's (its wording differs per screen).
     */
    fun day(date: Instant, language: AppLanguage, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): String {
        val sameYear = date.atZone(zone).year == now.atZone(zone).year
        return dateFormatter(if (sameYear) "MMMMd" else "yMMMMd", language, zone).format(Date.from(date))
    }

    /**
     * "Today · 10.42 WIB" / "Hari ini · 10.42 WIB" (Guardian Home recent rows).
     * `compact`: "Today, 10.42" / "Hari ini, 10.42", no time zone (family rows and the waiting site on Home).
     */
    fun dayAndTime(
        date: Instant,
        language: AppLanguage,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
        compact: Boolean = false,
    ): String {
        val locale = uLocale(language)
        val dateDay = ZonedDateTime.ofInstant(date, zone).toLocalDate()
        val today = ZonedDateTime.ofInstant(now, zone).toLocalDate()
        val day = if (dateDay == today || dateDay == today.minusDays(1)) {
            // "today" / "hari ini", "yesterday" / "kemarin", capitalised as the first word.
            val formatter = RelativeDateTimeFormatter.getInstance(locale)
            val direction = if (dateDay == today) RelativeDateTimeFormatter.Direction.THIS else RelativeDateTimeFormatter.Direction.LAST
            val word = formatter.format(direction, RelativeDateTimeFormatter.AbsoluteUnit.DAY)
            word.take(1).uppercase(language.locale) + word.drop(1)
        } else {
            dateFormatter("yMMMd", language, zone).format(Date.from(date))
        }
        val time = dateFormatter("jm", language, zone).format(Date.from(date))
        if (compact) return "$day, $time"
        val zoneName = icuZone(zone).getDisplayName(false, TimeZone.SHORT, locale) ?: ""
        val timeAndZone = listOf(time, zoneName).filter { it.isNotEmpty() }.joinToString(" ")
        return listOf(day, timeAndZone).joinToString(" · ")
    }
}
