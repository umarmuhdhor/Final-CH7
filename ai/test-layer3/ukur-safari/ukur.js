// Runs inside Safari, as the ONLY nonce'd script of a served page (page scripts are blocked by CSP).
// Times the same scan as ukur-telegram.mjs, but on the live DOM: inline <script> text + form actions.
// The server inlines ukur-safari/pola.js before this file.
(() => {
    const me = document.getElementById("shoo-ukur");
    const nama = me.dataset.nama;
    const { scanTeks } = globalThis.ShooPola;

    function pindai() {
        const parts = [];
        let bytes = 0;
        let n = 0;
        for (const s of document.querySelectorAll("script:not([src])")) {
            if (s.id === "shoo-ukur") continue;
            const t = s.textContent;
            parts.push(t);
            bytes += t.length;
            n++;
        }
        for (const f of document.querySelectorAll("form[action]")) parts.push(f.getAttribute("action"));
        return { hit: scanTeks(parts.join("\n")), bytes, n };
    }

    function ukur() {
        const t0 = performance.now();
        const first = pindai();
        const coldMs = performance.now() - t0; // one call, timer is ~1 ms coarse: informational only

        // Timer is coarse: at least 200 scans and at least 50 ms in total, then divide.
        let reps = 0;
        const start = performance.now();
        let now;
        do {
            for (let i = 0; i < 50; i++) pindai();
            reps += 50;
            now = performance.now();
        } while (reps < 200 || now - start < 50);
        return {
            nama,
            meanMs: (now - start) / reps,
            reps,
            coldMs,
            bytes: first.bytes,
            n: first.n,
            hit: first.hit,
            ua: navigator.userAgent,
        };
    }

    async function kirim(body) {
        const r = await fetch("/hasil", {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify(body),
        });
        const { next } = await r.json();
        if (next) location.href = next;
    }

    function jalan() {
        let body;
        try {
            body = ukur();
        } catch (e) {
            body = { nama, error: String(e) };
        }
        kirim(body);
    }

    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", jalan);
    else jalan();
})();
