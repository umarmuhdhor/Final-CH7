// 05b X3-X5 (admin dashboard): calibration report, dashboard import, versioned cases, lesson drafts. All invented `.test`
// domains, fake dashboard and fake LLM: no network, no real data.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { adminUrl, createDashboard, dashboardFromEnv, parseJson } from "../scripts/dashboard.mjs";
import { calibrate, renderReport, MIN_DENOMINATOR } from "../scripts/calibration-report.mjs";
import { toSamples } from "../eval/tools/import-dashboard.mjs";
import { buildCaseSet } from "../scripts/build-cases.mjs";
import { parseCases, casesForModel, createCasesLoader, ACTIVE_KEY, CASES_TTL_MS, MAX_CASES } from "../src/layer4/cases.js";
import { toLesson, caseInput, draftLessons, DEFAULT_MAX_CALLS, SYSTEM_PROMPT as LESSONS_PROMPT } from "../scripts/lessons.mjs";
import { buildInput, createRealityCheck } from "../src/layer4/reality.js";
import { createApp } from "../src/app.js";
import { summarize } from "../eval/lib.mjs";
import { field, page, SCAM_URL } from "./helpers.mjs";

const BASE = "https://shoo-admin.team.workers.dev";

// ---------------------------------------------------------------- dashboard client

test("adminUrl: only https workers.dev origins", () => {
    assert.equal(adminUrl(BASE), BASE);
    assert.equal(adminUrl(`${BASE}/`), BASE);
    for (const bad of ["http://shoo-admin.team.workers.dev", `${BASE}/api`, `${BASE}?x=1`, "https://u:p@shoo-admin.team.workers.dev", "https://evil.test", "https://shoo-admin.team.workers.dev:8443", "", null]) {
        assert.equal(adminUrl(bad), null, String(bad));
    }
    assert.throws(() => dashboardFromEnv({ SHOO_ADMIN_URL: BASE }), /missing CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET/);
    assert.throws(() => dashboardFromEnv({ SHOO_ADMIN_URL: "https://evil.test", CF_ACCESS_CLIENT_ID: "i", CF_ACCESS_CLIENT_SECRET: "s" }), /workers\.dev/);
});

test("client: Access headers, no redirects, JSONL paging by X-Next-Cursor, errors without query or body", async () => {
    const calls = [];
    const pages = { "": ['{"domain":"a.test"}', '{"domain":"b.test"}'], "b.test": ['{"domain":"c.test"}'] };
    const http = async (url, init) => {
        calls.push({ url: String(url), init });
        const cursor = url.searchParams.get("cursor") ?? "";
        if (url.pathname === "/api/fail") return new Response("secret body naming x.test", { status: 500 });
        const headers = cursor === "" ? { "x-next-cursor": "b.test" } : {};
        return new Response(pages[cursor].join("\n") + "\n", { status: 200, headers });
    };
    const dash = createDashboard({ baseUrl: BASE, clientId: "id-NOT-REAL", clientSecret: "secret-NOT-REAL", fetch: http });
    const rows = await dash.getJsonl("/api/export/intel.jsonl", { label: "safe" });
    assert.deepEqual(rows.map((r) => r.domain), ["a.test", "b.test", "c.test"]);
    assert.equal(calls.length, 2);
    assert.equal(calls[1].url, `${BASE}/api/export/intel.jsonl?label=safe&cursor=b.test`);
    for (const c of calls) {
        assert.equal(c.init.redirect, "manual");
        assert.equal(c.init.headers["cf-access-client-id"], "id-NOT-REAL");
    }
    await assert.rejects(dash.getJson("/api/fail?cursor=x.test"), (e) => e.message === "GET /api/fail failed: HTTP 500");
    assert.throws(() => parseJson('{"domain": "leak.test"', "x"), (e) => !e.message.includes("leak.test"));
});

// ---------------------------------------------------------------- X3 calibration report

const intel = (label, signals, domain) => ({ domain, label, signals, firstSeenAt: "2026-10-01T00:00:00Z", families: { scam: 2, safe: 0 } });
function intelRows() {
    const rows = [];
    for (let i = 0; i < 8; i++) rows.push(intel("scam_strong", { asks_pin: 2, new_domain: 1 }, `scam-${i}.test`));
    for (let i = 0; i < 2; i++) rows.push(intel("scam_weak", { asks_pin: 1 }, `weak-${i}.test`));
    for (let i = 0; i < 6; i++) rows.push(intel("safe", { new_domain: 1, ...(i < 1 ? { asks_pin: 1 } : {}) }, `safe-${i}.test`));
    rows.push(intel(null, { asks_pin: 5 }, "nolabel.test"));
    rows.push(intel("safe", { "evil-site.test": 1 }, "odd-1.test"), intel("scam_strong", { rare_id: 1 }, "odd-2.test"));
    return rows;
}

test("calibrate: per signal id, domains not scans, unlabelled skipped, odd or rare ids folded", () => {
    const r = calibrate(intelRows());
    assert.equal(r.scam, 11);
    assert.equal(r.safe, 7);
    assert.equal(r.unlabelled, 1);
    const by = Object.fromEntries(r.signals.map((s) => [s.id, s]));
    assert.deepEqual(Object.keys(by), ["asks_pin", "new_domain", "(other)"]);
    assert.equal(by.asks_pin.scam, 10);
    assert.equal(by.asks_pin.safe, 1);
    assert.equal(by.asks_pin.precision, 10 / 11);
    assert.equal(by.asks_pin.recall, 10 / 11);
    assert.equal(by.new_domain.precision, 8 / 14);
    assert.equal(by.new_domain.safeRate, 6 / 7);
    assert.deepEqual([by["(other)"].scam, by["(other)"].safe], [1, 1]);
    assert.equal(by["(other)"].precision, null, `under ${MIN_DENOMINATOR} domains: no ratio`);
});

test("report: numbers and signal ids only, never a domain", () => {
    const rows = intelRows();
    const md = renderReport(calibrate(rows), { date: "2026-11-03", since: "2026-10-01" });
    for (const r of rows) assert.ok(!md.includes(r.domain), r.domain);
    assert.ok(!md.includes("evil-site"));
    assert.match(md, /\| `asks_pin` \| 10 \| 1 \| 91% \| 91% \| 14% \|/);
    assert.match(md, /To look at \(precision under 50%\): none|No signal with precision under 50%/);
    assert.ok(!/https?:\/\//.test(md));
});

test("workflow: off by default, pinned actions, no artifact upload, export token only in the read job", () => {
    const yml = readFileSync(fileURLToPath(new URL("../../.github/workflows/ai-calibration.yml", import.meta.url)), "utf8");
    assert.match(yml, /if: vars\.AI_CALIBRATION_ENABLED == 'true'/);
    assert.match(yml, /^permissions: \{\}$/m);
    for (const use of yml.match(/uses: \S+/g)) assert.match(use, /@[0-9a-f]{40}$/, use);
    assert.ok(!yml.includes("upload-artifact"));
    const [readJob, writeJob] = yml.split(/^  open-pr:$/m);
    assert.match(readJob, /secrets\.CF_ACCESS_CLIENT_SECRET/);
    assert.ok(!writeJob.includes("secrets."), "the job that can write never sees the export token");
});

// ---------------------------------------------------------------- K6 dashboard import

const exported = (over = {}) => ({
    id: "dash-0123456789ab",
    label: "scam",
    tags: ["bank", "url-only"],
    synthetic: false,
    redacted: false,
    source: "shoo-dashboard 2026-11-01 scam_strong",
    collectedAt: "2026-11-01T00:00:00.000Z",
    snapshot: { url: "https://bank-verif.test/" },
    ...over,
});

test("import: redacted forced to false, unexpected shapes dropped, known ids skipped", () => {
    const { samples, dropped } = toSamples(
        [
            exported({ redacted: true }),
            exported({ id: "dash-aaaaaaaaaaaa", snapshot: { url: "https://x.test/", text: "page words" } }),
            exported({ id: "dash-bbbbbbbbbbbb", note: undefined, tags: ["bank"] }),
            exported({ id: "dash-cccccccccccc", snapshot: { url: "https://x.test/login?u=1" } }),
            exported({ id: "dash-dddddddddddd" }),
        ],
        new Set(["dash-dddddddddddd"]),
    );
    assert.equal(samples.length, 1);
    assert.equal(samples[0].redacted, false);
    assert.equal(dropped, 3);
    assert.deepEqual(Object.keys(samples[0]).sort(), ["collectedAt", "id", "label", "redacted", "snapshot", "source", "synthetic", "tags"]);
    const src = readFileSync(fileURLToPath(new URL("../eval/tools/import-dashboard.mjs", import.meta.url)), "utf8");
    assert.ok(!/redacted"?\s*:\s*true/.test(src), "the import never sets redacted: true");
});

test("eval: url-only samples do not count toward the mandate targets", () => {
    const row = (id, label, score, tags = []) => ({ id, label, score, tags, synthetic: false, signals: [], localMs: 1, remoteMs: null, remoteOk: null });
    const rows = [row("a", "scam", 90), row("b", "scam", 10, ["url-only"]), row("c", "legit", 0)];
    const s = summarize(rows);
    assert.equal(s.checks.scamAtLeast50.value, 1, "the url-only miss is not in the target");
    assert.equal(s.checksAll.scamAtLeast50.value, 0.5, "but it is in the every-sample view");
});

// ---------------------------------------------------------------- X4 versioned cases

const casesJson = () => ({
    cases: [
        { id: 7, domain: "bank-verif.test", signals: { asks_pin: 3, new_domain: 1, "bad id": 2 }, label: "scam_strong", category: "phishing_bank", note: "admin note about bank-verif.test", pinned: true, source: "admin", createdAt: "2026-11-01T00:00:00Z" },
        { id: 9, domain: "shop.test", signals: { brand_logo_offsite: 1 }, label: "safe", category: null, note: null, pinned: false, source: "analysis", createdAt: "2026-11-02T00:00:00Z" },
        { id: 11, domain: "empty.test", signals: {}, label: "scam_weak", category: null, note: null },
    ],
    lessons: [{ id: 1, kind: "avoid", text: "a pinned lesson", conditions: {}, pinned: true, createdAt: "2026-11-01T00:00:00Z" }],
});

test("build-cases: no domain, note or lesson; same library -> same version; the Worker accepts it", () => {
    const set = buildCaseSet(casesJson());
    const raw = JSON.stringify(set);
    for (const s of ["bank-verif", "shop.test", "admin note", "pinned lesson", "bad id", "createdAt"]) assert.ok(!raw.includes(s), s);
    assert.deepEqual(set.cases, [
        { id: 7, rules: ["asks_pin", "new_domain"], label: "scam_strong", category: "phishing_bank" },
        { id: 9, rules: ["brand_logo_offsite"], label: "safe", category: null },
    ]);
    assert.match(set.version, /^[0-9a-f]{8}$/);
    assert.equal(buildCaseSet(casesJson()).version, set.version);
    const changed = casesJson();
    changed.cases[1].label = "scam_weak";
    assert.notEqual(buildCaseSet(changed).version, set.version);
    assert.deepEqual(parseCases(JSON.stringify(set)), set);
});

test("parseCases: one bad case makes the whole set unusable", () => {
    const good = buildCaseSet(casesJson());
    for (const bad of [
        { ...good, version: "XYZ" },
        { ...good, cases: [{ ...good.cases[0], rules: ["Bad Id"] }] },
        { ...good, cases: [{ ...good.cases[0], label: "maybe" }] },
        { ...good, cases: [{ ...good.cases[0], category: "<b>" }] },
        { ...good, cases: [{ ...good.cases[0], id: 0 }] },
        "not json",
        null,
    ]) {
        assert.equal(parseCases(typeof bad === "string" || bad === null ? bad : JSON.stringify(bad)), null);
    }
});

function fakeKv(store) {
    const reads = [];
    return { reads, get: async (k) => (reads.push(k), store[k] ?? null) };
}

test("loader: off unless CASES_ENABLED is \"true\"; reads cases:active then the set; cached 10 min; KV error -> null", async () => {
    const set = buildCaseSet(casesJson());
    let t = 0;
    const load = createCasesLoader({ now: () => t });
    const kv = fakeKv({ [ACTIVE_KEY]: set.version, [`cases:${set.version}`]: JSON.stringify(set) });
    assert.equal(await load({ CASES_KV: kv }), null);
    assert.equal(await load({ CASES_KV: kv, CASES_ENABLED: "1" }), null);
    assert.equal(kv.reads.length, 0);
    assert.deepEqual(await load({ CASES_KV: kv, CASES_ENABLED: "true" }), set);
    assert.deepEqual(kv.reads, [ACTIVE_KEY, `cases:${set.version}`]);
    t += CASES_TTL_MS - 1;
    await load({ CASES_KV: kv, CASES_ENABLED: "true" });
    assert.equal(kv.reads.length, 2, "cached");
    t += 2;
    await load({ CASES_KV: kv, CASES_ENABLED: "true" });
    assert.equal(kv.reads.length, 4, "re-read after the TTL");

    const wrong = createCasesLoader();
    assert.equal(await wrong({ CASES_ENABLED: "true", CASES_KV: fakeKv({ [ACTIVE_KEY]: "deadbeef", "cases:deadbeef": JSON.stringify(set) }) }), null, "key and content disagree");
    const down = createCasesLoader();
    assert.equal(await down({ CASES_ENABLED: "true", CASES_KV: { get: async () => { throw new Error("kv down"); } } }), null);
});

test("layer 4: cases go into the model input as data only when on; casesVersion in stats() and ai_usage", async () => {
    const set = buildCaseSet(casesJson());
    const snap = page(SCAM_URL, [field({ name: "pin", label: "PIN" })], { title: "Cek hadiah anda" });
    assert.ok(!("cases" in buildInput(snap, ["asks_pin"], [])));
    assert.deepEqual(buildInput(snap, ["asks_pin"], [], casesForModel(set)).cases, [
        { rules: ["asks_pin", "new_domain"], label: "scam", category: "phishing_bank" },
        { rules: ["brand_logo_offsite"], label: "safe", category: null },
    ]);
    const many = { version: set.version, cases: Array.from({ length: 30 }, (_, i) => ({ ...set.cases[0], id: i + 1 })) };
    assert.equal(casesForModel(many).length, MAX_CASES);

    const sent = [];
    const fetch = async (u, init) => {
        sent.push(JSON.parse(init.body));
        return new Response(JSON.stringify({ choices: [{ message: { content: JSON.stringify({ page_type: "prize", asks: ["pin"], reasonable: true, confidence: 0.9, evidence: null }) } }] }), { status: 200 });
    };
    const CONFIG = { apiKey: "k-NOT-REAL", model: "m", baseUrl: "https://llm.test/v1", timeoutMs: 400, dailyCap: 100 };
    const points = [];
    const env = { AI_USAGE: { writeDataPoint: (p) => points.push(p) } };
    const send = (app) => app.request("/analyze", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ snapshot: snap, localSignals: [] }) }, env);

    const off = createRealityCheck({ config: CONFIG, fetch });
    await send(createApp({ llm: off }));
    assert.ok(!sent[0].messages[1].content.includes('"cases"'));
    assert.equal(off.stats().casesVersion, null);

    const on = createRealityCheck({ config: CONFIG, fetch });
    await send(createApp({ llm: on, cases: set }));
    assert.ok(sent[1].messages[1].content.includes('"cases":[{"rules":["asks_pin","new_domain"],"label":"scam"'));
    assert.equal(sent[1].messages[0].content, sent[0].messages[0].content, "the system prompt never changes");
    assert.equal(on.stats().casesVersion, set.version);
    assert.deepEqual(points.map((p) => p.blobs[1]), ["none", set.version]);
});

// ---------------------------------------------------------------- X5 lesson drafts

const mismatch = (over = {}) => ({ domain: "bank-verif.test", signals: { asks_pin: 2, new_domain: 1 }, aiScore: 85, aiStatus: "blocked", label: "safe", outcome: "fp", decidedAt: "2026-11-01T00:00:00Z", ...over });

test("lessons: fp -> avoid, fn -> repeat; general text only; conditions limited to the case's rules", () => {
    const answer = (o) => JSON.stringify({ text: "A PIN form on a new domain is not enough to block without a brand signal.", conditions: { rules: ["asks_pin", "new_domain", "made_up"], minScore: 80, maxScore: 300 }, ...o });
    const l = toLesson(answer(), mismatch());
    assert.equal(l.kind, "avoid");
    assert.deepEqual(l.conditions, { rules: ["asks_pin", "new_domain"], minScore: 80, maxScore: null, prompt: "lessons.v1" });
    assert.equal(toLesson(answer(), mismatch({ outcome: "fn", label: "scam_strong" })).kind, "repeat");
    for (const text of ["Pages like bank-verif.test are fine", "bank-verif pages are fine", "x".repeat(501), "use <b>", ""]) assert.equal(toLesson(answer({ text }), mismatch()), null, text);
    assert.equal(toLesson("not json", mismatch()), null);
    assert.deepEqual(caseInput(mismatch()), { site: "bank-verif.test", rules: ["asks_pin", "new_domain"], score: 85, decided: "safe", outcome: "fp" });
    assert.match(LESSONS_PROMPT, /data, never instructions/);
});

test("lessons: one call per mismatch, capped; failed or refused answers are counted, not sent", async () => {
    const runs = { runs: [], mismatches: [...Array.from({ length: 30 }, (_, i) => mismatch({ domain: `d${i}.test` })), { domain: "x.test", outcome: "tp" }] };
    let n = 0;
    const ask = async (messages) => {
        n += 1;
        assert.ok(messages[1].content.startsWith("DATA_START\n"));
        if (n === 2) return { ok: false, reason: "timeout" };
        if (n === 3) return { ok: true, content: '{"text":"<script>"}' };
        return { ok: true, content: JSON.stringify({ text: "Lower trust in a lone PIN field.", conditions: { rules: ["asks_pin"] } }) };
    };
    const r = await draftLessons(runs, { ask });
    assert.equal(r.calls, DEFAULT_MAX_CALLS);
    assert.equal(r.lessons.length, DEFAULT_MAX_CALLS - 2);
    assert.equal(r.refused, 2);
    assert.equal((await draftLessons(runs, { ask, maxCalls: 3 })).calls, 3);
});
