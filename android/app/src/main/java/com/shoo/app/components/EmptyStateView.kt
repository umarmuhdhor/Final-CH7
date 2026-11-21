package com.shoo.app.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.shoo.app.support.t

/**
 * Centred icon + title + message for lists with nothing to show. Own layout instead of `ContentUnavailableView`,
 * whose title stays on one line and truncates at accessibility text sizes (QA-A P2-5).
 * `title` and `message` are catalog keys.
 */
@Composable
fun EmptyStateView(systemImage: String, title: String, modifier: Modifier = Modifier, message: String? = null) {
    val titleText = t(title)
    val messageText = message?.let { t(it) }
    Column(
        modifier
            .fillMaxSize()
            // One TalkBack stop, and the caller's tag lands on one element.
            .clearAndSetSemantics {
                contentDescription = listOfNotNull(titleText, messageText).joinToString(". ")
                heading()
            }
            .padding(horizontal = 24.dp, vertical = 32.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // `.font(.largeTitle).imageScale(.large)`.
        SfSymbol(systemImage, pointSize = 34f, tint = readableSecondary, scale = SymbolScale.LARGE)
        Text(titleText, style = systemTextStyle(SystemTextStyle.TITLE2, FontWeight.Bold), textAlign = TextAlign.Center, color = labelColor)
        if (messageText != null) {
            Text(messageText, style = systemTextStyle(SystemTextStyle.BODY), textAlign = TextAlign.Center, color = readableSecondary)
        }
    }
}
