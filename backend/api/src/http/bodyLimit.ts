/** Largest body any route takes (D-alief-B12 d); readJson caps most routes lower (16 KB). */
export const MAX_REQUEST_BYTES = 256 * 1024;
/** EX-07 (K1): a scan with a page replica (≤ 400 KB of base64) plus the scan JSON. */
export const MAX_SCAN_BYTES = 512 * 1024;

/**
 * Only `POST /scans` exactly takes 512 KB. Hono also routes `/scans/` to it, so the check is on the
 * path itself: `/scans/`, `/scans/{id}`, `/replicas/*` and everything else stay at 256 KB.
 */
export function maxRequestBytes(method: string, path: string): number {
  return method === "POST" && path === "/scans" ? MAX_SCAN_BYTES : MAX_REQUEST_BYTES;
}
