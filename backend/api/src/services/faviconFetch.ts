import { sniffImage } from "./images";

/**
 * PR-05: the Worker downloads a scam site's favicon once, so the app never contacts the scam host
 * (SECURITY P9: no IP leak, no cached copy of the site's image on the phone). The URL comes from a
 * web page, so every step is guarded: http(s) on the default port only, no credentials, only public
 * addresses (literal IPs checked, names resolved over DoH first), at most 2 redirects re-checked hop
 * by hop, 3 s for everything, 64 KB, raster images only (Content-Type and magic bytes, never SVG),
 * at most 512 px per side (the app shows nothing larger; also no decompression bombs on the phone).
 * Workers' fetch keeps no cookies and we send no Referer; the User-Agent names no user or device.
 * The DoH check cannot stop a host that answers differently a moment later (DNS rebinding); a
 * Worker's own subrequests do not reach private networks, so this is defence in depth.
 */

export type FaviconType = "png" | "ico" | "jpeg" | "gif" | "webp";

export interface Favicon {
  type: FaviconType;
  bytes: Uint8Array;
}

export type FetchFail =
  | "bad_url"
  | "private_address"
  | "dns_failed"
  | "too_many_redirects"
  | "bad_status"
  | "bad_type"
  | "too_large"
  | "bad_magic"
  | "bad_size"
  | "timeout"
  | "network";

export type Download = { ok: true; favicon: Favicon } | { ok: false; reason: FetchFail };

/** Content type we store and serve, chosen from the magic bytes (not from the site's header). */
export const FAVICON_CONTENT_TYPE: Record<FaviconType, string> = {
  png: "image/png",
  ico: "image/x-icon",
  jpeg: "image/jpeg",
  gif: "image/gif",
  webp: "image/webp",
};
export const FAVICON_EXT: Record<FaviconType, string> = { png: "png", ico: "ico", jpeg: "jpg", gif: "gif", webp: "webp" };

const ACCEPTED_TYPES = new Set([
  "image/png", "image/x-icon", "image/vnd.microsoft.icon", "image/jpeg", "image/gif", "image/webp",
]);
export const MAX_FAVICON_BYTES = 64 * 1024;
export const MAX_FAVICON_SIDE = 512;
const TIMEOUT_MS = 3000;
const MAX_REDIRECTS = 2;
const USER_AGENT = "Mozilla/5.0 (compatible; ShooFavicon/1.0)";
const DOH = "https://cloudflare-dns.com/dns-query";
// Names that only mean something inside a private network.
const LOCAL_SUFFIXES = [".localhost", ".local", ".internal", ".intranet", ".lan", ".home", ".corp", ".arpa"];

type Fetcher = (input: string, init: RequestInit) => Promise<Response>;

export interface DownloadOptions {
  /** Tests only. */
  fetch?: Fetcher;
  timeoutMs?: number;
}

/** Never throws: any problem is a reason, and the scan is stored without a favicon. */
export async function downloadFavicon(raw: string, opts: DownloadOptions = {}): Promise<Download> {
  const fetcher: Fetcher = opts.fetch ?? ((input, init) => fetch(input, init));
  const signal = AbortSignal.timeout(opts.timeoutMs ?? TIMEOUT_MS);
  const fail = (reason: FetchFail): Download => ({ ok: false, reason });

  const first = checkUrl(raw);
  if (!first) return fail("bad_url");
  let url: URL = first;
  try {
    for (let hop = 0; ; hop++) {
      const blocked = await checkHost(url.hostname, fetcher, signal);
      if (blocked) return fail(blocked);
      const res = await fetcher(url.href, {
        method: "GET",
        redirect: "manual",
        headers: { "user-agent": USER_AGENT, accept: [...ACCEPTED_TYPES].join(",") },
        signal,
      });
      if ([301, 302, 303, 307, 308].includes(res.status)) {
        const location = res.headers.get("location");
        await res.body?.cancel();
        if (hop >= MAX_REDIRECTS) return fail("too_many_redirects");
        const next: URL | undefined = location ? checkUrl(location, url) : undefined;
        if (!next) return fail("bad_url");
        url = next;
        continue;
      }
      if (res.status !== 200) {
        await res.body?.cancel();
        return fail("bad_status");
      }
      const type = (res.headers.get("content-type") ?? "").split(";")[0]!.trim().toLowerCase();
      if (!ACCEPTED_TYPES.has(type)) {
        await res.body?.cancel();
        return fail("bad_type");
      }
      if (Number(res.headers.get("content-length") ?? 0) > MAX_FAVICON_BYTES) {
        await res.body?.cancel();
        return fail("too_large");
      }
      const bytes = await readCapped(res, MAX_FAVICON_BYTES);
      if (!bytes) return fail("too_large");
      const kind = sniffFavicon(bytes);
      if (!kind) return fail("bad_magic");
      const size = faviconSize(bytes, kind);
      if (!size || size.width < 1 || size.height < 1 || Math.max(size.width, size.height) > MAX_FAVICON_SIDE) return fail("bad_size");
      return { ok: true, favicon: { type: kind, bytes } };
    }
  } catch {
    return fail(signal.aborted ? "timeout" : "network");
  }
}

/** http(s), no user:password@, default port only. `base` resolves a relative redirect. */
export function checkUrl(raw: string, base?: URL): URL | undefined {
  let u: URL;
  try {
    u = new URL(raw, base);
  } catch {
    return undefined;
  }
  if (u.protocol !== "http:" && u.protocol !== "https:") return undefined;
  if (u.username || u.password || u.port !== "") return undefined;
  return u;
}

/** Undefined when the host may be fetched, else why not. */
async function checkHost(hostname: string, fetcher: Fetcher, signal: AbortSignal): Promise<FetchFail | undefined> {
  // The URL parser already turned every IPv4 spelling (0x7f.1, 2130706433, …) into dotted decimal.
  if (hostname.startsWith("[")) return isPublicIp(hostname.slice(1, -1)) ? undefined : "private_address";
  if (isIpv4(hostname)) return isPublicIp(hostname) ? undefined : "private_address";
  const name = hostname.replace(/\.$/, "");
  if (!name.includes(".") || name === "localhost" || LOCAL_SUFFIXES.some((s) => name.endsWith(s))) return "private_address";
  const addresses = await resolve(name, fetcher, signal);
  if (!addresses || addresses.length === 0) return "dns_failed";
  return addresses.every(isPublicIp) ? undefined : "private_address";
}

/** A and AAAA over DoH (JSON API). Undefined when a lookup fails: no address, no fetch. */
async function resolve(name: string, fetcher: Fetcher, signal: AbortSignal): Promise<string[] | undefined> {
  const ask = async (type: "A" | "AAAA"): Promise<string[] | undefined> => {
    const res = await fetcher(`${DOH}?name=${encodeURIComponent(name)}&type=${type}`, {
      headers: { accept: "application/dns-json" },
      signal,
    });
    if (!res.ok) {
      await res.body?.cancel();
      return undefined;
    }
    const body = (await res.json()) as { Status?: number; Answer?: { type?: number; data?: string }[] };
    // 0 = NOERROR, 3 = NXDOMAIN (no records of this type).
    if (body.Status !== 0 && body.Status !== 3) return undefined;
    const want = type === "A" ? 1 : 28;
    return (body.Answer ?? []).flatMap((a) => (a.type === want && typeof a.data === "string" ? [a.data] : []));
  };
  const [a, aaaa] = await Promise.all([ask("A"), ask("AAAA")]);
  return a && aaaa ? [...a, ...aaaa] : undefined;
}

async function readCapped(res: Response, max: number): Promise<Uint8Array | undefined> {
  if (!res.body) return new Uint8Array();
  const reader = res.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > max) {
      await reader.cancel();
      return undefined;
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let at = 0;
  for (const c of chunks) {
    out.set(c, at);
    at += c.byteLength;
  }
  return out;
}

/** Raster favicon types by magic bytes. SVG, HTML and anything else → undefined. */
export function sniffFavicon(b: Uint8Array): FaviconType | undefined {
  const starts = (sig: number[], at = 0) => b.length >= at + sig.length && sig.every((x, i) => b[at + i] === x);
  if (starts([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return "png";
  // ICONDIR: reserved 0, type 1 (icon, not cursor), at least one 16-byte entry.
  if (b.length >= 22 && starts([0x00, 0x00, 0x01, 0x00]) && (b[4]! | (b[5]! << 8)) >= 1) return "ico";
  if (starts([0xff, 0xd8, 0xff])) return "jpeg";
  if (starts([0x47, 0x49, 0x46, 0x38]) && (b[4] === 0x37 || b[4] === 0x39) && b[5] === 0x61) return "gif";
  if (starts([0x52, 0x49, 0x46, 0x46]) && starts([0x57, 0x45, 0x42, 0x50], 8)) return "webp";
  return undefined;
}

/**
 * Pixel size from the headers: PNG IHDR, GIF logical screen, JPEG SOFn, WebP VP8/VP8L/VP8X, ICO the
 * largest directory entry (0 means 256). Undefined when the header is cut short.
 */
export function faviconSize(b: Uint8Array, type: FaviconType): { width: number; height: number } | undefined {
  const u16le = (o: number) => b[o]! | (b[o + 1]! << 8);
  const u24le = (o: number) => b[o]! | (b[o + 1]! << 8) | (b[o + 2]! << 16);
  switch (type) {
    case "png": {
      const image = sniffImage(b);
      return image?.type === "png" ? image : undefined;
    }
    case "jpeg": {
      const image = sniffImage(b);
      return image?.type === "jpeg" ? image : undefined;
    }
    case "gif":
      return b.length >= 10 ? { width: u16le(6), height: u16le(8) } : undefined;
    case "ico": {
      const count = u16le(4);
      if (b.length < 6 + count * 16) return undefined;
      let width = 0;
      let height = 0;
      for (let i = 0; i < count; i++) {
        width = Math.max(width, b[6 + i * 16] || 256);
        height = Math.max(height, b[7 + i * 16] || 256);
      }
      return { width, height };
    }
    case "webp": {
      const chunk = String.fromCharCode(...b.subarray(12, 16));
      if (chunk === "VP8 " && b.length >= 30 && b[23] === 0x9d && b[24] === 0x01 && b[25] === 0x2a) {
        return { width: u16le(26) & 0x3fff, height: u16le(28) & 0x3fff };
      }
      if (chunk === "VP8L" && b.length >= 25 && b[20] === 0x2f) {
        const bits = (b[21]! | (b[22]! << 8) | (b[23]! << 16) | (b[24]! << 24)) >>> 0;
        return { width: (bits & 0x3fff) + 1, height: ((bits >>> 14) & 0x3fff) + 1 };
      }
      if (chunk === "VP8X" && b.length >= 30) return { width: u24le(24) + 1, height: u24le(27) + 1 };
      return undefined;
    }
  }
}

const isIpv4 = (s: string) => /^\d{1,3}(\.\d{1,3}){3}$/.test(s);

/** Only globally routable unicast addresses. Anything unparsable counts as not public. */
export function isPublicIp(ip: string): boolean {
  if (isIpv4(ip)) return isPublicIpv4(ip.split(".").map(Number));
  const h = ipv6Hextets(ip);
  if (!h) return false;
  // IPv4-mapped (::ffff:a.b.c.d) and NAT64 (64:ff9b::a.b.c.d) carry an IPv4 address.
  const tail = [h[6]! >> 8, h[6]! & 0xff, h[7]! >> 8, h[7]! & 0xff];
  if (h.slice(0, 5).every((x) => x === 0) && h[5] === 0xffff) return isPublicIpv4(tail);
  if (h[0] === 0x64 && h[1] === 0xff9b && h.slice(2, 6).every((x) => x === 0)) return isPublicIpv4(tail);
  if ((h[0]! & 0xe000) !== 0x2000) return false; // only 2000::/3 is global unicast
  if (h[0] === 0x2001 && h[1]! < 0x0200) return false; // IETF special use: Teredo, ORCHID, benchmarking
  if (h[0] === 0x2001 && h[1] === 0x0db8) return false; // documentation
  if (h[0] === 0x2002) return false; // 6to4 can wrap a private IPv4
  if (h[0] === 0x3fff && h[1]! < 0x1000) return false; // documentation (RFC 9637)
  return true;
}

function isPublicIpv4(o: number[]): boolean {
  if (o.length !== 4 || o.some((x) => !Number.isInteger(x) || x < 0 || x > 255)) return false;
  const [a, b, c] = o as [number, number, number, number];
  if (a === 0 || a === 10 || a === 127 || a >= 224) return false; // this network, private, loopback, multicast, reserved
  if (a === 100 && b >= 64 && b <= 127) return false; // carrier-grade NAT
  if (a === 169 && b === 254) return false; // link-local (cloud metadata)
  if (a === 172 && b >= 16 && b <= 31) return false;
  if (a === 192 && b === 168) return false;
  if (a === 192 && b === 0 && (c === 0 || c === 2)) return false; // IETF protocol, documentation
  if (a === 198 && (b === 18 || b === 19)) return false; // benchmarking
  if (a === 198 && b === 51 && c === 100) return false; // documentation
  if (a === 203 && b === 0 && c === 113) return false; // documentation
  return true;
}

/** Eight 16-bit groups, or undefined when the text is not an IPv6 address. */
function ipv6Hextets(ip: string): number[] | undefined {
  let text = ip.toLowerCase();
  if (text.includes("%")) return undefined; // zone ids are link-local by definition
  const dotted = /^(.*:)(\d{1,3}(?:\.\d{1,3}){3})$/.exec(text);
  let v4: number[] = [];
  if (dotted) {
    const o = dotted[2]!.split(".").map(Number);
    if (o.some((x) => x > 255)) return undefined;
    v4 = [(o[0]! << 8) | o[1]!, (o[2]! << 8) | o[3]!];
    text = dotted[1]!.endsWith("::") ? dotted[1]! : dotted[1]!.slice(0, -1);
  }
  const halves = text.split("::");
  if (halves.length > 2) return undefined;
  const parse = (s: string) => (s === "" ? [] : s.split(":"));
  const left = parse(halves[0]!);
  const right = halves.length === 2 ? parse(halves[1]!) : [];
  if ([...left, ...right].some((g) => !/^[0-9a-f]{1,4}$/.test(g))) return undefined;
  const missing = 8 - v4.length - left.length - right.length;
  if (halves.length === 1 ? missing !== 0 : missing < 1) return undefined;
  const groups = [...left, ...Array<string>(halves.length === 2 ? missing : 0).fill("0"), ...right].map((g) => parseInt(g, 16));
  return [...groups, ...v4];
}
