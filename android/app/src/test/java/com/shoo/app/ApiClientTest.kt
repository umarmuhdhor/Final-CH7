package com.shoo.app

import com.shoo.app.data.APIErrorCode
import com.shoo.app.data.ApiClient
import com.shoo.app.data.RepositoryError
import java.time.Instant
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS APIClientTests: the parts that need no network (request building, error mapping, Retry-After). */
class ApiClientTest {
    private fun client(token: () -> String? = { "tok" }) = ApiClient("https://api.example", token)

    @Test fun plainSegmentsOnly() {
        assertTrue(ApiClient.isPlainSegment("6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03"))
        assertTrue(ApiClient.isPlainSegment("dev_me"))
        assertFalse(ApiClient.isPlainSegment(""))
        assertFalse(ApiClient.isPlainSegment(".."))
        assertFalse(ApiClient.isPlainSegment("a/b"))
        assertFalse(ApiClient.isPlainSegment("%2e"))
        assertFalse(ApiClient.isPlainSegment("é"))
        assertFalse(ApiClient.isPlainSegment("a".repeat(129)))
    }

    @Test fun aPathThatIsNotAnIdNeverLeaves() {
        val error = runCatching {
            client().prepare(ApiClient.Request(ApiClient.Method.GET, listOf("scans", "..")))
        }.exceptionOrNull()
        assertEquals(RepositoryError.Api(APIErrorCode.notFound, "Invalid id"), error)
    }

    @Test fun requestCarriesTheBearerAndQuery() {
        val prepared = client().prepare(
            ApiClient.Request(
                ApiClient.Method.GET, listOf("scans"), query = listOf("owner" to "family", "cursor" to "a b+c"),
            ),
        )
        assertEquals("https://api.example/scans?owner=family&cursor=a%20b%2Bc", prepared.url.toString())
        assertEquals("Bearer tok", prepared.headers["Authorization"])
        assertNull(prepared.headers["Content-Type"])
    }

    @Test fun registrationIsNotAuthorizedAndSendsJson() {
        val prepared = client { null }.prepare(
            ApiClient.Request(ApiClient.Method.POST, listOf("devices"), body = JSONObject().put("name", "Mom"), authorized = false),
        )
        assertNull(prepared.headers["Authorization"])
        assertEquals("application/json", prepared.headers["Content-Type"])
        assertEquals("""{"name":"Mom"}""", prepared.body)
    }

    @Test fun noTokenIsUnauthorizedAndALockedStoreIsNetwork() {
        val missing = runCatching { client { null }.prepare(ApiClient.Request(ApiClient.Method.GET, listOf("devices", "me"))) }
        assertEquals(APIErrorCode.unauthorized, (missing.exceptionOrNull() as RepositoryError).apiCode)
        val locked = runCatching {
            client { throw IllegalStateException("locked") }.prepare(ApiClient.Request(ApiClient.Method.GET, listOf("devices", "me")))
        }
        assertEquals(RepositoryError.Network, locked.exceptionOrNull())
    }

    @Test fun contractBodyWins() {
        val body = """{"error":{"code":"code_expired","message":"Code expired"}}"""
        assertEquals(RepositoryError.Api(APIErrorCode.codeExpired, "Code expired"), ApiClient.error(410, body))
    }

    @Test fun statusWithoutBodyMapsToCommonCode() {
        assertEquals(APIErrorCode.unauthorized, ApiClient.error(401, "").apiCode)
        assertEquals(APIErrorCode.forbidden, ApiClient.error(403, "<html>").apiCode)
        assertEquals(APIErrorCode.notFound, ApiClient.error(404, "").apiCode)
        assertEquals(APIErrorCode.tooLarge, ApiClient.error(413, "").apiCode)
        assertEquals(APIErrorCode.rateLimited, ApiClient.error(429, "").apiCode)
        assertEquals(APIErrorCode.internal, ApiClient.error(502, "").apiCode)
    }

    @Test fun throttledCarriesRetryAfter() {
        val body = """{"error":{"code":"too_many_attempts","message":"Slow down"}}"""
        val error = ApiClient.error(429, body, retryAfter = 299.0)
        assertEquals(RepositoryError.Throttled(APIErrorCode.tooManyAttempts, "Slow down", 299.0), error)
        assertEquals(299.0, error.retryAfter!!, 0.0)
    }

    @Test fun onlyTheContractBodyEndsTheSession() {
        assertTrue(ApiClient.isContractUnauthorized("""{"error":{"code":"unauthorized","message":"x"}}"""))
        assertFalse(ApiClient.isContractUnauthorized("<html>Login to Wi-Fi</html>"))
        assertFalse(ApiClient.isContractUnauthorized(""))
    }

    @Test fun retryAfterSecondsAndDates() {
        val now = Instant.parse("2026-10-21T04:05:00Z")
        assertEquals(120.0, ApiClient.retryAfter("120", now)!!, 0.0)
        assertEquals(0.0, ApiClient.retryAfter("-5", now)!!, 0.0)
        assertEquals(ApiClient.maxRetryAfter, ApiClient.retryAfter("9999999", now)!!, 0.0)
        assertEquals(60.0, ApiClient.retryAfter("Wed, 21 Oct 2026 04:06:00 GMT", now)!!, 0.0)
        assertNull(ApiClient.retryAfter(null, now))
        assertNull(ApiClient.retryAfter("  ", now))
        assertNull(ApiClient.retryAfter("soon", now))
    }
}
