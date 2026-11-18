@file:Suppress("DEPRECATION")

package com.shoo.app.components

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.automirrored.rounded.FormatListBulleted
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.rounded.ListAlt
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.automirrored.rounded.Undo
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.GppBad
import androidx.compose.material.icons.outlined.GppMaybe
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material.icons.rounded.Abc
import androidx.compose.material.icons.rounded.AccessTimeFilled
import androidx.compose.material.icons.rounded.AccountCircle
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.BugReport
import androidx.compose.material.icons.rounded.CalendarToday
import androidx.compose.material.icons.rounded.Cancel
import androidx.compose.material.icons.rounded.ChatBubble
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Contrast
import androidx.compose.material.icons.rounded.CrueltyFree
import androidx.compose.material.icons.rounded.Dangerous
import androidx.compose.material.icons.rounded.DarkMode
import androidx.compose.material.icons.rounded.Eco
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Error
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.Explore
import androidx.compose.material.icons.rounded.FilterNone
import androidx.compose.material.icons.rounded.FindInPage
import androidx.compose.material.icons.rounded.FlutterDash
import androidx.compose.material.icons.rounded.GppMaybe
import androidx.compose.material.icons.rounded.Groups
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.IosShare
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.LightMode
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.ManageSearch
import androidx.compose.material.icons.rounded.NorthEast
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.NotificationsOff
import androidx.compose.material.icons.rounded.PanTool
import androidx.compose.material.icons.rounded.People
import androidx.compose.material.icons.rounded.PermPhoneMsg
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.Pets
import androidx.compose.material.icons.rounded.PriorityHigh
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Security
import androidx.compose.material.icons.rounded.Sell
import androidx.compose.material.icons.rounded.SetMeal
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.material.icons.rounded.Smartphone
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.SwapHoriz
import androidx.compose.material.icons.rounded.SyncProblem
import androidx.compose.material.icons.rounded.TouchApp
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material.icons.rounded.WebAsset
import androidx.compose.material.icons.rounded.WifiOff
import androidx.compose.material.icons.rounded.HelpOutline
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp

/**
 * SF Symbols (Apple-only) → the closest Material Symbols icon, Rounded set first (PORTING.md). Every SF Symbol
 * name the iOS app uses is here; add a missing one here, never at the call site. An unknown name draws a
 * question mark so it shows up in review.
 */
private val symbols: Map<String, ImageVector> = mapOf(
    // Arrows and chevrons
    "arrow.left" to Icons.AutoMirrored.Rounded.ArrowBack,
    "arrow.right" to Icons.AutoMirrored.Rounded.ArrowForward,
    "arrow.up.right" to Icons.Rounded.NorthEast,
    "arrow.left.arrow.right" to Icons.Rounded.SwapHoriz,
    "arrow.clockwise" to Icons.Rounded.Refresh,
    "arrow.uturn.backward.circle.fill" to Icons.AutoMirrored.Rounded.Undo,
    "chevron.down" to Icons.Rounded.ExpandMore,
    "chevron.right" to Icons.AutoMirrored.Rounded.KeyboardArrowRight,
    "clock.arrow.circlepath" to Icons.Rounded.History,
    "exclamationmark.arrow.circlepath" to Icons.Rounded.SyncProblem,

    // Marks
    "checkmark" to Icons.Rounded.Check,
    "checkmark.circle.fill" to Icons.Rounded.CheckCircle,
    "checkmark.seal" to Icons.Outlined.Verified,
    "checkmark.seal.fill" to Icons.Rounded.Verified,
    "xmark" to Icons.Rounded.Close,
    "xmark.circle.fill" to Icons.Rounded.Cancel,
    "xmark.octagon.fill" to Icons.Rounded.Dangerous,
    "xmark.shield" to Icons.Outlined.GppBad,
    "plus" to Icons.Rounded.Add,
    "exclamationmark" to Icons.Rounded.PriorityHigh,
    "exclamationmark.circle" to Icons.Rounded.ErrorOutline,
    "exclamationmark.circle.fill" to Icons.Rounded.Error,
    "exclamationmark.triangle.fill" to Icons.Rounded.Warning,
    "exclamationmark.shield" to Icons.Outlined.GppMaybe,
    "exclamationmark.shield.fill" to Icons.Rounded.GppMaybe,
    "info.circle" to Icons.Outlined.Info,
    "info.circle.fill" to Icons.Rounded.Info,

    // Shields
    "shield" to Icons.Outlined.Shield,
    "shield.fill" to Icons.Rounded.Shield,
    "shield.lefthalf.filled" to Icons.Rounded.Security,
    "bolt.shield.fill" to Icons.Rounded.Shield,
    "network.badge.shield.half.filled" to Icons.Rounded.Security,
    "lock.fill" to Icons.Rounded.Lock,
    "hand.raised.fill" to Icons.Rounded.PanTool,
    "eye.slash" to Icons.Rounded.VisibilityOff,

    // People
    "person" to Icons.Outlined.Person,
    "person.fill" to Icons.Rounded.Person,
    "person.2.fill" to Icons.Rounded.People,
    "person.3" to Icons.Outlined.Groups,
    "person.3.fill" to Icons.Rounded.Groups,
    "person.crop.circle" to Icons.Rounded.AccountCircle,

    // Communication and sharing
    "bell.fill" to Icons.Rounded.Notifications,
    "bell.slash.fill" to Icons.Rounded.NotificationsOff,
    "message" to Icons.Outlined.ChatBubbleOutline,
    "message.fill" to Icons.Rounded.ChatBubble,
    "phone.bubble.fill" to Icons.Rounded.PermPhoneMsg,
    "paperplane.fill" to Icons.AutoMirrored.Rounded.Send,
    "square.and.arrow.up" to Icons.Rounded.IosShare,
    "doc.on.doc" to Icons.Rounded.ContentCopy,
    "link" to Icons.Rounded.Link,

    // Web, device, documents
    "globe" to Icons.Rounded.Language,
    "safari.fill" to Icons.Rounded.Explore,
    "iphone" to Icons.Rounded.Smartphone,
    "macwindow" to Icons.Rounded.WebAsset,
    "macwindow.stack" to Icons.Rounded.FilterNone,
    "doc.text.magnifyingglass" to Icons.Rounded.FindInPage,
    "text.magnifyingglass" to Icons.Rounded.ManageSearch,
    "textformat.abc" to Icons.Rounded.Abc,
    "list.bullet.rectangle" to Icons.AutoMirrored.Rounded.ListAlt,
    "list.bullet.circle.fill" to Icons.AutoMirrored.Rounded.FormatListBulleted,
    "wifi.exclamationmark" to Icons.Rounded.WifiOff,
    "calendar" to Icons.Rounded.CalendarToday,
    "tag" to Icons.Rounded.Sell,
    "clock" to Icons.Rounded.Schedule,
    "clock.fill" to Icons.Rounded.AccessTimeFilled,
    "gearshape.fill" to Icons.Rounded.Settings,
    "switch.2" to Icons.Rounded.Tune,
    "pencil" to Icons.Rounded.Edit,
    "hand.tap.fill" to Icons.Rounded.TouchApp,
    "sparkles" to Icons.Rounded.AutoAwesome,

    // Appearance
    "sun.max.fill" to Icons.Rounded.LightMode,
    "moon.fill" to Icons.Rounded.DarkMode,
    "circle.lefthalf.filled" to Icons.Rounded.Contrast,

    // Avatar catalog (AvatarView fallbacks)
    "hare.fill" to Icons.Rounded.CrueltyFree,
    "tortoise.fill" to Icons.Rounded.Pets,
    "bird.fill" to Icons.Rounded.FlutterDash,
    "fish.fill" to Icons.Rounded.SetMeal,
    "pawprint.fill" to Icons.Rounded.Pets,
    "ant.fill" to Icons.Rounded.BugReport,
    "ladybug.fill" to Icons.Rounded.BugReport,
    "leaf.fill" to Icons.Rounded.Eco,
    "star.fill" to Icons.Rounded.Star,
    "cloud.fill" to Icons.Rounded.Cloud,
)

/** The Material icon standing in for SF Symbol `name` (`Image(systemName: name)`). */
fun sfSymbol(name: String): ImageVector = symbols[name] ?: Icons.Rounded.HelpOutline

/** True when `name` has a mapping (tests and the component gallery). */
fun hasSfSymbol(name: String): Boolean = symbols.containsKey(name)

/** Every mapped SF Symbol name. */
val sfSymbolNames: Set<String> get() = symbols.keys

/**
 * `Image(systemName:).font(.system(size: pointSize))`: an SF Symbol drawn at a font size. A symbol at point size P
 * is about 1.2 P tall; a Material icon's glyph fills 20 of its 24 dp, so the icon box is 1.4 P (`scale` = SwiftUI
 * `.imageScale`: small 0.8, medium 1, large 1.3). iOS: symbol weights (`.semibold`) have no Material counterpart.
 */
@Composable
fun SfSymbol(
    name: String,
    pointSize: Float,
    tint: Color,
    modifier: Modifier = Modifier,
    scale: Float = 1f,
    contentDescription: String? = null,
) {
    Icon(
        imageVector = sfSymbol(name),
        contentDescription = contentDescription,
        tint = tint,
        modifier = modifier.size((pointSize * 1.4f * scale * textScale()).dp),
    )
}

/** SwiftUI `.imageScale(.small / .medium / .large)`. */
object SymbolScale {
    const val SMALL = 0.8f
    const val MEDIUM = 1f
    const val LARGE = 1.3f
}
