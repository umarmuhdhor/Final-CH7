package com.shoo.app.debug

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.shoo.app.components.AvatarCatalog
import com.shoo.app.components.AvatarView
import com.shoo.app.components.EmptyStateView
import com.shoo.app.components.LightOnly
import com.shoo.app.components.ScanBadge
import com.shoo.app.components.ScoreRing
import com.shoo.app.components.SiteIcon
import com.shoo.app.components.StatusChip
import com.shoo.app.components.SystemTextStyle
import com.shoo.app.components.hex
import com.shoo.app.components.systemTextStyle
import com.shoo.app.features.activity.ActivityBadge

/**
 * Every shared component on one screen, for the UI gate screenshots (PROMPT step 7).
 * Debug builds only (iOS: launch with `-debug.gallery YES`; the app layer decides how Android opens it).
 * iOS draws it as an inset-grouped `List` in a `NavigationStack` with the large title "Components".
 */
@Composable
fun ComponentGalleryView(modifier: Modifier = Modifier) {
    LightOnly {
        Column(
            modifier
                .fillMaxSize()
                .background(hex(0xF2F2F7))
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(35.dp),
        ) {
            Text(
                "Components",
                style = systemTextStyle(SystemTextStyle.LARGE_TITLE, FontWeight.Bold),
                modifier = Modifier.padding(top = 8.dp),
            )
            GallerySection {
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterHorizontally),
                ) {
                    ScoreRing(score = 41, size = 72.dp, lineWidth = 8.dp)
                    ScoreRing(score = 63, size = 72.dp, lineWidth = 8.dp)
                    ScoreRing(score = 92, size = 72.dp, lineWidth = 8.dp)
                }
            }
            GallerySection {
                StatusChip(ScanBadge.WARNING)
                StatusChip(ScanBadge.BLOCKED)
                StatusChip(ScanBadge.VERIFIED_SCAM)
                StatusChip(ScanBadge.MARKED_SAFE)
            }
            GallerySection {
                // `LazyVGrid` with 6 flexible columns.
                AvatarCatalog.ids.chunked(6).forEach { row ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                        row.forEach { AvatarView(id = it, size = 40.dp) }
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    SiteIcon(url = null)
                    ActivityBadge(ScanBadge.WARNING)
                    ActivityBadge(ScanBadge.BLOCKED)
                }
            }
            GallerySection {
                Box(Modifier.fillMaxWidth().height(260.dp)) {
                    EmptyStateView(
                        systemImage = "list.bullet.rectangle",
                        title = "No activity yet",
                        message = "Risky sites you open will show up here.",
                    )
                }
            }
        }
    }
}

/** An inset-grouped `List` section: white, 10 pt corners, 16 / 11 row padding. */
@Composable
private fun GallerySection(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .background(hex(0xFFFFFF), RoundedCornerShape(10.dp))
            .padding(horizontal = 16.dp, vertical = 11.dp),
        verticalArrangement = Arrangement.spacedBy(11.dp),
        content = content,
    )
}
