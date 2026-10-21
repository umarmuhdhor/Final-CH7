import type { Context } from "hono";
import type { z } from "zod";
import { errors } from "./errors";

const DEFAULT_MAX_BYTES = 16 * 1024;

/** Reads a JSON body: 413 too_large, 400 bad_json, 422 invalid_body (contract error codes). */
export async function readJson<S extends z.ZodType>(
  c: Context,
  schema: S,
  maxBytes = DEFAULT_MAX_BYTES,
): Promise<z.infer<S>> {
  const declared = Number(c.req.header("content-length") ?? "0");
  if (declared > maxBytes) throw errors.tooLarge();
  const text = await c.req.text();
  if (new TextEncoder().encode(text).byteLength > maxBytes) throw errors.tooLarge();

  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    throw errors.badJson();
  }
  return parse(schema, data);
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
