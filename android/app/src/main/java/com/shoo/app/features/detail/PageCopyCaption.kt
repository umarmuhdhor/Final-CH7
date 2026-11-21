package com.shoo.app.features.detail

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.data.ScanResult
import com.shoo.app.features.activity.activityFont
import com.shoo.app.support.AppLanguage
import com.shoo.app.support.Formatters
import com.shoo.app.support.L10n
import java.time.Instant

/** Where the page copy is on the Detail screen (fase 18b). */
enum class PageCopyState {
    /** The scan has no copy link. */
    NONE,
    /** A scan from the last minute: the Worker may still be storing it (`DetailModel.waitForCopy`). */
    SAVING,
    LOADING,
    SHOWN,
    /** Gone, expired twice, refused by the lock, or the WebView couldn't draw it. */
    UNAVAILABLE,
    /** 429 from `GET /replicas/:id`. */
    RATE_LIMITED,
}

object PageCopyCaption {
    fun lines(
        state: PageCopyState,
        meta: ReplicaMeta?,
        scan: ScanResult,
        hasScreenshot: Boolean,
        language: AppLanguage,
        now: Instant = Instant.now(),
    ): List<String> = when (state) {
        PageCopyState.SAVING -> listOf(L10n.string("Saving a copy of the page…", language))
        PageCopyState.LOADING -> emptyList()
        PageCopyState.RATE_LIMITED -> listOf(L10n.string("Couldn't show the copy of the page. Try again later.", language))
        PageCopyState.NONE, PageCopyState.UNAVAILABLE ->
            if (hasScreenshot) emptyList() else listOf(L10n.string("No copy of this page", language))
        PageCopyState.SHOWN -> {
            val captured = ReplicaMeta.capturedAt(meta, scan.detectedAt)
            val `when` = Formatters.dayAndTime(captured, language, now)
            val lines = mutableListOf(L10n.string("Copy of the page · %@", language, `when`))
            meta?.copiedFrom(scan.url, scan.domain)?.let { lines.add(L10n.string("Copied from %@", language, it)) }
            if (meta?.truncated == true) lines.add(L10n.string("Page cut short", language))
            lines
        }
    }
}

/**
 * One line above the evidence cards: "Copy of the page · Today 10.42 WIB", "Copied from …", "Page cut short", or why
 * there is no copy. Plain text only (K4). `hasScreenshot`: an old build's screenshot is shown instead: no "no copy"
 * line then.
 */
@Composable
fun PageCopyCaption(
    state: PageCopyState,
    meta: ReplicaMeta?,
    scan: ScanResult,
    hasScreenshot: Boolean,
    modifier: Modifier = Modifier,
) {
    val language = LocalAppLanguage.current
    val lines = PageCopyCaption.lines(state, meta, scan, hasScreenshot, language)
    if (lines.isEmpty()) return
    val spoken = lines.joinToString(", ")
    Column(
        modifier.clearAndSetSemantics {
            contentDescription = spoken
            testTag = "detail.pageCopy"
        },
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        for (line in lines) {
            // iOS cuts in the middle; Compose 1.7 has no middle ellipsis, so the end goes.
            Text(
                line,
                style = activityFont(13f, tracking = -0.13f),
                color = DetailStyle.secondary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
