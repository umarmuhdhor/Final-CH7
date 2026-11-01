// Figma parity QA, test 2b/2c: joins what the live visit saw into img/figma-parity/live/live-results.json
// for figma-parity-report.mjs.
//   live/visited.tsv        pages the Protected Safari opened (live-visit.sh)
//   live/observations.json  { "<id>": "what the Safari shot shows" }, written by hand after looking at each shot
//   corpus-results.json     test 2a score per sample
//   local Supabase          scans and push_log rows (docker container supabase_db_shoo)
//
//   node plan/alief/qa/live-results.mjs [folder] [offline results] [since] [until]
//   Test 3b (ai/test-layer2 links): ... live-l2 layer2-dataset-results.json 2026-11-01T14:09:00Z
//   Test 2b (2026-11-01 run): ... live corpus-results.json 2026-11-01T00:00:00Z 2026-11-01T14:09:00Z
//   `since` / `until` keep only the scans and pushes of that run, so another run's rows don't count.
import { readFileSync, writeFileSync, existsSync, readdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const dir = join(dirname(fileURLToPath(import.meta.url)), "img/figma-parity");
const [folder = "live", offlineFile = "corpus-results.json", since = "1970-01-01T00:00:00Z", until = "2999-01-01T00:00:00Z"] = process.argv.slice(2);
const live = join(dir, folder);
const [sinceIso, untilIso] = [since, until].map((t) => new Date(t).toISOString()); // throws on anything that is not a date, so nothing else reaches the SQL
const visited = readFileSync(join(live, "visited.tsv"), "utf8").trim().split("\n").map((l) => l.split("\t"));
const seen = existsSync(join(live, "observations.json")) ? JSON.parse(readFileSync(join(live, "observations.json"), "utf8")) : {};
const offline = Object.fromEntries(JSON.parse(readFileSync(join(dir, offlineFile), "utf8")).results.map((r) => [r.id, r]));

const sql = (q) =>
    JSON.parse(execFileSync("docker", ["exec", "supabase_db_shoo", "psql", "-U", "postgres", "-At", "-c", `select coalesce(json_agg(t), '[]') from (${q}) t`]).toString());
// Seeded rows (dev_mom, dev_dad) are not part of this run.
const scans = sql(`select s.id, s.domain, s.url, s.score, s.status, s.signals, s.created_at from scans s join devices d on d.id = s.owner_id where d.name = 'Maria' and d.apns_token is not null and s.created_at >= '${sinceIso}' and s.created_at < '${untilIso}'`);
const pushes = sql(`select p.scan_id, p.result, p.created_at from push_log p join devices d on d.id = p.to_device_id where d.name = 'Adhella' and d.apns_token is not null and p.created_at >= '${sinceIso}' and p.created_at < '${untilIso}'`);

const host = (u) => new URL(u).hostname;
const rows = visited.map(([id, label, url]) => {
    const scan = scans.find((s) => host(s.url ?? `https://${s.domain}`) === host(url) || s.domain === host(url));
    const push = scan && pushes.find((p) => p.scan_id === scan.id);
    return {
        id,
        label,
        offline: offline[id]?.score ?? "—",
        live: seen[id] ?? "—",
        scan: scan ? `${scan.score} ${scan.status}` : "none",
        push: push ? push.result : scan ? "none" : "—",
    };
});

const flagged = rows.filter((r) => r.scan !== "none");
const summary =
    `${rows.length} pages opened (${rows.filter((r) => r.label === "legit").length} legit, ${rows.filter((r) => r.label === "scam").length} scam). ` +
    `${flagged.length} reached the server as a scan (score ≥ 30), ${pushes.length} Guardian push attempt(s) in push_log.`;
// The scam pages, one legit page, then what each app showed afterwards (taken by hand, see the report).
// Other folders: every guardian-* / protected-* shot, named after its file.
const appShots = folder === "live" ? [] : readdirSync(live).filter((f) => /^(guardian|protected)-.*\.jpg$/.test(f)).sort()
    .map((f) => f.replace(/\.jpg$/, ""))
    .map((f) => [f, f.replace(/^(guardian|protected)-\d+-/, (_, who) => (who === "guardian" ? "Guardian: " : "Protected: ")).replace(/-/g, " ")]);
const shots = [
    ...rows.filter((r) => r.label === "scam" || r.scan !== "none").map((r) => [`safari-${r.id}`, `Safari · ${r.id}`]),
    ...appShots,
    ["safari-bank-login-klikbca", "Safari · bank-login-klikbca"],
    ["guardian-activity", "Guardian Activity, Family mode off"],
    ["guardian-activity-family", "Guardian Activity, Family mode on"],
    ["guardian-home-family", "Guardian Home"],
    ["guardian-detail-regnows", "Guardian Detail"],
    ["guardian-push", "Guardian push (simctl)"],
    ["protected-activity", "Protected Activity"],
    ["protected-home", "Protected Home"],
]
    .filter(([file]) => existsSync(join(live, `${file}.jpg`)))
    .map(([file, caption]) => ({ caption, path: `img/figma-parity/${folder}/${file}.jpg` }));
writeFileSync(join(live, "live-results.json"), JSON.stringify({ summary, rows, scans, pushes, shots }, null, 2));
console.log(summary);
