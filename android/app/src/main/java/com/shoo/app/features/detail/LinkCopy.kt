package com.shoo.app.features.detail

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle

/** DT-03: the link can be copied, never opened from the app (D-alief-A31). */
object LinkCopy {
    /** Long enough to paste into a report or chat; then the browsing-history URL leaves the clipboard. */
    const val lifetimeMillis: Long = 5 * 60 * 1000L

    /**
     * Plain text only (no URI clip, so nothing offers to open it), marked sensitive so Android 13+ doesn't show it in
     * the clipboard preview, and it expires (SECURITY §3 P8).
     * iOS: `.localOnly` + `.expirationDate`. Android has neither: the clip is cleared after `lifetimeMillis` when it is
     * still ours and the app can still read the clipboard (Android 10+ only lets the app in front read it).
     */
    fun copy(url: String, context: Context) {
        val clipboard = context.applicationContext.getSystemService(ClipboardManager::class.java) ?: return
        val clip = ClipData.newPlainText("", url)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            clip.description.extras = PersistableBundle().apply { putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true) }
        }
        try {
            clipboard.setPrimaryClip(clip)
        } catch (_: RuntimeException) {
            return
        }
        Handler(Looper.getMainLooper()).postDelayed({ expire(clipboard, url) }, lifetimeMillis)
    }

    private fun expire(clipboard: ClipboardManager, url: String) {
        try {
            val current = clipboard.primaryClip ?: return
            if (current.itemCount != 1 || current.getItemAt(0).text?.toString() != url) return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                clipboard.clearPrimaryClip()
            } else {
                clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
            }
        } catch (_: RuntimeException) {
        }
    }
}
