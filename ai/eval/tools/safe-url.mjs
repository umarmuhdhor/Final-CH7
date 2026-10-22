// Guard for capture.mjs: only public http(s) hosts. Pages we capture are untrusted; a redirect or a name must never
// lead the tool to localhost, the LAN, or a cloud metadata address. Known limit: the name is resolved here and again by
// fetch, so a host that changes its answer between the two (DNS rebinding) is not stopped.
import { lookup } from "node:dns/promises";
import { isIP } from "node:net";

function v4(ip) {
    const [a, b, c] = ip.split(".").map(Number);
    return (
        a === 0 || a === 10 || a === 127 || a >= 224 || // this-net, private, loopback, multicast/reserved
        (a === 100 && b >= 64 && b <= 127) || // CGNAT
        (a === 169 && b === 254) || // link-local, cloud metadata
        (a === 172 && b >= 16 && b <= 31) ||
        (a === 192 && b === 168) ||
        (a === 192 && b === 0 && c === 0) ||
        (a === 198 && (b === 18 || b === 19))
    );
}

/** Eight 16-bit groups of an IPv6 address; a trailing dotted IPv4 part becomes two groups. */
function groups6(ip) {
    const v4tail = /(\d+)\.(\d+)\.(\d+)\.(\d+)$/.exec(ip);
    const text = v4tail ? ip.slice(0, v4tail.index) + ((+v4tail[1] << 8) | +v4tail[2]).toString(16) + ":" + ((+v4tail[3] << 8) | +v4tail[4]).toString(16) : ip;
    const [head, tail = ""] = text.split("::");
    const h = head ? head.split(":") : [];
    const t = tail ? tail.split(":") : [];
    const fill = text.includes("::") ? Array(8 - h.length - t.length).fill("0") : [];
    return [...h, ...fill, ...t].map((x) => parseInt(x, 16));
}

export function isPrivateAddress(ip) {
    const kind = isIP(ip);
    if (kind === 4) return v4(ip);
    if (kind !== 6) return true; // not an address we understand: refuse
    const g = groups6(ip.toLowerCase());
    if (g.every((x, i) => (i === 7 ? x <= 1 : x === 0))) return true; // :: and ::1
    if (g.slice(0, 5).every((x) => x === 0) && g[5] === 0xffff) return v4(`${g[6] >> 8}.${g[6] & 255}.${g[7] >> 8}.${g[7] & 255}`); // ::ffff:a.b.c.d
    return (g[0] & 0xfe00) === 0xfc00 || (g[0] & 0xffc0) === 0xfe80 || (g[0] & 0xff00) === 0xff00 || (g[0] === 0x2001 && g[1] === 0x0db8);
}

const defaultResolve = async (host) => (await lookup(host, { all: true })).map((r) => r.address);
const BAD_SUFFIX = /\.(local|localhost|internal|localdomain|lan|home|corp)$/;

/** @returns {Promise<URL>} the parsed URL, or throws why it was refused */
export async function assertPublicUrl(raw, { resolve = defaultResolve } = {}) {
    let u;
    try {
        u = new URL(raw);
    } catch {
        throw new Error("not a valid URL");
    }
    if (!["http:", "https:"].includes(u.protocol)) throw new Error(`only http(s), not ${u.protocol}`);
    if (u.username || u.password) throw new Error("URLs with credentials are refused");
    if (u.port) throw new Error(`port ${u.port} is refused (only the default 80/443)`);
    const host = u.hostname.replace(/^\[|\]$/g, "").toLowerCase();
    if (isIP(host)) {
        if (isPrivateAddress(host)) throw new Error(`${host} is a private or reserved address`);
        return u;
    }
    if (!host.includes(".") || BAD_SUFFIX.test(host)) throw new Error(`${host} is not a public host name`);
    let addrs;
    try {
        addrs = await resolve(host);
    } catch (e) {
        throw new Error(`cannot resolve ${host}: ${e.message}`);
    }
    if (!addrs.length) throw new Error(`${host} did not resolve`);
    const priv = addrs.find(isPrivateAddress);
    if (priv) throw new Error(`${host} resolves to a private address (${priv})`);
    return u;
}
