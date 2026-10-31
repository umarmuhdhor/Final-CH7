#!/usr/bin/env node
// Fase 22 (22a-1): Worker bundle size check. Builds with `wrangler deploy --dry-run --outdir`, prints
// the size of index.js (raw + gzip) and the 5 largest packages, and fails when a limit is passed.
// Usage (from the repo root): node backend/ci/bundle-size.mjs [--json]
// Limits = size after fase 22 O2 + O3 (1 Nov 2026: 267 988 B raw, 88 634 B gzip) + 10 %.
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { gzipSync } from "node:zlib";

const LIMIT_RAW = 295_000;
const LIMIT_GZIP = 97_500;

const api = join(dirname(fileURLToPath(import.meta.url)), "..", "api");
const out = mkdtempSync(join(tmpdir(), "shoo-bundle-"));
try {
  execFileSync("npx", ["wrangler", "deploy", "--dry-run", "--outdir", out], { cwd: api, stdio: ["ignore", "ignore", "inherit"] });
  const js = readFileSync(join(out, "index.js"));
  const raw = js.length;
  const gzip = gzipSync(js, { level: 9 }).length;

  // Source bytes per package from the source map (input size before minify: shows what pulls weight in).
  const map = JSON.parse(readFileSync(join(out, "index.js.map"), "utf8"));
  const perPackage = {};
  map.sources.forEach((source, i) => {
    const m = source.match(/node_modules\/(?:\.pnpm\/[^/]+\/node_modules\/)?((?:@[^/]+\/)?[^/]+)/);
    const name = m ? m[1] : "(app)";
    perPackage[name] = (perPackage[name] ?? 0) + (map.sourcesContent?.[i]?.length ?? 0);
  });
  const top = Object.entries(perPackage).sort((a, b) => b[1] - a[1]).slice(0, 5);

  const ok = raw <= LIMIT_RAW && gzip <= LIMIT_GZIP;
  if (process.argv.includes("--json")) {
    console.log(JSON.stringify({ raw, gzip, limitRaw: LIMIT_RAW, limitGzip: LIMIT_GZIP, ok, top: Object.fromEntries(top) }));
  } else {
    console.log(`index.js ${raw} B (limit ${LIMIT_RAW}), gzip ${gzip} B (limit ${LIMIT_GZIP})`);
    for (const [name, bytes] of top) console.log(`  ${name.padEnd(28)} ${bytes} B source`);
    console.log(ok ? "OK" : "FAIL: bundle over the limit");
  }
  process.exitCode = ok ? 0 : 1;
} finally {
  rmSync(out, { recursive: true, force: true });
}
