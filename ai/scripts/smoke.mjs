#!/usr/bin/env node
// Smoke test for a running service (local or deployed):  node ai/scripts/smoke.mjs <base-url> [runs]
// Sends ONLY an invented page (no real browsing data) and checks both endpoints, the security headers and latency.
// Exit 0 = all good, 1 = something failed. Prints numbers, never page content.
const base = process.argv[2];
const runs = Math.min(50, Math.max(5, Number(process.argv[3]) || 30)); // capped: each run is a real request (and may cost LLM budget)
if (!base) {
    console.error("usage: node ai/scripts/smoke.mjs <base-url> [runs]");
    process.exit(2);
}
const url = (p) => new URL(p, base).toString();
const failures = [];
const check = (ok, msg) => {
    if (!ok) failures.push(msg);
    console.log(`${ok ? "ok  " : "FAIL"} ${msg}`);
};

const snapshot = {
    url: "https://verif-akun-aman.invalid/login",
    domain: "verif-akun-aman.invalid",
    title: "Verifikasi akun",
    lang: "id",
    text: "Akun Anda akan diblokir dalam 24 jam. Masukkan PIN.",
    forms: [{ action: null, fields: [{ type: "text", name: "pin", id: null, label: "PIN", placeholder: null, autocomplete: null }] }],
    imageAlts: [],
    capturedAt: new Date().toISOString(),
};
if (!/^https:\/\//.test(base) && !/^http:\/\/(127\.0\.0\.1|localhost)[:/]/.test(base)) {
    console.error("refusing a non-local http:// base URL");
    process.exit(2);
}
const post = () =>
    fetch(url("/analyze"), { method: "POST", headers: { "content-type": "application/json", authorization: "Bearer smoke" }, body: JSON.stringify({ snapshot, localSignals: [] }), signal: AbortSignal.timeout(15000) });

const res = await post();
const body = await res.json().catch(() => null);
check(res.status === 200, `POST /analyze -> ${res.status}`);
check(Array.isArray(body?.signals) && body.signals.some((s) => s.id === "asks_pin" && s.layer === 3), "/analyze returns the asks_pin signal (layer 3)");
for (const [h, want] of [["x-content-type-options", "nosniff"], ["referrer-policy", "no-referrer"], ["cache-control", "no-store"], ["cross-origin-resource-policy", "cross-origin"]]) check(res.headers.get(h) === want, `header ${h}`);
check(/max-age=/.test(res.headers.get("strict-transport-security") ?? ""), "header strict-transport-security");
check(/default-src 'none'/.test(res.headers.get("content-security-policy") ?? ""), "header content-security-policy");

// CORS: only an extension origin is ever allowed; a web page gets nothing, and text/plain (no preflight) is refused.
const pre = await fetch(url("/analyze"), { method: "OPTIONS", headers: { origin: "safari-web-extension://smoke", "access-control-request-method": "POST", "access-control-request-headers": "content-type" } });
check(pre.status === 204 && pre.headers.get("access-control-allow-origin") === "safari-web-extension://smoke", `OPTIONS /analyze from the extension -> ${pre.status}, allow-origin echoed`);
const web = await fetch(url("/analyze"), { method: "OPTIONS", headers: { origin: "https://evil.invalid", "access-control-request-method": "POST" } });
check(web.headers.get("access-control-allow-origin") === null, "OPTIONS /analyze from a web page -> no allow-origin");
const plain = await fetch(url("/analyze"), { method: "POST", headers: { "content-type": "text/plain" }, body: JSON.stringify({ snapshot, localSignals: [] }) });
check(plain.status === 422, `text/plain POST /analyze -> ${plain.status} (want 422)`);

const bl = await fetch(url("/public-blocklist"), { headers: { authorization: "Bearer smoke" } });
const list = await bl.json().catch(() => null);
check(bl.status === 200, `GET /public-blocklist -> ${bl.status}`);
check(Array.isArray(list?.domains) && "nextSince" in (list ?? {}), `/public-blocklist shape (${list?.domains?.length ?? "?"} domains)`);
const bad = await fetch(url("/public-blocklist?since=bad"));
check(bad.status === 422, `bad since -> ${bad.status} (want 422 invalid_body)`);

const times = [];
for (let i = 0; i < runs; i++) {
    const t = performance.now();
    const r = await post();
    await r.arrayBuffer();
    if (r.status === 429) {
        console.log("note: rate limited during the latency run; use fewer runs or wait");
        break;
    }
    times.push(performance.now() - t);
}
times.sort((a, b) => a - b);
const p = (q) => times[Math.min(times.length - 1, Math.floor(times.length * q))];
check(times.length >= 5, `enough latency samples (${times.length})`);
if (times.length) {
    console.log(`latency /analyze over ${times.length} runs: p50 ${p(0.5).toFixed(0)} ms, p95 ${p(0.95).toFixed(0)} ms, max ${times[times.length - 1].toFixed(0)} ms`);
    check(p(0.95) < 8000, "p95 < 8000 ms");
}
process.exit(failures.length ? 1 : 0);
