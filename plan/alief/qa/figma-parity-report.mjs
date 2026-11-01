// Builds plan/alief/qa/figma-parity-2026-10-31.md from the run's files:
//   figma-parity-map.json (frame -> app shot), figma-parity-notes.json (gap per frame),
//   img/figma-parity/{app,figma,live}/, corpus-results.json, corpus-dns.json, live/live-results.json.
//   node plan/alief/qa/figma-parity-report.mjs
// Written for a quick read: a short summary first, then every section says what it checks,
// the result, and how to read its table. Plain words, short sentences, no em dashes.
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
// Where each test page comes from (ai/eval/data file + line) and its local view, from corpus-view.mjs.
const views = existsSync(join(here, "corpus-view/index.json")) ? read("corpus-view/index.json") : {};
const pageRef = (id) => (views[id] ? `[\`${id}\`](../../../${views[id].file}#L${views[id].line})<br>[view](corpus-view/${views[id].view})` : `\`${id}\``);

const FIGMA = "https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=";
const img = (path, w = 160) => `<img src="${path}" width="${w}">`;
const app = (shot) => (shot && existsSync(join(here, `img/figma-parity/app/${shot}.jpg`)) ? img(`img/figma-parity/app/${shot}.jpg`) : "no screenshot");
const fig = (id) => img(`img/figma-parity/figma/${id.replace(":", "-")}.jpg`);
const badge = { match: "✅ same", minor: "🟡 small diff", gap: "🟠 clear diff", missing: "🔴 missing", test: "⚪ not shot" };
const pct = (n, d) => Math.round((100 * n) / d);
const pass = (ok) => (ok ? "✅ pass" : "❌ fail");
// "asks_otp:L3:30" -> "asks_otp (L3, +30)"
const signal = (g) => g.replace(/^(.*):L(\d):(\d+)$/, "$1 (L$2, +$3)");
const signals = (list) => list.map(signal).join(", ") || "none";

const out = [];
const p = (s = "") => out.push(s);

// ---- counts
const rows = Object.entries(map).filter(([k]) => k !== "_note").flatMap(([sec, list]) => list.map((r) => [sec, ...r]));
const count = {};
for (const [, id] of rows) count[notes[id]?.[0] ?? "test"] = (count[notes[id]?.[0] ?? "test"] ?? 0) + 1;
const s = corpus.summary;
const scamN = s.counts.scam;
const legitN = s.counts.legit;
const scamMissed = scamN - s.scam.atLeast30;
const realScam = corpus.results.filter((r) => r.label === "scam" && !r.synthetic).length;
const realLegit = corpus.results.filter((r) => r.label === "legit" && !r.synthetic).length;
const p95 = s.timing.analyzeRemoteP95Ms / 1000;
const liveScam = live?.rows.find((r) => r.scan !== "none");

p("# QA report: does the iOS app match Figma, and does scam detection work?");
p();
p("Run on 2026-11-01 (first run 2026-10-31). Branch `feat/GD-01-home-figma`, PR #228.");
p();

// ---- summary
p("## Short version");
p();
p(`- **Screens vs Figma:** ${rows.length} Figma frames checked. ${count.match ?? 0} the same, ${count.minor ?? 0} with small differences, ${count.gap ?? 0} clearly different${count.missing ? `, ${count.missing} missing` : ""}${count.test ? `, ${count.test} not shot` : ""}. Many small differences come from iOS itself (top bar position, glass buttons).`);
p("- **Test 1, unusual fake data:** the screens still work. 2 small issues: a 39% warning says \"Risiko Tinggi\", and big counters don't shorten to \"999+\".");
p(`- **Test 2a, scam detector on saved pages:** misses its targets. It blocks only ${s.scam.atLeast80} of ${scamN} scam pages (${pct(s.scam.atLeast80, scamN)}%, target 70%) and wrongly flags ${s.legit.atLeast30} of ${legitN} normal pages (target 0).`);
p(`- **Test 2b/2c, real websites on two phones:** ${liveScam ? `one of the 2 live scam pages got a ${liveScam.scan.split(" ")[0]}% warning and reached the Guardian's app. ` : ""}The Guardian only sees it after turning Family mode on by hand. Push can't be tested on a laptop setup.`);
p("- **Test 3, Imelda's link lists (`ai/test-layer2`):** offline, from the link alone, only 3 of 25 scam links are blocked. Live, with the real page, the extension blocks or warns on most scam pages that still exist. But it **wrongly blocks `mit.edu`** because that domain is on the public scam list.");
p();

// ---- legend
p("## How to read this report");
p();
p("**Screen status:**");
p();
p("| Mark | Meaning |\n|---|---|");
p("| ✅ same | Looks like the Figma frame. |");
p("| 🟡 small diff | Small visual difference, often caused by iOS itself. |");
p("| 🟠 clear diff | Clearly different. Needs a design or product decision. |");
p("| 🔴 missing | The screen is not built. |");
p("| ⚪ not shot | No app screenshot for this frame. |");
p();
p("**Scam score** (from `contracts/README.md`):");
p();
p("| Score | What the user sees |\n|---|---|");
p("| 0 to 29 | Nothing. The page is treated as normal. |");
p("| 30 to 79 | A warning. |");
p("| 80 to 100 | The page is blocked. |");
p();
p("**The 4 detection layers** (from `contracts/detector-interface.md`):");
p();
p("| Layer | What it checks | Where it runs |\n|---|---|---|");
p("| L1 | Known scam sites list | On the phone |");
p("| L2 | The link name (fake brand names, odd hosts) | On the phone |");
p("| L3 | Page text and forms (asks for OTP, PIN, ID card) | Server |");
p("| L4 | Reality check by an AI model (does this request make sense for this kind of page?) | Server |");
p();

// ---- setup
p("## What was tested");
p();
p("| Test | What it checks | How |\n|---|---|---|");
p(`| Screens | Every app screen next to its Figma frame. | Figma page *High Fidelity*: every iOS frame marked Ready for dev, plus HOME and the *AI vs Guardian* exploration. Fake data (scenario \`figma\`). |`);
p("| Test 1 | The same screens with unusual fake data. | 6 data sets from `Data/MockScenarios.swift`. No server. |");
p(`| Test 2a | Does the detector give the right score? | ${scamN + legitN} saved web pages from Imelda's test set, sent through all 4 layers. No real website opened. |`);
p("| Test 2b/2c | Does it work end to end on real websites? | Two paired phones (Guardian + Protected). Safari opens the test-set pages that still exist. |");
p();
p("| | |\n|---|---|");
p("| Devices | Screens and Test 1: iPhone 17 Pro simulator, iOS 26.4. Test 2b/2c: \"QA Guardian iPhone 17\" (iOS 26.5) and \"QA Protected iPhone 17\" (iOS 26.4). |");
p("| Settings | Bahasa Indonesia, light mode, Jakarta time (WIB). |");
p("| App | `feat/GD-01-home-figma` @ f93e660 (with `main` merged in). |");
p(`| Figma | [High Fidelity](${FIGMA}18-2), exported at 1x with the TalkToFigma plugin. |`);
p();

// ---- findings
p("## Problems found");
p();
p("Found outside the screen-by-screen tables. First seen on 2026-10-31, checked again on 2026-11-01.");
p();
p("### Still open");
p();
p("| # | Problem | Where to see it | How bad |\n|---|---|---|---|");
p("| 12 | **`mit.edu` is blocked** (100%, \"This site is known to cheat people\"). The domain is on the public scam list the AI server builds, so the extension blocks the whole real MIT site, and the Guardian gets it as a blocked site. The list needs an allowlist check for big real sites. | Test 3, `legit-12`; `live-l2/safari-legit-12.jpg`, `guardian-1-home.jpg` | 🔴 Team AI / lead |");
p("| 6 | The Guardian sees nothing from the family after pairing. Family mode must be switched on by hand on Home first. Figma always shows the family. | `live/guardian-activity.jpg` (off) vs `guardian-activity-family.jpg` (on) | 🟠 |");
p("| 7 | Push can't be tested on the laptop setup. The local server can't use HTTP/2, which Apple's push service needs, so every push logs `failed:network`. Production uses the deployed server, so this is only a test setup limit. A cloud staging server is needed for a full push test. | Test 2b/2c, step 4 | 🟠 |");
p(`| 11 | The scam detector misses its targets: ${s.legit.atLeast30} normal pages flagged (target 0), ${scamMissed} scam pages missed, only ${pct(s.scam.atLeast80, scamN)}% of scams blocked (target 70%). | Test 2a | ⚪ Team AI |`);
p("| 4 | A 39% warning says \"Risiko Tinggi\", the same label as 72%. | `corpus-dt-real-lphone` | 🟡 |");
p("| 5 | Counters don't shorten: Guardian Profile shows \"3.000 Situs diblokir\" (no \"999+\"). It fits, but the tile gets wider than in Figma. | `heavy-pf-guardian` | 🟡 |");
p("| 9 | The Safari extension popup is in English while the app is in Bahasa Indonesia. It follows the phone's language. The extension is out of scope here; noted for the lead. | `live/safari-regs-apps14-code-php.jpg` | 🟡 |");
p("| 10 | On a live scan, the page copy in Detail (\"Salinan halaman\") stays grey and the site icon circle is empty. | `live/guardian-detail-regnows.jpg` | 🟡 |");
p();
p("### Fixed since 2026-10-31");
p();
p("| # | Problem | Now |\n|---|---|---|");
p("| 1 | Emoji in a name showed as ⍰ boxes. | `Bayu 🧑‍💻` shows the emoji (`edge-home-guardian`, `edge-pf-guardian`). |");
p("| 2 | An expired code showed a general error. | Shows \"Kode kedaluwarsa, minta kode baru dan coba lagi.\" like Figma 205:1182. |");
p("| 3 | A \"Notifikasi mati\" popup covered Home and Activity in every test run. | Gone in all Home and Activity screenshots. |");
p();
p("### Not checked again");
p();
p("| # | Problem | Why |\n|---|---|---|");
p("| 8 | Opening the same page twice made two rows in Activity (`regnows-dfg.com` at 22.40 and 22.41). | This run opened each page only once, and Activity showed one row. |");
p();
const sev = { missing: 0, gap: 1, minor: 2 };
const found = rows.filter(([, id]) => notes[id] && notes[id][0] in sev).sort((a, b) => sev[notes[a[1]][0]] - sev[notes[b[1]][0]]);
p("### Screens that differ from Figma");
p();
p("Worst first. Pictures are in the screen tables below.");
p();
p("| Status | Frame | What is different |\n|---|---|---|");
for (const [, id, name] of found) p(`| ${badge[notes[id][0]]} | [${name}](${FIGMA}${id.replace(":", "-")}) | ${notes[id][1]} |`);
p();

// ---- frame tables
const sectionName = { HOME: "Home", ONBOARDING: "Onboarding and pairing", Activity: "Activity and Detail", Profile: "Profile", "AI vs GUARDIAN - EKSPLORASI": "AI vs Guardian (design exploration)" };
p("## Screen by screen");
p();
p("Left: the app now. Right: the Figma frame. Figma frames show the whole scroll height; the app screenshot shows one screen. More screens of the same state are in `img/figma-parity/app/<name>-2.jpg` and `-3.jpg`.");
p();
for (const [sec, list] of Object.entries(map)) {
    if (sec === "_note") continue;
    p(`### Screens: ${sectionName[sec] ?? sec}`);
    p();
    p("| Frame | App now | Figma | Status | Notes |\n|---|---|---|---|---|");
    for (const [id, name, shot] of list) {
        const [st, note] = notes[id] ?? ["test", ""];
        p(`| [${name}](${FIGMA}${id.replace(":", "-")})<br>\`${id}\` | ${app(shot)}<br>\`${shot ?? "none"}\` | ${fig(id)} | ${badge[st]} | ${note} |`);
    }
    p();
}

// ---- variants
p("## Test 1: the same screens with unusual fake data");
p();
p("**What it checks:** the screens still look right when the data is extreme: long names, emoji, many scans, only safe, only blocked. The data is fake (`MockRepository`), so no server is involved.");
p();
p("**Result:** the screens hold up. Problems 4 and 5 above come from this test.");
p();
p("**How to read it:** one row of screenshots per data set. The label above each picture is the screen: `home` = Home, `act` = Activity, `pf` = Profile, `dt` = Detail; `guardian` / `protected` = whose phone.");
p();
const variants = {
    mixedVerdicts: "every kind of result: blocked or warning, and not reviewed, marked safe, or marked not safe by the Guardian",
    heavy: "a lot of data: 3 family members, 60 scans over 30 days, counters over 999",
    edge: "awkward data: 20-character names, emoji, an 87-character web address, no title, icon or screenshot, only one reason",
    allSafe: "every scan marked safe by the Guardian",
    allBlocked: "only blocked scans",
    corpus: "the scores and reasons the real detector gave in Test 2a (41 scans of 30 or more)",
};
const shots = ["home-guardian", "home-protected", "act-guardian", "act-protected", "pf-guardian"];
for (const [name, what] of Object.entries(variants)) {
    p(`### \`${name}\`: ${what}`);
    p();
    const extra = name === "edge" ? ["dt-long", "dt-one-signal"] : name === "corpus" ? ["dt-top", "dt-real-bsi", "dt-real-lphone", "dt-false-positive"] : name === "heavy" ? ["dt-first"] : name === "allSafe" ? ["dt-safe"] : [];
    const list = [...shots, ...extra].filter((x) => existsSync(join(here, `img/figma-parity/app/${name}-${x}.jpg`)));
    p("| " + list.map((x) => `\`${x}\``).join(" | ") + " |");
    p("|" + list.map(() => "---").join("|") + "|");
    p("| " + list.map((x) => img(`img/figma-parity/app/${name}-${x}.jpg`, 140)).join(" | ") + " |");
    p();
}

// ---- corpus
// Expected score and verdict per sample: contracts/README.md thresholds, docs/mandates/imelda.md targets.
const expected = (r) => (r.label === "scam" ? "≥ 80 % · scam, block it" : "< 30 % · not scam, show nothing");
const right = (r) => (r.label === "scam" ? (r.score >= 80 ? "✅ blocked" : r.score >= 30 ? "⚠️ only warned" : "❌ missed") : r.score < 30 ? "✅ left alone" : "❌ wrongly flagged");
const source = (r) => `${r.synthetic ? "made up" : "real"}${r.holdout ? ", held back" : ""}`;
p("## Test 2a: does the detector score saved pages right?");
p();
p(`**What it checks:** Imelda's test set has ${scamN + legitN} saved web pages: ${scamN} scam and ${legitN} normal. Each page goes through all 4 layers, and its score is compared with what it should be. No real website is opened.`);
p();
p(`**Result: targets not met.** Too few scams are blocked, and ${s.legit.atLeast30} normal pages are wrongly flagged.`);
p();
p("| Check | Target | Result | |\n|---|---|---|---|");
p(`| Scam pages blocked (score 80 or more) | at least 70% | ${s.scam.atLeast80} of ${scamN} = ${pct(s.scam.atLeast80, scamN)}% | ${pass(s.scam.atLeast80 / scamN >= 0.7)} |`);
p(`| Scam pages scoring 50 or more | at least 90% | ${s.scam.atLeast50} of ${scamN} = ${pct(s.scam.atLeast50, scamN)}% | ${pass(s.scam.atLeast50 / scamN >= 0.9)} |`);
p(`| Scam pages that got any warning (30 or more) | no target | ${s.scam.atLeast30} of ${scamN} = ${pct(s.scam.atLeast30, scamN)}% | |`);
p(`| Scam pages missed (under 30) | no target | ${scamMissed} of ${scamN} | |`);
p(`| Normal pages wrongly flagged (30 or more) | 0 | ${s.legit.atLeast30} of ${legitN} | ${pass(s.legit.atLeast30 === 0)} |`);
p(`| Server time for one page (95th percentile) | under 8 s | ${p95.toFixed(1)} s | ${pass(p95 < 8)} |`);
p(`| Server errors | 0 | ${s.remoteFailures} | ${pass(s.remoteFailures === 0)} |`);
p();
p(`**Keep in mind:** only ${realScam} of the ${scamN} scam pages are real captured scams. The rest were written by Team AI for testing (\"made up\"). ${realLegit} of the ${legitN} normal pages are real sites. So these numbers show how the detector does on the test set, not yet on the real web. \"Held back\" pages are kept aside and never used to tune the detector.`);
p();
p("Targets: `docs/mandates/imelda.md`. Command: `node ai/eval/run.mjs --analyze-url http://127.0.0.1:8788 --json --show-holdout`, against a local copy of the AI server (`ai/`) with the same AI model as production and the public scam list (190 000 sites) loaded. `corpus-to-scans.mjs` turns the results into the `corpus` data set for Test 1.");
p();
p("**See every test page:** each page name below links to its source in `ai/eval/data` (the code Imelda wrote or captured). The *view* link is a local HTML page that draws what the detector saw (URL, title, text, form fields, images as their alt text) next to its score and the live Safari screenshot. GitHub shows those as code, so open them on your Mac:");
p();
p("```bash");
p("node plan/alief/qa/corpus-view.mjs        # rebuild after the corpus or results change");
p("open plan/alief/qa/corpus-view/index.html  # list of all pages, scored-wrong ones first");
p("```");
p();
p("The corpus keeps a snapshot of each page, not the full website, so the view is a simple drawing of that snapshot. Scam addresses are shown as text, never as links.");
p();
p("### Pages scored wrong");
p();
p("**How to read it:** \"Should get\" is the target for that kind of page. \"Got\" is the detector's score. \"Why\" lists the reasons that fired: name, layer, and points added.");
p();
p("| Page | Problem | Source | Should get | Got | Why |\n|---|---|---|---|---|---|");
for (const r of corpus.results.filter((r) => (r.label === "scam" && r.score < 30) || (r.label === "legit" && r.score >= 30)))
    p(`| ${pageRef(r.id)} | ${r.label === "scam" ? "scam missed" : "normal page flagged"} | ${source(r)} | ${expected(r)} | ${r.score} % | ${signals(r.signals)} |`);
p();
p(`<details><summary>All ${scamN + legitN} pages</summary>`);
p();
p("\"L1-2\" is the score from the phone alone; \"Final\" adds the server layers.");
p();
p("| Page | Type | Source | Should get | L1-2 | Final | Right? | Why |\n|---|---|---|---|---|---|---|---|");
for (const r of corpus.results) p(`| ${pageRef(r.id)} | ${r.label === "scam" ? "scam" : "normal"} | ${source(r)} | ${expected(r)} | ${r.localScore} | ${r.score} | ${right(r)} | ${signals(r.signals)} |`);
p();
p("</details>");
p();

// ---- live
const resolving = dns.filter((d) => d.resolves);
p("## Test 2b/2c: real websites on two paired phones");
p();
p("**What it checks:** the whole chain on real pages: Safari extension, then server, then the Guardian's app and notification.");
p();
p("**Setup:** two simulators. Adhella is the Guardian (the one who watches). Maria is Protected (the one being watched). They paired with a code, like real users. Maria's Safari opened the test-set pages one by one. Page load only: no typing, no tapping on the page, no downloads.");
p();
p(`- **2b:** the ${resolving.length} pages that still exist online (${resolving.filter((d) => d.label === "legit").length} normal, ${resolving.filter((d) => d.label === "scam").length} scam).`);
p(`- **2c:** the ${dns.filter((d) => !d.resolves).length} pages that no longer exist, including ${dns.filter((d) => d.label === "scam" && !d.resolves).length} scam pages. These only have the offline result from Test 2a.`);
p();
if (live) {
    p("### Result");
    p();
    p("| What | Result | |\n|---|---|---|");
    p("| Normal pages | All showed 0%, except one old blog post at 24% (still under 30). None were sent to the server. | ✅ |");
    if (liveScam) p(`| Real scam \`regs-apps14.regnows-dfg.com/code.php\` | Popup with a ${liveScam.scan.split(" ")[0]}% warning. Sent to the server and shown in the Guardian's app. | ✅ |`);
    p("| Real scam `lphone-login.com` | Now forwards to the real iCloud page, so 0%. The scam hides itself from this visit. | ⚪ expected |");
    p("| Guardian sees Maria's scan | Only after Family mode is switched on by hand (problem 6). | ❌ |");
    p("| Push to the Guardian | The server tried, but the laptop setup can't send it (problem 7). The app shows the notification when it is sent by hand. | ⚠️ |");
    p("| Scheduled cleanup jobs | Ran fine when started by hand. | ✅ |");
    p();
    p(`Raw count: ${live.summary}`);
    p();
    const cell = (v) => (v === "—" ? "n/a" : v);
    const head = "| Page | Type | Offline score (2a) | What Safari showed | Sent to server | Push |\n|---|---|---|---|---|---|";
    const row = (r) => p(`| ${pageRef(r.id)} | ${r.label === "scam" ? "scam" : "normal"} | ${r.offline} | ${r.live} | ${cell(r.scan)} | ${cell(r.push)} |`);
    p("### Scam pages");
    p();
    p(head);
    live.rows.filter((r) => r.label === "scam" || r.scan !== "none").forEach(row);
    p();
    p(`<details><summary>${live.rows.filter((r) => r.label === "legit").length} normal pages</summary>`);
    p();
    p(head);
    live.rows.filter((r) => r.label === "legit" && r.scan === "none").forEach(row);
    p();
    p("</details>");
    p();
    p("### Step by step");
    p();
    p("1. **Normal pages.** Every page that loaded showed the green 0% badge. One old blog post showed 24%; that is under 30, so nothing happens. Pages under 30 are never sent to the server. The 4 normal pages that Test 2a flagged no longer show their old content (error page, parked domain, or no server), so here they scored 0. `beritakota` stopped at Safari's \"This Connection Is Not Private\" page, so there was no badge.");
    p("2. **The live scam, `regs-apps14.regnows-dfg.com/code.php`.** The extension showed a popup: 76%, \"Link sent to Adhella\", with *Leave this page* and *Continue anyway*. The server got the scan at 76 (warning) with 3 reasons: the page asks for things that don't fit it (L4, it quotes \"PENDAFTARAN VIA TELEGRAM\"), it asks for an OTP (L3), and the link looks suspicious (L2). The saved copy in Test 2a scored only 21 because it has no OTP field. On 2026-10-31 this page scored 46, without the L4 reason.");
    p("3. **`lphone-login.com`.** It scored 39 offline. Live, it forwards to the real `icloud.com` Find Devices page, so it scored 0%. Only the saved copy shows the fake login form.");
    p("4. **Push.** The visit was at 21.29 WITA, before quiet hours (22:00 to 06:00), so the server sent a push to Adhella and one to Maria right away. Both failed with `failed:network`. The reason: the local server can't use HTTP/2, and Apple's push service only accepts HTTP/2. Production sends from the deployed server, which passed this check before (fase 07, D-alief-B01). To test the app side, the same push was sent by hand with `xcrun simctl push` (\"Maria membuka situs mencurigakan · 76%\", real scan id). The notification showed on Adhella's Home screen.");
    p("5. **Guardian's app.** Right after pairing, Activity is empty: Family mode is off until Adhella switches it on from Home. After the switch, Home shows \"Keluarga Butuh Konfirmasi\" with Maria's 76% card. Activity lists the scan with Maria's name, and Detail opens with the 76% gauge.");
    p("6. **Maria's app.** Home shows \"Anda Terlindungi!\", \"Terhubung dengan Adhella\", 0 Diblokir and 1 Waspada, and the regnows row. Her Activity lists the same scan.");
    p("7. **No location popup** this time. On 2026-10-31 a Safari location question from `ruparupa.com` covered the later screenshots.");
    p("8. **Cleanup jobs.** Both scheduled jobs were started by hand and answered 200. The health row was written. There was nothing older than 14 days to delete, since the database was new.");
    p();
    if (live.shots?.length) {
        p("### Screenshots");
        p();
        p("| " + live.shots.map((x) => x.caption).join(" | ") + " |");
        p("|" + live.shots.map(() => "---").join("|") + "|");
        p("| " + live.shots.map((x) => img(x.path, 140)).join(" | ") + " |");
        p();
    }
    p("<details><summary>Laptop setup vs production</summary>");
    p();
    p("| Part | On the laptop | In production |\n|---|---|---|");
    p("| API | `wrangler dev` of `backend/api` on :8787, `--test-scheduled` | Worker `shoo-api` |");
    p("| Database and storage | `supabase start` + `supabase db reset` (all migrations, row security on) | Supabase project |");
    p("| Page copies | local R2 (Miniflare) | R2 `shoo-replicas` |");
    p("| AI layers 3 and 4 | `wrangler dev` of `ai/` on :8788, same AI model as production, public scam list loaded | Worker `shoo-ai` |");
    p("| Push | Apple push **sandbox**, team key AK7HLX5ZX5, topic `com.aliefauzan.shoo` | Apple push |");
    p("| App | Debug build, `-debug.aiBaseURL http://localhost:8788` (Debug only) | Release |");
    p();
    p("Pairing (`LiveQAUITests`): both phones go through onboarding in Bahasa Indonesia. Maria types the code shown on Adhella's screen. Both answer the real notification question. Maria's Safari has Shoo on for all websites.");
    p();
    p("</details>");
    p();
} else {
    p("_Live results not in yet._");
    p();
}

// ---- test 3: ai/test-layer2 link datasets
const l2File = join(here, "img/figma-parity/layer2-dataset-results.json");
if (existsSync(l2File)) {
    const l2 = JSON.parse(readFileSync(l2File, "utf8"));
    const t = l2.summary;
    const l2live = existsSync(join(here, "img/figma-parity/live-l2/live-results.json")) ? read("img/figma-parity/live-l2/live-results.json") : null;
    const l2dns = existsSync(join(here, "img/figma-parity/layer2-dataset-dns.json")) ? read("img/figma-parity/layer2-dataset-dns.json") : [];
    const liveRow = Object.fromEntries((l2live?.rows ?? []).map((r) => [r.id, r]));
    const dsLink = (r) => {
        const lines = readFileSync(join(here, "../../..", r.file), "utf8").split("\n");
        const n = lines.findIndex((l) => l.includes(r.url)) + 1;
        return `[\`${r.id}\`](../../../${r.file}#L${n})`;
    };
    p("## Test 3: Imelda's link datasets (`ai/test-layer2`)");
    p();
    p(`**What it checks:** the link lists in \`ai/test-layer2/dataset.md\` (${t.counts.scam} scam links) and \`dataset-legit.md\` (${t.counts.legit} normal links). These are links only, with no saved page. Two parts:`);
    p();
    p("- **3a, offline:** each link goes through all 4 layers like Test 2a. L1 = the public scam list, matched the same way as the extension. L2 = the real detector. L3–4 = the server, which only gets the link (no page text).");
    p(`- **3b, live:** Maria's Safari opens every link that still exists (${l2dns.filter((d) => d.resolves).length} of ${l2dns.length}), with the extension on. Each screenshot shows what the extension showed on that page.`);
    p();
    p("**Result:**");
    p();
    p("| Check | Target | Result | |\n|---|---|---|---|");
    p(`| Scam links blocked (80 or more) | at least 70% | ${t.scam.atLeast80} of ${t.counts.scam} = ${pct(t.scam.atLeast80, t.counts.scam)}% | ${pass(t.scam.atLeast80 / t.counts.scam >= 0.7)} |`);
    p(`| Scam links scoring 50 or more | at least 90% | ${t.scam.atLeast50} of ${t.counts.scam} = ${pct(t.scam.atLeast50, t.counts.scam)}% | ${pass(t.scam.atLeast50 / t.counts.scam >= 0.9)} |`);
    p(`| Scam links that got any warning (30 or more) | no target | ${t.scam.atLeast30} of ${t.counts.scam} = ${pct(t.scam.atLeast30, t.counts.scam)}% | |`);
    p(`| Scam links on the public scam list (L1) | no target | ${t.scam.blocklist} of ${t.counts.scam} | |`);
    p(`| Normal links wrongly flagged (30 or more) | 0 | ${t.legit.atLeast30} of ${t.counts.legit} | ${pass(t.legit.atLeast30 === 0)} |`);
    p(`| Server errors | 0 | ${t.remoteFailures} | ${pass(t.remoteFailures === 0)} |`);
    p();
    if (l2live) {
        const opened = l2live.rows.filter((r) => r.label === "scam");
        const lv = (r) => (r.scan === "none" ? 0 : Number(r.scan.split(" ")[0]));
        const lvBlocked = opened.filter((r) => lv(r) >= 80).length;
        const lvWarned = opened.filter((r) => lv(r) >= 30 && lv(r) < 80).length;
        const legitWrong = l2live.rows.filter((r) => r.label === "legit" && r.scan !== "none").length;
        p("**Live result (3b),** on the pages that still exist:");
        p();
        p("| What | Result | |\n|---|---|---|");
        p(`| Scam pages blocked by the extension | ${lvBlocked} of ${opened.length} = ${pct(lvBlocked, opened.length)}% (target 70%) | ${pass(lvBlocked / opened.length >= 0.7)} |`);
        p(`| Scam pages with a warning (30 to 79) | ${lvWarned} of ${opened.length} | ⚠️ |`);
        p(`| Scam pages with no warning | ${opened.length - lvBlocked - lvWarned} of ${opened.length}: 5 missed (under 30), 2 blank pages, 1 stopped by Safari's own warning first | ❌ |`);
        p(`| Normal pages blocked or warned | ${legitWrong} of ${l2live.rows.filter((r) => r.label === "legit").length} (\`mit.edu\`, problem 12) | ${legitWrong ? "❌" : "✅"} |`);
        p("| Scans in the Guardian's app | Every scan of 30 or more shows in Adhella's Home and Activity with Maria's name | ✅ |");
        p("| Push to the Guardian | The first 10 were tried and failed with `failed:network` (laptop setup, problem 7). The last 4 got none: the server sends at most 10 pushes per 10 minutes to one Guardian (`PUSH_CAP` in `backend/api/src/services/push/notify.ts`), by design. | ⚠️ |");
        p();
        p("**Live is much better than offline** because the real page adds layers 3 and 4: the server reads the page text and forms (OTP, PIN, \"code sent to your phone\"). Offline, the server only gets the link.");
        p();
        p("**Missed live:** a fake KlikBCA login on `sites.google.com` (0%), a Blogger page (0%), two Telegram sign-up forms on Blogger (13% and 24%), and a page behind Cloudflare's own phishing warning (24%). `m-pajak.top` and `apply.wozspace.site` showed a blank page, so there was nothing to check.");
        p();
        p(`Raw count: ${l2live.summary} Quiet hours were switched off for this run, like on 2026-10-31.`);
        p();
    }
    p("**How to read the table:** \"Offline\" is the 3a score. \"Extension showed\" is what the Safari screenshot shows (3b). Click a screenshot to see it full size. The link name goes to its line in the dataset file.");
    p();
    const cell = (v) => (v === "—" || v === undefined ? "n/a" : v);
    const shotOf = (id) => (existsSync(join(here, `img/figma-parity/live-l2/safari-${id}.jpg`)) ? `<a href="img/figma-parity/live-l2/safari-${id}.jpg">${img(`img/figma-parity/live-l2/safari-${id}.jpg`, 120)}</a>` : "not opened (site gone)");
    const head = "| Link | Should get | Offline | Why | Extension showed (3b) | Screenshot | Sent to server | Push |\n|---|---|---|---|---|---|---|---|";
    const row = (r) => {
        const lv = liveRow[r.id];
        p(`| ${dsLink(r)}<br><code>${r.host}</code><br>${r.note} | ${expected(r)} | **${r.score}** ${right(r)} | ${signals(r.signals)} | ${cell(lv?.live)} | ${shotOf(r.id)} | ${cell(lv?.scan)} | ${cell(lv?.push)} |`);
    };
    p("### Scam links");
    p();
    p(head);
    l2.results.filter((r) => r.label === "scam").forEach(row);
    p();
    p("### Normal links");
    p();
    p(head);
    l2.results.filter((r) => r.label === "legit").forEach(row);
    p();
    const appShots = (l2live?.shots ?? []).filter((x) => !x.path.includes("/safari-"));
    if (appShots.length) {
        p("### What our app showed after the visit");
        p();
        p("| " + appShots.map((x) => x.caption).join(" | ") + " |");
        p("|" + appShots.map(() => "---").join("|") + "|");
        p("| " + appShots.map((x) => img(x.path, 140)).join(" | ") + " |");
        p();
    }
}

// ---- rerun
p("## How to run it again");
p();
p("```bash");
p("# Figma frames (TalkToFigma plugin open in the file, channel joined)");
p("node plan/alief/qa/figma-export.mjs plan/alief/qa/img/figma-parity/figma <channel>");
p("# Screens + Test 1 screenshots (set TEST_RUNNER_QA_SCENARIO to figma, mixedVerdicts, heavy, edge, allSafe, allBlocked or corpus)");
p("TEST_RUNNER_QA_SCENARIO=figma TEST_RUNNER_QA_SHOT_DIR=$PWD/plan/alief/qa/img/figma-parity/app xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShooAppUITests/FigmaParityUITests");
p("# Test 2a data, then the local page viewer");
p("npx --prefix ai wrangler dev --cwd ai --port 8788 &");
p("node ai/eval/run.mjs --analyze-url http://127.0.0.1:8788 --json --show-holdout > /tmp/corpus-eval.json && node plan/alief/qa/corpus-to-scans.mjs /tmp/corpus-eval.json");
p("node plan/alief/qa/corpus-view.mjs && open plan/alief/qa/corpus-view/index.html");
p("# Test 2b: which hosts still exist");
p("node plan/alief/qa/corpus-dns.mjs plan/alief/qa/img/figma-parity/corpus-results.json plan/alief/qa/img/figma-parity/corpus-dns.json");
p("# Test 2b: pair, then visit");
p("TEST_RUNNER_QA_LIVE=1 TEST_RUNNER_QA_PAIR_DIR=/tmp/pair xcodebuild test … -only-testing:ShooAppUITests/LiveQAUITests/testGuardianPairs   # Guardian sim");
p("TEST_RUNNER_QA_LIVE=1 TEST_RUNNER_QA_PAIR_DIR=/tmp/pair xcodebuild test … -only-testing:ShooAppUITests/LiveQAUITests/testProtectedJoins  # Protected sim");
p("bash plan/alief/qa/live-visit.sh <protected-udid>");
p("# then write live/observations.json from the shots, and");
p("node plan/alief/qa/live-results.mjs live corpus-results.json <run start> <run end>");
p("xcrun simctl push <guardian-udid> com.aliefauzan.shoo plan/alief/qa/push-live-warning.apns   # app side of the push");
p("# Test 3: ai/test-layer2 links (3a offline, then 3b live; the AI server allows 300 /analyze calls per 10 min)");
p("node plan/alief/qa/layer2-dataset-test.mjs");
p("node plan/alief/qa/corpus-dns.mjs plan/alief/qa/img/figma-parity/layer2-dataset-results.json plan/alief/qa/img/figma-parity/layer2-dataset-dns.json");
p("bash plan/alief/qa/live-visit.sh <protected-udid> 15 img/figma-parity/layer2-dataset-dns.json img/figma-parity/live-l2");
p("# then write live-l2/observations.json from the shots, and");
p("node plan/alief/qa/live-results.mjs live-l2 layer2-dataset-results.json <run start> <run end>");
p("node plan/alief/qa/figma-parity-report.mjs");
p("```");
p();

writeFileSync(join(here, "figma-parity-2026-10-31.md"), out.join("\n"));
console.log(`${rows.length} frames, report written`);
