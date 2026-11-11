// node --test ios/ShooExtension/Tests/*.test.mjs
// background.js as Safari runs it: the module, a fake `browser`, a fake server. Each `boot()` is a new
// background page over the same storage, the way Safari stops and restarts it.
import { test } from "node:test";
import assert from "node:assert/strict";

const SESSION = { ok: true, deviceId: "dev_1", token: "t", mode: "guardian", name: "Rina", apiBaseURL: "https://api.test", aiBaseURL: null };
let generation = 0;

function world() {
    const store = {};
    const posts = [];
    const state = { session: SESSION };
    const local = {
        get: async (keys) => {
            const names = keys == null ? Object.keys(store) : [keys].flat();
            return structuredClone(Object.fromEntries(names.filter((k) => k in store).map((k) => [k, store[k]])));
        },
        set: async (items) => void Object.assign(store, structuredClone(items)),
        remove: async (keys) => { for (const key of [keys].flat()) delete store[key]; },
        clear: async () => { for (const key of Object.keys(store)) delete store[key]; },
    };
    async function boot() {
        let listener;
        globalThis.browser = {
            storage: { local },
            runtime: {
                sendNativeMessage: async (_app, message) => (message.type === "getSession" ? state.session : { ok: true }),
                onMessage: { addListener: (fn) => (listener = fn) },
                getURL: (path) => `safari-web-extension://x/${path}`,
            },
            permissions: { contains: async () => true },
        };
        globalThis.fetch = async (url, init = {}) => {
            if (init.method === "POST" && url.endsWith("/scans")) {
                posts.push(JSON.parse(init.body));
                const notified = state.notified === undefined ? {} : { notified: state.notified };
                return new Response(JSON.stringify({ id: `scan_${posts.length}`, ...notified }), { status: 201 });
            }
            return new Response(JSON.stringify({ domains: [], nextSince: null, verdict: null }), { status: 200 });
        };
        await import(`../Resources/background.js?boot=${++generation}`);
        return (message) => listener(message);
    }
    return { store, posts, state, boot };
}

const report = (key, domain = "scam.site", status = "warning") => ({
    type: "report", key,
    scan: { url: `https://${domain}/`, domain, score: 60, status, signals: [], detectedAt: "2026-11-05T00:00:00.000Z" },
    replica: null, fragments: null,
});

/** Lets the POST in startReport finish: it runs after the message is answered. */
const settled = async (send, key) => (await send({ type: "recordId", key })).recordId;

test("the record id still answers after Safari restarted the background page", async () => {
    const w = world();
    const send = await w.boot();
    assert.deepEqual(await send(report("k1")), { ok: true });
    assert.equal(await settled(send, "k1"), "scan_1");
    const restarted = await w.boot();
    assert.equal(await settled(restarted, "k1"), "scan_1");
});

test("a site reported lately goes out without its evidence, which POST /scans would throw away", async () => {
    const w = world();
    const send = await w.boot();
    const withCopy = { ...report("k1"), replica: { html: "<p>page</p>", nonce: "n", resources: [], sheets: [] } };
    await send(withCopy);
    await settled(send, "k1");
    await send({ ...withCopy, key: "k2" });
    await settled(send, "k2");
    assert.equal(w.posts.length, 2);
    assert.ok("pageReplicaBase64" in w.posts[0]);
    assert.ok(!("pageReplicaBase64" in w.posts[1]));
});

test("a failed POST doesn't count as sent: the next visit brings its evidence", async () => {
    const w = world();
    const send = await w.boot();
    const original = globalThis.fetch;
    globalThis.fetch = async () => new Response("{}", { status: 503 });
    await send(report("k1"));
    assert.equal(await settled(send, "k1"), null);
    globalThis.fetch = original;
    assert.equal(w.store["reportLog.v1"]?.domains?.["scam.site"], undefined);
});

test("account deleted: block memory is gone before a page asks for it", async () => {
    const w = world();
    const send = await w.boot();
    await send({ type: "rememberBlock", url: "https://scam.site/", domain: "scam.site", score: 90, signals: [] });
    assert.ok((await send({ type: "recallBlock", url: "https://scam.site/" })).memory);
    w.state.session = { ok: false, error: "not_onboarded" };
    const restarted = await w.boot();
    assert.equal((await restarted({ type: "recallBlock", url: "https://scam.site/" })).memory, null);
    assert.ok(!("blockMemory.v1" in w.store));
});

test("an app that can't be reached says nothing about the account: block memory stays", async () => {
    const w = world();
    const send = await w.boot();
    await send({ type: "rememberBlock", url: "https://scam.site/", domain: "scam.site", score: 90, signals: [] });
    w.state.session = undefined;
    const restarted = await w.boot();
    assert.ok((await restarted({ type: "recallBlock", url: "https://scam.site/" })).memory);
});

test("no message ever answers with the token", async () => {
    const w = world();
    const send = await w.boot();
    const reply = await send({ type: "profile" });
    assert.ok(!("token" in reply));
    assert.equal(reply.onboarded, true);
});

test("#375: POST /scans and block memory use the PSL domain of the URL, not the full host the page sent", async () => {
    const w = world();
    const send = await w.boot();
    const host = "login.bca-verifikasi.site";
    const fromPage = { ...report("k1", host), scan: { ...report("k1", host).scan, domain: host } };
    await send(fromPage);
    await settled(send, "k1");
    assert.equal(w.posts[0].domain, "bca-verifikasi.site");
    await send({ type: "rememberBlock", url: `https://${host}/pin`, domain: host, score: 90, signals: [] });
    const { memory } = await send({ type: "recallBlock", url: `https://${host}/pin` });
    assert.equal(memory.domain, "bca-verifikasi.site");
});

test("#377: the block page's Guardian name is read fresh, not from the 30 s session cache", async () => {
    const w = world();
    w.state.session = { ...SESSION, mode: "protected", guardianName: "Adhella" };
    const send = await w.boot();
    assert.equal((await send({ type: "profile" })).guardianName, "Adhella");
    w.state.session = { ...SESSION, mode: "protected", guardianName: null };
    assert.equal((await send({ type: "profile" })).guardianName, null);
});

test("#377: the record carries who the backend pushed — a name, null, or nothing from an older backend", async () => {
    const w = world();
    const send = await w.boot();
    await send(report("old"));
    await settled(send, "old");
    assert.ok(!("notified" in (await send({ type: "recordId", key: "old" }))));

    w.state.notified = null;
    await send(report("none", "other.site"));
    await settled(send, "none");
    assert.equal((await send({ type: "recordId", key: "none" })).notified, null);

    w.state.notified = { name: "Adhella" };
    await send(report("named", "third.site"));
    await settled(send, "named");
    assert.equal((await send({ type: "recordId", key: "named" })).notified, "Adhella");
    const restarted = await w.boot(); // from the stored log, after Safari restarted the background page
    assert.equal((await restarted({ type: "recordId", key: "named" })).notified, "Adhella");
    assert.equal((await restarted({ type: "recordId", key: "none" })).notified, null);
});
