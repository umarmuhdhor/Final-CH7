package com.shoo.app.features.detail

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.view.ActionMode
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.webkit.CookieManager
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.os.Message
import java.io.ByteArrayInputStream
import kotlinx.coroutines.delay

/**
 * K11: every URL other than `data:` and `about:` is blocked inside the replica web view.
 * This is the network lock under the CSP; the lexical gate in `ReplicaHTML` is the one above it.
 * iOS compiles a `WKContentRuleList`; Android blocks the same URLs in `shouldInterceptRequest`, and
 * `WebSettings.blockNetworkLoads` stops the network underneath both.
 */
object ReplicaRules {
    const val identifier = "shoo-replica-v1"

    fun allows(url: String): Boolean {
        val lower = url.trimStart().lowercase()
        return lower.startsWith("data:") || lower.startsWith("about:")
    }
}

/**
 * K12: no selection menu, no callout (Share, Translate, Save image), no keyboard. The evidence must not leave the
 * app (P9); the injected CSS can lose to inline `!important`, this can't.
 */
@SuppressLint("ViewConstructor")
class LockedWebView(context: Context) : WebView(context) {
    override fun startActionMode(callback: ActionMode.Callback?): ActionMode? = null

    override fun startActionMode(callback: ActionMode.Callback?, type: Int): ActionMode? = null

    override fun onCreateInputConnection(outAttrs: EditorInfo?): InputConnection? = null

    override fun onCheckIsTextEditor(): Boolean = false

    override fun performLongClick(): Boolean = true

    override fun requestFocus(direction: Int, previouslyFocusedRect: android.graphics.Rect?): Boolean = false
}

/**
 * Owns one locked web view: loads the replica once, refuses every later navigation. `ReplicaSnapshot` places and
 * draws it; no live web view is shown (fase 18b K12, fase 22 K9).
 *
 * WKWebView settings → WebView: JavaScript off, no file or content access, no network (blocked loads + every
 * non-`data:` request answered empty), no cache, no DOM storage or database, no cookies, no new windows, media only on
 * a gesture (there is none). iOS's non-persistent data store: nothing the page could set is allowed in the first place,
 * and the view is destroyed after the pictures are taken.
 */
class ReplicaWebController(context: Context) {
    companion object {
        /** How long the layout may keep changing after `onPageFinished` before we place the page anyway (K13). */
        const val layoutTimeoutMillis = 2_000L
    }

    val webView = LockedWebView(context)

    /** Navigations refused after the first load (links, forms, `meta refresh`). */
    var refusedNavigations = 0
        private set
    var onFinish: (() -> Unit)? = null
    /** The render process died or the page failed: show the placeholder, never reload. */
    var onFailure: (() -> Unit)? = null

    init {
        configure(webView)
        webView.webViewClient = object : WebViewClient() {
            // The string load itself never comes here; everything that does is the page trying to go somewhere.
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                refusedNavigations += 1
                return true
            }

            @Deprecated("Deprecated in Java")
            override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                refusedNavigations += 1
                return true
            }

            override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
                val url = request?.url?.toString() ?: return blocked()
                return if (ReplicaRules.allows(url)) null else blocked()
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {}

            override fun onPageFinished(view: WebView?, url: String?) {
                onFinish?.invoke()
            }

            override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
                if (request?.isForMainFrame == true) onFailure?.invoke()
            }

            override fun onRenderProcessGone(view: WebView?, detail: RenderProcessGoneDetail?): Boolean {
                onFailure?.invoke()
                // Handled: the app keeps running; `ReplicaSnapshot` removes and destroys this view.
                return true
            }
        }
        webView.webChromeClient = object : WebChromeClient() {
            override fun onCreateWindow(view: WebView?, isDialog: Boolean, isUserGesture: Boolean, resultMsg: Message?): Boolean = false
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    @Suppress("DEPRECATION")
    private fun configure(view: WebView) {
        view.settings.apply {
            javaScriptEnabled = false
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
            allowFileAccess = false
            allowContentAccess = false
            allowFileAccessFromFileURLs = false
            allowUniversalAccessFromFileURLs = false
            blockNetworkLoads = true
            blockNetworkImage = true
            cacheMode = WebSettings.LOAD_NO_CACHE
            domStorageEnabled = false
            databaseEnabled = false
            setGeolocationEnabled(false)
            mediaPlaybackRequiresUserGesture = true
            loadsImagesAutomatically = true
            // The copy lays out at the width in its viewport meta and is zoomed to fit, like WKWebView.
            useWideViewPort = true
            loadWithOverviewMode = true
            setSupportZoom(false)
            builtInZoomControls = false
            displayZoomControls = false
            // The page's own text sizes, like WKWebView (Dynamic Type never reaches web content there).
            textZoom = 100
            // Tiles are painted although the view sits outside the window's visible area.
            offscreenPreRaster = true
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(view, false)
        view.isFocusable = false
        view.isFocusableInTouchMode = false
        view.isLongClickable = false
        view.isHapticFeedbackEnabled = false
        view.setOnLongClickListener { true }
        view.isVerticalScrollBarEnabled = false
        view.isHorizontalScrollBarEnabled = false
        view.overScrollMode = View.OVER_SCROLL_NEVER
        view.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        view.isSaveEnabled = false
    }

    private fun blocked(): WebResourceResponse =
        WebResourceResponse("text/plain", "utf-8", 403, "Blocked", emptyMap(), ByteArrayInputStream(ByteArray(0)))

    /** `html` must come from `ReplicaHTML.locked`. No base URL: the document is `about:blank`, as on iOS. */
    fun load(html: String) {
        webView.loadDataWithBaseURL(null, html, "text/html", "utf-8", null)
    }

    /** Without JS there is no layout-done event: wait until the content height stops changing (or 2 s). */
    suspend fun waitForLayout() {
        val deadline = System.currentTimeMillis() + layoutTimeoutMillis
        var last = -1
        while (System.currentTimeMillis() < deadline) {
            // Cancelled: `delay` throws and the caller cleans up.
            delay(100)
            val height = webView.contentHeight
            if (height == last && height != 0) break
            last = height
        }
    }

    /** After the pictures: nothing of the page stays in the process (iOS: non-persistent data store). */
    fun tearDown() {
        onFinish = null
        onFailure = null
        webView.stopLoading()
        webView.clearHistory()
        webView.clearCache(false)
        webView.destroy()
    }
}
