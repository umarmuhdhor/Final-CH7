// Prototype: layer 2 as a whole-URL dissector. Each part scores on its own, with a cap per part. Not in the repo.
import { readFileSync } from "node:fs";

const data = JSON.parse(readFileSync("/Users/imelda/Documents/Swift/Final-CH/Final-CH7/detector/data/brands.json", "utf8"));
const CHEAP = new Set([...data.cheapTlds, "info", "pw", "cc", "ws", "su"]);
const BAIT = new Set(data.keywords);
const SUFFIXES = new Set(data.suffixes);
const FILE_EXT = /\.(html?|php\d?|aspx?|jsp)$/i;

const entropy = (s) => {
    const f = {};
    for (const c of s) f[c] = (f[c] || 0) + 1;
    return -Object.values(f).reduce((a, n) => a + (n / s.length) * Math.log2(n / s.length), 0);
};

export function dissect(raw) {
    const parts = []; // { part, weight, why }
    const add = (part, weight, why) => parts.push({ part, weight, why });
    let u;
    try { u = new URL(raw); } catch { return { score: 0, parts: [{ part: "url", weight: 0, why: "unparseable" }] }; }

    // scheme
    if (u.protocol === "http:") add("scheme", 5, "http without TLS");
    // userinfo
    if (u.username || u.password) add("userinfo", 25, "user@ before the host hides the real host");
    // host
    const host = u.hostname.toLowerCase().replace(/\.+$/, "");
    const labels = host.split(".");
    if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host) || host.includes(":")) add("host", 20, "IP address as host");
    else {
        const suffixLen = labels.length > 2 && SUFFIXES.has(labels.slice(-2).join(".")) ? 2 : 1;
        const tld = labels[labels.length - 1];
        const name = labels.slice(0, -suffixLen);
        if (labels.some((l) => l.startsWith("xn--"))) add("host", 10, "punycode label");
        if (name.length >= 4) add("host", 8, `${name.length} labels before the suffix`);
        if (name.some((l) => (l.match(/-/g) || []).length >= 3)) add("host", 8, "3+ hyphens in a label");
        if (name.some((l) => l.length >= 8 && (l.match(/\d/g) || []).length / l.length >= 0.4)) add("host", 8, "digit-heavy label");
        if (suffixLen === 1 && CHEAP.has(tld)) add("tld", 6, `.${tld} is a cheap/rare TLD`);
    }
    // port
    if (u.port && !["80", "443"].includes(u.port)) add("port", 10, `port ${u.port}`);
    // path
    const segs = u.pathname.split("/").filter(Boolean);
    const last = segs[segs.length - 1] || "";
    const stem = last.replace(FILE_EXT, "");
    if (stem.length >= 20 && /^[a-z0-9_-]+$/i.test(stem) && entropy(stem) >= 3.3 && /\d/.test(stem)) add("path", 15, `random-looking name "${stem.slice(0, 12)}…" (${stem.length} chars, entropy ${entropy(stem).toFixed(1)})`);
    if (FILE_EXT.test(last)) add("path-ext", 5, `ends in ${last.match(FILE_EXT)[0]}`);
    if (FILE_EXT.test(last) && u.pathname.endsWith("/")) add("path-slash", 8, "slash after a file name");
    if (segs.some((s) => s.split(/[^a-z]+/i).some((w) => BAIT.has(w.toLowerCase())))) add("path-bait", 6, "bait word in path");
    // query
    const q = [...u.searchParams];
    if (q.some(([k, v]) => /^(url|redirect|redir|next|return|goto|link|u)$/i.test(k) && /^(https?:)?\/\//i.test(v))) add("query", 12, "redirect to another URL");
    if (q.some(([, v]) => /\S+@\S+/.test(v))) add("query", 5, "email in query");
    if (u.search.length > 150) add("query", 5, "very long query");
    // fragment
    if (/https?:/i.test(u.hash)) add("fragment", 8, "URL inside the fragment");
    // total length
    if (raw.length > 120) add("length", 4, `${raw.length} chars`);

    // cap per part so one part cannot dominate
    const byPart = {};
    for (const p of parts) byPart[p.part] = Math.min(25, (byPart[p.part] || 0) + p.weight);
    return { score: Math.min(100, Object.values(byPart).reduce((a, b) => a + b, 0)), parts };
}

