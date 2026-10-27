// Phase 07 calibration rules (D-imelda-04: a single ambiguous signal must not reach the popup threshold alone;
// official and popular sites stay below 30 even with sensitive forms; pages that ask for nothing are not scam-weighted by words alone).
import test from "node:test";
import assert from "node:assert/strict";
import { analyze } from "../src/analyze.js";
import { BRANDS, field, page } from "./helpers.mjs";
import { POPULAR, SHARED_HOSTS } from "../src/blocklist/allowlist.js";
import { LAYER3_QUIET, isOfficialHost } from "../src/layer3/official.js";
import { isAllowlisted } from "../src/blocklist/build.js";

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

test("popular sites (layer 3 quiet set): login / OTP / card forms stay below 30", async () => {
    for (const domain of LAYER3_QUIET) {
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

test("review #60: a full native card checkout on a neutral shop stays below 30", async () => {
    const card = [
        field({ name: "name", label: "Nama di kartu", autocomplete: "cc-name" }),
        field({ name: "cc-number", label: "Nomor kartu", autocomplete: "cc-number" }),
        field({ name: "cc-exp", label: "Berlaku sampai", autocomplete: "cc-exp" }),
        field({ name: "cc-csc", label: "CVV", autocomplete: "cc-csc" }),
    ];
    for (const url of ["https://tokokopi-senja.com/checkout", "https://toko-kecil.example.xyz/checkout"]) {
        const signals = await run(url, card);
        assert.deepEqual(signals.map((x) => x.id), ["asks_card"], url);
        assert.ok(score(signals) < POPUP, `${url}: ${score(signals)}`);
    }
});

test("review #60: go.id and tokopedia.link are never published on the blocklist, yet get no layer 3 silence", async () => {
    for (const d of ["go.id", "jakarta.go.id", "dinas-xyz.go.id", "tokopedia.link"]) assert.equal(isAllowlisted(d), true, d);
    assert.equal(POPULAR.has("go.id"), true);
    for (const d of ["go.id", "tokopedia.link"]) assert.equal(LAYER3_QUIET.has(d), false, d);
    for (const host of ["jakarta.go.id", "tokopedia.link"]) assert.equal(isOfficialHost(host), false, host);
    assert.equal(isOfficialHost("kominfo.go.id"), true, "a named agency stays quiet");
});

test("review #60: user-made pages on popular domains do not get the popular-site silence", () => {
    for (const host of ["express.adobe.com", "new.express.adobe.com", "acrobat.adobe.com", "paper.dropbox.com", "alice.medium.com", "gist.github.com"]) {
        assert.equal(isOfficialHost(host), false, host);
    }
    for (const host of ["www.adobe.com", "www.dropbox.com", "medium.com", "www.medium.com", "github.com"]) assert.equal(isOfficialHost(host), true, host);
});

test("impersonation boundary: layer 1-2 sum >= 10 turns on full word weights, a cheap TLD alone (5) does not", async () => {
    const snap = { imageAlts: ["Logo OVO"], text: "Undian berhadiah. Klaim sekarang!", title: "Undian OVO" };
    const sig = (id, weight) => ({ id, layer: 2, weight, label: { en: "x", id: "x" }, labelSimple: { en: "x", id: "x" } });
    const logo = async (localSignals) => (await analyze(page("https://undian-ovo.example.xyz/", [], snap), { localSignals })).find((x) => x.id === "brand_logo_offsite").weight;
    assert.equal(await logo([sig("lookalike_domain", 10)]), 25, "lookalike level 1 (10) -> full");
    assert.equal(await logo([sig("cheap_tld", 5)]), 12, "cheap TLD alone (5) -> quiet");
    assert.equal(await logo([sig("cheap_tld", 9)]), 12, "9 is under the boundary");
});

test("a suspicious_link signal from the extension (layer 2, #140) turns on full word weights from 10 up, like the brand signals", async () => {
    const snap = { imageAlts: ["Logo OVO"], text: "Undian berhadiah. Klaim sekarang!", title: "Undian OVO" };
    const link = (weight) => [{ id: "suspicious_link", layer: 2, weight, label: { en: "x", id: "x" }, labelSimple: { en: "x", id: "x" } }];
    const logo = async (localSignals) => (await analyze(page("https://undian-ovo.example.com/", [], snap), { localSignals })).find((x) => x.id === "brand_logo_offsite").weight;
    assert.equal(await logo(link(13)), 25);
    assert.equal(await logo(link(9)), 12);
});
