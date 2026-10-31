// Fence test (C3a). Nonce'd script injected into uji-pagar.html only.
// Registers violation listener first, then after the page settles reports what happened.
(() => {
    const violations = [];
    document.addEventListener("securitypolicyviolation", (e) => {
        violations.push(`${e.violatedDirective} ${e.blockedURI || "inline"}`.slice(0, 120));
    });
    const startHref = location.href;

    async function lapor() {
        const f = document.getElementById("f");
        try {
            f.requestSubmit(document.getElementById("b")); // submit via the button
        } catch (e) {
            violations.push("requestSubmit error " + e);
        }
        await new Promise((r) => setTimeout(r, 700));
        const img = document.getElementById("i");
        const body = {
            startHref,
            endHref: location.href,
            title: document.title,
            ranWithoutNonce: window.__ranNoNonce === true,
            imgLoaded: img.complete && img.naturalWidth > 0,
            violations,
            ua: navigator.userAgent,
        };
        await fetch("/hasil-uji", {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify(body),
        });
        document.body.append(" [laporan terkirim]");
    }

    window.addEventListener("load", () => setTimeout(lapor, 1200));
})();
