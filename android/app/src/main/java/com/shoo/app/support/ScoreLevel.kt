package com.shoo.app.support

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color
import com.shoo.app.components.SystemColors
import com.shoo.app.data.ScoreThreshold

/**
 * Score bands from PRD §5 (`ScoreThreshold`, lead-owned). Drives ring colour and copy.
 * Built-in 30/50/80 only: the admins' thresholds (X1, `GET /config/public`) reach the extension, not the app.
 * Screens show the scan's `status` as the extension decided it (contracts/api.md "Score thresholds"); this enum only
 * colours `ScoreRing` (component gallery) and mock data.
 */
enum class ScoreLevel {
    /** 0–29: nothing shown, nothing sent. */
    NORMAL,
    /** 30–49: first popup. */
    FIRST_WARNING,
    /** 50–79: second popup. */
    SECOND_WARNING,
    /** ≥ 80: block screen. */
    BLOCKED;

    val color: Color
        @Composable @ReadOnlyComposable
        get() = when (this) {
            NORMAL -> SystemColors.green
            FIRST_WARNING -> SystemColors.yellow
            SECOND_WARNING -> SystemColors.orange
            BLOCKED -> SystemColors.red
        }

    companion object {
        fun fromScore(score: Int): ScoreLevel = when {
            score >= ScoreThreshold.blocked -> BLOCKED
            score >= ScoreThreshold.secondWarning -> SECOND_WARNING
            score >= ScoreThreshold.firstWarning -> FIRST_WARNING
            else -> NORMAL
        }
    }
}
