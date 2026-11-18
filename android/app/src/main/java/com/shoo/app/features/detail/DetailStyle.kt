package com.shoo.app.features.detail

import androidx.compose.ui.graphics.Color
import com.shoo.app.components.hex as rgb

/**
 * Figma "Guardian/Detail Aktivitas" (416:9255 and its states): colours of the Detail screen.
 * Type uses `activityFont` (same Figma type ramp as Activity). Light only, like Activity.
 */
object DetailStyle {
    val background = rgb(0xF5F8FC)
    val ink = rgb(0x151617)
    val title = rgb(0x191D2F)
    val link = rgb(0x3A3D42)
    /** "Diakses lewat SMS …", "Penilaian Risiko Shoo", "Status situs" (Figma #564C51, 7.6:1 on white). */
    val rowSubtitle = rgb(0x564C51)
    /** The line between the score and the status (1252:2036). */
    val scoreLine = rgb(0xE2E8F0)
    /** Under the score row (1252:3123). */
    val divider = rgb(0xEEF1F5)
    /** "Evidence Card" fill in the REVISI PRU frames. */
    val cardFill = rgb(0xF6F8FA)
    val secondary = rgb(0x6A717E)
    val tick = rgb(0x3F4D5A)
    val needle = rgb(0x383D43)
    val cardTop = rgb(0xFEFEFF)
    val photoFill = rgb(0xEAF1F8)
    val photoStroke = rgb(0xE2E8F0)
    val pageShadow = rgb(0x1A1C2E)
    val spotlight = rgb(0x0B1A2E)
    val contribution = rgb(0xB42318)
    /** Bar segments in order; the fourth and later reuse the last. */
    val segments = listOf(rgb(0xFF9500), rgb(0xF87541), rgb(0xE5483B))
    val barTick = rgb(0xE5483B)
    val barTrack = rgb(0xE9ECF1)
    val barTrackHatch = rgb(0xCFD5DD)
    val footer = rgb(0xF5F6FC)
    val safeStroke = rgb(0xE3E3E3)
    val dangerTop = rgb(0xBB1616)
    val dangerBottom = rgb(0xFF4F4F)
    val change = rgb(0x186FB9)
    val scamIconFill = rgb(0xFDECEA)
    val scamIcon = rgb(0xE5483B)
    val safeIconFill = rgb(0xE6F8EC)
    val safeIcon = rgb(0x34C759)
    // "Anda menandai ini aman" chip and the greyed AI badge (480:5780).
    val markedFill = rgb(0xEEF5FA)
    val markedStroke = rgb(0xC3DDEC)
    val markedText = rgb(0x1E78BE)
    val greyBadgeFill = rgb(0xF2F4F7)
    val greyBadgeStroke = rgb(0xDFE3E8)
    // "Virellia belum melihat link ini" banner on the Score Card (487:4221).
    val unseenFill = rgb(0xC7C7CE)
    val unseenText = rgb(0x727272)
    /** "Spotlight + kuning": several areas in one photo. */
    val marker = rgb(0xFFD60A)

    fun hex(value: Int): Color = rgb(value)
}
