// Fase 18a step 12 + 13: builds the pageReplicaBase64 that replica-e2e.sh posts, with the extension's own
// code (read-only import from ios/ShooExtension/Resources, like Tests/replica.test.mjs:5-6).
// Usage: node plan/alief/qa/replica-input.mjs <sample|worst|bomb> <out dir>
// Writes <out>/<kind>.b64 (the base64 text, no newline) and prints one JSON line with the sizes.
import { writeFileSync } from "node:fs";
import { createGzip } from "node:zlib";

await import("../../../ios/ShooExtension/Resources/replica.js");
const { buildReplica, gzipBase64 } = await import("../../../ios/ShooExtension/Resources/replica-build.js");
const { capture } = globalThis.ShooReplica;

const MAX_BASE64 = 409_600;
const MAX_HTML_BYTES = 3_145_728;
const [kind, out] = process.argv.slice(2);
if (!["sample", "worst", "bomb"].includes(kind) || !out) {
  console.error("usage: node replica-input.mjs <sample|worst|bomb> <out dir>");
  process.exit(2);
}

// Same DOM stand-in as ios/ShooExtension/Tests/replica.test.mjs:9-27.
const text = (data) => ({ nodeType: 3, data });
function h(localName, attrs = {}, ...children) {
  return {
    nodeType: 1,
    localName,
    attributes: Object.entries(attrs).map(([name, value]) => ({ name, value })),
    childNodes: children.map((c) => (typeof c === "string" ? text(c) : c)),
    getAttribute: (key) => attrs[key] ?? null,
    getBoundingClientRect: () => ({ width: 300, height: 150 }),
  };
}
const page = { url: "https://bca-verifikasi.site/login", viewport: { width: 390, height: 844 }, scrollY: 0, now: new Date().toISOString() };
const docOf = (body, headChildren = []) => ({
  documentElement: h("html", { lang: "id" }, h("head", {}, ...headChildren), body),
  baseURI: page.url,
  doctype: {},
});
// No network: stylesheets and images fail, as when the page is gone.
const offline = { fetchText: async () => { throw new Error("offline"); }, fetchImage: async () => null };

/** A login page like the ones Shoo blocks: typed input must not reach the replica. */
async function sample() {
  const draft = capture(
    docOf(
      h("body", {},
        h("h1", {}, "Verifikasi akun BCA"),
        h("form", { action: "https://bca-verifikasi.site/collect" },
          h("input", { name: "user", value: "typed-user-id" }),
          h("input", { type: "password", name: "pin", value: "123456" }),
          h("input", { type: "submit", value: "Masuk" })),
        h("script", {}, "steal()"),
        h("p", {}, "Akun Anda akan diblokir dalam 24 jam.")),
      [h("title", {}, "KlikBCA")],
    ),
    page,
  );
  return buildReplica(draft, offline);
}

/**
 * Worst case for the backend: 409 600 base64 characters that inflate to exactly 3 145 728 bytes.
 * Random ASCII (barely compressible) followed by filler; the random part is tuned until the gzip is
 * 307 198..307 200 bytes, which is 409 600 characters of base64.
 */
async function worst() {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  const packedAt = async (n) => {
    const rnd = new Uint8Array(n);
    for (let o = 0; o < n; o += 65536) crypto.getRandomValues(rnd.subarray(o, Math.min(n, o + 65536)));
    let head = "";
    for (let o = 0; o < n; o++) head += alphabet[rnd[o] & 63];
    return gzipBase64(head + "a".repeat(MAX_HTML_BYTES - n));
  };
  // Binary search gets close; random content makes the size a little noisy, so then walk around it.
  let lo = 300_000;
  let hi = MAX_HTML_BYTES;
  while (lo < hi) {
    const n = Math.floor((lo + hi) / 2);
    const packed = await packedAt(n);
    if (packed.length === MAX_BASE64) return packed;
    if (packed.length < MAX_BASE64) lo = n + 1;
    else hi = n - 1;
  }
  for (let d = 0; d < 400; d++) {
    const packed = await packedAt(lo + (d % 2 ? d : -d));
    if (packed.length === MAX_BASE64) return packed;
  }
  throw new Error("no worst-case replica found");
}

/** gzip of zeros, streamed, as large as fits in 307 200 bytes: inflates to ±300 MB (K2 bomb). */
async function bomb() {
  const gz = createGzip({ level: 9 });
  const parts = [];
  let size = 0;
  gz.on("data", (b) => { parts.push(b); size += b.length; });
  const done = new Promise((resolve) => gz.on("end", resolve));
  const mb = Buffer.alloc(1 << 20);
  for (let i = 0; i < 298; i++) if (!gz.write(mb)) await new Promise((r) => gz.once("drain", r));
  gz.end();
  await done;
  const bytes = Buffer.concat(parts, size);
  if (bytes.length > 307_200) throw new Error(`bomb too large: ${bytes.length}`);
  return bytes.toString("base64");
}

const base64 = await { sample, worst, bomb }[kind]();
if (!base64) throw new Error("buildReplica returned null");
writeFileSync(`${out}/${kind}.b64`, base64);
console.log(JSON.stringify({ kind, base64Chars: base64.length, gzipBytes: Buffer.from(base64, "base64").length }));
