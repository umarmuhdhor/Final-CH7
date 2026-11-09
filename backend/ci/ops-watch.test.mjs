// Tests for ops-watch.mjs (fase 21b). Run: node --test backend/ci/
// fetch, sleep and the gh CLI are fakes: nothing here touches the network or GitHub.
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  CODES,
  LIMITS,
  checkDaily,
  checkQuick,
  evaluateAnalytics,
  main,
  parseSimulate,
  queries,
  summary,
  syncIssue,
} from "./ops-watch.mjs";

const BASE = "https://shoo-api.example.workers.dev";
const TOKEN = "t".repeat(44);
const CF_TOKEN = "c".repeat(40);
const ACCOUNT = "0123456789abcdef0123456789abcdef";
const NOW = new Date("2026-11-09T20:41:00Z");

const json = (status, body) => ({ status, json: async () => body });

/** fetch fake: routes by URL path, records every call. */
function fakeFetch(routes) {
  const calls = [];
  const fn = async (url, init = {}) => {
    calls.push({ url, init });
    const path = new URL(url).pathname;
    const route = routes[path];
    if (route === undefined) throw new Error(`unexpected ${path}`);
    const r = typeof route === "function" ? route(init, calls.filter((c) => new URL(c.url).pathname === path).length) : route;
    if (r instanceof Error) throw r;
    return r;
  };
  fn.calls = calls;
  return fn;
}

const noSleep = Object.assign(async (ms) => noSleep.waits.push(ms), { waits: [] });
const okStatus = json(200, { ok: true, failing: [], dbBytes: 123456789, blocklistQueue: 4 });

describe("checkQuick", () => {
  it("reports healthz_down only after 3 failed attempts, 20 s apart", async () => {
    const sleep = Object.assign(async (ms) => sleep.waits.push(ms), { waits: [] });
    const f = fakeFetch({ "/healthz": json(503, {}), "/ops/status": okStatus });
    const codes = await checkQuick({ base: BASE, token: TOKEN, fetchImpl: f, sleep });
    assert.deepEqual(codes, [{ code: "healthz_down", level: "alert" }]);
    assert.equal(f.calls.filter((c) => c.url.endsWith("/healthz")).length, 3);
    assert.deepEqual(sleep.waits, [20_000, 20_000]);
  });

  it("is quiet when healthz answers on the third try", async () => {
    const f = fakeFetch({ "/healthz": (_i, n) => (n < 3 ? new Error("ECONNRESET") : json(200, { ok: true })), "/ops/status": okStatus });
    assert.deepEqual(await checkQuick({ base: BASE, token: TOKEN, fetchImpl: f, sleep: noSleep }), []);
  });

  it("sends the token as a Bearer header, never in the URL", async () => {
    const f = fakeFetch({ "/healthz": json(200, {}), "/ops/status": okStatus });
    await checkQuick({ base: BASE, token: TOKEN, fetchImpl: f, sleep: noSleep });
    const call = f.calls.find((c) => c.url.endsWith("/ops/status"));
    assert.equal(call.init.headers.authorization, `Bearer ${TOKEN}`);
    for (const c of f.calls) assert.ok(!c.url.includes(TOKEN));
  });

  for (const [what, answer] of [["404", json(404, {})], ["500", json(500, {})], ["network error", new Error("boom")], ["bad JSON", { status: 200, json: async () => { throw new SyntaxError("x"); } }]]) {
    it(`reports ops_status_unreachable on ${what}`, async () => {
      const f = fakeFetch({ "/healthz": json(200, {}), "/ops/status": answer });
      assert.deepEqual(await checkQuick({ base: BASE, token: TOKEN, fetchImpl: f, sleep: noSleep }), [{ code: "ops_status_unreachable", level: "alert" }]);
    });
  }

  it("never follows redirects (a 3xx is a failure)", async () => {
    const f = fakeFetch({ "/healthz": json(200, {}), "/ops/status": json(302, {}) });
    assert.deepEqual(await checkQuick({ base: BASE, token: TOKEN, fetchImpl: f, sleep: noSleep }), [{ code: "ops_status_unreachable", level: "alert" }]);
    for (const c of f.calls) assert.equal(c.init.redirect, "manual");
  });

  it("reports ops_status_unreachable without calling when the token is missing", async () => {
    const f = fakeFetch({ "/healthz": json(200, {}) });
    assert.deepEqual(await checkQuick({ base: BASE, token: "", fetchImpl: f, sleep: noSleep }), [{ code: "ops_status_unreachable", level: "alert" }]);
  });

  it("treats 429 as unknown (warn), not as an outage (fase 21a review LOW 4)", async () => {
    const f = fakeFetch({ "/healthz": json(200, {}), "/ops/status": json(429, {}) });
    assert.deepEqual(await checkQuick({ base: BASE, token: TOKEN, fetchImpl: f, sleep: noSleep }), [{ code: "ops_status_limited", level: "warn" }]);
  });

  it("passes the backend's failing[] through and drops malformed entries", async () => {
    const body = {
      ok: false,
      failing: [
        { code: "retention_failed", level: "alert" },
        { code: "db_size_high", level: "warn" },
        { code: "some new_code", level: "alert" },
        { code: "x".repeat(60), level: "alert" },
        { code: "fine_code", level: "critical" },
        "retention_stale",
      ],
    };
    const f = fakeFetch({ "/healthz": json(200, {}), "/ops/status": json(200, body) });
    assert.deepEqual(await checkQuick({ base: BASE, token: TOKEN, fetchImpl: f, sleep: noSleep }), [
      { code: "retention_failed", level: "alert" },
      { code: "db_size_high", level: "warn" },
    ]);
  });
});

/** GraphQL answer with the shape of the two queries. */
function analytics({ workers = [], ops = [], storage = [] } = {}) {
  return {
    workers: { viewer: { accounts: [{ workersInvocationsAdaptive: workers }] } },
    r2: { viewer: { accounts: [{ ops, storage }] } },
  };
}
const w = (scriptName, status, requests, errors = 0) => ({ sum: { requests, errors }, dimensions: { scriptName, status } });
const codesOf = (list) => list.map((c) => c.code);

describe("evaluateAnalytics", () => {
  it("is quiet on a normal day", () => {
    assert.deepEqual(evaluateAnalytics(analytics({ workers: [w("shoo-api", "success", 5000, 2)] })), []);
  });

  it("worker_exceeded_cpu from 1 exceededResources invocation of shoo-api", () => {
    assert.deepEqual(codesOf(evaluateAnalytics(analytics({ workers: [w("shoo-api", "success", 100), w("shoo-api", "exceededResources", 1, 1)] }))), ["worker_exceeded_cpu"]);
    assert.deepEqual(evaluateAnalytics(analytics({ workers: [w("shoo-ai", "exceededResources", 3, 3)] })), []);
    for (const status of ["exceededCpu", "exceededMemory"]) {
      assert.deepEqual(codesOf(evaluateAnalytics(analytics({ workers: [w("shoo-api", "success", 100), w("shoo-api", status, 1, 1)] }))), ["worker_exceeded_cpu"]);
    }
  });

  it("worker_errors above 1 % with at least 50 requests", () => {
    assert.deepEqual(evaluateAnalytics(analytics({ workers: [w("shoo-api", "success", 100, 1)] })), []);
    assert.deepEqual(codesOf(evaluateAnalytics(analytics({ workers: [w("shoo-api", "success", 100, 2)] }))), ["worker_errors"]);
    assert.deepEqual(evaluateAnalytics(analytics({ workers: [w("shoo-api", "success", 49, 20)] })), []);
    assert.deepEqual(codesOf(evaluateAnalytics(analytics({ workers: [w("shoo-api", "success", 50, 1), w("shoo-api", "scriptThrewException", 0, 1)] }))), ["worker_errors"]);
  });

  it("worker_requests_high counts every Worker of the account (the Free limit is per account)", () => {
    const below = LIMITS.workerRequestsDay - 1;
    assert.deepEqual(evaluateAnalytics(analytics({ workers: [w("shoo-api", "success", below - 10), w("shoo-ai", "success", 10)] })), []);
    assert.deepEqual(codesOf(evaluateAnalytics(analytics({ workers: [w("shoo-api", "success", below), w("shoo-ai", "success", 1)] }))), ["worker_requests_high"]);
  });

  it("R2 class A and B at the limit, delete is free", () => {
    const a = (actionType, requests) => ({ sum: { requests }, dimensions: { actionType } });
    assert.deepEqual(evaluateAnalytics(analytics({ ops: [a("PutObject", LIMITS.r2ClassAMonth - 2), a("ListObjects", 1), a("DeleteObject", 9_000_000)] })), []);
    assert.deepEqual(codesOf(evaluateAnalytics(analytics({ ops: [a("PutObject", LIMITS.r2ClassAMonth - 1), a("CreateMultipartUpload", 1)] }))), ["r2_class_a_high"]);
    assert.deepEqual(codesOf(evaluateAnalytics(analytics({ ops: [a("GetObject", LIMITS.r2ClassBMonth - 1), a("HeadObject", 1)] }))), ["r2_class_b_high"]);
    // An action type this script does not know counts as class A (the more expensive guess).
    assert.deepEqual(codesOf(evaluateAnalytics(analytics({ ops: [a("PutObject", LIMITS.r2ClassAMonth - 1), a("SomeNewAction", 1)] }))), ["r2_class_a_high"]);
  });

  it("r2_storage_high sums the buckets", () => {
    const s = (bucketName, payloadSize, metadataSize = 0) => ({ max: { payloadSize, metadataSize }, dimensions: { bucketName } });
    assert.deepEqual(evaluateAnalytics(analytics({ storage: [s("a", LIMITS.r2StorageBytes - 2), s("b", 1)] })), []);
    assert.deepEqual(codesOf(evaluateAnalytics(analytics({ storage: [s("a", LIMITS.r2StorageBytes - 2), s("b", 1, 1)] }))), ["r2_storage_high"]);
  });

  it("levels follow CODES", () => {
    const list = evaluateAnalytics(analytics({ workers: [w("shoo-api", "exceededResources", 100, 100)] }));
    for (const c of list) assert.equal(c.level, CODES[c.code]);
  });
});

describe("queries", () => {
  it("never select objectName (R2 keys carry device ids, SECURITY P6)", () => {
    const q = queries();
    assert.ok(!q.workers.includes("objectName"));
    assert.ok(!q.r2.includes("objectName"));
    assert.match(q.r2, /actionType/);
  });
});

describe("checkDaily", () => {
  const graphql = (init) => {
    const { query, variables } = JSON.parse(init.body);
    assert.equal(variables.account, ACCOUNT);
    assert.equal(init.headers.authorization, `Bearer ${CF_TOKEN}`);
    const data = analytics({ workers: [w("shoo-api", "success", 10)] });
    return json(200, { data: query.includes("workersInvocationsAdaptive") ? data.workers : data.r2 });
  };

  it("calls /healthz/db (keep-alive) and Cloudflare GraphQL", async () => {
    const f = fakeFetch({ "/healthz/db": json(200, { ok: true }), "/client/v4/graphql": graphql });
    assert.deepEqual(await checkDaily({ base: BASE, cfToken: CF_TOKEN, accountId: ACCOUNT, fetchImpl: f, now: NOW }), []);
    assert.equal(f.calls.filter((c) => c.url.endsWith("/healthz/db")).length, 1);
    const vars = JSON.parse(f.calls.find((c) => c.url.includes("graphql") && c.init.body.includes("r2")).init.body).variables;
    assert.equal(vars.monthStart, "2026-11-01T00:00:00.000Z");
    assert.equal(vars.dayStart, "2026-11-08T20:42:00.000Z");
  });

  it("cf_analytics_unavailable when the account is not visible (200 with accounts: []) or shoo-api has no rows", async () => {
    for (const data of [{ viewer: { accounts: [] } }, analytics({ workers: [w("shoo-ai", "success", 10)] }).workers]) {
      const f = fakeFetch({
        "/healthz/db": json(200, {}),
        "/client/v4/graphql": (init) => json(200, { data: JSON.parse(init.body).query.includes("workersInvocationsAdaptive") ? data : analytics().r2 }),
      });
      assert.deepEqual(await checkDaily({ base: BASE, cfToken: CF_TOKEN, accountId: ACCOUNT, fetchImpl: f, now: NOW }), [{ code: "cf_analytics_unavailable", level: "alert" }]);
    }
  });

  it("healthz_db_failed when /healthz/db is not 200", async () => {
    const f = fakeFetch({ "/healthz/db": json(429, {}), "/client/v4/graphql": graphql });
    assert.deepEqual(await checkDaily({ base: BASE, cfToken: CF_TOKEN, accountId: ACCOUNT, fetchImpl: f, now: NOW }), [{ code: "healthz_db_failed", level: "alert" }]);
  });

  it("cf_analytics_unavailable is an alert without token, with a bad account id, or on GraphQL errors (PR #340 review 3)", async () => {
    const f = fakeFetch({ "/healthz/db": json(200, {}), "/client/v4/graphql": json(200, { data: null, errors: [{ message: "x" }] }) });
    for (const [cfToken, accountId] of [["", ACCOUNT], [CF_TOKEN, "nope"], [CF_TOKEN, ACCOUNT]]) {
      assert.deepEqual(await checkDaily({ base: BASE, cfToken, accountId, fetchImpl: f, now: NOW }), [{ code: "cf_analytics_unavailable", level: "alert" }]);
    }
  });

  it("retries a transient GraphQL answer (5xx, network) 20 s apart, then gives up", async () => {
    const sleep = Object.assign(async (ms) => sleep.waits.push(ms), { waits: [] });
    const flaky = (init, n) => (n <= 2 ? json(503, {}) : graphql(init));
    const f = fakeFetch({ "/healthz/db": json(200, {}), "/client/v4/graphql": flaky });
    // Both queries share the path counter: calls 1-2 are attempt 1, 3-4 attempt 2.
    assert.deepEqual(await checkDaily({ base: BASE, cfToken: CF_TOKEN, accountId: ACCOUNT, fetchImpl: f, now: NOW, sleep }), []);
    assert.deepEqual(sleep.waits, [20_000]);

    const down = Object.assign(async (ms) => down.waits.push(ms), { waits: [] });
    const g = fakeFetch({ "/healthz/db": json(200, {}), "/client/v4/graphql": new Error("ECONNRESET") });
    assert.deepEqual(await checkDaily({ base: BASE, cfToken: CF_TOKEN, accountId: ACCOUNT, fetchImpl: g, now: NOW, sleep: down }), [{ code: "cf_analytics_unavailable", level: "alert" }]);
    assert.equal(g.calls.filter((c) => c.url.includes("graphql")).length, 6);
    assert.deepEqual(down.waits, [20_000, 20_000]);
  });

  it("does not retry a 401/403 (token revoked or wrong scope)", async () => {
    const sleep = Object.assign(async (ms) => sleep.waits.push(ms), { waits: [] });
    const f = fakeFetch({ "/healthz/db": json(200, {}), "/client/v4/graphql": json(403, { errors: [{ message: "x" }] }) });
    assert.deepEqual(await checkDaily({ base: BASE, cfToken: CF_TOKEN, accountId: ACCOUNT, fetchImpl: f, now: NOW, sleep }), [{ code: "cf_analytics_unavailable", level: "alert" }]);
    assert.equal(f.calls.filter((c) => c.url.includes("graphql")).length, 2);
    assert.deepEqual(sleep.waits, []);
  });
});

describe("parseSimulate", () => {
  it("accepts only known codes", () => {
    assert.deepEqual(parseSimulate("retention_failed, worker_errors"), [
      { code: "retention_failed", level: "alert" },
      { code: "worker_errors", level: "alert" },
    ]);
    assert.deepEqual(parseSimulate("$(rm -rf /),nope"), []);
    assert.deepEqual(parseSimulate(undefined), []);
  });
});

const BOT = { login: "github-actions" };

/** The bot as REST reports it (`user.login`), and as the GraphQL fixtures below name it. */
const restLogin = (login) => (login === "github-actions" ? "github-actions[bot]" : login);

/**
 * Error shaped like the one promisify(execFile) rejects with: `message` carries the whole command
 * line (so it always contains --assignee), the gh output is in `stderr`.
 */
function execError(args, stderr) {
  return Object.assign(new Error(`Command failed: gh ${args.join(" ")}\n${stderr}`), { code: 1, stderr, stdout: "" });
}

/**
 * gh fake: answers per subcommand, records every call. `open` = open issues (REST /issues);
 * `createFails` = stderr of a failing `issue create --assignee`; `createdAnyway` = GitHub created
 * the issue although gh failed (timeout).
 */
function fakeGh({ open = [], view = { author: BOT, body: "", comments: [] }, createFails = null, createdAnyway = false } = {}) {
  const calls = [];
  let created = false;
  const gh = async (args) => {
    calls.push(args);
    const cmd = args.slice(0, 2).join(" ");
    if (args[0] === "api" && args.some((a) => a.includes("/issues?labels=ops-alert&state=open"))) {
      const list = open.map((o) => ({ number: o.number, user: { login: restLogin((o.author ?? view.author ?? BOT).login) }, body: view.body, title: o.title ?? "" }));
      if (created) list.push({ number: 7, user: { login: "github-actions[bot]" }, body: "", title: "" });
      return JSON.stringify([list]);
    }
    if (args[0] === "api") {
      // REST comments, one page; the bot's REST login differs from its GraphQL login.
      const rest = (view.comments ?? []).map((c) => ({ user: { login: restLogin(c.author.login) }, body: c.body }));
      return JSON.stringify([rest]);
    }
    if (cmd === "issue create" && createFails && args.includes("--assignee")) {
      if (createdAnyway) created = true;
      throw execError(args, createFails);
    }
    if (cmd === "issue create") return "https://github.example/issues/7\n";
    return "";
  };
  gh.calls = calls;
  return gh;
}
const marker = (state) => `text\n<!-- ops-watch ${JSON.stringify(state)} -->`;
const bot = (body) => ({ author: BOT, body });
const human = (body) => ({ author: { login: "someone" }, body });
const alertCodes = (...codes) => codes.map((code) => ({ code, level: CODES[code] }));

describe("syncIssue", () => {
  it("opens one labelled issue, assigned to Alief, when an alert appears", async () => {
    const gh = fakeGh();
    assert.equal(await syncIssue({ quick: alertCodes("retention_failed"), daily: [], mode: "quick", gh, now: NOW }), "opened");
    assert.deepEqual(gh.calls[1], ["label", "create", "ops-alert", "--force", "--color", "B60205", "--description", "ops-watch alert (backend/ci/ops-watch.mjs)"]);
    const create = gh.calls.find((a) => a[1] === "create" && a[0] === "issue");
    assert.ok(create.includes("--assignee") && create.includes("aliefauzan"));
    assert.ok(create.includes("--label") && create.includes("ops-alert"));
    const body = create[create.indexOf("--body") + 1];
    assert.match(body, /retention_failed/);
    assert.match(body, /"alerts":\["retention_failed"\]/);
  });

  it("warn codes alone open nothing", async () => {
    const gh = fakeGh();
    assert.equal(await syncIssue({ quick: alertCodes("db_size_high", "blocklist_queue"), daily: [], mode: "quick", gh, now: NOW }), "none");
    assert.ok(!gh.calls.some((a) => a[1] === "create"));
  });

  it("stays silent while the set of alert codes does not change", async () => {
    const gh = fakeGh({ open: [{ number: 7 }], view: { author: BOT, body: marker({ alerts: ["retention_failed"], daily: [], green: 0 }), comments: [] } });
    assert.equal(await syncIssue({ quick: alertCodes("retention_failed"), daily: [], mode: "quick", gh, now: NOW }), "unchanged");
    assert.ok(!gh.calls.some((a) => a[1] === "comment" || a[1] === "close"));
  });

  it("comments when the set changes (state from the last comment, not the body)", async () => {
    const gh = fakeGh({
      open: [{ number: 7 }],
      view: { author: BOT, body: marker({ alerts: ["retention_failed"], daily: [], green: 0 }), comments: [human("human note"), bot(marker({ alerts: ["healthz_down"], daily: [], green: 0 }))] },
    });
    assert.equal(await syncIssue({ quick: alertCodes("healthz_down", "retention_failed"), daily: [], mode: "quick", gh, now: NOW }), "updated");
    const c = gh.calls.find((a) => a[1] === "comment");
    assert.equal(c[2], "7");
    assert.match(c[c.indexOf("--body") + 1], /"alerts":\["healthz_down","retention_failed"\]/);
  });

  it("closes after 2 green runs in a row", async () => {
    const first = fakeGh({ open: [{ number: 7 }], view: { author: BOT, body: marker({ alerts: ["retention_failed"], daily: [], green: 0 }), comments: [] } });
    assert.equal(await syncIssue({ quick: [], daily: [], mode: "quick", gh: first, now: NOW }), "green");
    const c = first.calls.find((a) => a[1] === "comment");
    assert.match(c[c.indexOf("--body") + 1], /"green":1/);

    const second = fakeGh({ open: [{ number: 7 }], view: { author: BOT, body: "", comments: [bot(c[c.indexOf("--body") + 1])] } });
    assert.equal(await syncIssue({ quick: [], daily: [], mode: "quick", gh: second, now: NOW }), "closed");
    assert.ok(second.calls.some((a) => a[0] === "issue" && a[1] === "close" && a[2] === "7"));
  });

  it("an alert after one green run resets the count", async () => {
    const gh = fakeGh({ open: [{ number: 7 }], view: { author: BOT, body: marker({ alerts: [], daily: [], green: 1 }), comments: [] } });
    assert.equal(await syncIssue({ quick: alertCodes("retention_failed"), daily: [], mode: "quick", gh, now: NOW }), "updated");
  });

  it("quick runs keep the daily run's alert codes until the next daily run", async () => {
    const state = marker({ alerts: ["worker_errors"], daily: ["worker_errors"], green: 0 });
    const quick = fakeGh({ open: [{ number: 7 }], view: { author: BOT, body: state, comments: [] } });
    assert.equal(await syncIssue({ quick: [], daily: [], mode: "quick", gh: quick, now: NOW }), "unchanged");
    const daily = fakeGh({ open: [{ number: 7 }], view: { author: BOT, body: state, comments: [] } });
    assert.equal(await syncIssue({ quick: [], daily: [], mode: "daily", gh: daily, now: NOW }), "green");
  });

  it("ignores markers written by anyone but the workflow (public repo)", async () => {
    const gh = fakeGh({
      open: [{ number: 7 }],
      view: { author: BOT, body: marker({ alerts: ["retention_failed"], daily: [], green: 0 }), comments: [human(marker({ alerts: [], daily: [], green: 1 }))] },
    });
    // The forged "green: 1" would close the issue on this green run; the real state says green 0.
    assert.equal(await syncIssue({ quick: [], daily: [], mode: "quick", gh, now: NOW }), "green");
    assert.ok(!gh.calls.some((a) => a[1] === "close"));
  });

  it("only trusts issues the workflow opened, read from REST (not the search index, PR #340 review 2)", async () => {
    const gh = fakeGh({ open: [{ number: 3, author: { login: "someone" } }] });
    assert.equal(await syncIssue({ quick: alertCodes("retention_failed"), daily: [], mode: "quick", gh, now: NOW }), "opened");
    assert.deepEqual(gh.calls[0], ["api", "--paginate", "--slurp", "repos/{owner}/{repo}/issues?labels=ops-alert&state=open&per_page=100"]);
    assert.ok(!gh.calls.some((a) => a[0] === "issue" && a[1] === "list"));
  });

  it("finds the bot's issue under its REST login github-actions[bot]", async () => {
    const gh = fakeGh({ open: [{ number: 7 }], view: { author: BOT, body: marker({ alerts: ["retention_failed"], daily: [], green: 0 }), comments: [] } });
    assert.equal(await syncIssue({ quick: alertCodes("retention_failed"), daily: [], mode: "quick", gh, now: NOW }), "unchanged");
    assert.ok(!gh.calls.some((a) => a[1] === "create"));
  });

  it("still opens the issue when the assignee cannot be assigned", async () => {
    const gh = fakeGh({ createFails: "could not assign user: 'aliefauzan' not found\n" });
    assert.equal(await syncIssue({ quick: alertCodes("retention_failed"), daily: [], mode: "quick", gh, now: NOW }), "opened");
    const creates = gh.calls.filter((a) => a[0] === "issue" && a[1] === "create");
    assert.equal(creates.length, 2);
    assert.ok(!creates[1].includes("--assignee"));
  });

  it("any other create error is not swallowed, although err.message contains --assignee (PR #340 review 1)", async () => {
    const gh = fakeGh({ createFails: "HTTP 502: Bad Gateway (https://api.github.com/graphql)\n" });
    await assert.rejects(syncIssue({ quick: alertCodes("retention_failed"), daily: [], mode: "quick", gh, now: NOW }), (err) => /--assignee/.test(err.message) && /502/.test(err.stderr));
    assert.equal(gh.calls.filter((a) => a[0] === "issue" && a[1] === "create").length, 1);
  });

  it("a create that failed after GitHub made the issue opens no second one", async () => {
    const gh = fakeGh({ createFails: "could not assign user: timeout\n", createdAnyway: true });
    assert.equal(await syncIssue({ quick: alertCodes("retention_failed"), daily: [], mode: "quick", gh, now: NOW }), "opened");
    assert.equal(gh.calls.filter((a) => a[0] === "issue" && a[1] === "create").length, 1);
  });

  it("the oldest open workflow issue wins when there are two", async () => {
    const gh = fakeGh({ open: [{ number: 9 }, { number: 7 }] });
    await syncIssue({ quick: [], daily: [], mode: "quick", gh, now: NOW });
    assert.ok(gh.calls.some((a) => a[0] === "api" && a.includes("repos/{owner}/{repo}/issues/7/comments?per_page=100")));
  });

  it("edits the title before writing the new marker (PR #340 review 8)", async () => {
    const gh = fakeGh({ open: [{ number: 7 }], view: { author: BOT, body: marker({ alerts: ["retention_failed"], daily: [], green: 0 }), comments: [] } });
    assert.equal(await syncIssue({ quick: alertCodes("healthz_down", "retention_failed"), daily: [], mode: "quick", gh, now: NOW }), "updated");
    const edit = gh.calls.findIndex((a) => a[1] === "edit");
    const comment = gh.calls.findIndex((a) => a[1] === "comment");
    assert.ok(edit >= 0 && edit < comment);
    assert.ok(gh.calls[edit].includes("ops-alert: healthz_down, retention_failed"));
  });

  it("a failed title edit is fixed by the next run, which still sees the old marker", async () => {
    const view = { author: BOT, body: marker({ alerts: ["retention_failed"], daily: [], green: 0 }), comments: [] };
    const failing = fakeGh({ open: [{ number: 7, title: "ops-alert: retention_failed" }], view });
    const gh = async (args) => {
      if (args[1] === "edit") throw new Error("HTTP 502");
      return failing(args);
    };
    await assert.rejects(syncIssue({ quick: alertCodes("healthz_down", "retention_failed"), daily: [], mode: "quick", gh, now: NOW }));
    assert.ok(!failing.calls.some((a) => a[1] === "comment"));
    // Next run: same marker, so it updates again (edit + comment).
    const again = fakeGh({ open: [{ number: 7, title: "ops-alert: retention_failed" }], view });
    assert.equal(await syncIssue({ quick: alertCodes("healthz_down", "retention_failed"), daily: [], mode: "quick", gh: again, now: NOW }), "updated");
  });

  it("an unchanged run fixes a title that does not match the marker", async () => {
    const view = { author: BOT, body: marker({ alerts: ["retention_failed"], daily: [], green: 0 }), comments: [] };
    const stale = fakeGh({ open: [{ number: 7, title: "ops-alert: healthz_down" }], view });
    assert.equal(await syncIssue({ quick: alertCodes("retention_failed"), daily: [], mode: "quick", gh: stale, now: NOW }), "unchanged");
    assert.ok(stale.calls.some((a) => a[1] === "edit" && a.includes("ops-alert: retention_failed")));
    const fine = fakeGh({ open: [{ number: 7, title: "ops-alert: retention_failed" }], view });
    await syncIssue({ quick: alertCodes("retention_failed"), daily: [], mode: "quick", gh: fine, now: NOW });
    assert.ok(!fine.calls.some((a) => a[1] === "edit"));
  });

  it("a blind run with no open issue does nothing", async () => {
    const gh = fakeGh();
    assert.equal(await syncIssue({ quick: [{ code: "ops_status_limited", level: "warn" }], daily: [], mode: "quick", gh, now: NOW }), "none");
  });

  it("a blind run (429, no analytics) is not green and never closes", async () => {
    const view = { author: BOT, body: marker({ alerts: [], daily: [], green: 1 }), comments: [] };
    const gh = fakeGh({ open: [{ number: 7 }], view });
    assert.equal(await syncIssue({ quick: [{ code: "ops_status_limited", level: "warn" }], daily: [], mode: "quick", gh, now: NOW }), "blind");
    assert.ok(!gh.calls.some((a) => a[1] === "close" || a[1] === "comment"));
  });

  it("a daily run without analytics replaces the old daily codes with cf_analytics_unavailable (PR #340 review 3 + 4)", async () => {
    const view = { author: BOT, body: marker({ alerts: ["worker_errors"], daily: ["worker_errors"], green: 0 }), comments: [] };
    const gh = fakeGh({ open: [{ number: 7 }], view });
    assert.equal(await syncIssue({ quick: [], daily: alertCodes("cf_analytics_unavailable"), mode: "daily", gh, now: NOW }), "updated");
    const c = gh.calls.find((a) => a[1] === "comment");
    assert.match(c[c.indexOf("--body") + 1], /"alerts":\["cf_analytics_unavailable"\],"daily":\["cf_analytics_unavailable"\]/);
    assert.ok(gh.calls.some((a) => a[1] === "edit" && a.includes("ops-alert: cf_analytics_unavailable")));
  });

  it("an expired Cloudflare token opens an issue on its own", async () => {
    const gh = fakeGh();
    assert.equal(await syncIssue({ quick: [], daily: alertCodes("cf_analytics_unavailable"), mode: "daily", gh, now: NOW }), "opened");
  });

  it("a 429 run keeps the last quick codes but not stale daily ones", async () => {
    const view = { author: BOT, body: marker({ alerts: ["retention_failed", "worker_errors"], daily: ["worker_errors"], green: 0 }), comments: [] };
    const gh = fakeGh({ open: [{ number: 7 }], view });
    // Daily run: /ops/status said 429 (blind for quick codes), analytics are clean now.
    assert.equal(await syncIssue({ quick: [{ code: "ops_status_limited", level: "warn" }], daily: [], mode: "daily", gh, now: NOW }), "updated");
    const c = gh.calls.find((a) => a[1] === "comment");
    assert.match(c[c.indexOf("--body") + 1], /"alerts":\["retention_failed"\],"daily":\[\]/);
  });

  it("a quick run re-checks /healthz/db and drops healthz_db_failed once it passes (PR #340 review 5)", async () => {
    const view = { author: BOT, body: marker({ alerts: ["healthz_db_failed"], daily: ["healthz_db_failed"], green: 0 }), comments: [] };
    let asked = 0;
    const ok = async () => (asked++, true);
    const gh = fakeGh({ open: [{ number: 7 }], view });
    assert.equal(await syncIssue({ quick: [], daily: [], mode: "quick", gh, now: NOW, recheckDb: ok }), "green");
    assert.equal(asked, 1);
    const c = gh.calls.find((a) => a[1] === "comment");
    assert.match(c[c.indexOf("--body") + 1], /"daily":\[\],"green":1/);

    const still = fakeGh({ open: [{ number: 7 }], view });
    assert.equal(await syncIssue({ quick: [], daily: [], mode: "quick", gh: still, now: NOW, recheckDb: async () => false }), "unchanged");

    // Analytics codes are not re-checked by quick runs.
    const wview = { author: BOT, body: marker({ alerts: ["worker_errors"], daily: ["worker_errors"], green: 0 }), comments: [] };
    let wasked = 0;
    await syncIssue({ quick: [], daily: [], mode: "quick", gh: fakeGh({ open: [{ number: 7 }], view: wview }), now: NOW, recheckDb: async () => (wasked++, true) });
    assert.equal(wasked, 0);
  });

  it("dropping a code comments at most once an hour; a new code comments at once", async () => {
    const recent = new Date(NOW.getTime() - 20 * 60_000).toISOString();
    const view = { author: BOT, body: marker({ alerts: ["healthz_down", "retention_failed"], daily: [], green: 0, at: recent }), comments: [] };
    assert.equal(await syncIssue({ quick: alertCodes("retention_failed"), daily: [], mode: "quick", gh: fakeGh({ open: [{ number: 7 }], view }), now: NOW }), "unchanged");
    assert.equal(await syncIssue({ quick: alertCodes("retention_failed", "notifications_stale"), daily: [], mode: "quick", gh: fakeGh({ open: [{ number: 7 }], view }), now: NOW }), "updated");
    // A daily run that clears a daily code always writes, quiet hour or not.
    const dview = { author: BOT, body: marker({ alerts: ["retention_failed", "worker_errors"], daily: ["worker_errors"], green: 0, at: recent }), comments: [] };
    const dgh = fakeGh({ open: [{ number: 7 }], view: dview });
    assert.equal(await syncIssue({ quick: alertCodes("retention_failed"), daily: [], mode: "daily", gh: dgh, now: NOW }), "updated");
    assert.ok(dgh.calls.some((a) => a[1] === "edit" && a.includes("ops-alert: retention_failed")));
    const later = new Date(NOW.getTime() + 41 * 60_000);
    assert.equal(await syncIssue({ quick: alertCodes("retention_failed"), daily: [], mode: "quick", gh: fakeGh({ open: [{ number: 7 }], view }), now: later }), "updated");
  });

  it("ignores a broken marker", async () => {
    const gh = fakeGh({ open: [{ number: 7 }], view: { author: BOT, body: "<!-- ops-watch {nope -->", comments: [] } });
    assert.equal(await syncIssue({ quick: alertCodes("retention_failed"), daily: [], mode: "quick", gh, now: NOW }), "updated");
  });
});

describe("summary", () => {
  it("lists codes and levels only, plus the blocklist line", () => {
    const md = summary({ mode: "daily", codes: alertCodes("blocklist_queue", "retention_failed"), now: NOW });
    assert.match(md, /\| `retention_failed` \| alert \|/);
    assert.match(md, /Blocklist queue: waiting for review/);
    assert.match(summary({ mode: "quick", codes: [], now: NOW }), /All checks green/);
    assert.match(summary({ mode: "daily", codes: alertCodes("ops_status_unreachable"), now: NOW }), /Blocklist queue: unknown/);
  });
});

describe("main", () => {
  const env = { OPS_STATUS_TOKEN: TOKEN, CF_ANALYTICS_TOKEN: CF_TOKEN, CLOUDFLARE_ACCOUNT_ID: ACCOUNT, OPS_API_URL: BASE };

  it("prints codes only: no numbers from the response, no URL, no token", async () => {
    const lines = [];
    const body = { ok: false, failing: [{ code: "db_size_high", level: "alert" }], dbBytes: 471859200, blocklistQueue: 987654321 };
    const f = fakeFetch({ "/healthz": json(200, {}), "/ops/status": json(200, body) });
    await main({ argv: ["--quick"], env, fetchImpl: f, gh: fakeGh(), sleep: noSleep, log: (l) => lines.push(l), now: NOW });
    const out = lines.join("\n");
    assert.match(out, /alert db_size_high/);
    assert.match(out, /issue: opened/);
    for (const leak of [TOKEN, "https://", "471859200", "987654321", "example.workers.dev"]) assert.ok(!out.includes(leak), leak);
  });

  it("--daily end to end: keep-alive, analytics, one issue", async () => {
    const f = fakeFetch({
      "/healthz": json(200, {}),
      "/ops/status": okStatus,
      "/healthz/db": json(200, {}),
      "/client/v4/graphql": (init) => {
        const d = analytics({ workers: [w("shoo-api", "exceededCpu", 2, 2), w("shoo-api", "success", 100)] });
        return json(200, { data: JSON.parse(init.body).query.includes("workersInvocationsAdaptive") ? d.workers : d.r2 });
      },
    });
    const r = await main({ argv: ["--daily"], env, fetchImpl: f, gh: fakeGh(), sleep: noSleep, log: () => {}, now: NOW });
    assert.deepEqual(codesOf(r.codes), ["worker_exceeded_cpu", "worker_errors"]);
    assert.equal(r.action, "opened");
  });

  it("simulate adds a known code without touching the backend's answer", async () => {
    const lines = [];
    const f = fakeFetch({ "/healthz": json(200, {}), "/ops/status": okStatus });
    const r = await main({ argv: ["--quick"], env: { ...env, OPS_SIMULATE: "retention_failed" }, fetchImpl: f, gh: fakeGh(), sleep: noSleep, log: (l) => lines.push(l), now: NOW });
    assert.deepEqual(codesOf(r.codes), ["retention_failed"]);
    assert.equal(r.action, "opened");
  });

  it("OPS_DRY_RUN=1 never calls gh", async () => {
    const gh = fakeGh();
    const f = fakeFetch({ "/healthz": json(200, {}), "/ops/status": json(500, {}) });
    const r = await main({ argv: ["--quick"], env: { ...env, OPS_DRY_RUN: "1" }, fetchImpl: f, gh, sleep: noSleep, log: () => {}, now: NOW });
    assert.equal(r.action, "dry-run");
    assert.equal(gh.calls.length, 0);
  });

  it("mode comes from the flag or OPS_MODE, anything else is an error", async () => {
    const f = fakeFetch({ "/healthz": json(200, {}), "/ops/status": okStatus });
    const r = await main({ argv: [], env: { ...env, OPS_MODE: "quick", OPS_DRY_RUN: "1" }, fetchImpl: f, gh: fakeGh(), sleep: noSleep, log: () => {}, now: NOW });
    assert.equal(r.mode, "quick");
    await assert.rejects(main({ argv: [], env: { ...env, OPS_MODE: "weekly" }, fetchImpl: f, gh: fakeGh(), sleep: noSleep, log: () => {}, now: NOW }), /mode/);
  });

  it("refuses an OPS_API_URL that is not https://host", async () => {
    for (const bad of ["http://a.b.workers.dev", "https://a.b.workers.dev/path", "https://a.b.workers.dev?q=1", "https://a.b.workers.dev:8443", "https://localhost", "https://1.2.3.4", "https://evil.example.com", "file:///etc"]) {
      await assert.rejects(main({ argv: ["--quick"], env: { ...env, OPS_API_URL: bad }, fetchImpl: fakeFetch({}), gh: fakeGh(), sleep: noSleep, log: () => {}, now: NOW }), /OPS_API_URL/);
    }
  });

  it("writes the job summary when GITHUB_STEP_SUMMARY is set", async () => {
    const written = [];
    const f = fakeFetch({ "/healthz": json(200, {}), "/ops/status": okStatus });
    await main({ argv: ["--quick"], env: { ...env, OPS_DRY_RUN: "1", GITHUB_STEP_SUMMARY: "/tmp/x" }, fetchImpl: f, gh: fakeGh(), sleep: noSleep, log: () => {}, now: NOW, appendSummary: (p, t) => written.push([p, t]) });
    assert.equal(written.length, 1);
    assert.match(written[0][1], /All checks green/);
  });
});
