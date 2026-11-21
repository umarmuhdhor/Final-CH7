package com.shoo.app.app

import android.net.Uri
import com.shoo.app.BuildConfig
import com.shoo.app.support.AppLanguage

/** Build-time configuration (plan/alief/ref/R5 §6): the `BuildConfig` fields of app/build.gradle.kts. */
object AppConfig {
    /**
     * Public host of every link (invite `/j/<code>`, share `/get`): the Custom Domain `join.shoo.ai.id` on the cloud
     * Worker (shoo-api, PR-03). Must equal `INVITE_BASE_URL` in backend/api/wrangler.jsonc.
     */
    val publicBaseURL: String = BuildConfig.PUBLIC_BASE_URL

    /**
     * The cloud Worker (shoo-api) deployed from `main`, on its workers.dev host. Invite links on this host (handed
     * out before PR-03 moved them to `publicBaseURL`) still open the app (`DeepLink.inviteHosts`).
     */
    val cloudAPIURL: String = BuildConfig.CLOUD_API_URL

    /**
     * Debug only (`-debug.backend local`, see `AppEnvironment.live`): `wrangler dev` on the computer, which the
     * emulator reaches at 10.0.2.2. iOS: the simulator build talks to localhost.
     */
    @Volatile
    var usesLocalAPI: Boolean = false

    /** The backend this build talks to: the cloud Worker, or `wrangler dev` in Debug when asked. */
    val apiBaseURL: String
        get() = if (BuildConfig.DEBUG && usesLocalAPI) BuildConfig.LOCAL_API_URL else cloudAPIURL

    /**
     * Team AI service (`POST /analyze`, `GET /public-blocklist`). null = not handed to the add-on, so it skips layer
     * 3–4 instead of sending pages anywhere. Debug builds stay on layer 1–2 (`AI_URL` empty, #82).
     */
    val aiBaseURL: String? = BuildConfig.AI_URL.ifBlank { null }

    /** PF-01 Tentang Shoo: share link and support address, always the public ones. `/get` redirects to the store. */
    val shareURL: String get() = "$publicBaseURL/get"

    /** Must equal `CONTACT` in backend/api/src/routes/privacy.ts. */
    const val supportEmail = "Apple.a.day.bali@gmail.com"

    /** Store id for "Beri nilai". null until the app is listed. iOS: App Store id. */
    val appStoreId: String? = null

    /** The policy or terms page in the app's language, served by the Worker. */
    fun legalPage(path: String, language: AppLanguage): String =
        Uri.parse(apiBaseURL).buildUpon().appendEncodedPath(path.trimStart('/'))
            .appendQueryParameter("lang", language.code).build().toString()

    /** Scan QR (PR-01). Off = Enter code only. */
    const val cameraEnabled = true
}
