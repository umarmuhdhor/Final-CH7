import type { Env } from "../env";

const BUCKET = "screenshots";
const TIMEOUT_MS = 5000;

/** Private evidence screenshots (bucket `screenshots`, R3 §4, SECURITY T6). */
export interface ScreenshotStore {
  put(path: string, bytes: Uint8Array, contentType: string): Promise<void>;
  signedUrl(path: string, ttlSeconds: number): Promise<string>;
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
      headers: this.headers(contentType),
      body: bytes,
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!res.ok) throw new Error(`storage put ${res.status}`);
  }

  async signedUrl(path: string, ttlSeconds: number): Promise<string> {
    const res = await fetch(`${this.baseUrl}/storage/v1/object/sign/${BUCKET}/${this.object(path)}`, {
      method: "POST",
      headers: this.headers("application/json"),
      body: JSON.stringify({ expiresIn: ttlSeconds }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!res.ok) throw new Error(`storage sign ${res.status}`);
    const { signedURL } = (await res.json()) as { signedURL: string };
    return `${this.baseUrl}/storage/v1${signedURL}`;
  }

  async remove(paths: string[]): Promise<void> {
    if (paths.length === 0) return;
    const res = await fetch(`${this.baseUrl}/storage/v1/object/${BUCKET}`, {
      method: "DELETE",
      headers: this.headers("application/json"),
      body: JSON.stringify({ prefixes: paths }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!res.ok) throw new Error(`storage remove ${res.status}`);
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
    await store.remove(paths);
  } catch (err) {
    // Count only: paths contain device ids.
    console.error(JSON.stringify({ event: "screenshots_delete_failed", count: paths.length, error: String(err) }));
  }
}
