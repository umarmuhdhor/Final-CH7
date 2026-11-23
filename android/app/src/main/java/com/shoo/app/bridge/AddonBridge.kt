package com.shoo.app.bridge

import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.security.SecureRandom
import org.json.JSONObject

/**
 * Hands the session to the Shoo add-on in Firefox for Android, which has no native messaging (Safari's
 * `getSession`, contracts/app-group-keys.md). Runs only while the user is linking:
 *
 * - listens on 127.0.0.1 only, for at most [LIFETIME_MS];
 * - answers one route, `POST /pair` with `{ code }`, the one-time 6-digit code shown in the app;
 * - refuses requests from web pages (their `Origin` is a website; the add-on's is `moz-extension://` or none),
 *   sends no CORS headers, and stops after [MAX_ATTEMPTS] wrong codes or the first success.
 *
 * The reply is the getSession shape: `{ ok, session: { deviceId, token, mode, name, guardianName, apiBaseURL,
 * aiBaseURL, autoSend, shareWarnings } }`. Pure parsing lives in [BridgeProtocol] (unit tested).
 */
class AddonBridge(
    private val session: () -> JSONObject?,
    private val onLinked: () -> Unit,
    private val onClosed: (reason: String) -> Unit,
) {
    @Volatile private var server: ServerSocket? = null
    @Volatile var code: String? = null
        private set
    @Volatile var expiresAt: Long = 0
        private set
    private var attempts = 0

    val isRunning get() = server != null

    /** Starts listening and returns the code to show. Throws if the port is taken. */
    fun start(now: Long = System.currentTimeMillis()): String {
        stop("restart")
        val socket = ServerSocket(PORT, 4, InetAddress.getByName("127.0.0.1"))
        val newCode = BridgeProtocol.newCode(SecureRandom())
        code = newCode
        expiresAt = now + LIFETIME_MS
        attempts = 0
        server = socket
        Thread({ serve(socket) }, "shoo-addon-bridge").apply { isDaemon = true }.start()
        return newCode
    }

    fun stop(reason: String = "stopped") {
        val socket = server ?: return
        server = null
        code = null
        runCatching { socket.close() }
        onClosed(reason)
    }

    private fun serve(socket: ServerSocket) {
        socket.soTimeout = 1000
        while (server === socket) {
            if (System.currentTimeMillis() > expiresAt) return stop("expired")
            val client = try {
                socket.accept()
            } catch (_: java.net.SocketTimeoutException) {
                continue
            } catch (_: Exception) {
                return
            }
            runCatching { client.use(::handle) }
        }
    }

    private fun handle(client: Socket) {
        client.soTimeout = 5000
        val request = BridgeProtocol.read(BufferedReader(InputStreamReader(client.getInputStream())))
        val reply = decide(request)
        client.getOutputStream().write(BridgeProtocol.response(reply.status, reply.body))
        client.getOutputStream().flush()
        when (reply.after) {
            After.LINKED -> {
                onLinked()
                stop("linked")
            }
            After.LOCKED -> stop("locked")
            After.NONE -> Unit
        }
    }

    private enum class After { NONE, LINKED, LOCKED }
    private class Reply(val status: Int, val body: JSONObject, val after: After = After.NONE)

    private fun decide(request: BridgeProtocol.Request?): Reply {
        fun error(status: Int, code: String, after: After = After.NONE) =
            Reply(status, JSONObject().put("ok", false).put("error", code), after)

        if (request == null) return error(400, "bad_request")
        if (!BridgeProtocol.originAllowed(request.origin)) return error(403, "forbidden")
        if (request.method != "POST" || request.path != "/pair") return error(404, "not_found")
        val expected = code ?: return error(410, "expired")
        val given = runCatching { JSONObject(request.body).optString("code") }.getOrDefault("")
        if (!MessageDigest.isEqual(given.toByteArray(), expected.toByteArray())) {
            attempts += 1
            return if (attempts >= MAX_ATTEMPTS) error(403, "locked", After.LOCKED) else error(403, "code_invalid")
        }
        val payload = session() ?: return error(409, "not_onboarded")
        return Reply(200, JSONObject().put("ok", true).put("session", payload), After.LINKED)
    }

    companion object {
        const val PORT = 47613
        const val LIFETIME_MS = 10 * 60 * 1000L
        const val MAX_ATTEMPTS = 5
    }
}

/** HTTP/1.1 parsing and the origin rule, kept free of Android so plain JVM tests cover them. */
object BridgeProtocol {
    data class Request(val method: String, val path: String, val origin: String?, val body: String)

    fun newCode(random: SecureRandom): String = (1..6).joinToString("") { random.nextInt(10).toString() }

    /** No Origin (some extension requests) or the add-on's own `moz-extension://` origin. Never a website. */
    fun originAllowed(origin: String?): Boolean = origin == null || origin.startsWith("moz-extension://")

    fun read(reader: BufferedReader): Request? {
        val line = reader.readLine() ?: return null
        val parts = line.split(" ")
        if (parts.size < 2) return null
        var length = 0
        var origin: String? = null
        while (true) {
            val header = reader.readLine() ?: break
            if (header.isEmpty()) break
            val colon = header.indexOf(':')
            if (colon <= 0) continue
            val name = header.substring(0, colon).trim().lowercase()
            val value = header.substring(colon + 1).trim()
            when (name) {
                "content-length" -> length = value.toIntOrNull()?.coerceIn(0, 4096) ?: 0
                "origin" -> origin = value.takeUnless { it == "null" } ?: "null"
            }
        }
        val body = CharArray(length)
        var read = 0
        while (read < length) {
            val n = reader.read(body, read, length - read)
            if (n < 0) break
            read += n
        }
        return Request(parts[0], parts[1], origin, String(body, 0, read))
    }

    fun response(status: Int, body: JSONObject): ByteArray {
        val bytes = body.toString().toByteArray()
        val reason = when (status) {
            200 -> "OK"; 400 -> "Bad Request"; 403 -> "Forbidden"; 404 -> "Not Found"; 409 -> "Conflict"; else -> "Gone"
        }
        val head = "HTTP/1.1 $status $reason\r\nContent-Type: application/json\r\nContent-Length: ${bytes.size}\r\n" +
            "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        return head.toByteArray() + bytes
    }
}
