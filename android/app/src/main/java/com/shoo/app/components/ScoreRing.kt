package com.shoo.app.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.shoo.app.support.Formatters
import com.shoo.app.support.ScoreLevel
import com.shoo.app.support.t

/**
 * Risk score 0–100 as a ring with the percentage inside (DT-01).
 * `maxScale`: how far the text size may grow the ring. Detail keeps it at 1: its 160 pt ring already has a 42 pt
 * number, and a bigger ring pushes link and evidence off a small screen (QA-A P2-3).
 */
@Composable
fun ScoreRing(
    score: Int,
    modifier: Modifier = Modifier,
    size: Dp = 120.dp,
    lineWidth: Dp = 12.dp,
    maxScale: Float = 2f,
) {
    val clamped = score.coerceIn(0, 100)
    val side = scoreRingSide(size, textScale(), maxScale)
    val percent = Formatters.percent(clamped, LocalAppLanguage.current)
    val track = SystemColors.secondary.copy(alpha = 0.2f)
    val color = ScoreLevel.fromScore(clamped).color
    val label = t("Risk score")
    val numberSize = with(LocalDensity.current) { (side * 0.26f).toSp() }
    Box(
        modifier
            .size(side)
            .clearAndSetSemantics {
                contentDescription = label
                stateDescription = percent
            },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = lineWidth.toPx()
            val inset = stroke / 2
            val arcSize = Size(this.size.width - stroke, this.size.height - stroke)
            drawArc(track, 0f, 360f, false, Offset(inset, inset), arcSize, style = Stroke(stroke))
            drawArc(
                color, -90f, 360f * clamped / 100f, false, Offset(inset, inset), arcSize,
                style = Stroke(stroke, cap = StrokeCap.Round),
            )
        }
        // The number is sized from the ring (already scaled), not by the text size again.
        // iOS: `.minimumScaleFactor(0.5)` shrinks a number that doesn't fit; Compose has no such option.
        Text(
            text = percent,
            style = figmaTextStyleFixed(side.value * 0.26f, FontWeight.Bold, family = FigmaFont.Family.SF_PRO)
                .copy(fontFeatureSettings = "tnum", textAlign = TextAlign.Center, fontSize = numberSize),
            color = labelColor,
            maxLines = 1,
            softWrap = false,
            modifier = Modifier.padding(lineWidth),
        )
    }
}

/** Ring diameter for a text scale, never above `maxScale` × `size`. */
fun scoreRingSide(size: Dp, textScale: Float, maxScale: Float): Dp = size * minOf(textScale, maxScale)
