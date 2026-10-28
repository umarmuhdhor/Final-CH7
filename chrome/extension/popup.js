// Owner: lead. Warning popup at 30% and 50% (EX-04). Plain script, loaded after pipeline.js.
// Chrome copy of the Safari popup.js (Figma design, PR #160) without "See detail": there is no Shoo app
// on Chrome to open. Keep decide() / layoutFor() / describe() the same as Safari's.
// Rules (PRD §5, 8.5): each popup at most once per page · none if the page goes straight to ≥80%
// (block screen instead, EX-06) · closable · the page stays usable underneath.
// Look (Figma "UI Pop Up Safari"): 30–49% → mini card at the bottom · 50–79% → sheet over a dimmed
// page with Leave / Continue; Continue (or the Shoo button above it) shrinks it to the mini card.

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

    /** "sheet" blocks the page until the user picks Leave or Continue; "mini" sits above Safari's toolbar. */
    function layoutFor(tier, minimized) {
        return tier === 2 && !minimized ? "sheet" : "mini";
    }

    /** Card text: the heaviest reason, then the tier's advice. Protected gets the plain wording (DT-04). */
    function describe(signals, { simple, lang, advice }) {
        const top = [...(signals ?? [])]
            .sort((a, b) => b.weight - a.weight)
            .map((s) => (simple ? s.labelSimple : s.label)?.[lang])
            .find(Boolean);
        if (!top) return advice;
        return `${/[.!?]$/.test(top) ? top : `${top}.`} ${advice}`;
    }

    globalThis.ShooPopup = { tierFor, decide, dismissed, layoutFor, describe };

    // ---- View (browser only) -------------------------------------------------------------

    if (typeof document === "undefined" || typeof browser === "undefined") return;

    const t = (key) => browser.i18n.getMessage(key) || key;
    const lang = (browser.i18n.getUILanguage?.() || "en").toLowerCase().startsWith("id") ? "id" : "en";

    // Sizes and colours from Figma (frames "Pertama kali buka langsung ke detect", "Safari / Warning Sedang / Minimized").
    const CSS = `
        :host { all: initial; }
        .ui { --ink: #151617; --muted: #6a717e;
              font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", "Segoe UI", Roboto, sans-serif; color: var(--ink);
              -webkit-font-smoothing: antialiased; }
        .rounded { font-family: ui-rounded, "SF Pro Rounded", -apple-system, BlinkMacSystemFont, sans-serif; }
        button, a { -webkit-tap-highlight-color: transparent; }

        .ring { position: relative; flex: none; width: var(--size); height: var(--size); border-radius: 50%;
                box-sizing: border-box; border: 1px solid #e4e6ea;
                background: linear-gradient(#fff, #f3f4f6); box-shadow: 0 4px 12px rgba(31,42,55,.08); }
        /* insets are inside the 1px border: track 4px and centre 24.5px from the outer edge at 124px (Figma) */
        .ring::before { content: ""; position: absolute; inset: var(--bezel); border-radius: 50%;
                box-shadow: inset 0 1px 2px rgba(31,42,55,.08);
                background: conic-gradient(transparent 0 calc(var(--p) * 1%), #ecedef 0),
                            radial-gradient(closest-side, #eb8900 68%, #ff9500 76%, #ffb752 86%, #ff9500 95%, #e58600 100%); }
        .center { position: absolute; inset: var(--hole); border-radius: 50%; box-sizing: border-box;
                  border: 1px solid #e3e4e7; background: linear-gradient(#fafafb, #f0f1f3);
                  box-shadow: inset 0 2px 4px rgba(31,42,55,.06);
                  display: flex; align-items: center; justify-content: center;
                  font-size: 22px; letter-spacing: -.02em; }

        .dim { position: fixed; inset: 0; z-index: 2147483646; background: rgba(125,129,135,.5);
               -webkit-backdrop-filter: blur(4px); backdrop-filter: blur(4px); animation: fade .25s ease-out; }
        .sheet { position: fixed; z-index: 2147483647; left: 12px; right: 12px; max-width: 400px; margin: 0 auto;
                 bottom: calc(12px + env(safe-area-inset-bottom, 0px)); box-sizing: border-box;
                 border-radius: 40px; border: 1px solid rgba(255,255,255,.9);
                 background: linear-gradient(#f9fafb, #f1f2f4);
                 box-shadow: 0 24px 48px rgba(31,42,55,.18), 0 2px 6px rgba(31,42,55,.06);
                 animation: rise .3s ease-out; }
        .shoo { position: absolute; right: 0; top: -56px; width: 44px; height: 44px; padding: 0;
                border-radius: 50%; border: 1px solid rgba(255,255,255,.9); background: rgba(255,255,255,.88);
                -webkit-backdrop-filter: blur(14px); backdrop-filter: blur(14px);
                box-shadow: 0 6px 18px rgba(31,42,55,.12); cursor: pointer;
                display: flex; align-items: center; justify-content: center; }
        .shoo img { width: 30px; height: 30px; border-radius: 50%; }
        .hero { display: flex; flex-direction: column; align-items: center; gap: 16px; padding: 30px 0 22px;
                border-bottom: 1px solid #e1e3e7; }
        .hero .ring { --size: 124px; --bezel: 3px; --hole: 23.5px; }
        .caption { font-size: 17px; font-weight: 600; letter-spacing: .06em; color: #f69001; text-transform: uppercase; }
        .body { display: flex; flex-direction: column; gap: 32px; padding: 24px 22px; }
        .copy { display: flex; flex-direction: column; align-items: center; gap: 8px; text-align: center; }
        .chip { max-width: 100%; box-sizing: border-box; padding: 7px 13px; border-radius: 999px; background: #e8eaed;
                box-shadow: inset 0 1px 1px rgba(255,255,255,.9); font-size: 13px; font-weight: 500;
                overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .text { display: flex; flex-direction: column; gap: 4px; }
        h2 { margin: 0; font-size: 22px; font-weight: 600; line-height: 1.4; letter-spacing: -.01em; }
        .sheet p { margin: 0; font-size: 15px; line-height: 1.5; color: var(--muted); }
        .actions { display: flex; flex-direction: column; gap: 10px; }
        .primary, .secondary { display: flex; align-items: center; justify-content: center; width: 100%;
                border-radius: 999px; font: 500 17px/22px -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; cursor: pointer; }
        .primary { height: 52px; border: 1px solid rgba(28,29,32,.6); color: #fff;
                   background: linear-gradient(#191c25, #3c435a);
                   box-shadow: inset 0 1.5px 1px rgba(255,255,255,.22), inset 0 -2px 4px rgba(0,0,0,.25); }
        .secondary { height: 54px; border: 0; color: #191c25; background: #fff; letter-spacing: -.0125em;
                     box-shadow: 0 0 0 1px #e3e3e3, 0 3px 5px -3px rgba(0,0,0,.2); }

        .mini { position: fixed; z-index: 2147483647; left: 16px; right: 16px; max-width: 360px; margin: 0 auto;
                bottom: calc(12px + env(safe-area-inset-bottom, 0px)); padding-top: 11px; animation: rise .25s ease-out; }
        .banner { display: flex; align-items: center; gap: 12px; padding: 14px; border-radius: 24px;
                  border: 1px solid rgba(255,255,255,.9); background: rgba(255,255,255,.92);
                  -webkit-backdrop-filter: blur(14px); backdrop-filter: blur(14px);
                  box-shadow: 0 12px 28px rgba(31,42,55,.14), 0 1px 3px rgba(31,42,55,.05); }
        .banner .ring { --size: 72px; --bezel: 1.3px; --hole: 13.3px; box-shadow: 0 2px 7px rgba(31,42,55,.08); }
        .lines { display: flex; flex-direction: column; gap: 4px; min-width: 0; padding-right: 8px; }
        .title { display: flex; align-items: center; gap: 8px; font-size: 17px; font-weight: 600;
                 line-height: 1.4; letter-spacing: -.01em; }
        .dot { width: 4px; height: 4px; border-radius: 50%; background: #c7c7ce; }
        .mini p { margin: 0; font-size: 13px; line-height: 1.4; color: var(--muted); }
        .close { position: absolute; right: 0; top: 0; width: 28px; height: 28px; padding: 0; border-radius: 50%;
                 border: 1px solid #f9f9fa; background: #e8eaed; cursor: pointer;
                 display: flex; align-items: center; justify-content: center; }
        .close svg { width: 12px; height: 12px; stroke: #6a717e; stroke-width: 1.1; stroke-linecap: round; }

        @keyframes rise { from { transform: translateY(24px); opacity: 0; } }
        @keyframes fade { from { opacity: 0; } }
        @media (prefers-reduced-motion: reduce) { .dim, .sheet, .mini { animation: none; } }
    `;

    const CLOSE_ICON = '<svg viewBox="0 0 12 12" aria-hidden="true"><path d="M3 3l6 6M9 3l-6 6"/></svg>';

    const dom = globalThis.ShooDom; // the page can shadow document properties and hide our host (dom.js)
    let host = null;
    let release = () => {}; // stops guarding host
    let ui = null; // the shadow root's wrapper; EX-07 hides it
    let refs = null; // the visible layout's nodes
    let simple = false; // Protected → plain reason wording
    let last = null; // newest { state, tier, minimized }

    browser.runtime
        .sendMessage({ type: "profile" })
        .then((p) => {
            simple = Boolean(p?.onboarded && p.mode === "protected");
            if (last) update(last.state);
        })
        .catch(() => {});

    function el(tag, className, text) {
        const node = dom.create(document, tag);
        if (className) node.className = className;
        if (text != null) node.textContent = text;
        return node;
    }

    function button(className, text, onClick) {
        const node = el("button", className, text);
        node.type = "button";
        node.addEventListener("click", (event) => {
            if (event.isTrusted) onClick();
        });
        return node;
    }

    function ring() {
        const node = el("div", "ring");
        node.setAttribute("aria-hidden", "true");
        const center = el("div", "center");
        node.append(center);
        return { node, center };
    }

    function mount() {
        if (host?.isConnected) return;
        host = dom.create(document, "shoo-warning");
        const root = host.attachShadow({ mode: "closed" });
        const style = el("style");
        style.textContent = CSS;
        ui = el("div", "ui");
        root.append(style, ui);
        release = dom.guard(host, dom.root(document)); // appends it, and puts it back if the page hides it
    }

    function buildSheet() {
        const dim = el("div", "dim");
        dim.addEventListener("click", (event) => {
            if (event.isTrusted) minimize(); // tapping the page = Continue
        });

        const sheet = el("div", "sheet");
        sheet.setAttribute("role", "alertdialog");
        sheet.setAttribute("aria-modal", "true");
        const shoo = button("shoo", null, minimize);
        shoo.setAttribute("aria-label", t("popup_minimize"));
        const logo = el("img");
        logo.src = browser.runtime.getURL("images/icon-96.png");
        logo.alt = "";
        shoo.append(logo);

        const hero = el("div", "hero");
        const meter = ring();
        const caption = el("div", "caption", t("popup_status_2"));
        hero.append(meter.node, caption);

        const body = el("div", "body");
        const copy = el("div", "copy");
        const chip = el("span", "chip");
        const text = el("div", "text");
        const title = el("h2", null, t("popup_title_2"));
        const description = el("p", "rounded");
        text.append(title, description);
        copy.append(chip, text);
        const actions = el("div", "actions");
        actions.append(button("primary", t("popup_leave"), leave), button("secondary", t("popup_continue"), minimize));
        body.append(copy, actions);

        sheet.append(shoo, hero, body);
        sheet.setAttribute("aria-label", title.textContent);
        ui.replaceChildren(dim, sheet);
        return { layout: "sheet", ring: meter.node, value: meter.center, chip, description };
    }

    function buildMini(tier) {
        const mini = el("div", "mini");
        mini.setAttribute("role", "alert");
        const banner = el("div", "banner");
        const meter = ring();
        const lines = el("div", "lines");
        const title = el("div", "title");
        const score = el("span");
        title.append(score, el("span", "dot"), el("span", null, t(`popup_status_${tier}`)));
        const description = el("p", "rounded");
        lines.append(title, description);
        banner.append(meter.node, lines);
        const close = button("close", null, () => {
            memo = dismissed(memo);
            hide();
        });
        close.innerHTML = CLOSE_ICON;
        close.setAttribute("aria-label", t("popup_close"));
        mini.append(banner, close);
        ui.replaceChildren(mini);
        return { layout: "mini", ring: meter.node, value: score, description };
    }

    function render(state, tier, minimized = false) {
        mount();
        last = { state, tier, minimized };
        const layout = layoutFor(tier, minimized);
        refs = layout === "sheet" ? buildSheet() : buildMini(tier);
        update(state);
    }

    function update(state) {
        if (!refs || !last) return;
        last.state = state;
        refs.ring.style.setProperty("--p", String(state.score));
        refs.value.textContent = `${state.score}%`;
        refs.description.textContent = describe(state.signals, { simple, lang, advice: t(`popup_body_${last.tier}`) });
        if (refs.chip) refs.chip.textContent = state.domain || state.url;
    }

    function minimize() {
        if (last && refs?.layout === "sheet") render(last.state, last.tier, true);
    }

    /** Back to where the user came from; a page opened on its own has nothing behind it. */
    function leave() {
        hide();
        if (history.length > 1) history.back();
        else location.replace("about:blank");
    }

    /** EX-07: the screenshot leaves our UI out. Hidden inside the shadow root, so guard() doesn't undo it. */
    globalThis.ShooPopup.capture = (hidden) => {
        if (ui) ui.style.visibility = hidden ? "hidden" : "";
    };

    function hide() {
        release();
        host?.remove();
        host = null;
        ui = null;
        refs = null;
        last = null;
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
