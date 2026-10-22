// Run: node --test ai/eval/test
import test from "node:test";
import assert from "node:assert/strict";
import { findPersonalData } from "../tools/check-redaction.mjs";
import { holdoutOf, validateCorpus, HOLDOUT_FRACTION } from "../corpus.mjs";
import { isPrivateAddress, assertPublicUrl } from "../tools/safe-url.mjs";
import { summarize } from "../lib.mjs";

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
        ["jwt eyJhbGciOiJIUzI1NiJ9", "eyJzdWIiOiIxMjM0NTY3ODkwIn0", "abcdefghijk"].join("."),
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

test("validateCorpus counts samples per tag", () => {
    const c = corpus(50, 50);
    assert.deepEqual(validateCorpus(c, { seed: "s", minPerTag: { "cat-a": 100 } }), []);
    assert.ok(validateCorpus(c, { seed: "s", minPerTag: { "cat-a": 101 } }).some((x) => /cat-a/.test(x)));
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
