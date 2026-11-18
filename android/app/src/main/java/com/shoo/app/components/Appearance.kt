package com.shoo.app.components

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.accessibility.AccessibilityManager
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import com.shoo.app.support.AppLanguage

/** PF-01 "Pengaturan/Tema": Terang, Gelap, Otomatis (follows the phone). */
enum class AppTheme(val rawValue: String) {
    LIGHT("light"),
    DARK("dark"),
    SYSTEM("system");

    companion object {
        fun fromRaw(raw: String?): AppTheme = entries.firstOrNull { it.rawValue == raw } ?: SYSTEM
    }
}

/**
 * PF-01 "Pengaturan/Aksesibilitas" text size slider: five stops. "Standard" keeps the phone's own size.
 * `fontScale`: the iOS content size category's body size over the default one (17 pt), applied on top of the
 * phone's font scale (sp already carries that).
 */
enum class TextSizeLevel(val rawValue: Int, val fontScale: Float) {
    /** iOS `.small`: body 15. */
    SMALL(0, 15f / 17f),
    /** No override: the phone setting applies. */
    STANDARD(1, 1f),
    /** iOS `.extraLarge`: body 19. */
    LARGE(2, 19f / 17f),
    /** iOS `.extraExtraLarge`: body 21. */
    LARGER(3, 21f / 17f),
    /** iOS `.extraExtraExtraLarge`: body 23. */
    LARGEST(4, 23f / 17f);

    /** Catalog key of the stop's name. */
    val title: String
        get() = when (this) {
            SMALL -> "Small"
            STANDARD -> "Standard"
            LARGE -> "Large"
            LARGER -> "Large text"
            LARGEST -> "Largest"
        }

    companion object {
        fun fromRaw(raw: Int?): TextSizeLevel = entries.firstOrNull { it.rawValue == raw } ?: STANDARD
    }
}

// MARK: Colours

/** `Color(hex: 0xRRGGBB, opacity:)` / `ActivityStyle.hex(0x…)`: an sRGB colour from 0xRRGGBB. */
fun hex(rgb: Int, alpha: Float = 1f): Color = Color(
    red = ((rgb shr 16) and 0xFF) / 255f,
    green = ((rgb shr 8) and 0xFF) / 255f,
    blue = (rgb and 0xFF) / 255f,
    alpha = alpha,
)

/**
 * `Color.dynamic(light, dark:, contrastLight:, contrastDark:)`: a colour that follows the theme and Increase
 * Contrast (the app's own switch). Read it inside composition: `val ink: Color @Composable get() = dynamicColor(…)`.
 */
@Composable
@ReadOnlyComposable
fun dynamicColor(light: Int, dark: Int, contrastLight: Int? = null, contrastDark: Int? = null): Color {
    val high = LocalHighContrast.current
    val value = if (LocalIsDarkTheme.current) {
        if (high) contrastDark ?: dark else dark
    } else {
        if (high) contrastLight ?: light else light
    }
    return hex(value)
}

// MARK: Environment (SwiftUI EnvironmentValues → CompositionLocals)

/** `\.locale` / `AppSettings.language`: the in-app language (PF-01). Bahasa Indonesia on a fresh install. */
val LocalAppLanguage = compositionLocalOf { AppLanguage.defaultLanguage }

/** `\.shooReduceMotion`: "Kurangi gerakan" in Shoo, or the phone's "Remove animations". */
val LocalReduceMotion = compositionLocalOf { false }

/** `\.shooReduceGlass`: "Kurangi efek kaca" in Shoo: solid instead of glass. */
val LocalReduceGlass = compositionLocalOf { false }

/** `\.colorScheme == .dark` after the theme override. Light-only screens provide `false` (iOS `.environment(\.colorScheme, .light)`). */
val LocalIsDarkTheme = compositionLocalOf { false }

/** `accessibilityContrast == .high`: the app's "Kontras tinggi" switch. */
val LocalHighContrast = compositionLocalOf { false }

/** `legibilityWeight == .bold`: the app's "Teks tebal" switch. `figmaTextStyle` makes every weight bolder. */
val LocalBoldText = compositionLocalOf { false }

/** The app's text size stop; `figmaTextStyle` and `scaled()` multiply by its `fontScale`. */
val LocalTextSizeLevel = staticCompositionLocalOf { TextSizeLevel.STANDARD }

/**
 * `AppearanceOverrides`: puts the in-app appearance choices on everything below, so every screen, sheet and
 * dynamic colour sees them. The app root wraps its content in this.
 */
@Composable
fun ShooAppearance(
    theme: AppTheme = AppTheme.SYSTEM,
    textSize: TextSizeLevel = TextSizeLevel.STANDARD,
    boldText: Boolean = false,
    highContrast: Boolean = false,
    reduceMotion: Boolean = false,
    reduceGlass: Boolean = false,
    language: AppLanguage = AppLanguage.defaultLanguage,
    content: @Composable () -> Unit,
) {
    val dark = when (theme) {
        AppTheme.LIGHT -> false
        AppTheme.DARK -> true
        AppTheme.SYSTEM -> isSystemInDarkTheme()
    }
    CompositionLocalProvider(
        LocalIsDarkTheme provides dark,
        LocalTextSizeLevel provides textSize,
        LocalBoldText provides boldText,
        LocalHighContrast provides highContrast,
        LocalReduceMotion provides reduceMotion,
        LocalReduceGlass provides reduceGlass,
        LocalAppLanguage provides language,
        content = content,
    )
}

/** iOS `.environment(\.colorScheme, .light)`: the Figma screens that are light only. */
@Composable
fun LightOnly(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalIsDarkTheme provides false, content = content)
}

// MARK: Haptics and read-aloud

/** "Getar" and "Bacakan peringatan" (Pengaturan/Aksesibilitas, "Saat ada peringatan"). */
object WarningFeedback {
    /** A warning reached the user inside the app (push while open, a Detail opened from a push). */
    fun warn(view: View, haptics: Boolean) {
        if (!haptics) return
        val constant = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            HapticFeedbackConstants.REJECT
        } else {
            HapticFeedbackConstants.LONG_PRESS
        }
        view.performHapticFeedback(constant)
    }

    /** TalkBack reads the score and the reasons when a warning opens (iOS: VoiceOver announcement). */
    fun readAloud(view: View, readAloud: Boolean, text: String) {
        if (!readAloud) return
        val manager = view.context.getSystemService(AccessibilityManager::class.java) ?: return
        if (!manager.isEnabled || !manager.isTouchExplorationEnabled) return
        @Suppress("DEPRECATION")
        view.announceForAccessibility(text)
    }
}
