import type { Env } from "../../env";
import { errorInfo } from "../../http/logError";
import { apnsJwt, importApnsKey } from "./jwt";
import type { PushMessage, PushSender, SendResult } from "./sender";

export interface ApnsConfig {
  /** The .p8 key file (PEM) as one line of base64. */
  keyP8B64: string;
  keyId: string;
  teamId: string;
  /** Bundle ID of the app build that receives the push. */
  topic: string;
  env: "sandbox" | "production";
}

const REQUIRED = ["APNS_KEY_P8_B64", "APNS_KEY_ID", "APNS_TEAM_ID", "APNS_TOPIC", "APNS_ENV"] as const;

export function apnsConfig(env: Env): ApnsConfig | { missing: string[] } {
  const missing: string[] = REQUIRED.filter((k) => !env[k]);
  if (env.APNS_ENV && env.APNS_ENV !== "sandbox" && env.APNS_ENV !== "production") missing.push("APNS_ENV");
  if (missing.length) return { missing };
  return {
    keyP8B64: env.APNS_KEY_P8_B64!, keyId: env.APNS_KEY_ID!, teamId: env.APNS_TEAM_ID!,
    topic: env.APNS_TOPIC!, env: env.APNS_ENV as ApnsConfig["env"],
  };
}

const HOST = { sandbox: "https://api.sandbox.push.apple.com", production: "https://api.push.apple.com" };
const TIMEOUT_MS = 5000;
// Apple: refresh the provider token at most once every 20 min, and before it is 60 min old.
const JWT_MAX_AGE_MS = 50 * 60_000;
const HEX = /^[0-9a-fA-F]{32,200}$/;
const REASON = /^[A-Za-z]{1,64}$/;

// Per isolate: one imported key and one provider token per key id, shared by every request.
interface CacheEntry {
  keyP8B64: string;
  key: Promise<CryptoKey>;
  jwt?: JwtPromise;
}
type JwtPromise = Promise<{ value: string; iatMs: number }>;
const cache = new Map<string, CacheEntry>();

function entry(config: ApnsConfig): CacheEntry {
  const id = `${config.keyId}:${config.teamId}`;
  let e = cache.get(id);
  if (!e || e.keyP8B64 !== config.keyP8B64) {
    e = { keyP8B64: config.keyP8B64, key: Promise.resolve().then(() => importApnsKey(atob(config.keyP8B64))) };
    // A failed import is retried on the next send instead of being cached.
    const created = e;
    e.key.catch(() => {
      if (cache.get(id) === created) cache.delete(id);
    });
    cache.set(id, e);
  }
  return e;
}

/**
 * Sends straight to APNs over HTTP/2 from the Worker (D-alief-B01, R3 §6). Only 410 clears the
 * token; 400 BadDeviceToken (also a sandbox token sent to production) keeps it. No retries:
 * one push per scan. Logs carry no token, JWT, key or text (SECURITY §3 P6).
 */
export class ApnsSender implements PushSender {
  private readonly fetch: typeof fetch;
  private readonly now: () => number;

  constructor(private readonly config: ApnsConfig, deps: { fetch?: typeof fetch; now?: () => number } = {}) {
    this.fetch = deps.fetch ?? ((input, init) => fetch(input, init));
    this.now = deps.now ?? Date.now;
  }

  /**
   * The cached provider token promise (wrapped, so it is not flattened); parallel sends share one
   * signature (single flight). The caller keeps the reference to drop only that token later.
   */
  private async tokenRef(e: CacheEntry): Promise<{ ref: JwtPromise }> {
    const now = this.now();
    const pending = e.jwt;
    if (pending) {
      const current = await pending.catch(() => undefined);
      if (current && now - current.iatMs < JWT_MAX_AGE_MS) return { ref: pending };
      // Another send replaced the stale token while this one waited: use that one.
      if (e.jwt !== pending) return this.tokenRef(e);
    }
    const fresh: JwtPromise = e.key.then(async (key) => ({ value: await apnsJwt(key, this.config.keyId, this.config.teamId, now), iatMs: now }));
    e.jwt = fresh;
    return { ref: fresh };
  }

  async send(message: PushMessage): Promise<SendResult> {
    if (!HEX.test(message.apnsToken)) return { result: "failed:400 BadDeviceToken" };
    const e = entry(this.config);
    const { ref } = await this.tokenRef(e);
    let jwt: string;
    try {
      jwt = (await ref).value;
    } catch (err) {
      if (e.jwt === ref) e.jwt = undefined;
      // Name only: a bad key secret and a WebCrypto failure both land here.
      console.error(JSON.stringify({ event: "push_key_failed", error: errorInfo(err) }));
      return { result: "failed:config" };
    }

    let res: Response;
    try {
      res = await this.fetch(`${HOST[this.config.env]}/3/device/${message.apnsToken}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-push-type": "alert",
          "apns-topic": this.config.topic,
          "apns-priority": "10",
          // A guardian offline for over an hour gets no stale alert; Activity still has the scan.
          "apns-expiration": String(Math.floor(this.now() / 1000) + 3600),
          "content-type": "application/json",
        },
        body: JSON.stringify({ aps: { alert: { body: message.body }, sound: "default" }, ...(message.scanId ? { scanId: message.scanId } : {}) }),
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
    } catch (err) {
      // Never log the error: its message can carry the URL, which carries the device token.
      return { result: (err as { name?: string })?.name === "TimeoutError" ? "failed:timeout" : "failed:network" };
    }
    if (res.status === 200) {
      // An unread body holds the connection in Workers.
      await res.body?.cancel().catch(() => {});
      return { result: "sent" };
    }

    let reason: string | undefined;
    try {
      const r = ((await res.json()) as { reason?: unknown }).reason;
      if (typeof r === "string" && REASON.test(r)) reason = r;
    } catch {
      // Not JSON: status only.
    }
    // Only drop the token this send used: a newer one from a parallel send stays (no refresh storm).
    if (res.status === 403 && reason === "ExpiredProviderToken" && e.jwt === ref) e.jwt = undefined;
    const result = `failed:${res.status}${reason ? ` ${reason}` : ""}`;
    return res.status === 410 ? { result, clearToken: true } : { result };
  }
}
