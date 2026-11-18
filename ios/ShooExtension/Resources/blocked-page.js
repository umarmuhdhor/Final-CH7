// Owner: lead. Block screen behaviour (EX-06), runs inside blocked.html.
// Protected (Figma "Safari / Blocked / Protected"): no button, no "Link sent to" pill; reopens by itself once the
// domain is marked safe. Guardian: "Review in Shoo" → Detail (reviewing, not deciding: PRD 8.2); its page also
// reopens after marking it safe for themselves (PRD §5 Validasi).

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
            autoNote: simple, // Figma "Safari / Blocked / Protected": "We blocked this page automatically."
            // Figma: Protected only goes back to a safe page; the Guardian decides in the app.
            button:
                mode === null
                    ? { textKey: "block_open_app", href: "shoo://activity" }
                    : mode === "protected"
                      ? null
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

    /** One paragraph from the reason lines (Figma): each line ends with a full stop, joined by spaces. */
    function sentence(lines) {
        return lines
            .map((line) => String(line).trim())
            .filter(Boolean)
            .map((line) => (/[.!?]$/.test(line) ? line : `${line}.`))
            .join(" ");
    }

    globalThis.ShooBlockedPage = { viewFor, detailUrl, nextPollMs, middleEllipsis, sentence };

    // ---- Page ---------------------------------------------------------------------------

    if (typeof document === "undefined" || typeof browser === "undefined") return;

    const t = (key, subs) => browser.i18n.getMessage(key, subs) || key;
    const lang = "id"; // always Bahasa Indonesia, whatever the device language (contracts/app-group-keys.md "Language")
    const $ = (selector) => document.querySelector(selector);
    const send = (message) => browser.runtime.sendMessage(message);

    document.documentElement.lang = lang;
    const keys = { title: "block_title", back: "block_back" };
    for (const node of document.querySelectorAll("[data-text]")) node.textContent = t(keys[node.dataset.text]);
    document.title = t("block_title");

    // Back to the page before this one (block.js replaced the scam page, so Back skips it).
    // `history.length > 1` doesn't mean a page is behind this one: a scam that pushState-d before it was blocked
    // leaves this screen first with an entry *after* it, and Back then did nothing. Still here after Back → leave
    // to a blank page, as the warning popup's leave() does.
    $(".back").addEventListener("click", () => {
        if (history.length <= 1) return location.replace("about:blank");
        const from = location.href;
        history.back();
        setTimeout(() => {
            if (location.href === from) location.replace("about:blank");
        }, 1000);
    });

    const payload = globalThis.ShooBlock.decode(location.hash);
    $(".screen").hidden = false;
    if (!payload) {
        // Fragment missing or edited: still blocked, just without details. Never reopen anything.
        for (const selector of [".score", ".link", ".reasons"]) $(selector).hidden = true;
        return;
    }

    // One piece per layer (block.js `layers`); an older fragment without it falls back to the top reasons.
    const layers = payload.layers ?? globalThis.ShooGauge.layerWeights(payload.reasons);
    globalThis.ShooGauge.fillBar($(".bar"), payload.score, layers, (tag) => document.createElement(tag));
    $(".score-value").textContent = `${payload.score}/100`;
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

        const lines = view.remembered ? [t("block_remembered")] : [...view.reasons];
        if (view.autoNote) lines.push(t("block_auto"));
        const reasons = $(".reasons");
        reasons.textContent = sentence(lines);
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
            const hostname = new URL(payload.url).hostname;
            const reply = await send({ type: "domain", hostname });
            // Or the page's own host: content.js sends that when its background didn't answer in time. Still this
            // page, never another site, and background works the real domain out of the URL for every lookup.
            domainMatches = reply?.domain === payload.domain ||
                payload.domain === hostname.toLowerCase().replace(/\.+$/, "").replace(/^www\./, "");
        } catch {
            domainMatches = false;
        }
        if (view.poll && domainMatches) poll();
    }

    // EX-07: the POST may still be running when this page opens. Asked again on every poll until it exists.
    let recordAnswered = false; // asked background at least once with an answer
    async function findRecord() {
        if ((recordId && recordAnswered) || !payload.reportKey || !view?.button || mode === null) return;
        const reply = await send({ type: "recordId", key: payload.reportKey }).catch(() => null);
        if (!reply?.recordId) return;
        recordAnswered = true;
        recordId = reply.recordId;
        showRecord();
    }

    /** Once the scan is stored: "Review in Shoo" opens it. */
    function showRecord() {
        if (!recordId || !view?.button || mode === null) return;
        $(".button").href = detailUrl({ recordId });
    }

    let timer = null;
    const openedAt = Date.now();
    async function poll() {
        clearTimeout(timer);
        timer = null;
        let reply = null;
        try {
            reply = await send({ type: "verdict", domain: payload.domain, url: payload.url, fresh: true });
        } catch {
            reply = null; // offline → keep waiting
        }
        const verdict = reply?.verdict ?? null;
        // `reopen`: this page was blocked from memory and the Guardian marked the reported page of the site safe.
        if (verdict?.value === "safe" || reply?.reopen === true) {
            location.replace(payload.url); // reopens; the rescan sees the safe verdict (or scans the page afresh)
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
