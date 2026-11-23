package com.shoo.app.app

import com.shoo.app.data.ApiClient
import java.net.URI
import java.net.URLDecoder

/**
 * Links that open the app (contracts/app-group-keys.md "Deep links"). Anything unknown or malformed is `Unknown` and
 * opens Shield. Nothing here acts on its own: a join link only fills in the code. Pure Kotlin, so JVM tests cover it.
 */
sealed interface DeepLink {
    /** `shoo://join?code=123456`, or the invite link `https://<api host>/j/123456` (QR, WhatsApp, App Link, PR-03). */
    data class Join(val code: String) : DeepLink

    /** `shoo://scan/{scanId}`: Detail on the Activity tab (D-alief-C13). */
    data class Scan(val id: String) : DeepLink

    /** `shoo://activity`: the Activity list. */
    data object Activity : DeepLink

    data object Unknown : DeepLink

    companion object {
        /**
         * Hosts whose `/j/<code>` page is ours: the backend this build talks to, the public host (join.shoo.ai.id),
         * and the cloud Worker's workers.dev host, where links handed out before PR-03 moved them still point.
         */
        val inviteHosts: Set<String>
            get() = listOf(AppConfig.apiBaseURL, AppConfig.publicBaseURL, AppConfig.cloudAPIURL)
                .mapNotNull { host(it) }.toSet()

        const val codeLength = 6

        fun from(url: String, inviteHosts: Set<String> = DeepLink.inviteHosts, api: String = AppConfig.apiBaseURL): DeepLink {
            val uri = try {
                URI(url)
            } catch (_: Exception) {
                return Unknown
            }
            val scheme = uri.scheme?.lowercase()
            if (scheme == "shoo") {
                return when (uri.host?.lowercase()) {
                    "join" -> join(uri)
                    "scan" -> {
                        // Exactly one path segment, a plain id (`shoo://scan/../devices` is not one).
                        val parts = (uri.rawPath ?: "").split("/")
                        if (parts.size == 2 && parts[0].isEmpty() && ApiClient.isPlainSegment(parts[1])) Scan(parts[1]) else Unknown
                    }
                    "activity" -> Activity
                    else -> Unknown
                }
            }
            if (scheme == "https" || scheme == "http") {
                val host = uri.host?.lowercase() ?: return Unknown
                if (host !in inviteHosts) return Unknown
                return if (scheme == "https" || isLocalWorker(url, api)) joinFromPath(uri) else Unknown
            }
            return Unknown
        }

        /**
         * `http` only for the Worker this build talks to over http (`wrangler dev` in Debug): same host and port.
         * Release talks https only, so no http link is ever accepted there.
         */
        fun isLocalWorker(url: String, api: String = AppConfig.apiBaseURL): Boolean {
            val link = try {
                URI(url)
            } catch (_: Exception) {
                return false
            }
            val apiUri = try {
                URI(api)
            } catch (_: Exception) {
                return false
            }
            return apiUri.scheme == "http" && link.scheme?.lowercase() == "http" &&
                link.host?.lowercase() == apiUri.host?.lowercase() && link.port == apiUri.port
        }

        /** Exactly six ASCII digits, the only code shape the backend issues (contracts/api.md, #128). */
        fun isCode(text: String): Boolean = text.length == codeLength && text.all { it in '0'..'9' }

        private fun host(url: String): String? = try {
            URI(url).host?.lowercase()
        } catch (_: Exception) {
            null
        }

        /** `?code=` exactly once, six ASCII digits. */
        private fun join(uri: URI): DeepLink {
            val codes = (uri.rawQuery ?: "").split("&").filter { it.isNotEmpty() }
                .map { it.split("=", limit = 2) }
                .filter { it[0] == "code" }
            if (codes.size != 1) return Unknown
            // Percent-decoded like `URLQueryItem.value`; `+` stays a plus.
            val raw = codes[0].getOrNull(1) ?: return Unknown
            val code = try {
                URLDecoder.decode(raw.replace("+", "%2B"), "UTF-8")
            } catch (_: Exception) {
                return Unknown
            }
            return if (isCode(code)) Join(code) else Unknown
        }

        /** `/j/<code>`, nothing before or after it. The old `/join?code=` page is gone (#128). */
        private fun joinFromPath(uri: URI): DeepLink {
            val parts = (uri.rawPath ?: "").split("/")
            if (parts.size != 3 || parts[0].isNotEmpty() || parts[1] != "j" || !isCode(parts[2])) return Unknown
            return Join(parts[2])
        }
    }
}
