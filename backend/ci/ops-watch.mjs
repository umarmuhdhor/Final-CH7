#!/usr/bin/env node
// Fase 21b (TODO B9): scheduled ops check, run by .github/workflows/ops-watch.yml.
//   --quick (every 15 min): /healthz (3 tries, 20 s apart), then GET /ops/status with OPS_STATUS_TOKEN.
//   --daily (once a day):   the quick checks + /healthz/db (Supabase keep-alive) + Cloudflare GraphQL
//                           analytics (Worker errors/CPU/requests, R2 class A/B, R2 storage).
// Alert codes open, update and close one GitHub issue labelled `ops-alert` (gh CLI of the runner).
// The repository is public: stdout, the job summary and the issue carry codes and levels only, never
// numbers, URLs, tokens or response bodies (fase 21 K6). Runbook: backend/README.md "Monitoring and alerts".
//
// Usage: node backend/ci/ops-watch.mjs --quick|--daily     (or OPS_MODE=quick|daily)
// Env:   OPS_STATUS_TOKEN, CF_ANALYTICS_TOKEN, CLOUDFLARE_ACCOUNT_ID, OPS_API_URL (optional),
//        OPS_SIMULATE (optional, comma-separated known codes: alert test), OPS_DRY_RUN=1 (no issue),
//        GITHUB_STEP_SUMMARY (set by Actions), GH_TOKEN + GH_REPO (for gh).
// Tests: node --test 'backend/ci/*.test.mjs'
import { execFile } from "node:child_process";
import { appendFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { promisify } from "node:util";

export const DEFAULT_API_URL = "https://shoo-api.afindo-mi01.workers.dev";
const GRAPHQL_URL = "https://api.cloudflare.com/client/v4/graphql";
const SCRIPT = "shoo-api";
const ASSIGNEE = "aliefauzan";
const LABEL = "ops-alert";
const REQUEST_TIMEOUT_MS = 15_000;
const HEALTHZ_ATTEMPTS = 3;
const HEALTHZ_GAP_MS = 20_000;
const GREEN_RUNS_TO_CLOSE = 2;
// Comments only drop codes at most once an hour: a flapping check must not mail the assignee every 15 min.
const QUIET_MS = 60 * 60_000;
// Codes that mean "the monitor could not see", not "healthy": they never count as a green run.
const BLIND = new Set(["ops_status_limited", "cf_analytics_unavailable"]);
// Comment authors whose ops-watch marker is trusted (the workflow's GITHUB_TOKEN). Anyone can comment
// on a public repo; a forged marker must not close or silence the issue.
const TRUSTED_AUTHORS = new Set(["github-actions", "github-actions[bot]", "app/github-actions"]);

/** Every code this script can print, with its level (backend codes: services/opsStatus.ts). */
export const CODES = Object.freeze({
  // GET /ops/status (fase 21a/21c). Their level comes from the response; this is the fallback.
  retention_stale: "alert",
  retention_failed: "alert",
  retention_overdue: "alert",
  retention_backlog: "warn",
  tombstones_stuck: "warn",
  notifications_stale: "alert",
  db_size_high: "warn",
  blocklist_queue: "warn",
  replica_full: "alert",
  replica_reserve: "warn",
  replica_family_cap: "warn",
  replica_unknown: "warn",
  // This script (fase 21 K3, "Dicek oleh workflow").
  healthz_down: "alert",
  ops_status_unreachable: "alert",
  ops_status_limited: "warn",
  healthz_db_failed: "alert",
  worker_exceeded_cpu: "alert",
  worker_errors: "alert",
  worker_requests_high: "warn",
  r2_class_a_high: "warn",
  r2_class_b_high: "warn",
  r2_storage_high: "warn",
  cf_analytics_unavailable: "warn",
});

/** Fase 21 K3 limits (Free plan: 100k Worker requests/day, R2 1M class A + 10M class B per month). */
export const LIMITS = Object.freeze({
  workerErrorRatio: 0.01, // alert when errors/requests is above this ...
  workerErrorMinRequests: 50, // ... with at least this many requests in 24 h
  workerRequestsDay: 80_000,
  r2ClassAMonth: 500_000,
  r2ClassBMonth: 5_000_000,
  r2StorageBytes: 5_000_000_000,
});

// R2 pricing (developers.cloudflare.com/r2/pricing/). Free operations are not counted; an action type
// that is in neither list counts as class A, the more expensive guess.
const R2_CLASS_B = new Set([
  "HeadBucket", "HeadObject", "GetObject", "UsageSummary", "GetBucketEncryption", "GetBucketLocation",
  "GetBucketCors", "GetBucketLifecycleConfiguration",
]);
const R2_FREE = new Set(["DeleteObject", "DeleteBucket", "AbortMultipartUpload"]);

const CODE_RE = /^[a-z][a-z0-9_]{0,39}$/;
const LEVELS = new Set(["warn", "alert"]);
const code = (name) => ({ code: name, level: CODES[name] });

/** fetch with a timeout; never throws. `json` is undefined when the body is not JSON. */
async function request(fetchImpl, url, init = {}) {
  try {
    // No redirects: a 3xx is a failure, and the Bearer header never follows one.
    const res = await fetchImpl(url, { ...init, redirect: "manual", signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS) });
    let json;
    try {
      json = await res.json();
    } catch {
      json = undefined;
    }
    return { status: res.status, json };
  } catch {
    return { status: 0, json: undefined };
  }
}

/** Uptime + backend self-check. Returns `{code, level}[]`. */
export async function checkQuick({ base, token, fetchImpl, sleep }) {
  const out = [];
  let up = false;
  for (let i = 0; i < HEALTHZ_ATTEMPTS && !up; i++) {
    if (i > 0) await sleep(HEALTHZ_GAP_MS);
    up = (await request(fetchImpl, `${base}/healthz`)).status === 200;
  }
  if (!up) out.push(code("healthz_down"));

  if (!token) {
    out.push(code("ops_status_unreachable"));
    return out;
  }
  const r = await request(fetchImpl, `${base}/ops/status`, { headers: { authorization: `Bearer ${token}` } });
  if (r.status === 429) {
    // Only token holders can use up the 30/h; it says nothing about the backend (fase 21a review LOW 4).
    out.push(code("ops_status_limited"));
  } else if (r.status !== 200 || !r.json || !Array.isArray(r.json.failing)) {
    out.push(code("ops_status_unreachable"));
  } else {
    for (const f of r.json.failing) {
      // Strict shape: whatever lands here is written to a public issue.
      if (f && typeof f.code === "string" && CODE_RE.test(f.code) && LEVELS.has(f.level)) out.push({ code: f.code, level: f.level });
    }
  }
  return out;
}

/** GraphQL documents. R2 is grouped by action type only: never the object key dimension (keys carry device ids, P6). */
export function queries() {
  return {
    workers: `query OpsWorkers($account: String!, $dayStart: Time!, $end: Time!) {
  viewer { accounts(filter: { accountTag: $account }) {
    workersInvocationsAdaptive(limit: 1000, filter: { datetime_geq: $dayStart, datetime_lt: $end }) {
      sum { requests errors }
      dimensions { scriptName status }
    }
  } }
}`,
    r2: `query OpsR2($account: String!, $monthStart: Time!, $dayStart: Time!, $end: Time!) {
  viewer { accounts(filter: { accountTag: $account }) {
    ops: r2OperationsAdaptiveGroups(limit: 1000, filter: { datetime_geq: $monthStart, datetime_lt: $end }) {
      sum { requests }
      dimensions { actionType }
    }
    storage: r2StorageAdaptiveGroups(limit: 1000, filter: { datetime_geq: $dayStart, datetime_lt: $end }) {
      max { payloadSize metadataSize }
      dimensions { bucketName }
    }
  } }
}`,
  };
}

const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
const account = (data) => data?.viewer?.accounts?.[0] ?? {};

/**
 * True when both answers have the expected shape. A wrong or unauthorised account id answers 200
 * with `accounts: []` and no error: without this check every count is 0 and the run looks green.
 * shoo-api always has rows (this run's own /healthz calls), so none means the data is not there.
 */
export function analyticsUsable({ workers, r2 }) {
  const w = workers?.viewer?.accounts;
  const r = r2?.viewer?.accounts;
  if (!Array.isArray(w) || w.length !== 1 || !Array.isArray(r) || r.length !== 1) return false;
  const rows = w[0].workersInvocationsAdaptive;
  if (!Array.isArray(rows) || !Array.isArray(r[0].ops) || !Array.isArray(r[0].storage)) return false;
  return rows.some((x) => x?.dimensions?.scriptName === SCRIPT);
}

/** K3 workflow checks from the two GraphQL answers (`data` of each). */
export function evaluateAnalytics({ workers, r2 }) {
  const out = [];
  const rows = account(workers).workersInvocationsAdaptive ?? [];
  let total = 0;
  let apiRequests = 0;
  let apiErrors = 0;
  let exceeded = 0;
  for (const r of rows) {
    const requests = num(r?.sum?.requests);
    total += requests;
    if (r?.dimensions?.scriptName !== SCRIPT) continue;
    apiRequests += requests;
    apiErrors += num(r?.sum?.errors);
    // "exceededResources", and the newer "exceededCpu" / "exceededMemory".
    if (String(r?.dimensions?.status ?? "").startsWith("exceeded")) exceeded += requests;
  }
  if (exceeded > 0) out.push(code("worker_exceeded_cpu"));
  if (apiRequests >= LIMITS.workerErrorMinRequests && apiErrors / apiRequests > LIMITS.workerErrorRatio) out.push(code("worker_errors"));
  if (total >= LIMITS.workerRequestsDay) out.push(code("worker_requests_high"));

  const r2a = account(r2);
  let classA = 0;
  let classB = 0;
  for (const g of r2a.ops ?? []) {
    const type = g?.dimensions?.actionType;
    if (R2_FREE.has(type)) continue;
    if (R2_CLASS_B.has(type)) classB += num(g?.sum?.requests);
    else classA += num(g?.sum?.requests);
  }
  if (classA >= LIMITS.r2ClassAMonth) out.push(code("r2_class_a_high"));
  if (classB >= LIMITS.r2ClassBMonth) out.push(code("r2_class_b_high"));
  const stored = (r2a.storage ?? []).reduce((s, g) => s + num(g?.max?.payloadSize) + num(g?.max?.metadataSize), 0);
  if (stored >= LIMITS.r2StorageBytes) out.push(code("r2_storage_high"));
  return out;
}

/** Keep-alive + Cloudflare analytics (once a day). Returns `{code, level}[]`. */
export async function checkDaily({ base, cfToken, accountId, fetchImpl, now }) {
  const out = [];
  // Writes ops_heartbeat('healthz'): the second, independent Supabase keep-alive (fase 21 K1).
  if ((await request(fetchImpl, `${base}/healthz/db`)).status !== 200) out.push(code("healthz_db_failed"));

  if (!cfToken || !/^[0-9a-f]{32}$/.test(accountId ?? "")) return [...out, code("cf_analytics_unavailable")];
  const end = now.toISOString();
  // 24 h minus a minute: the Workers dataset rejects ranges longer than a day.
  const dayStart = new Date(now.getTime() - 24 * 3600_000 + 60_000).toISOString();
  const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString();
  const q = queries();
  const ask = (query, variables) =>
    request(fetchImpl, GRAPHQL_URL, {
      method: "POST",
      headers: { authorization: `Bearer ${cfToken}`, "content-type": "application/json" },
      body: JSON.stringify({ query, variables }),
    });
  const [w, r] = await Promise.all([
    ask(q.workers, { account: accountId, dayStart, end }),
    ask(q.r2, { account: accountId, monthStart, dayStart, end }),
  ]);
  const good = (x) => x.status === 200 && x.json?.data && !(x.json.errors?.length > 0);
  if (!good(w) || !good(r)) return [...out, code("cf_analytics_unavailable")];
  const data = { workers: w.json.data, r2: r.json.data };
  if (!analyticsUsable(data)) return [...out, code("cf_analytics_unavailable")];
  return [...out, ...evaluateAnalytics(data)];
}

/** OPS_SIMULATE: known codes only (it ends up in a public issue). */
export function parseSimulate(raw) {
  return [...new Set((raw ?? "").split(",").map((s) => s.trim()))].filter((s) => Object.hasOwn(CODES, s)).map(code);
}

const MARKER_RE = /<!-- ops-watch (\{[^\n]*?\}) -->/;
const codeList = (v) => Array.isArray(v) && v.every((c) => typeof c === "string" && CODE_RE.test(c));

/** Last state written by the workflow itself: `texts` = issue body, then comments, oldest first; newest wins. */
function lastState(texts) {
  const trusted = texts.filter((t) => TRUSTED_AUTHORS.has(t?.login));
  for (const t of trusted.reverse()) {
    const m = MARKER_RE.exec(t.body ?? "");
    if (!m) continue;
    try {
      const s = JSON.parse(m[1]);
      const at = typeof s.at === "string" ? Date.parse(s.at) : NaN;
      if (codeList(s.alerts) && codeList(s.daily) && Number.isInteger(s.green) && s.green >= 0) return { ...s, at: Number.isNaN(at) ? 0 : at };
    } catch {
      // A broken marker is no state.
    }
  }
  return null;
}

const utc = (d) => `${d.toISOString().slice(0, 16).replace("T", " ")} UTC`;
const markerOf = (state) => `<!-- ops-watch ${JSON.stringify(state)} -->`;
const sameSet = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
const bullets = (codes) => codes.map((c) => `- \`${c}\``).join("\n");
const FOOTER =
  "Runbook: backend/README.md, section \"Monitoring and alerts\". Numbers are only in GET /ops/status " +
  "(token holders): this repository is public, so this issue carries codes only. It closes itself after " +
  `${GREEN_RUNS_TO_CLOSE} green runs in a row.`;

/**
 * Opens / updates / closes the one open `ops-alert` issue. Only `alert` codes count. Quick runs keep
 * the alert codes of the last daily run (they cannot see Cloudflare analytics); a daily run replaces
 * them. A run with a BLIND code changes nothing except to add new alert codes. Returns what it did:
 * opened | updated | unchanged | blind | green | closed | none.
 */
export async function syncIssue({ quick, daily, mode, gh, now }) {
  const alertsOf = (list) => [...new Set(list.filter((c) => c.level === "alert").map((c) => c.code))].sort();
  const union = (a, b) => [...new Set([...a, ...b])].sort();
  // Only issues the workflow opened: a labelled issue from someone else must not hide the real one.
  const listed = JSON.parse(await gh(["issue", "list", "--label", LABEL, "--state", "open", "--author", "app/github-actions", "--json", "number,author", "--limit", "20"]));
  const number = listed
    .filter((i) => TRUSTED_AUTHORS.has(i?.author?.login) && Number.isInteger(i.number))
    .map((i) => i.number)
    .sort((a, b) => a - b)[0];
  let prev = null;
  if (number) {
    const issue = JSON.parse(await gh(["issue", "view", String(number), "--json", "author,body"]));
    // Every page of comments (REST, oldest first): `issue view` may return only the first page.
    const pages = JSON.parse(await gh(["api", "--paginate", "--slurp", `repos/{owner}/{repo}/issues/${number}/comments?per_page=100`]));
    const comments = pages.flat().map((c) => ({ login: c?.user?.login, body: c?.body }));
    prev = lastState([{ login: issue?.author?.login, body: issue?.body }, ...comments]);
  }
  const blind = [...quick, ...daily].some((c) => BLIND.has(c.code));

  let dailyAlerts = mode === "daily" ? alertsOf(daily) : (prev?.daily ?? []);
  let alerts = union(alertsOf(quick), dailyAlerts);
  if (blind && number) {
    // Half-blind run: keep what was known, only add.
    dailyAlerts = union(prev?.daily ?? [], dailyAlerts);
    alerts = union(prev?.alerts ?? [], alerts);
    if (prev && prev.green === 0 && sameSet(prev.alerts, alerts) && sameSet(prev.daily, dailyAlerts)) return "blind";
  }

  if (alerts.length > 0) {
    const state = { alerts, daily: dailyAlerts, green: 0, at: now.toISOString() };
    if (!number) {
      await gh(["label", "create", LABEL, "--force", "--color", "B60205", "--description", "ops-watch alert (backend/ci/ops-watch.mjs)"]);
      const body = `ops-watch found alert codes at ${utc(now)} (${mode} run):\n\n${bullets(alerts)}\n\n${FOOTER}\n\n${markerOf(state)}`;
      const create = ["issue", "create", "--title", `ops-alert: ${alerts.join(", ")}`, "--label", LABEL, "--body", body];
      try {
        await gh([...create, "--assignee", ASSIGNEE]);
      } catch (err) {
        // Assignee no longer assignable: the alert still needs its issue. Any other error stays an error.
        if (!/assign/i.test(String(err?.message ?? "") + String(err?.stderr ?? ""))) throw err;
        await gh(create);
      }
      return "opened";
    }
    if (prev && prev.green === 0 && sameSet(prev.alerts, alerts) && sameSet(prev.daily, dailyAlerts)) return "unchanged";
    const added = alerts.some((c) => !(prev?.alerts ?? []).includes(c));
    // Quiet hour: only for codes of quick runs going away. A daily set always gets written, or the next
    // quick run would carry the stale daily codes again.
    if (prev && prev.green === 0 && !added && sameSet(prev.daily, dailyAlerts) && now.getTime() - prev.at < QUIET_MS) return "unchanged";
    const body = `Alert codes at ${utc(now)} (${mode} run):\n\n${bullets(alerts)}\n\n${markerOf(state)}`;
    await gh(["issue", "comment", String(number), "--body", body]);
    await gh(["issue", "edit", String(number), "--title", `ops-alert: ${alerts.join(", ")}`]);
    return "updated";
  }

  if (!number) return "none";
  if (blind) return "blind";
  const green = (prev?.green ?? 0) + 1;
  const state = { alerts: [], daily: dailyAlerts, green, at: now.toISOString() };
  if (green >= GREEN_RUNS_TO_CLOSE) {
    const body = `${green} green runs in a row (last at ${utc(now)}, ${mode} run): closing.\n\n${markerOf(state)}`;
    await gh(["issue", "close", String(number), "--comment", body]);
    return "closed";
  }
  const body = `Green run ${green} of ${GREEN_RUNS_TO_CLOSE} at ${utc(now)} (${mode} run).\n\n${markerOf(state)}`;
  await gh(["issue", "comment", String(number), "--body", body]);
  return "green";
}

/** Job summary (markdown): codes, levels and the time only. */
export function summary({ mode, codes, now }) {
  const lines = [`## ops-watch (${mode}) ${utc(now)}`, ""];
  if (codes.length === 0) lines.push("All checks green.");
  else lines.push("| Code | Level |", "|---|---|", ...codes.map((c) => `| \`${c.code}\` | ${c.level} |`));
  if (mode === "daily") {
    const seen = !codes.some((c) => c.code === "ops_status_unreachable" || c.code === "ops_status_limited");
    const queue = !seen ? "unknown (/ops/status did not answer)" : codes.some((c) => c.code === "blocklist_queue") ? "waiting for review (D9)" : "nothing older than 24 h";
    lines.push("", `Blocklist queue: ${queue}.`);
  }
  lines.push("", "Runbook: backend/README.md, section \"Monitoring and alerts\".", "");
  return lines.join("\n");
}

const execFileP = promisify(execFile);
const runGh = async (args) => (await execFileP("gh", args, { maxBuffer: 4 * 1024 * 1024 })).stdout;
const realSleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function main({
  argv = process.argv.slice(2),
  env = process.env,
  fetchImpl = fetch,
  gh = runGh,
  sleep = realSleep,
  log = console.log,
  now = new Date(),
  appendSummary = appendFileSync,
} = {}) {
  const flag = argv.find((a) => a === "--quick" || a === "--daily");
  const mode = flag ? flag.slice(2) : env.OPS_MODE;
  if (mode !== "quick" && mode !== "daily") throw new Error("ops-watch: mode must be --quick or --daily (or OPS_MODE)");
  const base = env.OPS_API_URL || DEFAULT_API_URL;
  // The ops token goes to this host: a Worker on workers.dev only, no path, no port.
  if (!/^https:\/\/[a-z0-9-]+\.[a-z0-9-]+\.workers\.dev$/i.test(base)) throw new Error("ops-watch: OPS_API_URL must be https://<name>.<account>.workers.dev");

  const quick = await checkQuick({ base, token: env.OPS_STATUS_TOKEN, fetchImpl, sleep });
  const daily = mode === "daily" ? await checkDaily({ base, cfToken: env.CF_ANALYTICS_TOKEN, accountId: env.CLOUDFLARE_ACCOUNT_ID, fetchImpl, now }) : [];
  const simulated = parseSimulate(env.OPS_SIMULATE);
  if (env.OPS_SIMULATE && simulated.length === 0) log("ops-watch: simulate ignored (no known code)");

  const seen = new Set();
  const codes = [...quick, ...daily, ...simulated].filter((c) => !seen.has(c.code) && seen.add(c.code));
  if (codes.length === 0) log(`ops-watch ${mode}: all green`);
  for (const c of codes) log(`ops-watch ${mode}: ${c.level} ${c.code}`);
  if (env.GITHUB_STEP_SUMMARY) appendSummary(env.GITHUB_STEP_SUMMARY, summary({ mode, codes, now }));

  const action = env.OPS_DRY_RUN === "1" ? "dry-run" : await syncIssue({ quick: [...quick, ...simulated], daily, mode, gh, now });
  log(`ops-watch ${mode}: issue: ${action}`);
  return { mode, codes, action };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((err) => {
    // Our own messages only: a fetch or gh error could carry a URL or a response.
    console.error(err instanceof Error && err.message.startsWith("ops-watch:") ? err.message : "ops-watch: failed (gh or runtime error)");
    process.exitCode = 1;
  });
}
