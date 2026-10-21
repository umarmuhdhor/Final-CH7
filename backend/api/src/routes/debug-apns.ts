import { Hono } from "hono";
import type { AppEnv } from "../env";
import { apnsJwt } from "../services/push/jwt";
import { errors } from "../http/errors";

// TEMPORARY (fase 07 spike, D-alief-16): does Worker fetch() reach APNs over HTTP/2?
// Uses a throwaway P-256 key and fake Key/Team IDs: an APNs JSON error such as
// 403 InvalidProviderToken already proves the connection works. Removed in fase 11.
export const debugApns = new Hono<AppEnv>();

const DUMMY_DEVICE = "0".repeat(64);

debugApns.post("/debug/apns-spike", async (c) => {
  const key = c.env.SPIKE_KEY;
  if (c.env.APNS_SPIKE !== "1" || !key || c.req.header("x-spike-key") !== key) throw errors.notFound();

  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, false, [
    "sign",
    "verify",
  ])) as CryptoKeyPair;
  const jwt = await apnsJwt(pair.privateKey, "SPIKE00000", "SPIKE00000");

  const started = Date.now();
  try {
    const res = await fetch(`https://api.sandbox.push.apple.com/3/device/${DUMMY_DEVICE}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-push-type": "alert",
        "apns-topic": "com.example.spike",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify({ aps: { alert: { body: "spike" } } }),
    });
    return c.json({
      reached: true,
      status: res.status,
      apnsId: res.headers.get("apns-id"),
      body: await res.text(),
      ms: Date.now() - started,
      colo: (c.req.raw.cf as { colo?: string } | undefined)?.colo ?? null,
    });
  } catch (err) {
    return c.json({ reached: false, error: String(err), ms: Date.now() - started }, 502);
  }
});
