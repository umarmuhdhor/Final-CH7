// Fills the "Screen by screen" tables of figma-parity-2026-11-10.md (between the screens:start / screens:end
// markers) from figma-parity-1110-map.json (frame -> app shot) and img/figma-parity-1110/notes.json
// ({frameId: {shot, status, note}}). Also writes the status totals into the line under the marker.
//   node plan/alief/qa/figma-parity-1110-report.mjs
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const read = (p) => JSON.parse(readFileSync(join(here, p), "utf8"));
const map = read("figma-parity-1110-map.json");
const notes = read("img/figma-parity-1110/notes.json");
const doc = join(here, "figma-parity-2026-11-10.md");

const FILE = "https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=";
const MARK = { same: "✅ same", small: "🟡 small diff", clear: "🟠 clear diff", missing: "🔴 missing", notshot: "⚪ not shot" };
const img = "img/figma-parity-1110";
const cell = (s) => String(s ?? "").replace(/\|/g, "\\|").replace(/\n/g, " ");

const totals = Object.fromEntries(Object.keys(MARK).map((k) => [k, 0]));
let out = "";
for (const [section, rows] of Object.entries(map)) {
  if (section.startsWith("_")) continue;
  out += `\n### ${section}\n\n| Frame | App now | Figma | Status | Notes |\n|---|---|---|---|---|\n`;
  for (const [id, name, mapped] of rows) {
    const n = notes[id];
    if (!n) throw new Error(`no note for ${id}`);
    const shot = n.shot === undefined ? mapped : n.shot;
    totals[n.status] = (totals[n.status] ?? 0) + 1;
    const app = shot ? `<img src="${img}/${shot}.jpg" width="160"><br>\`${shot}\`` : "no screenshot";
    const fig = `<img src="${img}/figma/${id.replace(/:/g, "-")}.jpg" width="160">`;
    out += `| [${cell(name)}](${FILE}${id.replace(":", "-")})<br>\`${id}\` | ${app} | ${fig} | ${MARK[n.status] ?? n.status} | ${cell(n.note)} |\n`;
  }
}
const total = Object.values(totals).reduce((a, b) => a + b, 0);
const summary = `\n**${total} frames:** ${Object.entries(totals).filter(([, v]) => v).map(([k, v]) => `${v} ${MARK[k]}`).join(" · ")}.\n`;

const text = readFileSync(doc, "utf8");
const start = "<!-- screens:start -->";
const end = "<!-- screens:end -->";
const a = text.indexOf(start);
const b = text.indexOf(end);
if (a < 0 || b < a) throw new Error("markers not found");
writeFileSync(doc, text.slice(0, a + start.length) + "\n" + summary + out + "\n" + text.slice(b));
console.log(summary.trim());
