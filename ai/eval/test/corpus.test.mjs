// Run: node --test ai/eval/test
import test from "node:test";
import assert from "node:assert/strict";
import { findPersonalData } from "../tools/check-redaction.mjs";
import { holdoutOf, validateCorpus, HOLDOUT_FRACTION } from "../corpus.mjs";
import { isPrivateAddress, assertPublicUrl } from "../tools/safe-url.mjs";
import { summarize } from "../lib.mjs";
import { fileURLToPath } from "node:url";

const clean = () => ({
    id: "clean-1",
    label: "scam",
    synthetic: false,
    redacted: true,
    source: "test",
    collectedAt: "2026-10-22T00:00:00.000Z",
    notes: "",
    snapshot: {
        url: "https://x.site/login?ref=REDACTED",
        title: "Masuk",
        text: "Hubungi [phone] atau [email]. Diskon 50% sampai 2026.",
        forms: [{ action: "/post", fields: [{ type: "password", name: "pin", id: null, label: "PIN", placeholder: null, autocomplete: null }] }],
        imageAlts: ["Logo Bank"],
    },
});
const withText = (text) => ({ ...clean(), snapshot: { ...clean().snapshot, text } });

// ---------- redaction checker ----------
test("findPersonalData passes a clean sample", () => {
    assert.deepEqual(findPersonalData(clean()), []);
});

test("findPersonalData rejects e-mail, ID phone numbers, NIK, long numbers and secrets", () => {
    const dirty = [
        "tulis ke budi@example.com",
        "wa 0812-3456-7890",
        "wa +62 812 3456 7890",
        "NIK 3171234567890001",
        "kartu 4111 1111 1111 1111",
        "key sk-abcdefghijklmnopqrstuvwx",
        "id AKIAIOSFODNN7EXAMPLE",
        ["jwt eyJhbGciOiJIUzI1NiJ9", "eyJzdWIiOiIxMjM0NTY3ODkwIn0", "abcdefghijk"].join("."), // built at runtime: a literal JWT trips secret scanners
    ];
    for (const t of dirty) assert.ok(findPersonalData(withText(t)).length > 0, `should reject: ${t}`);
});

test("findPersonalData looks in every field, not only text", () => {
    const s = clean();
    s.snapshot.title = "Halo budi@example.com";
    s.snapshot.imageAlts = ["foto 0812 3456 7890"];
    s.snapshot.forms[0].fields[0].placeholder = "3171234567890001";
    s.notes = "dari akun budi@example.com";
    const where = findPersonalData(s).join(" ");
    for (const f of ["title", "imageAlts", "forms", "notes"]) assert.ok(where.includes(f), `missing ${f} in: ${where}`);
});

test("findPersonalData rejects unredacted URL query values and fragments", () => {
    const s = clean();
    s.snapshot.url = "https://x.site/a?id=12345";
    assert.ok(findPersonalData(s).some((p) => /url/.test(p)));
    s.snapshot.url = "https://x.site/a#token";
    assert.ok(findPersonalData(s).some((p) => /url/.test(p)));
    s.snapshot.url = "https://x.site/a?id=REDACTED";
    assert.deepEqual(findPersonalData(s), []);
});

test("findPersonalData does not flag ordinary numbers or placeholders", () => {
    assert.deepEqual(findPersonalData(withText("[email] [phone] [number] 2026 50% Rp 150.000 pukul 08.30")), []);
});

// ---------- holdout ----------
test("holdoutOf is deterministic, seed-dependent and close to the fraction", () => {
    assert.equal(holdoutOf("abc", "seed-1"), holdoutOf("abc", "seed-1"));
    const ids = Array.from({ length: 400 }, (_, i) => `sample-${i}`);
    const n = ids.filter((id) => holdoutOf(id, "seed-1")).length;
    assert.ok(Math.abs(n / ids.length - HOLDOUT_FRACTION) < 0.07, `holdout share was ${n / ids.length}`);
    assert.ok(ids.some((id) => holdoutOf(id, "seed-1") !== holdoutOf(id, "seed-2")), "a different seed must pick differently");
});

// ---------- corpus validation ----------
function corpus(nScam, nLegit, seed = "s") {
    const out = [];
    const mk = (label, i) => {
        const id = `${label}-${i}`;
        const s = { ...clean(), id, label, tags: ["cat-a"], snapshot: { ...clean().snapshot } };
        if (holdoutOf(id, seed)) s.tags = [...s.tags, "holdout"];
        return s;
    };
    for (let i = 0; i < nScam; i++) out.push(mk("scam", i));
    for (let i = 0; i < nLegit; i++) out.push(mk("legit", i));
    return out;
}

test("validateCorpus accepts 50+50 well-formed samples", () => {
    assert.deepEqual(validateCorpus(corpus(50, 50), { seed: "s" }), []);
});

test("validateCorpus requires 50 per class", () => {
    const p = validateCorpus(corpus(49, 50), { seed: "s" });
    assert.ok(p.some((x) => /scam/.test(x) && /50/.test(x)), p.join("\n"));
    const q = validateCorpus(corpus(50, 12), { seed: "s" });
    assert.ok(q.some((x) => /legit/.test(x) && /50/.test(x)), q.join("\n"));
});

test("validateCorpus requires source, collectedAt, and redacted for real samples", () => {
    const c = corpus(50, 50);
    delete c[3].collectedAt;
    c[4].source = "";
    c[5].redacted = false;
    c[60].redacted = false; // a real legit page too
    const p = validateCorpus(c, { seed: "s" }).join("\n");
    assert.match(p, /scam-3.*collectedAt/);
    assert.match(p, /scam-4.*source/);
    assert.match(p, /scam-5.*redacted/);
    assert.match(p, /legit-10.*redacted/);
});

test("validateCorpus lets synthetic samples skip redacted", () => {
    const c = corpus(50, 50);
    c[5].synthetic = true;
    c[5].redacted = false;
    assert.deepEqual(validateCorpus(c, { seed: "s" }), []);
});

test("validateCorpus rejects a holdout tag that does not follow the seed", () => {
    const c = corpus(50, 50);
    const i = c.findIndex((s) => s.tags.includes("holdout"));
    c[i].tags = c[i].tags.filter((t) => t !== "holdout"); // picked out by hand
    assert.match(validateCorpus(c, { seed: "s" }).join("\n"), /holdout/);
    const c2 = corpus(50, 50);
    const j = c2.findIndex((s) => !s.tags.includes("holdout"));
    c2[j].tags = [...c2[j].tags, "holdout"]; // added by hand
    assert.match(validateCorpus(c2, { seed: "s" }).join("\n"), /holdout/);
});

test("validateCorpus rejects a form field with a value and unredacted personal data", () => {
    const c = corpus(50, 50);
    c[7].snapshot.forms = [{ action: null, fields: [{ type: "password", name: "pin", value: "1234" }] }];
    c[8].snapshot.text = "hubungi budi@example.com";
    const p = validateCorpus(c, { seed: "s" }).join("\n");
    assert.match(p, /scam-7.*value/);
    assert.match(p, /scam-8/);
});

test("validateCorpus counts category tags per class and wants exactly one category per sample", () => {
    const c = corpus(50, 50);
    const comp = (n) => ({ scam: { "cat-a": n }, legit: { "cat-a": n } });
    assert.deepEqual(validateCorpus(c, { seed: "s", composition: comp(50) }), []);
    assert.ok(validateCorpus(c, { seed: "s", composition: comp(51) }).some((x) => /cat-a/.test(x)));
    // a scam sample tagged with a legit-only category must not count towards the legit total
    const d = corpus(50, 50);
    d[0].tags = ["cat-b"];
    const cross = { scam: { "cat-a": 49, "cat-b": 1 }, legit: { "cat-a": 50 } };
    assert.deepEqual(validateCorpus(d, { seed: "s", composition: cross }), []);
    assert.ok(validateCorpus(d, { seed: "s", composition: { scam: { "cat-a": 50 }, legit: { "cat-a": 50, "cat-b": 1 } } }).some((x) => /cat-b/.test(x)), "scam sample must not fill a legit category");
    d[1].tags = ["cat-a", "cat-b"];
    assert.ok(validateCorpus(d, { seed: "s", composition: cross }).some((x) => /scam-1.*exactly one/.test(x)));
});

test("validateCorpus can require a real share per class", () => {
    const c = corpus(50, 50);
    for (let i = 0; i < 30; i++) c[50 + i].synthetic = true; // 20 of 50 legit are real = 40%
    assert.ok(validateCorpus(c, { seed: "s", minRealShare: { legit: 0.6 } }).some((x) => /legit.*real/.test(x)));
    assert.deepEqual(validateCorpus(c, { seed: "s", minRealShare: { legit: 0.4 } }), []);
});

// ---------- safe capture URLs ----------
test("isPrivateAddress covers loopback, private, link-local and metadata ranges", () => {
    for (const ip of ["127.0.0.1", "10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.1.1", "169.254.169.254", "0.0.0.0", "100.64.0.1", "::1", "fe80::1", "fc00::1", "fd12::1", "::ffff:127.0.0.1"])
        assert.equal(isPrivateAddress(ip), true, ip);
    for (const ip of ["8.8.8.8", "1.1.1.1", "172.32.0.1", "93.184.216.34", "2606:4700:4700::1111"]) assert.equal(isPrivateAddress(ip), false, ip);
});

test("assertPublicUrl allows normal https and rejects everything that could reach inside", async () => {
    const pub = async () => ["93.184.216.34"];
    await assertPublicUrl("https://example.com/a", { resolve: pub });
    await assertPublicUrl("http://example.com/", { resolve: pub });
    const bad = [
        "ftp://example.com/",
        "file:///etc/passwd",
        "https://user:pw@example.com/",
        "http://localhost/",
        "http://127.0.0.1/",
        "http://[::1]/",
        "http://169.254.169.254/latest/meta-data/",
        "http://printer.local/",
        "http://db.internal/",
        "http://example.com:8080/",
        "not a url",
    ];
    for (const u of bad) await assert.rejects(() => assertPublicUrl(u, { resolve: pub }), `should reject ${u}`);
});

test("assertPublicUrl rejects a public name that resolves to a private address, or to nothing", async () => {
    await assert.rejects(() => assertPublicUrl("https://rebind.example/", { resolve: async () => ["93.184.216.34", "10.0.0.5"] }));
    await assert.rejects(() => assertPublicUrl("https://nx.example/", { resolve: async () => [] }));
    await assert.rejects(() =>
        assertPublicUrl("https://err.example/", {
            resolve: async () => {
                throw new Error("ENOTFOUND");
            },
        }),
    );
});

// ---------- run.mjs summary breakdowns ----------
test("summarize reports per tag, holdout vs tuning, and real vs synthetic", () => {
    const row = (id, label, score, tags, synthetic = false) => ({ id, label, score, tags, synthetic, localMs: 1, signals: [] });
    const rows = [
        row("s1", "scam", 90, ["bank"]),
        row("s2", "scam", 20, ["bank", "holdout"]),
        row("s3", "scam", 60, ["kurir", "holdout"], true),
        row("l1", "legit", 0, ["trap"]),
        row("l2", "legit", 40, ["trap", "holdout"]),
    ];
    const m = summarize(rows, { remote: true });
    assert.deepEqual(m.byTag.bank, { scam: { n: 2, atLeast50: 1, atLeast80: 1 }, legit: { n: 0, atLeast30: 0 } });
    assert.deepEqual(m.byTag.trap, { scam: { n: 0, atLeast50: 0, atLeast80: 0 }, legit: { n: 2, atLeast30: 1 } });
    assert.deepEqual(m.bySplit.holdout, { scam: { n: 2, atLeast50: 1, atLeast80: 0 }, legit: { n: 1, atLeast30: 1 } });
    assert.deepEqual(m.bySplit.tuning, { scam: { n: 1, atLeast50: 1, atLeast80: 1 }, legit: { n: 1, atLeast30: 0 } });
    assert.deepEqual(m.real, { scam: { n: 2, atLeast50: 1, atLeast80: 1 }, legit: { n: 2, atLeast30: 1 } });
    assert.deepEqual(m.synthetic, { scam: { n: 1, atLeast50: 1, atLeast80: 0 }, legit: { n: 0, atLeast30: 0 } });
});

// ---------- iframe URLs are redacted too ----------
import { parseHtml } from "../tools/snapshot.mjs";
test("parseHtml redacts query values and fragments of iframe URLs, relative ones included", () => {
    const html = '<iframe src="https://cdn.x/p?id=123&autoplay=1#t"></iframe><iframe src="/frame.php?u=budi@example.com"></iframe><iframe src="/plain"></iframe>';
    const { meta } = parseHtml(html, { url: "https://x.site/" });
    assert.deepEqual(meta.iframes, ["https://cdn.x/p?id=REDACTED&autoplay=REDACTED", "/frame.php?u=REDACTED", "/plain"]);
});

// ---------- mark-redacted (owner tool) ----------
import { markRedacted } from "../tools/mark-redacted.mjs";
test("markRedacted sets the flag only on real samples without findings", () => {
    const real = { ...clean(), id: "r1", redacted: false };
    const dirty = { ...withText("hubungi budi@example.com"), id: "r2", redacted: false };
    const synth = { ...clean(), id: "r3", synthetic: true, redacted: false };
    const other = { ...clean(), id: "r4", redacted: false };
    const out = markRedacted([real, dirty, synth, other], ["r1", "r2", "r3"]);
    assert.deepEqual(out, { marked: ["r1"], refused: ["r2"] });
    assert.equal(real.redacted, true);
    assert.equal(dirty.redacted, false);
    assert.equal(synth.redacted, false);
    assert.equal(other.redacted, false, "not listed, not touched");
    assert.deepEqual(markRedacted([other], null).marked, ["r4"]);
});

// ---------- /analyze preflight ----------
import { probeAnalyze } from "../lib.mjs";
test("probeAnalyze throws when /analyze is unreachable instead of letting every sample silently score layers 1-2", async () => {
    await assert.rejects(() => probeAnalyze("http://127.0.0.1:1"), /analyze/i);
});

// ======== review fixes (phase 04) ========
import { redact } from "../tools/snapshot.mjs";
import { execFileSync } from "node:child_process";
import { mkdtempSync, symlinkSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createServer } from "node:http";
import { analyzeRemote, strictExitCode, visibleRows } from "../lib.mjs";

test("redact and the checker fold fullwidth/Arabic digits and catch landlines, dotted NIK and obfuscated e-mail", () => {
    const cases = [
        ["budi [at] gmail.com", /\[email\]/],
        ["budi (at) gmail (dot) com", /\[email\]/],
        ["user\uFF20gmail.com", /\[email\]/],
        ["telp 021-5551234", /\[phone\]/],
        ["telp (021) 5551234", /\[phone\]/],
        ["NIK 3171.0101.0101.0001", /\[number\]/],
        ["NIK \uFF13\uFF11\uFF17\uFF11\uFF10\uFF11\uFF10\uFF11\uFF10\uFF11\uFF10\uFF11\uFF10\uFF10\uFF10\uFF11", /\[number\]/],
        ["wa \u0660\u0668\u0661\u0662\u0663\u0664\u0665\u0666\u0667\u0668\u0669\u0660", /\[phone\]/],
        ["wa 0 8 1 2 3 4 5 6 7 8 9 0", /\[(phone|number)\]/],
    ];
    for (const [input, want] of cases) {
        assert.match(redact(input), want, `redact should mask: ${input}`);
        assert.ok(findPersonalData(withText(input)).length > 0, `checker should flag: ${input}`);
    }
    assert.equal(redact("Rp 150.000 pukul 08.30 tahun 2026"), "Rp 150.000 pukul 08.30 tahun 2026");
});

test("form action URLs are redacted at capture and checked by the checker", () => {
    const { snapshot } = parseHtml('<form action="https://x.site/post.php?sid=abc123&u=budi@x.com#f"><input name="a"></form>', { url: "https://x.site/" });
    assert.equal(snapshot.forms[0].action, "https://x.site/post.php?sid=REDACTED&u=REDACTED");
    const s = clean();
    s.snapshot.forms[0].action = "https://bank.example/login?p_auth=hRDXgBJT";
    assert.ok(findPersonalData(s).some((p) => /action/.test(p)));
    s.snapshot.forms[0].action = "https://bank.example/login?p_auth=REDACTED";
    assert.deepEqual(findPersonalData(s), []);
});

test("a non-http snapshot.url is still scanned", () => {
    const s = clean();
    s.snapshot.url = "ftp://u:pw@h.example/?a=1";
    assert.ok(findPersonalData(s).length > 0);
});

test("isPrivateAddress also covers IPv4-compatible, NAT64, 6to4, site-local and TEST-NET ranges", () => {
    for (const ip of ["::127.0.0.1", "64:ff9b::7f00:1", "2002:7f00:1::", "fec0::1", "192.0.2.1", "198.51.100.5", "203.0.113.9", "::ffff:7f00:1"]) assert.equal(isPrivateAddress(ip), true, ip);
    assert.equal(isPrivateAddress("64:ff9b::808:808"), false, "NAT64 of a public address");
});

test("assertPublicUrl strips a trailing dot before judging the host", async () => {
    const pub = async () => ["93.184.216.34"];
    for (const u of ["http://localhost./", "http://metadata.google.internal./", "http://printer.local./"]) await assert.rejects(() => assertPublicUrl(u, { resolve: pub }), u);
});

test("targets are judged on real samples only", () => {
    const rows = [];
    for (let i = 0; i < 50; i++) rows.push({ id: `s${i}`, label: "scam", score: 90, localMs: 1, signals: [], synthetic: true });
    for (let i = 0; i < 50; i++) rows.push({ id: `l${i}`, label: "legit", score: 0, localMs: 1, signals: [], synthetic: false });
    const m = summarize(rows, { remote: true });
    assert.equal(m.targetsMet, null, "49+ synthetic scam rows cannot prove the targets");
    assert.equal(m.realEnough, false);
    for (let i = 0; i < 50; i++) rows[i].synthetic = false;
    assert.equal(summarize(rows, { remote: true }).targetsMet, true);
    rows[0].score = 10;
    rows[1].score = 10;
    rows[2].score = 10;
    rows[3].score = 10;
    rows[4].score = 10;
    rows[5].score = 10; // 44/50 = 88% < 90%
    assert.equal(summarize(rows, { remote: true }).targetsMet, false);
});

test("--strict only passes when the targets were actually met", () => {
    assert.equal(strictExitCode({ targetsMet: true }), 0);
    assert.equal(strictExitCode({ targetsMet: false }), 1);
    assert.equal(strictExitCode({ targetsMet: null }), 2, "nothing was judged: that is not a pass");
});

test("analyzeRemote reports failures and drops malformed signals instead of scoring them", async () => {
    let mode = "ok";
    const server = createServer((req, res) => {
        req.resume();
        req.on("end", () => {
            if (mode === "500") { res.statusCode = 500; return res.end("x"); }
            const good = { id: "urgent_language", layer: 3, weight: 15, label: {}, labelSimple: {} };
            const bad = mode === "nan" ? [{ id: "x", layer: 3, weight: "NaN" }, { id: "y", layer: 3 }] : [];
            res.setHeader("content-type", "application/json");
            res.end(JSON.stringify({ signals: [good, ...bad] }));
        });
    });
    await new Promise((r) => server.listen(0, "127.0.0.1", r));
    const base = `http://127.0.0.1:${server.address().port}`;
    try {
        assert.deepEqual((await analyzeRemote(base, { url: "https://a.site/" }, [])).ok, true);
        mode = "500";
        assert.equal((await analyzeRemote(base, { url: "https://a.site/" }, [])).ok, false);
        mode = "nan";
        const r = await analyzeRemote(base, { url: "https://a.site/" }, []);
        assert.equal(r.ok, false, "malformed signals count as a failed call");
        assert.deepEqual(r.signals.map((s) => s.id), ["urgent_language"]);
    } finally {
        server.close();
    }
    const m = summarize([{ id: "l", label: "legit", score: 0, localMs: 1, signals: [], remoteOk: false }], { remote: true });
    assert.equal(m.remoteFailures, 1);
});

test("holdout rows are hidden unless asked for", () => {
    const rows = [{ id: "a", tags: [] }, { id: "b", tags: ["holdout"] }];
    assert.deepEqual(visibleRows(rows, { showHoldout: false }).map((r) => r.id), ["a"]);
    assert.deepEqual(visibleRows(rows, { showHoldout: true }).map((r) => r.id), ["a", "b"]);
});

test("the CLI tools run when started through a symlink (a gate must not pass by doing nothing)", () => {
    const base = mkdtempSync(join(tmpdir(), "eval-link-"));
    const link = join(base, "linked-tools");
    symlinkSync(fileURLToPath(new URL("../tools", import.meta.url)), link);
    const dataDir = join(base, "data");
    mkdirSync(dataDir);
    writeFileSync(join(dataDir, "s.json"), JSON.stringify({ ...withText("budi@example.com"), id: "dirty" }));
    let code = 0;
    let out = "";
    try {
        out = execFileSync("node", [join(link, "check-redaction.mjs"), dataDir], { encoding: "utf8" });
    } catch (e) {
        code = e.status;
        out = e.stdout;
    }
    assert.equal(code, 1, `expected exit 1, got ${code}: ${out}`);
    assert.match(out, /dirty/);
});

test("run.mjs refuses an option that is missing its value", () => {
    for (const opt of ["--analyze-url", "--tag", "--dir"]) {
        assert.throws(() => execFileSync("node", [fileURLToPath(new URL("../run.mjs", import.meta.url)), opt], { stdio: "pipe" }), (e) => e.status === 2, opt);
    }
});
