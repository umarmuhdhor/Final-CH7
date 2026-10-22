// Owner: Team AI. Layer 2 (link name) = M1. Layer 1 (database) = M5-B, via ShooLists.match. Contract: contracts/detector-interface.md
// Pure rules, no network (layer 1 data comes from the extension's globalThis.ShooLists). detector/data/brands.json is inlined at build time (scripts/build.mjs) into the placeholder below.
//
// Suspicion levels (how sure we are that the name imitates a brand). Weights are starting values, calibrated in M6.
//   Level 0  official domain (listed in brands.json)        -> no signals at all
//   Level 1  weak:   official name on an unlisted domain, or a cheap TLD alone      (+10 / +5)  never reaches 30 alone
//   Level 2  medium: brand + bait word (bca-verifikasi), cheap TLD next to a brand  (+14 / +15)
//   Level 3  strong: spelled like a brand (p0stindonesia, lphone, homoglyphs)       (+25)

(function () {
    "use strict";

    const DATA = /*__BRANDS_JSON__*/ null;

    const WEIGHT = { lookalike: 25, nameOnly: 10, brandKeyword: 14, cheapTldWithBrand: 15, cheapTldAlone: 5 };

    // Cyrillic / Greek / Armenian letters that look like Latin ones.
    const CONFUSABLES = {
        "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x", "і": "i", "ј": "j", "ӏ": "l", "ԁ": "d",
        "ԛ": "q", "ѕ": "s", "һ": "h", "ԝ": "w", "ɡ": "g", "ɑ": "a", "ο": "o", "α": "a", "ν": "v", "ι": "i", "ρ": "p",
        "τ": "t", "ε": "e", "κ": "k", "υ": "u", "ս": "u",
    };

    // ---------- index (built once) ----------
    let index = null;
    function buildIndex() {
        const names = new Map(); // name -> { brand, common }
        const official = new Set();
        for (const brand of DATA.brands) {
            for (const n of brand.names) names.set(n, { brand, common: (brand.commonNames || []).includes(n) });
            for (const d of brand.domains) official.add(d);
        }
        return {
            names,
            official,
            suffixes: new Set(DATA.suffixes),
            cheap: new Set(DATA.cheapTlds),
            keywords: new Set(DATA.keywords),
        };
    }

    // ---------- punycode (RFC 3492) so xn-- labels can be compared as the letters a person sees ----------
    function punyDecode(input) {
        const base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700;
        const adapt = (delta, count, first) => {
            delta = first ? Math.floor(delta / damp) : delta >> 1;
            delta += Math.floor(delta / count);
            let k = 0;
            while (delta > (((base - tMin) * tMax) >> 1)) {
                delta = Math.floor(delta / (base - tMin));
                k += base;
            }
            return k + Math.floor(((base - tMin + 1) * delta) / (delta + skew));
        };
        const digitOf = (c) => (c >= 48 && c <= 57 ? c - 22 : c >= 65 && c <= 90 ? c - 65 : c >= 97 && c <= 122 ? c - 97 : base);
        let n = 128, i = 0, bias = 72;
        const out = [];
        const basic = input.lastIndexOf("-");
        for (let j = 0; j < Math.max(basic, 0); j++) {
            if (input.charCodeAt(j) >= 128) throw new Error("bad punycode");
            out.push(input.charCodeAt(j));
        }
        for (let pos = basic > 0 ? basic + 1 : 0; pos < input.length; ) {
            const oldi = i;
            let w = 1;
            for (let k = base; ; k += base) {
                if (pos >= input.length) throw new Error("bad punycode");
                const digit = digitOf(input.charCodeAt(pos++));
                if (digit >= base) throw new Error("bad punycode");
                i += digit * w;
                const t = k <= bias ? tMin : k >= bias + tMax ? tMax : k - bias;
                if (digit < t) break;
                w *= base - t;
            }
            const len = out.length + 1;
            bias = adapt(i - oldi, len, oldi === 0);
            n += Math.floor(i / len);
            i %= len;
            out.splice(i++, 0, n);
        }
        return String.fromCodePoint(...out);
    }

    function toUnicodeLabel(label) {
        if (!label.startsWith("xn--")) return label;
        try {
            return punyDecode(label.slice(4));
        } catch (error) {
            return label;
        }
    }

    // ---------- string helpers ----------
    function fold(s) {
        let out = "";
        for (const ch of s.normalize("NFKD").replace(/[̀-ͯ]/g, "")) out += CONFUSABLES[ch] || ch;
        return out;
    }

    /** Digit / letter swaps people use: g00gle, p0st, rn -> m. Every variant is compared with the brand names. */
    function variants(s) {
        const map = { "0": "o", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s" };
        const swapped = s.replace(/[03457@$]/g, (c) => map[c]);
        const bases = new Set([swapped, swapped.replace(/rn/g, "m").replace(/vv/g, "w")]);
        const out = new Set();
        for (const b of bases) {
            if (b.includes("1")) {
                out.add(b.replace(/1/g, "i"));
                out.add(b.replace(/1/g, "l"));
            } else out.add(b);
        }
        out.delete(s);
        return out;
    }

    /** Optimal string alignment distance (insert, delete, replace, swap neighbours). */
    function distance(a, b) {
        const m = a.length, n = b.length;
        const d = Array.from({ length: m + 1 }, (_, i) => [i, ...Array(n).fill(0)]);
        for (let j = 0; j <= n; j++) d[0][j] = j;
        for (let i = 1; i <= m; i++) {
            for (let j = 1; j <= n; j++) {
                const cost = a[i - 1] === b[j - 1] ? 0 : 1;
                d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost);
                if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
            }
        }
        return d[m][n];
    }

    // ---------- matching ----------
    /** @returns {{brand: object, name: string, common: boolean, kind: "exact"|"lookalike", how: string} | null} */
    function matchToken(token, allowFuzzy) {
        const exact = index.names.get(token);
        if (exact) return { brand: exact.brand, name: token, common: exact.common, kind: "exact", how: "name" };

        const folded = fold(token);
        const f = index.names.get(folded);
        if (folded !== token && f) return { brand: f.brand, name: folded, common: f.common, kind: "lookalike", how: "homoglyph" };

        for (const v of variants(folded)) {
            const hit = index.names.get(v);
            if (hit) return { brand: hit.brand, name: v, common: hit.common, kind: "lookalike", how: "leet" };
        }

        if (allowFuzzy && folded.length >= 6) {
            for (const [name, entry] of index.names) {
                if (entry.common || name.length < 6 || Math.abs(name.length - folded.length) > 2) continue;
                if (distance(folded, name) <= (name.length >= 9 ? 2 : 1)) {
                    return { brand: entry.brand, name, common: false, kind: "lookalike", how: "typo" };
                }
            }
        }
        return null;
    }

    /** "bcalogin" -> brand "bca" + keyword "login" (no hyphen). */
    function matchGlued(token) {
        if (token.length < 6) return null;
        for (const kw of index.keywords) {
            if (token.length <= kw.length + 2) continue;
            let rest = null;
            if (token.endsWith(kw)) rest = token.slice(0, -kw.length);
            else if (token.startsWith(kw)) rest = token.slice(kw.length);
            if (!rest) continue;
            const hit = matchToken(rest, false);
            if (hit) return { ...hit, keyword: kw };
        }
        return null;
    }

    // ---------- host handling ----------
    function hostOf(snapshot) {
        try {
            if (typeof URL === "function" && snapshot.url) return new URL(snapshot.url).hostname.toLowerCase().replace(/\.+$/, "");
        } catch (error) {
            /* fall through to snapshot.domain */
        }
        return String(snapshot.domain || "").toLowerCase().replace(/\.+$/, "");
    }

    function isOfficial(host) {
        const labels = host.split(".");
        for (let i = 0; i < labels.length - 1; i++) {
            if (index.official.has(labels.slice(i).join("."))) return true;
        }
        return false;
    }

    // ---------- signal texts (English + Bahasa Indonesia) ----------
    const T = {
        lookalike: (b) => ({
            label: { en: `Domain spelled like ${b}`, id: `Nama domain meniru ${b}` },
            labelSimple: { en: `This address looks like ${b}'s, but it is not the real one`, id: `Alamat ini mirip alamat ${b}, tapi bukan yang asli` },
        }),
        nameOnly: (b) => ({
            label: { en: `Uses the name ${b} but is not an official ${b} domain`, id: `Memakai nama ${b} tapi bukan domain resmi ${b}` },
            labelSimple: { en: `This site uses the name ${b}. It may not be the real one`, id: `Situs ini memakai nama ${b}. Bisa jadi bukan yang asli` },
        }),
        brandKeyword: (b, kw) => ({
            label: { en: `Brand name plus extra word (${b} + ${kw})`, id: `Nama brand ditambah kata lain (${b} + ${kw})` },
            labelSimple: { en: `This address mixes ${b} with the word "${kw}"`, id: `Alamat ini menggabungkan ${b} dengan kata "${kw}"` },
        }),
        cheapTld: (tld) => ({
            label: { en: `Cheap domain ending .${tld}`, id: `Akhiran domain murah .${tld}` },
            labelSimple: { en: "This site uses a cheap address ending that scammers often use", id: "Situs ini memakai akhiran alamat murah yang sering dipakai penipu" },
        }),
        dbMatch: (source) => ({
            label: {
                en: source === "shoo" ? "Reported and confirmed as a scam by Shoo" : "Found on a public list of phishing sites",
                id: source === "shoo" ? "Dilaporkan dan dipastikan sebagai penipuan oleh Shoo" : "Ada di daftar publik situs phishing",
            },
            labelSimple: { en: "This site is known to cheat people. Do not enter anything here", id: "Situs ini sudah dikenal menipu orang. Jangan isi apa pun di sini" },
        }),
    };

    function signal(id, weight, texts, evidence, layer = 2) {
        return { id, layer, weight, label: texts.label, labelSimple: texts.labelSimple, evidence };
    }

    // ---------- layer 1: database (hostname only; the lists live in the extension) ----------
    /** @returns {Promise<object[] | null>} [db_match] on a hit, otherwise null (also when ShooLists is absent or fails). */
    async function matchLists(snapshot) {
        const host = hostOf(snapshot);
        if (!host || host.includes(":") || /^\d{1,3}(\.\d{1,3}){3}$/.test(host)) return null;
        try {
            const hit = await globalThis.ShooLists?.match(host);
            const source = hit && typeof hit === "object" ? hit.source : null;
            if (source !== "shoo" && source !== "public") return null; // contract: only these two sources exist
            return [signal("db_match", 100, T.dbMatch(source), source, 1)];
        } catch (error) {
            return null;
        }
    }

    // ---------- main ----------
    function analyze(snapshot) {
        if (!index) index = buildIndex();
        const host = hostOf(snapshot);
        if (!host || host.includes(":") || /^\d{1,3}(\.\d{1,3}){3}$/.test(host)) return [];
        if (isOfficial(host) || (snapshot.domain && isOfficial(String(snapshot.domain).toLowerCase()))) return [];

        const labels = host.split(".");
        const suffixLen = labels.length > 2 && index.suffixes.has(labels.slice(-2).join(".")) ? 2 : 1;
        const tld = labels[labels.length - 1];
        const nameLabels = labels.slice(0, -suffixLen).filter((l) => l && l !== "www").map(toUnicodeLabel);

        const parts = [];
        const candidates = [];
        for (const label of nameLabels) {
            const pieces = label.split("-").filter(Boolean);
            parts.push(...pieces);
            candidates.push(...pieces);
            if (pieces.length > 1) candidates.push(pieces.join(""));
        }

        const hits = [];
        const seen = new Set();
        const add = (hit) => {
            if (!hit) return;
            const key = hit.brand.id + hit.kind;
            if (seen.has(key)) return;
            seen.add(key);
            hits.push(hit);
        };
        for (const c of candidates) add(matchToken(c, true));
        let keyword = parts.find((p) => index.keywords.has(p)) || null;
        if (!keyword) {
            for (const p of parts) {
                const glued = matchGlued(p);
                if (glued) {
                    add(glued);
                    keyword = glued.keyword;
                    break;
                }
            }
        }

        const look = hits.find((h) => h.kind === "lookalike");
        const exact = hits.find((h) => h.kind === "exact");
        const signals = [];

        if (look) {
            signals.push(signal("lookalike_domain", WEIGHT.lookalike, T.lookalike(look.brand.name), `${look.brand.id} · level 3 · ${look.how}`));
        }
        const brandHit = look || exact;
        if (brandHit && keyword) {
            signals.push(signal("brand_plus_keyword", WEIGHT.brandKeyword, T.brandKeyword(brandHit.brand.name, keyword), `${brandHit.brand.id} · level 2 · ${keyword}`));
        } else if (exact && !exact.common && !look) {
            signals.push(signal("lookalike_domain", WEIGHT.nameOnly, T.nameOnly(exact.brand.name), `${exact.brand.id} · level 1 · name on unlisted domain`));
        }
        if (suffixLen === 1 && index.cheap.has(tld)) {
            const withBrand = signals.length > 0;
            signals.push(signal("cheap_tld", withBrand ? WEIGHT.cheapTldWithBrand : WEIGHT.cheapTldAlone, T.cheapTld(tld), withBrand ? `.${tld} · level 2` : `.${tld} · level 1`));
        }
        return signals;
    }

    globalThis.ShooDetector = {
        version: "0.1.0",

        /**
         * @param {object} snapshot PageSnapshot
         * @returns {Promise<Array<{id: string, layer: number, weight: number, label: {en: string, id: string}, labelSimple: {en: string, id: string}, evidence?: string}>>}
         */
        analyzeLocal: async (snapshot) => {
            try {
                if (!DATA) return [];
                const snap = snapshot || {};
                return (await matchLists(snap)) || analyze(snap);
            } catch (error) {
                return [];
            }
        },
    };
})();
