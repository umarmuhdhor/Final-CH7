package com.shoo.app

import com.shoo.app.bridge.BridgeProtocol
import java.io.BufferedReader
import java.io.StringReader
import java.security.SecureRandom
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BridgeProtocolTest {
    private fun read(raw: String) = BridgeProtocol.read(BufferedReader(StringReader(raw)))

    @Test fun readsPostWithBodyAndOrigin() {
        val body = """{"code":"123456"}"""
        val request = read("POST /pair HTTP/1.1\r\nHost: 127.0.0.1\r\nOrigin: moz-extension://abc\r\nContent-Length: ${body.length}\r\n\r\n$body")!!
        assertEquals("POST", request.method)
        assertEquals("/pair", request.path)
        assertEquals("moz-extension://abc", request.origin)
        assertEquals("123456", JSONObject(request.body).getString("code"))
    }

    @Test fun capsTheBody() {
        val request = read("POST /pair HTTP/1.1\r\nContent-Length: 999999\r\n\r\n{}")!!
        assertEquals("{}", request.body)
    }

    @Test fun emptyRequest() = assertNull(read(""))

    @Test fun onlyTheAddonOrNoOrigin() {
        assertTrue(BridgeProtocol.originAllowed(null))
        assertTrue(BridgeProtocol.originAllowed("moz-extension://7f3e"))
        assertFalse(BridgeProtocol.originAllowed("https://scam.example"))
        assertFalse(BridgeProtocol.originAllowed("null"))
        assertFalse(BridgeProtocol.originAllowed("http://127.0.0.1:8080"))
    }

    @Test fun codesAreSixDigits() {
        repeat(50) { assertTrue(BridgeProtocol.newCode(SecureRandom()).matches(Regex("^\\d{6}$"))) }
    }

    @Test fun responseHasNoCorsHeaders() {
        val text = String(BridgeProtocol.response(200, JSONObject().put("ok", true)))
        assertTrue(text.startsWith("HTTP/1.1 200 OK"))
        assertFalse(text.contains("Access-Control", ignoreCase = true))
    }
}
