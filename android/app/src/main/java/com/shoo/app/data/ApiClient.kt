package com.shoo.app.data

import com.shoo.app.support.Log
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.net.URLEncoder
import java.time.Duration
import java.time.Instant
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import kotlin.math.ceil
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * HTTP client for the Shoo backend (contracts/api.md). JSON in and out, ISO 8601 dates,
 * `Authorization: Bearer <token>` on every call except `POST /devices`. Plain `HttpURLConnection` + `org.json`:
 * no extra library in the APK (android/CLAUDE.md).
 *
 * Privacy (SECURITY §3 P6, P9, P13): no HTTP cache, no cookies, no redirects followed, so no answer is ever written
 * to disk and the token never goes to another place; the token and request bodies are never logged.
 */
class ApiClient(
    val baseURL: String,
    /** The session's token. Throws when the store can't be read right now (the call is then `Network`). */
    private val token: () -> String?,
    /** Called on 401 with the token that request carried: a late answer for an older session must not end the
     * current one. */
    private val onUnauthorized: (usedToken: String) -> Unit = {},
) {
    enum class Method { GET, POST, PATCH, DELETE }

    data class Request(
        val method: Method,
        /** Path segments, percent-encoded one by one (`listOf("scans", id)` → `/scans/<id>`). */
        val path: List<String>,
        val query: List<Pair<String, String>> = emptyList(),
        val body: JSONObject? = null,
        /** `false` only for `POST /devices`. */
        val authorized: Boolean = true,
        /** A 401 here means "already gone" to the caller (e.g. `DELETE /devices/me`), not a broken session. */
        val reportsUnauthorized: Boolean = true,
    )

    /** A built request: what goes on the wire. */
    data class Prepared(val url: URL, val method: Method, val headers: Map<String, String>, val body: String?)

    suspend fun <T> send(request: Request, decode: (JSONObject) -> T): T {
        val text = perform(request)
        return try {
            decode(parseObject(text.ifBlank { "{}" }))
        } catch (_: Exception) {
            Log.data.error("Response did not match the contract", request.path.firstOrNull() ?: "")
            throw RepositoryError.Decoding
        }
    }

    fun prepare(request: Request): Prepared {
        // Ids come from the server and from deep links (`shoo://scan/{id}`, T15): a segment that isn't a plain id
        // (`..`, `/`, `%2e`) never leaves the app; to the caller it is a scan that doesn't exist.
        if (!request.path.all { isPlainSegment(it) }) throw RepositoryError.Api(APIErrorCode.notFound, "Invalid id")
        val base = try {
            URI(baseURL)
        } catch (_: Exception) {
            throw RepositoryError.Decoding
        }
        val query = if (request.query.isEmpty()) "" else "?" + request.query.joinToString("&") { (name, value) ->
            encodeQuery(name) + "=" + encodeQuery(value)
        }
        val url = try {
            URL("${base.scheme}://${base.rawAuthority}/" + request.path.joinToString("/") + query)
        } catch (_: Exception) {
            throw RepositoryError.Decoding
        }
        val headers = linkedMapOf("Accept" to "application/json")
        if (request.authorized) {
            val stored = try {
                token()
            } catch (_: Exception) {
                // Keystore not readable right now: try later, the session is fine.
                throw RepositoryError.Network
            }
            // No token: never registered, or the session was just cleared (delete, expiry). A missing token at launch
            // is handled by `AppEnvironment.checkStoredSession()`.
            stored ?: throw RepositoryError.Api(APIErrorCode.unauthorized, "No device session")
            headers["Authorization"] = "Bearer $stored"
        }
        val body = request.body?.toString()
        if (body != null) headers["Content-Type"] = "application/json"
        return Prepared(url, request.method, headers, body)
    }

    private suspend fun perform(request: Request): String {
        val prepared = prepare(request)
        val usedToken = prepared.headers["Authorization"]?.removePrefix("Bearer ")
        val response = withContext(Dispatchers.IO) {
            try {
                exchange(prepared)
            } catch (_: IOException) {
                // A cancelled call stays a cancellation, not "no connection".
                ensureActive()
                throw RepositoryError.Network
            }
        }
        if (response.status !in 200..299) {
            val error = error(response.status, response.body, retryAfter(response.retryAfter))
            // Only the backend's own `unauthorized` body ends the session. A 401 from a captive portal, proxy or edge
            // has no contract body and must not wipe the token and the guardian link.
            if (isContractUnauthorized(response.body) && request.reportsUnauthorized && usedToken != null) {
                onUnauthorized(usedToken)
            }
            throw error
        }
        return response.body
    }

    private class Response(val status: Int, val body: String, val retryAfter: String?)

    // iOS: the request runs until it answers; a cancelled coroutine waits for this blocking call to end (≤ 20 s).
    private fun exchange(prepared: Prepared): Response {
        val connection = prepared.url.openConnection() as HttpURLConnection
        try {
            // Android's HttpURLConnection (OkHttp inside) accepts PATCH; the plain JVM one does not.
            connection.requestMethod = prepared.method.name
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            for ((name, value) in prepared.headers) connection.setRequestProperty(name, value)
            if (prepared.body != null) {
                connection.doOutput = true
                connection.outputStream.use { it.write(prepared.body.toByteArray(Charsets.UTF_8)) }
            }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
            return Response(status, text, connection.getHeaderField("Retry-After"))
        } finally {
            connection.disconnect()
        }
    }

    companion object {
        private const val TIMEOUT_MS = 20_000

        /** The longest wait taken from a `Retry-After`: a bad header can't lock a screen for days (seconds). */
        const val maxRetryAfter: Double = 24.0 * 60 * 60

        /** Route names and ids: letters, digits, `_` and `-` only (UUIDs, `dev_…`), at most 128. */
        fun isPlainSegment(segment: String): Boolean =
            segment.length in 1..128 && segment.all { it.code < 128 && (it.isLetterOrDigit() || it == '_' || it == '-') }

        /** `{"error":{"code":"unauthorized"}}`, the body the backend sends with every 401 (backend/api/src/http/errors.ts). */
        fun isContractUnauthorized(body: String): Boolean {
            val detail = errorBody(body) ?: return false
            return APIErrorCode(detail.code) == APIErrorCode.unauthorized
        }

        /** The contract error body, or a common code from the HTTP status when the body is not one (a proxy page, an
         * empty 502). */
        fun error(status: Int, body: String, retryAfter: Double? = null): RepositoryError {
            val detail = errorBody(body)
            if (detail != null) {
                val code = APIErrorCode(detail.code)
                if (status == 429 && retryAfter != null) return RepositoryError.Throttled(code, detail.message, retryAfter)
                return RepositoryError.Api(code, detail.message)
            }
            val code = when (status) {
                401 -> APIErrorCode.unauthorized
                403 -> APIErrorCode.forbidden
                404 -> APIErrorCode.notFound
                413 -> APIErrorCode.tooLarge
                429 -> APIErrorCode.rateLimited
                else -> APIErrorCode.internal
            }
            if (status == 429 && retryAfter != null) return RepositoryError.Throttled(code, "HTTP 429", retryAfter)
            return RepositoryError.Api(code, "HTTP $status")
        }

        /** `Retry-After` as seconds (what the backend sends) or an HTTP date (RFC 9110 §10.2.3); null when absent or
         * unreadable. */
        fun retryAfter(value: String?, now: Instant = Instant.now()): Double? {
            val text = value?.trim()?.takeIf { it.isNotEmpty() } ?: return null
            val seconds: Double = text.toIntOrNull()?.toDouble()
                ?: try {
                    val date = ZonedDateTime.parse(text, DateTimeFormatter.RFC_1123_DATE_TIME).toInstant()
                    ceil(Duration.between(now, date).toMillis() / 1000.0)
                } catch (_: Exception) {
                    return null
                }
            return seconds.coerceIn(0.0, maxRetryAfter)
        }

        private fun errorBody(body: String): APIErrorBody.Detail? = try {
            APIErrorBody.fromJson(JSONObject(body)).error
        } catch (_: Exception) {
            null
        }

        /** Query values percent-encoded (RFC 3986: a space is `%20`, never `+`). */
        private fun encodeQuery(text: String): String = URLEncoder.encode(text, "UTF-8").replace("+", "%20")

    }
}
