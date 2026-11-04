import type { Sql } from "postgres";
import type { Env } from "../env";
import { clearFragments, type FragmentQuota, type FragmentQuotaReason, reserveFragments } from "../db/repo/fragments";
import { errorInfo } from "../http/logError";
import { decodeReplica, MAX_REPLICA_BYTES, type ReplicaDrop, replicasEnabled } from "./replicas";
import type { ScreenshotStore } from "./screenshots";

/**
 * ADM-07 (dashboard plan fase 07a K6, D-dash-17 #4): evidence fragments are sent for every warning
 * and blocked scan, with or without a family, and kept for good in `shoo-replica-archive`. A
 * fragments document is a few KB to tens of KB of gzip; at the global bound (2000 uploads, 100 MB per
 * day) the bucket would pass R2's free 10 GB in ±100 days, which the dashboard's archive size warning
 * (Config archive_warn_mb, 5120 MB) shows long before. Per device 100 uploads + 10 MB (anti-abuse).
 * Past a quota the scan is stored without fragments.
 */
export const FRAGMENT_QUOTA: FragmentQuota = {
  owner: 100, ownerBytes: 10 * 1024 * 1024, global: 2000, globalBytes: 100 * 1024 * 1024,
};

type Drop = ReplicaDrop | "disabled" | "no_storage" | "scan_gone" | "taken" | `quota_${FragmentQuotaReason}` | "upload_failed";

// Reason only: never the scan id, URL, key or device (SECURITY §3 P6).
const dropped = (reason: Drop) => console.error(JSON.stringify({ event: "fragments_dropped", reason }));

/** One object per scan; the key holds no device id (07a "Batas"). */
export const fragmentsKey = (scanId: string) => `${scanId}.fragments.html.gz`;
/** One favicon per domain, shared by every scan of it (D-dash-17 #12a). */
export const faviconKey = (domain: string) => `favicon/${domain}`;

/**
 * Private R2 bucket `shoo-replica-archive` (no r2.dev, no expiry): evidence fragments and one favicon
 * per domain. Read only by the admin dashboard. Same size guard as the replica store (SECURITY T6).
 */
export class R2ArchiveStore implements ScreenshotStore {
  constructor(private readonly bucket: R2Bucket) {}

  async put(path: string, bytes: Uint8Array, contentType: string): Promise<void> {
    if (bytes.length > MAX_REPLICA_BYTES) throw new Error("r2 put: object too large");
    await this.bucket.put(path, bytes, { httpMetadata: { contentType } });
  }

  async has(path: string): Promise<boolean> {
    return (await this.bucket.head(path)) !== null;
  }

  async get(path: string): Promise<Response | undefined> {
    const object = await this.bucket.get(path);
    return object ? new Response(object.body) : undefined;
  }

  async remove(paths: string[]): Promise<void> {
    for (let i = 0; i < paths.length; i += 100) await this.bucket.delete(paths.slice(i, i + 100));
  }
}

export function archiveStore(env: Env): R2ArchiveStore | undefined {
  return env.REPLICA_ARCHIVE ? new R2ArchiveStore(env.REPLICA_ARCHIVE) : undefined;
}

/**
 * After the response and after the scan's pushes (like attachReplica): kill-switch (REPLICAS_ENABLED,
 * the same serializer) → decode with the replica limits → reserve under the quotas (sets
 * scans.fragments_bytes, the trigger fills the archive row) → put. A failed put clears the
 * reservation. No tombstone at reservation: archive objects are permanent; only DELETE /devices/me
 * tombstones them (migration 20261104085245, K12).
 */
export async function attachFragments(
  sql: Sql,
  env: Env,
  scan: { id: string; ownerId: string },
  base64: string,
  quota: FragmentQuota = FRAGMENT_QUOTA,
): Promise<void> {
  if (!replicasEnabled(env)) return dropped("disabled");
  const store = archiveStore(env);
  if (!store) return dropped("no_storage");

  const decoded = await decodeReplica(base64);
  if (!decoded.ok) return dropped(decoded.reason);

  const slot = await reserveFragments(sql, scan, decoded.bytes.length, quota);
  if ("gone" in slot) return dropped("scan_gone");
  if ("taken" in slot) return dropped("taken");
  if ("quota" in slot) return dropped(`quota_${slot.quota}`);

  try {
    await store.put(fragmentsKey(scan.id), decoded.bytes, "application/gzip");
  } catch (err) {
    console.error(JSON.stringify({ event: "fragments_dropped", reason: "upload_failed", error: errorInfo(err) }));
    await clearFragments(sql, scan).catch((e: unknown) =>
      console.error(JSON.stringify({ event: "fragments_clear_failed", error: errorInfo(e) })));
  }
}

/**
 * 07a K7: the first stored favicon of a domain is copied once to `favicon/<domain>` in the archive
 * (a site's icon, not user data; never deleted with an account). Never throws.
 */
export async function archiveFavicon(env: Env, domain: string, bytes: Uint8Array, contentType: string): Promise<void> {
  const store = archiveStore(env);
  if (!store) return;
  try {
    const key = faviconKey(domain);
    if (!(await store.has(key))) await store.put(key, bytes, contentType);
  } catch (err) {
    console.error(JSON.stringify({ event: "archive_favicon_failed", error: errorInfo(err) }));
  }
}
