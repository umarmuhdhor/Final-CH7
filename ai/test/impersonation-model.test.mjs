// Layer 3 impersonation model (src/layer3/model/impersonation.js) behind SHOO_L3_MODEL=impersonation.
// Only invented pages here. Parity with the lab's Python model is checked outside this repo (it needs real page text):
// shoo-impersonation-lab/parity_js.mjs.
import test from "node:test";
import assert from "node:assert/strict";
import { analyzeWithDomain } from "../src/analyze.js";
import { createApp } from "../src/app.js";
import { sanitizeSnapshot } from "../src/validate.js";
import { KNOWN_SIGNAL_IDS } from "../src/signal-ids.js";
import { buildModelSignal, isPopular, makesClaim, MODEL_SIGNAL_ID, pageRow, scoreImpersonation } from "../src/layer3/model/impersonation.js";
import { fastestMs, field, ids, page, post } from "./helpers.mjs";

const age = (ageDays) => ({ lookup: async () => ({ registeredAt: "2026-11-15", ageDays }) });
const SHOP = () =>
    page("https://toko-kue-bunda.com/", [], {
        title: "Toko Kue Bunda",
        text: "Kue kering dan kue basah buatan rumah. Pesan lewat telepon. Alamat toko di Bandung. Buka setiap hari dari pagi.",
    });
const FAKE_LOGIN = () =>
    page("https://bca-verifikasi-akun.vercel.app/login", [field({ type: "password", name: "password" }), field({ name: "user", label: "User ID" })], {
        title: "KlikBCA Individual - Verifikasi Akun",
        text: "Selamat! Anda pemenang undian hadiah BCA. Masukkan User ID dan PIN untuk verifikasi akun Anda sebelum diblokir dalam 24 jam.",
    });

test("flag off: no model signal, same answer as before", async () => {
    const snap = FAKE_LOGIN();
    const off = await analyzeWithDomain(snap);
    const offExplicit = await analyzeWithDomain(snap, { model: false });
    assert.deepEqual(off, offExplicit);
    assert.ok(!ids(off.signals).includes(MODEL_SIGNAL_ID));
});

test("flag on through createApp: SHOO_L3_MODEL in env or l3Model option", async () => {
    const body = { snapshot: FAKE_LOGIN(), localSignals: [] };
    const plain = await (await post(createApp(), body)).json();
    assert.ok(!ids(plain.signals).includes(MODEL_SIGNAL_ID), "default app: model off");
    const on = await (await post(createApp({ l3Model: true }), body)).json();
    const s = on.signals.find((x) => x.id === MODEL_SIGNAL_ID);
    assert.ok(s, "a brand login asking for a PIN with prize words is flagged");
    assert.ok(s.weight === 40 || s.weight === 80);
    const env = await createApp().request("/analyze", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) }, { SHOO_L3_MODEL: "impersonation" });
    assert.ok(ids((await env.json()).signals).includes(MODEL_SIGNAL_ID), "Worker var turns it on");
});

test("model signal: shape, layer 3, no evidence, known id", () => {
    for (const tier of ["warn", "block"]) {
        const s = buildModelSignal({ tier });
        assert.deepEqual(Object.keys(s).sort(), ["id", "label", "labelSimple", "layer", "weight"]);
        assert.equal(s.layer, 3);
        assert.ok(s.label.en && s.label.id && s.labelSimple.en && s.labelSimple.id);
    }
    assert.equal(buildModelSignal({ tier: "warn" }).weight, 40);
    assert.equal(buildModelSignal({ tier: "block" }).weight, 80);
    assert.equal(buildModelSignal({ tier: "gate" }), null, "gate counts as safe (2026-11-17)");
    assert.equal(buildModelSignal({ tier: "safe" }), null);
    assert.ok(KNOWN_SIGNAL_IDS.has(MODEL_SIGNAL_ID));
});

test("official and popular hosts are always safe", () => {
    assert.equal(isPopular("www.amazon.co.uk"), true);
    assert.equal(isPopular("someone.github.io"), false, "shared host never popular");
    assert.equal(isPopular("sites.google.com"), false, "user content never popular");
    const r = scoreImpersonation(sanitizeSnapshot(page("https://www.amazon.co.uk/ap/signin", [field({ type: "password", name: "password" })], { title: "Amazon Sign-In" })));
    assert.equal(r.tier, "safe");
});

test("domain younger than 30 days on its own domain is at least warn; not on a shared host", async () => {
    const own = await analyzeWithDomain(SHOP(), { rdap: age(3), model: true });
    assert.ok(ids(own.signals).includes(MODEL_SIGNAL_ID));
    const old = scoreImpersonation(sanitizeSnapshot(SHOP()), { ageDays: 400 });
    assert.ok(old.tier !== "warn" && old.tier !== "block", "a plain old shop page is not flagged");
    const shared = scoreImpersonation(sanitizeSnapshot(page("https://toko-kue-bunda.vercel.app/", [], { title: SHOP().title, text: SHOP().text })), { ageDays: 3 });
    assert.equal(shared.young, false, "on vercel.app the age is the platform's");
});

test("brand in someone else's domain is at least warn; the brand's own domains and campus domains are not", () => {
    const text = "Sign in with your Apple ID to manage your iCloud account. Forgot password?";
    const fake = scoreImpersonation(sanitizeSnapshot(page("https://appleid-icloudmac.com/", [], { title: "Apple ID", text })));
    assert.equal(fake.brandHost, true);
    assert.ok(fake.tier === "warn" || fake.tier === "block");
    for (const url of ["https://www.google.org/", "https://www.registry.amazon/", "https://bsi.ac.id/"]) {
        const r = scoreImpersonation(sanitizeSnapshot(page(url, [], { title: "Google Amazon BSI", text })));
        assert.equal(r.brandHost, false, url);
    }
    const noBrandOnPage = scoreImpersonation(sanitizeSnapshot(page("https://appleid-icloudmac.com/", [], { title: "Toko kue", text: "Kue enak murah." })));
    assert.equal(noBrandOnPage.brandHost, false, "host alone is not enough: the page must name a brand too");
});

test("pretending to be a brand and asking for a login is block; a brand only in the title is not; owned domains are safe", () => {
    const pw = [field({ type: "password", name: "password" }), field({ name: "email" })];
    const text = "Sign in with your Apple ID to manage your iCloud account.";
    const fake = scoreImpersonation(sanitizeSnapshot(page("https://appleid-icloudmac.com/login", pw, { title: "Apple ID", text })), { ruleIds: ["asks_password"] });
    assert.equal(fake.loginBlock, true);
    assert.equal(fake.tier, "block");
    const titleOnly = scoreImpersonation(sanitizeSnapshot(page("https://toko-donasi.id/masuk", pw, { title: "Masuk dengan Google", text: "Masuk untuk lanjut." })), { ruleIds: ["asks_password"] });
    assert.equal(titleOnly.loginBlock, false, "brand in the title alone is not pretending");
    const owned = scoreImpersonation(sanitizeSnapshot(page("https://www.mandirikartukredit.com/login", pw, { title: "Mandiri Kartu Kredit", text: "Login Mandiri" })), { ruleIds: ["asks_password"] });
    assert.equal(owned.tier, "safe");
});

test("Indonesian lure word in the chosen address is at least warn, with a brand or lure on the page", () => {
    const text = "Selamat, nomor anda terpilih sebagai pemenang. Klaim hadiah sekarang sebelum hangus.";
    const fake = scoreImpersonation(sanitizeSnapshot(page("https://program-hadiah-2026.blogspot.com/", [], { title: "Program Hadiah", text })));
    assert.equal(fake.lureHost, true);
    assert.ok(fake.tier === "warn" || fake.tier === "block");
    const plain = scoreImpersonation(sanitizeSnapshot(page("https://info-hadiah-kue.blogspot.com/", [], { title: "Resep", text: "Resep kue kering untuk lebaran." })));
    assert.equal(plain.lureHost, false, "the page must back it up");
    const gov = scoreImpersonation(sanitizeSnapshot(page("https://bantuan.kemdikbud.go.id/", [], { title: "Bantuan", text })));
    assert.equal(gov.lureHost, false, "government domains are skipped");
});

test("claim gate v3g: footer brands alone do not count, a form or a strong lure does", () => {
    const row = (over, fields = []) => pageRow(sanitizeSnapshot(page("https://jasa-limo-kota.com/", fields, over)));
    const footer = row({ title: "City Limo Service", text: "Book your ride today. Follow us on Facebook and Instagram. Customer service and refund policy." });
    assert.equal(makesClaim(footer, [], 0.3), false);
    const withForm = row({ title: "City Limo Service", text: "Login with your Facebook account." }, [field({ type: "password", name: "pw" }), field({ name: "email" })]);
    assert.equal(makesClaim(withForm, [], 0.3), true);
    const prize = row({ title: "Promo", text: "Selamat, anda pemenang undian. Klaim hadiah sekarang." });
    assert.equal(makesClaim(prize, [], 0.1), true);
    const ask = row({ title: "Form", text: "Isi data." });
    assert.equal(makesClaim(ask, ["asks_otp"], 0.1), true);
});

test("model stays fast: one page well under 50 ms after the first load", async () => {
    const snap = sanitizeSnapshot(page("https://example-news.com/a", [], { title: "News", text: "kata ".repeat(2000) + "lorem ipsum dolor ".repeat(400) }));
    scoreImpersonation(snap); // first call decodes the model
    const ms = await fastestMs(() => scoreImpersonation(snap));
    assert.ok(ms < 50, `took ${ms} ms`);
});

// ---- the platform's own brand is not a claim (23 Nov 2026) --------------------------------------------------------
// Ordinary Google Sheets / Drive / Forms / OneDrive / Microsoft Forms pages were warn or block: "… - Google Drive" in the
// title and google in docs.google.com read as "Google's brand on a site Google doesn't own" (docs.google.com is user
// content, so not official). The lab taught it: of 201 "scam" rows on these platforms, 180 were empty, "Loading…",
// "Error" or "access removed" pages from phishing feeds; 1 legit row. The team's own "Shoo Waitlist" sheet was blocked.
const platformPage = (url, title, text, fields = []) => page(url, fields, { title, text });
const SHEETS_ID_UI = "Edit dengan apl Spreadsheet. Membuat penyesuaian dan berbagi dengan yang lain agar dapat mengedit secara bersamaan. LAIN KALI DAPATKAN APLIKASI";

test("ordinary pages on Google and Microsoft platforms: no model signal", async () => {
    for (const [url, title, text] of [
        ["https://docs.google.com/spreadsheets/u/0/d/abc/htmlview", "Shoo Waitlist - Google Drive", `${SHEETS_ID_UI} Shoo Waitlist Sheet1 Waitlist`],
        ["https://docs.google.com/spreadsheets/d/abc/htmlview", "Team Schedule - Google Drive", "Make changes and share with others. GET THE APP. Team Schedule Sheet1"],
        ["https://docs.google.com/forms/d/e/abc/viewform", "Pendaftaran Lomba 17an - Google Formulir", "Pendaftaran Lomba 17an. Isi nama dan kelas. Nama lengkap Kelas Kirim"],
        ["https://drive.google.com/file/d/abc/view", "laporan.pdf - Google Drive", "Masuk Laporan keuangan bulanan"],
        ["https://docs.google.com/presentation/d/abc/edit", "Pitch Deck - Google Slide", "Pitch Deck Final Challenge"],
        ["https://onedrive.live.com/view.aspx?id=abc", "OneDrive", "Dokumen dibagikan dengan Anda"],
        ["https://forms.office.com/r/abc", "Microsoft Forms", "Survei kepuasan pelanggan. Nama Email Kirim"],
    ]) {
        const { signals } = await analyzeWithDomain(platformPage(url, title, text), { model: true });
        assert.ok(!ids(signals).includes(MODEL_SIGNAL_ID), `${title}: ${JSON.stringify(signals.map((s) => [s.id, s.weight]))}`);
    }
});

test("real phishing on those platforms still flagged: another brand, a sensitive ask, a lure or credential words", async () => {
    const bca = platformPage("https://docs.google.com/forms/d/e/abc/viewform", "Verifikasi Akun BCA - Google Formulir", "Akun BCA anda akan diblokir. Masukkan nomor kartu dan PIN", [field({ name: "pin", label: "PIN" })]);
    const od = platformPage("https://onedrive.live.com/view.aspx?id=abc", "OneDrive", "Sign in to view the shared document. Email Password", [field({ type: "password", name: "password" })]);
    for (const snap of [bca, od]) {
        const r = scoreImpersonation(sanitizeSnapshot(snap), { ruleIds: ids((await analyzeWithDomain(snap)).signals), ageDays: null });
        assert.ok(r.tier === "warn" || r.tier === "block", `${snap.title}: ${r.tier}`);
    }
});

test("the owner rule is only for the owner's own platforms: Google's name on someone else's site still counts", () => {
    const fake = page("https://google-drive-share.example.xyz/view", [], { title: "Shoo Waitlist - Google Drive", text: SHEETS_ID_UI });
    const onPlatform = page("https://docs.google.com/spreadsheets/d/abc/htmlview", [], { title: "Shoo Waitlist - Google Drive", text: SHEETS_ID_UI });
    const ownTier = scoreImpersonation(sanitizeSnapshot(onPlatform), { ageDays: null }).tier;
    assert.ok(ownTier === "safe" || ownTier === "gate", `on docs.google.com: ${ownTier}`);
    assert.equal(makesClaim(pageRow(sanitizeSnapshot(fake)), [], 0), true, "off the platform, Google in the title is still a claim");
});
