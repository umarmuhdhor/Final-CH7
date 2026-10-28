// Owner: lead. Block screen behaviour (EX-06), runs inside blocked.html.
// Protected: "Waiting for [guardian] to check", reopens by itself once the domain is marked safe.
// Guardian: "Review in Shoo" → Detail; also reopens after marking it safe for themselves (PRD §5 Validasi).

(() => {
    const POLL_MS = 5000; // contracts/api.md: poll GET /verdicts every 5 s while blocked

    /**
     * Pure: what the screen shows for this viewer. Kept free of DOM so it can be tested in Node.
     * @param {object|null} profile  { onboarded, mode, guardianName } from background
     * @param {object} payload       ShooBlock.decode() result
     * @param {"en"|"id"} lang
     */
    function viewFor(profile, payload, lang) {
        const mode = profile?.onboarded ? profile.mode : null;
        const simple = mode === "protected"; // parents get the plain wording (DT-04)
        return {
            reasons: payload.reasons
                .map((r) => (simple ? r.labelSimple : r.label)?.[lang])
                .filter(Boolean),
            waitingFor: mode === "protected" ? (profile.guardianName || null) : undefined,
            showWaiting: mode === "protected",
            button:
                mode === "guardian"
                    ? { textKey: "block_review", href: detailUrl(payload) }
                    : mode === null
                      ? { textKey: "block_open_app", href: "shoo://activity" }
                      : null, // Protected never decides (PRD 8.2)
            poll: mode !== null,
        };
    }

    /** 429 → wait at least Retry-After (backend/API.md), never treat it as "no verdict yet". */
    function nextPollMs(reply) {
        return reply?.rateLimited ? Math.max(POLL_MS, Number(reply.retryAfterMs) || 0) : POLL_MS;
    }

    function detailUrl(payload) {
        return payload.recordId ? `shoo://scan/${encodeURIComponent(payload.recordId)}` : "shoo://activity";
    }

    globalThis.ShooBlockedPage = { viewFor, detailUrl, nextPollMs };

    // ---- Page ---------------------------------------------------------------------------

    if (typeof document === "undefined" || typeof browser === "undefined") return;

    const t = (key, subs) => browser.i18n.getMessage(key, subs) || key;
    const lang = (browser.i18n.getUILanguage?.() || "en").toLowerCase().startsWith("id") ? "id" : "en";
    const $ = (selector) => document.querySelector(selector);
    const send = (message) => browser.runtime.sendMessage(message);

    document.documentElement.lang = lang;
    const keys = { title: "block_title", autoOpen: "block_auto_open", back: "block_back" };
    for (const node of document.querySelectorAll("[data-text]")) node.textContent = t(keys[node.dataset.text]);
    document.title = t("block_title");

    // Back to the page before this one (block.js replaced the scam page, so Back skips it).
    $(".back").addEventListener("click", () => {
        if (history.length > 1) history.back();
        else location.replace("about:blank");
    });

    const payload = globalThis.ShooBlock.decode(location.hash);
    $(".screen").hidden = false;
    if (!payload) {
        // Fragment missing or edited: still blocked, just without details. Never reopen anything.
        for (const selector of [".ring", ".link", ".reasons"]) $(selector).hidden = true;
        return;
    }

    $(".ring").style.setProperty("--p", String(payload.score));
    $(".score-value").textContent = `${payload.score}%`;
    $(".link").textContent = payload.domain || payload.url;

    let mode = null;
    async function start() {
        let profile = null;
        try {
            profile = await send({ type: "profile" });
        } catch {
            profile = null;
        }
        const view = viewFor(profile, payload, lang);
        mode = profile?.onboarded ? profile.mode : null;

        const reasons = $(".reasons");
        reasons.replaceChildren(...view.reasons.map((text) => Object.assign(document.createElement("span"), { textContent: text })));
        reasons.hidden = view.reasons.length === 0;

        if (view.showWaiting) {
            $(".waiting").hidden = false;
            $(".waiting-text").textContent = view.waitingFor
                ? t("block_waiting", [view.waitingFor])
                : t("block_waiting_family");
        }
        if (view.button) {
            const button = $(".button");
            button.textContent = t(view.button.textKey);
            button.href = view.button.href;
            button.hidden = false;
            linkToRecord(button);
        }
        // Only reopen the page this block is really about: a crafted link can't pair a scam URL
        // with some other domain that happens to be marked safe.
        let domainMatches = false;
        try {
            const reply = await send({ type: "domain", hostname: new URL(payload.url).hostname });
            domainMatches = reply?.domain === payload.domain;
        } catch {
            domainMatches = false;
        }
        if (view.poll && domainMatches) poll();
    }

    // EX-07: the POST may still be running when this page opens; point "Review in Shoo" at the record once it exists.
    async function linkToRecord(button) {
        if (payload.recordId || !payload.reportKey || mode !== "guardian") return;
        const reply = await send({ type: "recordId", key: payload.reportKey }).catch(() => null);
        if (reply?.recordId) button.href = detailUrl({ recordId: reply.recordId });
    }

    let timer = null;
    async function poll() {
        clearTimeout(timer);
        timer = null;
        let reply = null;
        try {
            reply = await send({ type: "verdict", domain: payload.domain, fresh: true });
        } catch {
            reply = null; // offline → keep waiting
        }
        const verdict = reply?.verdict ?? null;
        if (verdict?.value === "safe") {
            location.replace(payload.url); // reopens; the rescan sees the safe verdict and stays quiet
            return;
        }
        if (verdict?.value === "not_safe") {
            $(".waiting").hidden = true;
            const note = $(".verified");
            note.textContent = t("block_verified_scam", [verdict.byName || "Shoo"]);
            note.hidden = false;
            return; // decided — stays blocked for good
        }
        timer = setTimeout(poll, nextPollMs(reply));
    }

    // Coming back from the Shoo app (Guardian just reviewed it) → check right away.
    document.addEventListener("visibilitychange", () => {
        if (document.visibilityState === "visible" && timer) poll();
    });

    start();
})();
