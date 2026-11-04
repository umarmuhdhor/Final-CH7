// Baca dataset ai/test-layer2, cek DNS tiap host tanpa membuka situs, tulis <versi>/links.json.
//   node ai/test-layer-live/scripts/links.mjs [v1]
import { lookup } from "node:dns/promises";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const version = process.argv[2] || "v1";
const dataset = join(here, "..", "..", "test-layer2");

function rows(file, prefix, label) {
    return readFileSync(join(dataset, file), "utf8")
        .split("\n")
        .map((line) => line.split("|").map((cell) => cell.trim()))
        .filter((cells) => /^\d+$/.test(cells[1] ?? "") && /^https?:\/\//.test(cells[2] ?? ""))
        .map((cells) => ({ id: `${prefix}-${cells[1]}`, label, url: cells[2], host: new URL(cells[2]).hostname, note: cells[5] ?? "" }));
}

async function resolves(host) {
    const timeout = new Promise((_, reject) => setTimeout(() => reject(new Error("timeout")), 5000));
    try {
        await Promise.race([lookup(host), timeout]);
        return true;
    } catch {
        return false;
    }
}

const links = [...rows("dataset.md", "scam", "scam"), ...rows("dataset-legit.md", "legit", "legit")];
const scam = links.filter((l) => l.label === "scam").length;
const legit = links.length - scam;
if (scam !== 25 || legit !== 23) throw new Error(`sampel harus 25 + 23, dapat ${scam} + ${legit}`);

for (const link of links) link.resolves = await resolves(link.host);
writeFileSync(join(here, "..", version, "links.json"), JSON.stringify(links, null, 2) + "\n");
const alive = links.filter((l) => l.resolves);
console.log(`${scam} scam + ${legit} legit, DNS hidup: ${alive.filter((l) => l.label === "scam").length} scam, ${alive.filter((l) => l.label === "legit").length} legit`);
