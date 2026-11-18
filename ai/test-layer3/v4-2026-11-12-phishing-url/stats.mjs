// Aggregates snapshots/ + .probe/ into numbers for ANALISIS.md (counts only, no URL or host is printed). Use: NODE_OPTIONS=--max-old-space-size=8192 node stats.mjs [out.json]

import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path"; import { fileURLToPath } from "node:url";
const V4 = dirname(fileURLToPath(import.meta.url));
const OUT = process.argv[2] ?? V4 + "/.hasil/stats.json";
const inc = (o, k, n = 1) => (o[k] = (o[k] || 0) + n);
const FREE = ["blogspot.","vercel.app","netlify.app","pages.dev","github.io","weebly.com","weeblysite.com","wixsite.com","wordpress.com","webflow.io","herokuapp.com","firebaseapp.com","web.app","glitch.me","000webhostapp.com","godaddysites.com","sites.google.com","workers.dev","onrender.com","repl.co","replit.app","carrd.co","framer.app","framer.website","ucoz.","jimdofree.com","yolasite.com","webcindario.com","myshopify.com","square.site","mystrikingly.com","surge.sh","infinityfreeapp.com","rf.gd","epizy.com","wuaze.com","lovestoblog.com","hstn.me","16mb.com","000webhost","ipfs.","r2.dev","azurewebsites.net","cloudfront.net","s3.amazonaws.com","storage.googleapis.com","appspot.com","web.core.windows.net","fleek.co","on.fleek.co","edgeone.app","bubbleapps.io","wixstudio.io","webwave.me","site123.me","tilda.ws","dynv6.net","duckdns.org","ngrok","trycloudflare.com","gitbook.io","notion.site","typedream.app","hubspotpagebuilder.com","canva.site","my.canva.site","godaddysites","zyrosite.com","hostingersite.com","pythonanywhere.com","vercel.dev","now.sh","surge","neocities.org","gq","tk","ml","cf","ga"].filter((x) => x.length > 3 || false);
const freeHost = (h) => FREE.some((f) => h.includes(f.endsWith(".") ? f : f));
// --- alive set
const alive = new Map();
for (const l of readFileSync(V4 + "/links-alive.csv", "utf8").split("\n").slice(1).filter(Boolean)) alive.set(l.split(",")[0], l.slice(l.lastIndexOf(",") + 1));
const L = () => ({ n: 0, ok: 0, kosong: 0, gagal: 0, reasons: {}, openNonOff: 0, official: 0, caught: 0, caughtNoNew: 0, caughtOnlyNew: 0, noSignal: 0, maxScore: 0, sig: {}, sigCaught: {}, combo: {}, caughtIds: [], free: { n: 0, open: 0, nonOff: 0, caught: 0 }, pwd: { n: 0, caught: 0, low: 0, f1: 0, f2: 0, f3: 0, lowFree: 0, lowSigOnlyPwd: 0 }, age: {}, rdap: { ok: 0, gagal: 0, dilewati: 0, mati: 0 }, tld: {}, tldFail: {}, evid: {}, scheme: {}, www: {}, schemeWww: {}, movedHost: 0, iframes: 0, ekstrem: 0, scores: {}, hours: {} });
const A = { scam: L(), legit: L() };
const bucketAge = (d) => (d < 30 ? "<30" : d < 90 ? "30-89" : d < 365 ? "90-364" : d < 1825 ? "1-5y" : ">=5y");
const files = readdirSync(V4 + "/snapshots");
let skippedNotAlive = 0, seen = 0;
const hour = {};
for (const f of files) {
  const id = f.replace(".json", "");
  if (!alive.has(id)) { skippedNotAlive++; continue; }
  const r = JSON.parse(readFileSync(V4 + "/snapshots/" + f, "utf8"));
  const a = A[alive.get(id) === "legit" ? "legit" : "scam"];
  seen++;
  a.n++; a[r.status]++;
  let host = ""; let scheme = "";
  try { const u = new URL(r.originalUrl); host = u.hostname.toLowerCase(); scheme = u.protocol.replace(":", ""); } catch {}
  const www = host.startsWith("www.");
  const free = freeHost(host);
  if (r.status === "gagal") { inc(a.reasons, String(r.reason).replace(/^http_(\d)\d\d$/, "http_$1xx")); if (r.reason === "teks_ekstrem") a.ekstrem++; }
  inc(a.scheme, scheme + ":" + (r.status === "gagal" ? "gagal" : "open"));
  inc(a.www, (www ? "www" : "nowww") + ":" + (r.status === "gagal" ? "gagal" : "open"));
  inc(a.schemeWww, scheme + "|" + (www ? "www" : "nowww") + ":" + (r.status === "gagal" ? "gagal" : "open"));
  if (free) { a.free.n++; }
  if (r.status === "gagal") continue;
  if (free) a.free.open++;
  if (r.movedHost) a.movedHost++;
  if ((r.iframes || []).length) a.iframes++;
  const l3 = r.l3;
  if (l3.official) { a.official++; continue; }
  a.openNonOff++;
  if (free) a.free.nonOff++;
  const sigs = l3.signals || [];
  const ids = sigs.map((s) => s.id).sort();
  if (!ids.length) a.noSignal++;
  a.maxScore = Math.max(a.maxScore, l3.score);
  inc(a.scores, String(l3.score));
  for (const s of sigs) { inc(a.sig, s.id); if (l3.caught) inc(a.sigCaught, s.id); if (s.evidence && String(s.evidence).length <= 30 && !/[./@:]/.test(String(s.evidence))) { a.evid[s.id] = a.evid[s.id] || {}; inc(a.evid[s.id], String(s.evidence).toLowerCase()); } }
  const hasPwd = sigs.some((s) => s.id === "asks_password");
  const forms = r.snapshot?.forms || [];
  const fcount = forms.reduce((x, fm) => x + (fm.fields || []).length, 0);
  if (hasPwd || forms.some((fm) => (fm.fields || []).some((q) => q.type === "password"))) {
    a.pwd.n++;
    if (l3.caught) a.pwd.caught++;
    else { a.pwd.low++; if (fcount <= 1) a.pwd.f1++; else if (fcount === 2) a.pwd.f2++; else a.pwd.f3++; if (free) a.pwd.lowFree++; if (ids.length === 1 && ids[0] === "asks_password") a.pwd.lowSigOnlyPwd++; }
  }
  if (free && l3.caught) a.free.caught++;
  if (l3.caught) {
    a.caught++;
    if (l3.scoreNoAge >= 30) a.caughtNoNew++; else a.caughtOnlyNew++;
    inc(a.combo, ids.join("+") || "(kosong)");
    if (a.caughtIds.length < 40) a.caughtIds.push(id + ":" + l3.score);
  }
  const rd = r.rdap?.status || "mati";
  inc(a.rdap, rd);
  const dom = (r.snapshot?.domain || "").toLowerCase(); const tld = dom.split(".").pop() || "?";
  if (rd === "ok" || rd === "gagal") { inc(a.tld, tld); if (rd === "gagal") inc(a.tldFail, tld); }
  if (rd === "ok" && r.rdap.ageDays != null) { const b = bucketAge(r.rdap.ageDays); a.age[b] = a.age[b] || { n: 0, caught: 0, newDomain: 0 }; a.age[b].n++; if (l3.caught) a.age[b].caught++; if (ids.includes("new_domain")) a.age[b].newDomain++; }
  // RDAP failure by 30-minute bucket (UTC), all labels together
  if (rd === "ok" || rd === "gagal") { const t = new Date(r.fetchedAt); const k = t.toISOString().slice(5, 13) + (t.getUTCMinutes() < 30 ? ":00" : ":30"); hour[k] = hour[k] || { n: 0, g: 0 }; hour[k].n++; if (rd === "gagal") hour[k].g++; }
  const key = scheme + "|" + (www ? "www" : "nowww");
  a.schemeCaught = a.schemeCaught || {}; inc(a.schemeCaught, key + ":nonOff"); if (l3.caught) inc(a.schemeCaught, key + ":caught");
}
// --- probe level by scheme/www
function parseCsv(text) { const rows = []; let row = [], cell = "", q = false; for (let i = 0; i < text.length; i++) { const c = text[i]; if (q) { if (c === '"' && text[i + 1] === '"') { cell += '"'; i++; } else if (c === '"') q = false; else cell += c; } else if (c === '"') q = true; else if (c === ",") { row.push(cell); cell = ""; } else if (c === "\n" || c === "\r") { if (c === "\r" && text[i + 1] === "\n") i++; row.push(cell); if (row.some((x) => x !== "")) rows.push(row); row = []; cell = ""; } else cell += c; } row.push(cell); if (row.some((x) => x !== "")) rows.push(row); return rows; }
const rows = parseCsv(readFileSync(V4 + "/links.csv", "utf8")); const head = rows[0];
const iId = head.indexOf("id"), iUrl = head.indexOf("url"), iLab = head.indexOf("label");
const dns = new Map(readFileSync(V4 + "/.probe/dns.jsonl", "utf8").split("\n").filter(Boolean).map((l) => { const j = JSON.parse(l); return [j.h, j.s]; }));
const http = new Map(readFileSync(V4 + "/.probe/http.jsonl", "utf8").split("\n").filter(Boolean).map((l) => { const j = JSON.parse(l); return [j.id, j]; }));
const P = { scam: {}, legit: {} };
for (const r of rows.slice(1)) {
  let u; try { u = new URL(r[iUrl]); } catch { continue; }
  const lab = r[iLab] === "legit" ? "legit" : "scam"; const h = u.hostname.replace(/\.$/, "").toLowerCase();
  const key = u.protocol.replace(":", "") + "|" + (h.startsWith("www.") ? "www" : "nowww");
  const p = (P[lab][key] = P[lab][key] || { n: 0, dnsMati: 0, alive: 0 });
  p.n++;
  const d = dns.get(h); if (d === "nxdomain") p.dnsMati++;
  const hr = http.get(String(r[iId]).trim()); if (d === "ok" && hr && ((hr.st >= 300 && hr.st < 400) || (hr.st >= 200 && hr.st < 300 && /html/.test(hr.ct || "")))) p.alive++;
}
const summary = JSON.parse(readFileSync(V4 + "/.probe/summary.json", "utf8"));
writeFileSync(OUT, JSON.stringify({ A, P, summary, hour, seen, skippedNotAlive }, null, 1));
console.log("alive-set snapshots", seen, "bukan hidup (dilewati)", skippedNotAlive);
for (const k of ["scam", "legit"]) { const a = A[k]; console.log(k, "n", a.n, "ok", a.ok, "kosong", a.kosong, "gagal", a.gagal, "| resmi", a.official, "nonResmi", a.openNonOff, "| tertangkap", a.caught, "tanpaNew", a.caughtNoNew, "hanyaNew", a.caughtOnlyNew, "| tanpaSinyal", a.noSignal, "maks", a.maxScore, "| teks_ekstrem", a.ekstrem); }
