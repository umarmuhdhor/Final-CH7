package com.shoo.app.components

import android.content.ComponentCallbacks2
import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.shoo.app.BuildConfig
import com.shoo.app.app.AppConfig
import com.shoo.app.data.InMemoryCaches
import com.shoo.app.features.activity.ActivityStyle
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Loads the favicon behind `faviconUrl`. */
interface FaviconLoading {
    /** Throws `FaviconLoadException` when the icon is not ours, gone, expired, too big or not an image. */
    suspend fun image(url: String): ImageBitmap

    /** An image already in memory for this link, without waiting (no grey flash on a list reload). */
    fun cachedImage(url: String): ImageBitmap? = null
}

/** Not our Worker's link, gone, expired, too big or not an image. */
class FaviconLoadException : IOException("favicon unavailable")

/**
 * SECURITY §3 P9 (D-alief-A41): the app never contacts the scanned site. `faviconUrl` is a signed, short-lived link
 * to our own Worker, which serves the favicon the backend downloaded once and stores with the scan (deleted with it).
 * Loaded like screenshots: no HTTP cache, no cookies, no `Authorization` header, redirects refused, image kept in
 * memory only.
 */
class UrlConnectionFaviconLoader(private val allowedHost: () -> String? = { Uri.parse(AppConfig.apiBaseURL).host }) : FaviconLoading {
    companion object {
        /** Favicons are small; anything bigger is not one of ours. */
        const val maxBytes = 64 * 1024
        /** Stops decompression bombs; real favicons are ≤ 256 px. */
        const val maxPixelSide = 512
        /** Decoded no larger than this (iOS `maxPixelSize: 144`). */
        const val decodeSide = 144

        val shared = UrlConnectionFaviconLoader()

        /**
         * Our Worker's `/favicons/` path only, over HTTPS (SECURITY §3 P5); plain HTTP only for the local Worker
         * (`wrangler dev`, 10.0.2.2 on the emulator) in Debug builds.
         */
        fun isAllowed(url: String, allowedHost: String?): Boolean {
            val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return false
            val host = uri.host ?: return false
            if (host != allowedHost || !(uri.encodedPath ?: "").startsWith("/favicons/")) return false
            if (uri.scheme == "https") return true
            return BuildConfig.DEBUG && uri.scheme == "http" && host in setOf("localhost", "127.0.0.1", "10.0.2.2")
        }
    }

    override suspend fun image(url: String): ImageBitmap = withContext(Dispatchers.IO) {
        if (!isAllowed(url, allowedHost())) throw FaviconLoadException()
        val connection = try {
            URL(url).openConnection() as HttpURLConnection
        } catch (_: Exception) {
            throw FaviconLoadException()
        }
        try {
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.connectTimeout = 15_000
            connection.readTimeout = 15_000
            connection.setRequestProperty("Accept", "image/*")
            if (connection.responseCode != 200) throw FaviconLoadException()
            val declared = connection.contentLengthLong
            if (declared > maxBytes) throw FaviconLoadException()
            val data = connection.inputStream.use { input ->
                val out = ByteArrayOutputStream()
                val buffer = ByteArray(8 * 1024)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    out.write(buffer, 0, read)
                    if (out.size() > maxBytes) throw FaviconLoadException()
                }
                out.toByteArray()
            }
            decode(data) ?: throw FaviconLoadException()
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (_: Exception) {
            throw FaviconLoadException()
        } finally {
            connection.disconnect()
        }
    }

    /** Safe dimensions first (bounds only), then a downsampled decode. */
    private fun decode(data: ByteArray): ImageBitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        val width = bounds.outWidth
        val height = bounds.outHeight
        if (width <= 0 || height <= 0 || width > maxPixelSide || height > maxPixelSide) return null
        var sample = 1
        while (maxOf(width, height) / (sample * 2) >= decodeSide) sample *= 2
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size, options) ?: return null
        return bitmap.asImageBitmap()
    }
}

/**
 * Fase 22c (K10 a): `faviconUrl` is signed again on every `GET /scans` (`exp` moves), so without this every list
 * reload downloads every icon again. The key is the host plus the scan id from `/favicons/<id>`, never the signed link
 * with its query.
 *
 * SECURITY §3 P9/P13: memory only (never disk), at most 100 icons, failures not kept. `clear()` runs when data goes
 * (`SessionStore.forgetCachedData` → `InMemoryCaches`) and when the system is low on memory. A download that was
 * running during `clear()` is returned but not kept. An icon is kept at most `maxAge` (the lifetime of the signed
 * link, 1 h): after that the Worker is asked again.
 */
class CachedFaviconLoader(
    private val loader: FaviconLoading,
    val countLimit: Int = maxEntries,
    private val now: () -> Long = { System.currentTimeMillis() },
) : FaviconLoading {
    companion object {
        const val maxEntries = 100
        /** `exp` of a signed favicon link is now + 3600 s (`backend/api/src/services/screenshotLinks.ts`). */
        const val maxAgeMillis = 3_600_000L

        val shared: CachedFaviconLoader by lazy {
            CachedFaviconLoader(UrlConnectionFaviconLoader.shared).also { cache -> InMemoryCaches.register { cache.clear() } }
        }

        /** `host[:port]/<id>` for `https://host/favicons/<id>?v=…&exp=…&sig=…`; null for any other path. */
        fun key(url: String): String? {
            val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return null
            val prefix = "/favicons/"
            val path = uri.encodedPath ?: return null
            val host = uri.host?.lowercase() ?: return null
            if (!path.startsWith(prefix)) return null
            val id = path.removePrefix(prefix)
            if (id.isEmpty() || id.contains("/")) return null
            val origin = if (uri.port != -1) "$host:${uri.port}" else host
            return "$origin/$id"
        }

        /** Same scan on the same Worker: only the signature differs. */
        fun sameFavicon(a: String, b: String): Boolean {
            val ka = key(a)
            val kb = key(b)
            return if (ka == null || kb == null) a == b else ka == kb
        }
    }

    private class Entry(val image: ImageBitmap, val storedAt: Long)

    private val lock = Any()
    /** Access-ordered: the least recently used icon goes first (NSCache evicts on its own terms). */
    private val cache = object : LinkedHashMap<String, Entry>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Entry>?): Boolean = size > countLimit
    }
    /** Bumped by `clear()`: a download that started before it is not stored. */
    private var generation = 0
    private val watchingMemory = AtomicBoolean(false)

    override suspend fun image(url: String): ImageBitmap {
        // Not a favicon link: the loader decides (it refuses it), nothing is kept.
        val key = key(url) ?: return loader.image(url)
        fresh(key)?.let { return it }
        val started = synchronized(lock) { generation }
        val image = loader.image(url)
        synchronized(lock) {
            if (generation == started) cache[key] = Entry(image, now())
        }
        return image
    }

    override fun cachedImage(url: String): ImageBitmap? = key(url)?.let { fresh(it) }

    /** The stored icon while it is younger than `maxAge`; an older one is dropped. */
    private fun fresh(key: String): ImageBitmap? = synchronized(lock) {
        val entry = cache[key] ?: return@synchronized null
        if (now() - entry.storedAt >= maxAgeMillis) {
            cache.remove(key)
            null
        } else {
            entry.image
        }
    }

    fun clear() {
        synchronized(lock) {
            generation += 1
            cache.clear()
        }
    }

    /** iOS clears on a memory warning: the same on `onTrimMemory` / `onLowMemory`. Idempotent. */
    fun watchMemory(context: Context) {
        if (!watchingMemory.compareAndSet(false, true)) return
        context.applicationContext.registerComponentCallbacks(object : ComponentCallbacks2 {
            override fun onTrimMemory(level: Int) {
                @Suppress("DEPRECATION")
                if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) clear()
            }

            override fun onConfigurationChanged(newConfig: Configuration) = Unit

            @Deprecated("Deprecated in Java")
            override fun onLowMemory() = clear()
        })
    }
}

/** `\.faviconLoader`. */
val LocalFaviconLoader = staticCompositionLocalOf<FaviconLoading> { CachedFaviconLoader.shared }

/**
 * A site's favicon in a 48 pt circle (Figma "Update card" icon). No link, still loading, or failed: the empty grey
 * circle, exactly as Figma draws it. `url`: the scan's `faviconUrl`.
 */
@Composable
fun SiteIcon(url: String?, modifier: Modifier = Modifier, size: Dp = 48.dp) {
    val loader = LocalFaviconLoader.current
    val context = LocalContext.current
    // The image together with the link it was loaded for: a row that now shows another link never keeps the old icon.
    var loaded by remember { mutableStateOf<Pair<String, ImageBitmap>?>(null) }

    val image: ImageBitmap? = when {
        url == null -> null
        loaded != null && CachedFaviconLoader.sameFavicon(loaded!!.first, url) -> loaded!!.second
        else -> loader.cachedImage(url)
    }

    LaunchedEffect(url) {
        (loader as? CachedFaviconLoader)?.watchMemory(context)
        if (url == null) {
            loaded = null
            return@LaunchedEffect
        }
        loader.cachedImage(url)?.let {
            loaded = url to it
            return@LaunchedEffect
        }
        // Same scan already on screen (the cache was emptied): keep it while the new link loads.
        val current = loaded
        if (current != null && !CachedFaviconLoader.sameFavicon(current.first, url)) loaded = null
        try {
            loaded = url to loader.image(url)
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (_: Exception) {
            // Grey circle stays; the row still reads fine without the icon.
        }
    }

    Box(
        modifier
            .size(size)
            .clearAndSetSemantics { }
            .background(ActivityStyle.iconFill, CircleShape)
            .border(1.dp, ActivityStyle.iconStroke, CircleShape),
    ) {
        if (image != null) {
            Image(
                bitmap = image,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxSize().padding(size * 0.25f),
            )
        }
    }
}
