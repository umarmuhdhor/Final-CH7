// Phase 03: urgent_language and brand_logo_offsite. Evidence must be an exact piece of the page text.
import test from "node:test";
import assert from "node:assert/strict";
import { analyzeSnapshot } from "../src/analyze.js";
import { buildIndex, findPhrase } from "../src/layer3/match.js";
import { page, SCAM_URL } from "./helpers.mjs";

const run = (over, url = SCAM_URL) => analyzeSnapshot(page(url, [], over));
const find = (signals, id) => signals.find((s) => s.id === id);

// ---- match.js ---------------------------------------------------------------
test("match: finds a phrase case-insensitively and returns offsets into the ORIGINAL text", () => {
    const text = "Halo. AKUN Anda akan  DIBLOKIR dalam 24 jam!";
    const hit = findPhrase(buildIndex(text), "diblokir dalam 24 jam");
    assert.ok(hit);
    assert.equal(text.slice(hit.start, hit.end), "DIBLOKIR dalam 24 jam");
});

test("match: offsets stay right after NFKC and invisible characters (full-width, zero-width, NBSP)", () => {
    const text = "x​x KLAIM ｓｅｋａｒａｎｇ juga";
    const hit = findPhrase(buildIndex(text), "klaim sekarang");
    assert.ok(hit);
    assert.ok(text.includes(text.slice(hit.start, hit.end)));
    assert.equal(text.slice(hit.start, hit.end), "KLAIM ｓｅｋａｒａｎｇ");
});

test("match: word boundaries (act now is not inside react nowadays) and no match across a line break", () => {
    assert.equal(findPhrase(buildIndex("we react nowadays"), "act now"), null);
    assert.equal(findPhrase(buildIndex("klaim\nsekarang"), "klaim sekarang"), null);
    assert.ok(findPhrase(buildIndex("klaim   sekarang"), "klaim sekarang"));
});

test("match: text 20,000 chars of repeated near-misses stays fast", () => {
    const text = "act nowact now ".repeat(1400).slice(0, 20000);
    const t0 = performance.now();
    findPhrase(buildIndex(text), "act now");
    assert.ok(performance.now() - t0 < 100);
});

// ---- urgent_language --------------------------------------------------------
const URGENT = [
    ["Segera lakukan verifikasi. Akun Anda akan ditutup jika diabaikan.", "Akun Anda akan ditutup"],
    ["Rekening terancam. DIBLOKIR dalam 24 jam jika tidak verifikasi.", "DIBLOKIR dalam 24 jam"],
    ["Selamat! Klaim sekarang hadiahmu.", "Klaim sekarang"],
    ["Bantuan cair. Pendaftaran terakhir hari ini.", "terakhir hari ini"],
    ["Notice: Your account will be suspended. Please log in.", "Your account will be suspended"],
    ["Security alert. Act now to keep access.", "Act now"],
    ["Please verify your account within 24 hours.", "within 24 hours"],
];
for (const [text, evidence] of URGENT) {
    test(`urgent_language fires and evidence is an exact substring: ${evidence}`, () => {
        const s = find(run({ text }), "urgent_language");
        assert.ok(s, "signal present");
        assert.equal(s.layer, 3);
        assert.equal(s.weight, 8, "no form asks for data here: quiet weight (phase 07); full weight 15 is covered in calibration.test.mjs");
        assert.equal(s.evidence, evidence);
        assert.ok(text.includes(s.evidence), "string-equal substring of the page text");
        assert.deepEqual(Object.keys(s.label).sort(), ["en", "id"]);
        assert.ok(s.labelSimple.id.length > 0);
    });
}

test("urgent_language also reads the title, and only reports one signal", () => {
    const signals = run({ title: "Akun Anda Akan Diblokir", text: "klaim sekarang. act now." });
    assert.equal(signals.filter((s) => s.id === "urgent_language").length, 1);
    const t = run({ title: "Akun Anda Akan Diblokir", text: "halaman biasa" });
    assert.equal(find(t, "urgent_language").evidence, "Akun Anda Akan Diblokir");
});

test("urgent_language label uses our fixed phrase, never raw page text", () => {
    const s = find(run({ text: "KLAIM ｓｅｋａｒａｎｇ <b>x</b>" }), "urgent_language");
    assert.ok(s);
    assert.match(s.label.id, /"klaim sekarang"/);
    assert.ok(!s.label.id.includes("<b>"));
});

for (const text of [
    "Toko online dengan banyak pilihan. Promo berakhir bulan depan.",
    "Pesanan dikirim dalam 24 jam setelah pembayaran. Ships within 24 hours.",
    "We react nowadays to every request.",
    "Selamat datang di blog resep kami.",
    "",
]) {
    test(`urgent_language stays silent: ${text.slice(0, 40) || "(empty)"}`, () => {
        assert.equal(find(run({ text }), "urgent_language"), undefined);
    });
}

test("perf: worst NFKC blow-up (18x) stays under 100 ms", () => {
    const text = "\ufdfa".repeat(20000);
    const t0 = performance.now();
    analyzeSnapshot(page(SCAM_URL, [], { text, title: text.slice(0, 500), imageAlts: Array(50).fill("\ufdfa".repeat(300)) }));
    assert.ok(performance.now() - t0 < 100, `took ${performance.now() - t0}`);
});

test("match: caseless scripts count as word characters", () => {
    assert.equal(findPhrase(buildIndex("final warning\ufdfa"), "final warning"), null);
});

test("urgent_language: huge hostile text answers fast and never throws", () => {
    for (const unit of ["a", "akun anda ", "act now", "klaim ", "​", "ｓ"]) {
        const text = unit.repeat(Math.ceil(20000 / unit.length)).slice(0, 20000);
        const t0 = performance.now();
        analyzeSnapshot(page(SCAM_URL, [], { text, title: text.slice(0, 500) }));
        assert.ok(performance.now() - t0 < 100, `unit ${JSON.stringify(unit)} took ${performance.now() - t0} ms`);
    }
});

// ---- brand_logo_offsite -----------------------------------------------------
test("brand_logo_offsite fires for a BCA logo alt on an unofficial domain; evidence is exact", () => {
    const s = find(run({ imageAlts: ["Logo BCA", "banner"] }), "brand_logo_offsite");
    assert.ok(s);
    assert.equal(s.layer, 3);
    assert.equal(s.weight, 12, "quiet weight without a sensitive form (phase 07); full weight 25 is covered in calibration.test.mjs");
    assert.equal(s.evidence, "BCA");
    assert.match(s.label.en, /BCA/);
});

test("brand_logo_offsite fires when the title names the brand", () => {
    const title = "Login KlikBCA Individual";
    const s = find(run({ title }), "brand_logo_offsite");
    assert.ok(s);
    assert.ok(title.includes(s.evidence));
});

test("brand_logo_offsite: official domain, official subdomain and www are silent", () => {
    for (const url of ["https://www.bca.co.id/id", "https://ibank.bca.co.id/login", "https://klikbca.com/"]) {
        assert.equal(find(run({ imageAlts: ["Logo BCA"], title: "KlikBCA" }, url), "brand_logo_offsite"), undefined, url);
    }
});

test("brand_logo_offsite: user-content hosts of an official domain are NOT exempt", () => {
    assert.ok(find(run({ title: "Login Google" }, "https://sites.google.com/view/promo"), "brand_logo_offsite"));
});

test("brand_logo_offsite: look-alike domain is not official", () => {
    assert.ok(find(run({ imageAlts: ["Logo BCA"] }, "https://notbca.co.id/"), "brand_logo_offsite"));
});

for (const [name, over] of [
    ["common word dana in a sentence", { imageAlts: ["Bantuan dana desa untuk warga"], title: "Dana desa 2026" }],
    ["brand inside another word", { imageAlts: ["Logo brilliant", "bcaxyz"], title: "Brilliant ideas" }],
    ["alt without the word logo", { imageAlts: ["BCA", "iPhone 15 Pro"] }],
    ["iphone in a shop title", { title: "iPhone 15 Pro murah - Toko Ponsel" }],
    ["payment strip: 3+ brands in alts", { imageAlts: ["Logo BCA", "Logo BRI", "Logo Mandiri"] }],
    ["no alts, no title", {}],
    ["common-name brand with login word in title (Dana)", { title: "Login Dana" }],
    ["common-name brand with login word in title (Mandiri)", { title: "Verifikasi Mandiri" }],
    ["blog title naming a brand", { title: "Cara membuat akun BCA" }],
    ["update blog title", { title: "Update BCA 2026" }],
    ["social share/follow icons", { imageAlts: ["Facebook icon", "Instagram icon", "WhatsApp logo"] }],
    ["sign in with Google button", { imageAlts: ["Google logo"] }],
]) {
    test(`brand_logo_offsite stays silent: ${name}`, () => {
        assert.equal(find(run(over), "brand_logo_offsite"), undefined);
    });
}

test("brand_logo_offsite: title with brand + login word still fires; titleTerms skip commonNames only", () => {
    assert.ok(find(run({ title: "Masuk ke BRI Online" }), "brand_logo_offsite"));
    assert.ok(find(run({ title: "Login Bank Mandiri" }), "brand_logo_offsite"));
});

test("urgent_language: a hostile first hit does not hide a later clean one", () => {
    const text = "k\u200blaim " + "\u200b".repeat(300) + "sekarang. Lalu klaim sekarang";
    assert.equal(find(run({ text }), "urgent_language").evidence, "klaim sekarang");
});

test("urgent_language: a benign first 'within 24 hours' does not hide a later one near a threat word", () => {
    const text = "Ships within 24 hours. " + "x ".repeat(100) + "Verify your account within 24 hours.";
    const s = find(run({ text }), "urgent_language");
    assert.ok(s && s.evidence === "within 24 hours");
    assert.ok(text.lastIndexOf(s.evidence) > 100);
});

test("urgent_language: half words do not count as threat words (unblocked)", () => {
    assert.equal(find(run({ text: "Your phone is unblocked. Ships within 24 hours." }), "urgent_language"), undefined);
});

test("brand_logo_offsite: one signal even when several alts match the same brand", () => {
    const signals = run({ imageAlts: ["Logo BCA", "Ikon BCA mobile"] });
    assert.equal(signals.filter((s) => s.id === "brand_logo_offsite").length, 1);
});
