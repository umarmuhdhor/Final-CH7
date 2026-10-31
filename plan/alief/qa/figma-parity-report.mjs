// Builds plan/alief/qa/figma-parity-2026-10-31.md from the run's files:
//   figma-parity-map.json (frame -> app shot), figma-parity-notes.json (gap per frame),
//   img/figma-parity/{app,figma,live}/, corpus-results.json, corpus-dns.json, live/live-results.json.
//   node plan/alief/qa/figma-parity-report.mjs
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const read = (p) => JSON.parse(readFileSync(join(here, p), "utf8"));
const map = read("figma-parity-map.json");
const notes = read("figma-parity-notes.json");
const corpus = read("img/figma-parity/corpus-results.json");
const dns = read("img/figma-parity/corpus-dns.json");
const live = existsSync(join(here, "img/figma-parity/live/live-results.json")) ? read("img/figma-parity/live/live-results.json") : null;

const FIGMA = "https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=";
const img = (path, w = 160) => `<img src="${path}" width="${w}">`;
const app = (shot) => (shot && existsSync(join(here, `img/figma-parity/app/${shot}.jpg`)) ? img(`img/figma-parity/app/${shot}.jpg`) : "—");
const fig = (id) => img(`img/figma-parity/figma/${id.replace(":", "-")}.jpg`);
const badge = { match: "✅ match", minor: "🟡 minor", gap: "🟠 gap", missing: "🔴 missing", test: "⚪ not shot" };

const out = [];
const p = (s = "") => out.push(s);

// ---- counts
const rows = Object.entries(map).filter(([k]) => k !== "_note").flatMap(([sec, list]) => list.map((r) => [sec, ...r]));
const count = {};
for (const [, id] of rows) count[notes[id]?.[0] ?? "test"] = (count[notes[id]?.[0] ?? "test"] ?? 0) + 1;

p("# QA — Figma parity, iOS app (2026-10-31)");
p();
p("Every iOS frame marked **Ready for dev** on the Figma page *High Fidelity*, plus HOME and *AI vs Guardian — Eksplorasi* (not marked, shown as they are), next to the app as it is on `main` today. Safari extension and web frames are out of scope.");
p();
p("| | |\n|---|---|");
p("| Device | iPhone 17 simulator, iOS 26.3, Bahasa Indonesia, light, `TZ=Asia/Jakarta` (WIB) |");
p("| App | `main` @ 2720b13 + this branch's QA additions (no screen changed) |");
p("| Test 1 | `MockRepository` scenarios `figma`, `mixedVerdicts`, `heavy`, `edge`, `allSafe`, `allBlocked` (`Data/MockScenarios.swift`) |");
p("| Test 2a | Imelda's eval corpus (`ai/eval/data`, 108 samples, holdout included) through layers 1–4 on a local `shoo-ai` Worker → scenario `corpus` |");
p("| Test 2b/2c | Two paired simulators on a local stack built like prod; the Protected Safari opens every corpus URL that still resolves |");
p("| Figma | [High Fidelity](" + FIGMA + "18-2), exported at 1x through the TalkToFigma plugin |");
p();
p(`Result: **${rows.length} frames** — ${["match", "minor", "gap", "missing", "test"].map((k) => `${badge[k]} ${count[k] ?? 0}`).join(" · ")}.`);
p();
p("Figma frames are full height; the app shot is one screen (later screens of the same state are in `img/figma-parity/app/<shot>-2.jpg`, `-3.jpg`).");
p();

// ---- findings
p("## Findings");
p();
const sev = { missing: 0, gap: 1, minor: 2 };
const found = rows.filter(([, id]) => notes[id] && notes[id][0] in sev).sort((a, b) => sev[notes[a[1]][0]] - sev[notes[b[1]][0]]);
p("Bugs and gaps the run found outside the frame-by-frame view:");
p();
p("1. 🔴 **Emoji in a name shows as ⍰ boxes** (scenario `edge`, `Bayu 🧑‍💻`) on Guardian Home and Profile: the custom font has no emoji fallback for ZWJ sequences. `edge-home-guardian`, `edge-pf-guardian`.");
p("2. 🟠 **Code expired shows the generic error**: joining with the mock's `code_expired` code shows \"Ada yang salah. Coba lagi.\" (`on-connect-expired`), not Figma's \"Kode kadaluarsa…\" (205:1182).");
p("3. 🟡 **\"Notifikasi mati\" popup on every Home / Activity launch** in the mock run although `-UITestNotifications granted` is passed; the popup covers the hero in the Home shots.");
p("4. 🟡 **Gauge label for 30–49**: a 39% warning (`corpus-dt-real-lphone`) reads \"Risiko Tinggi\", the same as 72%.");
p("5. 🟡 **Counters** do not cap: Guardian Profile shows \"3.000 Situs diblokir\" in `heavy` (no \"999+\"); fits, but wider than Figma's tile.");
p("6. 🟠 **Live: Guardian sees nothing after pairing** until Family mode is switched on by hand on Home (`live/guardian-activity.jpg` vs `guardian-activity-family.jpg`). Figma's Guardian Home/Activity always show the family.");
p("7. 🟠 **Live: push cannot be tested on the local stack**: `wrangler dev` has no HTTP/2, APNs answers nothing (`push_log` `failed:network`). Prod path is the deployed Worker; a local relay or a cloud staging Worker is needed for an end-to-end push test.");
p("8. 🟡 **Live: same page twice = two scans** in Activity (`regnows-dfg.com` 22.40 and 22.41).");
p("9. 🟡 **Live: the extension banner is English** (\"46% · Be careful\") while the app is set to Bahasa Indonesia; the extension follows the system language (extension is out of scope for this report, noted for the lead).");
p("10. 🟡 **Live: Detail \"Salinan halaman\" stays grey** for the live scan (no page copy drawn) and the favicon circle is empty.");
p("11. ⚪ **Detector, 2a**: 4 legit pages ≥ 30 (target 0) and 20 scam pages < 30; 62 % of scams ≥ 50 (target 90 %). Details in Test 2a.");
p();
p("Per frame (most severe first):");
p();
p("| | Frame | Note |\n|---|---|---|");
for (const [, id, name] of found) p(`| ${badge[notes[id][0]]} | [${name}](${FIGMA}${id.replace(":", "-")}) | ${notes[id][1]} |`);
p();

// ---- frame tables
for (const [sec, list] of Object.entries(map)) {
    if (sec === "_note") continue;
    p(`## ${sec}`);
    p();
    p("| Frame | App now | Figma | Status | Note |\n|---|---|---|---|---|");
    for (const [id, name, shot] of list) {
        const [st, note] = notes[id] ?? ["test", ""];
        p(`| [${name}](${FIGMA}${id.replace(":", "-")})<br>\`${id}\` | ${app(shot)}<br>\`${shot ?? "—"}\` | ${fig(id)} | ${badge[st]} | ${note} |`);
    }
    p();
}

// ---- variants
p("## Test 1 — mock variants");
p();
p("Same screens with other data. Run: `TEST_RUNNER_QA_SCENARIO=<name> TEST_RUNNER_QA_SHOT_DIR=… xcodebuild test -only-testing:ShooAppUITests/FigmaParityUITests`.");
p();
const variants = {
    mixedVerdicts: "Every verdict state: blocked/warning × none / safe / not safe",
    heavy: "3 members, 60 scans over 30 days, counters past 999",
    edge: "20-character names, emoji, an 87-character domain, no title / favicon / screenshot, one signal",
    allSafe: "Every scan marked safe by the Guardian",
    allBlocked: "Only blocked scans",
    corpus: "Imelda's corpus with the detector's real scores and signals (41 scans ≥ 30)",
};
const shots = ["home-guardian", "home-protected", "act-guardian", "act-protected", "pf-guardian"];
for (const [name, what] of Object.entries(variants)) {
    p(`### \`${name}\` — ${what}`);
    p();
    const extra = name === "edge" ? ["dt-long", "dt-one-signal"] : name === "corpus" ? ["dt-top", "dt-real-bsi", "dt-real-lphone", "dt-false-positive"] : name === "heavy" ? ["dt-first"] : name === "allSafe" ? ["dt-safe"] : [];
    const list = [...shots, ...extra].filter((s) => existsSync(join(here, `img/figma-parity/app/${name}-${s}.jpg`)));
    p("| " + list.map((s) => `\`${s}\``).join(" | ") + " |");
    p("|" + list.map(() => "---").join("|") + "|");
    p("| " + list.map((s) => img(`img/figma-parity/app/${name}-${s}.jpg`, 140)).join(" | ") + " |");
    p();
}

// ---- corpus
const s = corpus.summary;
p("## Test 2a — Imelda's corpus through layers 1–4 (offline)");
p();
p("`node ai/eval/run.mjs --analyze-url http://127.0.0.1:8788 --json --show-holdout` against `wrangler dev` of `ai/` with the LLM key in `ai/.dev.vars` and the prebuilt public blocklist (190 000 domains, `ai/scripts/build-blocklist.mjs`) in local KV. `plan/alief/qa/corpus-to-scans.mjs` turns the rows into the `corpus` scenario. No live page was opened for this test.");
p();
p(`| | Samples | ≥ 30 (warning) | ≥ 50 | ≥ 80 (blocked) |\n|---|---|---|---|---|`);
p(`| Scam | ${s.counts.scam} | ${s.scam.atLeast30} | ${s.scam.atLeast50} | ${s.scam.atLeast80} |`);
p(`| Legit | ${s.counts.legit} | ${s.legit.atLeast30} | ${s.legit.atLeast50} | ${s.legit.atLeast80} |`);
p();
p(`Targets (docs/mandates/imelda.md): 0 legit ≥ 30 — **${s.legit.atLeast30} found**; ≥ 90 % scam ≥ 50 — **${Math.round((100 * s.scam.atLeast50) / s.counts.scam)} %**; ≥ 70 % scam ≥ 80 — **${Math.round((100 * s.scam.atLeast80) / s.counts.scam)} %**. \`/analyze\` p95 ${Math.round(s.timing.analyzeRemoteP95Ms)} ms, remote failures ${s.remoteFailures}. ${corpus.results.filter((r) => r.signals.some((g) => g.includes(":L4:"))).length} samples got a layer-4 signal.`);
p();
p("### Detector mismatches");
p();
p("| Sample | Label | Real? | Score | Signals |\n|---|---|---|---|---|");
for (const r of corpus.results.filter((r) => (r.label === "scam" && r.score < 30) || (r.label === "legit" && r.score >= 30)))
    p(`| \`${r.id}\` | ${r.label === "scam" ? "scam missed" : "legit flagged"} | ${r.synthetic ? "synthetic" : "real"}${r.holdout ? " · holdout" : ""} | ${r.score} | ${r.signals.join(", ") || "—"} |`);
p();
p("<details><summary>All 108 samples</summary>");
p();
p("| Sample | Label | Real? | L1–2 | Total | Status | Signals |\n|---|---|---|---|---|---|---|");
for (const r of corpus.results) p(`| \`${r.id}\` | ${r.label} | ${r.synthetic ? "syn" : "real"}${r.holdout ? " · H" : ""} | ${r.localScore} | ${r.score} | ${r.status} | ${r.signals.join(", ")} |`);
p();
p("</details>");
p();

// ---- live
p("## Test 2b/2c — live, two simulators on a local stack built like prod");
p();
p("| Part | Local | Prod |\n|---|---|---|");
p("| API | `wrangler dev` of `backend/api` on :8787, `--test-scheduled` | Worker `shoo-api` |");
p("| Database + Storage | `supabase start` + `supabase db reset` (all migrations, RLS) | Supabase project |");
p("| Replicas | local R2 (Miniflare) | R2 `shoo-replicas` |");
p("| AI layers 3–4 | `wrangler dev` of `ai/` on :8788, same LLM provider as prod, prebuilt blocklist in local KV | Worker `shoo-ai` |");
p("| Push | APNs **sandbox**, new team key (AK7HLX5ZX5), topic `com.aliefauzan.shoo` | APNs |");
p("| App | Debug build, `-debug.aiBaseURL http://localhost:8788` (new, Debug only) | Release |");
p();
p("Pairing (`LiveQAUITests`): Adhella (Guardian, \"QA Guardian iPhone 17\") and Maria (Protected, \"QA Protected iPhone 17\") onboard in Bahasa Indonesia, Maria joins with the code on Adhella's screen, both answer the real notification prompt. The Protected Safari has Shoo on with *All Websites: Allow*.");
p();
const resolving = dns.filter((d) => d.resolves);
p(`Guardrails: only corpus URLs, simulator only, page load only (no typing, no taps on the page, no downloads). Hosts were checked by DNS first: **${resolving.length} of ${dns.length} resolve** (${resolving.filter((d) => d.label === "legit").length} legit, ${resolving.filter((d) => d.label === "scam").length} scam). The ${dns.filter((d) => d.label === "scam" && !d.resolves).length} scam hosts that don't resolve (all synthetic + one real) are covered by 2a only (2c).`);
p();
if (live) {
    p(live.summary);
    p();
    const head = "| Sample | Label | 2a score | What the Safari shot shows | Scan on server | Guardian push |\n|---|---|---|---|---|---|";
    const row = (r) => p(`| \`${r.id}\` | ${r.label} | ${r.offline} | ${r.live} | ${r.scan} | ${r.push} |`);
    p(head);
    live.rows.filter((r) => r.label === "scam" || r.scan !== "none").forEach(row);
    p();
    p(`<details><summary>${live.rows.filter((r) => r.label === "legit").length} legit pages</summary>`);
    p();
    p(head);
    live.rows.filter((r) => r.label === "legit" && r.scan === "none").forEach(row);
    p();
    p("</details>");
    p();
    p("What happened, in order:");
    p();
    p("1. **Legit pages**: every page that loaded shows the green **0%** badge; none reached the server (only scores ≥ 30 are posted). The 4 legit traps that 2a flagged no longer serve their page (404, parking page, no server), so live they score 0.");
    p("2. **`regs-apps14.regnows-dfg.com/code.php`** (real scam, still up): the extension shows the **46% Waspada** banner, and the scan reaches the server with `asks_otp` (layer 3) + `suspicious_link` (layer 2). Offline it scored 21: the live page asks for an OTP, the corpus copy does not.");
    p("3. **`lphone-login.com`** (real scam, 39 offline): the host now redirects to the real `icloud.com` Find Devices page, so live it is a clean Apple page at 0%. A cloaked kit: only the offline copy shows the phishing form.");
    p("4. **No Guardian push on the first visit**: both devices were in *Jam tenang* (22:00–06:00, device zone Asia/Makassar, visit at 22:40). Warnings are muted then by design (PF-01, `notify.ts allowed()`); only blocked sites still push. After turning `quiet_hours` off in the local DB and reloading the page once, the Worker tried both pushes (Guardian + Maria's own) and logged **`failed:network`**: `wrangler dev` (workerd on the Mac) cannot speak HTTP/2, and APNs only takes HTTP/2. Production sends straight from the deployed Worker (spike passed in fase 07, D-alief-B01), so this is a limit of the local stack, not of prod. The app side of the push was checked with `xcrun simctl push` and the same payload the Worker builds (`pushText`, `scanId`).");
    p("5. **Guardian Activity is empty after pairing**: Adhella paired with Maria, but Family mode stays off until the Guardian switches it on from Home, so Activity shows only her own (empty) list. With `-settings.familyModeOn YES` both of Maria's scans show with her name, and Detail opens with the 46% gauge.");
    p("6. **Two rows for one page**: the second load of the same page made a second scan 1 min later; Activity lists both.");
    p("7. A Safari *Allow location?* prompt (from `ruparupa.com`) stayed on screen for the rest of the run; it was left unanswered during the visit and answered **Don't Allow** at the end. It covers part of the later shots but not the badge logic.");
    p("8. **Crons** fired by hand (`/cdn-cgi/handler/scheduled?cron=0+19+*+*+*` and `cron=5+*+*+*+*`): both 200, `ops_heartbeat` row written; nothing older than 14 days to delete on a fresh database.");
    p();
    if (live.shots?.length) {
        p("| " + live.shots.map((x) => x.caption).join(" | ") + " |");
        p("|" + live.shots.map(() => "---").join("|") + "|");
        p("| " + live.shots.map((x) => img(x.path, 140)).join(" | ") + " |");
        p();
    }
} else {
    p("_Live results pending._");
    p();
}

// ---- rerun
p("## Re-run");
p();
p("```bash");
p("# Figma frames (TalkToFigma plugin open in the file, channel joined)");
p("node plan/alief/qa/figma-export.mjs plan/alief/qa/img/figma-parity/figma <channel>");
p("# Test 1 + 2a screenshots");
p("TEST_RUNNER_QA_SCENARIO=figma TEST_RUNNER_QA_SHOT_DIR=$PWD/plan/alief/qa/img/figma-parity/app xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ShooAppUITests/FigmaParityUITests");
p("# Test 2a data");
p("npx --prefix ai wrangler dev --cwd ai --port 8788 &");
p("node ai/eval/run.mjs --analyze-url http://127.0.0.1:8788 --json --show-holdout > /tmp/corpus-eval.json && node plan/alief/qa/corpus-to-scans.mjs /tmp/corpus-eval.json");
p("# Test 2b: pair, then visit");
p("TEST_RUNNER_QA_LIVE=1 TEST_RUNNER_QA_PAIR_DIR=/tmp/pair xcodebuild test … -only-testing:ShooAppUITests/LiveQAUITests/testGuardianPairs   # Guardian sim");
p("TEST_RUNNER_QA_LIVE=1 TEST_RUNNER_QA_PAIR_DIR=/tmp/pair xcodebuild test … -only-testing:ShooAppUITests/LiveQAUITests/testProtectedJoins  # Protected sim");
p("bash plan/alief/qa/live-visit.sh <protected-udid>");
p("# then write live/observations.json from the shots, and");
p("node plan/alief/qa/live-results.mjs");
p("node plan/alief/qa/figma-parity-report.mjs");
p("```");
p();

writeFileSync(join(here, "figma-parity-2026-10-31.md"), out.join("\n"));
console.log(`${rows.length} frames, report written`);
