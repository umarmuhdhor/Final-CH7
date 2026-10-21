import type { Context } from "hono";
import { z } from "zod";
import { errors } from "./errors";

const DEFAULT_MAX_BYTES = 16 * 1024;

/** Reads a JSON body: 413 too_large, 400 bad_json, 422 invalid_body (contract error codes). */
export async function readJson<S extends z.ZodType>(
  c: Context,
  schema: S,
  maxBytes = DEFAULT_MAX_BYTES,
): Promise<z.infer<S>> {
  const text = await readText(c.req.raw, maxBytes);

  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    throw errors.badJson();
  }
  return parse(schema, data);
}

/** Reads at most maxBytes, also for chunked bodies without content-length. */
async function readText(req: Request, maxBytes: number): Promise<string> {
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > maxBytes) throw errors.tooLarge();
  if (!req.body) return "";

  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel();
      throw errors.tooLarge();
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

export function parse<S extends z.ZodType>(schema: S, data: unknown): z.infer<S> {
  const result = schema.safeParse(data);
  if (!result.success) {
    const message = result.error.issues
      .map((i) => `${i.path.join(".") || "body"}: ${i.message}`)
      .join("; ");
    throw errors.invalidBody(message);
  }
  return result.data;
}

/** Character count as Postgres char_length sees it (code points, not UTF-16 units). */
export const codePoints = (s: string) => [...s].length;

// Control characters (NUL included: Postgres text rejects it) and bidi overrides that could
// disguise a name in push text and the Guardian UI.
const UNSAFE_TEXT = /[\p{Cc}\u200E\u200F\u202A-\u202E\u2066-\u2069]/u;

/** Display name: 1–20 code points after trim, no control or bidi characters. */
export const displayName = z
  .string()
  .trim()
  .refine((s) => codePoints(s) >= 1 && codePoints(s) <= 20, "must be 1-20 characters")
  .refine((s) => !UNSAFE_TEXT.test(s), "must not contain control characters");

/** ISO 8601 with offset, limited to years Postgres and Date both handle the same way. */
export const isoTime = z.iso.datetime({ offset: true }).refine((v) => {
  const year = new Date(v).getUTCFullYear();
  return year >= 1970 && year <= 2100;
}, "must be between 1970 and 2100");
