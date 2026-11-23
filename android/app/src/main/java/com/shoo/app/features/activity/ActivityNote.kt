package com.shoo.app.features.activity

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.shoo.app.components.CapsuleShape
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.data.ScanResult
import com.shoo.app.data.ScanStatus
import com.shoo.app.data.Verdict
import com.shoo.app.support.AppLanguage
import com.shoo.app.support.L10n
import com.shoo.app.support.t

/**
 * The guardian's word under a row of the own Activity list (PR-05, Figma 450:8734 / 450:8739 / 450:8744):
 * "Menurut Virellia website ini berbahaya!", "Virellia menandai link ini aman" (#369) or "Virellia belum melihat website ini".
 */
sealed interface ActivityNote {
    /** `name` null = the viewer decided themselves ("you"). */
    data class NotSafe(val name: String?) : ActivityNote
    data class Safe(val name: String?) : ActivityNote
    data class Unseen(val guardianName: String) : ActivityNote

    /** The old safe note ran on two lines. Since #369 "Aman" stops the warnings, so the note is one line like the others. */
    val isTwoLine: Boolean get() = false

    /** Figma (icon, icon circle, stroke, text). */
    val colors: NoteColors
        get() = when (this) {
            is NotSafe -> NoteColors(ActivityStyle.hex(0xE5483B), ActivityStyle.hex(0xFFE0DC), ActivityStyle.hex(0xFFCDCD), ActivityStyle.ink)
            is Safe -> NoteColors(ActivityStyle.hex(0xFF9500), ActivityStyle.hex(0xFFE1B6), ActivityStyle.hex(0xFFE1B6), ActivityStyle.ink)
            is Unseen -> NoteColors(ActivityStyle.hex(0x727272), ActivityStyle.hex(0xE7E7E7), ActivityStyle.separator, ActivityStyle.secondary)
        }

    /** The name is bold (semibold for "unseen"), the rest regular, as in Figma. */
    fun text(language: AppLanguage): AnnotatedString {
        val you = L10n.string("activity.note.you", language)
        val (key, who, weight) = when (this) {
            is NotSafe -> Triple("activity.note.notSafe %@", name ?: you, FontWeight.Bold)
            // The name opens the sentence here ("Kamu menandai link ini aman"), so "you" gets a capital.
            is Safe -> Triple("activity.note.safe %@", name ?: (you.take(1).uppercase(language.locale) + you.drop(1)), FontWeight.Bold)
            is Unseen -> Triple("activity.note.unseen %@", guardianName, FontWeight.SemiBold)
        }
        // No arguments: the template as it stands, so the name can be styled where `%@` sits.
        val template = L10n.string(key, language)
        val parts = template.split("%@", limit = 2)
        return buildAnnotatedString {
            append(parts[0])
            withStyle(SpanStyle(fontWeight = weight)) { append(who) }
            if (parts.size > 1) append(parts[1])
        }
    }

    data class NoteColors(val icon: Color, val circle: Color, val stroke: Color, val text: Color)

    companion object {
        /**
         * Swift `init?(scan:guardianName:viewerDeviceId:)`. A verdict always shows. Without one, only a blocked scan of a
         * Protected user (one with a guardian) says the guardian has not looked yet; a warning row stays plain.
         * A verdict this build can't read (#493) gets no note: never "safe", and not "unseen" either.
         */
        fun of(scan: ScanResult, guardianName: String?, viewerDeviceId: String?): ActivityNote? {
            val verdict = scan.verdict
            if (verdict != null) {
                val name = if (verdict.byDeviceId == viewerDeviceId) null else verdict.byName
                return when (verdict.value) {
                    Verdict.Value.NOT_SAFE -> NotSafe(name)
                    Verdict.Value.SAFE -> Safe(name)
                    Verdict.Value.UNKNOWN -> null
                }
            }
            if (scan.status == ScanStatus.BLOCKED && !guardianName.isNullOrEmpty()) return Unseen(guardianName)
            return null
        }
    }
}

/** White strip with an info circle, r 10, 1 pt stroke in the note's colour. */
@Composable
fun ActivityNoteView(note: ActivityNote, language: AppLanguage, modifier: Modifier = Modifier) {
    val colors = note.colors
    val shape = RoundedCornerShape(10.dp)
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 34.dp)
            .background(Color.White, shape)
            .border(1.dp, colors.stroke, shape)
            // Figma: icon circle 9 pt in from the left, 7 pt from the top of the 34 pt strip.
            .padding(start = 9.dp, end = 8.dp)
            .padding(vertical = if (note.isTwoLine) 10.dp else 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(21.dp)
                .background(colors.circle, CircleShape)
                .clearAndSetSemantics { },
            contentAlignment = Alignment.Center,
        ) {
            com.shoo.app.components.SfSymbol("info.circle", pointSize = 12.8f, tint = colors.icon)
        }
        Text(
            note.text(language),
            style = activityFont(13f, tracking = -0.1625f),
            color = colors.text,
            modifier = Modifier.weight(1f),
        )
    }
}

/**
 * Own list: "Diblokir" as Figma's solid red "Red Button", white text only, no icon (450:8443). A blocked site the
 * guardian marked safe keeps the word but turns grey (Figma: the same button in Luminosity).
 */
@Composable
fun ActivityBlockedPill(markedSafe: Boolean, modifier: Modifier = Modifier) {
    val colors = if (markedSafe) {
        listOf(ActivityStyle.hex(0x474747), ActivityStyle.hex(0x848484))
    } else {
        listOf(ActivityStyle.hex(0xBB1616), ActivityStyle.hex(0xFF4F4F))
    }
    Box(
        modifier
            .wrapContentSize()
            .heightIn(min = 23.dp)
            // Swift `LinearGradient(startPoint: .bottom, endPoint: .top)`: the first colour at the bottom.
            .background(Brush.verticalGradient(colors.reversed()), CapsuleShape)
            .border(0.75.dp, colors[0], CapsuleShape)
            .padding(horizontal = 8.dp, vertical = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            t("Blocked"),
            style = activityFont(13f, tracking = -0.1625f),
            color = Color.White,
            maxLines = 1,
            overflow = TextOverflow.Clip,
            softWrap = false,
        )
    }
}

@Preview
@Composable
private fun ActivityNotePreview() {
    val language = LocalAppLanguage.current
    Column(Modifier.background(ActivityStyle.background).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ActivityNoteView(ActivityNote.NotSafe("Virellia"), language)
        ActivityNoteView(ActivityNote.Safe("Virellia"), language)
        ActivityNoteView(ActivityNote.Unseen("Virellia"), language)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ActivityBlockedPill(markedSafe = false)
            ActivityBlockedPill(markedSafe = true)
        }
    }
}

