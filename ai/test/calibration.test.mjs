// Phase 07 calibration rules (D-imelda-04: a single ambiguous signal must not reach the popup threshold alone;
// official and popular sites stay below 30 even with sensitive forms; pages that ask for nothing are not scam-weighted by words alone).
import test from "node:test";
import assert from "node:assert/strict";
import { analyze } from "../src/analyze.js";
import { BRANDS, field, page } from "./helpers.mjs";
import { POPULAR, SHARED_HOSTS } from "../src/blocklist/allowlist.js";

const score = (signals) => Math.min(100, signals.reduce((s, x) => s + x.weight, 0));
const run = (url, fields, over) => analyze(page(url, fields, over));
const POPUP = 30;

const FORMS = {
    password: [field({ type: "email", name: "email" }), field({ type: "password", name: "password" })],
    otp: [field({ name: "otp", label: "Kode OTP" })],
    pin: [field({ name: "pin", label: "PIN" })],
    card: [field({ name: "card_number", label: "Nomor kartu" }), field({ name: "cvv" })],
    ktp: [field({ name: "nik", label: "Nomor KTP" })],
};

test("official domains and their subdomains: every sensitive form stays below 30", async () => {
    for (const brand of BRANDS.brands) {
        for (const domain of brand.domains) {
            for (const [kind, fields] of Object.entries(FORMS)) {
                const signals = await run(`https://login.${domain}/masuk`, fields);
                assert.ok(score(signals) < POPUP, `${domain} ${kind}: ${score(signals)}`);
            }
        }
    }
});

test("popular sites (allowlist): login / OTP / card forms stay below 30", async () => {
    for (const domain of POPULAR) {
        if (SHARED_HOSTS.has(domain)) continue;
        for (const [kind, fields] of Object.entries(FORMS)) {
            const signals = await run(`https://www.${domain}/login`, fields);
            assert.ok(score(signals) < POPUP, `${domain} ${kind}: ${score(signals)}`);
        }
    }
});

test("an ambiguous field alone (OTP, card, CVV, KTP, password) never reaches 30 on an unknown site", async () => {
    for (const fields of [FORMS.otp, [FORMS.card[0]], [FORMS.card[1]], FORMS.ktp, FORMS.password]) {
        const s = score(await run("https://toko-kecil.example.xyz/akun", fields));
        assert.ok(s < POPUP, `${fields.map((f) => f.name)}: ${s}`);
    }
});

test("a PIN request stays strong on an unknown site (specific scam sign)", async () => {
    assert.ok(score(await run("https://toko-kecil.example.xyz/akun", FORMS.pin)) >= POPUP);
});

test("words alone: a page with no form that mentions a bank logo and 'terakhir hari ini' stays below 30", async () => {
    const snap = { imageAlts: ["Logo BCA", "Logo Mandiri"], text: "Diskon terakhir hari ini! Pembayaran via transfer bank.", title: "Promo toko" };
    const s = score(await run("https://toko-kecil.example.xyz/promo", [], snap));
    assert.ok(s < POPUP, String(s));
});

test("words alone: a news article quoting a block threat and a logo stays below 30", async () => {
    const snap = { imageAlts: ["Logo BRI"], text: "Pelaku mengirim pesan: rekening Anda akan diblokir dalam 24 jam.", title: "Waspada penipuan" };
    const s = score(await run("https://berita-kecil.example.xyz/waspada", [], snap));
    assert.ok(s < POPUP, String(s));
});

test("words still count at full weight when the page also asks for something sensitive", async () => {
    const snap = { imageAlts: ["Logo BCA"], text: "Rekening Anda akan diblokir dalam 24 jam. Segera verifikasi.", title: "Verifikasi BCA" };
    const signals = await run("https://verif-bca-aman.example.xyz/login", FORMS.pin, snap);
    const byId = Object.fromEntries(signals.map((x) => [x.id, x.weight]));
    assert.equal(byId.urgent_language, 15);
    assert.equal(byId.brand_logo_offsite, 25);
});
