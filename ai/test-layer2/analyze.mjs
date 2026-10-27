// Layer 2 test: reads dataset.md, runs the real detector (analyzeLocal) on every URL string, splits each URL into
// components, and rewrites the AUTO block of REPORT.md. Text of the URL only: no link is ever opened, no network.
//   node ai/test-layer2/analyze.mjs
import fs from "node:fs";
import vm from "node:vm";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, "../..");
const detectorFile = path.join(root, "ios/ShooExtension/Resources/detector.js");
const rules = JSON.parse(fs.readFileSync(path.join(root, "detector/data/link-rules.json"), "utf8"));
const brands = JSON.parse(fs.readFileSync(path.join(root, "detector/data/brands.json"), "utf8"));
// usage: node ai/test-layer2/analyze.mjs [dataset file] [report file]   (default: dataset.md -> REPORT.md)
const datasetFile = path.join(here, process.argv[2] || "dataset.md");
const reportFile = path.join(here, process.argv[3] || "REPORT.md");
const OFFICIAL = new Set(brands.brands.flatMap((b) => b.domains));
const onOfficialList = (host) => { const l = host.split("."); return l.some((_, i) => i < l.length - 1 && OFFICIAL.has(l.slice(i).join("."))); };
const START = "<!-- AUTO:START -->";
const END = "<!-- AUTO:END -->";

// ---------- dataset ----------
const rows = fs.readFileSync(datasetFile, "utf8").split("\n")
    .filter((l) => /^\|\s*\d+\s*\|/.test(l))
    .map((l) => l.split("|").slice(1, -1).map((c) => c.trim()))
    .map(([id, url, label, batch, note]) => ({ id, url, label, batch, note }));

// ---------- detector ----------
const ctx = { URL, console };
ctx.globalThis = ctx;
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(detectorFile, "utf8"), ctx);
const detectorVersion = ctx.ShooDetector.version;

// ---------- components ----------
const PLATFORMS = [...new Set([...rules.freeHosts, "edgeone.dev"])]; // edgeone.dev is not in link-rules.json yet
const MULTI = new Set(brands.suffixes);
const CHEAP = new Set(brands.cheapTlds);
const RARE = new Set(rules.rareTlds);
const GENERIC = new Set(["com", "net", "org"]);
const CRED_FILE = /^(code|otp|pin|info|confirm|verif\w*|login|2c)(\.\w+)?$/i;

function suffixGroup(suffix, tld) {
    if (PLATFORMS.includes(suffix)) return "platform (free host)";
    if (suffix.includes(".")) return "country SLD (" + suffix + ")";
    if (GENERIC.has(tld)) return "generic (.com .net .org)";
    if (CHEAP.has(tld)) return "cheap TLD (brands.json)";
    if (RARE.has(tld)) return "rare TLD (link-rules.json)";
    return "other TLD (not on any list)";
}

function split(raw) {
    const u = new URL(raw);
    const labels = u.hostname.toLowerCase().split(".");
    const host = labels.join(".");
    const platform = PLATFORMS.find((p) => host === p || host.endsWith("." + p));
    let suffix = platform;
    if (!suffix) suffix = labels.length > 2 && MULTI.has(labels.slice(-2).join(".")) ? labels.slice(-2).join(".") : labels.at(-1);
    const rest = host.slice(0, host.length - suffix.length).replace(/\.$/, "").split(".").filter(Boolean);
    // on a platform the owner of the page is the first label, so it is the "name"; elsewhere it is the registrable label
    const name = rest.at(-1) || "";
    const sub = rest.slice(0, -1).join(".");
    const tld = labels.at(-1);
    const segs = u.pathname.split("/").filter(Boolean);
    const file = segs.at(-1) || "";
    const ext = (file.match(/\.(\w+)\.?$/) || [])[1] || "";
    const hostText = host + u.pathname.toLowerCase();
    const bait = rules.baitWords.filter((w) => hostText.includes(w));
    return {
        scheme: u.protocol.replace(":", ""), sub, name, suffix, tld, group: suffixGroup(suffix, tld),
        path: u.pathname, file, ext, trailingSlash: u.pathname.length > 1 && u.pathname.endsWith("/"),
        hyphens: (name.match(/-/g) || []).length, digits: (host.match(/\d/g) || []).length,
        hasDigit: /\d/.test(host), hostLen: host.length, bait, credFile: CRED_FILE.test(file),
        pathKind: segs.length === 0 ? "root only" : file.includes(".") || ext ? "file" : "folder / bare word",
    };
}

// ---------- run ----------
const results = [];
const t0 = performance.now();
for (const r of rows) {
    const t = performance.now();
    const sig = await ctx.ShooDetector.analyzeLocal({ url: r.url, domain: new URL(r.url).hostname, title: "", text: "", forms: [], imageAlts: [] });
    const ms = performance.now() - t;
    const score = Math.min(100, sig.reduce((a, s) => a + s.weight, 0));
    results.push({ ...r, c: split(r.url), sig, score, ms, official: onOfficialList(new URL(r.url).hostname.toLowerCase()) });
}
const totalMs = performance.now() - t0;

// ---------- report ----------
const n = results.length;
const pct = (k, d = n) => (d ? Math.round((100 * k) / d) : 0) + "%";
const any = (r) => r.sig.length > 0;
const pop = (r) => r.score >= 30;
const code = (s) => "`" + String(s).replace(/`/g, "") + "`";
const sigText = (r) => (r.sig.length ? r.sig.map((s) => `${s.id}:${s.weight}` + (s.id === "suspicious_link" ? ` [${s.evidence}]` : "")).join("; ") : "-");

function group(keyFn) {
    const m = new Map();
    for (const r of results) {
        const k = keyFn(r);
        (m.get(k) || m.set(k, []).get(k)).push(r);
    }
    return [...m.entries()].sort((a, b) => b[1].length - a[1].length)
        .map(([k, v]) => `| ${k === "" || k == null ? "(none)" : k} | ${v.length} | ${pct(v.length)} | ${v.filter(any).length} (${pct(v.filter(any).length, v.length)}) | ${v.filter(pop).length} (${pct(v.filter(pop).length, v.length)}) |`).join("\n");
}
const legitMode = results.length > 0 && results.every((r) => r.label === "legit");
const labelText = [...new Set(results.map((r) => r.label))].join(" + ");
const A = legitMode ? "false positive (any signal)" : "L2 any signal";
const P = legitMode ? "false popup (>= 30)" : "L2 >= 30";
const gHead = (title) => `| ${title} | URLs | share of set | ${A} | ${P} |\n|---|---|---|---|---|`;

let out = `${START}
_Generated by \`analyze.mjs\` on ${new Date().toISOString()}. Do not edit inside this block._

## 1. Setup
- Detector: \`ios/ShooExtension/Resources/detector.js\`, version ${detectorVersion}. Layer 2 only (A: brand check, B: \`dissectLink\`). No layer 1 list, no layer 3-4.
- Input: \`${path.basename(datasetFile)}\`, ${n} unique URLs, labelled: ${labelText}.${legitMode ? " Every L2 signal here is a false positive. Target: 0 legit pages with score >= 30." : " No legit class in this file."}
- \`on official list\` = the host is on \`brands.json\` (25 brands). The detector returns no signal for those before any check, so a clean result there says nothing about the URL structure.
- Score of a URL = sum of its signal weights (max 100). Popup level = 30.
- Timing: ${totalMs.toFixed(1)} ms total, ${(totalMs / n).toFixed(2)} ms per URL (target < 50 ms).

## 2. Detection result
| Measure | URLs | Share |
|---|---|---|
| ${legitMode ? "Any L2 signal (false positive)" : "Any L2 signal"} | ${results.filter(any).length} / ${n} | ${pct(results.filter(any).length)} |
| Score >= 30 (popup) | ${results.filter(pop).length} / ${n} | ${pct(results.filter(pop).length)} |
| Score >= 50 | ${results.filter((r) => r.score >= 50).length} / ${n} | ${pct(results.filter((r) => r.score >= 50).length)} |
| ${legitMode ? "No signal (correctly clean)" : "No signal (missed)"} | ${results.filter((r) => !any(r)).length} / ${n} | ${pct(results.filter((r) => !any(r)).length)} |
| On official list (skipped by detector) | ${results.filter((r) => r.official).length} / ${n} | ${pct(results.filter((r) => r.official).length)} |
| Not on official list (really scored) | ${results.filter((r) => !r.official).length} / ${n} | ${pct(results.filter((r) => !r.official).length)} |

By batch:

${gHead("batch")}
${group((r) => r.batch)}

## 3. Per URL (L2 result)
| id | url | score | on official list | L2 signals |
|---|---|---|---|---|
${results.map((r) => `| ${r.id} | ${code(r.url)} | ${r.score} | ${r.official ? "yes" : "no"} | ${sigText(r)} |`).join("\n")}

## 4. Components per URL
\`name\` = registrable label (on a platform host: the label in front of the platform). \`sub\` = labels in front of that.

| id | scheme | sub | name | suffix | tld | suffix group | path kind | file | ext | hyph | digits | bait words |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
${results.map(({ id, c }) => `| ${id} | ${c.scheme} | ${c.sub || "-"} | ${code(c.name)} | ${c.suffix} | ${c.tld} | ${c.group} | ${c.pathKind} | ${c.file ? code(c.file) : "-"} | ${c.ext || "-"} | ${c.hyphens} | ${c.digits} | ${c.bait.join(", ") || "-"} |`).join("\n")}

## 5. Grouped by suffix and TLD
### 5.1 Suffix group
${gHead("suffix group")}
${group((r) => r.c.group)}

### 5.2 Suffix (full, e.g. \`blogspot.com\`)
${gHead("suffix")}
${group((r) => r.c.suffix)}

### 5.3 TLD (last label only)
${gHead("tld")}
${group((r) => "." + r.c.tld)}

## 6. Grouped by other components
### 6.1 Scheme
${gHead("scheme")}
${group((r) => r.c.scheme)}

### 6.2 Subdomain present
${gHead("has subdomain")}
${group((r) => (r.c.sub ? "yes" : "no"))}

### 6.3 Hyphens in the name
${gHead("hyphens")}
${group((r) => r.c.hyphens)}

### 6.4 Digits in the host
${gHead("digits in host")}
${group((r) => (r.c.hasDigit ? "has digits" : "no digits"))}

### 6.5 Path kind
${gHead("path kind")}
${group((r) => r.c.pathKind)}

### 6.6 File extension
${gHead("extension")}
${group((r) => r.c.ext || "none")}

### 6.7 Credential-step file name (code, otp, pin, info, confirm...)
${gHead("credential file")}
${group((r) => (r.c.credFile ? "yes" : "no"))}

### 6.8 Trailing slash after a file name
${gHead("slash after file")}
${group((r) => (r.c.trailingSlash && r.c.ext ? "yes" : "no"))}

### 6.9 Bait word in host or path (\`link-rules.json\` baitWords)
${gHead("bait word")}
${group((r) => (r.c.bait.length ? "yes" : "no"))}

## 6.10 On official list (detector skips these)
${gHead("on official list")}
${group((r) => (r.official ? "yes" : "no"))}

## 7. ${legitMode ? "Flagged by L2 (false positives)" : "Missed by L2 (no signal)"}
${results.filter((r) => (legitMode ? any(r) : !any(r))).map((r) => `- ${r.id} ${code(r.url)}${legitMode ? " " + sigText(r) : ""}`).join("\n") || "none"}
${END}`;

let manual = `

## Kesimpulan (manual, tidak ditimpa script)
Belum diisi.
`;
if (fs.existsSync(reportFile)) {
    const old = fs.readFileSync(reportFile, "utf8");
    const i = old.indexOf(END);
    if (i >= 0) manual = old.slice(i + END.length);
    const head = old.slice(0, old.indexOf(START));
    fs.writeFileSync(reportFile, head + out + manual);
} else {
    fs.writeFileSync(reportFile, `# Tes layer 2 pada ${labelText} link (${path.basename(datasetFile)})\n\n## Apa yang dikerjakan\nBelum diisi.\n\n` + out + manual);
}
console.log(`ok: ${n} urls, any=${results.filter(any).length}, >=30=${results.filter(pop).length}, ${totalMs.toFixed(1)} ms -> ${reportFile}`);
