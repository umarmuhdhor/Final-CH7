// Publishes the shared-host list (platforms where anyone can host a page) as JSON for the backend's
// admin.shared_hosts_set(). Source of truth stays in code; a test fails if this file goes stale.
// Run: node scripts/build-shared-hosts.mjs
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { SHARED_HOSTS } from "../src/blocklist/allowlist.js";
import { USER_CONTENT } from "../src/layer3/official.js";

export function sharedHostList() {
    const hosts = new Set();
    for (const raw of [...SHARED_HOSTS, ...USER_CONTENT]) {
        const h = raw.toLowerCase().replace(/^www\./, "");
        if (h) hosts.add(h);
    }
    return [...hosts].sort();
}

const OUT = new URL("../data/shared-hosts.json", import.meta.url);

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    const doc = {
        version: 1,
        source: "ai/src/blocklist/allowlist.js SHARED_HOSTS + ai/src/layer3/official.js USER_CONTENT",
        hosts: sharedHostList(),
    };
    writeFileSync(OUT, JSON.stringify(doc, null, 2) + "\n");
    console.log(`wrote ${doc.hosts.length} hosts`);
}
