/**
 * What may be logged about an error: its name and Postgres SQLSTATE. Never the message, which can
 * quote ids, names, tokens or URLs (SECURITY §3 P6, D-alief-40).
 */
export function errorInfo(err: unknown): { name: string; code?: string } {
  const e = err as { name?: unknown; code?: unknown } | null;
  const name = typeof e?.name === "string" ? e.name : "Error";
  return typeof e?.code === "string" && /^[0-9A-Z]{5}$/.test(e.code) ? { name, code: e.code } : { name };
}
