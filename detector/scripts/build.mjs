// Inlines detector/data/brands.json + link-rules.json into detector/src/detector.js so the result is ONE plain script
// (Safari content scripts can't import). Used by sync-to-extension.sh (prints to stdout) and by the tests (build()).
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const here = (p) => fileURLToPath(new URL(p, import.meta.url));
const PLACEHOLDERS = [
    ["/*__BRANDS_JSON__*/ null", "../data/brands.json"],
    ["/*__LINK_RULES_JSON__*/ null", "../data/link-rules.json"],
];

export function build() {
    let src = readFileSync(here("../src/detector.js"), "utf8");
    for (const [placeholder, file] of PLACEHOLDERS) {
        if (!src.includes(placeholder)) throw new Error(`src/detector.js must contain ${placeholder}`);
        const data = JSON.parse(readFileSync(here(file), "utf8"));
        src = src.replace(placeholder, () => JSON.stringify(data));
    }
    return src;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) process.stdout.write(build());
