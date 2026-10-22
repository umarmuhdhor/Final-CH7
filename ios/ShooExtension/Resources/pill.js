// Owner: lead. Live score pill (EX-03). Plain content script, loaded after pipeline.js.
// The extension can't drive the Dynamic Island (docs/spikes/dynamic-island.md), so the running
// score floats at the top of the page instead. It lives in the page: it exists only while a page
// is open in Safari and goes away with it.
// Rules: visible while the page is being checked · stays for warnings (30–79) · fades out a few
// seconds after a low final score · hidden when blocked (block screen owns the page, EX-06) ·
// tap hides it for the rest of this page.

(() => {
    const { THRESHOLD } = globalThis.ShooPipeline;
    const LINGER_MS = 3000; // how long a low final score stays before fading out

    /** "safe" < 30 · "warning" 30–49 · "danger" 50–79. Blocked never reaches the pill. */
    function toneFor(score) {
        if (score >= THRESHOLD.secondWarning) return "danger";
        if (score >= THRESHOLD.firstWarning) return "warning";
        return "safe";
    }

    /**
     * Pure decision: what the pill shows for the newest pipeline state. Free of DOM so it can be
     * tested in Node.
     * @returns {{ memo, view: { visible: boolean, score?, tone?, analyzing?, hideAfterMs? } }}
     */
    function decide(memo, state) {
        if (!memo || memo.scanId !== state.scanId) memo = { scanId: state.scanId, dismissed: false };
        if (memo.dismissed || state.status === "blocked") return { memo, view: { visible: false } };

        const view = { visible: true, score: state.score, tone: toneFor(state.score), analyzing: !state.done };
        if (state.done && state.score < THRESHOLD.firstWarning) view.hideAfterMs = LINGER_MS;
        return { memo, view };
    }

    /** The user tapped the pill: it stays hidden until the next page. */
    function dismissed(memo) {
        return memo ? { ...memo, dismissed: true } : memo;
    }

    globalThis.ShooPill = { toneFor, decide, dismissed, LINGER_MS };

    // ---- View (browser only) -------------------------------------------------------------

    if (typeof document === "undefined" || typeof browser === "undefined") return;

    const t = (key, sub) => browser.i18n.getMessage(key, sub) || key;
    const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

    const CSS = `
        :host { all: initial; }
        .pill {
            position: fixed; top: calc(8px + env(safe-area-inset-top, 0px)); left: 50%;
            z-index: 2147483647; box-sizing: border-box; height: 34px; padding: 0 14px 0 10px;
            display: flex; align-items: center; gap: 8px; transform: translateX(-50%);
            border: 0; border-radius: 999px; background: #000; color: #fff; cursor: pointer;
            box-shadow: 0 4px 14px rgba(0,0,0,.3);
            font: 600 15px/1 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
            transition: opacity .3s ease, transform .3s ease;
            -webkit-tap-highlight-color: transparent;
        }
        .pill[data-tone="safe"] { --tone: #30d158; }
        .pill[data-tone="warning"] { --tone: #ffb340; }
        .pill[data-tone="danger"] { --tone: #ff453a; }
        .pill.out { opacity: 0; transform: translate(-50%, -12px); pointer-events: none; }
        .shield { width: 16px; height: 18px; fill: var(--tone); transition: fill .3s ease; }
        .label { color: rgba(255,255,255,.7); font-weight: 500; font-size: 13px; }
        .score { min-width: 3ch; text-align: right; font-variant-numeric: tabular-nums; color: var(--tone); }
        .dot { width: 6px; height: 6px; border-radius: 50%; background: var(--tone); animation: pulse 1s ease-in-out infinite; }
        .pill:not([data-analyzing]) .dot { display: none; }
        @keyframes pulse { 50% { opacity: .25; } }
        @media (prefers-reduced-motion: reduce) { .pill, .shield { transition: none; } .dot { animation: none; } }
    `;

    const SHIELD = '<svg class="shield" viewBox="0 0 16 18" aria-hidden="true"><path d="M8 0 0 3v6c0 4.6 3.4 8.2 8 9 4.6-.8 8-4.4 8-9V3L8 0z"/></svg>';

    let host = null;
    let refs = null;
    let shown = 0; // the number on screen, counts toward the real score
    let tween = null;
    let hideTimer = null;

    function mount() {
        if (host?.isConnected) return;
        host = document.createElement("shoo-live-score");
        const root = host.attachShadow({ mode: "closed" });
        const style = document.createElement("style");
        style.textContent = CSS;

        const pill = document.createElement("button");
        pill.type = "button";
        pill.className = "pill out";
        pill.setAttribute("role", "status");
        pill.setAttribute("aria-live", "polite");
        pill.innerHTML = `${SHIELD}<span class="label"></span><span class="dot"></span><span class="score"></span>`;
        pill.addEventListener("click", () => {
            memo = dismissed(memo);
            hide();
        });
        root.append(style, pill);

        refs = { pill, label: pill.querySelector(".label"), score: pill.querySelector(".score") };
        refs.label.textContent = "Shoo";
        document.documentElement.appendChild(host);
        shown = 0;
        requestAnimationFrame(() => refs?.pill.classList.remove("out"));
    }

    /** Counts the number on screen up (or down) to the new score so each layer visibly moves it. */
    function countTo(target) {
        cancelAnimationFrame(tween);
        const from = shown;
        if (reduceMotion || from === target) return paint(target);
        const start = performance.now();
        const duration = 500;
        const step = (now) => {
            const p = Math.min(1, (now - start) / duration);
            paint(Math.round(from + (target - from) * (1 - (1 - p) ** 3)));
            if (p < 1) tween = requestAnimationFrame(step);
        };
        tween = requestAnimationFrame(step);
    }

    function paint(value) {
        shown = value;
        if (refs) refs.score.textContent = `${value}%`;
    }

    function show(view) {
        clearTimeout(hideTimer);
        mount();
        const { pill } = refs;
        pill.classList.remove("out");
        pill.dataset.tone = view.tone;
        pill.toggleAttribute("data-analyzing", view.analyzing);
        pill.setAttribute(
            "aria-label",
            view.analyzing ? t("pill_checking", [String(view.score)]) : t("pill_score", [String(view.score)]),
        );
        pill.title = t("pill_hide");
        countTo(view.score);
        if (view.hideAfterMs) hideTimer = setTimeout(hide, view.hideAfterMs);
    }

    function hide() {
        clearTimeout(hideTimer);
        cancelAnimationFrame(tween);
        if (!refs) return;
        const gone = host;
        refs.pill.classList.add("out");
        host = null;
        refs = null;
        setTimeout(() => gone.remove(), reduceMotion ? 0 : 300);
    }

    let memo = null;
    globalThis.ShooPipeline.subscribe((state) => {
        const result = decide(memo, state);
        memo = result.memo;
        if (result.view.visible) show(result.view);
        else hide();
    });
})();
