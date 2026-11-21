package com.shoo.app.features.detail

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.net.Uri
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.shoo.app.BuildConfig
import com.shoo.app.app.AppConfig
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

enum class ScreenshotLoadError {
    /** Gone (deleted, retention, disconnected: the Worker answers 404), expired, or not an image. */
    UNAVAILABLE,
}

/** iOS throws `ScreenshotLoadError` itself; Kotlin needs a `Throwable` around it. */
class ScreenshotLoadException(val error: ScreenshotLoadError = ScreenshotLoadError.UNAVAILABLE) :
    IOException("screenshot unavailable")

/** Loads the evidence screenshot behind `screenshotUrl`. */
interface ScreenshotLoading {
    suspend fun imageData(url: String): ByteArray
}

/** iOS `@Entry var screenshotLoader`. */
val LocalScreenshotLoader = staticCompositionLocalOf<ScreenshotLoading> { UrlConnectionScreenshotLoader.shared }

/**
 * SECURITY §3 P9 + P13: the screenshot lives in memory only. iOS `URLSessionScreenshotLoader`.
 * `screenshotUrl` is a short-lived Worker link re-checked on every request (D-alief-B08), so it is loaded as-is:
 * no `Authorization` header, no cookies, no HTTP cache, redirects refused (`RedirectRefuser`), nothing written to disk.
 */
class UrlConnectionScreenshotLoader(
    private val allowedHost: () -> String? = { Uri.parse(AppConfig.apiBaseURL).host },
) : ScreenshotLoading {
    companion object {
        /** The backend keeps screenshots ≤ 150 KB (contracts/api.md); anything far bigger is not ours. */
        const val maxBytes = 2 * 1024 * 1024
        /** Larger than any real screenshot (≤ 1280 px, contracts/api.md); stops decompression bombs. */
        const val maxPixelSide = 4096
        /** iOS `timeoutIntervalForRequest`: idle time. */
        const val requestTimeoutMillis = 20_000
        /** iOS `timeoutIntervalForResource`: a body dripping one byte every 19 s must still end. */
        const val resourceTimeoutMillis = 30_000L

        val shared = UrlConnectionScreenshotLoader()

        /** Our Worker's `/screenshots/` path only, over HTTPS (SECURITY §3 P5); plain HTTP only for the local Worker
         * in Debug builds. */
        fun isAllowed(url: String, allowedHost: String?): Boolean {
            val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return false
            val host = uri.host ?: return false
            if (host != allowedHost || !(uri.encodedPath ?: "").startsWith("/screenshots/")) return false
            if (uri.scheme == "https") return true
            return BuildConfig.DEBUG && uri.scheme == "http" && host in setOf("localhost", "127.0.0.1", "10.0.2.2")
        }
    }

    override suspend fun imageData(url: String): ByteArray = withContext(Dispatchers.IO) {
        if (!isAllowed(url, allowedHost())) throw ScreenshotLoadException()
        val connection = try {
            URL(url).openConnection() as HttpURLConnection
        } catch (_: Exception) {
            throw ScreenshotLoadException()
        }
        try {
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.connectTimeout = requestTimeoutMillis
            connection.readTimeout = requestTimeoutMillis
            // Offline, TLS failure, refused redirect: all mean "no screenshot" to the screen.
            if (connection.responseCode != 200 || connection.contentLengthLong > maxBytes) throw ScreenshotLoadException()
            val deadline = System.currentTimeMillis() + resourceTimeoutMillis
            // Stop reading as soon as the body is bigger than any real screenshot.
            val data = connection.inputStream.use { input ->
                val out = ByteArrayOutputStream()
                val buffer = ByteArray(16 * 1024)
                while (true) {
                    coroutineContext.ensureActive()
                    if (System.currentTimeMillis() > deadline) throw ScreenshotLoadException()
                    val read = input.read(buffer)
                    if (read < 0) break
                    out.write(buffer, 0, read)
                    if (out.size() > maxBytes) throw ScreenshotLoadException()
                }
                out.toByteArray()
            }
            if (!ScreenshotDecoder.hasSafeDimensions(data, maxPixelSide)) throw ScreenshotLoadException()
            data
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (known: ScreenshotLoadException) {
            throw known
        } catch (_: Exception) {
            throw ScreenshotLoadException()
        } finally {
            connection.disconnect()
        }
    }
}

/** Decodes untrusted image bytes without ever building a full-size bitmap. */
object ScreenshotDecoder {
    /** Reads only the header: a few-KB file can claim 30000 × 30000 px. */
    fun hasSafeDimensions(data: ByteArray, maxSide: Int): Boolean {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        val width = bounds.outWidth
        val height = bounds.outHeight
        return width in 1..maxSide && height in 1..maxSide
    }

    /** Downsampled once, at load time (longest side at most `maxPixelSize`), so every card shares one small bitmap. */
    fun image(data: ByteArray, maxPixelSize: Int = 2048): ImageBitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        val width = bounds.outWidth
        val height = bounds.outHeight
        if (width <= 0 || height <= 0) return null
        var sample = 1
        while (maxOf(width, height) / sample > maxPixelSize * 2) sample *= 2
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = BitmapFactory.decodeByteArray(data, 0, data.size, options) ?: return null
        val side = maxOf(decoded.width, decoded.height)
        val bitmap = if (side > maxPixelSize) {
            val scale = maxPixelSize.toFloat() / side
            Bitmap.createScaledBitmap(
                decoded,
                (decoded.width * scale).toInt().coerceAtLeast(1),
                (decoded.height * scale).toInt().coerceAtLeast(1),
                true,
            ).also { if (it !== decoded) decoded.recycle() }
        } else {
            decoded
        }
        return bitmap.asImageBitmap()
    }
}

/**
 * Debug only: fixture screenshot URLs point at `example.invalid`, which never resolves. With `MockRepository` the
 * Detail screen draws a stand-in page instead (390 × 520 pt at 3×, like iOS's renderer on a 3× iPhone), so previews
 * and the UI gate show the block.
 */
class FixtureScreenshotLoader : ScreenshotLoading {
    override suspend fun imageData(url: String): ByteArray = withContext(Dispatchers.Default) {
        val scale = 3f
        val width = 390f
        val height = 520f
        val bitmap = Bitmap.createBitmap((width * scale).toInt(), (height * scale).toInt(), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.scale(scale, scale)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.color = 0xFFF2F2F7.toInt() // systemGray6
        canvas.drawRect(0f, 0f, width, height, paint)
        paint.color = 0xFF007AFF.toInt() // systemBlue
        canvas.drawRect(0f, 0f, width, 64f, paint)
        paint.color = 0xFFFFFFFF.toInt()
        paint.textSize = 18f
        paint.typeface = Typeface.DEFAULT_BOLD
        val title = Uri.parse(url).lastPathSegment ?: ""
        canvas.drawText(title, 20f, 22f + 18f, paint)
        // Blurred inputs, as the extension sends them (contracts/api.md).
        paint.typeface = Typeface.DEFAULT
        paint.color = 0xFFC7C7CC.toInt() // systemGray3
        for (row in 0 until 3) {
            val top = 120f + row * 90f
            canvas.drawRoundRect(RectF(20f, top, width - 20f, top + 52f), 8f, 8f, paint)
        }
        paint.color = 0xFFFF3B30.toInt() // systemRed
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 3f
        canvas.drawRoundRect(RectF(16f, 116f, width - 16f, 176f), 10f, 10f, paint)
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        bitmap.recycle()
        out.toByteArray()
    }
}
