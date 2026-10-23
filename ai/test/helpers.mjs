// Test helpers for ai/. Fixtures are built here, never read from real browsing.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export const FIXTURES = fileURLToPath(new URL("../../contracts/fixtures/", import.meta.url));
export const readFixture = (name) => JSON.parse(readFileSync(FIXTURES + name, "utf8"));
export const BRANDS = JSON.parse(readFileSync(fileURLToPath(new URL("../../detector/data/brands.json", import.meta.url)), "utf8"));

/** One form field with the contract's shape; override what a test cares about. */
export function field(over = {}) {
    return { type: "text", name: null, id: null, label: null, placeholder: null, autocomplete: null, accept: null, capture: null, ...over };
}

/** A PageSnapshot (contracts/detector-interface.md) with one form holding `fields`. */
export function page(url, fields = [], over = {}) {
    const host = new URL(url).hostname.replace(/^www\./, "");
    return {
        url,
        domain: host,
        title: "",
        lang: null,
        text: "",
        forms: fields.length ? [{ action: null, fields }] : [],
        imageAlts: [],
        capturedAt: "2026-10-22T00:00:00.000Z",
        ...over,
    };
}

export const SCAM_URL = "https://verif-akun-aman.example.xyz/login";

export function post(app, body, init = {}) {
    const raw = typeof body === "string" ? body : JSON.stringify(body);
    return app.request("/analyze", { method: "POST", headers: { "content-type": "application/json", ...(init.headers || {}) }, body: raw });
}

export const ids = (signals) => signals.map((s) => s.id);

/**
 * Fastest of `runs` timings of `fn`, in ms. CPU budget tests use it so a busy machine (scheduler, GC) does not fail
 * them: a real slow path (ReDoS, quadratic scan) is slow on every run, noise is not.
 */
export async function fastestMs(fn, runs = 5) {
    let best = Infinity;
    for (let i = 0; i < runs; i++) {
        const t0 = performance.now();
        await fn();
        best = Math.min(best, performance.now() - t0);
    }
    return best;
}
