import { b64 } from "./images";

const bytesOf = async (stream: ReadableStream<Uint8Array>) => new Uint8Array(await new Response(stream).arrayBuffer());

/** gzip like the extension does (CompressionStream, replica-build.js). */
export async function gzip(data: Uint8Array | string): Promise<Uint8Array> {
  const input = typeof data === "string" ? new TextEncoder().encode(data) : data;
  return bytesOf(new Blob([input]).stream().pipeThrough(new CompressionStream("gzip")));
}

export const gzipBase64 = async (data: Uint8Array | string) => b64(await gzip(data));

/** gzip of `megabytes` MB of zeros, streamed so the input is never held in memory (≈ 1 KB out per 1 MB in). */
export async function zeroBomb(megabytes: number): Promise<Uint8Array> {
  const cs = new CompressionStream("gzip");
  const writer = cs.writable.getWriter();
  const out = bytesOf(cs.readable);
  const mb = new Uint8Array(1 << 20);
  for (let i = 0; i < megabytes; i++) await writer.write(mb);
  await writer.close();
  return out;
}

/** A small replica page like replica.js writes (meta first, no scripts). */
export const SAMPLE_HTML =
  '<!doctype html><html lang="id"><head><meta name="shoo-replica" content="{&quot;v&quot;:1}">' +
  "<style>body{font:16px system-ui}</style></head><body><h1>Masuk BCA</h1><form><input type=\"text\"></form></body></html>";
