// Run: node --test detector/test
import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { readFileSync } from "node:fs";
import { build } from "../scripts/build.mjs";

const brands = JSON.parse(readFileSync(new URL("../data/brands.json", import.meta.url), "utf8"));
const KNOWN_IDS = ["db_match", "lookalike_domain", "brand_plus_keyword", "cheap_tld"];

const ctx = { URL };
vm.createContext(ctx);
vm.runInContext(build(), ctx); // the same single script the extension gets
const detector = ctx.ShooDetector;

// The detector runs in its own vm context, so its arrays have another prototype: copy through JSON before deepEqual.
const run = async (snapshot) => JSON.parse(JSON.stringify(await detector.analyzeLocal(snapshot)));
const scan = (url) => run({ url, domain: new URL(url).hostname.replace(/^www\./, "") });
const ids = (signals) => signals.map((s) => s.id);
const score = (signals) => Math.min(100, signals.reduce((sum, s) => sum + s.weight, 0));
const find = (signals, id) => signals.find((s) => s.id === id);

test("exposes the contract shape", () => {
    assert.equal(typeof detector.version, "string");
    assert.equal(typeof detector.analyzeLocal, "function");
});

// ---------- level 0: official domains ----------
test("every official domain in brands.json returns no signals", async () => {
    for (const brand of brands.brands) {
        for (const domain of brand.domains) {
            for (const host of [domain, `www.${domain}`, `login.${domain}`]) {
                assert.deepEqual(await scan(`https://${host}/`), [], host);
            }
        }
    }
});

test("popular sites that are not brands give no signals", async () => {
    for (const host of ["wikipedia.org", "detik.com", "kompas.com", "github.com", "toko-maju.co.id", "sekolah.sch.id"]) {
        assert.deepEqual(await scan(`https://${host}/`), [], host);
    }
});

// ---------- level 3: spelled like a brand ----------
test("p0stindonesia.com -> lookalike_domain (digit swap)", async () => {
    const s = await scan("https://p0stindonesia.com/");
    assert.deepEqual(ids(s), ["lookalike_domain"]);
    assert.equal(s[0].weight, 25);
    assert.match(s[0].evidence, /level 3 · leet/);
});

test("g00gle.com, shoppe.co.id, tokopedla.com, gooogle.com -> lookalike_domain", async () => {
    for (const host of ["g00gle.com", "shoppe.co.id", "tokopedla.com", "gooogle.com"]) {
        const s = await scan(`https://${host}/`);
        assert.ok(ids(s).includes("lookalike_domain"), host);
        assert.equal(find(s, "lookalike_domain").weight, 25, host);
    }
});

// Known limit, on purpose: typo matching needs a token of 6+ letters. A 5-letter token can be an ordinary word
// ("cloud" is one edit from "icloud"), and a wrong block of a normal site costs more than a missed typo here.
// Layers 3-4 and the database (layer 1) are there for the typos this lets through.
test("5-letter tokens are not typo-matched (cloud.com, gogle.com)", async () => {
    assert.deepEqual(await scan("https://cloud.com/"), []);
    assert.deepEqual(await scan("https://cloud-storage.com/"), []);
    assert.deepEqual(await scan("https://gogle.com/"), []);
});

test("lphone-login.com -> lookalike + brand_plus_keyword = 39 (not yet blocked by layer 2 alone)", async () => {
    const s = await scan("https://lphone-login.com/tRrQ");
    assert.deepEqual(ids(s), ["lookalike_domain", "brand_plus_keyword"]);
    assert.equal(score(s), 39);
    assert.match(find(s, "lookalike_domain").evidence, /^apple · level 3/);
});

test("Cyrillic letters that look Latin are caught (xn-- is decoded)", async () => {
    const s = await scan("https://gооgle.com/"); // two Cyrillic o
    assert.ok(new URL("https://gооgle.com/").hostname.startsWith("xn--"));
    assert.match(find(s, "lookalike_domain").evidence, /homoglyph/);
});

test("a normal international domain does not crash or trigger", async () => {
    assert.deepEqual(await scan("https://bücher.de/"), []);
});

// ---------- level 2: brand + bait word, cheap TLD next to a brand ----------
test("fixture domains from contracts/fixtures", async () => {
    const a = await scan("https://bca-verifikasi.site/login?ref=wa");
    assert.deepEqual(ids(a), ["brand_plus_keyword", "cheap_tld"]);
    assert.equal(score(a), 29);

    const b = await scan("https://promo-undian-shopee.click/hadiah");
    assert.deepEqual(ids(b), ["brand_plus_keyword", "cheap_tld"]);

    const c = await scan("https://bansos-kemensos.site/cek");
    assert.deepEqual(ids(c), ["brand_plus_keyword", "cheap_tld"]);
});

test("brand and bait word glued together (bcalogin.com)", async () => {
    assert.ok(ids(await scan("https://bcalogin.com/")).includes("brand_plus_keyword"));
});

test("brand in a subdomain of an unrelated domain", async () => {
    assert.ok(ids(await scan("https://bca-login.evil-hosting.com/")).includes("brand_plus_keyword"));
});

test("cheap TLD with a brand scores 15, alone only 5", async () => {
    assert.equal(find(await scan("https://random-shop.xyz/"), "cheap_tld").weight, 5);
    assert.equal(find(await scan("https://bca-verifikasi.xyz/"), "cheap_tld").weight, 15);
});

test("two-part suffixes (.co.id) are never treated as a cheap TLD", async () => {
    assert.deepEqual(await scan("https://toko.co.id/"), []);
});

// ---------- level 1: weak, must stay below the 30 popup on its own ----------
test("official name on an unlisted domain is weak (google.id, bri.com)", async () => {
    for (const host of ["google.id", "bri.com", "jne.com"]) {
        const s = await scan(`https://${host}/`);
        assert.deepEqual(ids(s), ["lookalike_domain"], host);
        assert.equal(s[0].weight, 10, host);
        assert.match(s[0].evidence, /level 1/);
        assert.ok(score(s) < 30, host);
    }
});

test("google.com.evil.site is judged by evil.site, not google.com", async () => {
    const s = await scan("https://google.com.evil.site/");
    assert.ok(ids(s).includes("lookalike_domain"));
    assert.ok(ids(s).includes("cheap_tld"));
});

test("a brand name inside a longer word is not enough (notgoogle.com)", async () => {
    assert.deepEqual(await scan("https://notgoogle.com/"), []);
});

// ---------- false positives: everyday words that are also brands ----------
test("common words that are brand names stay silent on their own", async () => {
    for (const host of ["dana-sosial.org", "mandiri-jaya.co.id", "toko-apple.com", "meta-data.com", "danar.com"]) {
        assert.deepEqual(await scan(`https://${host}/`), [], host);
    }
});

test("a common word plus a bait word still counts (dana-login.com)", async () => {
    assert.ok(ids(await scan("https://dana-login.com/")).includes("brand_plus_keyword"));
});

test("short brand names are not fuzzy matched (bcx.com, brx.com, ovx.com)", async () => {
    for (const host of ["bcx.com", "brx.com", "ovx.com", "jnx.com"]) {
        assert.deepEqual(await scan(`https://${host}/`), [], host);
    }
});

// ---------- limits ----------
test("layer 2 alone never reaches the block threshold (80)", async () => {
    const worst = ["lphone-login.xyz", "p0stindonesia-verifikasi.click", "bca-login.site", "g00gle-login.top"];
    for (const host of worst) assert.ok(score(await scan(`https://${host}/`)) < 80, host);
});

test("signals follow the contract", async () => {
    const samples = ["lphone-login.com", "bca-verifikasi.site", "g00gle.com", "random-shop.xyz", "bri.com"];
    for (const host of samples) {
        for (const s of await scan(`https://${host}/`)) {
            assert.ok(KNOWN_IDS.includes(s.id));
            assert.equal(s.layer, 2);
            assert.ok(Number.isInteger(s.weight) && s.weight >= 0 && s.weight <= 100);
            for (const text of [s.label, s.labelSimple]) {
                assert.ok(text.en.length > 0 && text.id.length > 0);
                assert.notEqual(text.en, text.id);
            }
            assert.equal(typeof s.evidence, "string");
        }
    }
});

test("never throws and returns [] for odd input", async () => {
    for (const input of [undefined, null, {}, { url: "" }, { url: "not a url" }, { url: "http://192.168.0.1/" }, { url: "http://[::1]/" }, { domain: 5 }]) {
        assert.deepEqual(await run(input), []);
    }
});

test("falls back to snapshot.domain when the URL cannot be parsed", async () => {
    const s = await run({ url: "garbage", domain: "p0stindonesia.com" });
    assert.deepEqual(ids(s), ["lookalike_domain"]);
});

test("is fast (target < 50 ms per scan; we expect well under 5)", async () => {
    const hosts = ["lphone-login.com", "tokopedia.com", "random-shop.xyz", "g00gle.com", "bca-verifikasi.site", "wikipedia.org"];
    const start = performance.now();
    const rounds = 500;
    for (let i = 0; i < rounds; i++) for (const h of hosts) await scan(`https://${h}/`);
    const average = (performance.now() - start) / (rounds * hosts.length);
    assert.ok(average < 5, `average ${average.toFixed(3)} ms`);
});

// ---------- brands.json hygiene ----------
test("brands.json is consistent", () => {
    const names = new Set();
    const domains = new Set();
    const ids = new Set();
    for (const b of brands.brands) {
        assert.ok(!ids.has(b.id), `duplicate id ${b.id}`);
        ids.add(b.id);
        assert.ok(b.names.length > 0 && b.domains.length > 0, b.id);
        for (const n of b.names) {
            assert.match(n, /^[a-z0-9]+$/, `name ${n}: lowercase letters/digits only`);
            assert.ok(!names.has(n), `name ${n} belongs to two brands`);
            assert.ok(!brands.keywords.includes(n), `name ${n} is also a bait word`);
            names.add(n);
        }
        for (const c of b.commonNames) assert.ok(b.names.includes(c), `${b.id}: commonNames must be in names`);
        for (const d of b.domains) {
            assert.match(d, /^[a-z0-9.-]+\.[a-z]+$/, d);
            assert.ok(!domains.has(d), `domain ${d} listed twice`);
            domains.add(d);
        }
    }
    for (const t of brands.cheapTlds) assert.match(t, /^[a-z]+$/);
    for (const k of brands.keywords) assert.match(k, /^[a-z0-9]+$/);
});

// ---------- layer 1: db_match through ShooLists.match (mocked; the real helper lives in the extension) ----------
/** Runs `fn` with globalThis.ShooLists = { match } inside the detector's context, then removes it again. */
async function withLists(match, fn) {
    ctx.ShooLists = match === undefined ? undefined : { match };
    try {
        return await fn();
    } finally {
        delete ctx.ShooLists;
    }
}
const hit = (source) => async (host) => ({ source, domain: host, addedAt: "2026-10-01T00:00:00Z" });
const TECHNICAL = /\b(domain|dns|phishing|database|blocklist|url|tld|hostname|list)\b/i;

test("layer 1: a Shoo list hit gives db_match (layer 1, weight 100, evidence shoo) and stops", async () => {
    const s = await withLists(hit("shoo"), () => scan("https://p0stindonesia.com/login"));
    assert.deepEqual(ids(s), ["db_match"]);
    assert.equal(s[0].layer, 1);
    assert.equal(s[0].weight, 100);
    assert.equal(s[0].evidence, "shoo");
});

test("layer 1: a public list hit has evidence public", async () => {
    const s = await withLists(hit("public"), () => scan("https://random-site.example/"));
    assert.deepEqual(ids(s), ["db_match"]);
    assert.equal(s[0].evidence, "public");
});

test("layer 1: match returns null -> no db_match, layer 2 still runs", async () => {
    const s = await withLists(async () => null, () => scan("https://lphone-login.com/"));
    assert.ok(!ids(s).includes("db_match"));
    assert.deepEqual(ids(s), ["lookalike_domain", "brand_plus_keyword"]);
});

test("layer 1: ShooLists missing -> still works without error", async () => {
    assert.equal(ctx.ShooLists, undefined);
    assert.deepEqual(ids(await scan("https://lphone-login.com/")), ["lookalike_domain", "brand_plus_keyword"]);
});

test("layer 1: match throws or rejects -> caught, layer 2 runs, analyzeLocal does not throw", async () => {
    for (const match of [() => { throw new Error("sync boom"); }, async () => { throw new Error("async boom"); }]) {
        const s = await withLists(match, () => scan("https://lphone-login.com/"));
        assert.deepEqual(ids(s), ["lookalike_domain", "brand_plus_keyword"]);
    }
});

test("layer 1: official domains with match null stay silent (no false positives)", async () => {
    await withLists(async () => null, async () => {
        for (const brand of brands.brands) {
            for (const domain of brand.domains) assert.deepEqual(await scan(`https://www.${domain}/`), [], domain);
        }
    });
});

test("layer 1: match gets the hostname only (no scheme, path, query, port or credentials)", async () => {
    const calls = [];
    await withLists(async (h) => { calls.push(h); return null; }, async () => {
        await run({ url: "https://User:Pw@Login.Example.COM:8443/a/b?token=secret#frag", domain: "example.com" });
        await run({ url: "https://www.p0stindonesia.com./x?y=1" });
    });
    assert.deepEqual(calls, ["login.example.com", "www.p0stindonesia.com"]);
});

test("layer 1: unparseable URL does not throw and does not call match with junk", async () => {
    const calls = [];
    await withLists(async (h) => { calls.push(h); return null; }, async () => {
        for (const input of [{ url: "" }, { url: "not a url" }, {}, { url: "http://192.168.0.1/" }, { url: "http://[::1]/" }]) {
            assert.deepEqual(await run(input), []);
        }
    });
    assert.deepEqual(calls, []);
});

test("layer 1: db_match has bilingual label and labelSimple, labelSimple in plain words", async () => {
    for (const source of ["shoo", "public"]) {
        const [s] = await withLists(hit(source), () => scan("https://scam-site.example/"));
        for (const text of [s.label, s.labelSimple]) {
            assert.ok(text.en.length > 0 && text.id.length > 0, source);
            assert.notEqual(text.en, text.id);
        }
        assert.doesNotMatch(s.labelSimple.en, TECHNICAL);
        assert.doesNotMatch(s.labelSimple.id, TECHNICAL);
    }
});

test("layer 1: match is called with exactly one argument, the hostname", async () => {
    const argLengths = [];
    await withLists(async (...args) => { argLengths.push(args.length); return null; }, () => scan("https://lphone-login.com/a?b=c"));
    assert.deepEqual(argLengths, [1]);
});

test("layer 1: a hit on an official domain still wins (the server keeps official domains off the lists)", async () => {
    const s = await withLists(hit("shoo"), () => scan("https://www.bca.co.id/"));
    assert.deepEqual(ids(s), ["db_match"]);
});

test("layer 1: malformed hits are ignored and layer 2 runs", async () => {
    const bad = [true, "x", 5, {}, { source: 5 }, { source: "evil", domain: "x.com" }, { source: "" }];
    for (const value of bad) {
        const s = await withLists(async () => value, () => scan("https://lphone-login.com/"));
        assert.deepEqual(ids(s), ["lookalike_domain", "brand_plus_keyword"], JSON.stringify(value));
    }
    const throwing = { get source() { throw new Error("boom"); } };
    const s = await withLists(async () => throwing, () => scan("https://lphone-login.com/"));
    assert.deepEqual(ids(s), ["lookalike_domain", "brand_plus_keyword"]);
});
