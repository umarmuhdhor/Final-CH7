// GENERATED from detector/ by detector/scripts/sync-to-extension.sh — DO NOT EDIT HERE.
// Owner: Lead (taken over from Team AI). Layer 2 (link) = M1 + whole-link dissector (#140). Layer 1 (database) = M5-B, via ShooLists.match. Contract: contracts/detector-interface.md
// Pure rules, no network (layer 1 data comes from the extension's globalThis.ShooLists). detector/data/brands.json and link-rules.json are inlined at build time (scripts/build.mjs) into the placeholders below.
//
// Layer 2 has two parts that add up (score = sum of signal weights, computed by the extension):
//   A. Brand check (this block): does the NAME imitate one of the 25 brands in brands.json?
//   B. Link dissector (dissectLink below): the WHOLE URL, one `suspicious_link` signal. Each part of the URL scores on its
//      own, hosting-platform subdomains are judged by their first label and file name. Its weight is the raw score (max 100), no cap.
//
// Brand suspicion levels (how sure we are that the name imitates a brand). Weights are starting values, calibrated in M6.
//   Level 0  official domain (listed in brands.json)        -> no signals at all
//   Level 1  weak:   official name on an unlisted domain, or a cheap TLD alone      (+10 / +5)  never reaches 30 alone
//   Level 2  medium: brand + bait word (bca-verifikasi), cheap TLD next to a brand  (+14 / +15)
//   Level 3  strong: spelled like a brand (p0stindonesia, lphone, homoglyphs)       (+25)

(function () {
    "use strict";

    const DATA = {"version":1,"suffixes":["co.id","go.id","or.id","ac.id","web.id","sch.id","my.id","biz.id","desa.id","mil.id","net.id","co.uk","org.uk","com.au","co.jp","com.sg","com.my","co.in"],"cheapTlds":["xyz","site","click","top","icu","buzz","cfd","sbs","tk","ml","ga","cf","gq","link","vip","rest","monster","quest","cyou","bond","work","fun","online"],"keywords":["verifikasi","verify","verification","login","signin","masuk","promo","undian","hadiah","klaim","claim","bansos","bantuan","cek","update","perbarui","secure","security","official","resmi","akun","account","blokir","unlock","reset","otp","kyc","refund","voucher","bonus","gratis","support","cs"],"brands":[{"id":"bca","name":"BCA","names":["bca","klikbca","mybca"],"commonNames":[],"domains":["bca.co.id","klikbca.com"]},{"id":"bri","name":"BRI","names":["bri","brimo"],"commonNames":[],"domains":["bri.co.id"]},{"id":"mandiri","name":"Bank Mandiri","names":["mandiri","bankmandiri","livinmandiri"],"commonNames":["mandiri"],"domains":["bankmandiri.co.id"]},{"id":"bni","name":"BNI","names":["bni"],"commonNames":[],"domains":["bni.co.id"]},{"id":"bsi","name":"BSI","names":["bsi","bankbsi"],"commonNames":[],"domains":["bankbsi.co.id"]},{"id":"dana","name":"DANA","names":["dana"],"commonNames":["dana"],"domains":["dana.id"]},{"id":"ovo","name":"OVO","names":["ovo"],"commonNames":[],"domains":["ovo.id"]},{"id":"gopay","name":"GoPay","names":["gopay","gojek"],"commonNames":[],"domains":["gopay.co.id","gojek.com"]},{"id":"shopee","name":"Shopee","names":["shopee","shopeepay","shopeefood"],"commonNames":[],"domains":["shopee.co.id","shopee.com"]},{"id":"tokopedia","name":"Tokopedia","names":["tokopedia","tokped"],"commonNames":[],"domains":["tokopedia.com"]},{"id":"lazada","name":"Lazada","names":["lazada"],"commonNames":[],"domains":["lazada.co.id","lazada.com"]},{"id":"bukalapak","name":"Bukalapak","names":["bukalapak"],"commonNames":[],"domains":["bukalapak.com"]},{"id":"posindonesia","name":"Pos Indonesia","names":["posindonesia","postindonesia"],"commonNames":[],"domains":["posindonesia.co.id"]},{"id":"jne","name":"JNE","names":["jne"],"commonNames":[],"domains":["jne.co.id"]},{"id":"jnt","name":"J&T Express","names":["jnt","jntexpress","jtexpress"],"commonNames":[],"domains":["jet.co.id"]},{"id":"kemensos","name":"Kemensos","names":["kemensos"],"commonNames":[],"domains":["kemensos.go.id"]},{"id":"djp","name":"DJP (Pajak)","names":["djp"],"commonNames":[],"domains":["pajak.go.id"]},{"id":"bpjs","name":"BPJS","names":["bpjs","bpjskesehatan","bpjsketenagakerjaan"],"commonNames":[],"domains":["bpjs-kesehatan.go.id","bpjsketenagakerjaan.go.id"]},{"id":"apple","name":"Apple","names":["apple","iphone","icloud","appleid","itunes"],"commonNames":["apple"],"domains":["apple.com","icloud.com"]},{"id":"google","name":"Google","names":["google","gmail"],"commonNames":[],"domains":["google.com","google.co.id","gmail.com","youtube.com"]},{"id":"microsoft","name":"Microsoft","names":["microsoft","outlook","office365"],"commonNames":[],"domains":["microsoft.com","live.com","office.com","outlook.com","microsoftonline.com"]},{"id":"meta","name":"Meta","names":["facebook","instagram","whatsapp","meta"],"commonNames":["meta"],"domains":["facebook.com","instagram.com","whatsapp.com","fb.com","meta.com"]},{"id":"netflix","name":"Netflix","names":["netflix"],"commonNames":[],"domains":["netflix.com"]},{"id":"paypal","name":"PayPal","names":["paypal"],"commonNames":[],"domains":["paypal.com"]},{"id":"amazon","name":"Amazon","names":["amazon"],"commonNames":[],"domains":["amazon.com"]}]};
    const LINK = {"version":1,"rareTlds":["info","pw","cc","ws","su"],"freeHosts":["blogspot.com","blogspot.co.id","github.io","netlify.app","pages.dev","vercel.app","web.app","firebaseapp.com","weebly.com","wixsite.com","wordpress.com","herokuapp.com","glitch.me","workers.dev","cloudfront.net","r2.dev","webflow.io","000webhostapp.com","sites.google.com","s3.amazonaws.com"],"baitWords":["gratis","bantuan","bansos","kuota","hadiah","undian","klaim","promo","pulsa","saldo","subsidi","pencairan","verifikasi","resmi","official","bonus","giveaway","reward","voucher","cashback","kurir","paket","tracking","lowongan","pinjaman","pinjol","kripto","prakerja","login","update","claim","free"],"carriers":["dhl","fedex","sicepat","anteraja","ninjaxpress","wahana","tiki"]};

    const WEIGHT = { lookalike: 25, nameOnly: 10, brandKeyword: 14, cheapTldWithBrand: 15, cheapTldAlone: 5 };

    // Link dissector. Weights are starting values, not calibrated on real scams yet (D-imelda-45).
    const LINK_PART_CAP = 25; // one URL part cannot dominate
    const LINK_MIN_EMIT = 10; // below this the link says too little to show (a free host alone is 3)
    const FILE_EXT = /\.(html?|php\d?|aspx?|jsp)$/i;

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
            rareTlds: new Set(LINK.rareTlds),
            freeHosts: LINK.freeHosts,
            linkBait: LINK.baitWords,
            carriers: LINK.carriers,
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
        suspiciousLink: (reasons) => ({
            label: { en: `The link looks suspicious (${reasons.map((r) => REASON_TEXT[r].en).join(", ")})`, id: `Tautan terlihat mencurigakan (${reasons.map((r) => REASON_TEXT[r].id).join(", ")})` },
            labelSimple: { en: "The address of this page looks like the ones scammers use", id: "Alamat halaman ini mirip alamat yang biasa dipakai penipu" },
        }),
        dbMatch: (source) => ({
            label: {
                en: source === "shoo" ? "Reported and confirmed as a scam by Shoo" : "Found on a public list of phishing sites",
                id: source === "shoo" ? "Dilaporkan dan dipastikan sebagai penipuan oleh Shoo" : "Ada di daftar publik situs phishing",
            },
            labelSimple: { en: "This site is known to cheat people. Do not enter anything here", id: "Situs ini sudah dikenal menipu orang. Jangan isi apa pun di sini" },
        }),
    };

    // Reason codes -> short phrases for the label. Only OUR words appear in a label, never text taken from the URL.
    const REASON_TEXT = {
        userinfo: { en: "hidden host before @", id: "host disembunyikan sebelum @" },
        ip_host: { en: "raw IP address", id: "alamat IP mentah" },
        punycode: { en: "disguised letters", id: "huruf menyamar" },
        many_labels: { en: "too many dots", id: "terlalu banyak titik" },
        many_hyphens: { en: "too many hyphens", id: "terlalu banyak tanda hubung" },
        digit_label: { en: "name made of digits", id: "nama penuh angka" },
        rare_tld: { en: "rare ending", id: "akhiran jarang" },
        odd_port: { en: "unusual port", id: "port tak lazim" },
        random_name: { en: "random file name", id: "nama file acak" },
        file_ext: { en: "page file ending", id: "akhiran file halaman" },
        slash_after_file: { en: "slash after file name", id: "garis miring setelah nama file" },
        path_bait: { en: "bait word in path", id: "kata umpan di path" },
        redirect_param: { en: "redirects elsewhere", id: "mengalihkan ke tempat lain" },
        email_param: { en: "email in link", id: "email di tautan" },
        long_query: { en: "very long link", id: "tautan sangat panjang" },
        url_in_fragment: { en: "link inside link", id: "tautan di dalam tautan" },
        long_url: { en: "very long link", id: "tautan sangat panjang" },
        http_no_tls: { en: "not encrypted", id: "tidak terenkripsi" },
        free_host: { en: "free hosting page", id: "halaman hosting gratis" },
        free_name_bait: { en: "bait word in the name", id: "kata umpan di nama" },
        free_name_number: { en: "year or amount in the name", id: "tahun atau jumlah di nama" },
        free_file_bait: { en: "bait word in the file name", id: "kata umpan di nama file" },
    };

    function signal(id, weight, texts, evidence, layer = 2) {
        return { id, layer, weight, label: texts.label, labelSimple: texts.labelSimple, evidence };
    }


    // ---------- layer 2B: whole-link dissector ----------
    function entropy(str) {
        const freq = {};
        for (const ch of str) freq[ch] = (freq[ch] || 0) + 1;
        let h = 0;
        for (const n of Object.values(freq)) h -= (n / str.length) * Math.log2(n / str.length);
        return h;
    }

    /** Loopback / private-range addresses: never a scam site, and they sit in front of people's own routers. */
    function isLocalAddress(host) {
        if (host === "localhost" || host.endsWith(".localhost") || host === "[::1]") return true;
        const m = host.match(/^(\d{1,3})\.(\d{1,3})\.\d{1,3}\.\d{1,3}$/);
        if (!m) return false;
        const a = +m[1], b = +m[2];
        return a === 10 || a === 127 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168);
    }

    const wordsIn = (text, list) => list.filter((w) => text.includes(w));

    /**
     * Scores the whole URL. Pure string work on `rawUrl`, the page is never opened.
     * Parts: scheme, userinfo, host, TLD, port, path, query, fragment, length (each capped at 25), then the free-hosting
     * checks, which are added on top: on blogspot / github.io / cloudfront ... the domain belongs to the platform, so
     * what says something is the first label and the file name.
     * @returns {{ score: number, reasons: string[] }} reasons are codes (see REASON_TEXT), never pieces of the URL: they are sent to the server as evidence.
     */
    function dissectLink(rawUrl) {
        const parts = []; // { part, weight, reason }
        const free = []; // added outside the per-part cap
        const add = (part, weight, reason) => parts.push({ part, weight, reason });
        let u;
        try {
            u = new URL(rawUrl);
        } catch (error) {
            return { score: 0, reasons: [] };
        }
        if (u.protocol !== "http:" && u.protocol !== "https:") return { score: 0, reasons: [] };
        if (isLocalAddress(u.hostname.toLowerCase())) return { score: 0, reasons: [] }; // router pages, dev servers

        if (u.protocol === "http:") add("scheme", 5, "http_no_tls");
        if (u.username || u.password) add("userinfo", 25, "userinfo");

        const host = u.hostname.toLowerCase().replace(/\.+$/, "");
        const labels = host.split(".");
        if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host) || host.includes(":")) add("host", 20, "ip_host");
        else {
            const suffixLen = labels.length > 2 && index.suffixes.has(labels.slice(-2).join(".")) ? 2 : 1;
            const tld = labels[labels.length - 1];
            const name = labels.slice(0, -suffixLen).map(toUnicodeLabel); // "xn--bcher-kva" has hyphens of its own: judge the letters people see
            if (labels.some((l) => l.startsWith("xn--"))) add("host", 5, "punycode");
            if (name.length >= 4) add("host", 8, "many_labels");
            if (name.some((l) => (l.match(/-/g) || []).length >= 3)) add("host", 8, "many_hyphens");
            if (name.some((l) => l.length >= 8 && (l.match(/\d/g) || []).length / l.length >= 0.4)) add("host", 8, "digit_label");
            // brands.json cheapTlds are already scored by the `cheap_tld` signal (part A); only the extra rare ones count here.
            if (suffixLen === 1 && index.rareTlds.has(tld) && !index.cheap.has(tld)) add("tld", 6, "rare_tld");
        }
        if (u.port && u.port !== "80" && u.port !== "443") add("port", 10, "odd_port");

        const segs = u.pathname.split("/").filter(Boolean);
        const last = segs[segs.length - 1] || "";
        const stem = last.replace(FILE_EXT, "");
        if (stem.length >= 20 && /^[a-z0-9_-]+$/i.test(stem) && entropy(stem) >= 3.3 && /\d/.test(stem)) add("path", 15, "random_name");
        if (FILE_EXT.test(last)) add("path-ext", 5, "file_ext");
        if (FILE_EXT.test(last) && u.pathname.endsWith("/")) add("path-slash", 8, "slash_after_file");
        if (segs.some((s) => s.split(/[^a-z]+/i).some((w) => index.keywords.has(w.toLowerCase())))) add("path-bait", 6, "path_bait");

        const q = [...u.searchParams];
        if (q.some(([k, v]) => /^(url|redirect|redir|next|return|goto|link|u)$/i.test(k) && /^(https?:)?\/\//i.test(v))) add("query", 12, "redirect_param");
        if (q.some(([, v]) => /\S+@\S+/.test(v))) add("query", 5, "email_param");
        if (u.search.length > 150) add("query", 5, "long_query");
        if (/https?:/i.test(u.hash)) add("fragment", 8, "url_in_fragment");
        if (rawUrl.length > 120) add("length", 4, "long_url");

        const platform = index.freeHosts.find((h) => host === h || host.endsWith("." + h));
        if (platform) {
            const label = host.slice(0, host.length - platform.length - 1).split(".").pop() || "";
            const file = (segs[segs.length - 1] || "").toLowerCase();
            const inLabel = [...wordsIn(label, index.linkBait), ...wordsIn(label, index.carriers)];
            const inFile = [...wordsIn(file, index.linkBait), ...wordsIn(file, index.carriers)];
            free.push({ weight: 3, reason: "free_host" });
            if (inLabel.length) free.push({ weight: inLabel.length >= 2 ? 16 : 10, reason: "free_name_bait" });
            if (/20\d\d|\d+(gb|mb|jt|rb)/.test(label)) free.push({ weight: 5, reason: "free_name_number" });
            if (inFile.length) free.push({ weight: 10, reason: "free_file_bait" });
        }

        const byPart = {};
        for (const p of parts) byPart[p.part] = Math.min(LINK_PART_CAP, (byPart[p.part] || 0) + p.weight);
        const score = Math.min(100, Object.values(byPart).reduce((a, b) => a + b, 0) + free.reduce((a, p) => a + p.weight, 0));
        const reasons = [...new Set([...parts, ...free].map((p) => p.reason))];
        return { score, reasons };
    }

    /** One `suspicious_link` signal, or null when the link says too little. Weight is the raw dissector score (max 100), no cap. */
    function linkSignal(snapshot) {
        if (!snapshot.url) return null;
        const { score, reasons } = dissectLink(String(snapshot.url));
        if (score < LINK_MIN_EMIT) return null;
        const shown = reasons.filter((r) => r !== "free_host" && r !== "file_ext" && r !== "http_no_tls" && r !== "long_url");
        const top = (shown.length ? shown : reasons).slice(0, 3);
        return signal("suspicious_link", score, T.suspiciousLink(top), reasons.join(","));
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
        if (host && isOfficial(host)) return [];
        if (snapshot.domain && isOfficial(String(snapshot.domain).toLowerCase())) return [];
        const link = linkSignal(snapshot);
        return [...analyzeBrand(snapshot, host), ...(link ? [link] : [])];
    }

    /** Layer 2A: does the host NAME imitate a brand? Skips raw IP hosts (no name to read). */
    function analyzeBrand(snapshot, host) {
        if (!host || host.includes(":") || /^\d{1,3}(\.\d{1,3}){3}$/.test(host)) return [];

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
        version: "0.2.0",

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
