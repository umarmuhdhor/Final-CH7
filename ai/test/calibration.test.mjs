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

test("words keep full weight when the domain itself already looks like impersonation (layer 2 evidence from the extension)", async () => {
    const snap = { imageAlts: ["Logo OVO"], text: "Undian berhadiah. Klaim sekarang!", title: "Undian OVO" };
    const quiet = await analyze(page("https://undian-ovo.example.xyz/", [], snap));
    assert.equal(quiet.find((x) => x.id === "brand_logo_offsite").weight, 12);
    const layer2 = [{ id: "brand_plus_keyword", layer: 2, weight: 14, label: { en: "x", id: "x" }, labelSimple: { en: "x", id: "x" } }];
    const loud = await analyze(page("https://undian-ovo.example.xyz/", [], snap), { localSignals: layer2 });
    assert.equal(loud.find((x) => x.id === "brand_logo_offsite").weight, 25);
    assert.equal(loud.find((x) => x.id === "urgent_language").weight, 15);
});

test("a client cannot use localSignals for anything but this weighting (junk is ignored)", async () => {
    const snap = { imageAlts: ["Logo OVO"], text: "", title: "" };
    for (const junk of [null, "x", [null, 5, { layer: 2, weight: "999" }, { layer: 3, weight: 50 }, { layer: 2, weight: -4 }]]) {
        const out = await analyze(page("https://undian-ovo.example.xyz/", [], snap), { localSignals: junk });
        assert.equal(out.find((x) => x.id === "brand_logo_offsite").weight, 12);
    }
});

test("review: user-content / hosting platforms never get the official or popular silence", async () => {
    const hosts = [
        "evil-bank.s3.amazonaws.com", "x.execute-api.ap-southeast-1.amazonaws.com", "sites.googleusercontent.com", "x.googleapis.com",
        "sway.office.com", "onedrive.live.com", "tenant.sharepoint.com", "forms.cloud.microsoft", "evil.pages.dev", "x.github.io",
    ];
    for (const host of hosts) {
        const signals = await run(`https://${host}/login`, FORMS.pin);
        assert.ok(signals.some((x) => x.id === "asks_pin"), host);
    }
});

test("review: government suffixes and link shorteners are not popular sites (only named agencies are)", async () => {
    for (const host of ["dinas-xyz.go.id", "kecil.ac.id"]) {
        assert.ok((await run(`https://${host}/bayar`, FORMS.pin)).some((x) => x.id === "asks_pin"), host);
    }
});
