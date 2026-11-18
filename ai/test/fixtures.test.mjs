// Phase 03 proof: the two contract fixtures (contracts/fixtures/blocked-92, warning-63) are reproduced roughly:
// every layer 3 signal of the fixture is present; total score within +-10 (blocked-92) or +-12 with a documented gap (warning-63). Snapshots below are built by hand to match each fixture's page;
// RDAP is mocked. The LLM signal (unreasonable_request, layer 4) belongs to phase 06 and is not expected here.
import test from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../src/app.js";
import { loadDetector, scoreOf, statusOf } from "../eval/lib.mjs";
import { field, page, post, readFixture, ids } from "./helpers.mjs";

const NOW = Date.parse("2026-10-22T00:00:00Z");
const bootstrap = { services: [[["site"], ["https://rdap.registry-s.example/"]]] };
const fetchAge = (days) => async (url) =>
    String(url).endsWith("dns.json")
        ? new Response(JSON.stringify(bootstrap))
        : new Response(JSON.stringify({ events: [{ eventAction: "registration", eventDate: new Date(NOW - days * 86_400_000).toISOString() }] }));

// Same id on layer 2 and layer 3 (asks_* since #379): the extension keeps the heavier one, never both
// (ios/ShooExtension/Resources/pipeline.js mergeSignals), so the score here does the same.
function mergeById(signals) {
    const byId = new Map();
    for (const s of signals) if (!byId.has(s.id) || s.weight > byId.get(s.id).weight) byId.set(s.id, s);
    return [...byId.values()];
}

async function reproduce(snapshot, days) {
    const detector = loadDetector();
    const local = await detector.analyzeLocal(snapshot);
    const app = createApp({ fetch: fetchAge(days), now: () => NOW });
    const remote = (await (await post(app, { snapshot, localSignals: local })).json()).signals;
    return { local, remote, score: scoreOf(mergeById([...local, ...remote])) };
}

test("blocked-92: bca-verifikasi.site with a PIN form on a 3-day-old domain", async () => {
    const fx = readFixture("blocked-92.json");
    const snap = page("https://bca-verifikasi.site/login?ref=wa", [field({ type: "password", name: "pin", label: "PIN m-banking" })], {
        title: "KlikBCA - Verifikasi Akun",
        text: "Verifikasi akun KlikBCA Anda. Masukkan PIN m-banking.",
        imageAlts: ["Logo BCA"],
    });
    const { remote, score } = await reproduce(snap, 3);
    const wanted = fx.signals.filter((s) => s.layer === 3).map((s) => s.id).sort(); // new_domain, asks_pin
    for (const id of wanted) assert.ok(ids(remote).includes(id), `fixture signal ${id}`);
    assert.equal(remote.find((s) => s.id === "new_domain").weight, 30, "same weight as the fixture");
    assert.ok(Math.abs(score - fx.score) <= 10, `score ${score} vs fixture ${fx.score}`);
});

test("warning-63: bansos-kemensos.site asks for NIK, deadline wording, domain older than 90 days", async () => {
    const fx = readFixture("warning-63.json");
    const snap = page("https://bansos-kemensos.site/cek", [field({ name: "nik", label: "NIK" })], {
        title: "Cek Penerima Bansos 2026",
        text: "Cek penerima bansos 2026. Pendaftaran terakhir hari ini.",
    });
    const { remote, score } = await reproduce(snap, 400);
    for (const id of fx.signals.filter((s) => s.layer === 3).map((s) => s.id)) assert.ok(ids(remote).includes(id), `fixture signal ${id}`);
    assert.equal(ids(remote).includes("new_domain"), false, "old domain: no new_domain, like the fixture");
    assert.equal(remote.find((s) => s.id === "urgent_language").evidence, "terakhir hari ini");
    // Honest gap: score is 70 vs 63 (+7). urgent_language is 15, not the fixture's 10 (R1/D-imelda-12), and the real layer 2
    // (brand_plus_keyword 14, cheap_tld 16) adds 2 more than the fixture. asks_ktp comes on layer 2 (15) and layer 3 (25):
    // counted once, the heavier. Same signals, same status (warning). Weights are not bent to fit a fixture.
    assert.ok(statusOf(score).startsWith(fx.status), statusOf(score));
    assert.ok(Math.abs(score - fx.score) <= 12, `score ${score} vs fixture ${fx.score}`);
});
