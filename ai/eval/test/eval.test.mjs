// Run: node --test ai/eval/test
import test from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { redact, redactUrl, parseHtml } from "../tools/snapshot.mjs";
import { validateSample, loadSamples, normalizeSnapshot, scoreOf, statusOf, summarize, evaluate, loadDetector, domainOf, jsonReport } from "../lib.mjs";

const dataDir = fileURLToPath(new URL("../data", import.meta.url));

// ---------- redaction ----------
test("redact masks email, long numbers and Indonesian phone numbers", () => {
    assert.equal(redact("hubungi budi@example.com"), "hubungi [email]");
    assert.equal(redact("NIK 3171234567890001 ya"), "NIK [number] ya");
    assert.equal(redact("kartu 4111 1111 1111 1111"), "kartu [number]");
    assert.equal(redact("wa 0812-3456-7890 atau +62 812 3456 7890"), "wa [phone] atau [phone]");
    assert.equal(redact("diskon 50% sampai 2026"), "diskon 50% sampai 2026"); // ordinary numbers stay
});

test("redactUrl keeps host and path, hides query values and fragment", () => {
    assert.equal(redactUrl("https://x.site/a/b?ref=wa&id=12345#top"), "https://x.site/a/b?ref=REDACTED&id=REDACTED");
    assert.equal(redactUrl("https://x.site/a"), "https://x.site/a");
});

// ---------- HTML -> snapshot ----------
const HTML = `<!doctype html><html lang="id"><head><title> Masuk &amp; Verifikasi </title><script>var secret="no"</script></head>
<body><!-- comment --><h1>Verifikasi akun</h1><img alt="Logo Bank" src="a.png"><img src="b.png">
<form action="/post"><label for="p">PIN Anda</label><input id="p" name="pin" type="password" autocomplete="off" value="1234">
<input type="hidden" name="csrf"><input type="submit"><select name="bank"></select></form>
<input name="loose" placeholder="Nomor">
<iframe src="/login-frame.php"></iframe><p>Hubungi 0812 3456 7890</p></body></html>`;

test("parseHtml reads title, lang, text, forms, alts and iframes", () => {
    const { snapshot, meta } = parseHtml(HTML, { url: "https://x.site/p?x=1", domain: "x.site", capturedAt: "2026-01-01T00:00:00.000Z" });
    assert.equal(snapshot.title, "Masuk & Verifikasi");
    assert.equal(snapshot.lang, "id");
    assert.equal(snapshot.url, "https://x.site/p?x=REDACTED");
    assert.ok(snapshot.text.includes("Verifikasi akun"));
    assert.ok(!snapshot.text.includes("secret"), "script content is not visible text");
    assert.ok(snapshot.text.includes("[phone]") && !snapshot.text.includes("3456"));
    assert.deepEqual(snapshot.imageAlts, ["Logo Bank"]);
    assert.deepEqual(meta.iframes, ["/login-frame.php"]);

    assert.equal(snapshot.forms.length, 2); // the <form> and the loose input
    const [form, loose] = snapshot.forms;
    assert.equal(form.action, "/post");
    assert.deepEqual(form.fields.map((f) => f.name), ["pin", "bank"]); // hidden/submit skipped
    assert.deepEqual(form.fields[0], { type: "password", name: "pin", id: "p", label: "PIN Anda", placeholder: null, autocomplete: "off" });
    assert.equal(loose.action, null);
    assert.equal(loose.fields[0].name, "loose");
});

test("field values are never copied", () => {
    const { snapshot } = parseHtml(HTML, { url: "https://x.site/" });
    assert.ok(!JSON.stringify(snapshot).includes("1234"));
});

test("parseHtml respects the contract limits", () => {
    const many = "<img alt=a>".repeat(80) + "<p>" + "x ".repeat(30000) + "</p>";
    const { snapshot } = parseHtml(many, { url: "https://x.site/" });
    assert.ok(snapshot.imageAlts.length <= 50);
    assert.ok(snapshot.text.length <= 20000);
});

// ---------- samples ----------
const ok = () => ({ id: "a-1", label: "scam", synthetic: true, source: "test", snapshot: { url: "https://x.site/" } });

test("validateSample accepts a minimal sample and rejects bad ones", () => {
    assert.deepEqual(validateSample(ok()), []);
    assert.ok(validateSample({ ...ok(), id: "Bad Id" }).length);
    assert.ok(validateSample({ ...ok(), label: "maybe" }).length);
    assert.ok(validateSample({ ...ok(), source: "" }).length);
    assert.ok(validateSample({ ...ok(), snapshot: { url: "nope" } }).length);
    assert.ok(validateSample({ ...ok(), snapshot: { url: "https://x.site/", forms: [{ fields: [{ name: "pin", value: "1234" }] }] } }).length);
});

test("a real scam sample must be marked redacted after a manual check", () => {
    assert.ok(validateSample({ ...ok(), synthetic: false }).some((p) => /redacted/.test(p)));
    assert.deepEqual(validateSample({ ...ok(), synthetic: false, redacted: true }), []);
    assert.deepEqual(validateSample({ ...ok(), label: "legit", synthetic: false }), []); // legit pages carry no victim data
});

test("the seed samples are valid and unique", () => {
    const { samples, errors } = loadSamples(dataDir);
    assert.deepEqual(errors, []);
    assert.ok(samples.length >= 10);
    assert.ok(samples.some((s) => s.label === "scam") && samples.some((s) => s.label === "legit"));
});

test("normalizeSnapshot fills what the extension would set; domainOf uses the public suffix list", () => {
    const s = normalizeSnapshot({ url: "https://www.bca.co.id/x" });
    assert.equal(s.domain, "bca.co.id");
    assert.deepEqual(s.forms, []);
    assert.equal(domainOf("https://a.b.toko.co.id/"), "toko.co.id");
});

// ---------- scoring and metrics ----------
test("score and status follow the contract", () => {
    assert.equal(scoreOf([{ id: "x", weight: 60 }, { id: "y", weight: 70 }]), 100);
    assert.equal(scoreOf([{ id: "db_match", weight: 100 }, { id: "y", weight: 1 }]), 100);
    assert.deepEqual([0, 29, 30, 49, 50, 79, 80, 100].map(statusOf), ["normal", "normal", "warning 1", "warning 1", "warning 2", "warning 2", "blocked", "blocked"]);
});

test("--json hides holdout rows and holdout ids in the summary unless showHoldout", () => {
    const row = (id, label, score, tags = []) => ({ id, label, score, tags, localMs: 1, signals: score ? [{ id: "lookalike_domain", weight: score, evidence: "" }] : [] });
    const rows = [row("s1", "scam", 90), row("s-hold", "scam", 20, ["holdout"]), row("l-hold", "legit", 40, ["holdout"]), row("l1", "legit", 35)];
    const summary = summarize(rows, { remote: true });
    const hidden = jsonReport(rows, summary, {});
    assert.deepEqual(hidden.rows.map((r) => r.id), ["s1", "l1"]);
    assert.deepEqual(hidden.summary.misses, []);
    assert.deepEqual(hidden.summary.falsePositives, ["l1"]);
    assert.equal(hidden.summary.holdoutRowsHidden, 2);
    assert.ok(!JSON.stringify(hidden).includes("-hold"), "no holdout id anywhere in the output");
    const shown = jsonReport(rows, summary, { showHoldout: true });
    assert.equal(shown.rows.length, 4);
    assert.deepEqual(shown.summary.misses, ["s-hold"]);
});

test("summarize counts hits, misses, false positives and judges targets only when meaningful", () => {
    const row = (id, label, score, evidence = "") => ({ id, label, score, localMs: 1, signals: score ? [{ id: "lookalike_domain", weight: score, evidence }] : [] });
    const rows = [row("s1", "scam", 90), row("s2", "scam", 55), row("s3", "scam", 20), row("l1", "legit", 0), row("l2", "legit", 35, "bca · level 3 · typo")];
    const m = summarize(rows, { remote: true });
    assert.deepEqual(m.counts, { scam: 3, legit: 2 });
    assert.deepEqual(m.scam, { atLeast30: 2, atLeast50: 2, atLeast80: 1 });
    assert.deepEqual(m.falsePositives, ["l2"]);
    assert.deepEqual(m.misses, ["s3"]);
    assert.deepEqual(m.falsePositiveSignals, { "level 3 lookalike_domain": 1 });
    assert.equal(m.enough, false);
    assert.equal(m.targetsMet, null, "5 samples cannot prove anything");
    assert.equal(summarize(rows, { remote: false }).targetsMet, null);
});

test("summarize judges the targets with 50+ per class and layers 3-4", () => {
    const rows = [];
    for (let i = 0; i < 50; i++) rows.push({ id: `s${i}`, label: "scam", score: i < 46 ? 85 : 10, localMs: 1, signals: [] });
    for (let i = 0; i < 50; i++) rows.push({ id: `l${i}`, label: "legit", score: 0, localMs: 1, signals: [] });
    assert.equal(summarize(rows, { remote: true }).targetsMet, true); // 92% >= 50, 92% >= 80, no false positive
    rows[60].score = 40;
    assert.equal(summarize(rows, { remote: true }).targetsMet, false); // one wrong block is enough
});

test("evaluate runs M1 and drops signals from the wrong layer", async () => {
    const detector = loadDetector();
    const row = await evaluate({ id: "t", label: "scam", snapshot: { url: "https://lphone-login.com/x" } }, { detector });
    assert.equal(row.localScore, 39);
    assert.equal(row.score, 39);

    const fake = { analyzeLocal: async () => [{ id: "asks_pin", layer: 3, weight: 50, label: {}, labelSimple: {} }, { id: "cheap_tld", layer: 2, weight: 15, label: {}, labelSimple: {} }] };
    const filtered = await evaluate({ id: "t2", label: "scam", snapshot: { url: "https://x.site/" } }, { detector: fake });
    assert.deepEqual(filtered.signals.map((s) => s.id), ["cheap_tld"], "layer 3 signals must come from /analyze, not from the local detector");
});
