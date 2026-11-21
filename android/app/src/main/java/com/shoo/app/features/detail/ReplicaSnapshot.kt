package com.shoo.app.features.detail

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.shoo.app.support.Log
import kotlin.coroutines.resume
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull

/** One picture of part of the page copy, and the marks that touch it. */
class PagePicture(
    val image: ImageBitmap,
    /** Width of the page in CSS px, so `marks` land on the image. */
    val cssWidth: Float,
    /** The meta's marks, moved to CSS px from the top of `image`; marks outside it are dropped. */
    val marks: List<ReplicaMark>,
) {
    /** Where `signalId` sits on this picture, in page CSS px from its top. */
    fun highlights(signalId: String): List<Rect> = marks.filter { it.signalId == signalId }.map { it.rect }
}

/**
 * The page copy as the Detail cards draw it: one picture of the locked replica around `focusY`, plus a small picture
 * for each card whose marks fell outside it (DT-04: a reason far down the page still shows where it is). It lives in
 * memory only while Detail is open (SECURITY §3 P9, P13); the HTML is dropped once drawn.
 */
class PageCopy(
    val image: ImageBitmap,
    val meta: ReplicaMeta?,
    /** Width of the page in CSS px, so `marks` land on the image. */
    val cssWidth: Float,
    /** The meta's marks, moved to CSS px from the top of `image`; marks outside it are dropped. */
    val marks: List<ReplicaMark>,
    /** Signal id → its own picture, only for signals with no mark on `image`. */
    val crops: Map<String, PagePicture> = emptyMap(),
) {
    /** The main picture. */
    val main: PagePicture get() = PagePicture(image, cssWidth, marks)

    /** The picture for one reason card: its own crop when it has one, else the main picture. */
    fun picture(signalId: String): PagePicture = crops[signalId] ?: main
}

/**
 * Draws the replica once in a hidden `LockedWebView` and keeps only pictures of it (fase 18b). The pictures serve
 * every evidence card: no live web view stays on screen, so there is no form control to focus and nothing to select
 * or share (K12). Lengths are in dp (iOS points) unless they say px. Main thread only.
 */
object ReplicaSnapshot {
    /** Same width as the iPhone the extension copied from, so the page lays out as it did there. */
    const val renderWidth = 390f
    /** Most of the page we keep, in view dp, around the focus (fase 22 K7 a). */
    const val windowHeight = 1800f
    /** How much of the page above the focus stays in the picture. */
    const val leadIn = 600f
    /** Pixels per dp of the pictures, at most 3 (iOS: the 3× screen scale), so a full window is ≤ 1170 × 5400 px. */
    const val maxImageScale = 3f
    /** `onPageFinished` never came: show the placeholder instead of waiting forever. */
    const val loadTimeoutMillis = 10_000L
    /** A page that stalls the render process must not keep the hidden view in the window. */
    const val snapshotTimeoutMillis = 5_000L
    /** Time for the newly shown tiles after the frame grows. */
    const val paintDelayMillis = 300L
    /** A card whose marks are all outside the main window gets its own picture this tall (view dp). */
    const val cropHeight = 700f
    /** How much of the page above the mark stays in a crop, so the reader sees what leads to it. */
    const val cropLeadIn = 220f
    const val maxCrops = 3

    /** Why `render` gave null (fase 23a, flake F2): the stage, never the page or its address. */
    enum class RenderFailure {
        /** Detail closed or a new link: normal. */
        CANCELLED,
        /** No `onPageFinished` within `loadTimeoutMillis`, a load error, or a dead render process. */
        LOAD,
        /** The page has no size to place the window on. */
        PLACE,
        /** No picture within `snapshotTimeoutMillis`. */
        SNAPSHOT,
    }

    /** A picture, or the stage that failed (iOS `Result<_, RenderFailure>`). */
    private class Attempt<T>(val value: T?, val failure: RenderFailure?)

    /**
     * `lockedHTML` must come from `ReplicaHTML.locked`. null when the WebView can't draw it. Cancelling the caller
     * (Detail closed, new link) takes the hidden view out of the window at once and rethrows.
     * `host`: the window's root view (iOS `keyWindow`); the view is added to it outside the visible area.
     * `wanted`: signal ids of the reason cards that point at the page; each one whose marks miss the main picture
     * gets its own crop.
     */
    suspend fun render(lockedHTML: String, meta: ReplicaMeta?, wanted: List<String> = emptyList(), host: ViewGroup): PageCopy? {
        val attempt = attempt(lockedHTML, meta, wanted, host)
        when (attempt.failure) {
            null -> return attempt.value
            RenderFailure.CANCELLED -> Log.replica.info("Replica snapshot nil: cancelled")
            RenderFailure.LOAD -> Log.replica.error("Replica snapshot nil: load")
            RenderFailure.PLACE -> Log.replica.error("Replica snapshot nil: place")
            RenderFailure.SNAPSHOT -> Log.replica.error("Replica snapshot nil: snapshot")
        }
        return null
    }

    private suspend fun attempt(lockedHTML: String, meta: ReplicaMeta?, wanted: List<String>, host: ViewGroup): Attempt<PageCopy> {
        val density = host.resources.displayMetrics.density
        val controller = ReplicaWebController(host.context)
        val webView = controller.webView
        val widthPx = (renderWidth * density).roundToInt()
        // In the window (WebView only lays out and paints attached views), outside its bounds, never seen or read out.
        webView.layoutParams = FrameLayout.LayoutParams(widthPx, (844 * density).roundToInt())
        webView.translationX = -widthPx * 2f
        webView.visibility = View.VISIBLE
        host.addView(webView)
        try {
            val loaded = finished(controller, lockedHTML)
            if (!loaded) return Attempt(null, RenderFailure.LOAD)
            controller.waitForLayout()

            val allMarks = meta?.marks ?: emptyList()
            val main = picture(controller, density, meta?.focusY ?: 0.0, windowHeight, leadIn, allMarks)
            val mainPicture = main.value ?: return Attempt(null, main.failure)

            // A reason far from the focus (urgent text in the footer) would show no mark at all: give it its own
            // picture around its first mark. A crop that fails leaves that card on the main picture.
            val crops = LinkedHashMap<String, PagePicture>()
            for (signalId in cropSignals(wanted, allMarks, mainPicture.marks)) {
                val first = allMarks.firstOrNull { it.signalId == signalId } ?: continue
                val crop = picture(controller, density, first.rect.top.toDouble(), cropHeight, cropLeadIn, allMarks)
                if (crop.value != null) crops[signalId] = crop.value else Log.replica.error("Replica crop skipped")
            }
            return Attempt(
                PageCopy(mainPicture.image, meta, mainPicture.cssWidth, mainPicture.marks, crops),
                null,
            )
        } finally {
            host.removeView(webView)
            controller.tearDown()
        }
    }

    /** Signals in `wanted` (in its order) with marks on the page but none on the main picture, at most `maxCrops`. */
    fun cropSignals(wanted: List<String>, marks: List<ReplicaMark>, kept: List<ReplicaMark>): List<String> {
        val onPage = marks.map { it.signalId }.toSet()
        val shown = kept.map { it.signalId }.toSet()
        val seen = HashSet<String>()
        return wanted.filter { it in onPage && it !in shown && seen.add(it) }.take(maxCrops)
    }

    /** Places the hidden view on one part of the page and takes its picture. */
    private suspend fun picture(
        controller: ReplicaWebController,
        density: Float,
        focusY: Double,
        height: Float,
        leadIn: Float,
        marks: List<ReplicaMark>,
    ): Attempt<PagePicture> {
        val webView = controller.webView
        if (!place(webView, density, focusY, height, leadIn)) return Attempt(null, RenderFailure.PLACE)
        // The taller frame shows page parts the WebView has not painted yet; there is no paint-done event without JS,
        // so let the new size lay out and give the tiles a moment. Pages sized with `vh` change height with the
        // frame: place once more on the final size.
        awaitLayout(webView)
        controller.waitForLayout()
        if (!place(webView, density, focusY, height, leadIn)) return Attempt(null, RenderFailure.PLACE)
        awaitLayout(webView)
        delay(paintDelayMillis)

        val image = withTimeoutOrNull(snapshotTimeoutMillis) { draw(webView, density) }
            ?: return Attempt(null, RenderFailure.SNAPSHOT)

        // Marks follow where the picture really starts, after the WebView clamped the offset.
        val zoom = zoomPx(webView)
        val topCSS = webView.scrollY / zoom
        return Attempt(
            PagePicture(
                image = image,
                cssWidth = webView.width / zoom,
                marks = shifted(marks, topCSS, webView.height / zoom),
            ),
            null,
        )
    }

    /** Pixels per CSS px (iOS `zoomScale`, in pixels instead of points). */
    @Suppress("DEPRECATION")
    private fun zoomPx(webView: android.webkit.WebView): Float = webView.scale.coerceAtLeast(0.01f)

    /** Sizes the view to the kept part and scrolls to it. `false` for an empty page. */
    private fun place(webView: android.webkit.WebView, density: Float, focusY: Double, height: Float, leadIn: Float): Boolean {
        val zoom = zoomPx(webView)
        val contentHeight = webView.contentHeight * zoom
        if (contentHeight <= 0f) return false
        val kept = window(focusY, zoom, contentHeight, height * density, leadIn * density)
        val params = webView.layoutParams
        val heightPx = kept.second.roundToInt().coerceAtLeast(1)
        if (params.height != heightPx) {
            params.height = heightPx
            webView.layoutParams = params
        }
        webView.scrollTo(0, kept.first.roundToInt())
        return true
    }

    /** Waits for the next layout pass of `view` (at most 500 ms). */
    private suspend fun awaitLayout(view: View) {
        if (!view.isLayoutRequested) return
        withTimeoutOrNull(500) {
            suspendCancellableCoroutine { continuation ->
                val listener = object : View.OnLayoutChangeListener {
                    override fun onLayoutChange(
                        v: View?, left: Int, top: Int, right: Int, bottom: Int,
                        oldLeft: Int, oldTop: Int, oldRight: Int, oldBottom: Int,
                    ) {
                        view.removeOnLayoutChangeListener(this)
                        if (continuation.isActive) continuation.resume(Unit)
                    }
                }
                view.addOnLayoutChangeListener(listener)
                continuation.invokeOnCancellation { view.removeOnLayoutChangeListener(listener) }
            }
        }
    }

    /** The visible part of the view, drawn into a bitmap at up to 3 px per dp. */
    private fun draw(webView: android.webkit.WebView, density: Float): ImageBitmap? {
        val width = webView.width
        val height = webView.height
        if (width <= 0 || height <= 0) return null
        val scale = minOf(density, maxImageScale) / density
        val bitmap = try {
            Bitmap.createBitmap(
                (width * scale).roundToInt().coerceAtLeast(1),
                (height * scale).roundToInt().coerceAtLeast(1),
                Bitmap.Config.ARGB_8888,
            )
        } catch (_: OutOfMemoryError) {
            return null
        }
        val canvas = Canvas(bitmap)
        canvas.scale(scale, scale)
        // A view draws its content in scrolled coordinates; its parent normally moves the canvas for it.
        canvas.translate(-webView.scrollX.toFloat(), -webView.scrollY.toFloat())
        webView.draw(canvas)
        return bitmap.asImageBitmap()
    }

    /** The part of the page we keep, in view px: `leadIn` above the focus, inside the page. */
    fun window(focusY: Double, zoom: Float, contentHeight: Float, height: Float, leadIn: Float): Pair<Float, Float> {
        val kept = minOf(height, contentHeight)
        val focus = if (focusY.isFinite()) maxOf(0.0, focusY).toFloat() * zoom else 0f
        val top = minOf(maxOf(0f, focus - leadIn), contentHeight - kept)
        return top to kept
    }

    /** Marks that touch the kept part, measured from its top. */
    fun shifted(marks: List<ReplicaMark>, topCSS: Float, heightCSS: Float): List<ReplicaMark> = marks.mapNotNull { mark ->
        if (mark.rect.bottom <= topCSS || mark.rect.top >= topCSS + heightCSS) {
            null
        } else {
            ReplicaMark(mark.signalId, mark.rect.translate(0f, -topCSS))
        }
    }

    /** `true` on `onPageFinished`; `false` on failure, a dead render process, or `loadTimeoutMillis`. */
    private suspend fun finished(controller: ReplicaWebController, html: String): Boolean =
        withTimeoutOrNull(loadTimeoutMillis) {
            suspendCancellableCoroutine { continuation ->
                controller.onFinish = { if (continuation.isActive) continuation.resume(true) }
                controller.onFailure = { if (continuation.isActive) continuation.resume(false) }
                continuation.invokeOnCancellation {
                    controller.onFinish = null
                    controller.onFailure = null
                }
                controller.load(html)
            }
        } ?: false
}
