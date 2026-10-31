// v2: v1 (whole-URL dissector) + free-host awareness. On a free host (blogspot, cloudfront, github.io ...) the domain
// belongs to the host, not the scammer, so the part that says something is the first label and the file name.
import { dissect } from "./dissect-lib.mjs";

const FREE_HOSTS = [
    "blogspot.com", "blogspot.co.id", "github.io", "netlify.app", "pages.dev", "vercel.app", "web.app", "firebaseapp.com",
    "weebly.com", "wixsite.com", "wordpress.com", "herokuapp.com", "glitch.me", "workers.dev", "cloudfront.net",
    "r2.dev", "webflow.io", "000webhostapp.com", "sites.google.com", "s3.amazonaws.com",
];
// Indonesian scam bait. Matched as a substring of the label (labels have no separators: "gratiskuota60gb"), so 5+ letters only.
const BAIT = [
    "gratis", "bantuan", "bansos", "kuota", "hadiah", "undian", "klaim", "promo", "pulsa", "saldo", "subsidi", "pencairan",
    "verifikasi", "resmi", "official", "bonus", "giveaway", "reward", "voucher", "cashback", "kurir", "paket", "tracking",
    "lowongan", "pinjaman", "pinjol", "kripto", "prakerja", "login", "update", "claim", "free",
];
// Courier / carrier names that are not in brands.json (DHL was the miss).
const CARRIERS = ["dhl", "fedex", "sicepat", "anteraja", "ninjaxpress", "wahana", "tiki"];

const hits = (s, list) => list.filter((w) => s.includes(w));

export function dissect2(raw) {
    const base = dissect(raw);
    const extras = [];
    const add = (part, weight, why) => extras.push({ part, weight, why });
    let u;
    try { u = new URL(raw); } catch { return base; }
    const host = u.hostname.toLowerCase();
    const free = FREE_HOSTS.find((h) => host === h || host.endsWith("." + h));
    if (free) {
        const label = host.slice(0, host.length - free.length - 1).split(".").pop() || "";
        const stem = (u.pathname.split("/").filter(Boolean).pop() || "").toLowerCase();
        const inLabel = [...hits(label, BAIT), ...hits(label, CARRIERS)];
        const inPath = [...hits(stem, BAIT), ...hits(stem, CARRIERS)];
        add("freehost", 3, `free host ${free}`);
        if (inLabel.length) add("free-label", inLabel.length >= 2 ? 16 : 10, `bait in subdomain "${label}": ${inLabel.join("+")}`);
        if (/20\d\d|\d+(gb|mb|jt|rb)/.test(label)) add("free-number", 5, "year / quantity inside the name");
        if (inPath.length) add("free-path", 10, `bait in file name "${stem.slice(0, 24)}": ${inPath.join("+")}`);
    }
    return { score: Math.min(100, base.score + extras.reduce((a, p) => a + p.weight, 0)), parts: [...base.parts, ...extras] };
}
