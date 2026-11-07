import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env, exports } from "cloudflare:workers";
import { app } from "../../src/app";
import type { Env } from "../../src/env";

let ipCounter = 0;
/** A fresh client IP per call keeps the POST /devices rate limit out of unrelated tests. */
export const freshIp = () => `198.51.100.${(ipCounter++ % 250) + 1}`;

export function call(path: string, init: RequestInit & { token?: string; ip?: string; json?: unknown } = {}) {
  const headers = new Headers(init.headers);
  if (init.token) headers.set("authorization", `Bearer ${init.token}`);
  headers.set("cf-connecting-ip", init.ip ?? freshIp());
  let body = init.body;
  if (init.json !== undefined) {
    headers.set("content-type", "application/json");
    body = JSON.stringify(init.json);
  }
  return exports.default.fetch(new Request(`http://api.test${path}`, { ...init, headers, body }));
}

/** A Rate Limiting binding that always says no (hitEdge): the limit's 429 without sending `max` requests. */
export const denyingLimiter: RateLimit = { limit: async () => ({ success: false }) };

/** Like call(), with some env values replaced (e.g. a rate-limit binding), waiting for the request's waitUntil work. */
export async function callWithEnv(over: Partial<Env>, path: string, init: RequestInit & { token?: string } = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  if (init.token) headers.set("authorization", `Bearer ${init.token}`);
  headers.set("cf-connecting-ip", freshIp());
  const ctx = createExecutionContext();
  const res = await app.fetch(new Request(`http://api.test${path}`, { ...init, headers }), { ...env, ...over }, ctx);
  await waitOnExecutionContext(ctx);
  return res;
}

export interface Created {
  deviceId: string;
  token: string;
  avatarId: string;
}

export async function createDevice(name = "Mom", mode: "guardian" | "protected" = "protected"): Promise<Created> {
  const res = await call("/devices", { method: "POST", json: { name, mode } });
  if (res.status !== 201) throw new Error(`createDevice: ${res.status} ${await res.text()}`);
  return res.json();
}
