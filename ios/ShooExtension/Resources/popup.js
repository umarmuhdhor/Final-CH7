// Owner: lead. Warning popup at 30% and 50% (EX-04). Plain script, loaded after pipeline.js.
// Rules (PRD §5, 8.5): each popup at most once per page · none if the page goes straight to ≥80%
// (block screen instead, EX-06) · closable · the page stays usable underneath.

(() => {
    const { THRESHOLD } = globalThis.ShooPipeline;

    /** 0 = nothing, 1 = first warning (30–49), 2 = second warning (50–79), "blocked" = ≥80. */
    function tierFor(score) {
        if (score >= THRESHOLD.blocked) return "blocked";
        if (score >= THRESHOLD.secondWarning) return 2;
        if (score >= THRESHOLD.firstWarning) return 1;
        return 0;
    }

    function freshMemo(scanId) {
        return { scanId, highestShown: 0, blocked: false, visibleTier: 0 };
    }

    /**
     * Pure decision: given what this page has shown so far and the newest pipeline state,
     * what should the popup do? Kept free of DOM so it can be tested in Node.
     * @returns {{ memo, actions: Array<{type: "show", tier} | {type: "update"} | {type: "hide"}> }}
     */
    function decide(memo, state) {
        const actions = [];
        if (!memo || memo.scanId !== state.scanId) {
            if (memo?.visibleTier) actions.push({ type: "hide" }); // new page → old popup goes
            memo = freshMemo(state.scanId);
        }
        const next = { ...memo };
        const tier = tierFor(state.score);

        if (tier === "blocked" || memo.blocked) {
            next.blocked = true; // block screen owns the page from here on
            next.visibleTier = 0;
            if (memo.visibleTier) actions.push({ type: "hide" });
        } else if (tier === 0) {
            next.visibleTier = 0; // only a "safe" verdict brings the score back down
            if (memo.visibleTier) actions.push({ type: "hide" });
        } else if (tier > memo.highestShown) {
            next.highestShown = tier;
            next.visibleTier = tier;
            actions.push({ type: "show", tier });
        } else if (tier === memo.visibleTier) {
            actions.push({ type: "update" });
        }
        return { memo: next, actions };
    }

    /** The user closed the popup: it stays closed for this tier on this page. */
    function dismissed(memo) {
        return memo ? { ...memo, visibleTier: 0 } : memo;
    }

    // Deep link into the app's Detail (DT-*). The scan id exists once EX-07 has POSTed the result.
    function detailUrl(state) {
        return state.recordId ? `shoo://scan/${encodeURIComponent(state.recordId)}` : "shoo://activity";
    }

    globalThis.ShooPopup = { tierFor, decide, dismissed, detailUrl };

    // ---- View (browser only) -------------------------------------------------------------

    if (typeof document === "undefined" || typeof browser === "undefined") return;

    const t = (key) => browser.i18n.getMessage(key) || key;

    const CSS = `
        :host { all: initial; }
        .card {
            position: fixed; left: 12px; right: 12px;
            bottom: calc(12px + env(safe-area-inset-bottom, 0px));
            z-index: 2147483647; box-sizing: border-box; max-width: 520px; margin: 0 auto;
            padding: 16px; border-radius: 18px; border: 2px solid var(--accent);
            background: #fff; color: #1c1c1e; box-shadow: 0 10px 30px rgba(0,0,0,.25);
            font: 16px/1.35 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
            animation: in .25s ease-out;
        }
        .card[data-tier="1"] { --accent: #f5a623; --chip: #fff4e0; --chip-text: #8a5300; }
        .card[data-tier="2"] { --accent: #e5484d; --chip: #ffe8e8; --chip-text: #a1161c; }
        @keyframes in { from { transform: translateY(24px); opacity: 0; } }
        @media (prefers-reduced-motion: reduce) { .card { animation: none; } }
        .top { display: flex; align-items: center; gap: 8px; }
        .chip { padding: 3px 10px; border-radius: 999px; background: var(--chip); color: var(--chip-text);
                font-weight: 700; font-size: 13px; text-transform: uppercase; letter-spacing: .03em; }
        .score { margin-left: auto; font-weight: 800; font-size: 22px; color: var(--chip-text); }
        .close { width: 36px; height: 36px; margin-left: 4px; border: 0; border-radius: 50%;
                 background: #f2f2f7; color: #3a3a3c; font-size: 20px; line-height: 1; cursor: pointer; }
        h2 { margin: 10px 0 4px; font-size: 19px; line-height: 1.25; }
        p { margin: 0 0 8px; }
        .link { display: block; margin-bottom: 12px; color: #636366; font-size: 14px;
                overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .detail { display: block; padding: 12px; border-radius: 12px; background: var(--accent);
                  color: #fff; text-align: center; font-weight: 700; text-decoration: none; }
        .card[data-tier="1"] .detail { color: #1c1c1e; }
    `;

    let host = null;
    let refs = null;

    function el(tag, className, text) {
        const node = document.createElement(tag);
        if (className) node.className = className;
        if (text != null) node.textContent = text;
        return node;
    }

    function mount() {
        if (host?.isConnected) return;
        host = document.createElement("shoo-warning");
        const root = host.attachShadow({ mode: "closed" });
        const style = el("style");
        style.textContent = CSS;

        const card = el("div", "card");
        card.setAttribute("role", "alertdialog");
        card.setAttribute("aria-live", "assertive");
        const top = el("div", "top");
        const chip = el("span", "chip", t("popup_status_warning"));
        const score = el("span", "score");
        const close = el("button", "close", "×");
        close.type = "button";
        close.setAttribute("aria-label", t("popup_close"));
        close.addEventListener("click", () => {
            memo = dismissed(memo);
            hide();
        });
        top.append(chip, score, close);

        const title = el("h2");
        const body = el("p");
        const link = el("span", "link");
        const detail = el("a", "detail", t("popup_see_detail"));
        card.append(top, title, body, link, detail);
        root.append(style, card);

        refs = { card, score, title, body, link, detail };
        document.documentElement.appendChild(host);
    }

    function render(state, tier) {
        mount();
        refs.card.dataset.tier = String(tier);
        refs.title.textContent = t(`popup_title_${tier}`);
        refs.body.textContent = t(`popup_body_${tier}`);
        refs.card.setAttribute("aria-label", refs.title.textContent);
        update(state);
    }

    function update(state) {
        if (!refs) return;
        refs.score.textContent = `${state.score}%`;
        refs.link.textContent = state.url;
        refs.detail.href = detailUrl(state);
    }

    function hide() {
        host?.remove();
        host = null;
        refs = null;
    }

    let memo = null;
    globalThis.ShooPipeline.subscribe((state) => {
        const result = decide(memo, state);
        memo = result.memo;
        for (const action of result.actions) {
            if (action.type === "show") render(state, action.tier);
            else if (action.type === "update") update(state);
            else if (action.type === "hide") hide();
        }
    });
})();
