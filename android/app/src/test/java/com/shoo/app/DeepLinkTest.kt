package com.shoo.app

import com.shoo.app.app.DeepLink
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS DeepLinkTests (PairingTests.swift): invite links, scan and activity links. */
class DeepLinkTest {
    private val hosts = setOf("join.shoo.ai.id", "shoo-api.afindo-mi01.workers.dev", "localhost")
    private val releaseApi = "https://shoo-api.afindo-mi01.workers.dev"

    private fun link(url: String) = DeepLink.from(url, inviteHosts = hosts, api = releaseApi)

    @Test fun joinLinksGiveTheCode() {
        listOf(
            "shoo://join?code=482193",
            "https://join.shoo.ai.id/j/482193",
            "https://shoo-api.afindo-mi01.workers.dev/j/482193",
            "https://SHOO-API.afindo-mi01.workers.dev/j/482193",
            "SHOO://JOIN?code=482193",
        ).forEach { assertEquals(it, DeepLink.Join("482193"), link(it)) }
    }

    @Test fun everythingElseIsUnknown() {
        listOf(
            "shoo://join?code=48219",
            "shoo://join?code=4821930",
            "shoo://join?code=4821",
            "shoo://join?code=48a193",
            "shoo://join?code=%D9%A4%D9%A8%D9%A2%D9%A1%D9%A9%D9%A3",
            "shoo://join",
            "shoo://join?code=482193&code=111111",
            "https://evil.example/j/482193",
            "https://shoo-api.afindo-mi01.workers.dev/join?code=482193",
            "https://shoo-api.afindo-mi01.workers.dev/j/4821",
            "https://shoo-api.afindo-mi01.workers.dev/j/482193/x",
            "https://shoo-api.afindo-mi01.workers.dev/x/j/482193",
            "https://shoo-api.afindo-mi01.workers.dev/jj/482193",
            "https://shoo-api.afindo-mi01.workers.dev/j/%34%38%32%31%39%33",
            "http://shoo-api.afindo-mi01.workers.dev/j/482193",
            "shoo://settings",
            "mailto:a@b.c",
            "not a url",
        ).forEach { assertEquals(it, DeepLink.Unknown, link(it)) }
    }

    /** http only for the Worker this build talks to over http, same host and port (never in Release). */
    @Test fun httpOnlyForTheLocalWorker() {
        val local = "http://localhost:8787"
        assertTrue(DeepLink.isLocalWorker("http://localhost:8787/j/482193", api = local))
        assertFalse(DeepLink.isLocalWorker("http://localhost:9999/j/482193", api = local))
        assertFalse(DeepLink.isLocalWorker("http://evil.example:8787/j/482193", api = local))
        assertFalse(DeepLink.isLocalWorker("http://shoo-api.afindo-mi01.workers.dev/j/482193", api = releaseApi))
        assertEquals(DeepLink.Join("482193"), DeepLink.from("http://localhost:8787/j/482193", inviteHosts = hosts, api = local))
    }

    @Test fun scanAndActivityLinks() {
        assertEquals(
            DeepLink.Scan("6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03"),
            link("shoo://scan/6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03"),
        )
        assertEquals(DeepLink.Unknown, link("shoo://scan/../devices"))
        assertEquals(DeepLink.Unknown, link("shoo://scan/"))
        assertEquals(DeepLink.Unknown, link("shoo://scan/a/b"))
        assertEquals(DeepLink.Activity, link("shoo://activity"))
    }

    @Test fun codesAreSixAsciiDigits() {
        assertTrue(DeepLink.isCode("482193"))
        assertFalse(DeepLink.isCode("48219"))
        assertFalse(DeepLink.isCode("٤٨٢١٩٣"))
    }
}
