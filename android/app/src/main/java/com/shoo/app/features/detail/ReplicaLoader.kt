package com.shoo.app.features.detail

import android.net.Uri
import androidx.compose.runtime.staticCompositionLocalOf
import com.shoo.app.BuildConfig
import com.shoo.app.app.AppConfig
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

enum class ReplicaLoadError {
    /** Gone (deleted, retention, disconnected: the Worker answers 404), expired, too big, or not text. */
    UNAVAILABLE,
    /** 429: too many views; the screen says "Try again later" and does not ask for a new link. */
    RATE_LIMITED,
}

/** iOS throws `ReplicaLoadError` itself; Kotlin needs a `Throwable` around it. */
class ReplicaLoadException(val error: ReplicaLoadError) : IOException("replica ${error.name.lowercase()}")

/** Loads the page replica behind `pageReplicaUrl`. */
interface ReplicaLoading {
    suspend fun html(url: String): String
}

/** iOS `@Entry var replicaLoader`: tests and previews provide another one. */
val LocalReplicaLoader = staticCompositionLocalOf<ReplicaLoading> { UrlConnectionReplicaLoader.shared }

/**
 * SECURITY §3 P9 + P13: the replica lives in memory only, like the screenshot. iOS `URLSessionReplicaLoader`.
 * The Worker sends the stored gzip with `Content-Encoding: gzip`; `HttpURLConnection` inflates it, and the inflated
 * size is capped here because the backend only checks the compressed size on some paths (K2 plan B).
 * Loaded as-is: no `Authorization` header, no cookies, no HTTP cache, no redirects.
 */
class UrlConnectionReplicaLoader(
    private val allowedHost: () -> String? = { Uri.parse(AppConfig.apiBaseURL).host },
) : ReplicaLoading {
    companion object {
        /** Same as `MAX_HTML_BYTES` in replica-build.js and `MAX_REPLICA_HTML` in the Worker. */
        const val maxHTMLBytes = 3_145_728

        val shared = UrlConnectionReplicaLoader()

        /**
         * Our Worker's `/replicas/` path only, over HTTPS (SECURITY §3 P5); plain HTTP only for the local Worker
         * (`wrangler dev`, 10.0.2.2 on the emulator) in Debug builds.
         */
        fun isAllowed(url: String, host: String): Boolean {
            val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return false
            val urlHost = uri.host ?: return false
            if (urlHost != host) return false
            if (!(uri.encodedPath ?: "").startsWith("/replicas/")) return false
            if ((uri.path ?: "").contains("..")) return false
            if (uri.userInfo != null) return false
            if (uri.scheme == "https") return uri.port == -1
            return BuildConfig.DEBUG && uri.scheme == "http" && urlHost in setOf("localhost", "127.0.0.1", "10.0.2.2")
        }
    }

    override suspend fun html(url: String): String = withContext(Dispatchers.IO) {
        val host = allowedHost()
        if (host == null || !isAllowed(url, host)) throw ReplicaLoadException(ReplicaLoadError.UNAVAILABLE)
        val connection = try {
            URL(url).openConnection() as HttpURLConnection
        } catch (_: Exception) {
            throw ReplicaLoadException(ReplicaLoadError.UNAVAILABLE)
        }
        try {
            // `RedirectRefuser`: the Worker never redirects; a redirect would leave our origin.
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            // The request timeout is idle time only; the whole load also stops after `resourceTimeoutMillis`.
            connection.connectTimeout = UrlConnectionScreenshotLoader.requestTimeoutMillis
            connection.readTimeout = UrlConnectionScreenshotLoader.requestTimeoutMillis
            val status = connection.responseCode
            if (status == 429) throw ReplicaLoadException(ReplicaLoadError.RATE_LIMITED)
            if (status != 200) throw ReplicaLoadException(ReplicaLoadError.UNAVAILABLE)
            val deadline = System.currentTimeMillis() + UrlConnectionScreenshotLoader.resourceTimeoutMillis
            // Counted after inflating: a 300 KB gzip can hold far more than 3 MB. A dropped connection mid-body is
            // "unavailable" like one that never started, never an expired link.
            val declared = connection.contentLengthLong
            val bytes = connection.inputStream.use { input ->
                val out = ByteArrayOutputStream(
                    declared.coerceIn(64L * 1024, maxHTMLBytes.toLong()).toInt(),
                )
                val buffer = ByteArray(16 * 1024)
                while (true) {
                    coroutineContext.ensureActive()
                    if (System.currentTimeMillis() > deadline) throw ReplicaLoadException(ReplicaLoadError.UNAVAILABLE)
                    val read = input.read(buffer)
                    if (read < 0) break
                    out.write(buffer, 0, read)
                    if (out.size() > maxHTMLBytes) throw ReplicaLoadException(ReplicaLoadError.UNAVAILABLE)
                }
                out.toByteArray()
            }
            // Strict UTF-8, like `String(bytes:encoding: .utf8)`: invalid bytes mean "not ours".
            try {
                Charsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(bytes))
                    .toString()
            } catch (_: CharacterCodingException) {
                throw ReplicaLoadException(ReplicaLoadError.UNAVAILABLE)
            }
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (known: ReplicaLoadException) {
            throw known
        } catch (_: Exception) {
            throw ReplicaLoadException(ReplicaLoadError.UNAVAILABLE)
        } finally {
            connection.disconnect()
        }
    }
}

/**
 * Debug only: the page copy `MockRepository` links to (`example.invalid` never resolves). A stand-in bank login page
 * as replica.js writes it (CSP meta, `shoo-replica` meta with marks), so previews and the UI gate show the copy, the
 * "Copy of the page" line, both spotlight variants and a reason far down the page (DT-04 crop).
 */
class FixtureReplicaLoader : ReplicaLoading {
    override suspend fun html(url: String): String {
        val q = "&quot;"
        val meta = "{${q}v$q:1,${q}url$q:${q}https://bca-verifikasi.site/login/pin$q,${q}capturedAt$q:${q}2026-10-31T03:42:00Z$q," +
            "${q}focusY$q:300,${q}truncated$q:false,${q}marks$q:[" +
            "{${q}signalId$q:${q}asks_pin$q,${q}x$q:24,${q}y$q:332,${q}w$q:342,${q}h$q:52}," +
            "{${q}signalId$q:${q}unreasonable_request$q,${q}x$q:24,${q}y$q:2300,${q}w$q:342,${q}h$q:44}," +
            "{${q}signalId$q:${q}unreasonable_request$q,${q}x$q:24,${q}y$q:2440,${q}w$q:342,${q}h$q:52}]}"
        // Absolute positions, so the marks above sit exactly on their elements.
        fun box(top: Int, height: Int, style: String, text: String = ""): String =
            "<div style=\"position:absolute;left:24px;width:342px;top:${top}px;height:${height}px;$style\">$text</div>"
        val field = "box-sizing:border-box;border:1px solid #c9d3df;border-radius:10px;background:#fff"
        val button = "border-radius:26px;background:#0a5cab;color:#fff;text-align:center;line-height:52px;font-weight:700"
        val body = listOf(
            "<div style=\"position:absolute;left:0;top:0;width:390px;height:64px;background:#0a5cab;color:#fff;" +
                "font-weight:700;font-size:20px;line-height:64px;text-indent:24px\">KlikBCA</div>",
            box(92, 30, "font-size:22px;font-weight:700", "Verifikasi Akun Anda"),
            box(130, 44, "font-size:15px;color:#4b5868", "Akun Anda dibekukan sementara. Selesaikan verifikasi dalam 15 menit."),
            box(304, 20, "font-size:14px;font-weight:600", "PIN KlikBCA (6 digit)"),
            box(332, 52, field),
            box(420, 52, button, "Lanjut"),
            // DT-04: the second reason sits far below the form, outside the main picture, so its card needs its own crop.
            box(2240, 40, "font-size:13px;color:#4b5868", "Langkah terakhir untuk mengaktifkan kembali akun Anda:"),
            box(2300, 44, "font-size:15px;color:#b42318;font-weight:600", "Transfer biaya aktivasi Rp 150.000 untuk membuka akun"),
            box(2412, 20, "font-size:14px;font-weight:600", "Nomor rekening tujuan"),
            box(2440, 52, field),
            box(2524, 52, button, "Verifikasi Sekarang"),
        ).joinToString("")
        return "<!doctype html><html><head><meta charset=\"utf-8\">" +
            "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline'\">" +
            "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">" +
            "<meta name=\"shoo-replica\" content=\"$meta\"><title>KlikBCA - Verifikasi Akun</title></head>" +
            "<body style=\"margin:0;position:relative;height:2700px;font-family:sans-serif;background:#f3f6fa;color:#1d2733\">" +
            "$body</body></html>"
    }
}
