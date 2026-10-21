// Inlines detector/data/brands.json into detector/src/detector.js so the result is ONE plain script
// (Safari content scripts can't import). Used by sync-to-extension.sh (prints to stdout) and by the tests (build()).
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const here = (p) => fileURLToPath(new URL(p, import.meta.url));
const PLACEHOLDER = "/*__BRANDS_JSON__*/ null";

export function build() {
    const src = readFileSync(here("../src/detector.js"), "utf8");
    if (!src.includes(PLACEHOLDER)) throw new Error(`src/detector.js must contain ${PLACEHOLDER}`);
    const data = JSON.parse(readFileSync(here("../data/brands.json"), "utf8"));
    return src.replace(PLACEHOLDER, () => JSON.stringify(data));
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) process.stdout.write(build());
