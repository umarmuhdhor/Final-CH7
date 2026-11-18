package com.shoo.app.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.shoo.app.data.ScanResult
import com.shoo.app.data.ScanStatus
import com.shoo.app.data.Verdict
import com.shoo.app.support.t

/** What a scan's chip says (Activity rows, Detail DT-02/DT-06). */
enum class ScanBadge {
    WARNING,
    BLOCKED,
    VERIFIED_SCAM,
    MARKED_SAFE;

    /** Catalog key. */
    val title: String
        get() = when (this) {
            WARNING -> "Warning"
            BLOCKED -> "Blocked"
            VERIFIED_SCAM -> "Verified scam"
            MARKED_SAFE -> "Marked safe"
        }

    /** SF Symbol name (`sfSymbol`). */
    val systemImage: String
        get() = when (this) {
            WARNING -> "exclamationmark.triangle.fill"
            BLOCKED -> "hand.raised.fill"
            VERIFIED_SCAM -> "xmark.octagon.fill"
            MARKED_SAFE -> "checkmark.seal.fill"
        }

    val color: Color
        @Composable @ReadOnlyComposable
        get() = when (this) {
            WARNING -> SystemColors.orange
            BLOCKED, VERIFIED_SCAM -> SystemColors.red
            MARKED_SAFE -> SystemColors.green
        }

    companion object {
        /**
         * A guardian's verdict wins over the detection status. A verdict or status this build does not know (#493)
         * reads as no verdict / a warning: never safer than a warning.
         */
        fun from(scan: ScanResult): ScanBadge = when (scan.verdict?.value) {
            Verdict.Value.NOT_SAFE -> VERIFIED_SCAM
            Verdict.Value.SAFE -> MARKED_SAFE
            else -> if (scan.status == ScanStatus.BLOCKED) BLOCKED else WARNING
        }

        /** Family cards (GD-03) only know the status of a member's newest scan, not its verdict. */
        fun from(status: ScanStatus): ScanBadge = if (status == ScanStatus.BLOCKED) BLOCKED else WARNING
    }
}

/**
 * Small capsule with icon + label. Colour is never the only signal: the text is always there. The label uses the
 * primary label colour so it keeps full contrast on the tinted capsule; the colour sits on the icon and the fill.
 */
@Composable
fun StatusChip(badge: ScanBadge, modifier: Modifier = Modifier) {
    val title = t(badge.title)
    val color = badge.color
    Row(
        modifier
            .clearAndSetSemantics { contentDescription = title }
            .background(color.copy(alpha = 0.15f), CapsuleShape)
            .padding(horizontal = 10.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SfSymbol(badge.systemImage, pointSize = 12f, tint = color)
        Text(title, style = systemTextStyle(SystemTextStyle.CAPTION, FontWeight.SemiBold), color = labelColor)
    }
}
