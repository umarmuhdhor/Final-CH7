// Owner: lead. Block screen behaviour (EX-06), runs inside blocked.html.
// Protected: "Link sent to [guardian]" once the scan is reported (EX-07); reopens by itself once the domain
// is marked safe. Guardian and Protected: "Review in Shoo" → Detail (reviewing, not deciding: PRD 8.2);
// a Guardian's page also reopens after marking it safe for themselves (PRD §5 Validasi).

(() => {
    // #350 (contracts/api.md): fast while a Guardian is most likely deciding, slower once it's been a while.
    const POLL_STEPS = [
        { until: 2 * 60 * 1000, every: 2000 },
        { until: 10 * 60 * 1000, every: 5000 },
        { until: Infinity, every: 15000 },
    ];

    /**
     * Pure: what the screen shows for this viewer. Kept free of DOM so it can be tested in Node.
     * @param {object|null} profile  { onboarded, mode, guardianName } from background
     * @param {object} payload       ShooBlock.decode() result
     * @param {"en"|"id"} lang
     */
    function viewFor(profile, payload, lang) {
        const mode = profile?.onboarded ? profile.mode : null;
        const simple = mode === "protected"; // parents get the plain wording (DT-04)
        const lookalike = lookalikeNote(payload, lang);
        return {
            // #382: a block from memory can be about a sibling page (another subdomain of the same site), so its
            // reasons may not fit this page. It shows one generic line instead (`remembered` → block_remembered).
            remembered: Boolean(payload.remembered),
            reasons: payload.remembered
                ? []
                : payload.reasons
                      .filter((r) => !(lookalike && r.id === "lookalike_domain")) // already said under the chip
                      .map((r) => (simple ? r.labelSimple : r.label)?.[lang])
                      .filter(Boolean),
            chip: middleEllipsis(payload.domain || payload.url),
            lookalike,
            sentTo: mode === "protected" ? profile.guardianName || null : null,
            button:
                mode === null
                    ? { textKey: "block_open_app", href: "shoo://activity" }
                    : { textKey: "block_review", href: detailUrl(payload) },
            poll: mode !== null,
        };
    }

    /**
     * #382: long names are cut in the middle, so the ending (".xyz", ".co.id") always shows. The chip keeps
     * a CSS end-ellipsis only as a backstop for very narrow screens.
     */
    function middleEllipsis(text, max = 32) {
        const value = String(text ?? "");
        if (value.length <= max) return value;
        const lastDot = value.lastIndexOf(".");
        const ending = lastDot > 0 ? value.length - lastDot : 0;
        const tail = Math.min(max - 4, Math.max(Math.floor((max - 1) / 2), ending));
        return `${value.slice(0, max - 1 - tail)}…${value.slice(-tail)}`;
    }

    /**
     * #382: an IDN look-alike stays in punycode on the chip (the decoded letters are what fool the eye), with
     * the detector's own "spelled like <brand>" line under it.
     */
    function lookalikeNote(payload, lang) {
        const name = String(payload.domain || "");
        if (!name.split(".").some((label) => label.startsWith("xn--"))) return null;
        const reason = payload.reasons.find((r) => r.id === "lookalike_domain");
        return reason?.label?.[lang] || null;
    }

    /** 429 → wait at least Retry-After (backend/API.md), never treat it as "no verdict yet". */
    /** @param {number} openForMs  how long this block screen has been open */
    function nextPollMs(reply, openForMs = 0) {
        const every = POLL_STEPS.find((step) => openForMs < step.until).every;
        return reply?.rateLimited ? Math.max(every, Number(reply.retryAfterMs) || 0) : every;
    }

    function detailUrl(payload) {
        return payload.recordId ? `shoo://scan/${encodeURIComponent(payload.recordId)}` : "shoo://activity";
    }

    globalThis.ShooBlockedPage = { viewFor, detailUrl, nextPollMs, middleEllipsis };

    // ---- Page ---------------------------------------------------------------------------

    if (typeof document === "undefined" || typeof browser === "undefined") return;

    const t = (key, subs) => browser.i18n.getMessage(key, subs) || key;
    const lang = (browser.i18n.getUILanguage?.() || "en").toLowerCase().startsWith("id") ? "id" : "en";
    const $ = (selector) => document.querySelector(selector);
    const send = (message) => browser.runtime.sendMessage(message);

    document.documentElement.lang = lang;
    const keys = { title: "block_title", level: "popup_status_2", back: "block_back" };
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
        for (const selector of [".gauge", ".link", ".reasons"]) $(selector).hidden = true;
        return;
    }

    $(".gauge-art").innerHTML = globalThis.ShooGauge.gauge(payload.score, "bahaya"); // our markup from a number
    $(".score-value").textContent = `${payload.score}%`;
    $(".link").textContent = globalThis.ShooBlockedPage.middleEllipsis(payload.domain || payload.url);
    $(".link").title = payload.domain || payload.url;

    let mode = null;
    let view = null;
    let recordId = payload.recordId || null;
    async function start() {
        let profile = null;
        try {
            profile = await send({ type: "profile" });
        } catch {
            profile = null;
        }
        view = viewFor(profile, payload, lang);
        mode = profile?.onboarded ? profile.mode : null;

        const lines = view.remembered ? [t("block_remembered")] : view.reasons;
        const reasons = $(".reasons");
        reasons.replaceChildren(...lines.map((text) => Object.assign(document.createElement("span"), { textContent: text })));
        reasons.hidden = lines.length === 0;
        if (view.lookalike) {
            $(".lookalike").textContent = view.lookalike;
            $(".lookalike").hidden = false;
        }

        if (view.button) {
            const button = $(".button");
            button.textContent = t(view.button.textKey);
            button.href = view.button.href;
            button.hidden = false;
        }
        showRecord();
        findRecord();
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

    // EX-07: the POST may still be running when this page opens. Asked again on every poll until it exists.
    let recordAnswered = false; // asked background at least once with an answer (it also carries `notified`, #377)
    async function findRecord() {
        if ((recordId && recordAnswered) || !payload.reportKey || mode === null) return;
        const reply = await send({ type: "recordId", key: payload.reportKey }).catch(() => null);
        if (!reply?.recordId) return;
        recordAnswered = true;
        recordId = reply.recordId;
        // #377: the backend says who it really pushed (null = nobody). Older backends say nothing: keep the name.
        if (view && "notified" in reply) view.sentTo = mode === "protected" ? reply.notified || null : null;
        showRecord();
    }

    /** Once the scan is stored: "Review in Shoo" opens it, and Protected sees who it went to. */
    function showRecord() {
        if (!recordId || !view) return;
        if (view.button && mode !== null) $(".button").href = detailUrl({ recordId });
        if (!view.sentTo) {
            $(".sent").hidden = true; // #377: the backend said nobody got it
            return;
        }
        $(".avatar").textContent = Array.from(view.sentTo)[0].toUpperCase();
        const [before = "", after = ""] = t("popup_sent_to", ["\u0000"]).split("\u0000");
        $(".sent-text").replaceChildren(before, Object.assign(document.createElement("b"), { textContent: view.sentTo }), after);
        $(".sent").hidden = false;
    }

    let timer = null;
    const openedAt = Date.now();
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
            const note = $(".verified");
            note.textContent = t("block_verified_scam", [verdict.byName || "Shoo"]);
            note.hidden = false;
            return; // decided — stays blocked for good
        }
        findRecord();
        timer = setTimeout(poll, nextPollMs(reply, Date.now() - openedAt));
    }

    // Coming back from the Shoo app (Guardian just reviewed it) → check right away.
    document.addEventListener("visibilitychange", () => {
        if (document.visibilityState === "visible" && timer) poll();
    });

    start();
})();
