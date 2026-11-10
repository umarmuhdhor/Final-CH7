// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { createLive, LIVE_CLOSE_DELAY_MS, LIVE_SCORE_INTERVAL_MS } from "../Resources/live.js";

const ONLINE = { token: "t", apiBaseURL: "https://api.example", aiBaseURL: "https://ai.example" };

/** Fake clock + timers; `sent` collects every POST /live body. */
function world({ session = ONLINE, fail = false } = {}) {
    let clock = 0;
    let timers = [];
    let nextId = 1;
    const sent = [];
    const live = createLive({
        getSession: async () => session,
        post: async (_session, body) => {
            if (fail) throw Object.assign(new Error("HTTP 429"), { status: 429 });
            sent.push(body);
            return { ok: true };
        },
        now: () => clock,
        setTimer: (fn, ms) => {
            const id = nextId++;
            timers.push({ id, at: clock + ms, fn });
            return id;
        },
        clearTimer: (id) => (timers = timers.filter((t) => t.id !== id)),
    });
    async function tick(ms) {
        clock += ms;
        const due = timers.filter((t) => t.at <= clock);
        timers = timers.filter((t) => t.at > clock);
        for (const t of due) t.fn();
        await new Promise((resolve) => setImmediate(resolve));
    }
    return { live, sent, tick };
}

const page = (over = {}) => ({ domain: "hadiah-gratis.xyz", score: 0, status: "normal", analyzing: true, ...over });

test("a page on screen is sent right away with open: true", async () => {
    const { live, sent } = world();
    await live.show(page());
    assert.deepEqual(sent, [{ domain: "hadiah-gratis.xyz", score: 0, status: "normal", analyzing: true, open: true }]);
});

test("status, analyzing or domain changes go out at once; an unchanged state is not sent again", async () => {
    const { live, sent } = world();
    await live.show(page());
    await live.show(page());
    await live.show(page({ analyzing: false, score: 12 }));
    await live.show(page({ analyzing: false, score: 60, status: "warning" }));
    await live.show(page({ domain: "contoh-toko.com", analyzing: false, score: 60, status: "warning" }));
    assert.deepEqual(
        sent.map((b) => [b.domain, b.score, b.status, b.analyzing]),
        [
            ["hadiah-gratis.xyz", 0, "normal", true],
            ["hadiah-gratis.xyz", 12, "normal", false],
            ["hadiah-gratis.xyz", 60, "warning", false],
            ["contoh-toko.com", 60, "warning", false],
        ],
    );
});

test("score-only changes are coalesced to one call per interval, newest score wins", async () => {
    const { live, sent, tick } = world();
    await live.show(page({ analyzing: false, score: 10 }));
    await live.show(page({ analyzing: false, score: 20 }));
    await live.show(page({ analyzing: false, score: 30, status: "warning" })); // status change: at once
    await live.show(page({ analyzing: false, score: 35, status: "warning" }));
    await live.show(page({ analyzing: false, score: 40, status: "warning" }));
    assert.deepEqual(sent.map((b) => b.score), [10, 30]);
    await tick(LIVE_SCORE_INTERVAL_MS);
    assert.deepEqual(sent.map((b) => b.score), [10, 30, 40]);
});

test("hidden → open: false after the close delay, with the last page's values", async () => {
    const { live, sent, tick } = world();
    await live.show(page({ analyzing: false, score: 60, status: "warning" }));
    await live.hide();
    await tick(LIVE_CLOSE_DELAY_MS - 1);
    assert.equal(sent.length, 1);
    await tick(1);
    assert.deepEqual(sent.at(-1), { domain: "hadiah-gratis.xyz", score: 60, status: "warning", analyzing: false, open: false });
});

test("a tab switch (hidden, then another page on screen) never ends the island", async () => {
    const { live, sent, tick } = world();
    await live.show(page({ analyzing: false }));
    await live.hide();
    await live.show(page({ domain: "contoh-toko.com", analyzing: false, score: 5 }));
    await tick(LIVE_CLOSE_DELAY_MS * 2);
    assert.equal(sent.some((b) => b.open === false), false);
    assert.equal(sent.at(-1).domain, "contoh-toko.com");
});

test("a pending score update is dropped when the island ends", async () => {
    const { live, sent, tick } = world();
    await live.show(page({ analyzing: false, score: 10 }));
    await live.show(page({ analyzing: false, score: 20 }));
    await live.hide();
    await tick(LIVE_CLOSE_DELAY_MS);
    assert.deepEqual(sent.map((b) => [b.score, b.open]), [[10, true], [10, false]]);
});

test("nothing to end when no island was shown, and a second hide is a no-op", async () => {
    const { live, sent, tick } = world();
    await live.hide();
    await tick(LIVE_CLOSE_DELAY_MS);
    assert.equal(sent.length, 0);
    await live.show(page());
    await live.hide();
    await live.hide();
    await tick(LIVE_CLOSE_DELAY_MS);
    assert.equal(sent.filter((b) => b.open === false).length, 1);
});

test("online check off (no aiBaseURL) or not onboarded → no call at all", async () => {
    for (const session of [{ ...ONLINE, aiBaseURL: null }, null]) {
        const { live, sent, tick } = world({ session });
        assert.equal((await live.show(page())).skipped, "online_check_off");
        await live.hide();
        await tick(LIVE_CLOSE_DELAY_MS);
        assert.equal(sent.length, 0);
    }
});

test("a host with no registrable domain (IP, localhost) shows no island and ends the previous one", async () => {
    const { live, sent, tick } = world();
    await live.show(page({ analyzing: false }));
    await live.show(page({ domain: "192.168.1.1" }));
    await live.show(page({ domain: "localhost" }));
    await tick(LIVE_CLOSE_DELAY_MS);
    assert.deepEqual(sent.map((b) => [b.domain, b.open]), [["hadiah-gratis.xyz", true], ["hadiah-gratis.xyz", false]]);
});

test("score is clamped to 0–100 and a failed call never throws", async () => {
    const ok = world();
    await ok.live.show(page({ score: 140 }));
    assert.equal(ok.sent[0].score, 100);
    const failing = world({ fail: true });
    assert.deepEqual(await failing.live.show(page()), { ok: false });
});
