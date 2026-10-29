import { decodeBase64 } from "./images";

/** contracts/api.md "Page replica" = replica-build.js MAX_BASE64 (400 KB of base64). */
export const MAX_REPLICA_BASE64 = 409_600;
/** The gzip bytes 409 600 base64 characters decode to at most; also the largest object put in R2. */
export const MAX_REPLICA_BYTES = 307_200;
/** = replica-build.js MAX_HTML_BYTES: the inflated page, counted while inflating (ISIZE is not trusted). */
export const MAX_REPLICA_HTML = 3_145_728;
/**
 * gzip input per DecompressionStream write (K2, D-alief-C25 e). One write inflates its whole input
 * before the output can be counted, and zero-gzip inflates ±1000:1, so a 300 KB write could expand
 * to ±300 MB. 4 KB slices bound one step to ±4 MB.
 */
export const INFLATE_SLICE = 4096;

export type ReplicaDrop = "invalid" | "too_large" | "not_gzip";

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
