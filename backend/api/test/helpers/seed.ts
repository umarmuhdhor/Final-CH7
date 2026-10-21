import { exports } from "cloudflare:workers";

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
