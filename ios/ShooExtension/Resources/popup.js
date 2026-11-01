// Owner: lead. Warning popup at 30% and 50% (EX-04). Plain script, loaded after pipeline.js and gauge.js.
// Rules (PRD §5, 8.5): each popup at most once per page · none if the page goes straight to ≥80%
// (block screen instead, EX-06) · closable · the page stays usable underneath.
// Look (Figma "UI Pop Up Safari"): 30–49% → mini card at the bottom · 50–79% → sheet over a dimmed
// page with the score gauge and Leave / Continue; Continue (or the Shoo button above it) shrinks it to
// the mini card. Protected: "Link sent to <guardian>" once the scan is reported (EX-07).

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

    // Sizes and colours from Figma "UI Pop Up Safari" (frames "Pertama kali buka langsung ke detect",
    // "Safari / Warning Sedang / Minimized"). Gauge and ring drawings: gauge.js.
    const CSS = `
        :host { all: initial; }
        .ui { --ink: #151617; --muted: #6a717e;
              font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; color: var(--ink);
              -webkit-font-smoothing: antialiased; }
        .rounded { font-family: ui-rounded, "SF Pro Rounded", -apple-system, BlinkMacSystemFont, sans-serif; }
        button { -webkit-tap-highlight-color: transparent; }

        .dim { position: fixed; inset: 0; z-index: 2147483646; background: rgba(125,129,135,.5);
               -webkit-backdrop-filter: blur(4px); backdrop-filter: blur(4px); animation: fade .25s ease-out; }
        .sheet { position: fixed; z-index: 2147483647; left: 12px; right: 12px; max-width: 400px; margin: 0 auto;
                 bottom: calc(12px + env(safe-area-inset-bottom, 0px)); box-sizing: border-box;
                 border-radius: 40px; border: 1px solid rgba(255,255,255,.9);
                 background: linear-gradient(180deg, #fff 18.19%, #f1f2f4 99.96%);
                 box-shadow: 0 24px 48px rgba(31,42,55,.18), 0 2px 6px rgba(31,42,55,.06);
                 animation: rise .3s ease-out; }
        .shoo { position: absolute; right: 6px; top: -56px; width: 44px; height: 44px; padding: 0; border: 0;
                border-radius: 50%; overflow: hidden; background: none; cursor: pointer; }
        .shoo img { display: block; width: 44px; height: 44px; }
        .hero { display: flex; flex-direction: column; align-items: center; gap: 16px; padding: 30px 0 22px;
                border-bottom: 1px solid #e1e3e7; }
        .sent { display: flex; align-items: center; gap: 6px; max-width: calc(100% - 44px); box-sizing: border-box;
                padding: 6px 13px 6px 9px; border-radius: 999px; border: 1px solid rgba(171,171,171,.9);
                background: rgba(255,255,255,.7); -webkit-backdrop-filter: blur(7px); backdrop-filter: blur(7px);
                box-shadow: 0 6px 18px rgba(31,42,55,.12); font-size: 15px; white-space: nowrap; }
        .sent[hidden] { display: none; }
        .sent span { overflow: hidden; text-overflow: ellipsis; }
        .sent b { font-weight: 700; }
        .avatar { flex: none; width: 28.97px; height: 28.97px; border-radius: 50%;
                  background: linear-gradient(135deg, #7de49c 0%, #54cae8 71.43%); color: #fff;
                  display: flex; align-items: center; justify-content: center; font-size: 11.85px; font-weight: 600; }
        .gauge { position: relative; flex: none; width: 277.5px; height: 177.75px; overflow: hidden; border-radius: 24px; }
        .gauge svg { position: absolute; left: 0; top: 0; }
        .gauge .value, .gauge .label { position: absolute; left: 0; right: 0; margin: 0; text-align: center; line-height: normal; }
        .gauge .value { top: 87px; font-size: 22.5px; letter-spacing: -.01em; }
        .gauge .label { top: 135px; font-size: 11.25px; font-weight: 500; letter-spacing: -.005em; }
        .body { display: flex; flex-direction: column; gap: 32px; padding: 24px 22px; }
        .copy { display: flex; flex-direction: column; align-items: center; gap: 8px; text-align: center; }
        .chip { max-width: 100%; box-sizing: border-box; padding: 7px 13px; border-radius: 999px; background: #e8eaed;
                box-shadow: inset 0 1px 1px rgba(255,255,255,.9); font-size: 13px; font-weight: 500; line-height: normal;
                overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .text { display: flex; flex-direction: column; gap: 4px; width: 100%; }
        h2 { margin: 0; font-size: 22px; font-weight: 600; line-height: 1.4; letter-spacing: -.01em; }
        .sheet p.rounded { margin: 0; font-size: 15px; line-height: 1.5; color: var(--muted); }
        .actions { display: flex; flex-direction: column; gap: 10px; }
        .primary, .secondary { display: flex; align-items: center; justify-content: center; width: 100%; box-sizing: border-box;
                border-radius: 999px; font: 500 17px/22px -apple-system, BlinkMacSystemFont, sans-serif; cursor: pointer; }
        .primary { height: 52px; border: 1px solid rgba(28,29,32,.6); color: #fff;
                   background: linear-gradient(0deg, #191c25 25%, #3c435a 105.21%);
                   box-shadow: inset 0 1.5px 1px rgba(255,255,255,.22), inset 0 -2px 4px rgba(0,0,0,.25); }
        .secondary { height: 54px; border: 0; color: #191c25; background: #fff; letter-spacing: -.0125em;
                     box-shadow: 0 0 0 1px #e3e3e3, 0 3px 5px -3px rgba(0,0,0,.2); }

        .mini { position: fixed; z-index: 2147483647; left: 16px; right: 16px; max-width: 360px; margin: 0 auto;
                bottom: calc(12px + env(safe-area-inset-bottom, 0px)); padding-top: 11px; animation: rise .25s ease-out; }
        .banner { display: flex; align-items: center; gap: 12px; padding: 14px; border-radius: 24px;
                  border: 1px solid rgba(255,255,255,.9); background: rgba(255,255,255,.92);
                  -webkit-backdrop-filter: blur(7px); backdrop-filter: blur(7px);
                  box-shadow: 0 12px 28px rgba(31,42,55,.14), 0 1px 3px rgba(31,42,55,.05); }
        .ring { position: relative; flex: none; width: 72px; height: 72px; }
        .ring svg { position: absolute; left: -6.97px; top: -4.65px; }
        .lines { display: flex; flex-direction: column; gap: 4px; min-width: 0; padding-right: 8px; }
        .title { display: flex; align-items: center; gap: 8px; font-size: 17px; font-weight: 600;
                 line-height: 1.4; letter-spacing: -.01em; }
        .dot { flex: none; width: 4px; height: 4px; border-radius: 50%; background: #c7c7ce; }
        .mini p { margin: 0; font-size: 13px; line-height: 1.4; color: var(--muted); }
        .close { position: absolute; right: 0; top: 0; width: 28px; height: 28px; padding: 0; border-radius: 50%;
                 box-sizing: border-box; border: 1px solid #f9f9fa; background: #e8eaed; cursor: pointer;
                 display: flex; align-items: center; justify-content: center; }
        .close svg { width: 12px; height: 12px; fill: none; stroke: #6a717e; stroke-width: 1.1;
                     stroke-linecap: round; stroke-linejoin: round; }

        @keyframes rise { from { transform: translateY(24px); opacity: 0; } }
        @keyframes fade { from { opacity: 0; } }
        @media (prefers-reduced-motion: reduce) { .dim, .sheet, .mini { animation: none; } }
    `;

    // Figma "icon/close" (12 × 12).
    const CLOSE_ICON = '<svg viewBox="0 0 12 12" aria-hidden="true"><path d="M3 3L6 6M6 6L9 9M6 6L9 3M6 6L3 9"/></svg>';
    const LEVEL = { 1: "sedang", 2: "tinggi" }; // gauge.js colour set per tier

    const dom = globalThis.ShooDom; // the page can shadow document properties and hide our host (dom.js)
    const { gauge: drawGauge, ring: drawRing } = globalThis.ShooGauge;
    let host = null;
    let release = () => {}; // stops guarding host
    let ui = null; // the shadow root's wrapper
    let refs = null; // the visible layout's nodes
    let simple = false; // Protected → plain reason wording
    let guardianName = null; // Protected only: who gets the link (EX-07 push)
    let last = null; // newest { state, tier, minimized }

    browser.runtime
        .sendMessage({ type: "profile" })
        .then((p) => {
            simple = Boolean(p?.onboarded && p.mode === "protected");
            guardianName = simple ? p.guardianName || null : null;
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

    /** "Link terkirim ke **Virellia**": the scan went to the guardian (EX-07). Hidden until it has. */
    function sentPill() {
        const pill = el("div", "sent");
        pill.hidden = true;
        const avatar = el("span", "avatar");
        avatar.setAttribute("aria-hidden", "true");
        const text = el("span");
        pill.append(avatar, text);
        return { pill, avatar, text };
    }

    function fillSent(sent, state) {
        const show = Boolean(guardianName && state.recordId);
        sent.pill.hidden = !show;
        if (!show) return;
        sent.avatar.textContent = Array.from(guardianName)[0].toUpperCase();
        const [before = "", after = ""] = t("popup_sent_to", ["\u0000"]).split("\u0000");
        sent.text.replaceChildren(before, el("b", null, guardianName), after);
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

    function buildSheet(tier) {
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
        const sent = sentPill();
        const meter = el("div", "gauge");
        const value = el("p", "value");
        meter.append(el("div"), value, el("p", "label", t(`popup_status_${tier}`)));
        hero.append(sent.pill, meter);

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
        return { layout: "sheet", art: meter.firstChild, draw: drawGauge, value, chip, description, sent };
    }

    function buildMini(tier) {
        const mini = el("div", "mini");
        mini.setAttribute("role", "alert");
        const banner = el("div", "banner");
        const meter = el("div", "ring");
        meter.setAttribute("aria-hidden", "true");
        const lines = el("div", "lines");
        const title = el("div", "title");
        const score = el("span");
        title.append(score, el("span", "dot"), el("span", null, t(`popup_status_${tier}`)));
        const description = el("p", "rounded");
        lines.append(title, description);
        banner.append(meter, lines);
        const close = button("close", null, () => {
            memo = dismissed(memo);
            hide();
        });
        close.innerHTML = CLOSE_ICON;
        close.setAttribute("aria-label", t("popup_close"));
        mini.append(banner, close);
        ui.replaceChildren(mini);
        return { layout: "mini", art: meter, draw: drawRing, value: score, description };
    }

    function render(state, tier, minimized = false) {
        mount();
        last = { state, tier, minimized };
        const layout = layoutFor(tier, minimized);
        refs = layout === "sheet" ? buildSheet(tier) : buildMini(tier);
        update(state);
    }

    function update(state) {
        if (!refs || !last) return;
        last.state = state;
        refs.art.innerHTML = refs.draw(state.score, LEVEL[last.tier]); // our own markup from numbers only
        refs.value.textContent = `${state.score}%`;
        refs.description.textContent = describe(state.signals, { simple, lang, advice: t(`popup_body_${last.tier}`) });
        if (refs.chip) refs.chip.textContent = state.domain || state.url;
        if (refs.sent) fillSent(refs.sent, state);
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
