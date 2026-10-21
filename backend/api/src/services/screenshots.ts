import type { Env } from "../env";
import { errorInfo } from "../http/logError";

const BUCKET = "screenshots";
const TIMEOUT_MS = 5000;
const REMOVE_BATCH = 100;

/** Throws on a non-2xx response; the body is released first (workerd caps open subrequests). */
async function ensureOk(res: Response, what: string): Promise<void> {
  if (res.ok) return;
  await res.body?.cancel();
  throw new Error(`storage ${what} ${res.status}`);
}

/** Private evidence screenshots (bucket `screenshots`, R3 §4, SECURITY T6). */
export interface ScreenshotStore {
  put(path: string, bytes: Uint8Array, contentType: string): Promise<void>;
  /** The object as a streaming response, or undefined when it does not exist. */
  get(path: string): Promise<Response | undefined>;
  remove(paths: string[]): Promise<void>;
}

/**
 * Supabase Storage REST with the service key (`sb_secret_…` or the legacy service_role JWT;
 * both were checked against local Storage v1.80.2, D-alief-B07). One subrequest per call.
 */
export class SupabaseStorageStore implements ScreenshotStore {
  constructor(
    private readonly baseUrl: string,
    private readonly key: string,
  ) {}

  private headers(contentType: string): Record<string, string> {
    return { apikey: this.key, authorization: `Bearer ${this.key}`, "content-type": contentType };
  }

  private object(path: string): string {
    return path.split("/").map(encodeURIComponent).join("/");
  }

  async put(path: string, bytes: Uint8Array, contentType: string): Promise<void> {
    const res = await fetch(`${this.baseUrl}/storage/v1/object/${BUCKET}/${this.object(path)}`, {
      method: "POST",
      // Stored with the object and sent on every signed GET. Without it Storage uses max-age=3600,
      // and the CDN kept serving a screenshot for up to 1 h after it was deleted (fase 09 smoke).
      headers: { ...this.headers(contentType), "cache-control": "no-store" },
      body: bytes,
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    await ensureOk(res, "put");
    await res.body?.cancel();
  }

  async get(path: string): Promise<Response | undefined> {
    const res = await fetch(`${this.baseUrl}/storage/v1/object/authenticated/${BUCKET}/${this.object(path)}`, {
      headers: { apikey: this.key, authorization: `Bearer ${this.key}`, "cache-control": "no-cache" },
      // Never a cached copy: a path can outlive one of the scans that shares it (dedupe).
      cache: "no-store",
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    // Storage answers a missing object with 400 or 404.
    if (res.status === 400 || res.status === 404) {
      await res.body?.cancel();
      return undefined;
    }
    await ensureOk(res, "get");
    return res;
  }

  async remove(paths: string[]): Promise<void> {
    if (paths.length === 0) return;
    const res = await fetch(`${this.baseUrl}/storage/v1/object/${BUCKET}`, {
      method: "DELETE",
      headers: this.headers("application/json"),
      body: JSON.stringify({ prefixes: paths }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    await ensureOk(res, "remove");
    await res.body?.cancel();
  }
}

/** Undefined without SUPABASE_URL + key: screenshots are then dropped and scans still stored. */
export function screenshotStore(env: Env): ScreenshotStore | undefined {
  if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) return undefined;
  return new SupabaseStorageStore(env.SUPABASE_URL.replace(/\/+$/, ""), env.SUPABASE_SERVICE_ROLE_KEY);
}

/** Removes screenshot objects after their rows are gone (DELETE /devices/me, retention in fase 12). */
export async function deleteScreenshots(env: Env, paths: string[]): Promise<void> {
  if (paths.length === 0) return;
  const store = screenshotStore(env);
  try {
    if (!store) throw new Error("storage not configured");
    for (let i = 0; i < paths.length; i += REMOVE_BATCH) await store.remove(paths.slice(i, i + REMOVE_BATCH));
  } catch (err) {
    // Count only: paths contain device ids.
    console.error(JSON.stringify({ event: "screenshots_delete_failed", count: paths.length, error: errorInfo(err) }));
  }
}
