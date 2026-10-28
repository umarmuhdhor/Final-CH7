// node --test chrome/test/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { DEV_SESSION_KEY, createSession, validSession } from "../extension/session.js";

const storage = (items) => ({ get: async (key) => ({ [key]: items[key] }) });

test("no stored session → null: nothing leaves the browser by default", async () => {
    assert.equal(await createSession({ storage: storage({}) })(), null);
});

test("storage failure → null, never throws", async () => {
    const broken = { get: async () => { throw new Error("quota"); } };
    assert.equal(await createSession({ storage: broken })(), null);
});

test("dev session has the getSession shape (contracts/app-group-keys.md)", async () => {
    const getSession = createSession({
        storage: storage({ [DEV_SESSION_KEY]: { token: "t", apiBaseURL: "http://localhost:8787", mode: "protected", guardianName: "Rina" } }),
    });
    assert.deepEqual(await getSession(), {
        ok: true,
        token: "t",
        deviceId: null,
        name: "",
        mode: "protected",
        guardianName: "Rina",
        apiBaseURL: "http://localhost:8787",
        aiBaseURL: null,
    });
});

test("needs a token and at least one http(s) base URL", () => {
    assert.equal(validSession(null), null);
    assert.equal(validSession({ apiBaseURL: "https://api.test" }), null);
    assert.equal(validSession({ token: "t" }), null);
    assert.equal(validSession({ token: "t", apiBaseURL: "javascript:alert(1)" }), null);
    assert.equal(validSession({ token: "t", aiBaseURL: "https://ai.test" }).aiBaseURL, "https://ai.test");
});

test("unknown mode falls back to guardian", () => {
    assert.equal(validSession({ token: "t", apiBaseURL: "https://api.test", mode: "admin" }).mode, "guardian");
});
