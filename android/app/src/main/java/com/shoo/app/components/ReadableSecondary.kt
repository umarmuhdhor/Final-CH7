package com.shoo.app.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color

/** iOS `Color(.label)`: black in light mode, white in dark. */
val labelColor: Color
    @Composable @ReadOnlyComposable
    get() = if (LocalIsDarkTheme.current) Color.White else Color.Black

/**
 * `.readableSecondary`: secondary text that still reaches 4.5:1 (WCAG 1.4.3) on white and grouped cards.
 * iOS `.secondary` is about 3.5:1 in light mode, too faint for Shoo's 45–65 audience.
 */
val readableSecondary: Color
    @Composable @ReadOnlyComposable
    get() = labelColor.copy(alpha = 0.72f)

/** `.readableRed`: error and destructive text that reaches 4.5:1 in light and dark mode (system red is about 3.6:1). */
val readableRed: Color
    @Composable @ReadOnlyComposable
    get() = if (LocalIsDarkTheme.current) Color(red = 1f, green = 0.54f, blue = 0.50f) else Color(red = 0.70f, green = 0.15f, blue = 0.12f)

/** iOS system colours (light / dark), for code that uses `.orange`, `.red`, `.green`, `.secondary`… */
object SystemColors {
    val red: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xFF3B30, 0xFF453A)
    val orange: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xFF9500, 0xFF9F0A)
    val yellow: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xFFCC00, 0xFFD60A)
    val green: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x34C759, 0x30D158)
    val mint: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x00C7BE, 0x63E6E2)
    val teal: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x30B0C7, 0x40C8E0)
    val cyan: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x32ADE6, 0x64D2FF)
    val blue: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x007AFF, 0x0A84FF)
    val indigo: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x5856D6, 0x5E5CE6)
    val pink: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xFF2D55, 0xFF375F)
    val brown: Color @Composable @ReadOnlyComposable get() = dynamicColor(0xA2845E, 0xAC8E68)
    val gray: Color @Composable @ReadOnlyComposable get() = dynamicColor(0x8E8E93, 0x8E8E93)
    /** `.secondary` (label at 60 % in light, 60 % white in dark). */
    val secondary: Color @Composable @ReadOnlyComposable get() =
        if (LocalIsDarkTheme.current) hex(0xEBEBF5, 0.6f) else hex(0x3C3C43, 0.6f)
}
