import { afterEach, describe, expect, it, vi } from "vitest";
import { ApnsSender, apnsConfig, type ApnsConfig } from "../src/services/push/apns";
import { LogSender, pushSender, type PushMessage } from "../src/services/push/sender";

const decode = (part: string) => JSON.parse(atob(part.replace(/-/g, "+").replace(/_/g, "/")));

async function testKey(): Promise<{ p8b64: string; publicKey: CryptoKey }> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der)).replace(/(.{64})/g, "$1\n")}\n-----END PRIVATE KEY-----\n`;
  return { p8b64: btoa(pem), publicKey: pair.publicKey };
}

// Every test gets its own key id, so the module-level JWT cache never crosses tests.
let n = 0;
async function setup(overrides: Partial<ApnsConfig> = {}) {
  const { p8b64, publicKey } = await testKey();
  const config: ApnsConfig = {
    keyP8B64: p8b64, keyId: `KEY${String(++n).padStart(7, "0")}`, teamId: "TEAM123456",
    topic: "com.example.shoo", env: "sandbox", ...overrides,
  };
  return { config, publicKey };
}

const TOKEN = "ab".repeat(32);
const message: PushMessage = { toDeviceId: "dev_g", apnsToken: TOKEN, body: "Mom hit a blocked site · 92%", scanId: "scan-1" };

type Call = { url: string; init: RequestInit };
function fakeFetch(...responses: (Response | Error | (() => Promise<Response>))[]) {
  const calls: Call[] = [];
  const fn = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    calls.push({ url: String(input), init: init ?? {} });
    const next = responses.length > 1 ? responses.shift()! : responses[0]!;
    if (next instanceof Error) throw next;
    return typeof next === "function" ? next() : next.clone();
  });
  return { fetch: fn as unknown as typeof fetch, calls };
}
const apns = (status: number, reason?: string) =>
  new Response(reason ? JSON.stringify({ reason }) : null, { status, headers: { "apns-id": "id-1" } });
const headers = (c: Call) => new Headers(c.init.headers);

afterEach(() => vi.restoreAllMocks());

describe("ApnsSender request (R3 §6, contracts/api.md Push payloads)", () => {
  it("POSTs the contract payload + sound to the sandbox host with the APNs headers", async () => {
    const { config, publicKey } = await setup();
    const { fetch, calls } = fakeFetch(apns(200));
    expect(await new ApnsSender(config, { fetch }).send(message)).toEqual({ result: "sent" });

    expect(calls).toHaveLength(1);
    expect(calls[0]!.url).toBe(`https://api.sandbox.push.apple.com/3/device/${TOKEN}`);
    expect(calls[0]!.init.method).toBe("POST");
    const h = headers(calls[0]!);
    expect(h.get("apns-push-type")).toBe("alert");
    expect(h.get("apns-topic")).toBe("com.example.shoo");
    expect(h.get("apns-priority")).toBe("10");
    expect(h.get("content-type")).toBe("application/json");
    expect(calls[0]!.init.signal).toBeInstanceOf(AbortSignal);
    // Stale alerts are not delivered hours later (security review fase 11 M1).
    const exp = Number(h.get("apns-expiration"));
    expect(exp).toBeGreaterThan(Date.now() / 1000 + 3500);
    expect(exp).toBeLessThanOrEqual(Math.floor(Date.now() / 1000) + 3600);
    expect(JSON.parse(String(calls[0]!.init.body))).toEqual({
      aps: { alert: { body: "Mom hit a blocked site · 92%" }, sound: "default" }, scanId: "scan-1",
    });

    const jwt = h.get("authorization")!.replace(/^bearer /, "");
    const [hd, pl, sg] = jwt.split(".");
    expect(decode(hd!)).toEqual({ alg: "ES256", kid: config.keyId });
    expect(decode(pl!).iss).toBe("TEAM123456");
    const sig = Uint8Array.from(atob(sg!.replace(/-/g, "+").replace(/_/g, "/") + "=="), (ch) => ch.charCodeAt(0));
    expect(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, publicKey, sig, new TextEncoder().encode(`${hd}.${pl}`))).toBe(true);
  });

  it("production uses api.push.apple.com", async () => {
    const { config } = await setup({ env: "production" });
    const { fetch, calls } = fakeFetch(apns(200));
    await new ApnsSender(config, { fetch }).send(message);
    expect(calls[0]!.url).toBe(`https://api.push.apple.com/3/device/${TOKEN}`);
  });

  it("a token that is not hex never reaches APNs", async () => {
    const { config } = await setup();
    const { fetch, calls } = fakeFetch(apns(200));
    expect(await new ApnsSender(config, { fetch }).send({ ...message, apnsToken: "../../x" })).toEqual({ result: "failed:400 BadDeviceToken" });
    expect(calls).toHaveLength(0);
  });
});

describe("ApnsSender results", () => {
  it.each([
    [410, "Unregistered", { result: "failed:410 Unregistered", clearToken: true }],
    [410, "ExpiredToken", { result: "failed:410 ExpiredToken", clearToken: true }],
    [400, "BadDeviceToken", { result: "failed:400 BadDeviceToken" }],
    [403, "InvalidProviderToken", { result: "failed:403 InvalidProviderToken" }],
    [429, "TooManyProviderTokenUpdates", { result: "failed:429 TooManyProviderTokenUpdates" }],
  ])("%i %s", async (status, reason, expected) => {
    const { config } = await setup();
    const { fetch } = fakeFetch(apns(status, reason));
    expect(await new ApnsSender(config, { fetch }).send(message)).toEqual(expected);
  });

  it("non-JSON or odd reasons keep the status only", async () => {
    const { config } = await setup();
    const { fetch } = fakeFetch(new Response("<html>oops</html>", { status: 500 }), apns(400, "has spaces and eyJhbGc.token"));
    const sender = new ApnsSender(config, { fetch });
    expect(await sender.send(message)).toEqual({ result: "failed:500" });
    expect(await sender.send(message)).toEqual({ result: "failed:400" });
  });

  it("a real AbortSignal timeout maps to failed:timeout", async () => {
    const { config } = await setup();
    // Fetch that only ends when its signal aborts; the 5 s timeout is shortened to 10 ms.
    const hang: typeof fetch = (_u, init) =>
      new Promise((_, reject) => init!.signal!.addEventListener("abort", () => reject(init!.signal!.reason)));
    const real = AbortSignal.timeout.bind(AbortSignal);
    const spy = vi.spyOn(AbortSignal, "timeout").mockImplementation(() => real(10));
    expect(await new ApnsSender(config, { fetch: hang }).send(message)).toEqual({ result: "failed:timeout" });
    expect(spy).toHaveBeenCalledWith(5000);
  });

  it("a broken key is retried with the next send, not cached", async () => {
    const { config } = await setup();
    vi.spyOn(console, "error").mockImplementation(() => {});
    const { fetch, calls } = fakeFetch(apns(200));
    const broken = { ...config, keyP8B64: btoa("not a key") };
    expect(await new ApnsSender(broken, { fetch }).send(message)).toEqual({ result: "failed:config" });
    // Rotated to a good key under the same key id.
    expect(await new ApnsSender(config, { fetch }).send(message)).toEqual({ result: "sent" });
    expect(calls).toHaveLength(1);
  });

  it("timeout, network error and a broken key never throw", async () => {
    const { config } = await setup();
    const timeout = new DOMException("The operation timed out.", "TimeoutError");
    const { fetch } = fakeFetch(timeout, new TypeError(`connect failed https://api.sandbox.push.apple.com/3/device/${TOKEN}`));
    const sender = new ApnsSender(config, { fetch });
    expect(await sender.send(message)).toEqual({ result: "failed:timeout" });
    expect(await sender.send(message)).toEqual({ result: "failed:network" });

    vi.spyOn(console, "error").mockImplementation(() => {});
    const broken = await setup({ keyP8B64: btoa("not a key") });
    const { fetch: f2, calls } = fakeFetch(apns(200));
    expect(await new ApnsSender(broken.config, { fetch: f2 }).send(message)).toEqual({ result: "failed:config" });
    expect(calls).toHaveLength(0);
  });
});

describe("ApnsSender provider token cache", () => {
  it("reuses the JWT for under 50 min, signs a new one after", async () => {
    const { config } = await setup();
    let now = Date.UTC(2026, 9, 22, 1);
    const { fetch, calls } = fakeFetch(apns(200));
    const sender = new ApnsSender(config, { fetch, now: () => now });
    await sender.send(message);
    now += 49 * 60_000;
    await sender.send(message);
    now += 2 * 60_000;
    await sender.send(message);
    const auth = calls.map((c) => headers(c).get("authorization"));
    expect(auth[1]).toBe(auth[0]);
    expect(auth[2]).not.toBe(auth[0]);
    expect(decode(auth[2]!.split(".")[1]!).iat).toBe(Math.floor(now / 1000));
  });

  it("parallel sends share one signature (ECDSA signatures differ each time)", async () => {
    const { config } = await setup();
    const { fetch, calls } = fakeFetch(apns(200));
    const sender = new ApnsSender(config, { fetch });
    await Promise.all([sender.send(message), sender.send(message), sender.send(message)]);
    expect(new Set(calls.map((c) => headers(c).get("authorization"))).size).toBe(1);
  });

  it("the cache is shared across sender instances (one per request)", async () => {
    const { config } = await setup();
    const { fetch, calls } = fakeFetch(apns(200));
    await new ApnsSender(config, { fetch }).send(message);
    await new ApnsSender(config, { fetch }).send(message);
    expect(headers(calls[1]!).get("authorization")).toBe(headers(calls[0]!).get("authorization"));
  });

  it("a stale JWT is refreshed once for parallel sends", async () => {
    const { config } = await setup();
    let now = Date.UTC(2026, 9, 22, 1);
    const { fetch, calls } = fakeFetch(apns(200));
    const sender = new ApnsSender(config, { fetch, now: () => now });
    await sender.send(message);
    now += 51 * 60_000;
    await Promise.all([sender.send(message), sender.send(message)]);
    const auth = calls.map((c) => headers(c).get("authorization"));
    expect(auth[1]).not.toBe(auth[0]);
    expect(auth[2]).toBe(auth[1]);
  });

  it("403 ExpiredProviderToken on an old JWT keeps the newer one", async () => {
    const { config } = await setup();
    let now = Date.UTC(2026, 9, 22, 1);
    let release!: () => void;
    const gate = new Promise<void>((r) => (release = r));
    const calls: string[] = [];
    const fetch = (async (_u: RequestInfo | URL, init?: RequestInit) => {
      const auth = new Headers(init?.headers).get("authorization")!;
      calls.push(auth);
      if (calls.length === 1) {
        await gate;
        return apns(403, "ExpiredProviderToken");
      }
      return apns(200);
    }) as typeof globalThis.fetch;
    const sender = new ApnsSender(config, { fetch, now: () => now });
    const slow = sender.send(message);
    await new Promise((r) => setTimeout(r, 10));
    now += 51 * 60_000; // a parallel send signs a new token while the first one waits on APNs
    await sender.send(message);
    release();
    await slow;
    await sender.send(message);
    expect(calls[1]).not.toBe(calls[0]);
    expect(calls[2]).toBe(calls[1]);
  });

  it("403 ExpiredProviderToken drops the cached JWT", async () => {
    const { config } = await setup();
    const { fetch, calls } = fakeFetch(apns(403, "ExpiredProviderToken"), apns(200));
    const sender = new ApnsSender(config, { fetch });
    expect(await sender.send(message)).toEqual({ result: "failed:403 ExpiredProviderToken" });
    expect(await sender.send(message)).toEqual({ result: "sent" });
    expect(headers(calls[1]!).get("authorization")).not.toBe(headers(calls[0]!).get("authorization"));
  });
});

describe("pushSender selection", () => {
  const base = { APNS_KEY_P8_B64: "eA==", APNS_KEY_ID: "KEY0000001", APNS_TEAM_ID: "TEAM123456", APNS_TOPIC: "com.example.shoo", APNS_ENV: "sandbox" };
  const env = (e: Record<string, string | undefined>) => e as unknown as Parameters<typeof pushSender>[0];

  it("all APNs values present → ApnsSender", () => {
    expect(pushSender(env(base))).toBeInstanceOf(ApnsSender);
    expect(pushSender(env({ ...base, APNS_ENV: "production" }))).toBeInstanceOf(ApnsSender);
  });

  it("any value missing, empty or an unknown env → LogSender", () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    for (const k of Object.keys(base)) {
      expect(pushSender(env({ ...base, [k]: undefined }))).toBeInstanceOf(LogSender);
      expect(pushSender(env({ ...base, [k]: "" }))).toBeInstanceOf(LogSender);
    }
    expect(pushSender(env({ ...base, APNS_ENV: "staging" }))).toBeInstanceOf(LogSender);
  });

  it("apnsConfig names what is missing, never the values", () => {
    expect(apnsConfig(env({ ...base, APNS_KEY_ID: "", APNS_TOPIC: undefined }))).toEqual({ missing: ["APNS_KEY_ID", "APNS_TOPIC"] });
  });
});
