import type { Sql } from "postgres";
import type { Env } from "../env";
import {
  clearReplicaPath, precheckReplica, type ReplicaQuota, type ReplicaQuotaReason, replicaUsage, reserveReplica, scanExists,
} from "../db/repo/scans";
import { usableSecret } from "../http/crypto";
import { ApiError } from "../http/errors";
import { errorInfo } from "../http/logError";
import { hit, limits } from "../http/rateLimit";
import { decodeBase64 } from "./images";
import { replicaLink } from "./screenshotLinks";
import { abandonUpload, r2Store } from "./screenshots";

/** contracts/api.md "Page replica" = replica-build.js MAX_BASE64 (400 KB of base64). */
export const MAX_REPLICA_BASE64 = 409_600;
/** The gzip bytes 409 600 base64 characters decode to at most; also the largest object put in R2. */
export const MAX_REPLICA_BYTES = 307_200;
/** = replica-build.js MAX_HTML_BYTES: the inflated page, counted while inflating (ISIZE is not trusted). */
export const MAX_REPLICA_HTML = 3_145_728;
/**
 * gzip input per DecompressionStream write (K2, D-alief-C25 e). One write inflates its whole input
 * before the output can be counted, and deflate inflates at most ±1032:1, so a 300 KB write could
 * expand to ±300 MB. 8 KB slices bound one step to ±8.5 MB and cut the write + yield rounds for a
 * 300 KB replica from ±75 to ±38 (fase 22 K4 a). Not 16 KB as planned: concurrent bombs share one
 * isolate's 128 MB, and the peak is per request (security review 22a-2). The yield after each write
 * stays a macrotask: a microtask yield let a whole bomb through in workerd (fase 22 C4).
 */
export const INFLATE_SLICE = 8192;

/**
 * D-alief-C26, R2 instead of Supabase: 500 MB/day × 16 days of object life = 8 GB < 10 GB R2 free;
 * 3000 × 30 = 90 000 puts/month ≪ 1 M Class A; 3000 < the cron's 4000 R2 deletes per run. Per device
 * 50 (anti-abuse; a reuse covers the same domain). Past a quota the scan is stored without a replica.
 * Fase 19 (TODO E8, review security 18a M1, D-alief-B14): per family 60 uploads + 10 MB, so one family
 * holds at most ±34 full-size replicas (a normal page is tens of KB gzip: 60 × 50 KB = 3 MB); the last
 * 20 % of the global quota is kept for families with fewer than 10 uploads (K3). Without device
 * attestation many IPs still beat it; this raises the attacker's cost ±2.3–4× (fase 19 K2) and makes it visible.
 */
export const REPLICA_QUOTA: ReplicaQuota = {
  owner: 50, family: 60, familyBytes: 10 * 1024 * 1024, global: 3000, globalBytes: 500 * 1024 * 1024,
  reserveUploads: 600, reserveBytes: 100 * 1024 * 1024, lightFamily: 10,
};

export type ReplicaDrop = "invalid" | "too_large" | "not_gzip";

type Drop =
  | ReplicaDrop
  | "disabled" | "no_storage" | "ip_quota" | "quota" | "family_quota" | "family_bytes" | "reserve"
  | "global_quota" | "global_bytes" | "scan_gone" | "upload_failed";

// Reason only: never the scan id, URL, path or device (SECURITY §3 P6). One level for every drop,
// so a log filter on the event sees them all.
const dropped = (reason: Drop) => console.error(JSON.stringify({ event: "replica_dropped", reason }));

// Event names are an interface (fase 19 K5.1, read by fase 21): never rename them.
const QUOTA_DROP: Record<ReplicaQuotaReason, Drop> = {
  owner: "quota", family: "family_quota", family_bytes: "family_bytes", reserve: "reserve",
  global: "global_quota", global_bytes: "global_bytes",
};

export const replicasEnabled = (env: Env) => env.REPLICAS_ENABLED === "true";

/**
 * Hourly gauge (fase 19 K5.2, cron `5 * * * *`): one line `replica_quota_usage` with aggregates only.
 * `level` is the quota state now, not a drop (drops are `replica_dropped`). log for ok, warn for
 * reserve, error for full, so a log filter on the level sees trouble.
 */
export async function logReplicaUsage(sql: Sql): Promise<void> {
  const usage = await replicaUsage(sql, REPLICA_QUOTA, MAX_REPLICA_BYTES);
  const line = JSON.stringify({ event: "replica_quota_usage", ...usage });
  if (usage.level === "full") console.error(line);
  else if (usage.level === "reserve") console.warn(line);
  else console.log(line);
}

/**
 * EX-07, after the response and after the scan's pushes were sent (K2): cheap checks first so a reuse
 * or a full quota burns neither the IP slot nor inflate CPU. Kill-switch →
 * reuse/quota pre-check (fase 22 K12) → per-IP limit → decode → reserve (per-owner lock,
 * quotas again as the final word, tombstone) → R2 put.
 * Any failure drops the replica only; the scan is already stored and answered.
 */
export async function attachReplica(
  sql: Sql,
  env: Env,
  scan: { id: string; ownerId: string; domain: string },
  base64: string,
  ip: string,
): Promise<void> {
  if (!replicasEnabled(env)) return dropped("disabled");
  const store = r2Store(env);
  if (!store) return dropped("no_storage");

  const pre = await precheckReplica(sql, scan, estimatedBytes(base64), REPLICA_QUOTA);
  if (pre.reuse) {
    const slot = await reserveReplica(sql, scan, null, REPLICA_QUOTA);
    if ("gone" in slot) return dropped("scan_gone");
    // { none }: the reuse expired in between; carry on as a new upload.
    if (!("none" in slot)) return;
  }
  // Fase 22 K12: a full quota drops here, before the IP slot and the inflate.
  if (pre.quota) return dropped(QUOTA_DROP[pre.quota]);

  try {
    await hit(sql, limits.replicaIp, ip);
  } catch (err) {
    if (err instanceof ApiError) return dropped("ip_quota");
    throw err;
  }

  const decoded = await decodeReplica(base64);
  if (!decoded.ok) return dropped(decoded.reason);

  const path = `${scan.ownerId}/${scan.id}-replica.html.gz`;
  const slot = await reserveReplica(sql, scan, { path, bytes: decoded.bytes.length }, REPLICA_QUOTA);
  if ("reuse" in slot || "none" in slot) return;
  if ("gone" in slot) return dropped("scan_gone");
  if ("quota" in slot) return dropped(QUOTA_DROP[slot.quota]);

  try {
    await store.put(path, decoded.bytes, "application/gzip");
  } catch (err) {
    console.error(JSON.stringify({ event: "replica_dropped", reason: "upload_failed", error: errorInfo(err) }));
    // Left set, the path would be reused for 24 hours as a link that always 404s: say so in the log.
    await clearReplicaPath(sql, scan.ownerId, path).catch((e: unknown) =>
      console.error(JSON.stringify({ event: "replica_clear_failed", error: errorInfo(e) })));
    await abandonUpload(sql, store, path);
    return;
  }
  // The scan may have been deleted meanwhile (DELETE /devices/me): never leave an orphan object.
  if (!(await scanExists(sql, scan.id))) await abandonUpload(sql, store, path);
}

/**
 * The gzip size the base64 decodes to, from its length alone (no regex pass over 400 KB, fase 22
 * K12): 0 for a string the decoder will refuse anyway by its shape (length), so then only the upload
 * counts are checked early and decodeReplica drops it as before.
 */
export function estimatedBytes(base64: string): number {
  const n = base64.length;
  if (n === 0 || n % 4 !== 0 || n > MAX_REPLICA_BASE64) return 0;
  const pad = base64.endsWith("==") ? 2 : base64.endsWith("=") ? 1 : 0;
  return (n / 4) * 3 - pad;
}

/**
 * Detail's pageReplicaUrl: a 1-hour Worker link for this viewer, like screenshotUrl. Null without a
 * replica, with the kill-switch off, or without a usable secret.
 */
export async function replicaUrl(env: Env, scan: { id: string; replicaPath: string | null }, viewerId: string): Promise<string | null> {
  if (!scan.replicaPath || !replicasEnabled(env)) return null;
  const secret = usableSecret(env.SCREENSHOT_URL_SECRET);
  if (!secret) return null;
  const origin = env.INVITE_BASE_URL.replace(/\/+$/, "");
  return replicaLink(secret, origin, scan.id, viewerId, Date.now() / 1000);
}

export type DecodedReplica =
  | { ok: true; bytes: Uint8Array; htmlBytes: number }
  | { ok: false; reason: ReplicaDrop; consumed?: number };

/**
 * EX-07 (D-alief-C20): validates the replica and returns the gzip bytes exactly as sent, which are
 * stored and served as is (`Content-Encoding: gzip`). Inflating only measures: strict base64 ≤ 400 KB,
 * gzip magic (1f 8b 08), at most 3 MB inflated, one complete member and nothing after it (workerd's
 * DecompressionStream rejects truncated data, a bad trailer and trailing bytes). The length limits
 * live here, not in zod: a 422 would make the extension drop the whole scan.
 */
export async function decodeReplica(base64: string): Promise<DecodedReplica> {
  if (base64.length > MAX_REPLICA_BASE64) {
    return { ok: false, reason: /^[A-Za-z0-9+/]*={0,2}$/.test(base64) && base64.length % 4 === 0 ? "too_large" : "invalid" };
  }
  const bytes = decodeBase64(base64, MAX_REPLICA_BYTES);
  if (!bytes || bytes.length === 0) return { ok: false, reason: "invalid" };
  if (bytes.length < 3 || bytes[0] !== 0x1f || bytes[1] !== 0x8b || bytes[2] !== 0x08) return { ok: false, reason: "not_gzip" };
  const size = await inflatedSize(bytes, MAX_REPLICA_HTML);
  if (!size.ok) return { ok: false, reason: size.reason, consumed: size.consumed };
  return { ok: true, bytes, htmlBytes: size.size };
}

type Measured = { ok: true; size: number } | { ok: false; reason: "too_large" | "invalid"; consumed: number };

/**
 * Inflates `gz` and counts the output, stopping once it passes `max`. The input goes in INFLATE_SLICE
 * pieces, each awaited and followed by its output, so the stream stops after the slice that crossed
 * the limit; `consumed` is the input written until then.
 */
export async function inflatedSize(gz: Uint8Array, max: number): Promise<Measured> {
  const stream = new DecompressionStream("gzip");
  const writer = stream.writable.getWriter();
  const reader = stream.readable.getReader();
  let size = 0;
  let over = false;
  let failed = false;
  const reading = (async () => {
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) return;
        size += value.byteLength;
        if (size > max) {
          over = true;
          await reader.cancel().catch(() => undefined);
          return;
        }
      }
    } catch {
      failed = true;
    }
  })();

  let consumed = 0;
  try {
    for (let o = 0; o < gz.length && !over && !failed; o += INFLATE_SLICE) {
      const slice = gz.subarray(o, o + INFLATE_SLICE);
      await writer.write(slice);
      consumed += slice.length;
      // Let the reader count this slice's output before the next write.
      await yieldToReader();
    }
    if (!over && !failed) await writer.close();
  } catch {
    failed = true;
  }
  if (over || failed) await writer.abort().catch(() => undefined);
  await reading;
  if (over) return { ok: false, reason: "too_large", consumed };
  if (failed) return { ok: false, reason: "invalid", consumed };
  return { ok: true, size };
}

const yieldToReader = () => new Promise<void>((resolve) => setTimeout(resolve, 0));
